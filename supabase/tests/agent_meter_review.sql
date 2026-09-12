begin;
create function pg_temp.ok(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.denied(command text) returns void language plpgsql as $$
begin begin execute command; exception when others then return; end;
 raise exception 'Expected denial'; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('a3200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'workflow-'||n||'@example.invalid','{}' from generate_series(1,6) n;
update public.profiles set role=case right(id::text,1) when '1' then 'client' when '2' then 'client'
 when '3' then 'owner' when '4' then 'client_mechanic' when '5' then 'client_admin' else 'operator' end,
 full_name='Workflow '||right(id::text,1) where id::text like 'a3200000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a3200000-0000-4000-8000-000000000010','Document company','a3200000-0000-4000-8000-000000000001');
update public.profiles set org_id='a3200000-0000-4000-8000-000000000010'
 where id::text like 'a3200000-%' and right(id::text,1) in ('1','4','5','6');
insert into public.client_capabilities(client_id,capability_key,enabled)
select 'a3200000-0000-4000-8000-000000000001',k,true from unnest(array['pm_checklists','operational_checklists','maintenance_planning']) k;
insert into public.asset_types(id,category,name) values('a3200000-0000-4000-8000-000000000020','test','Test machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a3200000-0000-4000-8000-000000000021','a3200000-0000-4000-8000-000000000001','a3200000-0000-4000-8000-000000000020','Machine A'),
 ('a3200000-0000-4000-8000-000000000022','a3200000-0000-4000-8000-000000000002','a3200000-0000-4000-8000-000000000020','Machine B');
create temp table results(name text primary key,value jsonb);
grant all on results to authenticated,anon;
create function pg_temp.token(n text) returns text language sql as $$ select value->>'token' from results where name=n $$;
insert into public.maintenance_documents(id,client_id,created_by,title) values('a3200000-0000-4000-8000-000000000040','a3200000-0000-4000-8000-000000000001','a3200000-0000-4000-8000-000000000001','Truck service manual');
insert into public.maintenance_document_pages(document_id,page,object_path) values('a3200000-0000-4000-8000-000000000040',1,'a3200000-0000-4000-8000-000000000040/1.jpg');
set local role authenticated;
select set_config('request.jwt.claim.sub','a3200000-0000-4000-8000-000000000001',true);
select public.configure_asset_meter('a3200000-0000-4000-8000-000000000021',gen_random_uuid(),'km',62000);
insert into results select 'engine',to_jsonb(primary_meter_engine_id) from public.assets where id='a3200000-0000-4000-8000-000000000021';
insert into results values('docs',public.create_agent_workflow_connection('a3200000-0000-4000-8000-000000000001','Truck document agent',false,true,false));
insert into results values('input',jsonb_build_object('asset_id','a3200000-0000-4000-8000-000000000021','document_id','a3200000-0000-4000-8000-000000000040','engine_id',(select value#>>'{}' from results where name='engine'),
 'interval_label','Truck service','interval_hours',10000,'meter_unit','km','source_page',1,'source_quote','Service every 10000 km or twelve months','notes','Also review the twelve-month limit.'));
set local role anon;
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'work_order_context','{"asset_id":"a3200000-0000-4000-8000-000000000021"}')->'data'->'components'->0->>'meter_unit'='km','agent equipment context states km');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'create_plan_draft',(select value-'meter_unit' from results where name='input'),gen_random_uuid())->>'error'='Invalid input','nonhour plan rejects missing unit');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'create_plan_draft',(select value||'{"meter_unit":"mi"}' from results where name='input'),gen_random_uuid())->>'error'='Invalid input','plan rejects mismatched meter unit');
insert into results values('plan',public.agent_execute(pg_temp.token('docs'),'create_plan_draft',(select value from results where name='input'),gen_random_uuid()));
select pg_temp.ok((select value->'data'->'equipment_context'->>'meter_unit'='km' from results where name='plan'),'source plan freezes km metadata');
set local role authenticated;
insert into results values('review',jsonb_build_object('engine_id',(select value#>>'{}' from results where name='engine'),'interval_label','Reviewed truck service','interval_hours','10000','meter_unit','km',
 'last_service_hours','62000','review_current_hours',62000,'source_reviewed',true,'interval_months','12','last_service_date',current_date,'generation_lead_days','20','notes','Manual verified'));
select pg_temp.denied($q$select public.apply_agent_plan_draft((select (value->'data'->>'plan_draft_id')::uuid from results where name='plan'),gen_random_uuid(),(select value||'{"meter_unit":"hours"}' from results where name='review'))$q$);
insert into results select 'applied',to_jsonb(public.apply_agent_plan_draft((select (value->'data'->>'plan_draft_id')::uuid from results where name='plan'),gen_random_uuid(),(select value from results where name='review')));
select pg_temp.ok((select (p->>'next_due_hours')::numeric=72000 and p->>'meter_unit'='km' and p->>'interval_months'='12' from jsonb_array_elements(public.maintenance_planning()->'plans') p where p->>'id'=(select value#>>'{}' from results where name='applied')),'reviewed mixed plan retains 72000km and twelve-month targets');
set local role anon;
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'maintenance_summary')->'data'->'assets'->0->'plans'->0->>'meter_unit'='km','agent summary labels plan target units');
select pg_temp.ok(public.agent_execute(pg_temp.token('docs'),'work_order_context','{"asset_id":"a3200000-0000-4000-8000-000000000021"}')->'data'->'service_plans'->0->>'next_due_date' is not null,'agent sees calendar target as well as meter target');
rollback;
