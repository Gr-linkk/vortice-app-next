begin;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$ begin
  if ok is distinct from true then raise exception 'FAIL: %', label; end if;
end $$;
create function pg_temp.expect_error(command text, expected text) returns void
language plpgsql as $$ begin
  begin execute command;
  exception when others then
    if position(expected in sqlerrm)>0 then return; end if;
    raise;
  end;
  raise exception 'Expected error containing: %',expected;
end $$;

insert into auth.users(id,email,raw_user_meta_data)
select ('a0240000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'now024-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NOW024 '||right(id::text,1) where id::text like 'a0240000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0240000-0000-4000-8000-000000000010','Company A','a0240000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0240000-0000-4000-8000-000000000010'
 where id in ('a0240000-0000-4000-8000-000000000001','a0240000-0000-4000-8000-000000000002','a0240000-0000-4000-8000-000000000004','a0240000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0240000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a0240000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a0240000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0240000-0000-4000-8000-000000000021','a0240000-0000-4000-8000-000000000001','a0240000-0000-4000-8000-000000000020','A vessel'),
 ('a0240000-0000-4000-8000-000000000022','a0240000-0000-4000-8000-000000000003','a0240000-0000-4000-8000-000000000020','B vessel');
update public.assets set created_at='2025-12-01Z' where id::text like 'a0240000-%';
select set_config('request.jwt.claim.sub','a0240000-0000-4000-8000-000000000005',true);
insert into public.work_orders(id,asset_id,client_id,created_by,title,job_type,status,managed_maintenance,completed_at)
select ('a0240000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'a0240000-0000-4000-8000-000000000021','a0240000-0000-4000-8000-000000000001',
 'a0240000-0000-4000-8000-000000000005','Report job '||n,'repair','closed',n in (30,31,32,37),'2026-01-10Z'
from generate_series(30,37) n;
insert into public.maintenance_job_records(id,approved_at,hourly_cost)
select id,case when right(id::text,2)='32' then null else '2026-01-10Z'::timestamptz end,50
from public.work_orders where id::text like 'a0240000-%' and managed_maintenance;
insert into public.saved_checklists(id,asset_id,client_id,template_name,checklist_type,source_type,work_order_id,submitted_at,snapshot)
values ('a0240000-0000-4000-8000-000000000100','a0240000-0000-4000-8000-000000000021','a0240000-0000-4000-8000-000000000001',
 'Approved job','maintenance','work_order','a0240000-0000-4000-8000-000000000030','2026-01-10Z',
 '{"managed_maintenance":true,"hourly_cost":50,"labour":[{"started_at":"2026-01-10T08:00:00Z","stopped_at":"2026-01-10T10:00:00Z"}],"parts":[{"quantity":2,"unit_cost":20}]}');
-- An older receipt for the same job must not double the expense.
insert into public.saved_checklists(asset_id,client_id,template_name,checklist_type,source_type,work_order_id,submitted_at,snapshot)
select asset_id,client_id,template_name,checklist_type,source_type,work_order_id,'2026-01-09Z',snapshot
from public.saved_checklists where id='a0240000-0000-4000-8000-000000000100';
-- A zero rate with positive hours is explicitly incomplete.
insert into public.saved_checklists(asset_id,client_id,template_name,checklist_type,source_type,work_order_id,submitted_at,snapshot)
select asset_id,client_id,template_name,checklist_type,source_type,'a0240000-0000-4000-8000-000000000031','2026-01-11Z',
 jsonb_set(snapshot,'{hourly_cost}','0')||'{"parts":[]}'
from public.saved_checklists where id='a0240000-0000-4000-8000-000000000100';
-- Mutable post-approval costs and an unapproved job do not affect the report.
insert into public.parts(work_order_id,description,quantity,unit_cost)
values ('a0240000-0000-4000-8000-000000000030','Later edit',1,900),
 ('a0240000-0000-4000-8000-000000000032','Unapproved',1,800);
insert into public.invoices(id,work_order_id,client_id,invoice_number,labour_hours,billable_rate_usd,parts_total_usd,consumables_total_usd,iva_pct,exchange_rate,labour_total_usd,subtotal_usd,iva_total_usd,total_usd,total_mxn)
select ('a0240000-0000-4000-8000-'||lpad((n+100)::text,12,'0'))::uuid,
 ('a0240000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'a0240000-0000-4000-8000-000000000001','REPORT-'||n,1,100,0,0,16,20,100,100,16,116,2320
from generate_series(33,35) n;
-- Initial historical issued fixtures: insertion intentionally supplies frozen dates.
update public.invoices set status='sent' where id in ('a0240000-0000-4000-8000-000000000133','a0240000-0000-4000-8000-000000000135');
-- Issued dates are immutable; test fixtures use the normal migration-owner bypass.
alter table public.invoices disable trigger user;
update public.invoices set sent_at='2026-01-12Z' where id::text like 'a0240000-%' and status='sent';
alter table public.invoices enable trigger user;
update public.invoices set status='void',void_reason='Replaced fixture invoice' where id='a0240000-0000-4000-8000-000000000135';
insert into public.asset_availability_events(asset_id,operation_id,from_state,to_state,note,actor_name,created_at) values
 ('a0240000-0000-4000-8000-000000000021',gen_random_uuid(),'unknown','out_of_service','Awaiting repair','Manager','2025-12-31T20:00Z'),
 ('a0240000-0000-4000-8000-000000000021',gen_random_uuid(),'out_of_service','under_maintenance','Repair begun','Manager','2026-01-01T04:00Z'),
 ('a0240000-0000-4000-8000-000000000021',gen_random_uuid(),'under_maintenance','restricted','Restricted use','Manager','2026-01-01T08:00Z');
insert into public.maintenance_requests(asset_id,flagged_by,description,created_at,status)
values ('a0240000-0000-4000-8000-000000000021','a0240000-0000-4000-8000-000000000001','Cooling leak','2026-01-05Z','resolved'),
 ('a0240000-0000-4000-8000-000000000021','a0240000-0000-4000-8000-000000000001',E'\t cooling   LEAK \n','2026-01-07Z','open'),
 ('a0240000-0000-4000-8000-000000000021','a0240000-0000-4000-8000-000000000001','Cooling leak','2026-01-08Z','dismissed'),
 ('a0240000-0000-4000-8000-000000000022','a0240000-0000-4000-8000-000000000003','Cooling leak','2026-01-07Z','open');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0240000-0000-4000-8000-000000000001',true);
create temporary table equipment_report_result on commit drop as
select public.equipment_report('2026-01-01Z','2026-02-01Z') as report;
select pg_temp.assert_true(jsonb_array_length((select report from pg_temp.equipment_report_result)->'assets')=1,'company scope');
select pg_temp.assert_true(((select report from pg_temp.equipment_report_result)->'assets'->0->>'labour')::numeric=100,'approved frozen labour once');
select pg_temp.assert_true(((select report from pg_temp.equipment_report_result)->'assets'->0->>'parts')::numeric=40,'approved frozen parts only');
select pg_temp.assert_true(((select report from pg_temp.equipment_report_result)->'assets'->0->>'outside')::numeric=116,'issued only, no duplicate provider costs');
select pg_temp.assert_true(((select report from pg_temp.equipment_report_result)->'assets'->0->>'total')::numeric=256,'total reconciles');
select pg_temp.assert_true(((select report from pg_temp.equipment_report_result)->'assets'->0->>'unavailable_hours')::numeric=8,'clipped transitions, restricted excluded');
select pg_temp.assert_true(((select report from pg_temp.equipment_report_result)->'assets'->0->>'unknown_hours')::numeric=0,'known before start');
select pg_temp.assert_true(((select report from pg_temp.equipment_report_result)->'assets'->0->>'cost_gaps')::int=5,'zero rate, missing receipt and three unbilled provider jobs');
select pg_temp.assert_true(((select report from pg_temp.equipment_report_result)->'assets'->0->>'fault_count')::int=2,'dismissed and other fleet faults excluded');
select pg_temp.assert_true(((select report from pg_temp.equipment_report_result)->'assets'->0->'repeats'->0->>'count')::int=2,'case and whitespace match');
select pg_temp.assert_true((public.equipment_report('2026-01-01T02:00Z','2026-01-01T06:00Z')->'assets'->0->>'unavailable_hours')::numeric=4,'both edges clipped');
select pg_temp.assert_true((public.equipment_report('2026-01-01Z','2026-01-10Z')->'assets'->0->>'labour')::numeric=0,'exclusive end');
select pg_temp.expect_error($q$select public.equipment_report(null,'2026-02-01Z')$q$,'Select');
select pg_temp.expect_error($q$select public.equipment_report('2024-01-01Z','2026-02-01Z')$q$,'Select');
select pg_temp.expect_error($q$select public.equipment_report('2026-02-01Z','2026-01-01Z')$q$,'Select');
select set_config('request.jwt.claim.sub','a0240000-0000-4000-8000-000000000007',true);
select pg_temp.assert_true((public.equipment_report('2026-01-01Z','2026-02-01Z')->'assets'->0->>'total')::numeric=256,'company admin access');
select set_config('request.jwt.claim.sub','a0240000-0000-4000-8000-000000000003',true);
update pg_temp.equipment_report_result set report=public.equipment_report('2026-01-01Z','2026-02-01Z');
select pg_temp.assert_true(((select report from pg_temp.equipment_report_result)->'assets'->0->>'total')::numeric=0,'other company cannot see costs');
select pg_temp.assert_true(((select report from pg_temp.equipment_report_result)->'assets'->0->>'unknown_hours')::numeric=744,'missing history is unknown');
select pg_temp.assert_true(jsonb_array_length((select report from pg_temp.equipment_report_result)->'assets'->0->'repeats')=0,'no cross-asset repeat group');
reset role;
insert into public.asset_availability_events(asset_id,operation_id,from_state,to_state,note,actor_name,created_at)
values ('a0240000-0000-4000-8000-000000000022',gen_random_uuid(),'unknown','out_of_service','Open interval','Manager','2026-01-15Z');
set local role authenticated;
select pg_temp.assert_true((public.equipment_report('2026-01-01Z','2026-02-01Z')->'assets'->0->>'unavailable_hours')::numeric=408,'open interval ends at report boundary');
select pg_temp.assert_true((public.equipment_report('2026-01-01Z','2026-02-01Z')->'assets'->0->>'unknown_hours')::numeric=336,'before first state remains unknown');
reset role;
insert into public.asset_availability_events(asset_id,operation_id,from_state,to_state,note,actor_name,created_at)
values ('a0240000-0000-4000-8000-000000000022',gen_random_uuid(),'out_of_service','available','Ambiguous same instant','Manager','2026-01-15Z');
set local role authenticated;
select pg_temp.assert_true((public.equipment_report('2026-01-01Z','2026-02-01Z')->'assets'->0->>'unknown_hours')::numeric=744,'unordered same-time events are unknown');
select pg_temp.assert_true((public.equipment_report('2026-01-01Z','2026-02-01Z')->'assets'->0->>'unavailable_hours')::numeric=0,'ambiguous state does not invent downtime');
select set_config('request.jwt.claim.sub','a0240000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error($q$select public.equipment_report('2026-01-01Z','2026-02-01Z')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0240000-0000-4000-8000-000000000004',true);
select pg_temp.expect_error($q$select public.equipment_report('2026-01-01Z','2026-02-01Z')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0240000-0000-4000-8000-000000000006',true);
select pg_temp.expect_error($q$select public.equipment_report('2026-01-01Z','2026-02-01Z')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0240000-0000-4000-8000-000000000005',true);
-- The provider owner can also see pre-existing hosted fleets. Require both
-- isolated fixture assets without assuming the entire backend contains only two.
select pg_temp.assert_true((select count(distinct a->>'id')=2
 from jsonb_array_elements(public.equipment_report('2026-01-01Z','2026-02-01Z')->'assets') a
 where a->>'id' in ('a0240000-0000-4000-8000-000000000021','a0240000-0000-4000-8000-000000000022')),
 'provider manager sees both fixture fleets');
reset role;
set local role anon;
select pg_temp.expect_error($q$select public.equipment_report('2026-01-01Z','2026-02-01Z')$q$,'permission denied');
rollback;
