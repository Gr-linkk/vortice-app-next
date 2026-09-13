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
