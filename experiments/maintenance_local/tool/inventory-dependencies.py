#!/usr/bin/env python3
"""Record installed, locked package license evidence without choosing our license."""
import hashlib,json,os,re,shutil,tomllib
from pathlib import Path
from collections import Counter
from urllib.parse import urlparse,unquote
lab=Path(__file__).resolve().parents[1]
out=lab/'dependencies'; (out/'licenses').mkdir(parents=True,exist_ok=True)
rows=[]
active_notices=set()
for p in json.loads((lab/'.dart_tool/package_config.json').read_text())['packages']:
 uri=p['rootUri']; parsed=urlparse(uri)
 root=Path(unquote(parsed.path)) if parsed.scheme=='file' else (lab/'.dart_tool'/uri).resolve()
 if root.is_relative_to(lab): continue
 manifest=(root/'pubspec.yaml').read_text()
 m=re.search(r'^version:\s*[\'"]?([^\s\'"#]+)',manifest,re.M)
 files=[root/x for x in ['LICENSE','LICENSE.md','LICENSE.txt','COPYING'] if (root/x).is_file()]
 if not files:
  files=[parent/'LICENSE' for parent in root.parents if (parent/'bin/flutter').is_file() and (parent/'LICENSE').is_file()]
 if not files: raise RuntimeError('Missing license: '+p['name'])
 dest=out/'licenses'/(p['name']+'.txt');shutil.copyfile(files[0],dest)
 active_notices.add(dest)
 rows.append({'name':p['name'],'version':m.group(1) if m else 'Flutter SDK 3.44.0',
              'licenseFile':str(dest.relative_to(out)), 'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()})
(out/'dart-licenses.json').write_text(json.dumps(rows,indent=2)+'\n')
cargo=Path(os.environ.get('CARGO_HOME',str(Path.home()/'.cargo')))/'registry/src'
rows=[]
upstream=json.loads((out/'upstream/sources.json').read_text())
packages=tomllib.loads((lab/'rust/Cargo.lock').read_text())['package']
counts=Counter(p['name'] for p in packages if 'source' in p)
for p in packages:
 if 'source' not in p: continue
 # A lock can contain multiple versions with different copyright/notice text.
 notice_id=p['name']+('-'+p['version'] if counts[p['name']]>1 else '')
 matches=list(cargo.glob('*/'+p['name']+'-'+p['version']+'/Cargo.toml'))
 if not matches: raise RuntimeError('Fetch locked Rust package first: '+p['name'])
 manifest=tomllib.loads(matches[0].read_text())['package']
 row={'name':p['name'],'version':p['version'],'license':manifest.get('license'), 'checksum':p.get('checksum')}
 f=manifest.get('license-file')
 root=matches[0].parent
 files=sorted(x for x in root.rglob('*') if x.is_file() and x.name.upper().startswith(('LICENSE','LICENCE','COPYING','NOTICE')))
 if f and (root/f).is_file(): files=sorted(set(files+[root/f]))
 captured=[]
 for source in files:
  dest=out/'licenses'/('rust-'+notice_id+'-'+str(source.relative_to(root)).replace('/','__')+'.txt');shutil.copyfile(source,dest)
  active_notices.add(dest)
  captured.append({'path':str(dest.relative_to(out)), 'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()})
 for source in upstream:
  if source['package']!=p['name']: continue
  local=out/source['file']
  if hashlib.sha256(local.read_bytes()).hexdigest()!=source['sha256']: raise RuntimeError('Changed upstream notice: '+p['name'])
  dest=out/'licenses'/('rust-'+notice_id+'-upstream.txt');shutil.copyfile(local,dest)
  active_notices.add(dest)
  captured.append({'path':str(dest.relative_to(out)), 'sha256':source['sha256'], 'source':source['source']})
 row['licenseFiles']=captured
 if not captured: raise RuntimeError('Missing notice text: '+p['name'])
 if not row['license'] and not f: raise RuntimeError('Missing Rust license: '+p['name'])
 rows.append(row)
for row in rows:
 for notice in row['licenseFiles']:
  if hashlib.sha256((out/notice['path']).read_bytes()).hexdigest()!=notice['sha256']:
   raise RuntimeError('Notice was overwritten: '+notice['path'])
(out/'rust-licenses.json').write_text(json.dumps(rows,indent=2)+'\n')
print('Recorded locked Dart and Rust dependency license evidence.')

# Include exact notices in internal binaries; this does not choose our license.
by_text={}
for f in (out/'licenses').glob('*.txt'):
 if f not in active_notices: f.unlink()
for f in sorted(active_notices):
 raw=f.read_text(errors='replace')
 by_text.setdefault(raw,[]).append(f.stem)
asset=lab/'assets/THIRD_PARTY_NOTICES.txt';asset.parent.mkdir(exist_ok=True)
asset.write_text('Third-party dependency notices for the Vortice Sync Lab internal experiment.\nThe repository license and public distribution remain separate decisions.\n\n'+
 '\n\n'.join('Packages: '+', '.join(names)+'\n\n'+raw for raw,names in by_text.items()))
