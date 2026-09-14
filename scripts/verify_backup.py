#!/usr/bin/env python3
"""Check a complete local export's recorded lengths and hashes without network IO."""
import argparse
import hashlib
import json
from pathlib import Path


def verify(manifest):
    manifest = Path(manifest).resolve()
    root = manifest.parent
    data = json.loads(manifest.read_text())
    if data.get('project_ref') != 'hkjpojobdbbtjkhaudki' or data.get('complete') is not True:
        raise ValueError('Not a complete Next export')
    if {row['file'] for row in data['database']} != {
        'roles.sql', 'schema.sql', 'data.sql', 'managed-access.json',
        'history-schema.sql', 'history-data.sql',
    }:
        raise ValueError('Database export inventory is incomplete')
    if len(data['objects']) != data.get('source_object_count'):
        raise ValueError('Storage export inventory is incomplete')
    seen = set()
    for row in data['database'] + data['objects']:
        path = (root / row['file']).resolve()
        if not path.is_relative_to(root) or path in seen:
            raise ValueError('Unsafe or duplicate backup file mapping')
        seen.add(path)
        if not path.is_file() or path.stat().st_size != row['bytes']:
            raise ValueError('A backup file is missing or has the wrong length')
        digest = hashlib.sha256()
        with path.open('rb') as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b''):
                digest.update(chunk)
        if digest.hexdigest() != row['sha256']:
            raise ValueError('Backup file checksum mismatch')
    return {'verified_files': len(seen), 'storage_objects': len(data['objects']),
            'limits': 'File integrity only; not authenticated provenance or a successful restore.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.manifest)))
    except (OSError, ValueError, KeyError, TypeError):
        parser.exit(1, 'Backup integrity verification failed; no recovery conclusion.\n')
