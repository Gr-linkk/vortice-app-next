"""Remove one exact native-CAD synthetic job/profile; never delete its asset."""
import argparse
import json
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from next_environment import assert_environment, query_file

parser = argparse.ArgumentParser()
parser.add_argument('manifest', type=Path)
args = parser.parse_args()
assert_environment()
manifest = json.loads(args.manifest.read_text())
title = manifest['title']
assert title.startswith('E2E-CAD-') and str(uuid.UUID(title[8:])) == title[8:]
org = str(uuid.UUID(manifest['organization']))
job = str(uuid.UUID(manifest['work_order_id']))
sql_file = args.manifest.parent / 'native-cad-cleanup.sql'
receipt = args.manifest.parent / ('native-cad-cleanup-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S') + '.json')
assert not receipt.exists()
sql_file.write_text(f"""begin;
do $$ begin
 if not exists(select 1 from public.organization_memberships m join public.profiles p on p.id=m.profile_id
  where m.organization_id='{org}' and p.email='demo_service_owner@vortice.dev' and 'company_owner'=any(m.roles))
 then raise exception 'Test company identity mismatch'; end if;
 if exists(select 1 from public.work_orders where id='{job}' and (title<>'{title}' or provider_organization_id is distinct from '{org}'::uuid))
 then raise exception 'Test work identity mismatch'; end if;
 if exists(select 1 from public.organization_billing_profiles where organization_id='{org}' and details->>'legal_name' is distinct from '{title}')
 then raise exception 'Issuer was changed outside this test'; end if;
 if exists(select 1 from public.invoices where work_order_id='{job}' and billing_details->'issuer'->>'legal_name' is distinct from '{title}')
  or exists(select 1 from storage.objects where split_part(name,'/',1)='{job}')
  or exists(select 1 from public.parts where work_order_id='{job}')
  or exists(select 1 from public.job_part_requirements where work_order_id='{job}')
 then raise exception 'Unexpected fixture dependencies'; end if;
end $$;
create temp table before_cleanup as select
 (select count(*) from public.work_orders where id<>'{job}') as other_jobs,
 (select count(*) from public.invoices where work_order_id<>'{job}') as other_invoices,
 (select count(*) from public.organization_billing_profiles where organization_id<>'{org}') as other_profiles;
-- Only this uniquely marked synthetic invoice; restore the guard in this transaction.
delete from public.notifications where reference_id='{job}' or reference_id in(select id from public.invoices where work_order_id='{job}');
alter table public.invoices disable trigger invoice_closeout;
delete from public.invoices where work_order_id='{job}';
alter table public.invoices enable trigger invoice_closeout;
delete from public.organization_work_report_state where work_order_id='{job}';
delete from public.maintenance_labour_sessions where work_order_id='{job}';
delete from public.hour_logs where work_order_id='{job}';
delete from public.maintenance_operations where object_id='{job}';
delete from public.work_order_sources where work_order_id='{job}';
delete from public.work_orders where id='{job}';
delete from public.asset_history_entries where job_id='{job}' or (source_type='job' and source_id='{job}');
delete from public.organization_billing_profiles where organization_id='{org}' and details->>'legal_name'='{title}';
do $$ begin
 if exists(select 1 from before_cleanup where
 other_jobs<>(select count(*) from public.work_orders) or other_invoices<>(select count(*) from public.invoices)
 or other_profiles<>(select count(*) from public.organization_billing_profiles)) then raise exception 'Unrelated records changed'; end if;
end $$;
commit;
select not exists(select 1 from public.work_orders where id='{job}') as work_removed,
 not exists(select 1 from public.organization_billing_profiles where organization_id='{org}') as synthetic_profile_removed,
 exists(select 1 from pg_trigger where tgrelid='public.invoices'::regclass and tgname='invoice_closeout' and tgenabled='O') as guard_enabled;
""")
receipt.write_text(json.dumps({'status': 'started', 'manifest': str(args.manifest.resolve()), 'job': job}, indent=2))
rows = query_file(sql_file)
assert rows and all(rows[-1].values()), 'Cleanup verification failed'
receipt.write_text(json.dumps({'status': 'complete', 'manifest': str(args.manifest.resolve()), 'job': job, 'checks': rows[-1]}, indent=2))
print(json.dumps({'status': 'complete', 'receipt': str(receipt)}))
