"""Guard and isolate public browser defines; create an offline static app shell."""
import base64
import hashlib
import json
import re
import sys
from pathlib import Path

PROJECT = 'https://hkjpojobdbbtjkhaudki.supabase.co'
ASSETS = {
    'drift_worker.js': 'f0a9b87085f732fd7b6ee7eb34d3858c556f05d221eb1febfc443649cd365752',
    'sqlite3.wasm': '922a76b182b6af69b030c8e2fdd3283ecc8e827248b20e4b1f3f3db170b52117',
}

def public_config(source):
    if source.get('SUPABASE_URL') != PROJECT:
        raise ValueError('Unauthorized Supabase target')
    key = source.get('SUPABASE_ANON_KEY', '').strip()
    if key.startswith('eyJ'):
        payload = key.split('.')[1]
        claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        if claims.get('role') != 'anon' or claims.get('ref') != 'hkjpojobdbbtjkhaudki':
            raise ValueError('Only the independent public client key may enter a browser build')
    elif not key.startswith('sb_publishable_') or len(key) < 30:
        raise ValueError('Missing public client key')
    return {'SUPABASE_URL': PROJECT, 'SUPABASE_ANON_KEY': key}

def prepare(config_path, output):
    for name, digest in ASSETS.items():
        if hashlib.sha256((Path('web') / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f'Browser storage asset mismatch: {name}')
    clean = public_config(json.loads(Path(config_path).read_text(encoding='utf-8-sig')))
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(clean))
    output.chmod(0o600)

def finish(directory):
    root = Path(directory)
    files = sorted(p for p in root.rglob('*') if p.is_file())
    # Generated compiler metadata is not part of the runnable public artifact.
    for path in files:
        if path.name.endswith(('.map', '.deps')):
            path.unlink()
    files = sorted(p for p in root.rglob('*') if p.is_file())
    revision = hashlib.sha256(b''.join(hashlib.sha256(p.read_bytes()).digest() for p in files)).hexdigest()[:20]
    urls = [p.relative_to(root).as_posix() for p in files]
    worker = '''const CACHE = %s;
const FILES = %s;
const URLS = new Set(FILES.map(p => new URL(p, self.registration.scope).href));
self.addEventListener('install', event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(FILES))));
// Activate only when old tabs close, so an update never interrupts an unsent form.
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const key of await caches.keys()) if (key.startsWith('vortice-shell-') && key !== CACHE) await caches.delete(key);
  await self.clients.claim();
})()));
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin || url.search) return;
  if (event.request.mode === 'navigate') {
    event.respondWith(caches.open(CACHE).then(async c => (await c.match('index.html')) || fetch(event.request)));
  } else if (URLS.has(url.href)) {
    event.respondWith(caches.open(CACHE).then(async c => (await c.match(event.request)) || fetch(event.request)));
  }
});
''' % (json.dumps('vortice-shell-' + revision), json.dumps(urls))
    (root / 'workspace-worker.js').write_text(worker)
    (root / 'build-receipt.json').write_text(json.dumps({'revision': revision, 'public_defines': ['SUPABASE_URL','SUPABASE_ANON_KEY'], 'static_files': len(files)}, indent=2)+'\n')

if __name__ == '__main__':
    if sys.argv[1] == 'prepare': prepare(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'finish': finish(sys.argv[2])
    else: raise ValueError('Unknown command')
