begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_error(command text,expected text) returns void language plpgsql as $$
begin begin execute command; exception when others then
 if position(expected in sqlerrm)>0 then return; end if; raise; end;
 raise exception 'Expected error: %',expected; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('a0150000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'now015-'||n||'@example.invalid','{}'::jsonb from generate_series(1,5) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'operator' when '3' then 'client'
 when '4' then 'client_mechanic' else 'owner' end,full_name='Builder test'
 where id::text like 'a0150000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0150000-0000-4000-8000-000000000010','Builder company A','a0150000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0150000-0000-4000-8000-000000000010'
 where id in ('a0150000-0000-4000-8000-000000000001','a0150000-0000-4000-8000-000000000002','a0150000-0000-4000-8000-000000000004');
insert into public.client_capabilities(client_id,capability_key,enabled)
select 'a0150000-0000-4000-8000-000000000001',k,true
 from unnest(array['pm_checklists','operational_checklists','maintenance_planning']) k;
insert into public.asset_types(id,category,name) values
 ('a0150000-0000-4000-8000-000000000020','test','Builder machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0150000-0000-4000-8000-000000000021','a0150000-0000-4000-8000-000000000001','a0150000-0000-4000-8000-000000000020','Builder A'),
 ('a0150000-0000-4000-8000-000000000022','a0150000-0000-4000-8000-000000000003','a0150000-0000-4000-8000-000000000020','Builder B');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000001',true);
select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000030',
 'a0150000-0000-4000-8000-000000000040',0,'draft',
 '{"name":"Daily preparation","checklist_type":"operator_daily","asset_type_id":"a0150000-0000-4000-8000-000000000020","items":[{"description_en":"Check guards","category":"Safety","definition":{"critical":true}}]}');
select pg_temp.assert_true((select count(*)=1 from public.checklist_procedures),'manager owns draft');
select pg_temp.assert_true((select count(*)=0 from public.checklist_templates where procedure_id='a0150000-0000-4000-8000-000000000040'),'draft is not executable');
select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000031',
 'a0150000-0000-4000-8000-000000000040',1,'publish','{}');
select pg_temp.assert_true((select count(*)=1 and min(version)=1 from public.checklist_templates
 where procedure_id='a0150000-0000-4000-8000-000000000040'),'publish creates immutable version');
select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000031',
 'a0150000-0000-4000-8000-000000000040',1,'publish','{}');
select pg_temp.expect_error($q$select public.save_checklist_procedure(gen_random_uuid(),
 'a0150000-0000-4000-8000-000000000040',1,'archive','{}')$q$,'changed');
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.client_capabilities where client_id='a0150000-0000-4000-8000-000000000001'),'other company cannot read capability switches');
select pg_temp.assert_true((select count(*)=0 from public.checklist_procedures),'other company cannot read drafts');
select pg_temp.assert_true((select count(*)=0 from public.checklist_templates where procedure_id='a0150000-0000-4000-8000-000000000040'),'other company cannot read published template');
select pg_temp.assert_true((select count(*)=0 from public.checklist_items where template_id in
 (select id from public.checklist_templates where procedure_id='a0150000-0000-4000-8000-000000000040')),'other company has no published items');
select pg_temp.expect_error($q$select public.save_checklist_procedure(gen_random_uuid(),
 'a0150000-0000-4000-8000-000000000040',2,'archive','{}')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select count(*)=3 from public.client_capabilities where client_id='a0150000-0000-4000-8000-000000000001'),'operator can read company capability switches');
update public.client_capabilities set enabled=false where client_id='a0150000-0000-4000-8000-000000000001';
select pg_temp.assert_true((select bool_and(enabled) from public.client_capabilities where client_id='a0150000-0000-4000-8000-000000000001'),'operator cannot change company capability switches');
select pg_temp.assert_true((select count(*)=1 from public.checklist_templates where procedure_id='a0150000-0000-4000-8000-000000000040'),'operator can read own published template');
select pg_temp.assert_true((select count(*)=0 from public.checklist_procedures),'operator cannot read drafts');
select pg_temp.expect_error($q$select public.save_checklist_procedure(gen_random_uuid(),
 'a0150000-0000-4000-8000-000000000040',2,'archive','{}')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000001',true);
select public.assign_preop_checklist('a0150000-0000-4000-8000-000000000050','a0150000-0000-4000-8000-000000000051',
 jsonb_build_object('asset_id','a0150000-0000-4000-8000-000000000021','template_id',
  (select id from public.checklist_templates where procedure_id='a0150000-0000-4000-8000-000000000040' and version=1),
  'assigned_to','a0150000-0000-4000-8000-000000000002'));
select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000052',
 'a0150000-0000-4000-8000-000000000040',2,'draft',
 '{"name":"Daily preparation v2","checklist_type":"operator_daily","asset_type_id":"a0150000-0000-4000-8000-000000000020","items":[{"description_en":"Check all guards","category":"Safety"}]}');
select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000053',
 'a0150000-0000-4000-8000-000000000040',3,'publish','{}');
select pg_temp.assert_true((select count(*)=2 and count(*) filter(where is_active)=1 from public.checklist_templates
 where procedure_id='a0150000-0000-4000-8000-000000000040'),'new publication retains v1 and selects v2 for new work');
select pg_temp.assert_true((select description_en='Check guards' from public.checklist_items where template_id=(select id from public.checklist_templates
 where procedure_id='a0150000-0000-4000-8000-000000000040' and version=1)),'published instruction remains unchanged');
-- Model a real gap between retirement and the operator starting an assignment.
reset role;
update public.checklist_templates set updated_at=now()-interval '1 hour'
 where procedure_id='a0150000-0000-4000-8000-000000000040' and version=1;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000002',true);
create function pg_temp.run_data() returns jsonb language sql as $$
 select jsonb_build_object('asset_id','a0150000-0000-4000-8000-000000000021','template_id',t.id,'template_version',1,
  'assignment_id','a0150000-0000-4000-8000-000000000051','completed_at',now(),'started_at',now(),
  'run_type','pre_departure','responses',jsonb_build_object(i.id,'action'),'notes',jsonb_build_object(i.id,'Guard is loose'), 'photos','{}'::jsonb)
 from public.checklist_templates t join public.checklist_items i on i.template_id=t.id
 where t.procedure_id='a0150000-0000-4000-8000-000000000040' and t.version=1
$$;
select public.submit_operations_checklist('a0150000-0000-4000-8000-000000000054',pg_temp.run_data());
select public.submit_operations_checklist('a0150000-0000-4000-8000-000000000054',pg_temp.run_data());
select pg_temp.assert_true((select status='completed' and completed_run_id='a0150000-0000-4000-8000-000000000054'
 from public.checklist_assignments where id='a0150000-0000-4000-8000-000000000051'),'run completes its assignment');
select pg_temp.assert_true((select count(*)=1 from public.checklist_findings where run_id='a0150000-0000-4000-8000-000000000054'),'retry creates one linked finding');
select pg_temp.assert_true((select count(*)=1 from public.maintenance_faults() f where f->>'severity'='urgent'),'critical failure is an urgent manager fault');
select pg_temp.expect_error($q$select public.submit_operations_checklist(gen_random_uuid(),pg_temp.run_data())$q$,'Assignment is unavailable');
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error($q$select public.save_checklist_procedure(gen_random_uuid(),gen_random_uuid(),0,'draft',
 '{"name":"Bad range","checklist_type":"pm","items":[{"description_en":"Record pressure","definition":{"input_type":"number","min":50,"max":10}}]}')$q$,'valid numeric limits');
select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000060','a0150000-0000-4000-8000-000000000061',0,'draft',
 '{"name":"Pressure service","checklist_type":"pm","items":[{"description_en":"Record pressure","definition":{"input_type":"number","unit":"bar","min":10,"max":50}}]}');
select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000062','a0150000-0000-4000-8000-000000000061',1,'publish','{}');
select public.create_maintenance_job('a0150000-0000-4000-8000-000000000063',jsonb_build_object('asset_id','a0150000-0000-4000-8000-000000000021',
 'title','Pressure service','job_type','preventative','checklist_template_id',(select id from public.checklist_templates where procedure_id='a0150000-0000-4000-8000-000000000061')));
select pg_temp.assert_true((select (j->'checklist_snapshot'->0->'definition'->>'max')::numeric=50
 from public.maintenance_jobs('a0150000-0000-4000-8000-000000000063') j),'internal work freezes rich step rules');
select pg_temp.expect_error($q$select public.validate_checklist_answer('{"input_type":"number","max":50}','pass','80')$q$,'Out-of-range');
select pg_temp.expect_error($q$select public.validate_checklist_answer('{"input_type":"number"}','pass','NaN')$q$,'valid numeric');
select pg_temp.expect_error($q$select public.validate_checklist_answer('{"allow_na":false}','n/a','')$q$,'not applicable');
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000005',true);
select pg_temp.expect_error($q$update public.checklist_templates set name='Tampered' where procedure_id='a0150000-0000-4000-8000-000000000040'$q$,'immutable');
select pg_temp.expect_error($q$update public.checklist_items set description_en='Tampered' where template_id=(select id from public.checklist_templates
 where procedure_id='a0150000-0000-4000-8000-000000000040' and version=1)$q$,'immutable');
-- Provider orders freeze the private procedure and enforce its rich answers.
insert into public.work_orders(id,title,asset_id,client_id,created_by,status,job_type,checklist_template_id)
select 'a0150000-0000-4000-8000-000000000070','Provider pressure service',
 'a0150000-0000-4000-8000-000000000021','a0150000-0000-4000-8000-000000000001',auth.uid(),'draft','preventative',id
 from public.checklist_templates where procedure_id='a0150000-0000-4000-8000-000000000061';
select pg_temp.assert_true((select (items_json->0->'definition'->>'min')::numeric=10
 from public.work_order_checklist_snapshots where work_order_id='a0150000-0000-4000-8000-000000000070'),'provider job freezes numeric limits');
select pg_temp.expect_error($q$update public.work_orders set status='pending_review'
 where id='a0150000-0000-4000-8000-000000000070'$q$,'Complete the work order checklist');
select pg_temp.expect_error($q$update public.work_orders set asset_id='a0150000-0000-4000-8000-000000000022',client_id='a0150000-0000-4000-8000-000000000003'
 where id='a0150000-0000-4000-8000-000000000070'$q$,'Checklist is unavailable');
select pg_temp.expect_error($q$insert into public.checklist_responses(work_order_id,checklist_item_id,response_status,notes,completed_by)
 select 'a0150000-0000-4000-8000-000000000070',i.id,'pass','80',auth.uid() from public.checklist_items i join public.checklist_templates t on t.id=i.template_id
 where t.procedure_id='a0150000-0000-4000-8000-000000000061'$q$,'Out-of-range');
insert into public.checklist_responses(id,work_order_id,checklist_item_id,response_status,notes,completed_by)
 select 'a0150000-0000-4000-8000-000000000071','a0150000-0000-4000-8000-000000000070',i.id,'action','80',auth.uid() from public.checklist_items i join public.checklist_templates t on t.id=i.template_id
 where t.procedure_id='a0150000-0000-4000-8000-000000000061';
select pg_temp.expect_error($q$update public.work_orders set status='pending_review'
 where id='a0150000-0000-4000-8000-000000000070'$q$,'resolve failed steps');
update public.checklist_responses set response_status='pass',notes='30' where id='a0150000-0000-4000-8000-000000000071';
update public.work_orders set status='pending_review' where id='a0150000-0000-4000-8000-000000000070';
select pg_temp.expect_error($q$update public.checklist_responses set notes='40' where id='a0150000-0000-4000-8000-000000000071'$q$,'locked');
select pg_temp.expect_error($q$update public.work_orders set checklist_template_id=null where id='a0150000-0000-4000-8000-000000000070'$q$,'after work starts');
-- The owner shares a starter; a company makes an independent private copy.
select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000080','a0150000-0000-4000-8000-000000000081',0,'draft',
 '{"name":"Shared safety starter","checklist_type":"operator_daily","items":[{"description_en":"Inspect safety guards","definition":{"allow_na":false}}]}');
select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000082','a0150000-0000-4000-8000-000000000081',1,'publish','{}');
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true((select count(*)=1 from public.checklist_templates where procedure_id='a0150000-0000-4000-8000-000000000081'),'client reads owner starter');
select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000083','a0150000-0000-4000-8000-000000000084',0,'draft',
 jsonb_build_object('name','Private customized safety','checklist_type','operator_daily','source_template_id',
 (select id from public.checklist_templates where procedure_id='a0150000-0000-4000-8000-000000000081'),'source_version',1,
 'items','[{"description_en":"Inspect our machine guards"}]'::jsonb));
select pg_temp.assert_true((select client_id=auth.uid() from public.checklist_procedures where id='a0150000-0000-4000-8000-000000000084'),'copy belongs to current company');
select pg_temp.expect_error($q$select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000083',
 'a0150000-0000-4000-8000-000000000084',0,'draft','{}')$q$,'different input');
select public.save_checklist_procedure('a0150000-0000-4000-8000-000000000090','a0150000-0000-4000-8000-000000000040',4,'archive','{}');
select pg_temp.assert_true((select not is_active from public.checklist_templates where procedure_id='a0150000-0000-4000-8000-000000000040' and version=2),'archive prevents new selection');
select pg_temp.assert_true((select updated_at=now()-interval '1 hour' from public.checklist_templates where procedure_id='a0150000-0000-4000-8000-000000000040' and version=1),'archive preserves original retirement timestamp');
select pg_temp.assert_true((select count(*)=1 from public.operator_checklist_runs where id='a0150000-0000-4000-8000-000000000054'),'archive retains completed run');
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error($q$select public.submit_operations_checklist(gen_random_uuid(),pg_temp.run_data()-'assignment_id')$q$,'unavailable');
select public.submit_operations_checklist('a0150000-0000-4000-8000-000000000091',
 jsonb_build_object('asset_id','a0150000-0000-4000-8000-000000000021','template_id',t.id,'template_version',2,
  'completed_at',now(),'started_at',now()-interval '1 minute','run_type','pre_departure',
  'responses',jsonb_build_object(i.id,'pass'),'notes','{}'::jsonb,'photos','{}'::jsonb))
 from public.checklist_templates t join public.checklist_items i on i.template_id=t.id
 where t.procedure_id='a0150000-0000-4000-8000-000000000040' and t.version=2;
select pg_temp.assert_true((select count(*)=1 from public.operator_checklist_runs where id='a0150000-0000-4000-8000-000000000091'),'work started before archive still submits');
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.work_order_checklist_snapshots where work_order_id='a0150000-0000-4000-8000-000000000070'),'other company cannot read provider snapshot');
select pg_temp.assert_true((select count(*)=0 from public.checklist_procedures where id='a0150000-0000-4000-8000-000000000084'),'other company cannot read private copy');
select pg_temp.assert_true(not public.checklist_media_access('checklists/asset_a0150000-0000-4000-8000-000000000021/image.jpg',false),'other company cannot read private PM photos');
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.checklist_media_access('checklists/asset_a0150000-0000-4000-8000-000000000021/image.jpg',false),'company reads its PM photos from private storage');
select pg_temp.assert_true(not public.checklist_photo_exists('[]','asset_a0150000-0000-4000-8000-000000000021','a0150000-0000-4000-8000-000000000099'),'empty photo array is not evidence');
select pg_temp.assert_true(not public.checklist_photo_exists('https://hkjpojobdbbtjkhaudki.supabase.co/storage/v1/object/public/service-report-photos/checklists/asset_a0150000-0000-4000-8000-000000000021/a0150000-0000-4000-8000-000000000099_fake.jpg',
 'asset_a0150000-0000-4000-8000-000000000021','a0150000-0000-4000-8000-000000000099'),'nonexistent object is not evidence');
insert into public.saved_checklists(id,asset_id,client_id,template_id,template_name,checklist_type,source_type,submitted_by,snapshot)
 select 'a0150000-0000-4000-8000-000000000100','a0150000-0000-4000-8000-000000000021',auth.uid(),t.id,'Forged title','maintenance','client',auth.uid(),
 jsonb_build_object('template','{}'::jsonb,'header','{}'::jsonb,'items',jsonb_build_array(jsonb_build_object('id',i.id,'description_en','Forged instruction','definition','{}'::jsonb,'response','pass','note','30')))
 from public.checklist_templates t join public.checklist_items i on i.template_id=t.id
 where t.procedure_id='a0150000-0000-4000-8000-000000000061';
select pg_temp.assert_true((select template_name='Pressure service' and snapshot->'items'->0->>'description_en'='Record pressure'
 and (snapshot->'items'->0->'definition'->>'min')::numeric=10 from public.saved_checklists where id='a0150000-0000-4000-8000-000000000100'),'saved PM history canonicalizes the published instruction and rules');
insert into storage.objects(id,bucket_id,name) values ('a0150000-0000-4000-8000-000000000101','service-report-photos',
 'checklists/asset_a0150000-0000-4000-8000-000000000021/a0150000-0000-4000-8000-000000000099_real.jpg');
select pg_temp.assert_true(public.checklist_photo_exists('https://hkjpojobdbbtjkhaudki.supabase.co/storage/v1/object/public/service-report-photos/checklists/asset_a0150000-0000-4000-8000-000000000021/a0150000-0000-4000-8000-000000000099_real.jpg',
 'asset_a0150000-0000-4000-8000-000000000021','a0150000-0000-4000-8000-000000000099'),'uploaded company evidence satisfies requirement');
select pg_temp.assert_true((select count(*)=1 from storage.objects where id='a0150000-0000-4000-8000-000000000101'),'client reads PM photo metadata');
select set_config('request.jwt.claim.sub','a0150000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from storage.objects where id='a0150000-0000-4000-8000-000000000101'),'other company cannot read PM photo metadata');
select pg_temp.expect_error($q$insert into storage.objects(id,bucket_id,name) values (gen_random_uuid(),'service-report-photos',
 'checklists/asset_a0150000-0000-4000-8000-000000000021/cross-company.jpg')$q$,'row-level security');
rollback;
