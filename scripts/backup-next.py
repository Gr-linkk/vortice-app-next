#!/usr/bin/env python3
"""Stage a local Next DB/Storage export with checksums, never restore remotely.

This is plaintext staging in ignored outputs. A complete receipt is not proof of
an atomic cross-service snapshot, encryption, off-device retention or recovery.
"""
import hashlib
import json
import subprocess
import re
import shlex
import uuid
from datetime import datetime, timezone
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.parse import quote
from next_environment import ROOT, REF, assert_environment, checked, query_file


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def assert_dump_target(script):
    fields = {}
    for name in ('PGHOST', 'PGUSER'):
        match = re.search(r'^export ' + name + r'=(.+)$', script, re.MULTILINE)
        if match:
            values = shlex.split(match.group(1))
            if len(values) == 1:
                fields[name] = values[0]
    host, user = fields.get('PGHOST', ''), fields.get('PGUSER', '')
    if host == f'db.{REF}.supabase.co':
        return
    if re.fullmatch(r'[a-z0-9.-]+\.pooler\.supabase\.com', host) and re.fullmatch(r'[A-Za-z0-9_]+\.' + REF, user):
        return
    raise RuntimeError('Dump script does not target the authorized Next database')


def dump_database(target, flags):
    # Use the installed CLI's vendor dump/filter script with the same PG major
    # version as Next. An existing image avoids an implicit large image download.
    # Credentials travel on stdin, never in argv, a saved script or diagnostics.
    if not (ROOT / 'supabase/.temp/postgres-version').read_text().strip().startswith('17.'):
        raise RuntimeError('Review dump client compatibility for this Postgres version')
    checked(['docker', 'image', 'inspect', 'postgres:17'])
    script = checked(['supabase', 'db', 'dump', '--linked', *flags, '--dry-run'])
    assert_dump_target(script)
    container = 'vortice-next-export-' + uuid.uuid4().hex
    try:
        with target.open('w') as output:
            result = subprocess.run(
                ['docker', 'run', '--rm', '--name', container, '-i', '--env', 'PGCONNECT_TIMEOUT=15',
                 'postgres:17', 'bash', '-s'], cwd=ROOT, input=script, text=True,
                stdout=output, stderr=subprocess.PIPE, timeout=180,
            )
    except subprocess.TimeoutExpired:
        # Only the unique read-only export container created by this invocation.
        subprocess.run(['docker', 'rm', '-f', container], capture_output=True,
                       stdin=subprocess.DEVNULL, timeout=20)
        raise
    if result.returncode:
        raise RuntimeError('Database dump failed; no raw connection details logged')


def storage_downloader():
    # The same service authorization the CLI uses for private Storage downloads,
    # fetched once in memory rather than once per object. Never persist the key.
    response = json.loads(checked(['supabase', 'projects', 'api-keys', '--project-ref', REF, '--output', 'json']))
    rows = response if isinstance(response, list) else response.get('api_keys', [])
    candidates = [row.get('api_key') for row in rows if row.get('name') == 'service_role']
    if len(candidates) != 1 or not candidates[0]:
        raise RuntimeError('A unique Next Storage service credential is unavailable')
    key = candidates[0]

    class NoRedirect(HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            raise RuntimeError('Private Storage download redirect refused')

    def download(item, target):
        url = f'https://{REF}.supabase.co/storage/v1/object/authenticated/' + \
            quote(item['bucket_id'], safe='') + '/' + quote(item['name'], safe='/')
        request = Request(url, headers={'Authorization': 'Bearer ' + key, 'apikey': key})
        with build_opener(NoRedirect()).open(request, timeout=60) as source, target.open('wb') as output:
            for chunk in iter(lambda: source.read(1024 * 1024), b''):
                output.write(chunk)
    return download


def copy_object(item, output, download):
    remote = f"{item['bucket_id']}/{item['name']}"
    local = 'objects/' + hashlib.sha256(remote.encode()).hexdigest()
    target = output / local
    download(item, target)
    if not target.is_file():
        raise RuntimeError('A storage export is missing')
    expected_size = (item.get('metadata') or {}).get('size')
    if expected_size is not None and target.stat().st_size != int(expected_size):
        raise RuntimeError('Storage export length differs from its inventory')
    return {**item, 'file': local, 'bytes': target.stat().st_size, 'sha256': digest(target)}


def main():
    assert_environment()
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    output = ROOT / 'outputs/backups' / stamp
    output.mkdir(parents=True, mode=0o700)
    (output / 'objects').mkdir()
    receipt = {'project_ref': REF, 'started_at': stamp, 'complete': False,
               'plaintext_staging': True, 'database': [], 'objects': [],
               'limits': 'Not an atomic cross-service snapshot or an accepted hosted restore.'}
    manifest = output / 'manifest.json'

    def save():
        manifest.write_text(json.dumps(receipt, indent=2) + '\n')

    save()
    try:
        receipt['phase'] = 'storage_inventory'
        save()
        inventory_sql = output / 'inventory.sql'
        inventory_sql.write_text("begin read only; select id,bucket_id,name,updated_at,metadata "
                                 "from storage.objects order by bucket_id,name; commit;\n")
        objects = query_file(inventory_sql)
        receipt['source_object_count'] = len(objects)
        buckets_sql = output / 'buckets.sql'
        buckets_sql.write_text('begin read only; select id,name,public,file_size_limit,allowed_mime_types '
                               'from storage.buckets order by id; commit;\n')
        receipt['buckets'] = query_file(buckets_sql)
        for filename, flags in [
            ('roles.sql', ['--role-only']),
            ('schema.sql', []),
            ('data.sql', ['--data-only', '--use-copy']),
            ('history-schema.sql', ['--schema', 'supabase_migrations']),
            ('history-data.sql', ['--schema', 'supabase_migrations', '--data-only', '--use-copy']),
        ]:
            receipt['phase'] = filename
            save()
            target = output / filename
            dump_database(target, flags)
            if not target.is_file() or target.stat().st_size == 0:
                raise RuntimeError('Database export is missing or empty')
            receipt['database'].append({'file': filename, 'bytes': target.stat().st_size, 'sha256': digest(target)})
            save()
        # The managed schemas are supplied by Supabase on restore. Snapshot the
        # custom access rules through the supported read-only catalog API; a full
        # managed-schema pg_dump may require provider-owned relation privileges.
        access_query = output / 'managed-access-query.sql'
        access_query.write_text("begin read only; select jsonb_build_object("
            "'policies',(select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) from pg_policies p "
            "where schemaname in ('auth','storage')),"
            "'public_function_triggers',(select coalesce(jsonb_agg(pg_get_triggerdef(t.oid)),'[]'::jsonb) "
            "from pg_trigger t join pg_class c on c.oid=t.tgrelid "
            "join pg_namespace n on n.oid=c.relnamespace join pg_proc p on p.oid=t.tgfoid "
            "join pg_namespace f on f.oid=p.pronamespace where n.nspname in ('auth','storage') "
            "and f.nspname='public' and not t.tgisinternal)) as access; commit;\n")
        target = output / 'managed-access.json'
        target.write_text(json.dumps(query_file(access_query), indent=2) + '\n')
        receipt['database'].append({'file': target.name, 'bytes': target.stat().st_size, 'sha256': digest(target)})
        save()
        receipt['phase'] = 'storage_files'
        save()

        download = storage_downloader() if objects else None
        executor = ThreadPoolExecutor(max_workers=4)
        try:
            futures = [executor.submit(copy_object, item, output, download) for item in objects]
            for future in as_completed(futures):
                receipt['objects'].append(future.result())
                save()
        finally:
            executor.shutdown(wait=True, cancel_futures=True)
        receipt['objects'].sort(key=lambda item: (item['bucket_id'], item['name']))
        if query_file(inventory_sql) != objects or query_file(buckets_sql) != receipt['buckets']:
            raise RuntimeError('Storage changed during export; repeat during a quiet window')
        receipt['complete'] = True
        receipt['phase'] = 'complete'
        receipt['finished_at'] = datetime.now(timezone.utc).isoformat()
        save()
        print(json.dumps({'complete': True, 'objects': len(objects), 'manifest': str(manifest)}))
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        # Leave incomplete files and receipt for diagnosis. Never advertise a
        # partial export as recovery-ready, and never relay CLI secrets.
        receipt['failure'] = str(error) if isinstance(error, RuntimeError) else (
            'Export timed out; no complete recovery bundle.' if isinstance(error, subprocess.TimeoutExpired)
            else 'Export incomplete; verify CLI access and retry into a fresh directory.')
        save()
        print(json.dumps({'complete': False, 'manifest': str(manifest), 'failure': receipt['failure']}))
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
