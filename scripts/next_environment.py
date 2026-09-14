"""Shared guards for read-only operational tooling. No secret values in errors."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = 'hkjpojobdbbtjkhaudki'


def checked(command, timeout=180):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                            stdin=subprocess.DEVNULL, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'{command[0]} command failed; check local authentication/tool setup.')
    return result.stdout


def assert_environment():
    if Path(checked(['git', 'rev-parse', '--show-toplevel']).strip()).resolve() != ROOT:
        raise RuntimeError('Wrong repository root')
    if checked(['git', 'remote']).split() != ['origin']:
        raise RuntimeError('Unexpected remotes')
    for direction in ([], ['--push']):
        urls = checked(['git', 'remote', 'get-url', *direction, '--all', 'origin']).splitlines()
        if not urls or any(u.rstrip('/').removesuffix('.git').lower() !=
                           'https://github.com/gr-linkk/vortice-app-next' for u in urls):
            raise RuntimeError('Unexpected repository target')
    if (ROOT / 'supabase/.temp/project-ref').read_text().strip() != REF:
        raise RuntimeError('Wrong linked project')


def query_file(file):
    response = json.loads(checked(['supabase', 'db', 'query', '--linked',
                                  '--file', str(file), '--output', 'json']))
    rows = response if isinstance(response, list) else response.get('rows', response.get('result'))
    if not isinstance(rows, list):
        raise RuntimeError('Unexpected query response')
    return rows
