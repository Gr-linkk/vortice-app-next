begin;
create function pg_temp.ok(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.denied(command text) returns void language plpgsql as $$
begin begin execute command; exception when insufficient_privilege then return; end; raise exception 'Expected access denial'; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('b0060000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'sources-'||n||'@example.invalid','{}' from generate_series(1,5) n;
update public.profiles set role=case right(id::text,1) when '1' then 'client' when '2' then 'operator' when '3' then 'client_mechanic' when '4' then 'client' else 'operator' end,full_name='Source test' where id::text like 'b0060000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('b0060000-0000-4000-8000-000000000010','Source company A','b0060000-0000-4000-8000-000000000001'),
 ('b0060000-0000-4000-8000-000000000011','Source company B','b0060000-0000-4000-8000-000000000004');
update public.profiles set org_id=case when right(id::text,1) in ('1','2','3') then 'b0060000-0000-4000-8000-000000000010'::uuid else 'b0060000-0000-4000-8000-000000000011'::uuid end where id::text like 'b0060000-%';
insert into public.client_capabilities(client_id,capability_key,enabled)
select 'b0060000-0000-4000-8000-000000000001',k,true from unnest(array['pm_checklists','operational_checklists','maintenance_planning']) k;
insert into public.asset_types(id,category,name) values('b0060000-0000-4000-8000-000000000020','test','Source equipment');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('b0060000-0000-4000-8000-000000000021','b0060000-0000-4000-8000-000000000001','b0060000-0000-4000-8000-000000000020','Source A'),
 ('b0060000-0000-4000-8000-000000000022','b0060000-0000-4000-8000-000000000004','b0060000-0000-4000-8000-000000000020','Source B');
create temp table source_ids(name text primary key,template uuid,item uuid); grant all on source_ids to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000001',true);
select public.save_maintenance_document('b0060000-0000-4000-8000-000000000030','b0060000-0000-4000-8000-000000000001','Reviewed engine manual');
insert into storage.objects(id,bucket_id,name) values
 (gen_random_uuid(),'maintenance-documents','b0060000-0000-4000-8000-000000000030/1.jpg'),
 (gen_random_uuid(),'maintenance-documents','b0060000-0000-4000-8000-000000000030/2.jpg');
select public.save_maintenance_document('b0060000-0000-4000-8000-000000000030','b0060000-0000-4000-8000-000000000001','Reviewed engine manual',2);
select public.save_maintenance_document('b0060000-0000-4000-8000-000000000031','b0060000-0000-4000-8000-000000000001','Private unrelated manual');
insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'maintenance-documents','b0060000-0000-4000-8000-000000000031/1.jpg');
select public.save_maintenance_document('b0060000-0000-4000-8000-000000000031','b0060000-0000-4000-8000-000000000001','Private unrelated manual',1);
select public.save_checklist_procedure(gen_random_uuid(),'b0060000-0000-4000-8000-000000000040',0,'draft',
 '{"name":"Engine walk around","checklist_type":"operator_daily","items":[{"description_en":"Check coolant cold","definition":{"equipment_state":"stopped","procedure_source":{"document_id":"b0060000-0000-4000-8000-000000000030","page":1,"section":"Printed page 42"}}}]}');
select public.save_checklist_procedure(gen_random_uuid(),'b0060000-0000-4000-8000-000000000040',1,'publish','{}');
insert into source_ids select 'operator',t.id,i.id from public.checklist_templates t join public.checklist_items i on i.template_id=t.id where t.procedure_id='b0060000-0000-4000-8000-000000000040';
select public.assign_preop_checklist(gen_random_uuid(),'b0060000-0000-4000-8000-000000000041',jsonb_build_object('asset_id','b0060000-0000-4000-8000-000000000021','template_id',(select template from source_ids where name='operator'),'assigned_to','b0060000-0000-4000-8000-000000000002'));
select public.save_checklist_procedure(gen_random_uuid(),'b0060000-0000-4000-8000-000000000040',2,'draft','{"name":"Replacement procedure","checklist_type":"operator_daily","items":[{"description_en":"Check engine guards"}]}');
select public.save_checklist_procedure(gen_random_uuid(),'b0060000-0000-4000-8000-000000000040',3,'publish','{}');
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000002',true);
select pg_temp.ok((select public.checklist_source_page(template,item,'b0060000-0000-4000-8000-000000000030',1)->>'title'='Reviewed engine manual' from source_ids where name='operator'),'assigned operator opens retired immutable source');
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='maintenance-documents' and name like 'b0060000-%'),'operator gets linked page only');
select pg_temp.ok((select count(*)=0 from public.maintenance_documents where id::text like 'b0060000-%'),'source grants do not expose manual library');
select pg_temp.denied($q$select public.checklist_source_page(template,item,'b0060000-0000-4000-8000-000000000030',2) from source_ids where name='operator'$q$);
select pg_temp.denied($q$select public.checklist_source_page(null,null,'b0060000-0000-4000-8000-000000000031',1)$q$);
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000005',true);
select pg_temp.denied($q$select public.checklist_source_page(template,item,'b0060000-0000-4000-8000-000000000030',1) from source_ids where name='operator'$q$);
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='maintenance-documents' and name like 'b0060000-%'),'other company gets no source objects');
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000001',true);
select public.save_checklist_procedure(gen_random_uuid(),'b0060000-0000-4000-8000-000000000050',0,'draft',
 '{"name":"Engine maintenance","checklist_type":"pm","items":[{"description_en":"Isolate engine","definition":{"equipment_state":"isolated","procedure_source":{"document_id":"b0060000-0000-4000-8000-000000000030","page":2}}}]}');
select public.save_checklist_procedure(gen_random_uuid(),'b0060000-0000-4000-8000-000000000050',1,'publish','{}');
insert into source_ids select 'mechanic',t.id,i.id from public.checklist_templates t join public.checklist_items i on i.template_id=t.id where t.procedure_id='b0060000-0000-4000-8000-000000000050';
select public.create_maintenance_job('b0060000-0000-4000-8000-000000000051',jsonb_build_object('asset_id','b0060000-0000-4000-8000-000000000021','assigned_to','b0060000-0000-4000-8000-000000000003','title','Engine isolation','checklist_template_id',(select template from source_ids where name='mechanic')));
select public.save_checklist_procedure(gen_random_uuid(),'b0060000-0000-4000-8000-000000000050',2,'archive','{}');
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000003',true);
select pg_temp.ok((select public.checklist_source_page(template,item,'b0060000-0000-4000-8000-000000000030',2)->>'page'='2' from source_ids where name='mechanic'),'assigned mechanic opens frozen source after archive');
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='maintenance-documents' and name like 'b0060000-%'),'mechanic gets exact frozen page only');
reset role;
update public.work_orders set assigned_to=null where id='b0060000-0000-4000-8000-000000000051';
update public.checklist_assignments set status='cancelled' where id='b0060000-0000-4000-8000-000000000041';
set local role authenticated;
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000003',true);
select pg_temp.denied($q$select public.checklist_source_page(template,item,'b0060000-0000-4000-8000-000000000030',2) from source_ids where name='mechanic'$q$);
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='maintenance-documents' and name like 'b0060000-%'),'revoked mechanic assignment loses source storage access');
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000002',true);
select pg_temp.denied($q$select public.checklist_source_page(template,item,'b0060000-0000-4000-8000-000000000030',1) from source_ids where name='operator'$q$);
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='maintenance-documents' and name like 'b0060000-%'),'cancelled retired operator assignment loses source access');
rollback;
