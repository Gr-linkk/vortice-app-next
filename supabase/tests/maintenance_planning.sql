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
select ('a0130000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'now013-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NOW013 '||right(id::text,1) where id::text like 'a0130000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0130000-0000-4000-8000-000000000010','Company A','a0130000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0130000-0000-4000-8000-000000000010'
 where id in ('a0130000-0000-4000-8000-000000000001','a0130000-0000-4000-8000-000000000002','a0130000-0000-4000-8000-000000000004','a0130000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0130000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a0130000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a0130000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0130000-0000-4000-8000-000000000021','a0130000-0000-4000-8000-000000000001','a0130000-0000-4000-8000-000000000020','A vessel'),
 ('a0130000-0000-4000-8000-000000000022','a0130000-0000-4000-8000-000000000003','a0130000-0000-4000-8000-000000000020','B vessel');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0130000-0000-4000-8000-000000000001',true);
-- The existing plans and newly booked work are one connected journey.
select public.save_maintenance_setup(gen_random_uuid(),'component','a0130000-0000-4000-8000-000000000040',0,
 '{"asset_id":"a0130000-0000-4000-8000-000000000021","label":"Generator","current_hours":240}');
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0130000-0000-4000-8000-000000000041',0,
 '{"asset_id":"a0130000-0000-4000-8000-000000000021","engine_id":"a0130000-0000-4000-8000-000000000040","interval_label":"250-hour service","interval_hours":250,"last_service_hours":0}');
select public.create_maintenance_job('a0130000-0000-4000-8000-000000000030',
 '{"asset_id":"a0130000-0000-4000-8000-000000000021","title":"Generator service","service_interval_id":"a0130000-0000-4000-8000-000000000041","due_date":"2026-09-10"}');
select public.create_maintenance_job('a0130000-0000-4000-8000-000000000031',
 '{"asset_id":"a0130000-0000-4000-8000-000000000021","title":"Inspect hydraulic seal"}');
select pg_temp.assert_true((select jsonb_array_length(public.maintenance_planning()->'jobs')=2),'manager discovers open work');
select pg_temp.assert_true((select (p->>'next_due_hours')::numeric=250 and (p->>'current_hours')::numeric=240 and (p->>'has_open_job')::boolean
 from jsonb_array_elements(public.maintenance_planning()->'plans') p),'existing component service drives plan feed');
select pg_temp.assert_true((select j->>'planned_start' is null and j->>'due_date'='2026-09-10' from public.maintenance_jobs('a0130000-0000-4000-8000-000000000030') j),'deadline is not a booking');

create function pg_temp.booking(job uuid, rev integer, op uuid, starts text, minutes integer, person uuid,
 extra jsonb default '{}') returns void language sql as $$
 select public.schedule_maintenance_job(job,rev,op,jsonb_build_object('planned_start',starts,'estimated_minutes',minutes,
  'assigned_to',person,'due_date','2026-09-10','priority','high','note','Plan around shutdown','allow_overlap',false)||extra)
$$;
select pg_temp.booking('a0130000-0000-4000-8000-000000000030',0,'a0130000-0000-4000-8000-000000000060','2026-09-07T08:00:00-04:00',120,'a0130000-0000-4000-8000-000000000002');
select pg_temp.booking('a0130000-0000-4000-8000-000000000030',0,'a0130000-0000-4000-8000-000000000060','2026-09-07T08:00:00-04:00',120,'a0130000-0000-4000-8000-000000000002');
select pg_temp.assert_true((select (j->>'revision')::integer=1 and (j->>'planned_start')::timestamptz='2026-09-07T12:00:00Z'::timestamptz
  and j->>'status'='assigned' and (j->>'estimated_minutes')::integer=120 from public.maintenance_jobs('a0130000-0000-4000-8000-000000000030') j),'replay is one booking and timezone normalized');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000030',0,'a0130000-0000-4000-8000-000000000060','2026-09-07T09:00:00-04:00',120,'a0130000-0000-4000-8000-000000000002')$q$,'different input');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000030',0,gen_random_uuid(),null,null,null)$q$,'changed');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000031',0,gen_random_uuid(),'2026-09-07T09:00:00-04:00',60,null)$q$,'overlaps');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000031',0,gen_random_uuid(),'2026-09-07T12:00:00Z',14,null)$q$,'duration');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000031',0,gen_random_uuid(),'2026-09-07T12:00:00Z',null,null)$q$,'duration');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000031',0,gen_random_uuid(),null,60,null)$q$,'duration');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000031',0,gen_random_uuid(),'infinity',60,null)$q$,'Invalid start');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000031',0,gen_random_uuid(),null,null,'a0130000-0000-4000-8000-000000000003')$q$,'Invalid assignee');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000031',0,gen_random_uuid(),null,null,'a0130000-0000-4000-8000-000000000006')$q$,'Invalid assignee');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000031',0,gen_random_uuid(),null,null,null,'{"note":""}')$q$,'Explain');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000031',0,gen_random_uuid(),null,null,null,'{"priority":"invalid"}')$q$,'priority');
-- Back-to-back work is safe; deliberate overlaps require acknowledgement.
select pg_temp.booking('a0130000-0000-4000-8000-000000000031',0,gen_random_uuid(),'2026-09-07T10:00:00-04:00',60,'a0130000-0000-4000-8000-000000000002');
select pg_temp.assert_true((select not bool_or((j->>'conflict')::boolean) from jsonb_array_elements(public.maintenance_planning()->'jobs') j),'back-to-back has no conflict');
select pg_temp.booking('a0130000-0000-4000-8000-000000000031',1,gen_random_uuid(),'2026-09-07T09:00:00-04:00',60,'a0130000-0000-4000-8000-000000000002','{"allow_overlap":true,"note":"Second technician assists during inspection"}');
select pg_temp.assert_true((select bool_and((j->>'conflict')::boolean) from jsonb_array_elements(public.maintenance_planning()->'jobs') j),'overlap stays visible after acknowledgement');
select pg_temp.booking('a0130000-0000-4000-8000-000000000031',2,gen_random_uuid(),null,null,null);
select pg_temp.assert_true((select j->>'planned_start' is null and j->>'status'='draft' and (j->>'revision')::integer=3
 from public.maintenance_jobs('a0130000-0000-4000-8000-000000000031') j),'unschedule preserves job and unassigns explicitly');

-- Role isolation uses the same rules as the execution screens.
select set_config('request.jwt.claim.sub','a0130000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(jsonb_array_length(public.maintenance_planning()->'jobs')=0 and jsonb_array_length(public.maintenance_planning()->'plans')=0,'other company sees no planning data');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000030',1,gen_random_uuid(),null,null,null)$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0130000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true(jsonb_array_length(public.maintenance_planning()->'jobs')=0,'operator gets no private job schedule');
select set_config('request.jwt.claim.sub','a0130000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(jsonb_array_length(public.maintenance_planning()->'jobs')=1 and jsonb_array_length(public.maintenance_planning()->'plans')=0,'mechanic sees assigned work only');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000030',1,gen_random_uuid(),null,null,null)$q$,'Access denied');
select public.change_maintenance_job('a0130000-0000-4000-8000-000000000030',1,gen_random_uuid(),'start','{}');
select set_config('request.jwt.claim.sub','a0130000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000030',2,gen_random_uuid(),null,null,null)$q$,'Pause running');
select public.change_maintenance_job('a0130000-0000-4000-8000-000000000030',2,gen_random_uuid(),'pause','{}');
select public.change_maintenance_job('a0130000-0000-4000-8000-000000000030',3,gen_random_uuid(),'submit','{"diagnosis":"Scheduled service","repair":"Changed filter and tested","completion_hours":250}');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000030',4,gen_random_uuid(),null,null,null)$q$,'Only open');
select public.change_maintenance_job('a0130000-0000-4000-8000-000000000030',4,gen_random_uuid(),'approve','{}');
select pg_temp.assert_true((select (p->>'next_due_hours')::numeric=500 and not (p->>'has_open_job')::boolean
 from jsonb_array_elements(public.maintenance_planning()->'plans') p),'approved booked service advances original plan exactly once');
select pg_temp.assert_true(jsonb_array_length(public.maintenance_planning()->'jobs')=1,'completed booking leaves forward queue');
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000030',5,gen_random_uuid(),null,null,null)$q$,'Only open');
reset role;
select pg_temp.assert_true((select count(*)=1 from public.maintenance_operations where id='a0130000-0000-4000-8000-000000000060'),'exactly one original scheduling event');
select pg_temp.assert_true((select count(*)=4 from public.maintenance_operations where kind='schedule_previous' and object_id in ('a0130000-0000-4000-8000-000000000030','a0130000-0000-4000-8000-000000000031')),'previous bookings are retained');
update public.client_capabilities set enabled=false where client_id='a0130000-0000-4000-8000-000000000001' and capability_key='maintenance_planning';
set local role authenticated;
select pg_temp.expect_error($q$select pg_temp.booking('a0130000-0000-4000-8000-000000000031',3,gen_random_uuid(),null,null,null)$q$,'Access denied');
select pg_temp.assert_true(jsonb_array_length(public.maintenance_planning()->'plans')=0,'disabled planning hides service planning');
rollback;
