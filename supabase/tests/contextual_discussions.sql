begin;
create function pg_temp.ok(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.denied(command text) returns void language plpgsql as $$
begin begin execute command; exception when insufficient_privilege then return; end; raise exception 'Expected access denial'; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('b0190000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'discussion-'||n||'@example.invalid','{}' from generate_series(1,5) n;
update public.profiles set role=case right(id::text,1) when '1' then 'client' when '2' then 'operator' when '3' then 'client_mechanic' when '4' then 'client' else 'operator' end,full_name='Discussion test' where id::text like 'b0190000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('b0190000-0000-4000-8000-000000000010','Discussion company A','b0190000-0000-4000-8000-000000000001'),
 ('b0190000-0000-4000-8000-000000000011','Discussion company B','b0190000-0000-4000-8000-000000000004');
update public.profiles set org_id=case when right(id::text,1) in ('1','2','3') then 'b0190000-0000-4000-8000-000000000010'::uuid else 'b0190000-0000-4000-8000-000000000011'::uuid end where id::text like 'b0190000-%';
insert into public.client_capabilities(client_id,capability_key,enabled)
select 'b0190000-0000-4000-8000-000000000001',k,true from unnest(array['pm_checklists','operational_checklists','maintenance_planning']) k;
insert into public.asset_types(id,category,name) values('b0190000-0000-4000-8000-000000000020','test','Source equipment');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('b0190000-0000-4000-8000-000000000021','b0190000-0000-4000-8000-000000000001','b0190000-0000-4000-8000-000000000020','Source A'),
 ('b0190000-0000-4000-8000-000000000022','b0190000-0000-4000-8000-000000000004','b0190000-0000-4000-8000-000000000020','Source B');
create temp table issue_ids(name text primary key,id uuid); grant all on issue_ids to authenticated;
create temp table issue_data(payload jsonb); grant all on issue_data to authenticated;
create function pg_temp.rejected(command text) returns void language plpgsql as $$
begin begin execute command; exception when others then return; end; raise exception 'Expected rejection'; end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
select public.save_checklist_procedure(gen_random_uuid(),'b0190000-0000-4000-8000-000000000030',0,'draft',
 '{"name":"Pressure safety check","checklist_type":"operator_daily","items":[{"description_en":"Read pressure gauge","definition":{"input_type":"number","unit":"bar","max":50}}]}');
select public.save_checklist_procedure(gen_random_uuid(),'b0190000-0000-4000-8000-000000000030',1,'publish','{}');
insert into issue_ids select 'template',id from public.checklist_templates where procedure_id='b0190000-0000-4000-8000-000000000030';
insert into issue_ids select 'item',id from public.checklist_items where template_id=(select id from issue_ids where name='template');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
insert into storage.objects(id,bucket_id,name)
select gen_random_uuid(),'operator-evidence','b0190000-0000-4000-8000-000000000021/b0190000-0000-4000-8000-000000000002/b0190000-0000-4000-8000-000000000040/'||id||'.jpg' from issue_ids where name='item';
insert into issue_data select jsonb_build_object('asset_id','b0190000-0000-4000-8000-000000000021','template_id',(select id from issue_ids where name='template'),'template_version',1,
 'run_type','pre_departure','started_at',now(),'completed_at',now(),'responses',jsonb_build_object(id,'action'),'notes',jsonb_build_object(id,'72'),
 'photos',jsonb_build_object(id,'b0190000-0000-4000-8000-000000000021/b0190000-0000-4000-8000-000000000002/b0190000-0000-4000-8000-000000000040/'||id||'.jpg'),
 'issues',jsonb_build_object(id,jsonb_build_object('message','Pressure climbs after shutdown','urgency','urgent','safe_to_operate','unsafe')))
 from issue_ids where name='item';
select public.submit_operations_checklist('b0190000-0000-4000-8000-000000000040',(select payload from issue_data));
select public.submit_operations_checklist('b0190000-0000-4000-8000-000000000040',(select payload from issue_data));
select pg_temp.ok((select count(*)=1 from public.checklist_issue_context where run_id='b0190000-0000-4000-8000-000000000040'),'same retry creates one context');
select pg_temp.ok((select message='Pressure climbs after shutdown' and safe_to_operate='unsafe' and urgency='urgent' from public.checklist_issue_context where run_id='b0190000-0000-4000-8000-000000000040'),'issue narrative and assessment persisted');
select pg_temp.ok((select snapshot->'items'->0->>'note'='72' from public.saved_checklists where id='b0190000-0000-4000-8000-000000000040'),'numeric reading remains intact');
select pg_temp.ok((select jsonb_array_length(public.coordination_thread('checklist','b0190000-0000-4000-8000-000000000040')->'posts')=1),'one original issue post');
insert into issue_ids select 'fault',fault_id from public.checklist_issue_context where run_id='b0190000-0000-4000-8000-000000000040';
select pg_temp.rejected($q$select public.submit_operations_checklist('b0190000-0000-4000-8000-000000000040',jsonb_set(payload,array['issues',(select id::text from issue_ids where name='item'),'message'],'"Changed message"')) from issue_data$q$);
select pg_temp.rejected($q$select public.submit_operations_checklist(gen_random_uuid(),payload||jsonb_build_object('issues',jsonb_build_object(gen_random_uuid(),'{}'::jsonb))) from issue_data$q$);
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
select pg_temp.ok((select count(*)=1 from public.notifications where user_id='b0190000-0000-4000-8000-000000000001' and type='checklist_issue' and reference_id='b0190000-0000-4000-8000-000000000040'),'responsible manager receives issue notification');
select pg_temp.ok((select f->>'description' like '%Pressure climbs after shutdown%' and f->>'severity'='urgent' from public.maintenance_faults(null,(select id from issue_ids where name='fault')) f),'fault contains operator narrative without retyping');
insert into issue_ids select 'job',public.plan_fault_work_order((select id from issue_ids where name='fault'),
 (select (f->>'revision')::int from public.maintenance_faults(null,(select id from issue_ids where name='fault')) f),gen_random_uuid(),
 '{"title":"Repair pressure relief","job_type":"repair","assigned_to":"b0190000-0000-4000-8000-000000000003"}');
select pg_temp.ok((select jsonb_array_length(public.coordination_thread('job',id)->'posts')=1 from issue_ids where name='job'),'original issue follows linked work order');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000003',true);
select public.post_coordination_message('b0190000-0000-4000-8000-000000000050','job',(select id from issue_ids where name='job'),'{"body":"Pressure relief replaced; ready for verification","visibility":"shared"}');
select public.post_coordination_message('b0190000-0000-4000-8000-000000000051','job',(select id from issue_ids where name='job'),'{"body":"Private workshop planning","visibility":"team"}');
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='operator-evidence' and name like 'b0190000-%'),'assigned mechanic can view original issue evidence');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
select pg_temp.ok(jsonb_array_length(public.coordination_thread('checklist','b0190000-0000-4000-8000-000000000040')->'posts')=2,'operator follows explicitly shared repair outcome');
select pg_temp.denied($q$select public.coordination_thread('job',id) from issue_ids where name='job'$q$);
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000005',true);
select pg_temp.denied($q$select public.coordination_thread('checklist','b0190000-0000-4000-8000-000000000040')$q$);
select pg_temp.ok((select count(*)=0 from public.checklist_issue_context where run_id='b0190000-0000-4000-8000-000000000040'),'other company cannot read issue context');
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='operator-evidence' and name like 'b0190000-%'),'other company cannot read issue photo');
reset role;
select pg_temp.ok((select count(*)=0 from public.notifications where user_id='b0190000-0000-4000-8000-000000000004' and reference_id='b0190000-0000-4000-8000-000000000040'),'other company manager not notified');
select pg_temp.ok((select count(*)=3 from public.asset_history_entries where category='discussion' and asset_id='b0190000-0000-4000-8000-000000000021'),'each conversation message has one history event');
rollback;
