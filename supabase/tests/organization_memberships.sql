begin;
-- The local Supabase auth scaffold is intentionally smaller than auth.users.
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_error(command text,expected text) returns void language plpgsql as $$
begin begin execute command; exception when others then
 if position(expected in sqlerrm)>0 then return; end if; raise; end;
 raise exception 'Expected error: %',expected; end $$;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select ('b0180000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'membership-'||n||'@example.invalid',case when n=3 then null else now() end,
 '{"onboarding_v2":true,"role":"owner","org_id":"b0180000-0000-4000-8000-000000000099"}'::jsonb
from generate_series(1,9) n;
insert into auth.users(id,phone,phone_confirmed_at,raw_user_meta_data)
values('b0180000-0000-4000-8000-000000000010','+15555550110',now(),'{"onboarding_v2":true}');
select pg_temp.assert_true((select count(*)=10 from public.profiles where id::text like 'b0180000-%' and role='member' and org_id is null),'untrusted signup metadata cannot assign owner or organization');
select pg_temp.assert_true((select email='' and phone='+15555550110' from public.profiles where id='b0180000-0000-4000-8000-000000000010'),'phone-only identity is supported');
create temp table fixture(key text primary key,value text);
grant all on fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.create_company_workspace('Unverified Company','Unverified Person')$q$,'Verify your email or phone');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000001',true);
insert into fixture values('org_a',public.create_company_workspace('Company A','Owner A')::text);
select pg_temp.assert_true(public.organization_context()->>'route_role'='client_admin','company owner has company routes');
select pg_temp.assert_true(public.get_my_role()='member','company ownership never creates platform/provider owner');
select pg_temp.assert_true(public.organization_has_permission(public.active_organization_id(),'billing'),'company owner has org billing');
select pg_temp.expect_error($q$update public.profiles set role='owner' where id=auth.uid()$q$,'authority must be changed');
select pg_temp.expect_error($q$update public.profiles set subscription_tier=3 where id=auth.uid()$q$,'authority must be changed');
update public.profiles set full_name='Owner A Updated' where id=auth.uid();
select pg_temp.assert_true((select full_name='Owner A Updated' from public.profiles where id=auth.uid()),'ordinary own profile update allowed');
insert into fixture values('supervisor',public.create_membership_invite(public.active_organization_id(),array['supervisor'],'{}','membership-4@example.invalid')->>'code');
insert into fixture values('operator',public.create_membership_invite(public.active_organization_id(),array['operator'])->>'code');
insert into fixture values('mechanic',public.create_membership_invite(public.active_organization_id(),array['mechanic','operator'])->>'code');
insert into fixture values('delegated',public.create_membership_invite(public.active_organization_id(),array['supervisor'],array['team_admin'])->>'code');
insert into fixture values('expired',public.create_membership_invite(public.active_organization_id(),array['operator'])->>'code');
insert into fixture values('revoked',public.create_membership_invite(public.active_organization_id(),array['operator'])->>'code');
select pg_temp.expect_error($q$insert into public.organization_memberships(organization_id,profile_id,roles)
 values(public.active_organization_id(),'b0180000-0000-4000-8000-000000000003',array['company_owner'])$q$,'permission denied');
select pg_temp.expect_error('select token_hash from public.organization_invitations','permission denied');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000002',true);
insert into fixture values('org_b',public.create_company_workspace('Company B','Owner B')::text);
select pg_temp.assert_true((select count(*)=0 from public.organization_memberships where organization_id=(select value::uuid from fixture where key='org_a')),'company B cannot read A membership');
select pg_temp.expect_error($q$select public.organization_team((select value::uuid from fixture where key='org_a'))$q$,'Team administration');
select pg_temp.expect_error($q$select public.redeem_membership_invite((select value from fixture where key='supervisor'),'Wrong Contact')$q$,'email or phone named');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000004',true);
select public.redeem_membership_invite((select value from fixture where key='supervisor'),'Supervisor A');
select public.redeem_membership_invite((select value from fixture where key='supervisor'),'Supervisor A');
select pg_temp.assert_true(public.organization_has_permission(public.active_organization_id(),'planning'),'supervisor plans work');
select pg_temp.assert_true(not public.organization_has_permission(public.active_organization_id(),'team_admin') and not public.organization_has_permission(public.active_organization_id(),'billing') and not public.organization_has_permission(public.active_organization_id(),'inspection_manage'),'supervisor has no implied team billing inspection admin');
select pg_temp.expect_error($q$select public.create_membership_invite(public.active_organization_id(),array['operator'])$q$,'Team administration');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000005',true);
select public.redeem_membership_invite((select value from fixture where key='operator'),'Operator A');
select pg_temp.assert_true(not public.organization_has_permission(public.active_organization_id(),'assets_manage') and public.organization_has_permission(public.active_organization_id(),'preop'),'operator can preop but not manage fleet');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000006',true);
select public.redeem_membership_invite((select value from fixture where key='mechanic'),'Mechanic Operator A');
select pg_temp.assert_true(public.organization_has_permission(public.active_organization_id(),'work_assigned') and public.organization_has_permission(public.active_organization_id(),'preop'),'multi-role preserves mechanic and operator work');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000007',true);
select public.redeem_membership_invite((select value from fixture where key='delegated'),'Team Administrator');
select public.create_membership_invite(public.active_organization_id(),array['operator']);
select pg_temp.expect_error($q$select public.create_membership_invite(public.active_organization_id(),array['company_owner'])$q$,'Only a Company Owner');
select pg_temp.expect_error($q$select public.create_membership_invite(public.active_organization_id(),array['supervisor'],array['billing'])$q$,'Only a Company Owner');
select pg_temp.expect_error($q$select public.update_organization_membership(public.active_organization_id(),auth.uid(),array['supervisor'],array['team_admin','billing'])$q$,'Only a Company Owner');
reset role;
update public.organization_invitations set expires_at=now()-interval '1 second' where token_hash=encode(extensions.digest((select value from fixture where key='expired'),'sha256'),'hex');
update public.organization_invitations set revoked_at=now() where token_hash=encode(extensions.digest((select value from fixture where key='revoked'),'sha256'),'hex');
insert into public.asset_types(id,category,name) values('b0180000-0000-4000-8000-000000000020','test','Membership machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('b0180000-0000-4000-8000-000000000021','b0180000-0000-4000-8000-000000000001','b0180000-0000-4000-8000-000000000020','Company A machine'),
 ('b0180000-0000-4000-8000-000000000022','b0180000-0000-4000-8000-000000000002','b0180000-0000-4000-8000-000000000020','Company B machine');
insert into public.client_capabilities(client_id,capability_key,enabled)
select 'b0180000-0000-4000-8000-000000000001'::uuid,key,true from unnest(array['pm_checklists','maintenance_planning','operational_checklists']) key
on conflict(client_id,capability_key) do update set enabled=excluded.enabled;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000008',true);
select pg_temp.expect_error($q$select public.redeem_membership_invite((select value from fixture where key='expired'),'Expired Invite')$q$,'Invitation expired');
select pg_temp.expect_error($q$select public.redeem_membership_invite((select value from fixture where key='revoked'),'Revoked Invite')$q$,'Invitation revoked');
select pg_temp.expect_error($q$select public.redeem_membership_invite((select value from fixture where key='operator'),'Used Invite')$q$,'Invitation already used');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000004',true);
select public.create_maintenance_job('b0180000-0000-4000-8000-000000000030',
 '{"asset_id":"b0180000-0000-4000-8000-000000000021","title":"Membership repair","assigned_to":"b0180000-0000-4000-8000-000000000006"}');
select pg_temp.assert_true(public.maintenance_can_read_job('b0180000-0000-4000-8000-000000000030'),'supervisor reads company work');
select pg_temp.expect_error($q$select public.create_asset_inspection('b0180000-0000-4000-8000-000000000021',gen_random_uuid(),'{"title":"Not delegated"}')$q$,'Access denied');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000005',true);
select pg_temp.assert_true((select count(*)=1 from public.assets where id::text like 'b0180000-%'),'operator reads only active company assets');
select pg_temp.assert_true(public.operations_can_submit('b0180000-0000-4000-8000-000000000021'),'operator product gate allows checks');
select pg_temp.assert_true(not public.maintenance_can_read_job('b0180000-0000-4000-8000-000000000030'),'operator cannot read private mechanic jobs');
select pg_temp.expect_error($q$select public.transfer_asset_custody('b0180000-0000-4000-8000-000000000021',0,gen_random_uuid(),'{"reason":"Forbidden custody"}')$q$,'Access denied');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000006',true);
select public.change_maintenance_job('b0180000-0000-4000-8000-000000000030',0,gen_random_uuid(),'start','{}');
select public.change_maintenance_job('b0180000-0000-4000-8000-000000000030',1,gen_random_uuid(),'pause','{}');
select pg_temp.expect_error($q$select public.change_maintenance_job('b0180000-0000-4000-8000-000000000030',2,gen_random_uuid(),'approve','{}')$q$,'Only a manager');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error($q$select public.update_organization_membership(public.active_organization_id(),auth.uid(),array['supervisor'],'{}')$q$,'at least one active Company Owner');
select public.update_organization_membership(public.active_organization_id(),'b0180000-0000-4000-8000-000000000004',array['supervisor'],array['inspection_manage']);
select public.update_organization_membership(public.active_organization_id(),'b0180000-0000-4000-8000-000000000005',array['operator'],'{}','revoked');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000005',true);
select pg_temp.assert_true(public.active_organization_id() is null,'revocation clears active organization');
select pg_temp.assert_true((select count(*)=0 from public.assets where id::text like 'b0180000-%'),'revocation immediately denies direct asset reads');
select pg_temp.expect_error($q$select public.set_active_organization((select value::uuid from fixture where key='org_a'))$q$,'access denied');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000004',true);
select public.create_asset_inspection('b0180000-0000-4000-8000-000000000021','b0180000-0000-4000-8000-000000000040','{"title":"Delegated inspection"}');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000001',true);
select public.set_organization_relationship((select value::uuid from fixture where key='org_a'),(select value::uuid from fixture where key='org_b'),'propose');
select pg_temp.expect_error($q$select public.set_organization_relationship((select value::uuid from fixture where key='org_a'),(select value::uuid from fixture where key='org_b'),'accept')$q$,'Client team administration');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000002',true);
select public.set_organization_relationship((select value::uuid from fixture where key='org_a'),(select value::uuid from fixture where key='org_b'),'accept');
select pg_temp.assert_true(not public.maintenance_can_view_asset('b0180000-0000-4000-8000-000000000021'),'relationship alone never exposes partner private fleet');
insert into fixture values('second_company',public.create_membership_invite(public.active_organization_id(),array['mechanic'])->>'code');
select set_config('request.jwt.claim.sub','b0180000-0000-4000-8000-000000000006',true);
select public.redeem_membership_invite((select value from fixture where key='second_company'),'Mechanic Operator A');
select pg_temp.assert_true(public.active_organization_id()=(select value::uuid from fixture where key='org_b'),'invite selects new company');
select pg_temp.assert_true(not public.maintenance_can_read_job('b0180000-0000-4000-8000-000000000030'),'switching organization blocks previous company job');
select public.set_active_organization((select value::uuid from fixture where key='org_a'));
select pg_temp.assert_true(public.maintenance_can_read_job('b0180000-0000-4000-8000-000000000030'),'switching back restores only retained active membership');
select pg_temp.assert_true(jsonb_array_length(public.organization_context()->'memberships')=2,'one identity keeps two memberships');
reset role;
select pg_temp.assert_true((select count(*)>=10 from public.organization_membership_events),'membership mutation audit retained');
rollback;
