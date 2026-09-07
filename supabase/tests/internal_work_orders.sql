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
select ('a0140000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'now014-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NOW014 '||right(id::text,1) where id::text like 'a0140000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0140000-0000-4000-8000-000000000010','Company A','a0140000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0140000-0000-4000-8000-000000000010'
 where id in ('a0140000-0000-4000-8000-000000000001','a0140000-0000-4000-8000-000000000002','a0140000-0000-4000-8000-000000000004','a0140000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0140000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a0140000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a0140000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0140000-0000-4000-8000-000000000021','a0140000-0000-4000-8000-000000000001','a0140000-0000-4000-8000-000000000020','A vessel'),
 ('a0140000-0000-4000-8000-000000000022','a0140000-0000-4000-8000-000000000003','a0140000-0000-4000-8000-000000000020','B vessel');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000001',true);
-- The existing plans and newly booked work are one connected journey.
select public.save_maintenance_setup(gen_random_uuid(),'component','a0140000-0000-4000-8000-000000000040',0,
 '{"asset_id":"a0140000-0000-4000-8000-000000000021","label":"Generator","current_hours":240}');
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000041',0,
 '{"asset_id":"a0140000-0000-4000-8000-000000000021","engine_id":"a0140000-0000-4000-8000-000000000040","interval_label":"250-hour service","interval_hours":250,"last_service_hours":0}');
reset role;
insert into public.checklist_templates(id,asset_type_id,name,checklist_type) values
 ('a0140000-0000-4000-8000-000000000060','a0140000-0000-4000-8000-000000000020','Inspection checks','pm');
insert into public.checklist_items(id,template_id,description_en,requires_photo) values
 ('a0140000-0000-4000-8000-000000000061','a0140000-0000-4000-8000-000000000060','Inspect mountings',false);
set local role authenticated;
create function pg_temp.order_data(kind text) returns jsonb language sql as $$
 select jsonb_build_object('asset_id','a0140000-0000-4000-8000-000000000021','title','Internal '||coalesce(kind,'legacy'),
 'job_type',kind,'assigned_to','a0140000-0000-4000-8000-000000000002',
 'expected_materials','Filter and fasteners','description','Inspect and prepare the vessel')
$$;
create function pg_temp.edit_data() returns jsonb language sql as $$
 select '{"title":"Updated inspection scope","description":"Inspect every mounting","job_type":"inspection",
 "expected_materials":"Torque wrench","priority":"high","note":"Prepare before planned shutdown"}'::jsonb
$$;
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000030',pg_temp.order_data('general'));
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000031',pg_temp.order_data('inspection')||
 '{"checklist_template_id":"a0140000-0000-4000-8000-000000000060"}');
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000032',pg_temp.order_data('preventative'));
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000033',pg_temp.order_data('repair'));
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000034',pg_temp.order_data('preventative')||
 '{"service_interval_id":"a0140000-0000-4000-8000-000000000041"}');
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000035',pg_temp.order_data(null));
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000030',pg_temp.order_data('general'));
select pg_temp.assert_true((select count(*)=6 from public.maintenance_jobs()),'all four types and legacy input create one order each');
select pg_temp.assert_true((select j->>'job_type'='repair' from public.maintenance_jobs('a0140000-0000-4000-8000-000000000035') j),'older caller retains repair default');
select pg_temp.assert_true((select j->>'job_type'='inspection' and j->>'expected_materials'='Filter and fasteners'
 and jsonb_array_length(j->'checklist_snapshot')=1 from public.maintenance_jobs('a0140000-0000-4000-8000-000000000031') j),'inspection keeps type materials and checklist');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.maintenance_planning()->'jobs') j where j->>'job_type'='general'),'planning preserves work type');
select pg_temp.expect_error($q$select public.create_maintenance_job(gen_random_uuid(),pg_temp.order_data('other'))$q$,'valid work type');
select pg_temp.expect_error($q$select public.create_maintenance_job(gen_random_uuid(),pg_temp.order_data('general')||'{"service_interval_id":"a0140000-0000-4000-8000-000000000041"}')$q$,'requires preventive');
select pg_temp.expect_error($q$select public.create_maintenance_job(gen_random_uuid(),pg_temp.order_data('general')||jsonb_build_object('expected_materials',repeat('x',4001)))$q$,'4000');
select pg_temp.expect_error($q$select public.create_maintenance_job(gen_random_uuid(),pg_temp.order_data('general')||'{"checklist_template_id":"a0140000-0000-4000-8000-000000000099"}')$q$,'Invalid checklist');
select public.update_internal_work_order('a0140000-0000-4000-8000-000000000030',0,'a0140000-0000-4000-8000-000000000070',pg_temp.edit_data());
select public.update_internal_work_order('a0140000-0000-4000-8000-000000000030',0,'a0140000-0000-4000-8000-000000000070',pg_temp.edit_data());
select pg_temp.assert_true((select j->>'title'='Updated inspection scope' and j->>'expected_materials'='Torque wrench'
 and j->>'job_type'='inspection' and (j->>'revision')::int=1 from public.maintenance_jobs('a0140000-0000-4000-8000-000000000030') j),'revision checked edit is replay safe');
select pg_temp.expect_error($q$select public.update_internal_work_order('a0140000-0000-4000-8000-000000000030',0,'a0140000-0000-4000-8000-000000000070',pg_temp.edit_data()||'{"title":"Different input"}')$q$,'different input');
select pg_temp.expect_error($q$select public.update_internal_work_order('a0140000-0000-4000-8000-000000000030',0,gen_random_uuid(),pg_temp.edit_data())$q$,'changed');
select pg_temp.expect_error($q$select public.update_internal_work_order('a0140000-0000-4000-8000-000000000030',1,gen_random_uuid(),pg_temp.edit_data()||'{"note":""}')$q$,'Explain');
select pg_temp.expect_error($q$select public.update_internal_work_order('a0140000-0000-4000-8000-000000000034',0,gen_random_uuid(),pg_temp.edit_data())$q$,'requires preventive');
-- A second company's manager cannot discover, create against, or edit A's work.
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.maintenance_jobs()),'other company cannot read orders');
select pg_temp.expect_error($q$select public.create_maintenance_job(gen_random_uuid(),pg_temp.order_data('general'))$q$,'Access denied');
select pg_temp.expect_error($q$select public.update_internal_work_order('a0140000-0000-4000-8000-000000000030',1,gen_random_uuid(),pg_temp.edit_data())$q$,'Access denied');
-- Mechanics execute, but scope management remains with their company manager.
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error($q$select public.update_internal_work_order('a0140000-0000-4000-8000-000000000030',1,gen_random_uuid(),pg_temp.edit_data())$q$,'Access denied');
select public.change_maintenance_job('a0140000-0000-4000-8000-000000000030',1,gen_random_uuid(),'start','{}');
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error($q$select public.update_internal_work_order('a0140000-0000-4000-8000-000000000030',2,gen_random_uuid(),pg_temp.edit_data())$q$,'before work starts');
select public.change_maintenance_job('a0140000-0000-4000-8000-000000000030',2,gen_random_uuid(),'pause','{}');
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error($q$select public.change_maintenance_job('a0140000-0000-4000-8000-000000000030',3,gen_random_uuid(),'submit','{"diagnosis":"","repair":""}')$q$,'Findings and work performed');
select public.change_maintenance_job('a0140000-0000-4000-8000-000000000030',3,gen_random_uuid(),'submit',
 '{"diagnosis":"Mountings inspected; no defects","repair":"Verified mounting torque and recorded results","answers":{},"evidence_paths":[]}');
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000001',true);
select public.change_maintenance_job('a0140000-0000-4000-8000-000000000030',4,gen_random_uuid(),'approve','{}');
select pg_temp.assert_true((select j->>'status'='closed' and j->>'job_type'='inspection' from public.maintenance_jobs('a0140000-0000-4000-8000-000000000030') j),'inspection completes the same reviewed lifecycle');
reset role;
select pg_temp.assert_true(not exists(select 1 from public.invoices where work_order_id='a0140000-0000-4000-8000-000000000030'),'internal approval creates no invoice');
select pg_temp.assert_true((select next_due_hours=250 from public.asset_service_intervals where id='a0140000-0000-4000-8000-000000000041'),'unlinked inspection does not advance service interval');
select pg_temp.assert_true((select count(*)=1 from public.maintenance_operations where object_id='a0140000-0000-4000-8000-000000000030' and kind='scope_previous' and payload->>'job_type'='general'),'original scope retained once');
update public.client_capabilities set enabled=false where client_id='a0140000-0000-4000-8000-000000000001' and capability_key='pm_checklists';
set local role authenticated;
select pg_temp.expect_error($q$select public.update_internal_work_order('a0140000-0000-4000-8000-000000000031',0,gen_random_uuid(),pg_temp.edit_data())$q$,'Access denied');
rollback;
