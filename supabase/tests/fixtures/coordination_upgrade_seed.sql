-- Deliberately runs before NOW-007 migrations to exercise nonempty backfill.
insert into auth.users(id,email,raw_user_meta_data)
select ('a0080000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'upgrade-'||n||'@example.invalid','{}'::jsonb from generate_series(1,4) n;
update public.profiles set role=case right(id::text,1) when '1' then 'owner' when '2' then 'client'
 when '3' then 'client_mechanic' else 'operator' end,full_name='Upgrade fixture' where id::text like 'a0080000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0080000-0000-4000-8000-000000000010','Upgrade company','a0080000-0000-4000-8000-000000000002');
update public.profiles set org_id='a0080000-0000-4000-8000-000000000010' where id::text like 'a0080000-%' and role<>'owner';
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0080000-0000-4000-8000-000000000002','pm_checklists',true);
insert into public.asset_types(id,category,name) values('a0080000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name,location,created_at) values
 ('a0080000-0000-4000-8000-000000000021','a0080000-0000-4000-8000-000000000002','a0080000-0000-4000-8000-000000000020','Existing vessel','Dock 4','2025-01-01');
insert into public.asset_engines(id,asset_id,label,current_hours) values
 ('a0080000-0000-4000-8000-000000000022','a0080000-0000-4000-8000-000000000021','Generator',1240);
insert into public.asset_service_intervals(id,asset_id,engine_id,interval_hours,next_due_hours) values
 ('a0080000-0000-4000-8000-000000000023','a0080000-0000-4000-8000-000000000021','a0080000-0000-4000-8000-000000000022',250,1250);
insert into public.work_orders(id,asset_id,client_id,created_by,assigned_to,title,job_type,status,notes_internal,billable_rate,wage_rate) values
 ('a0080000-0000-4000-8000-000000000030','a0080000-0000-4000-8000-000000000021','a0080000-0000-4000-8000-000000000002','a0080000-0000-4000-8000-000000000001',
 'a0080000-0000-4000-8000-000000000001','Legacy pump repair','repair','in_progress','PROVIDER_PRIVATE_SENTINEL',987,654);
insert into public.parts(id,work_order_id,description,part_number,quantity,unit_cost) values
 ('a0080000-0000-4000-8000-000000000031','a0080000-0000-4000-8000-000000000030','Legacy gasket','OLD-42',2,15);
insert into public.service_reports(id,work_order_id,complaint,cause,correction,comments) values
 ('a0080000-0000-4000-8000-000000000032','a0080000-0000-4000-8000-000000000030','Leak','Worn gasket','Replaced gasket','Checked under load');
set role authenticated;
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000002',false);
select public.create_maintenance_job('a0080000-0000-4000-8000-000000000040',
 '{"asset_id":"a0080000-0000-4000-8000-000000000021","title":"Existing managed repair","assigned_to":"a0080000-0000-4000-8000-000000000003"}');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000040',0,'a0080000-0000-4000-8000-000000000041','start','{}');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000040',1,'a0080000-0000-4000-8000-000000000042','add_part','{"description":"New gasket","part_number":"NEW-42","quantity":1,"unit_cost":12}');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000040',2,'a0080000-0000-4000-8000-000000000043','pause','{}');
select public.report_maintenance_fault('a0080000-0000-4000-8000-000000000050','a0080000-0000-4000-8000-000000000021','Existing urgent leak','urgent');
reset role;
