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
select ('a0090000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'now009-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NOW009 '||right(id::text,1) where id::text like 'a0090000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0090000-0000-4000-8000-000000000010','Company A','a0090000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0090000-0000-4000-8000-000000000010'
 where id in ('a0090000-0000-4000-8000-000000000001','a0090000-0000-4000-8000-000000000002','a0090000-0000-4000-8000-000000000004','a0090000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0090000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a0090000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a0090000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0090000-0000-4000-8000-000000000021','a0090000-0000-4000-8000-000000000001','a0090000-0000-4000-8000-000000000020','A vessel'),
 ('a0090000-0000-4000-8000-000000000022','a0090000-0000-4000-8000-000000000003','a0090000-0000-4000-8000-000000000020','B vessel');

insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0090000-0000-4000-8000-000000000023','a0090000-0000-4000-8000-000000000001','a0090000-0000-4000-8000-000000000020','Another A asset');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000001',true);
select public.report_maintenance_fault('a0090000-0000-4000-8000-000000000030','a0090000-0000-4000-8000-000000000021','Hydraulic seal leaking','urgent');
select pg_temp.assert_true((select (j->>'can_plan_repair')::boolean from public.maintenance_faults(null,'a0090000-0000-4000-8000-000000000030') j),'company manager can plan a repair');
select public.change_asset_availability('a0090000-0000-4000-8000-000000000021',0,gen_random_uuid(),'under_maintenance','Isolated pending repair');
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000030',null,gen_random_uuid(),'{"title":"Repair seal"}')$q$,'changed');
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000030',0,gen_random_uuid(),'{"asset_id":"a0090000-0000-4000-8000-000000000023","title":"Repair seal"}')$q$,'same asset');
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000030',0,gen_random_uuid(),'{"title":"x"}')$q$,'Title');
select pg_temp.assert_true((select count(*)=0 from public.maintenance_jobs()),'failed create leaves no orphan job');

select set_config('now009.job',public.plan_fault_work_order('a0090000-0000-4000-8000-000000000030',0,
 'a0090000-0000-4000-8000-000000000031','{"title":"Repair seal","description":"Hydraulic seal leaking","assigned_to":"a0090000-0000-4000-8000-000000000002","priority":"urgent"}')::text,true);
select pg_temp.assert_true(public.plan_fault_work_order('a0090000-0000-4000-8000-000000000030',0,
 'a0090000-0000-4000-8000-000000000031','{"title":"Repair seal","description":"Hydraulic seal leaking","assigned_to":"a0090000-0000-4000-8000-000000000002","priority":"urgent"}')=current_setting('now009.job')::uuid,'uncertain response returns same job');
select pg_temp.assert_true((select count(*)=1 from public.maintenance_jobs()),'exactly one managed work order');
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000030',0,'a0090000-0000-4000-8000-000000000031','{"title":"Different repair"}')$q$,'different input');
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000030',1,gen_random_uuid(),'{"title":"Second repair"}')$q$,'already has');
select pg_temp.expect_error($q$select public.update_maintenance_fault('a0090000-0000-4000-8000-000000000030',1,gen_random_uuid(),'start','Start repair')$q$,'linked work order');
select pg_temp.expect_error($q$select public.update_maintenance_fault('a0090000-0000-4000-8000-000000000030',1,gen_random_uuid(),'assign','Assign again','a0090000-0000-4000-8000-000000000002')$q$,'linked work order');
select pg_temp.expect_error($q$select public.update_maintenance_fault('a0090000-0000-4000-8000-000000000030',1,gen_random_uuid(),'resolve','Looks fixed')$q$,'Approve the linked');

-- Only the same asset's open managed jobs can be linked, including company admins.
select public.report_maintenance_fault('a0090000-0000-4000-8000-000000000032','a0090000-0000-4000-8000-000000000021','Second inspection finding','normal');
select public.create_maintenance_job('a0090000-0000-4000-8000-000000000034','{"asset_id":"a0090000-0000-4000-8000-000000000023","title":"Other asset repair"}');
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000032',0,gen_random_uuid(),'{"job_id":"a0090000-0000-4000-8000-000000000034"}')$q$,'on this asset');
select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000007',true);
select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000032',0,'a0090000-0000-4000-8000-000000000033',jsonb_build_object('job_id',current_setting('now009.job')));
select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000032',0,'a0090000-0000-4000-8000-000000000033',jsonb_build_object('job_id',current_setting('now009.job')));
select pg_temp.assert_true((select (j->>'work_order_managed')::boolean and (j->>'can_open_work_order')::boolean and j->>'status'='acknowledged'
 from public.maintenance_faults(null,'a0090000-0000-4000-8000-000000000032') j),'admin links managed work order');

select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000030',1,gen_random_uuid(),'{"title":"Cross company"}')$q$,'Access denied');
select pg_temp.assert_true((select count(*)=0 from public.maintenance_faults()),'company B cannot read company A fault links');
select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true((select not (j->>'can_open_work_order')::boolean and not (j->>'can_plan_repair')::boolean
 from public.maintenance_faults(null,'a0090000-0000-4000-8000-000000000030') j),'operator sees progress without job access');
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000030',1,gen_random_uuid(),'{"title":"Operator attempt"}')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000030',1,gen_random_uuid(),'{"title":"Mechanic attempt"}')$q$,'Access denied');
select public.apply_maintenance_field_action(current_setting('now009.job')::uuid,0,gen_random_uuid(),'start','{}',clock_timestamp());
select pg_temp.assert_true((select count(*)=2 from public.maintenance_faults() f where f->>'status'='in_progress'),'both linked faults follow job start');
select public.change_maintenance_job(current_setting('now009.job')::uuid,1,gen_random_uuid(),'pause','{}');
select public.change_maintenance_job(current_setting('now009.job')::uuid,2,gen_random_uuid(),'submit','{"diagnosis":"Worn seal","repair":"Replaced and tested under load"}');
select pg_temp.assert_true((select f->>'status'='in_progress' and f->>'work_order_status'='pending_review'
 from public.maintenance_faults(null,'a0090000-0000-4000-8000-000000000030') f),'job submission does not prematurely ask for fault resolution');
select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000001',true);
select public.report_maintenance_fault('a0090000-0000-4000-8000-000000000035','a0090000-0000-4000-8000-000000000021','Unlinked finding','normal');
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000035',0,gen_random_uuid(),jsonb_build_object('job_id',current_setting('now009.job')))$q$,'not awaiting review');
select public.change_maintenance_job(current_setting('now009.job')::uuid,3,gen_random_uuid(),'approve','{}');
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000035',0,gen_random_uuid(),jsonb_build_object('job_id',current_setting('now009.job')))$q$,'not awaiting review');
select pg_temp.assert_true((select count(*)=2 from public.maintenance_faults() f where f->>'status'='pending_review'),'job approval requests explicit fault verification');
select pg_temp.assert_true((select a->>'operating_state'='under_maintenance' from public.maintenance_fleet() a where a->>'id'='a0090000-0000-4000-8000-000000000021'),'job approval never returns asset to service');
select public.update_maintenance_fault('a0090000-0000-4000-8000-000000000030',
 (select (f->>'revision')::integer from public.maintenance_faults(null,'a0090000-0000-4000-8000-000000000030') f),gen_random_uuid(),'resolve','Seal repair verified');
select pg_temp.assert_true((select f->>'status'='resolved' from public.maintenance_faults(null,'a0090000-0000-4000-8000-000000000030') f),'explicit verification resolves only selected fault');
select public.change_maintenance_job(current_setting('now009.job')::uuid,4,gen_random_uuid(),'reopen','{"note":"Second finding needs further work"}');
select pg_temp.assert_true((select f->>'status'='in_progress' from public.maintenance_faults(null,'a0090000-0000-4000-8000-000000000032') f),'reopening job resumes active fault');
select pg_temp.assert_true((select f->>'status'='resolved' from public.maintenance_faults(null,'a0090000-0000-4000-8000-000000000030') f),'verified fault history remains explicit');

reset role;
update public.client_capabilities set enabled=false where client_id='a0090000-0000-4000-8000-000000000001' and capability_key='pm_checklists';
set local role authenticated;
select pg_temp.expect_error($q$select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000035',0,gen_random_uuid(),'{"title":"Disabled capability"}')$q$,'Access denied');
-- Provider owner remains allowed, independent of company capability.
select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000005',true);
select public.plan_fault_work_order('a0090000-0000-4000-8000-000000000035',0,gen_random_uuid(),'{"title":"Provider repair"}');
rollback;
