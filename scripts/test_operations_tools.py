"""Offline checks for backup receipts and failure handling; never use credentials."""
import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
import subprocess
from pathlib import Path
from unittest.mock import patch
from verify_backup import verify
import next_environment

SPEC = importlib.util.spec_from_file_location('backup_next', Path(__file__).with_name('backup-next.py'))
backup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backup)


class BackupTests(unittest.TestCase):
    def exercise(self, *, missing=False, changed=False, corrupt=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        item = {'id': 'fixture', 'bucket_id': 'private', 'name': '../../outside.txt',
                'updated_at': 'fixture-time', 'metadata': {'size': 8}}
        calls = 0

        def query(file):
            nonlocal calls
            if file.name == 'managed-access-query.sql':
                return [{'access': {'policies': [], 'public_function_triggers': []}}]
            if file.name == 'buckets.sql':
                return [{'id': 'private', 'public': False}]
            calls += 1
            return [] if changed and calls > 1 else [item]

        def download(item, target):
            if not missing:
                target.write_bytes(b'bad' if corrupt else b'evidence')

        with patch.object(backup, 'ROOT', root), patch.object(backup, 'assert_environment'), \
             patch.object(backup, 'query_file', side_effect=query), \
             patch.object(backup, 'dump_database', side_effect=lambda path, flags: path.write_text('-- fixture SQL\n')), \
             patch.object(backup, 'storage_downloader', return_value=download), contextlib.redirect_stdout(io.StringIO()):
            status = backup.main()
        manifest = next(root.glob('outputs/backups/*/manifest.json'))
        return root, manifest, json.loads(manifest.read_text()), status

    def test_complete_receipt_preserves_private_mapping_and_hashes(self):
        root, manifest, receipt, status = self.exercise()
        self.assertEqual(status, 0)
        self.assertTrue(receipt['complete'])
        self.assertEqual(len(receipt['database']), 6)
        item = receipt['objects'][0]
        self.assertEqual(item['name'], '../../outside.txt')
        target = manifest.parent / item['file']
        self.assertTrue(target.resolve().is_relative_to(manifest.parent.resolve()))
        self.assertEqual(item['sha256'], backup.digest(target))
        self.assertFalse((root / 'outside.txt').exists())
        self.assertEqual(verify(manifest)['verified_files'], 7)
        target.write_bytes(b'tampered')
        with self.assertRaises(ValueError):
            verify(manifest)

    def test_missing_download_cannot_produce_complete_receipt(self):
        _, manifest, receipt, status = self.exercise(missing=True)
        self.assertEqual(status, 1)
        self.assertFalse(receipt['complete'])
        with self.assertRaises(ValueError):
            verify(manifest)

    def test_changed_inventory_cannot_produce_complete_receipt(self):
        _, _, receipt, status = self.exercise(changed=True)
        self.assertEqual(status, 1)
        self.assertFalse(receipt['complete'])

    def test_wrong_download_length_cannot_produce_complete_receipt(self):
        _, _, receipt, status = self.exercise(corrupt=True)
        self.assertEqual(status, 1)
        self.assertFalse(receipt['complete'])

    def test_dump_target_must_be_next_even_with_authorized_cli_link(self):
        backup.assert_dump_target('export PGHOST="db.hkjpojobdbbtjkhaudki.supabase.co"\nexport PGUSER="postgres"')
        backup.assert_dump_target('export PGHOST="aws-0-ca-central-1.pooler.supabase.com"\nexport PGUSER="postgres.hkjpojobdbbtjkhaudki"')
        backup.assert_dump_target('export PGHOST="aws-0-ca-central-1.pooler.supabase.com"\nexport PGUSER="cli_login_postgres.hkjpojobdbbtjkhaudki"')
        for script in ['', 'export PGHOST="unrelated.invalid"',
                       'export PGHOST="aws-0-ca-central-1.pooler.supabase.com"\nexport PGUSER="postgres.unrelated"']:
            with self.assertRaises(RuntimeError):
                backup.assert_dump_target(script)

    def test_local_dump_rejects_wrong_client_before_getting_credentials(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'supabase/.temp').mkdir(parents=True)
            (root / 'supabase/.temp/postgres-version').write_text('17.6.1')
            (root / 'pg_dump').touch()
            with patch.object(backup, 'ROOT', root), \
                 patch.dict(backup.os.environ, {'VORTICE_BACKUP_DATABASE_BACKEND': 'local', 'VORTICE_PG_BIN': str(root)}), \
                 patch.object(backup, 'checked', return_value='pg_dump (PostgreSQL) 18.6\n') as checked:
                with self.assertRaisesRegex(RuntimeError, 'PostgreSQL 17'):
                    backup.dump_database(root / 'dump.sql', [])
                self.assertEqual(checked.call_count, 1)

    def test_local_dump_keeps_credentials_on_stdin(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'supabase/.temp').mkdir(parents=True)
            (root / 'supabase/.temp/postgres-version').write_text('17.6.1')
            (root / 'pg_dump').touch()
            script = 'export PGHOST="db.hkjpojobdbbtjkhaudki.supabase.co"\nexport PGUSER="postgres"\nexport PGPASSWORD="test-secret"\npg_dump'
            with patch.object(backup, 'ROOT', root), \
                 patch.dict(backup.os.environ, {'VORTICE_BACKUP_DATABASE_BACKEND': 'local', 'VORTICE_PG_BIN': str(root)}), \
                 patch.object(backup, 'checked', side_effect=['pg_dump (PostgreSQL) 17.11\n', script]), \
                 patch.object(backup.subprocess, 'Popen') as popen:
                process = popen.return_value.__enter__.return_value
                process.returncode = 0
                backup.dump_database(root / 'dump.sql', [])
                self.assertEqual(popen.call_args.args[0], ['bash', '-s'])
                self.assertNotIn('test-secret', str(popen.call_args))
                process.communicate.assert_called_once_with(script, timeout=180)

    def test_private_download_stays_on_next_and_refuses_redirects(self):
        with tempfile.TemporaryDirectory() as temp, \
             patch.object(backup, 'checked', return_value=json.dumps([{'name': 'service_role', 'api_key': 'fixture'}])), \
             patch.object(backup, 'build_opener') as opener:
            opener.return_value.open.return_value.__enter__.return_value = io.BytesIO(b'evidence')
            target = Path(temp) / 'download'
            backup.storage_downloader()({'bucket_id': 'private', 'name': 'file #1.png'}, target)
            self.assertEqual(target.read_bytes(), b'evidence')
            request = opener.return_value.open.call_args.args[0]
            self.assertEqual(request.full_url, 'https://hkjpojobdbbtjkhaudki.supabase.co/storage/v1/object/authenticated/private/file%20%231.png')
            handler = opener.call_args.args[0]
            with self.assertRaises(RuntimeError):
                handler.redirect_request(None, None, 302, 'Found', {}, 'https://example.invalid')

    def test_missing_storage_service_authorization_fails_closed(self):
        with patch.object(backup, 'checked', return_value='[]'), self.assertRaises(RuntimeError):
            backup.storage_downloader()


class EnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.git('init', '-q')
        self.git('remote', 'add', 'origin', 'https://github.com/Gr-linkk/vortice-app-next.git')
        link = self.root / 'supabase/.temp/project-ref'
        link.parent.mkdir(parents=True)
        link.write_text('hkjpojobdbbtjkhaudki')
        self.patch = patch.object(next_environment, 'ROOT', self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def git(self, *args):
        subprocess.run(['git', *args], cwd=self.root, check=True, capture_output=True)

    def test_expected_environment_passes_without_network(self):
        next_environment.assert_environment()

    def test_extra_push_destination_is_rejected_before_network(self):
        self.git('remote', 'set-url', '--add', '--push', 'origin', 'https://github.com/Gr-linkk/vortice-app-next.git')
        self.git('remote', 'set-url', '--add', '--push', 'origin', 'https://example.invalid/unrelated.git')
        with self.assertRaises(RuntimeError):
            next_environment.assert_environment()

    def test_wrong_link_is_rejected_before_network(self):
        (self.root / 'supabase/.temp/project-ref').write_text('unrelated')
        with self.assertRaises(RuntimeError):
            next_environment.assert_environment()


if __name__ == '__main__':
    unittest.main()
