begin;
create function pg_temp.ok(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.denied(command text) returns void language plpgsql as $$
begin begin execute command; exception when insufficient_privilege then return; end; raise exception 'Expected access denial'; end $$;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select ('b0290000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'context-member-'||n||'@example.invalid',now(),'{"onboarding_v2":true}' from generate_series(1,4) n;
create temp table context_fixture(key text primary key,value text); grant all on context_fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0290000-0000-4000-8000-000000000001',true);
insert into context_fixture values('org',public.create_company_workspace('Discussion members','Owner')::text);
insert into context_fixture values('mechanic',public.create_membership_invite(public.active_organization_id(),array['mechanic','operator'])->>'code');
insert into context_fixture values('operator',public.create_membership_invite(public.active_organization_id(),array['operator'])->>'code');
select set_config('request.jwt.claim.sub','b0290000-0000-4000-8000-000000000002',true);
select public.redeem_membership_invite((select value from context_fixture where key='mechanic'),'Mechanic Operator');
select set_config('request.jwt.claim.sub','b0290000-0000-4000-8000-000000000003',true);
select public.redeem_membership_invite((select value from context_fixture where key='operator'),'Operator');
select set_config('request.jwt.claim.sub','b0290000-0000-4000-8000-000000000004',true);
select public.create_company_workspace('Other discussion company','Other owner');
reset role;
insert into public.asset_types(id,category,name) values('b0290000-0000-4000-8000-000000000020','test','Context machine');
insert into public.assets(id,client_id,asset_type_id,name) values('b0290000-0000-4000-8000-000000000021','b0290000-0000-4000-8000-000000000001','b0290000-0000-4000-8000-000000000020','Context machine');
insert into public.client_capabilities(client_id,capability_key,enabled)
select 'b0290000-0000-4000-8000-000000000001',k,true from unnest(array['pm_checklists','operational_checklists','maintenance_planning']) k on conflict(client_id,capability_key) do update set enabled=true;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0290000-0000-4000-8000-000000000001',true);
select public.create_maintenance_job('b0290000-0000-4000-8000-000000000030','{"asset_id":"b0290000-0000-4000-8000-000000000021","title":"Inspect drive","assigned_to":"b0290000-0000-4000-8000-000000000002"}');
select public.post_coordination_message('b0290000-0000-4000-8000-000000000031','asset','b0290000-0000-4000-8000-000000000021','{"body":"Check drive before operating","visibility":"shared"}');
select set_config('request.jwt.claim.sub','b0290000-0000-4000-8000-000000000002',true);
select public.post_coordination_message('b0290000-0000-4000-8000-000000000032','job','b0290000-0000-4000-8000-000000000030','{"body":"Assigned mechanic inspection notes","visibility":"team"}');
select pg_temp.ok(jsonb_array_length(public.coordination_thread('job','b0290000-0000-4000-8000-000000000030')->'posts')=1,'modern assigned mechanic can discuss work');
select set_config('request.jwt.claim.sub','b0290000-0000-4000-8000-000000000003',true);
select pg_temp.denied($q$select public.coordination_thread('job','b0290000-0000-4000-8000-000000000030')$q$);
select pg_temp.ok(jsonb_array_length(public.coordination_thread('asset','b0290000-0000-4000-8000-000000000021')->'posts')=1,'asset discussion does not expose private job to operator');
select public.post_coordination_message('b0290000-0000-4000-8000-000000000033','asset','b0290000-0000-4000-8000-000000000021','{"body":"Operator checked drive guards","visibility":"shared"}');
select set_config('request.jwt.claim.sub','b0290000-0000-4000-8000-000000000004',true);
select pg_temp.denied($q$select public.coordination_thread('asset','b0290000-0000-4000-8000-000000000021')$q$);
select set_config('request.jwt.claim.sub','b0290000-0000-4000-8000-000000000001',true);
select public.update_organization_membership(public.active_organization_id(),'b0290000-0000-4000-8000-000000000002',array['mechanic','operator'],'{}','revoked');
select pg_temp.ok(jsonb_array_length(public.coordination_thread('job','b0290000-0000-4000-8000-000000000030')->'posts')=1,'revoked author contribution remains in authorized company history');
select set_config('request.jwt.claim.sub','b0290000-0000-4000-8000-000000000002',true);
select pg_temp.denied($q$select public.coordination_thread('job','b0290000-0000-4000-8000-000000000030')$q$);
select pg_temp.denied($q$select public.post_coordination_message(gen_random_uuid(),'asset','b0290000-0000-4000-8000-000000000021','{"body":"Revoked member cannot post"}')$q$);
rollback;
