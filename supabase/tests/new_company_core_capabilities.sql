begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select ('b0332000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'core-default-'||n||'@example.invalid',now(),'{"onboarding_v2":true}'
from generate_series(1,2) n;
-- Explicit off is not a missing default, even for a newly created company.
insert into public.client_capabilities(client_id,capability_key,enabled)
values('b0332000-0000-4000-8000-000000000002','pm_checklists',false);
create temp table original_capabilities as select * from public.client_capabilities
where client_id not in ('b0332000-0000-4000-8000-000000000001','b0332000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0332000-0000-4000-8000-000000000001',true);
select public.create_company_workspace('Core Default Company','Core Owner');
select pg_temp.assert_true(public.checklist_can_author(auth.uid(),'operator_daily'),'new owner can author core operator checklists');
select pg_temp.assert_true(public.checklist_can_author(auth.uid(),'pm'),'new owner can author core PM checklists');
select set_config('request.jwt.claim.sub','b0332000-0000-4000-8000-000000000002',true);
select public.create_company_workspace('Explicit Disabled Company','Disabled Owner');
select pg_temp.assert_true(not public.checklist_can_author(auth.uid(),'pm'),'explicitly disabled PM still enforced');
select pg_temp.assert_true(public.checklist_can_author(auth.uid(),'operator_daily'),'other missing defaults initialize normally');
reset role;
select pg_temp.assert_true((select count(*)=3 from public.client_capabilities where client_id='b0332000-0000-4000-8000-000000000001' and enabled),'exactly three core workflows initialized');
select pg_temp.assert_true((select count(*)=3 from public.client_capabilities where client_id='b0332000-0000-4000-8000-000000000002'),'no duplicate or extra capabilities');
select pg_temp.assert_true((select not enabled from public.client_capabilities where client_id='b0332000-0000-4000-8000-000000000002' and capability_key='pm_checklists'),'explicit off remains off');
select pg_temp.assert_true(not exists(select * from original_capabilities except select * from public.client_capabilities),'all preexisting capability rows unchanged');
select pg_temp.assert_true((select count(*)=2 from public.organization_membership_events where actor_id in ('b0332000-0000-4000-8000-000000000001','b0332000-0000-4000-8000-000000000002') and action='core_capabilities_initialized'),'defaults initialization audited');
select pg_temp.assert_true(not has_function_privilege('authenticated','public.create_company_workspace_before_core_defaults(text,text)','execute'),'private pre-default creation cannot bypass initialization');
rollback;
