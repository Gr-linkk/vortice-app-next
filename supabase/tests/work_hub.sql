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
select ('a2020000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'next002-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NEXT002 '||right(id::text,1) where id::text like 'a2020000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a2020000-0000-4000-8000-000000000010','Company A','a2020000-0000-4000-8000-000000000001');
update public.profiles set org_id='a2020000-0000-4000-8000-000000000010'
 where id in ('a2020000-0000-4000-8000-000000000001','a2020000-0000-4000-8000-000000000002','a2020000-0000-4000-8000-000000000004','a2020000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a2020000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a2020000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a2020000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a2020000-0000-4000-8000-000000000021','a2020000-0000-4000-8000-000000000001','a2020000-0000-4000-8000-000000000020','A vessel'),
 ('a2020000-0000-4000-8000-000000000022','a2020000-0000-4000-8000-000000000003','a2020000-0000-4000-8000-000000000020','B vessel');

set local role authenticated;
select set_config('request.jwt.claim.sub','a2020000-0000-4000-8000-000000000001',true);
select public.save_maintenance_setup(gen_random_uuid(),'component','a2020000-0000-4000-8000-000000000040',0,
 '{"asset_id":"a2020000-0000-4000-8000-000000000021","label":"Generator","current_hours":240}');
select public.save_maintenance_setup(gen_random_uuid(),'plan','a2020000-0000-4000-8000-000000000041',0,
 '{"asset_id":"a2020000-0000-4000-8000-000000000021","engine_id":"a2020000-0000-4000-8000-000000000040","interval_label":"250-hour service","interval_hours":250,"last_service_hours":0}');
select public.create_maintenance_job('a2020000-0000-4000-8000-000000000030',
 '{"asset_id":"a2020000-0000-4000-8000-000000000021","title":"Completed mechanic job","service_interval_id":"a2020000-0000-4000-8000-000000000041","due_date":"2026-09-10"}');
select public.create_maintenance_job('a2020000-0000-4000-8000-000000000031',
 '{"asset_id":"a2020000-0000-4000-8000-000000000021","title":"Completed employee job"}');
select public.create_maintenance_job('a2020000-0000-4000-8000-000000000032',
 '{"asset_id":"a2020000-0000-4000-8000-000000000021","title":"Waiting for parts"}');
select public.create_maintenance_job('a2020000-0000-4000-8000-000000000033',
 '{"asset_id":"a2020000-0000-4000-8000-000000000021","title":"Unassigned work"}');
-- Read-only contract fixture: exercise reader scope without retesting completion.
reset role;
update public.work_orders set status='closed', assigned_to=case id
 when 'a2020000-0000-4000-8000-000000000030'::uuid then 'a2020000-0000-4000-8000-000000000002'::uuid
 else 'a2020000-0000-4000-8000-000000000006'::uuid end
 where id in ('a2020000-0000-4000-8000-000000000030','a2020000-0000-4000-8000-000000000031');
update public.work_orders set status='on_hold',on_hold_reason='Waiting for replacement filter' where id='a2020000-0000-4000-8000-000000000032';
update public.maintenance_job_records set blocked_category='parts' where id='a2020000-0000-4000-8000-000000000032';
update public.maintenance_job_records set planned_start='2026-09-08T12:00:00Z',estimated_minutes=60 where id='a2020000-0000-4000-8000-000000000030';
select pg_temp.assert_true(not has_function_privilege('anon','public.maintenance_work_hub(uuid)','execute'),'anonymous has no hub execution grant');
set local role anon;
select pg_temp.expect_error($q$select public.maintenance_work_hub()$q$,'permission denied');
reset role;
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.maintenance_work_hub()->'jobs')=4,'manager hub includes completed and active work');
select pg_temp.assert_true(jsonb_array_length(public.maintenance_planning()->'jobs')=2,'legacy forward planning still excludes completed work');
select pg_temp.assert_true((public.maintenance_work_hub()->'plans')=(public.maintenance_planning()->'plans'),'hub preserves latest recurrence and included-plan projections');
select pg_temp.assert_true((select count(*)=2 from jsonb_array_elements(public.maintenance_work_hub()->'jobs') j where j->>'status'='closed'),'completed history is present');
select pg_temp.assert_true((select j->>'blocked_category'='parts' from jsonb_array_elements(public.maintenance_work_hub()->'jobs') j where j->>'id'='a2020000-0000-4000-8000-000000000032'),'blocked filter receives exact category');
select pg_temp.assert_true((select j->>'due_date'='2026-09-10' and (j->>'planned_start')::timestamptz='2026-09-08T12:00:00Z'::timestamptz and j->>'component_name'='Generator'
 from jsonb_array_elements(public.maintenance_work_hub()->'jobs') j where j->>'id'='a2020000-0000-4000-8000-000000000030'),'history keeps component deadline and appointment separate');
select pg_temp.assert_true(jsonb_array_length(public.maintenance_work_hub('a2020000-0000-4000-8000-000000000022')->'jobs')=0,'asset filter does not broaden company scope');
select set_config('request.jwt.claim.sub','a2020000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(jsonb_array_length(public.maintenance_work_hub()->'jobs')=0 and jsonb_array_length(public.maintenance_work_hub()->'plans')=0,'other company cannot see active or completed work');
select set_config('request.jwt.claim.sub','a2020000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(jsonb_array_length(public.maintenance_work_hub()->'jobs')=1 and public.maintenance_work_hub()->'jobs'->0->>'id'='a2020000-0000-4000-8000-000000000030','company mechanic sees only assigned completed work');
select pg_temp.assert_true(jsonb_array_length(public.maintenance_work_hub()->'plans')=0,'mechanic gains no plan access');
select set_config('request.jwt.claim.sub','a2020000-0000-4000-8000-000000000006',true);
select pg_temp.assert_true(jsonb_array_length(public.maintenance_work_hub()->'jobs')=1 and public.maintenance_work_hub()->'jobs'->0->>'id'='a2020000-0000-4000-8000-000000000031','provider employee sees only assigned completed managed work');
select set_config('request.jwt.claim.sub','a2020000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true(jsonb_array_length(public.maintenance_work_hub()->'jobs')=0,'operator receives no private work history');
rollback;
