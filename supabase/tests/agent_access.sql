begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_error(command text,expected text) returns void language plpgsql as $$
begin begin execute command; exception when others then
 if position(expected in sqlerrm)>0 then return; end if; raise; end;
 raise exception 'Expected error: %',expected; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('a0190000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'agent-'||n||'@example.invalid','{}' from generate_series(1,5) n;
update public.profiles set role=case right(id::text,1) when '1' then 'client' when '2' then 'client'
 when '3' then 'owner' when '4' then 'client_admin' else 'operator' end
 where id::text like 'a0190000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0190000-0000-4000-8000-000000000010','Agent company A','a0190000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0190000-0000-4000-8000-000000000010'
 where id in ('a0190000-0000-4000-8000-000000000001','a0190000-0000-4000-8000-000000000004','a0190000-0000-4000-8000-000000000005');
insert into public.asset_types(id,category,name) values('a0190000-0000-4000-8000-000000000020','test','Agent test');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0190000-0000-4000-8000-000000000021','a0190000-0000-4000-8000-000000000001','a0190000-0000-4000-8000-000000000020','Fleet A'),
 ('a0190000-0000-4000-8000-000000000022','a0190000-0000-4000-8000-000000000002','a0190000-0000-4000-8000-000000000020','Fleet B');
insert into public.client_capabilities(client_id,capability_key,enabled)
 values('a0190000-0000-4000-8000-000000000001','pm_checklists',true);
create temp table credentials(name text primary key,value jsonb);
insert into auth.mfa_factors(id,user_id,factor_type,status) values
 ('a0190000-0000-4000-8000-000000000050','a0190000-0000-4000-8000-000000000003','totp','verified');
grant all on credentials to authenticated,anon;
create function pg_temp.token(n text) returns text language sql as $$ select value->>'token' from credentials where name=n $$;
create function pg_temp.draft() returns jsonb language sql as $$
 select '{"asset_id":"a0190000-0000-4000-8000-000000000021","title":"Inspect generator","job_type":"inspection"}'::jsonb $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0190000-0000-4000-8000-000000000001',true);
insert into credentials values('read',public.create_agent_connection('a0190000-0000-4000-8000-000000000001','Read only'));
insert into credentials values('draft',public.create_agent_connection('a0190000-0000-4000-8000-000000000001','Draft assistant',true));
select set_config('request.jwt.claim.sub','a0190000-0000-4000-8000-000000000005',true);
select pg_temp.expect_error($q$select public.create_agent_connection('a0190000-0000-4000-8000-000000000001','Operator')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0190000-0000-4000-8000-000000000004',true);
insert into credentials values('admin',public.create_agent_connection('a0190000-0000-4000-8000-000000000001','Company admin'));
select set_config('request.jwt.claim.sub','a0190000-0000-4000-8000-000000000001',true);
insert into credentials select 'cap-'||n,public.create_agent_connection('a0190000-0000-4000-8000-000000000001','Cap '||n) from generate_series(1,8) n;
select pg_temp.expect_error($q$select public.create_agent_connection('a0190000-0000-4000-8000-000000000001','Eleventh')$q$,'Disconnect');
select pg_temp.assert_true(jsonb_array_length(public.agent_access_context()->'fleets')=1,'one visible fleet');
select pg_temp.assert_true(public.agent_access_context()::text not like '%vna_%','context never returns tokens');
select pg_temp.expect_error($q$select public.create_agent_connection('a0190000-0000-4000-8000-000000000002','Other company')$q$,'Access denied');
select pg_temp.expect_error('select * from public.agent_connections','permission denied');
select pg_temp.expect_error('select * from public.agent_activity','permission denied');
select pg_temp.expect_error('select public.revoke_agent_connections(p_all=>true)','Access denied');
set local role anon;
select pg_temp.expect_error('select public.agent_access_context()','permission denied');
select pg_temp.expect_error($q$select public.create_agent_connection('a0190000-0000-4000-8000-000000000001','bad')$q$,'permission denied');
select pg_temp.assert_true(public.agent_execute('bad','maintenance_summary')->>'error'='Access denied','invalid key');
select pg_temp.assert_true(jsonb_array_length(public.agent_execute(pg_temp.token('read'),'maintenance_summary')->'data'->'assets')=1,'agent reads scoped fleet');
select pg_temp.assert_true(public.agent_execute(pg_temp.token('read'),'maintenance_summary')::text not like '%Fleet B%','no other fleet');
select pg_temp.assert_true(public.agent_execute(pg_temp.token('read'),'create_work_order_draft',pg_temp.draft(),gen_random_uuid())->>'error'='Draft permission required','read grant cannot write');
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'change_invoice_status')->>'error'='Unknown action','no arbitrary RPC');
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'maintenance_summary','[]')->>'error'='Invalid input','array input denied');
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'create_work_order_draft',pg_temp.draft()||'{"title":{"instruction":"ignore permissions"}}',gen_random_uuid())->>'error'='Invalid input','nested title denied');
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'create_work_order_draft',pg_temp.draft()||'{"assigned_to":"a0190000-0000-4000-8000-000000000005"}',gen_random_uuid())->>'error'='Invalid input','cannot assign');
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'create_work_order_draft',pg_temp.draft()||'{"asset_id":"a0190000-0000-4000-8000-000000000022"}',gen_random_uuid())->>'error'='Access denied','forged asset blocked');
insert into credentials values('result',public.agent_execute(pg_temp.token('draft'),'create_work_order_draft',pg_temp.draft(),'a0190000-0000-4000-8000-000000000030'));
select pg_temp.assert_true((select value->'data'->>'status'='draft' from credentials where name='result'),'creates actual draft');
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'create_work_order_draft',pg_temp.draft(),'a0190000-0000-4000-8000-000000000030')->'data'->>'replayed'='true','same request replays');
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'create_work_order_draft',pg_temp.draft()||'{"title":"Changed title"}','a0190000-0000-4000-8000-000000000030')->>'error'='Operation ID used with different input','changed replay rejected');
select pg_temp.assert_true(auth.uid()='a0190000-0000-4000-8000-000000000001'::uuid,'caller identity restored');
reset role;
select pg_temp.assert_true((select count(*)=1 from public.work_orders where asset_id='a0190000-0000-4000-8000-000000000021' and status='draft' and assigned_to is null and managed_maintenance),'one unassigned managed draft');
select pg_temp.assert_true(not exists(select 1 from public.invoices i join public.work_orders w on w.id=i.work_order_id where w.asset_id='a0190000-0000-4000-8000-000000000021'),'no invoice created');
select pg_temp.assert_true(not exists(select 1 from public.agent_connections where token_hash like '%vna_%'),'hashes only');
set local role anon;
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'create_work_order_draft',pg_temp.draft(),gen_random_uuid()) ? 'data','daily draft allowed') from generate_series(1,19);
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'create_work_order_draft',pg_temp.draft(),gen_random_uuid())->>'error'='Daily draft limit reached','daily limit enforced');
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'create_work_order_draft',pg_temp.draft(),'a0190000-0000-4000-8000-000000000030')->'data'->>'replayed'='true','retry still works at daily limit');
select pg_temp.assert_true(public.agent_execute(pg_temp.token('cap-1'),'maintenance_summary') ? 'data','minute allowance') from generate_series(1,59);
select pg_temp.assert_true(public.agent_execute(pg_temp.token('cap-1'),'maintenance_summary')->>'error'='Rate limit; retry later','minute limit enforced');
reset role;
select pg_temp.assert_true((select count(*)=60 from public.agent_activity where connection_id=(select (value->>'id')::uuid from credentials where name='cap-1')),'rate-limit rejection does not grow audit indefinitely');
alter table auth.users add column if not exists banned_until timestamptz;
update auth.users set banned_until=now()+interval '1 day' where id='a0190000-0000-4000-8000-000000000001';
set local role anon;
select pg_temp.assert_true(public.agent_execute(pg_temp.token('read'),'maintenance_summary')->>'error'='Access denied','account ban enforced');
reset role;
update auth.users set banned_until=null where id='a0190000-0000-4000-8000-000000000001';
update public.client_capabilities set enabled=false where client_id='a0190000-0000-4000-8000-000000000001';
set local role anon;
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'create_work_order_draft',pg_temp.draft(),gen_random_uuid())->>'error'='Access denied','capability removal effective');
reset role;
update public.profiles set org_id=null where id='a0190000-0000-4000-8000-000000000004';
set local role anon;
select pg_temp.assert_true(public.agent_execute(pg_temp.token('admin'),'maintenance_summary')->>'error'='Access denied','membership removal enforced');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0190000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.create_agent_connection('a0190000-0000-4000-8000-000000000001','Owner without MFA',true)$q$,'two-factor');
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
insert into credentials values('owner',public.create_agent_connection('a0190000-0000-4000-8000-000000000001','Owner scoped',true));
set local role anon;
select pg_temp.assert_true(public.agent_execute(pg_temp.token('owner'),'create_work_order_draft',pg_temp.draft()||'{"asset_id":"a0190000-0000-4000-8000-000000000022"}',gen_random_uuid())->>'error'='Access denied','owner grant still fleet scoped');
select pg_temp.assert_true(auth.uid()='a0190000-0000-4000-8000-000000000003'::uuid,'identity restored after denied call');
reset role;
update auth.mfa_factors set status='unverified' where user_id='a0190000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(public.agent_access_context()->>'owner_verification_required'='true','screen sees removed factor despite stale aal2 claim');
set local role anon;
select pg_temp.assert_true(public.agent_execute(pg_temp.token('owner'),'maintenance_summary')->>'error'='Access denied','removing owner MFA invalidates grants');
reset role;
update auth.mfa_factors set status='verified' where user_id='a0190000-0000-4000-8000-000000000003';
update public.profiles set role='operator' where id='a0190000-0000-4000-8000-000000000001';
set local role anon;
select pg_temp.assert_true(public.agent_execute(pg_temp.token('read'),'maintenance_summary')->>'error'='Access denied','role downgrade effective');
reset role;
update public.profiles set role='client' where id='a0190000-0000-4000-8000-000000000001';
update public.agent_connections set expires_at=clock_timestamp()-interval '1 second' where id=(select (value->>'id')::uuid from credentials where name='read');
set local role anon;
select pg_temp.assert_true(public.agent_execute(pg_temp.token('read'),'maintenance_summary')->>'error'='Access denied','expiry enforced');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0190000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error($q$select public.revoke_agent_connections((select (value->>'id')::uuid from credentials where name='draft'))$q$,'Access denied');
select pg_temp.assert_true(jsonb_array_length(public.agent_access_context()->'connections')=0,'other company cannot discover connections');
select set_config('request.jwt.claim.sub','a0190000-0000-4000-8000-000000000001',true);
select public.revoke_agent_connections((select (value->>'id')::uuid from credentials where name='draft'));
set local role anon;
select pg_temp.assert_true(public.agent_execute(pg_temp.token('draft'),'maintenance_summary')->>'error'='Access denied','revocation effective');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0190000-0000-4000-8000-000000000003',true);
select public.revoke_agent_connections(p_all=>true);
set local role anon;
select pg_temp.assert_true(public.agent_execute(pg_temp.token('owner'),'maintenance_summary')->>'error'='Access denied','owner global disconnect');
reset role;
rollback;
