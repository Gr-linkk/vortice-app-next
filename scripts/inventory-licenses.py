#!/usr/bin/env python3
"""Inventory resolved runtime dependency licenses; does not grant legal clearance."""
import hashlib
import json
import subprocess
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse

ROOT = Path(__file__).resolve().parents[1]


def main():
    graph = json.loads((ROOT / '.dart_tool/package_graph.json').read_text())
    packages = {p['name']: p for p in graph['packages']}
    root = packages['vortice_app']
    runtime, pending = set(), list(root['dependencies'])
    while pending:
        name = pending.pop()
        if name in runtime:
            continue
        runtime.add(name)
        pending.extend(packages[name].get('dependencies', []))
    config_path = ROOT / '.dart_tool/package_config.json'
    config = json.loads(config_path.read_text())
    locations = {p['name']: Path(unquote(urlparse(urljoin(config_path.as_uri(), p['rootUri'])).path))
                 for p in config['packages']}
    output = ROOT / 'outputs/next009/licenses'
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for name in sorted(runtime):
        location = locations[name]
        licenses = sorted(p for p in location.iterdir() if p.is_file() and
                          p.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')))
        inherited_sdk_license = False
        if not licenses and name in {'flutter_localizations', 'flutter_test', 'flutter_web_plugins'}:
            for parent in location.parents:
                if (parent / 'bin/flutter').is_file() and (parent / 'LICENSE').is_file():
                    licenses = [parent / 'LICENSE']
                    inherited_sdk_license = True
                    break
        record = {'package': name, 'version': packages[name]['version'],
                  'direct': name in root['dependencies'], 'license_files': [],
                  'inherited_sdk_license': inherited_sdk_license,
                  'manual_review': name.startswith('syncfusion_') or not licenses}
        for file in licenses:
            data = file.read_bytes()
            (output / f'{name}-{file.name}.txt').write_bytes(data)
            record['license_files'].append({'name': file.name, 'sha256': hashlib.sha256(data).hexdigest()})
        records.append(record)
    (output / 'inventory.json').write_text(json.dumps(records, indent=2) + '\n')
    summary = ['# Resolved runtime dependency license inventory', '',
               'Generated from the current package graph; includes transitive runtime packages.',
               'License text presence is not commercial permission or a complete native dependency audit.', '',
               '| Package | Version | Direct | License files | Review |',
               '|---|---|---|---|---|']
    summary.extend(f"| {r['package']} | {r['version']} | {r['direct']} | "
                   f"{', '.join(f['name'] for f in r['license_files']) or 'MISSING'} | "
                   f"{'REQUIRED' if r['manual_review'] else 'Unclassified license text retained'} |" for r in records)
    (output / 'inventory.md').write_text('\n'.join(summary) + '\n')
    tracked_assets = subprocess.run(['git', 'ls-files', '-z', '--', 'assets'], cwd=ROOT,
                                    check=True, capture_output=True, text=True).stdout.split('\0')
    assets = [{'file': name, 'bytes': (ROOT / name).stat().st_size,
               'sha256': hashlib.sha256((ROOT / name).read_bytes()).hexdigest(),
               'rights_status': 'Source and commercial permission require owner review'}
              for name in tracked_assets if name and (ROOT / name).is_file()]
    (output / 'asset-inventory.json').write_text(json.dumps(assets, indent=2) + '\n')
    print(json.dumps({'runtime_packages': len(records), 'manual_review':
                      [r['package'] for r in records if r['manual_review']],
                      'tracked_assets': len(assets), 'output': str(output)}))


if __name__ == '__main__':
    main()
