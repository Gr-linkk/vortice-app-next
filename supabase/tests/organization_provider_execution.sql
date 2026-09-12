begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_error(command text,expected text) returns void language plpgsql as $$
begin begin execute command; exception when others then if position(expected in sqlerrm)>0 then return; end if; raise; end;
raise exception 'Expected error: %',expected; end $$;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select ('b0230000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'org-work-'||n||'@example.invalid',now(),'{"onboarding_v2":true}'
from generate_series(1,6) n;
insert into auth.users(id,email) values('b0230000-0000-4000-8000-000000000007','legacy-provider@example.invalid');
update public.profiles set role='owner' where id='b0230000-0000-4000-8000-000000000007';
create temp table fixture(key text primary key,value text);grant all on fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000001',true);
insert into fixture values('provider',public.create_company_workspace('Provider company','Provider owner')::text);
select public.configure_organization_services(true,true);
insert into fixture values('mechanic_invite',public.create_membership_invite(public.active_organization_id(),array['mechanic'])->>'code');
insert into fixture values('supervisor_invite',public.create_membership_invite(public.active_organization_id(),array['supervisor'])->>'code');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000002',true);
insert into fixture values('customer',public.create_company_workspace('Customer company','Customer owner')::text);
insert into fixture values('company_code',public.organization_service_configuration()->'settings'->>'connection_code');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000001',true);
insert into fixture values('relationship',public.propose_organization_customer((select value from fixture where key='company_code'))::text);
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000002',true);
select public.set_organization_relationship((select value::uuid from fixture where key='provider'),public.active_organization_id(),'accept');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000003',true);
select public.redeem_membership_invite((select value from fixture where key='mechanic_invite'),'Assigned mechanic');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000004',true);
select public.redeem_membership_invite((select value from fixture where key='supervisor_invite'),'Provider supervisor');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000005',true);
insert into fixture values('unrelated',public.create_company_workspace('Other company','Other owner')::text);
reset role;
insert into public.asset_types(id,category,name) values('b0230000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('b0230000-0000-4000-8000-000000000021','b0230000-0000-4000-8000-000000000002','b0230000-0000-4000-8000-000000000020','Customer machine'),
 ('b0230000-0000-4000-8000-000000000022','b0230000-0000-4000-8000-000000000005','b0230000-0000-4000-8000-000000000020','Unrelated machine');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000002',true);
select public.configure_asset_meter('b0230000-0000-4000-8000-000000000021','b0230000-0000-4000-8000-000000000060','km',62000);
reset role;
insert into public.client_capabilities(client_id,capability_key,enabled) values('b0230000-0000-4000-8000-000000000001','pm_checklists',true)
 on conflict(client_id,capability_key) do update set enabled=true;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000001',true);
select public.save_checklist_procedure(gen_random_uuid(),'b0230000-0000-4000-8000-000000000040',0,'draft',
 '{"name":"Provider inspection","checklist_type":"pm","items":[{"description_en":"Verify repaired pressure","requires_photo":true,"definition":{"input_type":"number","unit":"bar","min":2,"max":4,"equipment_state":"verification"}}]}');
select public.save_checklist_procedure(gen_random_uuid(),'b0230000-0000-4000-8000-000000000040',1,'publish','{}');
insert into fixture select 'template',t.id::text from public.checklist_templates t where t.procedure_id='b0230000-0000-4000-8000-000000000040';
insert into fixture select 'item',i.id::text from public.checklist_items i where i.template_id=(select value::uuid from fixture where key='template');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000002',true);
select public.request_organization_work('b0230000-0000-4000-8000-000000000030',(select value::uuid from fixture where key='relationship'),
 'b0230000-0000-4000-8000-000000000021','Repair the pressure loss','Customer source description');
select pg_temp.assert_true(not(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030') ? 'checklist_snapshot'),'customer has no private execution metadata');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000004',true);
create function pg_temp.change(action text,data jsonb default '{}',operation uuid default gen_random_uuid()) returns void language plpgsql as $$
begin perform public.change_organization_work('b0230000-0000-4000-8000-000000000030',
 (public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->>'revision')::integer,operation,action,data); end $$;
select pg_temp.change('configure',jsonb_build_object('checklist_template_id',(select value from fixture where key='template'),'procedure_notes','Isolate before repair; verify after restart.','service_date','2026-09-18'));
select pg_temp.change('assign','{"assigned_to":"b0230000-0000-4000-8000-000000000003"}');
select pg_temp.assert_true(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->'sources'->0->'snapshot'->>'description'='Customer source description','actual request context remains linked');
select pg_temp.assert_true(not public.maintenance_can_view_asset('b0230000-0000-4000-8000-000000000021'),'execution grants do not expose customer fleet');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select pg_temp.change('start','{"meter_value":62000,"meter_unit":"hours"}')$q$,'meter unit');
select public.change_organization_work('b0230000-0000-4000-8000-000000000030',2,'b0230000-0000-4000-8000-000000000031','start','{"meter_value":62000,"meter_unit":"km"}');
select public.change_organization_work('b0230000-0000-4000-8000-000000000030',2,'b0230000-0000-4000-8000-000000000031','start','{"meter_value":62000,"meter_unit":"km"}');
select pg_temp.assert_true(jsonb_array_length(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->'labour')=1,'start replay creates one shared timer');
select pg_temp.expect_error($q$select pg_temp.change('resume')$q$,'running labour timer');
select pg_temp.change('block','{"note":"Waiting for replacement seal"}');
select pg_temp.assert_true(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->'work_order'->>'status'='on_hold','block records work state');
select pg_temp.change('resume');
select pg_temp.expect_error($q$select pg_temp.change('configure','{}')$q$,'Prepare this work');
insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'maintenance-evidence','b0230000-0000-4000-8000-000000000030/b0230000-0000-4000-8000-000000000003/pressure.jpg');
insert into fixture values('answers',jsonb_build_object((select value from fixture where key='item'),jsonb_build_object('result','fail','note','1','issue_note','Pressure remains below specification','photo_path','b0230000-0000-4000-8000-000000000030/b0230000-0000-4000-8000-000000000003/pressure.jpg'))::text);
insert into fixture values('report',jsonb_build_object('diagnosis','Leaking pressure seal','repair','Replaced seal; verification pending','meter_value',62010,'meter_unit','km','answers',(select value::jsonb from fixture where key='answers'),'evidence_paths',jsonb_build_array('b0230000-0000-4000-8000-000000000030/b0230000-0000-4000-8000-000000000003/pressure.jpg'))::text);
select pg_temp.change('save_report',(select value::jsonb from fixture where key='report'));
select pg_temp.expect_error($q$select pg_temp.change('submit',(select value::jsonb from fixture where key='report'))$q$,'resolve failed steps');
select pg_temp.assert_true((public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->>'current_meter')::numeric=62000,'unapproved completion does not change equipment meter');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->'report'='null'::jsonb,'customer cannot see report draft');
select pg_temp.assert_true((select count(*)=0 from storage.objects where name like 'b0230000-0000-4000-8000-000000000030/%'),'customer cannot see unapproved report evidence');
select pg_temp.expect_error($q$select pg_temp.change('approve')$q$,'access denied');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000003',true);
update fixture set value=jsonb_set(value::jsonb,array['answers',(select value from fixture where key='item')],jsonb_build_object('result','pass','note','3','photo_path','b0230000-0000-4000-8000-000000000030/b0230000-0000-4000-8000-000000000003/pressure.jpg'))::text where key='report';
select pg_temp.expect_error($q$select pg_temp.change('submit',(select value::jsonb from fixture where key='report')||'{"evidence_paths":[]}'::jsonb)$q$,'required photo');
select pg_temp.change('submit',(select value::jsonb from fixture where key='report'));
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->'labour') l where l->>'stopped_at' is null),'submission stops the author timer');
select pg_temp.expect_error($q$select pg_temp.change('approve')$q$,'manager must approve');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000004',true);
select pg_temp.change('return','{"note":"Describe the pressure verification"}');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000003',true);
select pg_temp.change('save_report',(select value::jsonb from fixture where key='report'));
select pg_temp.assert_true(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->>'returned_at' is not null,'returned state remains until resubmission');
select pg_temp.change('submit',(select value::jsonb from fixture where key='report'));
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000004',true);
insert into fixture values('approve_revision',public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->>'revision');
select public.change_organization_work('b0230000-0000-4000-8000-000000000030',(select value::int from fixture where key='approve_revision'),'b0230000-0000-4000-8000-000000000032','approve');
select public.change_organization_work('b0230000-0000-4000-8000-000000000030',(select value::int from fixture where key='approve_revision'),'b0230000-0000-4000-8000-000000000032','approve');
select pg_temp.assert_true((public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->>'current_meter')::numeric=62010,'approval applies completion meter once');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->'report'->'answers'->(select value from fixture where key='item')->>'note'='3','customer receives approved checklist result');
select pg_temp.assert_true((select count(*)=1 from storage.objects where name like 'b0230000-0000-4000-8000-000000000030/%'),'customer receives only approved evidence');
select pg_temp.assert_true(not(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030') ? 'labour'),'customer does not receive labour session records');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000005',true);
select pg_temp.expect_error($q$select public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')$q$,'access denied');
select pg_temp.assert_true((select count(*)=0 from storage.objects where name like 'b0230000-0000-4000-8000-000000000030/%'),'unrelated company receives no evidence');
reset role;
select pg_temp.assert_true((select count(*)=1 from public.work_orders where id='b0230000-0000-4000-8000-000000000030'),'one canonical work order');
select pg_temp.assert_true((select count(*)=1 from public.service_reports where work_order_id='b0230000-0000-4000-8000-000000000030'),'one canonical report through return and replay');
select pg_temp.assert_true((select count(*)=1 from public.hour_logs where asset_id='b0230000-0000-4000-8000-000000000021' and notes='Approved provider work completion'),'one approved meter log');
rollback;
