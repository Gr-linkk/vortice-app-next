#!/usr/bin/env python3
"""One-shot, read-only Next operational report; no scheduler or messages."""
import json
import subprocess
from next_environment import ROOT, REF, assert_environment, query_file


def main():
    assert_environment()
    rows = query_file('supabase/operations/readiness_snapshot.sql')
    if not isinstance(rows, list) or len(rows) != 1 or 'readiness' not in rows[0]:
        raise RuntimeError('Unexpected snapshot response; no health conclusion recorded')
    snapshot = rows[0]['readiness']
    if isinstance(snapshot, str):
        snapshot = json.loads(snapshot)
    expected = sorted(p.name.split('_', 1)[0] for p in (ROOT / 'supabase/migrations').glob('*.sql'))
    snapshot['missing_local_migrations_on_host'] = sorted(set(expected) - set(snapshot['applied_migrations']))
    snapshot['host_migrations_not_in_checkout'] = sorted(set(snapshot['applied_migrations']) - set(expected))
    checks = {
        'public_tables_have_rls': not snapshot['tables_without_rls'],
        'storage_buckets_private': not snapshot['public_buckets'],
        'migration_versions_match': snapshot['applied_migrations'] == expected,
        'push_schedule_recent': snapshot['push_schedule_active'] and
            snapshot['push_last_run_age_seconds'] is not None and snapshot['push_last_run_age_seconds'] < 300,
        'no_schedule_failures_24h': snapshot['push_schedule_failures_24h'] == 0,
        'no_overdue_push': snapshot['overdue_push_deliveries'] == 0,
        'no_failed_push_deliveries': snapshot['push_delivery_states'].get('failed', 0) == 0,
    }
    report = {'project_ref': REF, 'checks': checks, 'snapshot': snapshot,
              'limits': 'Aggregate health only; not delivery, restore, auth email, or customer acceptance.'}
    output = ROOT / 'outputs/next009/operations.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'checks': checks, 'report': str(output)}, indent=2))
    return 0 if all(checks.values()) else 2


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(f'Operational check unavailable: {error}')
        raise SystemExit(1)
