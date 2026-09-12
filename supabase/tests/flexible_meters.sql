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
select ('a2150000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'next215-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NOW013 '||right(id::text,1) where id::text like 'a2150000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a2150000-0000-4000-8000-000000000010','Company A','a2150000-0000-4000-8000-000000000001');
update public.profiles set org_id='a2150000-0000-4000-8000-000000000010'
 where id in ('a2150000-0000-4000-8000-000000000001','a2150000-0000-4000-8000-000000000002','a2150000-0000-4000-8000-000000000004','a2150000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a2150000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a2150000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a2150000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a2150000-0000-4000-8000-000000000021','a2150000-0000-4000-8000-000000000001','a2150000-0000-4000-8000-000000000020','A vessel'),
 ('a2150000-0000-4000-8000-000000000022','a2150000-0000-4000-8000-000000000003','a2150000-0000-4000-8000-000000000020','B vessel');
set local role authenticated;
select set_config('request.jwt.claim.sub','a2150000-0000-4000-8000-000000000001',true);
select public.configure_asset_meter('a2150000-0000-4000-8000-000000000021','a2150000-0000-4000-8000-000000000060','km',62000);
select public.configure_asset_meter('a2150000-0000-4000-8000-000000000021','a2150000-0000-4000-8000-000000000060','km',62000);
select pg_temp.assert_true((select a.meter_unit='km' and e.current_hours=62000 and e.meter_unit='km' from public.assets a join public.asset_engines e on e.id=a.primary_meter_engine_id where a.id='a2150000-0000-4000-8000-000000000021'),'primary truck meter configured without conversion');
select public.save_maintenance_setup(gen_random_uuid(),'plan','a2150000-0000-4000-8000-000000000041',0,
 jsonb_build_object('asset_id','a2150000-0000-4000-8000-000000000021','engine_id',(select primary_meter_engine_id from public.assets where id='a2150000-0000-4000-8000-000000000021'),
 'interval_label','Truck service','interval_hours',10000,'last_service_hours',52000,'interval_months',12,'last_service_date',(current_date-interval '12 months')::date));
select public.create_maintenance_job('a2150000-0000-4000-8000-000000000030',
 '{"asset_id":"a2150000-0000-4000-8000-000000000021","title":"Truck service","service_interval_id":"a2150000-0000-4000-8000-000000000041"}');
select pg_temp.assert_true((select j->>'meter_unit'='km' and (j->>'hours_at_start')::numeric=62000 from public.maintenance_jobs('a2150000-0000-4000-8000-000000000030') j),'work retains original km');
select pg_temp.expect_error($q$select public.change_maintenance_job('a2150000-0000-4000-8000-000000000030',0,gen_random_uuid(),'start','{"start_meter":62000,"meter_unit":"mi"}')$q$,'Meter unit changed');
select public.change_maintenance_job('a2150000-0000-4000-8000-000000000030',0,gen_random_uuid(),'start','{"start_meter":62000,"meter_unit":"km"}');
select public.change_maintenance_job('a2150000-0000-4000-8000-000000000030',1,gen_random_uuid(),'pause','{}');
select pg_temp.expect_error($q$select public.change_maintenance_job('a2150000-0000-4000-8000-000000000030',2,gen_random_uuid(),'submit','{"diagnosis":"Regular service","repair":"Serviced and tested","completion_hours":62000,"meter_unit":"hours"}')$q$,'Meter unit changed');
select public.change_maintenance_job('a2150000-0000-4000-8000-000000000030',2,gen_random_uuid(),'submit','{"diagnosis":"Regular service","repair":"Serviced and tested","completion_hours":62000,"meter_unit":"km"}');
select public.change_maintenance_job('a2150000-0000-4000-8000-000000000030',3,'a2150000-0000-4000-8000-000000000061','approve','{}');
select public.change_maintenance_job('a2150000-0000-4000-8000-000000000030',3,'a2150000-0000-4000-8000-000000000061','approve','{}');
select pg_temp.assert_true((select (p->>'next_due_hours')::numeric=72000 and (p->>'next_due_date')::date=(current_date+interval '12 months')::date from jsonb_array_elements(public.maintenance_planning()->'plans') p where p->>'id'='a2150000-0000-4000-8000-000000000041'),'approved 62000km work advances to 72000km or 12 months');
select pg_temp.expect_error($q$select public.configure_asset_meter('a2150000-0000-4000-8000-000000000021',gen_random_uuid(),'mi',62000)$q$,'cannot change');
select pg_temp.expect_error($q$select public.record_manual_meter(gen_random_uuid(),(select primary_meter_engine_id from public.assets where id='a2150000-0000-4000-8000-000000000021'),'a2150000-0000-4000-8000-000000000021',62001,now())$q$,'unit-aware');
select set_config('request.jwt.claim.sub','a2150000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.configure_asset_meter('a2150000-0000-4000-8000-000000000021',gen_random_uuid(),'km',63000)$q$,'Access denied');
reset role;
select pg_temp.assert_true((select count(*)=1 from public.hour_logs where id='a2150000-0000-4000-8000-000000000061' and meter_unit='km' and hours=62000),'completion reading posted once');
select pg_temp.assert_true((select meter_unit='km' from public.service_reports where work_order_id='a2150000-0000-4000-8000-000000000030'),'report carries frozen unit');
select pg_temp.assert_true((select meter_unit='km' and snapshot->>'meter_unit'='km' and snapshot->'header'->>'meter_unit'='km' from public.saved_checklists where work_order_id='a2150000-0000-4000-8000-000000000030'),'completion snapshot carries frozen original unit');
select pg_temp.expect_error($q$update public.asset_engines set meter_unit='mi' where id=(select primary_meter_engine_id from public.assets where id='a2150000-0000-4000-8000-000000000021')$q$,'cannot change');
select pg_temp.expect_error($q$update public.hour_logs set meter_unit='mi' where id='a2150000-0000-4000-8000-000000000061'$q$,'cannot change');
rollback;
