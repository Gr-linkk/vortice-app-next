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

create function pg_temp.plans() returns setof public.asset_service_intervals language sql security definer as $$ select * from public.asset_service_intervals $$;
create function pg_temp.reminders() returns setof public.service_reminders language sql security definer as $$ select * from public.service_reminders $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.maintenance_next_hours(6700,250,'fixed',7000)=7000,'transition target');
select pg_temp.assert_true(public.maintenance_next_hours(7020,250,'fixed',7000)=7250,'late completion keeps milestone');
select pg_temp.assert_true(public.maintenance_next_hours(7020,250,'completion',null)=7270,'completion schedule follows meter');
select pg_temp.assert_true(public.maintenance_next_hours(7850,250,'fixed',7000)=8000,'late completion skips past milestones without fake completions');
select pg_temp.assert_true(public.maintenance_next_date('2026-10-20',6,'completion',null)='2027-04-20','completion calendar');
select pg_temp.assert_true(public.maintenance_next_date('2026-10-20',6,'fixed','2026-10-01')='2027-04-01','fixed calendar');
select pg_temp.assert_true(public.maintenance_next_date('2028-02-29',1,'fixed','2028-01-31')='2028-03-31','month end anchor survives leap February');
select public.save_maintenance_setup(gen_random_uuid(),'component','a0140000-0000-4000-8000-000000000040',0,
 '{"asset_id":"a0140000-0000-4000-8000-000000000021","label":"Main engine","current_hours":6700}');
select public.save_maintenance_setup(gen_random_uuid(),'component','a0140000-0000-4000-8000-000000000042',0,
 '{"asset_id":"a0140000-0000-4000-8000-000000000021","label":"Generator","current_hours":600}');
create function pg_temp.plan_data() returns jsonb language sql as $$ select
 '{"asset_id":"a0140000-0000-4000-8000-000000000021","engine_id":"a0140000-0000-4000-8000-000000000040",
 "interval_label":"250 hour service","interval_hours":250,"last_service_hours":6700,"recurrence_mode":"fixed","anchor_hours":7000}'::jsonb $$;
select public.save_maintenance_setup('a0140000-0000-4000-8000-000000000090','plan','a0140000-0000-4000-8000-000000000041',0,pg_temp.plan_data());
select public.save_maintenance_setup('a0140000-0000-4000-8000-000000000090','plan','a0140000-0000-4000-8000-000000000041',0,pg_temp.plan_data());
select pg_temp.assert_true((select next_due_hours=7000 and last_service_hours=6700 from pg_temp.plans() where id='a0140000-0000-4000-8000-000000000041'),'setup preserves baseline and uses explicit transition');
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000041',99,pg_temp.plan_data())$q$,'changed');
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000041',0,pg_temp.plan_data()||'{"anchor_hours":7100}')$q$,'Explain');
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000043',0,
 pg_temp.plan_data()||'{"engine_id":"a0140000-0000-4000-8000-000000000042","last_service_hours":600,"anchor_hours":750,"interval_label":"Generator"}');
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000044',0,
 pg_temp.plan_data()||'{"covers_plan_ids":["a0140000-0000-4000-8000-000000000043"]}')$q$,'this component');
-- A larger service includes the explicitly selected smaller plan.
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000044',0,
 pg_temp.plan_data()||'{"interval_label":"500 hour service","interval_hours":500,"anchor_hours":7500,"covers_plan_ids":["a0140000-0000-4000-8000-000000000041"]}');
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000041',0,
 pg_temp.plan_data()||'{"change_reason":"Cycle test","covers_plan_ids":["a0140000-0000-4000-8000-000000000044"]}')$q$,'covered plan');
-- Calendar-only and combined recurrence appear in due attention without fake hour targets.
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000045',0,
 pg_temp.plan_data()||jsonb_build_object('interval_hours',0,'interval_months',6,'anchor_date',(current_date-1)::text,'interval_label','Calendar inspection'));
select pg_temp.assert_true((select next_due_hours is null and next_due_date=current_date-1 from pg_temp.plans() where id='a0140000-0000-4000-8000-000000000045'),'calendar-only has no artificial meter target');
select pg_temp.assert_true(not exists(select 1 from pg_temp.reminders() where service_interval_id='a0140000-0000-4000-8000-000000000045'),'calendar-only has no hours reminder');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.fleet_attention(current_date,'overdue_service')->'items') i where i->>'id'='a0140000-0000-4000-8000-000000000045'),'calendar due appears in fleet attention');
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000046',0,
 pg_temp.plan_data()||jsonb_build_object('interval_months',6,'anchor_date',(current_date-1)::text,'interval_label','Combined service'));
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.fleet_attention(current_date,'overdue_service')->'items') i where i->>'id'='a0140000-0000-4000-8000-000000000046'),'combined due by calendar before meter');
-- Foreign company and mechanic cannot edit recurrence, including coverage.
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000041',0,pg_temp.plan_data())$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000041',0,pg_temp.plan_data())$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000001',true);
create function pg_temp.job_data(plan_id uuid) returns jsonb language sql as $$ select jsonb_build_object(
 'asset_id','a0140000-0000-4000-8000-000000000021','service_interval_id',plan_id,'job_type','preventative',
 'title','Scheduled service','assigned_to','a0140000-0000-4000-8000-000000000002') $$;
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000050',pg_temp.job_data('a0140000-0000-4000-8000-000000000041'));
select pg_temp.expect_error($q$select public.create_maintenance_job(gen_random_uuid(),pg_temp.job_data('a0140000-0000-4000-8000-000000000044'))$q$,'open job');
create function pg_temp.finish(job uuid, meter numeric, answer_items boolean default true) returns void language plpgsql as $$
declare r integer; answers jsonb;
begin
 select (value->>'revision')::integer into r from public.maintenance_jobs(job) value;
 select coalesce(jsonb_object_agg(item->>'id',jsonb_build_object('result','pass')),'{}') into answers
 from public.maintenance_jobs(job) data, lateral jsonb_array_elements(data->'checklist_snapshot') item;
 perform set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000002',true);
 perform public.change_maintenance_job(job,r,gen_random_uuid(),'start','{}');
 perform public.change_maintenance_job(job,r+1,gen_random_uuid(),'pause','{}');
 perform public.change_maintenance_job(job,r+2,gen_random_uuid(),'submit',jsonb_build_object('diagnosis','Scheduled service','repair','Completed all required work','completion_hours',meter,'answers',case when answer_items then answers else '{}'::jsonb end));
 perform set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000001',true);
 perform public.change_maintenance_job(job,r+3,gen_random_uuid(),'approve','{}');
end $$;
select pg_temp.finish('a0140000-0000-4000-8000-000000000050',7020);
select pg_temp.assert_true((select next_due_hours=7250 and last_service_hours=7020 from pg_temp.plans() where id='a0140000-0000-4000-8000-000000000041'),'approved late work retains 7250 milestone');
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000041',1,
 pg_temp.plan_data()||'{"last_service_hours":7020,"interval_label":"Renamed service"}');
select pg_temp.assert_true((select next_due_hours=7250 from pg_temp.plans() where id='a0140000-0000-4000-8000-000000000041'),'rename does not reset to old anchor');
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000051',pg_temp.job_data('a0140000-0000-4000-8000-000000000041'));
select pg_temp.finish('a0140000-0000-4000-8000-000000000051',7240);
select pg_temp.assert_true((select next_due_hours=7500 from pg_temp.plans() where id='a0140000-0000-4000-8000-000000000041'),'early work satisfies current occurrence');
reset role;
insert into public.checklist_templates(id,asset_type_id,name,checklist_type) values
 ('a0140000-0000-4000-8000-000000000060','a0140000-0000-4000-8000-000000000020','250 hour checklist','pm');
insert into public.checklist_items(id,template_id,description_en,requires_photo) values
 ('a0140000-0000-4000-8000-000000000061','a0140000-0000-4000-8000-000000000060','Inspect oil filter',false);
set local role authenticated;
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000041',3,
 pg_temp.plan_data()||'{"last_service_hours":7240,"checklist_template_id":"a0140000-0000-4000-8000-000000000060"}');
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000052',pg_temp.job_data('a0140000-0000-4000-8000-000000000044'));
select pg_temp.assert_true((select jsonb_array_length(value->'checklist_snapshot')=1 from public.maintenance_jobs('a0140000-0000-4000-8000-000000000052') value),'larger job contains smaller checklist tasks');
select pg_temp.expect_error($q$select pg_temp.finish('a0140000-0000-4000-8000-000000000052',7500,false)$q$,'Complete every checklist');
select pg_temp.expect_error($q$select public.create_maintenance_job(gen_random_uuid(),pg_temp.job_data('a0140000-0000-4000-8000-000000000041'))$q$,'open job');
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000041',4,pg_temp.plan_data()||'{"last_service_hours":7240}')$q$,'open job');
select pg_temp.finish('a0140000-0000-4000-8000-000000000052',7500);
select pg_temp.assert_true((select next_due_hours=7750 and last_service_hours=7500 from pg_temp.plans() where id='a0140000-0000-4000-8000-000000000041'),'500 service satisfies 250');
select pg_temp.assert_true((select next_due_hours=8000 from pg_temp.plans() where id='a0140000-0000-4000-8000-000000000044'),'500 service advances its own milestone');
select pg_temp.assert_true((select next_due_hours=750 and last_service_hours=600 from pg_temp.plans() where id='a0140000-0000-4000-8000-000000000043'),'other component unchanged');
select pg_temp.assert_true((select due_at_hours=7750 from pg_temp.reminders() where service_interval_id='a0140000-0000-4000-8000-000000000041'),'hour reminder matches recurrence');
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000053',pg_temp.job_data('a0140000-0000-4000-8000-000000000045'));
select pg_temp.finish('a0140000-0000-4000-8000-000000000053',null);
select pg_temp.assert_true((select next_due_hours is null and last_service_date=current_date and next_due_date=public.maintenance_next_date(current_date,6,'fixed',current_date-1)
 from pg_temp.plans() where id='a0140000-0000-4000-8000-000000000045'),'calendar approval advances date without hour reminder');
-- Reopening reserves the completed job's own and frozen included plans.
-- Each scenario rolls back its changes so it tests the same completed history.
savepoint reopen_larger;
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000054',pg_temp.job_data('a0140000-0000-4000-8000-000000000041'));
select pg_temp.expect_error($q$select public.change_maintenance_job('a0140000-0000-4000-8000-000000000052',4,gen_random_uuid(),'reopen','{"note":"Inspect service again"}')$q$,'open job');
select pg_temp.assert_true((select value->>'status'='closed' and (value->>'revision')::integer=4 from public.maintenance_jobs('a0140000-0000-4000-8000-000000000052') value),'rejected larger reopen leaves completed job unchanged');
rollback to savepoint reopen_larger;

savepoint reopen_smaller;
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000054',pg_temp.job_data('a0140000-0000-4000-8000-000000000044'));
select pg_temp.expect_error($q$select public.change_maintenance_job('a0140000-0000-4000-8000-000000000051',4,gen_random_uuid(),'reopen','{"note":"Inspect service again"}')$q$,'open job');
rollback to savepoint reopen_smaller;

savepoint reopen_shared_coverage;
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000047',0,
 pg_temp.plan_data()||'{"interval_label":"1000 hour service","interval_hours":1000,"last_service_hours":7500,"anchor_hours":8500,"covers_plan_ids":["a0140000-0000-4000-8000-000000000041"]}');
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000054',pg_temp.job_data('a0140000-0000-4000-8000-000000000047'));
select pg_temp.expect_error($q$select public.change_maintenance_job('a0140000-0000-4000-8000-000000000052',4,gen_random_uuid(),'reopen','{"note":"Inspect service again"}')$q$,'open job');
rollback to savepoint reopen_shared_coverage;

savepoint reopen_frozen_coverage;
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0140000-0000-4000-8000-000000000044',1,
 pg_temp.plan_data()||'{"interval_label":"500 hour service","interval_hours":500,"last_service_hours":7500,"anchor_hours":7500,"covers_plan_ids":[],"change_reason":"Separate future services"}');
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000054',pg_temp.job_data('a0140000-0000-4000-8000-000000000041'));
select pg_temp.expect_error($q$select public.change_maintenance_job('a0140000-0000-4000-8000-000000000052',4,gen_random_uuid(),'reopen','{"note":"Inspect original service again"}')$q$,'open job');
rollback to savepoint reopen_frozen_coverage;

savepoint reopen_unrelated;
-- A different plan on the same component remains independent.
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000054',pg_temp.job_data('a0140000-0000-4000-8000-000000000045'));
select public.change_maintenance_job('a0140000-0000-4000-8000-000000000052',4,'a0140000-0000-4000-8000-000000000091','reopen','{"note":"Inspect service again"}');
select public.change_maintenance_job('a0140000-0000-4000-8000-000000000052',4,'a0140000-0000-4000-8000-000000000091','reopen','{"note":"Inspect service again"}');
select pg_temp.assert_true((select value->>'status'='in_progress' and (value->>'revision')::integer=5 from public.maintenance_jobs('a0140000-0000-4000-8000-000000000052') value),'unrelated open job allows reopening and replay does not repeat it');
select pg_temp.expect_error($q$select public.create_maintenance_job(gen_random_uuid(),pg_temp.job_data('a0140000-0000-4000-8000-000000000041'))$q$,'open job');
select pg_temp.finish('a0140000-0000-4000-8000-000000000052',7500);
select pg_temp.assert_true((select next_due_hours=8000 from pg_temp.plans() where id='a0140000-0000-4000-8000-000000000044'),'reapproval does not consume another larger occurrence');
select pg_temp.assert_true((select next_due_hours=7750 from pg_temp.plans() where id='a0140000-0000-4000-8000-000000000041'),'reapproval does not consume another included occurrence');
rollback to savepoint reopen_unrelated;

reset role;
select pg_temp.assert_true(exists(select 1 from public.saved_checklists where work_order_id='a0140000-0000-4000-8000-000000000052'
 and snapshot->'header'->'covered_plan_ids' ? 'a0140000-0000-4000-8000-000000000041'),'approved history records included services');
rollback;
