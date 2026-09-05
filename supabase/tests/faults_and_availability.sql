-- Run as a transaction against the isolated Next project; always rolled back.
begin;

create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$ begin
  if ok is distinct from true then raise exception 'FAIL: %', label; end if;
end $$;
create function pg_temp.expect_error(command text, expected text) returns void
language plpgsql as $$ begin
  begin
    execute command;
  exception when others then
    if position(expected in sqlerrm) > 0 then return; end if;
    raise;
  end;
  raise exception 'Expected error containing: %', expected;
end $$;

-- No real customer fixtures or credentials; the auth trigger does not send mail.
insert into auth.users(id, email, raw_user_meta_data) values
 ('a0030000-0000-4000-8000-000000000001', 'now003-owner@example.invalid', '{}'),
 ('a0030000-0000-4000-8000-000000000002', 'now003-manager@example.invalid', '{}'),
 ('a0030000-0000-4000-8000-000000000003', 'now003-mechanic@example.invalid', '{}'),
 ('a0030000-0000-4000-8000-000000000004', 'now003-operator@example.invalid', '{}'),
 ('a0030000-0000-4000-8000-000000000005', 'now003-outsider@example.invalid', '{}');
update public.profiles set role = case right(id::text,1)
 when '1' then 'owner' when '2' then 'client' when '3' then 'client_mechanic'
 when '4' then 'operator' else 'client' end,
 full_name = 'NOW003 test ' || right(id::text,1)
where id::text like 'a0030000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0030000-0000-4000-8000-000000000010','NOW003 test org','a0030000-0000-4000-8000-000000000002');
update public.profiles set org_id='a0030000-0000-4000-8000-000000000010'
where id in ('a0030000-0000-4000-8000-000000000002',
 'a0030000-0000-4000-8000-000000000003','a0030000-0000-4000-8000-000000000004');
insert into public.asset_types(id,category,name) values
 ('a0030000-0000-4000-8000-000000000020','test','NOW003 fixture');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0030000-0000-4000-8000-000000000021','a0030000-0000-4000-8000-000000000002',
  'a0030000-0000-4000-8000-000000000020','NOW003 pump'),
 ('a0030000-0000-4000-8000-000000000022','a0030000-0000-4000-8000-000000000005',
  'a0030000-0000-4000-8000-000000000020','NOW003 other fleet');

set local role authenticated;
select set_config('request.jwt.claim.sub','a0030000-0000-4000-8000-000000000004',true);
select public.report_maintenance_fault('a0030000-0000-4000-8000-000000000030',
 'a0030000-0000-4000-8000-000000000021','Hydraulic leak at pump','urgent');
select public.report_maintenance_fault('a0030000-0000-4000-8000-000000000030',
 'a0030000-0000-4000-8000-000000000021','Hydraulic leak at pump','urgent');
select pg_temp.assert_true((select count(*) = 1 from public.maintenance_fault_events
 where fault_id='a0030000-0000-4000-8000-000000000030'),'report retry creates one event');
select pg_temp.expect_error($q$select public.report_maintenance_fault(
 'a0030000-0000-4000-8000-000000000031','a0030000-0000-4000-8000-000000000022',
 'Cross-company fault','normal')$q$,'Access denied');
select pg_temp.expect_error($q$update public.maintenance_requests set status='dismissed'
 where id='a0030000-0000-4000-8000-000000000030'$q$,'permission denied');
select pg_temp.expect_error($q$select public.change_asset_availability(
 'a0030000-0000-4000-8000-000000000021',0,'a0030000-0000-4000-8000-000000000060',
 'out_of_service','Operator tries to override state')$q$,'Access denied');
select pg_temp.assert_true((select count(*)=1 from public.maintenance_fleet() a
 where a->>'id' like 'a0030000-%'),'operator inherits exactly their own fleet');

select set_config('request.jwt.claim.sub','a0030000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.update_maintenance_fault(
 'a0030000-0000-4000-8000-000000000030',0,'a0030000-0000-4000-8000-000000000061',
 'start','Unassigned mechanic')$q$,'Access denied');

select set_config('request.jwt.claim.sub','a0030000-0000-4000-8000-000000000002',true);
select public.change_asset_availability('a0030000-0000-4000-8000-000000000021',0,
 'a0030000-0000-4000-8000-000000000040','out_of_service','Pump isolated for leak');
select public.change_asset_availability('a0030000-0000-4000-8000-000000000021',0,
 'a0030000-0000-4000-8000-000000000040','out_of_service','Pump isolated for leak');
select pg_temp.expect_error($q$select public.change_asset_availability(
 'a0030000-0000-4000-8000-000000000021',1,'a0030000-0000-4000-8000-000000000041',
 'available','Return to service')$q$,'urgent');
select public.update_maintenance_fault('a0030000-0000-4000-8000-000000000030',0,
 'a0030000-0000-4000-8000-000000000050','assign','Inspect pump seal',
 'a0030000-0000-4000-8000-000000000003');
select public.update_maintenance_fault('a0030000-0000-4000-8000-000000000030',0,
 'a0030000-0000-4000-8000-000000000050','assign','Inspect pump seal',
 'a0030000-0000-4000-8000-000000000003');
select pg_temp.assert_true((select revision=1 from public.maintenance_requests
 where id='a0030000-0000-4000-8000-000000000030'),'assignment retry does not advance revision');
select pg_temp.expect_error($q$select public.update_maintenance_fault(
 'a0030000-0000-4000-8000-000000000030',0,'a0030000-0000-4000-8000-000000000050',
 'assign','Changed note','a0030000-0000-4000-8000-000000000003')$q$,'already used');
select pg_temp.expect_error($q$select public.update_maintenance_fault(
 'a0030000-0000-4000-8000-000000000030',1,'a0030000-0000-4000-8000-000000000062',
 'assign','Wrong fleet','a0030000-0000-4000-8000-000000000005')$q$,'eligible mechanic');
select pg_temp.expect_error($q$select public.update_maintenance_fault(
 'a0030000-0000-4000-8000-000000000030',1,'a0030000-0000-4000-8000-000000000063',
 'resolve','Premature closure')$q$,'submitted for review');

select set_config('request.jwt.claim.sub','a0030000-0000-4000-8000-000000000003',true);
select public.update_maintenance_fault('a0030000-0000-4000-8000-000000000030',1,
 'a0030000-0000-4000-8000-000000000051','start','Starting repair');
select pg_temp.expect_error($q$select public.update_maintenance_fault(
 'a0030000-0000-4000-8000-000000000030',1,'a0030000-0000-4000-8000-000000000052',
 'note','Stale note')$q$,'changed');
select public.update_maintenance_fault('a0030000-0000-4000-8000-000000000030',2,
 'a0030000-0000-4000-8000-000000000053','submit','Seal replaced and pressure tested');
select pg_temp.expect_error($q$select public.update_maintenance_fault(
 'a0030000-0000-4000-8000-000000000030',3,'a0030000-0000-4000-8000-000000000054',
 'resolve','Self approval')$q$,'Access denied');

select set_config('request.jwt.claim.sub','a0030000-0000-4000-8000-000000000005',true);
select pg_temp.assert_true((select count(*) = 0 from public.maintenance_requests
 where id='a0030000-0000-4000-8000-000000000030'),'other company cannot read fault');
select pg_temp.assert_true((select count(*) = 0 from public.asset_operating_states
 where asset_id='a0030000-0000-4000-8000-000000000021'),'other company cannot read availability');
select pg_temp.assert_true((select count(*) = 0 from public.maintenance_fault_events
 where fault_id='a0030000-0000-4000-8000-000000000030'),'other company cannot read event history');

select set_config('request.jwt.claim.sub','a0030000-0000-4000-8000-000000000002',true);
select public.change_asset_availability('a0030000-0000-4000-8000-000000000021',1,
 'a0030000-0000-4000-8000-000000000042','under_maintenance','Workshop repair');
select pg_temp.assert_true((select unavailable_since =
 (select created_at from public.asset_availability_events where
 operation_id='a0030000-0000-4000-8000-000000000040') from public.asset_operating_states
 where asset_id='a0030000-0000-4000-8000-000000000021'),'downtime start survives state change');
select public.update_maintenance_fault('a0030000-0000-4000-8000-000000000030',3,
 'a0030000-0000-4000-8000-000000000055','resolve','Verified pressure and no leaks');
select public.change_asset_availability('a0030000-0000-4000-8000-000000000021',2,
 'a0030000-0000-4000-8000-000000000043','available','Verified and released');
select pg_temp.assert_true((select unavailable_since is null and revision=3
 from public.asset_operating_states where asset_id='a0030000-0000-4000-8000-000000000021'),
 'return to service closes outage and records revision');
select pg_temp.assert_true((select count(*)=3 from public.asset_availability_events
 where asset_id='a0030000-0000-4000-8000-000000000021'),'availability retry is idempotent');
select pg_temp.expect_error($q$select public.change_asset_availability(
 'a0030000-0000-4000-8000-000000000021',2,'a0030000-0000-4000-8000-000000000064',
 'restricted','Stale state update')$q$,'changed');

-- Simulate an earlier outage without sleeping, entirely in the rolled-back fixture.
reset role;
update public.asset_operating_states set operating_state='out_of_service',
 unavailable_since=now()-interval '2 hours',downtime_seconds=3600
 where asset_id='a0030000-0000-4000-8000-000000000021';
set local role authenticated;
select public.change_asset_availability('a0030000-0000-4000-8000-000000000021',3,
 'a0030000-0000-4000-8000-000000000065','under_maintenance','Continue outage');
select public.change_asset_availability('a0030000-0000-4000-8000-000000000021',4,
 'a0030000-0000-4000-8000-000000000066','restricted','Released for limited operation');
select pg_temp.assert_true((select downtime_seconds=10800 and unavailable_since is null
 from public.asset_operating_states where asset_id='a0030000-0000-4000-8000-000000000021'),
 'completed downtime preserves earlier episodes and adds the current outage once');

select public.report_maintenance_fault('a0030000-0000-4000-8000-000000000070',
 'a0030000-0000-4000-8000-000000000021','Work light intermittent','normal');
select set_config('request.jwt.claim.sub','a0030000-0000-4000-8000-000000000001',true);
select public.update_maintenance_fault('a0030000-0000-4000-8000-000000000070',0,
 'a0030000-0000-4000-8000-000000000071','create_work_order','Inspect light circuit');
select public.update_maintenance_fault('a0030000-0000-4000-8000-000000000070',0,
 'a0030000-0000-4000-8000-000000000071','create_work_order','Inspect light circuit');
select public.update_maintenance_fault('a0030000-0000-4000-8000-000000000070',1,
 'a0030000-0000-4000-8000-000000000072','create_work_order','Second attempt after refresh');
select pg_temp.assert_true((select count(*)=1 from public.work_orders
 where asset_id='a0030000-0000-4000-8000-000000000021'),'at most one linked work order');
select pg_temp.assert_true((select status='open' and converted_to_work_order_id is not null
 from public.maintenance_requests where id='a0030000-0000-4000-8000-000000000070'),
 'linking a job does not resolve the fault');
select pg_temp.expect_error($q$insert into public.asset_availability_events
 (asset_id,operation_id,from_state,to_state,note,actor_name) values
 ('a0030000-0000-4000-8000-000000000021','a0030000-0000-4000-8000-000000000080',
 'unknown','available','Forged review','Fake')$q$,'permission denied');
set local role anon;
select pg_temp.expect_error($q$select public.maintenance_fleet()$q$,'permission denied');

rollback;
select 'NOW003 database contracts passed; all fixture changes rolled back' as result;
