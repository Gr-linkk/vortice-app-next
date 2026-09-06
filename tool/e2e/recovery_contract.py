"""Exercise Next recovery with a disposable account; never send email or log tokens."""
import json
import secrets
import subprocess
import urllib.error
import urllib.request
import uuid
from pathlib import Path

root = Path.cwd()
project = 'hkjpojobdbbtjkhaudki'
assert (root / 'supabase/.temp/project-ref').read_text().strip() == project
def cli(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout
assert cli('git', 'remote', 'get-url', 'origin').strip() == 'https://github.com/Gr-linkk/vortice-app-next.git'
keys = json.loads(cli('supabase', 'projects', 'api-keys', '--project-ref', project, '--output', 'json'))
admin = next(k['api_key'] for k in keys if k['name'] == 'service_role')
anon = next(k['api_key'] for k in keys if k['name'] == 'anon')
base = f'https://{project}.supabase.co/auth/v1/'

def request(path, data=None, token=None, method='POST'):
    key = token or admin
    req = urllib.request.Request(base + path, method=method,
        data=json.dumps(data).encode() if data is not None else None,
        headers={'apikey': anon, 'Authorization': 'Bearer ' + key,
                 'Content-Type': 'application/json', 'User-Agent': 'Next-Recovery-Test/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, {}  # No provider payloads or recovery secrets in logs.

email = f'e2e-011-{uuid.uuid4()}@example.invalid'
old_password, new_password = secrets.token_urlsafe(24), secrets.token_urlsafe(24)
account = None
try:
    status, user = request('admin/users', {'email': email, 'password': old_password, 'email_confirm': True})
    assert status == 200, 'Synthetic user creation failed'
    account = user['id']
    status, link = request('admin/generate_link', {'type': 'recovery', 'email': email,
        'redirect_to': 'com.vortice.next://auth/recovery'})
    assert status == 200, 'Recovery link generation failed'
    hashed_token = link['hashed_token']
    status, session = request('verify', {'type': 'recovery', 'token_hash': hashed_token}, token=anon)
    assert status == 200 and session['user']['id'] == account
    status, _ = request('user', {'password': new_password}, token=session['access_token'], method='PUT')
    assert status == 200, 'Password update failed'
    status, _ = request('verify', {'type': 'recovery', 'token_hash': hashed_token}, token=anon)
    assert status >= 400, 'Used recovery link accepted'
    status, _ = request('token?grant_type=password', {'email': email, 'password': old_password}, token=anon)
    assert status >= 400, 'Old password still accepted'
    status, signed_in = request('token?grant_type=password', {'email': email, 'password': new_password}, token=anon)
    assert status == 200 and signed_in['user']['id'] == account
    print('PASS Next recovery exchange, password change, one-use link, old/new password checks')
finally:
    if account:
        status, _ = request('admin/users/' + account, method='DELETE')
        assert status == 200, 'Synthetic auth fixture cleanup failed'
        print('PASS synthetic recovery account removed')
