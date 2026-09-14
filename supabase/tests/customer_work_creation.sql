begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_error(command text,expected text) returns void language plpgsql as $$
begin begin execute command; exception when others then if position(expected in sqlerrm)>0 then return; end if; raise; end;
raise exception 'Expected error: %',expected; end $$;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select ('b0190000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'org-work-'||n||'@example.invalid',now(),'{"onboarding_v2":true}'
from generate_series(1,6) n;
insert into auth.users(id,email) values('b0190000-0000-4000-8000-000000000007','legacy-provider@example.invalid');
update public.profiles set role='owner' where id='b0190000-0000-4000-8000-000000000007';
create temp table fixture(key text primary key,value text);grant all on fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
insert into fixture values('provider',public.create_company_workspace('Provider company','Provider owner')::text);
select public.configure_organization_services(true,true);
insert into fixture values('mechanic_invite',public.create_membership_invite(public.active_organization_id(),array['mechanic'])->>'code');
insert into fixture values('supervisor_invite',public.create_membership_invite(public.active_organization_id(),array['supervisor'])->>'code');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
insert into fixture values('customer',public.create_company_workspace('Customer company','Customer owner')::text);
insert into fixture values('company_code',public.organization_service_configuration()->'settings'->>'connection_code');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
insert into fixture values('relationship',public.propose_organization_customer((select value from fixture where key='company_code'))::text);
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
select public.set_organization_relationship((select value::uuid from fixture where key='provider'),public.active_organization_id(),'accept');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000003',true);
select public.redeem_membership_invite((select value from fixture where key='mechanic_invite'),'Assigned mechanic');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000004',true);
select public.redeem_membership_invite((select value from fixture where key='supervisor_invite'),'Provider supervisor');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000005',true);
insert into fixture values('unrelated',public.create_company_workspace('Other company','Other owner')::text);
reset role;
insert into public.asset_types(id,category,name) values('b0190000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('b0190000-0000-4000-8000-000000000021','b0190000-0000-4000-8000-000000000002','b0190000-0000-4000-8000-000000000020','Customer machine'),
 ('b0190000-0000-4000-8000-000000000022','b0190000-0000-4000-8000-000000000005','b0190000-0000-4000-8000-000000000020','Unrelated machine');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
select public.save_checklist_procedure(gen_random_uuid(),'b0190000-0000-4000-8000-000000000040',0,'draft',
 '{"name":"Creation checklist","checklist_type":"pm","items":[{"description_en":"Check pressure","requires_photo":true}]}');
select public.save_checklist_procedure(gen_random_uuid(),'b0190000-0000-4000-8000-000000000040',1,'publish','{}');
insert into fixture select 'template',id::text from public.checklist_templates where procedure_id='b0190000-0000-4000-8000-000000000040';
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000005',true);
select public.save_checklist_procedure(gen_random_uuid(),'b0190000-0000-4000-8000-000000000041',0,'draft',
 '{"name":"Private checklist","checklist_type":"pm","items":[{"description_en":"Private step"}]}');
select public.save_checklist_procedure(gen_random_uuid(),'b0190000-0000-4000-8000-000000000041',1,'publish','{}');
insert into fixture select 'private_template',id::text from public.checklist_templates where procedure_id='b0190000-0000-4000-8000-000000000041';
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
select public.request_organization_work('b0190000-0000-4000-8000-000000000030',(select value::uuid from fixture where key='relationship'),
 'b0190000-0000-4000-8000-000000000021','Repair customer machine','Customer request details');
select public.request_organization_work('b0190000-0000-4000-8000-000000000030',(select value::uuid from fixture where key='relationship'),
 'b0190000-0000-4000-8000-000000000021','Repair customer machine','Customer request details');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(jsonb_array_length(public.customer_work_creation_context()->'equipment')=1,'only customer-shared equipment offered');
select pg_temp.expect_error($q$select public.create_customer_work(gen_random_uuid(),(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000022','Private equipment','')$q$,'not available');
select public.create_customer_work('b0190000-0000-4000-8000-000000000080',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Follow up repair','Preserve context');
select public.create_customer_work('b0190000-0000-4000-8000-000000000080',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Follow up repair','Preserve context');
select pg_temp.assert_true((select count(*)=2 from public.organization_work_orders()),'follow up and request each appear once');
select public.create_customer_work('b0190000-0000-4000-8000-000000000081',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Calendar repair','Selected day','2026-09-20');
select public.create_customer_work('b0190000-0000-4000-8000-000000000081',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Calendar repair','Selected day','2026-09-20');
select pg_temp.assert_true((select scheduled_date='2026-09-20'::date from public.work_orders where id='b0190000-0000-4000-8000-000000000081'),'calendar creation preserves selected service day');
select pg_temp.expect_error($q$select public.create_customer_work('b0190000-0000-4000-8000-000000000081',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Calendar repair','Selected day','2026-09-21')$q$,'Retry input differs');
select pg_temp.expect_error($q$select public.create_customer_work('b0190000-0000-4000-8000-000000000080',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Changed repair','')$q$,'Retry input differs');
-- Checklist and edited date are created together; retry cannot change either.
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.customer_work_creation_context()->'equipment'->0->'templates') t where t->>'id'=(select value from fixture where key='template')),'compatible provider checklist offered');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.customer_work_creation_context()->'equipment'->0->'templates') t where t->>'id'=(select value from fixture where key='private_template')),'other company checklist hidden');
select public.create_customer_work('b0190000-0000-4000-8000-000000000082',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Prepared work','Check the pressure','2026-09-23',(select value::uuid from fixture where key='template'));
select public.create_customer_work('b0190000-0000-4000-8000-000000000082',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Prepared work','Check the pressure','2026-09-23',(select value::uuid from fixture where key='template'));
select pg_temp.assert_true((select scheduled_date='2026-09-23'::date and checklist_template_id=(select value::uuid from fixture where key='template') and checklist_template_version=1 and parts_kit_captured from public.work_orders where id='b0190000-0000-4000-8000-000000000082'),'date checklist version and kit saved');
select pg_temp.assert_true(jsonb_array_length(public.organization_work_order_context('b0190000-0000-4000-8000-000000000082')->'checklist_snapshot')=1,'checklist steps available immediately');
select pg_temp.expect_error($q$select public.create_customer_work('b0190000-0000-4000-8000-000000000082',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Prepared work','Check the pressure','2026-09-23',null)$q$,'Retry input differs');
select pg_temp.expect_error($q$select public.create_customer_work('b0190000-0000-4000-8000-000000000082',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Prepared work','Check the pressure','2026-09-24',(select value::uuid from fixture where key='template'))$q$,'Retry input differs');
select pg_temp.expect_error($q$select public.create_customer_work('b0190000-0000-4000-8000-000000000083',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Private procedure','','2026-09-23',(select value::uuid from fixture where key='private_template'))$q$,'published provider checklist');
select pg_temp.assert_true(not exists(select 1 from public.work_orders where id='b0190000-0000-4000-8000-000000000083'),'invalid checklist rolls back work');
select public.create_customer_work('b0190000-0000-4000-8000-000000000083',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Unscheduled work','',null,null);
select pg_temp.assert_true((select scheduled_date is null and checklist_template_id is null from public.work_orders where id='b0190000-0000-4000-8000-000000000083'),'cleared choices persist and rejection leaves no receipt');
reset role;
update public.checklist_templates set is_active=false where id=(select value::uuid from fixture where key='template');
set local role authenticated;
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.customer_work_creation_context()->'equipment'->0->'templates') t where t->>'id'=(select value from fixture where key='template')),'retired checklist hidden');
select pg_temp.expect_error($q$select public.create_customer_work(gen_random_uuid(),(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Retired procedure','',null,(select value::uuid from fixture where key='template'))$q$,'published provider checklist');
-- An acknowledged creation can be retried after its template is retired.
select public.create_customer_work('b0190000-0000-4000-8000-000000000082',(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Prepared work','Check the pressure','2026-09-23',(select value::uuid from fixture where key='template'));
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(jsonb_array_length(public.customer_work_creation_context()->'equipment')=0,'mechanic cannot create customer work');
select pg_temp.expect_error($q$select public.create_customer_work(gen_random_uuid(),(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Unauthorized repair','','2026-09-20')$q$,'not available');
select pg_temp.expect_error($q$select public.create_customer_work(gen_random_uuid(),(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Unauthorized repair','')$q$,'not available');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(not(public.organization_work_order_context('b0190000-0000-4000-8000-000000000080')->'work_order' ? 'notes_internal'),'customer sees follow up without private notes');
select public.set_organization_relationship((select value::uuid from fixture where key='provider'),public.active_organization_id(),'revoke');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(jsonb_array_length(public.customer_work_creation_context()->'equipment')=0,'revoked customer no longer offered');
select pg_temp.expect_error($q$select public.create_customer_work(gen_random_uuid(),(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000021','Revoked repair','')$q$,'not available');
rollback;
