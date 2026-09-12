begin;
create function pg_temp.ok(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.denied(command text) returns void language plpgsql as $$
begin begin execute command; exception when others then return; end;
 raise exception 'Expected denial'; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('a2200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'workflow-'||n||'@example.invalid','{}' from generate_series(1,6) n;
update public.profiles set role=case right(id::text,1) when '1' then 'client' when '2' then 'client'
 when '3' then 'owner' when '4' then 'client_mechanic' when '5' then 'client_admin' else 'operator' end,
 full_name='Workflow '||right(id::text,1) where id::text like 'a2200000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a2200000-0000-4000-8000-000000000010','Document company','a2200000-0000-4000-8000-000000000001');
update public.profiles set org_id='a2200000-0000-4000-8000-000000000010'
 where id::text like 'a2200000-%' and right(id::text,1) in ('1','4','5','6');
insert into public.client_capabilities(client_id,capability_key,enabled)
select 'a2200000-0000-4000-8000-000000000001',k,true from unnest(array['pm_checklists','operational_checklists','maintenance_planning']) k;
insert into public.asset_types(id,category,name) values('a2200000-0000-4000-8000-000000000020','test','Test machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a2200000-0000-4000-8000-000000000021','a2200000-0000-4000-8000-000000000001','a2200000-0000-4000-8000-000000000020','Machine A'),
 ('a2200000-0000-4000-8000-000000000022','a2200000-0000-4000-8000-000000000002','a2200000-0000-4000-8000-000000000020','Machine B');
create temp table results(name text primary key,value jsonb);
grant all on results to authenticated,anon;
create function pg_temp.token(n text) returns text language sql as $$ select value->>'token' from results where name=n $$;
create function pg_temp.proposal(n text) returns uuid language sql as $$ select (value->'data'->>'proposal_id')::uuid from results where name=n $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a2200000-0000-4000-8000-000000000001',true);
insert into results values('manage',public.create_agent_workflow_connection('a2200000-0000-4000-8000-000000000001','Verified agent',true,true,true));
insert into results values('read',public.create_agent_connection('a2200000-0000-4000-8000-000000000001','Read only'));
select public.create_maintenance_job('a2200000-0000-4000-8000-000000000030','{"asset_id":"a2200000-0000-4000-8000-000000000021","title":"Cooling service"}');
set local role anon;
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'connection_test')->'data'->>'connected'='true','host check reaches current grant');
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'connection_test')->'data'->>'fleet_id'='a2200000-0000-4000-8000-000000000001','host check reports exact scope');
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'connection_test')::text not like '%vna_%','host check never reflects secret');
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'connection_test','{"client_id":"a2200000-0000-4000-8000-000000000002"}')->>'error'='Invalid input','host check cannot select another scope');
select pg_temp.ok(public.agent_execute(pg_temp.token('read'),'assign_work_order','{}',gen_random_uuid())->>'error'='Management permission required','proposal requires opt-in');
insert into results values('assignment',public.agent_execute(pg_temp.token('manage'),'assign_work_order','{"work_order_id":"a2200000-0000-4000-8000-000000000030","revision":0,"assigned_to":"a2200000-0000-4000-8000-000000000004"}','a2200000-0000-4000-8000-000000000071'));
select pg_temp.ok((select value->'data'->>'review_required'='true' from results where name='assignment'),'agent assignment is a proposal');
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'assign_work_order','{"work_order_id":"a2200000-0000-4000-8000-000000000030","revision":0,"assigned_to":"a2200000-0000-4000-8000-000000000004"}','a2200000-0000-4000-8000-000000000071')->'data'->>'replayed'='true','proposal retries do not duplicate');
select pg_temp.denied('select * from public.agent_work_proposals');
select pg_temp.denied($q$select public.review_agent_work_proposal(pg_temp.proposal('assignment'),gen_random_uuid(),'apply')$q$);
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'review_agent_work_proposal','{}',gen_random_uuid())->>'error'='Unknown action','agent cannot approve its proposal');
reset role;
select pg_temp.ok((select assigned_to is null and status='draft' from public.work_orders where id='a2200000-0000-4000-8000-000000000030'),'proposal leaves work unchanged');
select pg_temp.ok((select count(*)=1 from public.agent_work_proposals),'one replay-safe proposal');
set local role authenticated;
select set_config('request.jwt.claim.sub','a2200000-0000-4000-8000-000000000002',true);
select pg_temp.denied($q$select public.agent_work_review_context(pg_temp.proposal('assignment'))$q$);
select pg_temp.denied($q$select public.review_agent_work_proposal(pg_temp.proposal('assignment'),gen_random_uuid(),'apply')$q$);
select set_config('request.jwt.claim.sub','a2200000-0000-4000-8000-000000000001',true);
select pg_temp.ok((select c->>'last_tested_at' is not null from jsonb_array_elements(public.agent_access_context()->'connections') c where c->>'label'='Verified agent'),'app shows successful host check');
select pg_temp.ok(public.agent_work_review_context(pg_temp.proposal('assignment'))->0->>'proposed_person'='Workflow 4','human preview resolves proposed assignee');
select public.review_agent_work_proposal(pg_temp.proposal('assignment'),'a2200000-0000-4000-8000-000000000081','apply');
select public.review_agent_work_proposal(pg_temp.proposal('assignment'),'a2200000-0000-4000-8000-000000000081','apply');
select pg_temp.ok((select j->>'assigned_to'='a2200000-0000-4000-8000-000000000004' and j->>'revision'='1' from public.maintenance_jobs('a2200000-0000-4000-8000-000000000030') j),'human applies checked assignment once');
set local role anon;
insert into results values('schedule',public.agent_execute(pg_temp.token('manage'),'schedule_work_order','{"work_order_id":"a2200000-0000-4000-8000-000000000030","revision":1,"assigned_to":"a2200000-0000-4000-8000-000000000004","due_date":"","planned_start":"2026-10-10T10:00:00Z","estimated_minutes":60,"priority":"normal","note":"Schedule service"}',gen_random_uuid()));
select pg_temp.ok((select value->'data'->>'review_required'='true' from results where name='schedule'),'schedule waits for human');
set local role authenticated;
select public.review_agent_work_proposal(pg_temp.proposal('schedule'),gen_random_uuid(),'apply');
set local role anon;
insert into results values('stale_edit',public.agent_execute(pg_temp.token('manage'),'edit_work_order','{"work_order_id":"a2200000-0000-4000-8000-000000000030","revision":2,"title":"Inspect cooling system","description":"Follow reviewed checklist","job_type":"inspection","expected_materials":"Coolant","priority":"high","note":"Clarify scope"}',gen_random_uuid()));
set local role authenticated;
select public.schedule_maintenance_job('a2200000-0000-4000-8000-000000000030',2,gen_random_uuid(),'{"assigned_to":"a2200000-0000-4000-8000-000000000004","planned_start":"2026-10-10T12:00:00Z","estimated_minutes":60,"priority":"normal","note":"Human moved booking"}');
select pg_temp.ok(public.agent_work_review_context(pg_temp.proposal('stale_edit'))->0->>'can_apply'='false','review exposes changed work revision');
select pg_temp.denied($q$select public.review_agent_work_proposal(pg_temp.proposal('stale_edit'),gen_random_uuid(),'apply')$q$);
select public.review_agent_work_proposal(pg_temp.proposal('stale_edit'),gen_random_uuid(),'reject');
select pg_temp.ok((select j->>'title'='Cooling service' from public.maintenance_jobs('a2200000-0000-4000-8000-000000000030') j),'stale proposal cannot overwrite human edits');
select public.revoke_agent_connections((select (value->>'id')::uuid from results where name='manage'));
set local role anon;
select pg_temp.ok(public.agent_execute(pg_temp.token('manage'),'connection_test')->>'error'='Access denied','revocation immediately fails host check');
reset role;
update public.profiles set role='member' where id='a2200000-0000-4000-8000-000000000005';
insert into public.organization_memberships(organization_id,profile_id,roles) values('a2200000-0000-4000-8000-000000000010','a2200000-0000-4000-8000-000000000005',array['supervisor']);
set local role authenticated;
select set_config('request.jwt.claim.sub','a2200000-0000-4000-8000-000000000005',true);
select pg_temp.ok(jsonb_array_length(public.agent_access_context()->'fleets')=1,'new organization supervisor can use guided setup');
insert into results values('member',public.create_agent_connection('a2200000-0000-4000-8000-000000000001','Company supervisor'));
select pg_temp.denied($q$select public.create_agent_connection('a2200000-0000-4000-8000-000000000002','Other company')$q$);
set local role anon;
select pg_temp.ok(public.agent_execute(pg_temp.token('member'),'connection_test')->'data'->>'connected'='true','member grant verifies within own company');
reset role;
update public.organization_memberships set status='revoked' where profile_id='a2200000-0000-4000-8000-000000000005';
set local role anon;
select pg_temp.ok(public.agent_execute(pg_temp.token('member'),'connection_test')->>'error'='Access denied','membership revocation invalidates connection');
rollback;
