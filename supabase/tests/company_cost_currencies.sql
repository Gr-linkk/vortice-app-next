begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_error(command text,expected text) returns void language plpgsql as $$
begin begin execute command; exception when others then if position(expected in sqlerrm)>0 then return; end if; raise; end;
raise exception 'Expected error: %',expected; end $$;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select ('b0148000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'org-parts-'||n||'@example.invalid',now(),'{"onboarding_v2":true}'
from generate_series(1,6) n;
insert into auth.users(id,email) values('b0148000-0000-4000-8000-000000000007','legacy-provider@example.invalid');
update public.profiles set role='owner' where id='b0148000-0000-4000-8000-000000000007';
create temp table fixture(key text primary key,value text);grant all on fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000001',true);
insert into fixture values('provider',public.create_company_workspace('Provider company','Provider owner')::text);
select public.configure_organization_services(true,true);
insert into fixture values('mechanic_invite',public.create_membership_invite(public.active_organization_id(),array['mechanic'])->>'code');
insert into fixture values('supervisor_invite',public.create_membership_invite(public.active_organization_id(),array['supervisor'])->>'code');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000002',true);
insert into fixture values('customer',public.create_company_workspace('Customer company','Customer owner')::text);
insert into fixture values('company_code',public.organization_service_configuration()->'settings'->>'connection_code');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000001',true);
insert into fixture values('relationship',public.propose_organization_customer((select value from fixture where key='company_code'))::text);
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000002',true);
select public.set_organization_relationship((select value::uuid from fixture where key='provider'),public.active_organization_id(),'accept');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000003',true);
select public.redeem_membership_invite((select value from fixture where key='mechanic_invite'),'Assigned mechanic');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000004',true);
select public.redeem_membership_invite((select value from fixture where key='supervisor_invite'),'Provider supervisor');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000005',true);
insert into fixture values('unrelated',public.create_company_workspace('Other company','Other owner')::text);
reset role;
insert into public.asset_types(id,category,name) values('b0148000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('b0148000-0000-4000-8000-000000000021','b0148000-0000-4000-8000-000000000002','b0148000-0000-4000-8000-000000000020','Customer machine'),
 ('b0148000-0000-4000-8000-000000000022','b0148000-0000-4000-8000-000000000005','b0148000-0000-4000-8000-000000000020','Unrelated machine');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000002',true);
select public.request_organization_work('b0148000-0000-4000-8000-000000000030',(select value::uuid from fixture where key='relationship'),
 'b0148000-0000-4000-8000-000000000021','Repair customer machine','Customer request details');
select pg_temp.assert_true(public.organization_service_configuration()->'settings'->>'cost_currency'='CAD','new Canadian workspace starts with CAD');
select public.create_maintenance_job('b0148000-0000-4000-8000-000000000090','{"asset_id":"b0148000-0000-4000-8000-000000000021","title":"CAD own equipment work","cost_currency":"CAD","hourly_cost":60}');
select pg_temp.assert_true((select data->>'cost_currency'='CAD' from public.maintenance_jobs('b0148000-0000-4000-8000-000000000090') data),'CAD work keeps denomination beside its cost');
select public.configure_organization_cost_currency('USD');
select pg_temp.assert_true(public.maintenance_asset_context('b0148000-0000-4000-8000-000000000021')->>'cost_currency'='USD','next work context reflects company choice');
select pg_temp.assert_true((select data->>'cost_currency'='CAD' from public.maintenance_jobs('b0148000-0000-4000-8000-000000000090') data),'settings never relabel saved work');
select public.create_maintenance_job('b0148000-0000-4000-8000-000000000091','{"asset_id":"b0148000-0000-4000-8000-000000000021","title":"USD own equipment work","cost_currency":"USD","hourly_cost":100}');
select public.parts_change('b0148000-0000-4000-8000-000000000090','b0148000-0000-4000-8000-000000000080','stock_create','{"description":"CAD stock","location":"Store","unit_cost":10,"cost_currency":"CAD"}');
select public.parts_change('b0148000-0000-4000-8000-000000000090','b0148000-0000-4000-8000-000000000081','stock_create','{"description":"USD stock","location":"Store","unit_cost":10,"cost_currency":"USD"}');
select public.parts_change('b0148000-0000-4000-8000-000000000090','b0148000-0000-4000-8000-000000000082','requirement_add','{"description":"Filter","quantity":1}');
select pg_temp.expect_error($q$select public.parts_change('b0148000-0000-4000-8000-000000000090',gen_random_uuid(),'link','{"requirement_id":"b0148000-0000-4000-8000-000000000082","revision":0,"stock_id":"b0148000-0000-4000-8000-000000000081"}')$q$,'currencies differ');
select public.parts_change('b0148000-0000-4000-8000-000000000090',gen_random_uuid(),'link','{"requirement_id":"b0148000-0000-4000-8000-000000000082","revision":0,"stock_id":"b0148000-0000-4000-8000-000000000080"}');
select pg_temp.assert_true(public.parts_workspace('b0148000-0000-4000-8000-000000000090')->>'cost_currency'='CAD','job stock workspace uses saved currency after company change');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.configure_organization_cost_currency('USD')$q$,'Company Owner');
select pg_temp.expect_error($q$select public.equipment_report('2026-01-01','2026-02-01')$q$,'Access denied');
reset role;
select pg_temp.expect_error($q$update public.work_orders set cost_currency='USD' where id='b0148000-0000-4000-8000-000000000090'$q$,'immutable');
select pg_temp.expect_error($q$update public.parts_inventory set cost_currency='USD' where id='b0148000-0000-4000-8000-000000000080'$q$,'immutable');
-- Synthetic approved receipts exercise mixed-currency report grouping; no real work is changed.
insert into public.saved_checklists(id,work_order_id,asset_id,client_id,submitted_by,template_name,checklist_type,source_type,snapshot,submitted_at)
select gen_random_uuid(),id,asset_id,client_id,client_id,'Synthetic cost receipt','maintenance','work_order',
 jsonb_build_object('managed_maintenance',true,'hourly_cost',case when cost_currency='CAD' then 60 else 100 end,
 'labour','[{"started_at":"2026-01-10T10:00:00Z","stopped_at":"2026-01-10T12:00:00Z"}]'::jsonb,'parts','[]'::jsonb),'2026-01-10'
from public.work_orders where id in ('b0148000-0000-4000-8000-000000000090','b0148000-0000-4000-8000-000000000091');
select pg_temp.assert_true((select snapshot->>'cost_currency'='CAD' from public.saved_checklists where work_order_id='b0148000-0000-4000-8000-000000000090'),'approval receipt pins currency');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((public.equipment_report('2026-01-01','2026-02-01')->'assets'->0->'amounts_by_currency'->'CAD'->>'labour')::numeric=120,'modern company report sums CAD separately');
select pg_temp.assert_true((public.equipment_report('2026-01-01','2026-02-01')->'assets'->0->>'labour')::numeric=200,'legacy report fields contain only USD, not a mixed sum');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000005',true);
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.equipment_report('2026-01-01','2026-02-01')->'assets') a where a->>'id'='b0148000-0000-4000-8000-000000000021'),'money report stays within company');
rollback;
