begin;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'FAIL: %',label; end if;
end $$;

insert into auth.users(id,email,raw_user_meta_data) values
 ('a0080000-0000-4000-8000-000000000001','now008-owner@example.invalid','{}'),
 ('a0080000-0000-4000-8000-000000000002','now008-client@example.invalid','{}'),
 ('a0080000-0000-4000-8000-000000000003','now008-other@example.invalid','{}'),
 ('a0080000-0000-4000-8000-000000000004','now008-tech@example.invalid','{}'),
 ('a0080000-0000-4000-8000-000000000005','now008-mechanic@example.invalid','{}'),
 ('a0080000-0000-4000-8000-000000000006','now008-operator@example.invalid','{}');
update public.profiles set role=case right(id::text,1) when '1' then 'owner'
 when '4' then 'employee' when '5' then 'client_mechanic' when '6' then 'operator' else 'client' end
 where id::text like 'a0080000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0080000-0000-4000-8000-000000000008','NOW008 company','a0080000-0000-4000-8000-000000000002');
update public.profiles set org_id='a0080000-0000-4000-8000-000000000008'
 where id in ('a0080000-0000-4000-8000-000000000002','a0080000-0000-4000-8000-000000000005','a0080000-0000-4000-8000-000000000006');
insert into public.asset_types(id,category,name) values
 ('a0080000-0000-4000-8000-000000000010','test','Test machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0080000-0000-4000-8000-000000000011','a0080000-0000-4000-8000-000000000002',
  'a0080000-0000-4000-8000-000000000010','NOW008 test machine');
insert into public.work_orders(id,title,asset_id,client_id,created_by,status,job_type) values
 ('a0080000-0000-4000-8000-000000000020','NOW008 provider inspection',
  'a0080000-0000-4000-8000-000000000011','a0080000-0000-4000-8000-000000000002',
  'a0080000-0000-4000-8000-000000000001','closed','repair');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000001',true);
insert into public.service_reports(id,work_order_id,complaint) values
 ('a0080000-0000-4000-8000-000000000021','a0080000-0000-4000-8000-000000000020','First report');
insert into public.service_reports(id,work_order_id,complaint,tech_signature_url,signed_at) values
 ('a0080000-0000-4000-8000-000000000022','a0080000-0000-4000-8000-000000000020',
  'Signed follow-up','test-signature.png',now())
 on conflict(id) do update set complaint=excluded.complaint;
-- Retrying one report ID must not create a third report or overwrite the first.
insert into public.service_reports(id,work_order_id,complaint) values
 ('a0080000-0000-4000-8000-000000000022','a0080000-0000-4000-8000-000000000020','Signed follow-up')
 on conflict(id) do update set complaint=excluded.complaint;
select pg_temp.assert_true((select count(*)=2 from public.service_reports
 where work_order_id='a0080000-0000-4000-8000-000000000020'),'provider reports remain separate');
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select count(*)=2 from public.service_reports
 where work_order_id='a0080000-0000-4000-8000-000000000020'),'client reads both closed provider reports');
select pg_temp.assert_true((select count(*)=2 from public.provider_service_reports(
 p_asset=>'a0080000-0000-4000-8000-000000000011')),'client asset report list uses checked projection');
select pg_temp.assert_true((select count(*)=0 from public.work_orders
 where id='a0080000-0000-4000-8000-000000000020'),'client cannot read provider-only work-order fields');
select pg_temp.assert_true(public.provider_report_media_readable('signatures','test-signature.png'),
 'client can read signed report media');
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.provider_service_reports()),'other company sees no reports');
select pg_temp.assert_true(not public.provider_report_media_readable('signatures','test-signature.png'),
 'other company cannot read known signature path');
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000005',true);
select pg_temp.assert_true((select count(*)=2 from public.provider_service_reports()),'company mechanic reads company reports');
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000006',true);
select pg_temp.assert_true((select count(*)=0 from public.provider_service_reports()),'operator cannot read provider reports');
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true((select count(*)=1 from public.assets
 where id='a0080000-0000-4000-8000-000000000011'),'provider technician can read assigned asset label without old cache');
select pg_temp.assert_true((select count(*)=2 from public.provider_service_reports(
 p_asset=>'a0080000-0000-4000-8000-000000000011')),'provider technician reads reports');

select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000001',true);
select public.create_maintenance_job('a0080000-0000-4000-8000-000000000030',
 '{"asset_id":"a0080000-0000-4000-8000-000000000011","title":"NOW008 internal repair"}');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000030',0,gen_random_uuid(),'start','{}');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000030',1,gen_random_uuid(),'pause','{}');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000030',2,gen_random_uuid(),'save_report',
 '{"diagnosis":"Test diagnosis","repair":"First revision"}');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000030',3,gen_random_uuid(),'submit',
 '{"diagnosis":"Test diagnosis","repair":"Final revision"}');
select pg_temp.assert_true((select count(*)=0 from public.service_reports
 where work_order_id='a0080000-0000-4000-8000-000000000030'),'managed report remains RPC only');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000030',4,gen_random_uuid(),'approve','{}');
reset role;
select pg_temp.assert_true((select count(*)=1 and min(correction)='Final revision'
 from public.service_reports where work_order_id='a0080000-0000-4000-8000-000000000030'),
 'managed draft and submit update one report');
do $$ begin
 begin
  insert into public.service_reports(work_order_id,complaint) values
   ('a0080000-0000-4000-8000-000000000030','Duplicate internal report');
  raise exception 'Managed report uniqueness was lost';
 exception when unique_violation then null;
 end;
end $$;
select pg_temp.assert_true((select snapshot->'report'->>'repair'='Final revision'
 from public.saved_checklists where work_order_id='a0080000-0000-4000-8000-000000000030'),
 'approval snapshots the single final managed report');
rollback;
