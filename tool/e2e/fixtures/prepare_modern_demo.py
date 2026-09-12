"""Prepare additive SQL; activate private debug credentials after verified deploy.

Run from the independent Next root. This script never deploys SQL, sends email,
or changes remote accounts. Activation only signs in to verify the new identities.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import urllib.error
import urllib.request
import uuid

EXPECTED_URL = 'https://hkjpojobdbbtjkhaudki.supabase.co'
EXPECTED_REMOTE = 'https://github.com/Gr-linkk/vortice-app-next'
PERSONAS = ('owner', 'supervisor', 'mechanic', 'operator', 'service_owner')


def hash_password(password):
    try:
        import bcrypt
        return bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=10)).decode()
    except ImportError:
        try:
            import crypt
            if crypt.METHOD_BLOWFISH not in crypt.methods:
                raise RuntimeError('bcrypt support is required')
            return crypt.crypt(password, crypt.mksalt(crypt.METHOD_BLOWFISH))
        except ImportError as error:
            raise RuntimeError('Run with Python bcrypt or Linux Python supporting crypt Blowfish') from error


def private_json(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')
    os.chmod(path, 0o600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'activate'))
    parser.add_argument('--config', default='config/vortice-next.local.json')
    args = parser.parse_args()
    root = Path.cwd().resolve()
    git_root = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip()
    remotes = subprocess.check_output(['git', 'remote'], text=True).split()
    remote = subprocess.check_output(['git', 'remote', 'get-url', 'origin'], text=True).strip().removesuffix('.git')
    if Path(git_root).resolve() != root or remotes != ['origin'] or remote != EXPECTED_REMOTE:
        raise SystemExit('Run only from the verified independent Next root')
    config_path = Path(args.config).resolve()
    if config_path.parent != root / 'config' or not config_path.name.endswith('.local.json'):
        raise SystemExit('Use an ignored config/*.local.json file in this Next clone')
    config = json.loads(config_path.read_text(encoding='utf-8-sig'))
    if config.get('SUPABASE_URL') != EXPECTED_URL:
        raise SystemExit('Unauthorized backend in config')
    work = root / 'work' / 'modern-demo-private'
    work.mkdir(parents=True, exist_ok=True)
    pending = work / 'credentials.pending.local.json'
    if args.action == 'prepare':
        if pending.exists() or (work / 'apply.sql').exists():
            raise SystemExit('Prepared fixture exists; reuse it, never rotate credentials implicitly')
        accounts = []
        for index, role in enumerate(PERSONAS, start=1):
            email = f'demo_fleet_{role}@vortice.dev' if role != 'service_owner' else 'demo_service_owner@vortice.dev'
            password = secrets.token_urlsafe(30)
            accounts.append({'id': f'd0210000-0000-4000-8000-{index:012}', 'email': email, 'password': password})
        rows = ',\n'.join("('%s','%s','%s')" % (a['id'], a['email'], hash_password(a['password'])) for a in accounts)
        sql = Path(__file__).with_name('modern_demo.sql').read_text(encoding='utf-8').replace('__AUTH_ROWS__', rows)
        private_json(pending, {'backend': EXPECTED_URL, 'accounts': accounts})
        with (work / 'apply.sql').open('x', encoding='utf-8') as stream:
            stream.write(sql)
        os.chmod(work / 'apply.sql', 0o600)
        print('Prepared additive apply.sql and private pending credentials. No remote changes or config activation.')
        return
    saved = json.loads(pending.read_text(encoding='utf-8'))
    if saved.get('backend') != EXPECTED_URL or len(saved.get('accounts', [])) != 5:
        raise SystemExit('Unexpected pending fixture')
    for account in saved['accounts']:
        request = urllib.request.Request(EXPECTED_URL + '/auth/v1/token?grant_type=password',
            data=json.dumps({'email': account['email'], 'password': account['password']}).encode(),
            headers={'apikey': config['SUPABASE_ANON_KEY'], 'Content-Type': 'application/json'}, method='POST')
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                session = json.load(response)
        except (urllib.error.URLError, ValueError):
            raise SystemExit('Fixture sign-in not verified; config unchanged') from None
        if session.get('user', {}).get('id') != account['id']:
            raise SystemExit('Unexpected identity; config unchanged')
    passwords = json.loads(config.get('DEV_LOGIN_PASSWORDS', '{}'))
    passwords.update({a['email']: a['password'] for a in saved['accounts']})
    config['DEV_LOGIN_PASSWORDS'] = json.dumps(passwords, separators=(',', ':'))
    temporary = config_path.with_name(config_path.name + '.' + uuid.uuid4().hex + '.local.json')
    private_json(temporary, config)
    os.replace(temporary, config_path)
    print('Verified all five demo identities and added their passwords to ignored local debug config.')


if __name__ == '__main__':
    main()
