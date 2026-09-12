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
select ('a2140000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'next204-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NOW013 '||right(id::text,1) where id::text like 'a2140000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a2140000-0000-4000-8000-000000000010','Company A','a2140000-0000-4000-8000-000000000001');
update public.profiles set org_id='a2140000-0000-4000-8000-000000000010'
 where id in ('a2140000-0000-4000-8000-000000000001','a2140000-0000-4000-8000-000000000002','a2140000-0000-4000-8000-000000000004','a2140000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a2140000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a2140000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a2140000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a2140000-0000-4000-8000-000000000021','a2140000-0000-4000-8000-000000000001','a2140000-0000-4000-8000-000000000020','A vessel'),
 ('a2140000-0000-4000-8000-000000000022','a2140000-0000-4000-8000-000000000003','a2140000-0000-4000-8000-000000000020','B vessel');
insert into public.checklist_templates(id,name,checklist_type,is_active,created_by) values('a2140000-0000-4000-8000-000000000040','Truck PM','pm',true,'a2140000-0000-4000-8000-000000000005');
insert into public.checklist_items(id,template_id,sort_order,description_en,requires_photo,definition) values('a2140000-0000-4000-8000-000000000042','a2140000-0000-4000-8000-000000000040',1,'Check hydraulic seal',false,'{"input_type":"check"}');
create function pg_temp.cycle_job(kind text,source uuid) returns uuid language sql as $$ select work_order_id from public.recurring_work_cycles where source_kind=kind and source_id=source order by created_at desc,id desc limit 1 $$;
insert into public.checklist_templates(id,name,checklist_type,is_active,created_by) values
 ('a2140000-0000-4000-8000-000000000043','Covered procedure','pm',true,'a2140000-0000-4000-8000-000000000005');
insert into public.checklist_items(id,template_id,sort_order,description_en,requires_photo,definition) values
 ('a2140000-0000-4000-8000-000000000044','a2140000-0000-4000-8000-000000000043',1,'Replace fuel filter',false,'{"input_type":"check"}');
insert into public.pm_parts_requirements(id,template_id,description,qty,unit) values
 ('a2140000-0000-4000-8000-000000000080','a2140000-0000-4000-8000-000000000040','Primary seal',1,'ea'),
 ('a2140000-0000-4000-8000-000000000081','a2140000-0000-4000-8000-000000000043','Covered fuel filter',2,'ea');
set local role authenticated;
select set_config('request.jwt.claim.sub','a2140000-0000-4000-8000-000000000001',true);
select public.configure_asset_meter('a2140000-0000-4000-8000-000000000021',gen_random_uuid(),'km',62000);
select public.save_maintenance_setup(gen_random_uuid(),'plan','a2140000-0000-4000-8000-000000000045',0,
 jsonb_build_object('asset_id','a2140000-0000-4000-8000-000000000021','engine_id',(select primary_meter_engine_id from public.assets where id='a2140000-0000-4000-8000-000000000021'),
 'interval_label','Covered filter service','interval_hours',5000,'last_service_hours',57000,'checklist_template_id','a2140000-0000-4000-8000-000000000043'));
select public.save_maintenance_setup(gen_random_uuid(),'plan','a2140000-0000-4000-8000-000000000041',0,
 jsonb_build_object('asset_id','a2140000-0000-4000-8000-000000000021','engine_id',(select primary_meter_engine_id from public.assets where id='a2140000-0000-4000-8000-000000000021'),
 'interval_label','Major truck service','interval_hours',10000,'last_service_hours',52000,'checklist_template_id','a2140000-0000-4000-8000-000000000040','covers_plan_ids',jsonb_build_array('a2140000-0000-4000-8000-000000000045')));
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role service_role;
select pg_temp.assert_true(public.run_recurring_generation()>=1,'unattended generator creates covering work without a signed-in manager');
select pg_temp.assert_true(public.run_recurring_generation()=0,'unattended overlapping cycles deduplicate');
select pg_temp.assert_true((select count(*)=1 from public.recurring_work_cycles
 where asset_id='a2140000-0000-4000-8000-000000000021'),'covered plan does not create competing work');
select pg_temp.assert_true((select w.created_by is null and w.assigned_to is null and j.planned_start is null from public.work_orders w join public.maintenance_job_records j on j.id=w.id where w.id=pg_temp.cycle_job('plan','a2140000-0000-4000-8000-000000000041')),'scheduler uses system authorship without scheduling or assigning');
select pg_temp.assert_true((select jsonb_array_length(checklist_snapshot)=2 from public.maintenance_job_records where id=pg_temp.cycle_job('plan','a2140000-0000-4000-8000-000000000041')),'unattended generation freezes both procedures');
select pg_temp.assert_true((select count(*)=1 and sum(required_qty)=1 from public.job_part_requirements where work_order_id=pg_temp.cycle_job('plan','a2140000-0000-4000-8000-000000000041')),'selected complete kit is captured once without summing the smaller kit');
reset role;
update public.pm_parts_requirements set qty=9,description='Future seal kit' where id='a2140000-0000-4000-8000-000000000080';
select pg_temp.assert_true((select required_qty=1 and description='Primary seal' from public.job_part_requirements where work_order_id=pg_temp.cycle_job('plan','a2140000-0000-4000-8000-000000000041') and source_requirement_id='a2140000-0000-4000-8000-000000000080'),'later kit edits do not rewrite frozen work requirements');
rollback;
