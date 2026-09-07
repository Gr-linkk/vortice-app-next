begin;
create function pg_temp.ok(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.denied(command text) returns void language plpgsql as $$
begin begin execute command; exception when others then return; end;
 raise exception 'Expected denial'; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('a0200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'workflow-'||n||'@example.invalid','{}' from generate_series(1,6) n;
update public.profiles set role=case right(id::text,1) when '1' then 'client' when '2' then 'client'
 when '3' then 'owner' when '4' then 'client_mechanic' when '5' then 'client_admin' else 'operator' end,
 full_name='Workflow '||right(id::text,1) where id::text like 'a0200000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0200000-0000-4000-8000-000000000010','Document company','a0200000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0200000-0000-4000-8000-000000000010'
 where id::text like 'a0200000-%' and right(id::text,1) in ('1','4','5','6');
insert into public.client_capabilities(client_id,capability_key,enabled)
select 'a0200000-0000-4000-8000-000000000001',k,true from unnest(array['pm_checklists','operational_checklists','maintenance_planning']) k;
insert into public.asset_types(id,category,name) values('a0200000-0000-4000-8000-000000000020','test','Test machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0200000-0000-4000-8000-000000000021','a0200000-0000-4000-8000-000000000001','a0200000-0000-4000-8000-000000000020','Machine A'),
 ('a0200000-0000-4000-8000-000000000022','a0200000-0000-4000-8000-000000000002','a0200000-0000-4000-8000-000000000020','Machine B');
create temp table results(name text primary key,value jsonb);
grant all on results to authenticated,anon;
create function pg_temp.token(n text) returns text language sql as $$ select value->>'token' from results where name=n $$;
create function pg_temp.checklist() returns jsonb language sql as $$ select '{
 "document_id":"a0200000-0000-4000-8000-000000000040","asset_id":"a0200000-0000-4000-8000-000000000021",
 "name":"Pre-start cooling inspection","checklist_type":"operator_daily",
 "items":[{"description_en":"Check coolant with the engine cold.","source_page":1,"source_quote":"Check coolant only when the engine is cold.","definition":{"input_type":"check","critical":true}}]}'::jsonb $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0200000-0000-4000-8000-000000000001',true);
insert into results values('read',public.create_agent_connection('a0200000-0000-4000-8000-000000000001','Read'));
insert into results values('docs',public.create_agent_workflow_connection('a0200000-0000-4000-8000-000000000001','Documents',false,true,false));
insert into results values('manage',public.create_agent_workflow_connection('a0200000-0000-4000-8000-000000000001','Manage',true,false,true));
select public.save_maintenance_document('a0200000-0000-4000-8000-000000000040','a0200000-0000-4000-8000-000000000001','Maintenance manual rev 1');
select pg_temp.denied($q$select public.save_maintenance_document('a0200000-0000-4000-8000-000000000040','a0200000-0000-4000-8000-000000000001','Maintenance manual rev 1',1)$q$);
insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'maintenance-documents','a0200000-0000-4000-8000-000000000040/1.jpg');
select pg_temp.denied($q$insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'maintenance-documents','a0200000-0000-4000-8000-000000000040/../2.jpg')$q$);
select public.save_maintenance_document('a0200000-0000-4000-8000-000000000040','a0200000-0000-4000-8000-000000000001','Maintenance manual rev 1',1);
select public.save_maintenance_document('a0200000-0000-4000-8000-000000000040','a0200000-0000-4000-8000-000000000001','Maintenance manual rev 1',1);
select pg_temp.ok((select count(*)=1 from public.maintenance_document_pages),'finalize replays');
select pg_temp.denied($q$update public.maintenance_documents set title='Different manual'$q$);
select pg_temp.denied($q$insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'maintenance-documents','a0200000-0000-4000-8000-000000000040/1.jpg')$q$);
select public.create_maintenance_job('a0200000-0000-4000-8000-000000000030','{"asset_id":"a0200000-0000-4000-8000-000000000021","title":"Cooling service"}');
select public.create_maintenance_job('a0200000-0000-4000-8000-000000000031','{"asset_id":"a0200000-0000-4000-8000-000000000021","title":"Hydraulic service"}');
select public.save_maintenance_setup(gen_random_uuid(),'component','a0200000-0000-4000-8000-000000000041',0,
 '{"asset_id":"a0200000-0000-4000-8000-000000000021","label":"Main engine","current_hours":250}');
select set_config('request.jwt.claim.sub','a0200000-0000-4000-8000-000000000002',true);
select pg_temp.ok((select count(*)=0 from public.maintenance_documents),'other company cannot read document');
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='maintenance-documents'),'other company cannot read pages');
select pg_temp.denied($q$insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'maintenance-documents','a0200000-0000-4000-8000-000000000040/2.jpg')$q$);
set local role anon;
select pg_temp.denied('select * from public.maintenance_document_pages');
select pg_temp.ok(public.agent_execute(pg_temp.token('read'),'documents')->>'error'='Document permission required','read cannot access scans');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'documents')->'data'->'documents'->0->>'pages'='1','agent lists finalized source');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'document_page','{"document_id":"a0200000-0000-4000-8000-000000000040","page":1}')->'data'->>'object_path'='a0200000-0000-4000-8000-000000000040/1.jpg','agent gets authorized page');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'document_page','{"document_id":"a0200000-0000-4000-8000-000000000099","page":1}')->>'error'='Access denied','unknown document denied');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'create_checklist_draft',pg_temp.checklist()||'{"asset_id":"a0200000-0000-4000-8000-000000000022"}',gen_random_uuid())->>'error'='Access denied','forged checklist fleet denied');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'create_checklist_draft',jsonb_set(pg_temp.checklist(),'{items,0,source_page}','2'),gen_random_uuid())->>'error'='Each step needs a source page and quote','missing page denied');
insert into results values('checklist',public.agent_execute(pg_temp.token('docs'),'create_checklist_draft',pg_temp.checklist(),'a0200000-0000-4000-8000-000000000070'));
select pg_temp.ok((select value->'data'->>'status'='draft' from results where name='checklist'),'preop draft created');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'create_checklist_draft',pg_temp.checklist(),'a0200000-0000-4000-8000-000000000070')->'data'->>'replayed'='true','draft replay');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'create_checklist_draft',pg_temp.checklist()||'{"name":"Changed name"}','a0200000-0000-4000-8000-000000000070')->>'error'='Operation ID used with different input','draft replay conflict');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'publish_checklist',pg_temp.checklist(),gen_random_uuid())->>'error'='Unknown action','agent cannot publish');
select pg_temp.ok(public.agent_execute(pg_temp.token('read'),'assign_work_order','{}',gen_random_uuid())->>'error'='Management permission required','management is separate permission');
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'work_order_context','{"asset_id":"a0200000-0000-4000-8000-000000000021"}')->'data'->'work_orders'->0->>'revision'='0','current revision readable');
insert into results values('assigned',public.agent_execute(pg_temp.token('manage'),'assign_work_order','{"work_order_id":"a0200000-0000-4000-8000-000000000030","revision":0,"assigned_to":"a0200000-0000-4000-8000-000000000004"}','a0200000-0000-4000-8000-000000000071'));
select pg_temp.ok((select value->'data'->>'revision'='1' from results where name='assigned'),'assign uses checked transition');
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'assign_work_order','{"work_order_id":"a0200000-0000-4000-8000-000000000030","revision":0,"assigned_to":"a0200000-0000-4000-8000-000000000004"}','a0200000-0000-4000-8000-000000000071')->'data'->>'replayed'='true','assignment exact retry');
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'assign_work_order','{"work_order_id":"a0200000-0000-4000-8000-000000000030","revision":0,"assigned_to":"a0200000-0000-4000-8000-000000000001"}',gen_random_uuid()) ? 'error','stale revision denied');
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'assign_work_order','{"work_order_id":"a0200000-0000-4000-8000-000000000030","revision":1,"assigned_to":"a0200000-0000-4000-8000-000000000002"}',gen_random_uuid()) ? 'error','other company assignee denied');
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'schedule_work_order','{"work_order_id":"a0200000-0000-4000-8000-000000000030","revision":1,"assigned_to":"a0200000-0000-4000-8000-000000000004","planned_start":"2026-09-10T10:00:00Z","estimated_minutes":60,"priority":"normal","note":"Schedule service"}',gen_random_uuid()) ? 'data','agent schedules');
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'schedule_work_order','{"work_order_id":"a0200000-0000-4000-8000-000000000031","revision":0,"assigned_to":"a0200000-0000-4000-8000-000000000004","planned_start":"2026-09-10T10:30:00Z","estimated_minutes":60,"priority":"normal","note":"Schedule conflict"}',gen_random_uuid()) ? 'error','overlapping schedule denied');
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'edit_work_order','{"work_order_id":"a0200000-0000-4000-8000-000000000030","revision":2,"title":"Inspect cooling system","description":"Follow reviewed checklist","job_type":"inspection","expected_materials":"Coolant","priority":"high","note":"Clarify scope"}',gen_random_uuid()) ? 'data','scope edit through checked RPC');
insert into results values('plan_input','{"asset_id":"a0200000-0000-4000-8000-000000000021","document_id":"a0200000-0000-4000-8000-000000000040","engine_id":"a0200000-0000-4000-8000-000000000041","interval_label":"Cooling service","interval_hours":250,"source_page":1,"source_quote":"Service cooling system every 250 hours"}');
insert into results values('plan',public.agent_execute(pg_temp.token('docs'),'create_plan_draft',(select value from results where name='plan_input'),'a0200000-0000-4000-8000-000000000075'));
select pg_temp.ok((select value->'data'->>'status'='draft' from results where name='plan'),'agent proposes actual draft plan');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'create_plan_draft',(select value from results where name='plan_input'),'a0200000-0000-4000-8000-000000000075')->'data'->>'replayed'='true','plan proposal exact retry');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'create_plan_draft',(select value||'{"last_service_hours":0}' from results where name='plan_input'),gen_random_uuid())->>'error'='Invalid input','agent cannot invent baseline');
select pg_temp.denied($q$select public.apply_agent_plan_draft((select (value->'data'->>'plan_draft_id')::uuid from results where name='plan'),gen_random_uuid(),'{}')$q$);
reset role;
select pg_temp.ok((select count(*)=0 from public.asset_service_intervals where source_agent_plan_id is not null),'proposal does not activate an interval');
select pg_temp.ok((select count(*)=1 from public.checklist_procedures where client_id='a0200000-0000-4000-8000-000000000001' and published_template_id is null),'one private unpublised draft');
select pg_temp.ok((select draft->'items'->0->'definition'->>'source_document_id'='a0200000-0000-4000-8000-000000000040' from public.checklist_procedures where id=(select (value->'data'->>'procedure_id')::uuid from results where name='checklist')),'source provenance persists');
select pg_temp.ok((select assigned_to='a0200000-0000-4000-8000-000000000004'::uuid and title='Inspect cooling system' and status='assigned' from public.work_orders where id='a0200000-0000-4000-8000-000000000030'),'actual work state updated');
select pg_temp.ok((select count(*)=1 from public.agent_activity where action='assign_work_order' and outcome='created'),'one durable assignment audit');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0200000-0000-4000-8000-000000000001',true);
select public.save_checklist_procedure(gen_random_uuid(),(select (value->'data'->>'procedure_id')::uuid from results where name='checklist'),1,'publish','{}');
select pg_temp.ok((select count(*)=1 from public.checklist_items where definition->>'source_document_id'='a0200000-0000-4000-8000-000000000040'),'publication retains source in immutable step');
select pg_temp.denied($q$select public.apply_agent_plan_draft((select (value->'data'->>'plan_draft_id')::uuid from results where name='plan'),gen_random_uuid(),'{"last_service_hours":""}')$q$);
insert into results values('review_input','{"engine_id":"a0200000-0000-4000-8000-000000000041","interval_label":"Reviewed cooling service","interval_hours":"300","last_service_hours":"100","is_active":true,"source_reviewed":true,"review_current_hours":250}');
select pg_temp.denied($q$select public.apply_agent_plan_draft((select (value->'data'->>'plan_draft_id')::uuid from results where name='plan'),gen_random_uuid(),(select value||'{"review_current_hours":200}' from results where name='review_input'))$q$);
select pg_temp.denied($q$select public.apply_agent_plan_draft((select (value->'data'->>'plan_draft_id')::uuid from results where name='plan'),gen_random_uuid(),(select value||'{"last_service_hours":300}' from results where name='review_input'))$q$);
insert into results select 'applied',to_jsonb(public.apply_agent_plan_draft((select (value->'data'->>'plan_draft_id')::uuid from results where name='plan'),
 'a0200000-0000-4000-8000-000000000076',(select value from results where name='review_input')));
select pg_temp.ok(to_jsonb(public.apply_agent_plan_draft((select (value->'data'->>'plan_draft_id')::uuid from results where name='plan'),
 'a0200000-0000-4000-8000-000000000076',(select value from results where name='review_input')))=(select value from results where name='applied'),'human activation retry creates no duplicate');
select pg_temp.denied($q$select public.apply_agent_plan_draft((select (value->'data'->>'plan_draft_id')::uuid from results where name='plan'),gen_random_uuid(),(select value from results where name='review_input'))$q$);
reset role;
select pg_temp.ok((select count(*)=1 from public.asset_service_intervals where source_agent_plan_id is not null and interval_hours=300 and last_service_hours=100 and next_due_hours=400),'human tweaks persisted and baseline used');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0200000-0000-4000-8000-000000000002',true);
select pg_temp.ok((select count(*)=0 from public.agent_plan_drafts),'other company cannot read proposed plans');
select set_config('request.jwt.claim.sub','a0200000-0000-4000-8000-000000000001',true);
set local role anon;
insert into results values('existing_proposal',public.agent_execute(pg_temp.token('docs'),'create_plan_draft',
 (select value from results where name='plan_input')||jsonb_build_object('existing_plan_id',(select value from results where name='applied')),gen_random_uuid()));
select pg_temp.ok((select (value->'data'->'equipment_context'->>'recorded_current_hours')::numeric=250
 and (value->'data'->'equipment_context'->>'recorded_last_service_hours')::numeric=100
 and (value->'data'->'equipment_context'->>'proposed_next_due_hours')::numeric=350 from results where name='existing_proposal'),'manual plus current hours and task history yield due point');
set local role authenticated;
select public.apply_agent_plan_draft((select (value->'data'->>'plan_draft_id')::uuid from results where name='existing_proposal'),gen_random_uuid(),
 (select value||'{"revision":0,"interval_hours":"200"}' from results where name='review_input'));
reset role;
select pg_temp.ok((select count(*)=1 from public.asset_service_intervals where asset_id='a0200000-0000-4000-8000-000000000021')
 and (select interval_hours=200 and last_service_hours=100 and next_due_hours=300 from public.asset_service_intervals where id=(select (value#>>'{}')::uuid from results where name='applied')),'review updates existing plan without duplicating or replacing history');
set local role authenticated;
select public.revoke_agent_connections((select (value->>'id')::uuid from results where name='manage'));
set local role anon;
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'work_order_context','{"asset_id":"a0200000-0000-4000-8000-000000000021"}')->>'error'='Access denied','revocation blocks workflow');
reset role;
insert into auth.mfa_factors(id,user_id,factor_type,status) values(gen_random_uuid(),'a0200000-0000-4000-8000-000000000003','totp','verified');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0200000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
insert into results values('owner',public.create_agent_workflow_connection('a0200000-0000-4000-8000-000000000001','Owner document assistant',false,true,false));
set local role anon;
select pg_temp.ok(public.agent_execute(pg_temp.token('owner'),'create_checklist_draft',pg_temp.checklist()||'{"checklist_type":"pm","name":"Owner sourced PM"}',gen_random_uuid()) ? 'data','owner can draft private fleet PM');
reset role;
select pg_temp.ok((select count(*)=1 from public.checklist_procedures where created_by='a0200000-0000-4000-8000-000000000003' and client_id='a0200000-0000-4000-8000-000000000001'),'owner source stays company-private');
update public.client_capabilities set enabled=false where client_id='a0200000-0000-4000-8000-000000000001';
set local role anon;
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'create_checklist_draft',pg_temp.checklist(),gen_random_uuid())->>'error'='Access denied','removed checklist capability blocks writes');
rollback;
