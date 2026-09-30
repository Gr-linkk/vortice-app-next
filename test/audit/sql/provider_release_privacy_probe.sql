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
select pg_temp.assert_true((select count(*)=1 from public.organization_work_orders()),'customer request appears in common Work Orders projection once');
select pg_temp.assert_true((select count(*)=0 from public.work_orders where id='b0190000-0000-4000-8000-000000000030'),'customer cannot read private raw work row');
select pg_temp.assert_true(not(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'work_order' ? 'notes_internal'),'customer work projection excludes internal notes');
select pg_temp.expect_error($q$select public.request_organization_work(gen_random_uuid(),(select value::uuid from fixture where key='relationship'),'b0190000-0000-4000-8000-000000000022','Foreign asset','Not allowed')$q$,'not available');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true(not public.maintenance_can_view_asset('b0190000-0000-4000-8000-000000000021'),'service order does not open customer private fleet');
select public.change_organization_work('b0190000-0000-4000-8000-000000000030',0,gen_random_uuid(),'assign','{"assigned_to":"b0190000-0000-4000-8000-000000000003"}');
select pg_temp.expect_error($q$select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','generate','{"billable_rate":100}')$q$,'billing capability and permission');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000003',true);
select public.change_organization_work('b0190000-0000-4000-8000-000000000030',1,'b0190000-0000-4000-8000-000000000031','start','{}');
select public.change_organization_work('b0190000-0000-4000-8000-000000000030',1,'b0190000-0000-4000-8000-000000000031','start','{}');
reset role;
update public.maintenance_labour_sessions set started_at='2026-09-01T10:00:00Z',stopped_at='2026-09-01T12:00:00Z'
 where work_order_id='b0190000-0000-4000-8000-000000000030';
set local role authenticated;
select public.change_organization_work('b0190000-0000-4000-8000-000000000030',2,gen_random_uuid(),'add_part','{"description":"Private-cost seal","quantity":2,"unit_cost":17}');
select public.change_organization_work('b0190000-0000-4000-8000-000000000030',3,gen_random_uuid(),'save_report','{"diagnosis":"Worn seal","repair":"Replaced and tested","labour_hours":2}');

select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
select public.parts_change(null,'b0190000-0000-4000-8000-000000000080','stock_create','{"description":"Synthetic confidential provider stock","location":"Synthetic private provider store","unit_cost":123,"cost_currency":"CAD"}');
select public.parts_change(null,gen_random_uuid(),'stock_count','{"stock_id":"b0190000-0000-4000-8000-000000000080","revision":0,"quantity":2,"note":"Synthetic opening count"}');
select public.parts_change('b0190000-0000-4000-8000-000000000030','b0190000-0000-4000-8000-000000000081','requirement_add','{"description":"Synthetic requirement","quantity":2}');
select public.parts_change('b0190000-0000-4000-8000-000000000030',gen_random_uuid(),'link','{"requirement_id":"b0190000-0000-4000-8000-000000000081","revision":0,"stock_id":"b0190000-0000-4000-8000-000000000080"}');
select public.parts_change('b0190000-0000-4000-8000-000000000030',gen_random_uuid(),'reserve','{"requirement_id":"b0190000-0000-4000-8000-000000000081","revision":1,"quantity":1}');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000003',true);
select public.change_organization_work('b0190000-0000-4000-8000-000000000030',4,gen_random_uuid(),'submit','{"diagnosis":"Worn seal","repair":"Replaced and tested","labour_hours":2}');
reset role;
select pg_temp.assert_true((select reserved_qty=0 from public.job_part_requirements where id='b0190000-0000-4000-8000-000000000081'), 'unused reservation released');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000007',true);
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.parts_workspace(null)->'events') e where e->>'description'='Synthetic confidential provider stock'), 'legacy unrelated provider must not see modern provider auto-release stock history');
select 'PASS modern provider automatic release remains company-private';
rollback;
