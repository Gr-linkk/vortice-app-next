insert into auth.users(id,email,raw_user_meta_data) values
 ('a0080000-0000-4000-8000-000000000001','now008-owner@example.invalid','{}'),
 ('a0080000-0000-4000-8000-000000000002','now008-client@example.invalid','{}');
update public.profiles set role=case right(id::text,1) when '1' then 'owner' else 'client' end
 where id::text like 'a0080000-%';
insert into public.asset_types(id,category,name) values
 ('a0080000-0000-4000-8000-000000000010','test','Test machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0080000-0000-4000-8000-000000000011','a0080000-0000-4000-8000-000000000002',
  'a0080000-0000-4000-8000-000000000010','NOW008 upgrade machine');
insert into public.work_orders(id,title,asset_id,client_id,created_by,status,job_type) values
 ('a0080000-0000-4000-8000-000000000020','NOW008 provider inspection',
  'a0080000-0000-4000-8000-000000000011','a0080000-0000-4000-8000-000000000002',
  'a0080000-0000-4000-8000-000000000001','closed','repair');
insert into public.service_reports(id,work_order_id,complaint,created_at,updated_at) values
 ('a0080000-0000-4000-8000-000000000021','a0080000-0000-4000-8000-000000000020',
  'Original provider report','2026-08-01T10:00:00Z','2026-08-02T11:00:00Z');
set role authenticated;
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000001',false);
select public.create_maintenance_job('a0080000-0000-4000-8000-000000000030',
 '{"asset_id":"a0080000-0000-4000-8000-000000000011","title":"NOW008 internal repair"}');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000030',0,gen_random_uuid(),'start','{}');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000030',1,gen_random_uuid(),'pause','{}');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000030',2,gen_random_uuid(),'save_report',
 '{"diagnosis":"Test diagnosis","repair":"Saved before upgrade"}');
reset role;
create table public.now008_report_upgrade_snapshot as select id,to_jsonb(s) as original from public.service_reports s;
create table public.now008_history_upgrade_snapshot as select count(*) as original_count from public.asset_history_entries;
