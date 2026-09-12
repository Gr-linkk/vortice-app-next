begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.must_fail(command text) returns void language plpgsql as $$
begin begin execute command; exception when others then return; end; raise exception 'Unexpected success: %',command; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('a0191000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'asset-create-'||n||'@example.invalid',
 case when n<=3 then '{"onboarding_v2":true}'::jsonb else '{}'::jsonb end from generate_series(1,5)n;
update public.profiles set role='owner' where id='a0191000-0000-4000-8000-000000000004';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0191000-0000-4000-8000-000000000011','Atomic A','a0191000-0000-4000-8000-000000000001'),
 ('a0191000-0000-4000-8000-000000000012','Atomic B','a0191000-0000-4000-8000-000000000002');
insert into public.organization_memberships(organization_id,profile_id,roles) values
 ('a0191000-0000-4000-8000-000000000011','a0191000-0000-4000-8000-000000000001',array['company_owner']),
 ('a0191000-0000-4000-8000-000000000012','a0191000-0000-4000-8000-000000000002',array['company_owner']),
 ('a0191000-0000-4000-8000-000000000011','a0191000-0000-4000-8000-000000000003',array['operator']);
insert into public.organization_identity_context values
 ('a0191000-0000-4000-8000-000000000001','a0191000-0000-4000-8000-000000000011'),
 ('a0191000-0000-4000-8000-000000000002','a0191000-0000-4000-8000-000000000012'),
 ('a0191000-0000-4000-8000-000000000003','a0191000-0000-4000-8000-000000000011');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0191000-0000-4000-8000-000000000001',true);
do $$ declare data jsonb:='{"id":"a0191000-0000-4000-8000-000000000021","client_id":"a0191000-0000-4000-8000-000000000001","asset_type_id":"00000000-0000-0000-0000-000000000023","name":"Mini excavator","meter_unit":"hours"}'; engine jsonb:='{"label":"Main Engine","kind":"main","make":"Example","serial_number":"ENG-001","meter_unit":"hours"}'; result uuid;
begin
 perform pg_temp.must_fail(format('select public.create_asset_with_engine(%L::jsonb,%L::jsonb)',data,jsonb_set(engine,'{kind}','"invalid"')));
 perform pg_temp.assert_true(not exists(select 1 from public.assets where id=(data->>'id')::uuid),'bad optional engine rolls the asset back');
 result:=public.create_asset_with_engine(data,engine);
 perform pg_temp.assert_true(public.create_asset_with_engine(data,engine)=result,'lost-response retry returns same asset');
 perform pg_temp.assert_true((select count(*)=1 from public.asset_engines where asset_id=result),'retry creates one engine');
 perform pg_temp.must_fail(format('select public.create_asset_with_engine(%L::jsonb,%L::jsonb)',jsonb_set(data,'{name}','"Changed retry"'),engine));
 perform pg_temp.assert_true((select name='Mini excavator' and meter_unit='hours' from public.assets where id=result),'changed retry cannot modify the accepted asset');
end $$;
-- Modern managers can use the same Add/Edit engine flow after creation.
insert into public.asset_engines(asset_id,label,kind) values('a0191000-0000-4000-8000-000000000021','Auxiliary','auxiliary');
update public.asset_engines set make='Updated' where asset_id='a0191000-0000-4000-8000-000000000021' and label='Auxiliary';
select pg_temp.assert_true((select make='Updated' from public.asset_engines where asset_id='a0191000-0000-4000-8000-000000000021' and label='Auxiliary'),'modern manager edits own engines');
select set_config('request.jwt.claim.sub','a0191000-0000-4000-8000-000000000003',true);
select pg_temp.must_fail($q$select public.create_asset_with_engine('{"id":"a0191000-0000-4000-8000-000000000022","client_id":"a0191000-0000-4000-8000-000000000001","asset_type_id":"00000000-0000-0000-0000-000000000023","name":"Operator creation"}')$q$);
select pg_temp.must_fail($q$insert into public.asset_engines(asset_id,label) values('a0191000-0000-4000-8000-000000000021','Denied')$q$);
update public.asset_engines set make='Forbidden' where asset_id='a0191000-0000-4000-8000-000000000021';
select pg_temp.assert_true(not exists(select 1 from public.asset_engines where make='Forbidden'),'operator cannot edit engines');
select set_config('request.jwt.claim.sub','a0191000-0000-4000-8000-000000000002',true);
select pg_temp.must_fail($q$select public.create_asset_with_engine('{"id":"a0191000-0000-4000-8000-000000000023","client_id":"a0191000-0000-4000-8000-000000000001","asset_type_id":"00000000-0000-0000-0000-000000000023","name":"Foreign company"}')$q$);
select pg_temp.assert_true(not exists(select 1 from public.asset_engines where asset_id='a0191000-0000-4000-8000-000000000021'),'other company cannot read engines');
select set_config('request.jwt.claim.sub','a0191000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true(not exists(select 1 from public.asset_engines where asset_id='a0191000-0000-4000-8000-000000000021'),'legacy owner cannot read new company engines');
select pg_temp.must_fail($q$select public.create_asset_with_engine('{"id":"a0191000-0000-4000-8000-000000000024","client_id":"a0191000-0000-4000-8000-000000000001","asset_type_id":"00000000-0000-0000-0000-000000000023","name":"Legacy foreign"}')$q$);
select public.create_asset_with_engine('{"id":"a0191000-0000-4000-8000-000000000025","client_id":"a0191000-0000-4000-8000-000000000005","asset_type_id":"00000000-0000-0000-0000-000000000023","name":"Legacy allowed","meter_unit":"km"}');
select pg_temp.assert_true((select meter_unit='km' from public.assets where id='a0191000-0000-4000-8000-000000000025'),'legacy creator retains explicit distance meter');
reset role;
select pg_temp.assert_true((select count(*)=2 from public.closeout_operations where kind='asset_create' and actor_id::text like 'a0191000-%'),'only accepted operations leave receipts');
rollback;
