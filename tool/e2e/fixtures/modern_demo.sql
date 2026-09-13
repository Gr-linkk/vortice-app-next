-- Additive internal-demo fixture, applied explicitly to Next after migrations.
-- No existing identity, organization, asset, password or record is changed.
-- Generated auth rows contain bcrypt hashes only. Plaintext stays local.
begin;
set local statement_timeout='60s';
create temp table demo_identities(id uuid primary key,email text,password_hash text);
insert into demo_identities values
__AUTH_ROWS__;
do $$ begin
 if to_regprocedure('public.organization_service_configuration()') is null then
  raise exception 'Apply organization membership/provider migrations first';
 end if;
 if exists(select 1 from auth.users u join demo_identities d on u.id=d.id or lower(u.email)=d.email)
 or exists(select 1 from public.assets where id='d0210000-0000-4000-8000-000000000010') then
  raise exception 'Demo identity or asset already exists; refusing to overwrite';
 end if;
end $$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change)
select id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',email,password_hash,now(),
 '{"provider":"email","providers":["email"]}'::jsonb,'{"onboarding_v2":true}'::jsonb,now(),now(),'','','',''
from demo_identities;
insert into auth.identities(id,provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
select gen_random_uuid(),id::text,id,jsonb_build_object('sub',id::text,'email',email,'email_verified',true),
 'email',now(),now(),now() from demo_identities;
create temp table demo_context(key text primary key,value text);
grant all on demo_context to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','d0210000-0000-4000-8000-000000000001',true);
insert into demo_context values('fleet',public.create_company_workspace('Next Demo Fleet','Demo Fleet Owner')::text);
insert into demo_context values('supervisor',public.create_membership_invite(public.active_organization_id(),array['supervisor'],'{}','demo_fleet_supervisor@vortice.dev')->>'code');
insert into demo_context values('mechanic',public.create_membership_invite(public.active_organization_id(),array['mechanic'],'{}','demo_fleet_mechanic@vortice.dev')->>'code');
insert into demo_context values('operator',public.create_membership_invite(public.active_organization_id(),array['operator'],'{}','demo_fleet_operator@vortice.dev')->>'code');
select set_config('request.jwt.claim.sub','d0210000-0000-4000-8000-000000000002',true);
select public.redeem_membership_invite((select value from demo_context where key='supervisor'),'Demo Fleet Supervisor');
select set_config('request.jwt.claim.sub','d0210000-0000-4000-8000-000000000003',true);
select public.redeem_membership_invite((select value from demo_context where key='mechanic'),'Demo Fleet Mechanic');
select set_config('request.jwt.claim.sub','d0210000-0000-4000-8000-000000000004',true);
select public.redeem_membership_invite((select value from demo_context where key='operator'),'Demo Fleet Operator');
select set_config('request.jwt.claim.sub','d0210000-0000-4000-8000-000000000005',true);
insert into demo_context values('provider',public.create_company_workspace('Next Demo Service','Demo Service Owner')::text);
select public.configure_organization_services(true,true);
select public.set_organization_relationship((select value::uuid from demo_context where key='provider'),(select value::uuid from demo_context where key='fleet'),'propose');
select set_config('request.jwt.claim.sub','d0210000-0000-4000-8000-000000000001',true);
select public.set_organization_relationship((select value::uuid from demo_context where key='provider'),(select value::uuid from demo_context where key='fleet'),'accept');
reset role;
-- Use the catalog identity so every screen selects the bundled truck drawing.
insert into public.assets(id,client_id,asset_type_id,name,make,model,serial_number,location,notes,meter_unit)
values('d0210000-0000-4000-8000-000000000010','d0210000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000022',
 'Demo Truck 01','Demo','Hwy truck','NEXT-DEMO-TRUCK-01','Demo yard','Synthetic modern membership acceptance asset.','km');
insert into public.client_capabilities(client_id,capability_key,enabled)
select 'd0210000-0000-4000-8000-000000000001'::uuid,key,true
from unnest(array['pm_checklists','maintenance_planning','operational_checklists']) key
on conflict(client_id,capability_key) do nothing;
set local role authenticated;
select set_config('request.jwt.claim.sub','d0210000-0000-4000-8000-000000000001',true);
select public.configure_asset_meter('d0210000-0000-4000-8000-000000000010','d0210000-0000-4000-8000-000000000011','km',62000);
reset role;
do $$ begin
 if (select count(*) from public.profiles where id in(select id from demo_identities) and role='member')<>5
 or (select count(*) from public.organization_memberships where profile_id in(select id from demo_identities) and status='active')<>5
 or not exists(select 1 from public.assets a join public.asset_engines e on e.id=a.primary_meter_engine_id
 where a.id='d0210000-0000-4000-8000-000000000010' and a.meter_unit='km' and e.meter_unit='km' and e.current_hours=62000)
 or exists(select 1 from public.legacy_provider_identities where profile_id in(select id from demo_identities)) then
  raise exception 'Modern demo fixture verification failed';
 end if;
end $$;
commit;
