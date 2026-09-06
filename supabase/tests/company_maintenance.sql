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
select ('a0060000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'now006-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NOW006 '||right(id::text,1) where id::text like 'a0060000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0060000-0000-4000-8000-000000000010','Company A','a0060000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0060000-0000-4000-8000-000000000010'
 where id in ('a0060000-0000-4000-8000-000000000001','a0060000-0000-4000-8000-000000000002','a0060000-0000-4000-8000-000000000004','a0060000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0060000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a0060000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a0060000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0060000-0000-4000-8000-000000000021','a0060000-0000-4000-8000-000000000001','a0060000-0000-4000-8000-000000000020','A vessel'),
 ('a0060000-0000-4000-8000-000000000022','a0060000-0000-4000-8000-000000000003','a0060000-0000-4000-8000-000000000020','B vessel');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000001',true);
select public.create_maintenance_job('a0060000-0000-4000-8000-000000000030',
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","title":"Repair seal","assigned_to":"a0060000-0000-4000-8000-000000000002","priority":"high"}');
select pg_temp.assert_true((select count(*)=1 from public.maintenance_jobs() j
 where j->>'id'='a0060000-0000-4000-8000-000000000030'),'manager creates one internal job');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000002',true);
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',0,
 'a0060000-0000-4000-8000-000000000031','start','{}');
select pg_temp.assert_true((select j->>'status'='in_progress' from public.maintenance_jobs('a0060000-0000-4000-8000-000000000030') j),'mechanic starts assigned work');
-- An uncertain response can be retried even after its revision has advanced.
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',0,
 'a0060000-0000-4000-8000-000000000031','start','{}');
select pg_temp.assert_true((select jsonb_array_length(j->'labour')=1 from public.maintenance_jobs('a0060000-0000-4000-8000-000000000030') j),'timer retry does not duplicate');
select pg_temp.expect_error($q$select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',0,gen_random_uuid(),'pause','{}')$q$,'changed');
select pg_temp.expect_error($q$select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',null,gen_random_uuid(),'pause','{}')$q$,'changed');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',1,gen_random_uuid(),'pause','{}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',2,gen_random_uuid(),'start','{}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',3,gen_random_uuid(),'pause','{}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',4,gen_random_uuid(),'add_part','{"description":"Seal","quantity":1,"unit_cost":25}');
select pg_temp.expect_error($q$select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',5,gen_random_uuid(),'approve','{}')$q$,'Only a manager');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',5,gen_random_uuid(),'submit','{"diagnosis":"Worn seal","repair":"Replaced seal and tested"}');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.maintenance_jobs()),'company B sees no A jobs');
select pg_temp.expect_error($q$select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',6,gen_random_uuid(),'approve','{}')$q$,'Access denied');
select pg_temp.expect_error($q$select public.maintenance_asset_context('a0060000-0000-4000-8000-000000000021')$q$,'Access denied');
select pg_temp.assert_true((select count(*)=0 from public.work_orders where id='a0060000-0000-4000-8000-000000000030'),'direct work-order read is denied');
select pg_temp.assert_true((select count(*)=0 from public.service_reports where work_order_id='a0060000-0000-4000-8000-000000000030'),'direct report read is denied');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000001',true);
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',6,gen_random_uuid(),'return','{"note":"Add test pressure"}');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000002',true);
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',7,gen_random_uuid(),'submit','{"diagnosis":"Worn seal","repair":"Replaced seal; tested at 100 psi"}');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000001',true);
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',8,'a0060000-0000-4000-8000-000000000032','approve','{}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',8,'a0060000-0000-4000-8000-000000000032','approve','{}');
select pg_temp.assert_true((select j->>'status'='closed' and jsonb_array_length(j->'labour')=2 and jsonb_array_length(j->'parts')=1
 from public.maintenance_jobs('a0060000-0000-4000-8000-000000000030') j),'two labour sessions and part survive approval');
select pg_temp.assert_true((select count(*)=0 from public.invoices where work_order_id='a0060000-0000-4000-8000-000000000030'),'internal repair creates no invoice');

select public.save_maintenance_setup(gen_random_uuid(),'component','a0060000-0000-4000-8000-000000000040',0,
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","label":"Generator","kind":"generator","current_hours":100}');
select public.save_maintenance_setup(gen_random_uuid(),'component','a0060000-0000-4000-8000-000000000041',0,
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","label":"Propulsion","kind":"engine","current_hours":500}');
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0060000-0000-4000-8000-000000000042',0,
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","engine_id":"a0060000-0000-4000-8000-000000000040","interval_label":"Generator service","interval_hours":250,"last_service_hours":0}');
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0060000-0000-4000-8000-000000000043',0,
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","engine_id":"a0060000-0000-4000-8000-000000000041","interval_label":"Engine service","interval_hours":500,"last_service_hours":100}');
select public.create_maintenance_job('a0060000-0000-4000-8000-000000000050',
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","title":"Generator service","service_interval_id":"a0060000-0000-4000-8000-000000000042","assigned_to":"a0060000-0000-4000-8000-000000000002"}');
select pg_temp.expect_error($q$select public.create_maintenance_job(gen_random_uuid(),
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","title":"Duplicate service","service_interval_id":"a0060000-0000-4000-8000-000000000042"}')$q$,'already has an open job');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000002',true);
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000050',0,gen_random_uuid(),'start','{}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000050',1,gen_random_uuid(),'pause','{}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000050',2,gen_random_uuid(),'submit','{"diagnosis":"Scheduled service","repair":"Changed oil and tested"}');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error($q$select public.change_maintenance_job('a0060000-0000-4000-8000-000000000050',3,gen_random_uuid(),'approve','{}')$q$,'valid completion meter');
select pg_temp.assert_true((select j->>'status'='pending_review' from public.maintenance_jobs('a0060000-0000-4000-8000-000000000050') j),'failed approval rolls back job');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000050',3,gen_random_uuid(),'return','{"note":"Record completion meter"}');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000002',true);
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000050',4,gen_random_uuid(),'submit','{"diagnosis":"Scheduled service","repair":"Changed oil and tested","completion_hours":150}');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000001',true);
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000050',5,'a0060000-0000-4000-8000-000000000051','approve','{}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000050',5,'a0060000-0000-4000-8000-000000000051','approve','{}');
select pg_temp.assert_true((select (p->>'next_due_hours')::numeric=400 from jsonb_array_elements(public.maintenance_asset_context('a0060000-0000-4000-8000-000000000021')->'plans') p
 where p->>'id'='a0060000-0000-4000-8000-000000000042'),'generator advances exactly once');
select pg_temp.assert_true((select (p->>'next_due_hours')::numeric=600 from jsonb_array_elements(public.maintenance_asset_context('a0060000-0000-4000-8000-000000000021')->'plans') p
 where p->>'id'='a0060000-0000-4000-8000-000000000043'),'propulsion plan remains unchanged');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000050',6,gen_random_uuid(),'reopen','{"note":"Check follow-up leak"}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000050',7,gen_random_uuid(),'submit','{"diagnosis":"Follow-up check","repair":"Retested; no leak","completion_hours":180}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000050',8,gen_random_uuid(),'approve','{}');
select pg_temp.assert_true((select (p->>'next_due_hours')::numeric=400 from jsonb_array_elements(public.maintenance_asset_context('a0060000-0000-4000-8000-000000000021')->'plans') p
 where p->>'id'='a0060000-0000-4000-8000-000000000042'),'reopening cannot advance service twice');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000005',true);
select pg_temp.expect_error($q$insert into public.invoices(work_order_id,client_id,invoice_number)
 values('a0060000-0000-4000-8000-000000000030','a0060000-0000-4000-8000-000000000001','INTERNAL-DENIED')$q$,'row-level security');
select pg_temp.expect_error($q$insert into public.parts(work_order_id,description,quantity,unit_cost)
 values('a0060000-0000-4000-8000-000000000030','Bypass',1,5)$q$,'row-level security');
-- Checklist snapshots and evidence are server-validated, not UI conventions.
reset role;
insert into public.checklist_templates(id,asset_type_id,name,checklist_type) values
 ('a0060000-0000-4000-8000-000000000060','a0060000-0000-4000-8000-000000000020','Generator procedure','pm');
insert into public.checklist_items(id,template_id,description_en,requires_photo) values
 ('a0060000-0000-4000-8000-000000000061','a0060000-0000-4000-8000-000000000060','Inspect oil filter',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000001',true);
select public.create_maintenance_job('a0060000-0000-4000-8000-000000000070',
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","title":"Inspect filter","checklist_template_id":"a0060000-0000-4000-8000-000000000060","assigned_to":"a0060000-0000-4000-8000-000000000002"}');
select pg_temp.expect_error($q$select public.create_maintenance_job('a0060000-0000-4000-8000-000000000070',
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","title":"Changed payload"}')$q$,'already used');
reset role;
update public.checklist_items set requires_photo=false,description_en='Changed procedure' where id='a0060000-0000-4000-8000-000000000061';
set local role authenticated;
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select j->'checklist_snapshot'->0->>'description_en'='Inspect oil filter' from public.maintenance_jobs('a0060000-0000-4000-8000-000000000070') j),'job retains original procedure');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000070',0,gen_random_uuid(),'start','{}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000070',1,gen_random_uuid(),'pause','{}');
select pg_temp.expect_error($q$select public.change_maintenance_job('a0060000-0000-4000-8000-000000000070',2,gen_random_uuid(),'submit',
 '{"diagnosis":"Inspection","repair":"Passed inspection"}')$q$,'Complete every checklist');
select pg_temp.expect_error($q$select public.change_maintenance_job('a0060000-0000-4000-8000-000000000070',2,gen_random_uuid(),'submit',
 '{"diagnosis":"Inspection","repair":"Passed inspection","answers":{"a0060000-0000-4000-8000-000000000061":{"result":"pass"}}}')$q$,'Required checklist photo');
insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'maintenance-evidence',
 'a0060000-0000-4000-8000-000000000070/a0060000-0000-4000-8000-000000000002/filter.jpg');
select pg_temp.assert_true((select count(*)=1 from storage.objects where bucket_id='maintenance-evidence'),'assigned mechanic reads own evidence');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='maintenance-evidence'),'company B cannot read A evidence');
select pg_temp.expect_error($q$insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'maintenance-evidence',
 'a0060000-0000-4000-8000-000000000070/a0060000-0000-4000-8000-000000000003/attack.jpg')$q$,'row-level security');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000002',true);
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000070',2,gen_random_uuid(),'submit',
 '{"diagnosis":"Inspection","repair":"Passed inspection","answers":{"a0060000-0000-4000-8000-000000000061":{"result":"pass","photo_path":"a0060000-0000-4000-8000-000000000070/a0060000-0000-4000-8000-000000000002/filter.jpg"}},"evidence_paths":["a0060000-0000-4000-8000-000000000070/a0060000-0000-4000-8000-000000000002/filter.jpg"]}');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000001',true);
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000070',3,'a0060000-0000-4000-8000-000000000071','approve','{}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000070',3,'a0060000-0000-4000-8000-000000000071','approve','{}');
select pg_temp.assert_true((select count(*)=1 from public.saved_checklists where work_order_id='a0060000-0000-4000-8000-000000000070'),'approval retry has one immutable history record');
select pg_temp.assert_true((select jsonb_array_length(snapshot->'evidence_paths')=1 and
 snapshot->'checklist_answers'->'a0060000-0000-4000-8000-000000000061'->>'result'='pass'
 from public.saved_checklists where id='a0060000-0000-4000-8000-000000000071'),'approved history preserves evidence and answers');

-- Provider-performed service uses the same exact plan and approval operation.
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000005',true);
select public.create_maintenance_job('a0060000-0000-4000-8000-000000000080',
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","title":"Provider generator service","service_interval_id":"a0060000-0000-4000-8000-000000000042","assigned_to":"a0060000-0000-4000-8000-000000000006"}');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000006',true);
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000080',0,gen_random_uuid(),'start','{}');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000080',1,gen_random_uuid(),'pause','{}');
select pg_temp.expect_error($q$select public.change_maintenance_job('a0060000-0000-4000-8000-000000000080',2,gen_random_uuid(),'submit',
 '{"diagnosis":"Scheduled service","repair":"Changed filters","completion_hours":"NaN"}')$q$,'valid completion meter');
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000080',2,gen_random_uuid(),'submit',
 '{"diagnosis":"Scheduled service","repair":"Changed filters","completion_hours":400}');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000001',true);
select public.change_maintenance_job('a0060000-0000-4000-8000-000000000080',3,gen_random_uuid(),'approve','{}');
select pg_temp.assert_true((select (p->>'next_due_hours')::numeric=650 from jsonb_array_elements(public.maintenance_asset_context('a0060000-0000-4000-8000-000000000021')->'plans') p
 where p->>'id'='a0060000-0000-4000-8000-000000000042'),'provider completion advances the same plan');
select pg_temp.assert_true((select (e->>'current_hours')::numeric=500 from jsonb_array_elements(public.maintenance_asset_context('a0060000-0000-4000-8000-000000000021')->'components') e
 where e->>'id'='a0060000-0000-4000-8000-000000000041'),'propulsion meter unchanged');

-- Disabling execution preserves history, blocks writes on the server.
-- Administrators create assets for the company owner, never themselves or B.
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000007',true);
select public.save_maintenance_setup('a0060000-0000-4000-8000-000000000091','asset','a0060000-0000-4000-8000-000000000090',0,
 '{"name":"Admin vessel","client_id":"a0060000-0000-4000-8000-000000000003","asset_type_id":"a0060000-0000-4000-8000-000000000020"}');
select public.save_maintenance_setup('a0060000-0000-4000-8000-000000000091','asset','a0060000-0000-4000-8000-000000000090',0,
 '{"name":"Admin vessel","client_id":"a0060000-0000-4000-8000-000000000003","asset_type_id":"a0060000-0000-4000-8000-000000000020"}');
select pg_temp.assert_true(public.maintenance_asset_context('a0060000-0000-4000-8000-000000000090')->'asset'->>'client_id'='a0060000-0000-4000-8000-000000000001','admin asset belongs to company owner');
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'asset','a0060000-0000-4000-8000-000000000090',null,'{"name":"Bypass revision"}')$q$,'changed');
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'component',gen_random_uuid(),0,
 '{"asset_id":"a0060000-0000-4000-8000-000000000090","label":"Invalid meter","current_hours":"NaN"}')$q$,'finite');
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'plan','a0060000-0000-4000-8000-000000000043',0,
 '{"engine_id":"a0060000-0000-4000-8000-000000000040","interval_hours":500,"last_service_hours":100}')$q$,'separate plan');
reset role;
update public.client_capabilities set enabled=false where client_id='a0060000-0000-4000-8000-000000000001' and capability_key='maintenance_planning';
set local role authenticated;
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000007',true);
select pg_temp.expect_error($q$select public.create_maintenance_job(gen_random_uuid(),
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","title":"Disabled scheduled service","service_interval_id":"a0060000-0000-4000-8000-000000000042"}')$q$,'planning is disabled');
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'plan',gen_random_uuid(),0,
 '{"asset_id":"a0060000-0000-4000-8000-000000000021"}')$q$,'Access denied');
reset role;
update public.client_capabilities set enabled=false where client_id='a0060000-0000-4000-8000-000000000001' and capability_key='pm_checklists';
set local role authenticated;
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select count(*)>0 from public.maintenance_jobs()),'disabled mechanic retains job history');
select pg_temp.expect_error($q$select public.change_maintenance_job('a0060000-0000-4000-8000-000000000030',9,gen_random_uuid(),'start','{}')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true((select count(*)=0 from public.maintenance_jobs()),'operator does not read internal jobs');
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'asset',gen_random_uuid(),0,'{"name":"Forbidden"}')$q$,'Access denied');
reset role;
set local role anon;
select pg_temp.expect_error('select public.maintenance_jobs()','permission denied');
rollback;
