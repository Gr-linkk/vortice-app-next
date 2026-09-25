begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_error(command text,expected text) returns void language plpgsql as $$
begin begin execute command; exception when others then
 if position(expected in sqlerrm)>0 then return; end if; raise; end;
 raise exception 'Expected error: %',expected; end $$;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select ('b0060000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'purpose-'||n||'@example.invalid',now(),'{"onboarding_v2":true}'::jsonb from generate_series(1,5) n;
create temp table fixture(key text primary key,value text);
grant all on fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error($q$select public.create_company_with_purpose('Company A','Owner A','invalid',gen_random_uuid())$q$,'Choose how');
select pg_temp.assert_true(public.active_organization_id() is null,'invalid selection leaves no partial company');
insert into fixture values('fleet',public.create_company_with_purpose('Company A','Owner A','fleet','b0061000-0000-4000-8000-000000000001')::text);
select pg_temp.assert_true(public.create_company_with_purpose('Company A','Owner A','fleet','b0061000-0000-4000-8000-000000000001')::text=(select value from fixture where key='fleet'),'retry returns same company');
select pg_temp.expect_error($q$select public.create_company_with_purpose('Company A','Owner A','both','b0061000-0000-4000-8000-000000000001')$q$,'different details');
select pg_temp.assert_true(public.organization_context()->'memberships'->0->>'company_purpose'='fleet','purpose survives context reload');
select pg_temp.assert_true(public.organization_service_configuration()->'settings'->>'provider_enabled'='false','fleet does not provide customer work');
select pg_temp.expect_error($q$select public.configure_organization_services(false,true)$q$,'Customer billing requires a service provider company');
select pg_temp.expect_error($q$select public.configure_organization_services(true,false)$q$,'Choose Service provider or Both');
insert into fixture values('invite',public.create_membership_invite(public.active_organization_id(),array['mechanic'])->>'code');
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000002',true);
insert into fixture values('service',public.create_company_with_purpose('Company B','Owner B','service','b0061000-0000-4000-8000-000000000002')::text);
select pg_temp.assert_true(public.organization_service_configuration()->'settings'->>'provider_enabled'='true','service enables customer work');
select public.configure_organization_services(true,true);
select pg_temp.assert_true(public.organization_service_configuration()->'settings'->>'billing_enabled'='true','service owner can enable customer billing');
select pg_temp.assert_true(public.organization_has_permission(public.active_organization_id(),'assets_manage') and public.organization_has_permission(public.active_organization_id(),'planning'),'service owner has fleet functions');
select pg_temp.assert_true(public.get_my_role()='member','service owner is never a platform owner');
select pg_temp.assert_true((select count(*)=3 from public.client_capabilities where client_id=auth.uid() and enabled and capability_key in ('pm_checklists','operational_checklists','maintenance_planning')),'service owner has all core capabilities');
select pg_temp.assert_true(jsonb_array_length(public.organization_context()->'memberships')=1,'other company is not exposed');
select public.set_company_purpose('both');
select pg_temp.assert_true(public.organization_context()->'memberships'->0->>'company_purpose'='both','existing owner can change purpose');
select public.set_company_purpose('fleet');
select pg_temp.assert_true(public.organization_service_configuration()->'settings'->>'billing_enabled'='false','switching to fleet turns off customer billing');
select pg_temp.expect_error($q$select public.configure_organization_services(false,true)$q$,'Customer billing requires a service provider company');
select public.set_company_purpose('both');
select public.configure_organization_services(false,false);
select pg_temp.assert_true(public.organization_context()->'memberships'->0->>'company_purpose' is null,'older client changes cannot leave contradictory purpose');
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000003',true);
insert into fixture values('both',public.create_company_with_purpose('Company C','Owner C','both','b0061000-0000-4000-8000-000000000003')::text);
select pg_temp.assert_true(public.organization_service_configuration()->'settings'->>'provider_enabled'='true','both enables customer work');
select pg_temp.assert_true(public.organization_has_permission(public.active_organization_id(),'assets_manage'),'both retains fleet functions');
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000004',true);
select public.redeem_membership_invite((select value from fixture where key='invite'),'Mechanic A');
select pg_temp.assert_true(public.organization_context()->'memberships'->0->>'company_purpose'='fleet','invite inherits company purpose');
select pg_temp.expect_error($q$select public.set_company_purpose('service')$q$,'Company Owner required');
select pg_temp.expect_error($q$select public.create_company_with_purpose('Wrong Company','Mechanic A','service',gen_random_uuid())$q$,'already available');
select pg_temp.assert_true(not public.organization_has_permission(public.active_organization_id(),'billing'),'invited mechanic has no billing');
select set_config('request.jwt.claim.sub','b0060000-0000-4000-8000-000000000005',true);
select public.create_company_workspace('Older client','Older owner');
select pg_temp.assert_true(public.organization_context()->'memberships'->0->>'company_purpose' is null,'older clients work without guessed purpose');
select pg_temp.expect_error('select * from public.company_onboarding_operations','permission denied');
rollback;
