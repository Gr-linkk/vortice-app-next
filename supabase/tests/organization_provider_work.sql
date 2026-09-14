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
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'report'='null'::jsonb,'customer never sees provider report draft');
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'parts'='null'::jsonb,'customer never sees provider internal parts costs');
select pg_temp.assert_true((select count(*)=0 from public.parts where work_order_id='b0190000-0000-4000-8000-000000000030'),'customer raw parts access denied');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000003',true);
select public.change_organization_work('b0190000-0000-4000-8000-000000000030',4,gen_random_uuid(),'submit','{"diagnosis":"Worn seal","repair":"Replaced and tested","labour_hours":2}');
select pg_temp.expect_error($q$select public.change_organization_work('b0190000-0000-4000-8000-000000000030',5,gen_random_uuid(),'approve','{}')$q$,'manager must approve');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000004',true);
select public.change_organization_work('b0190000-0000-4000-8000-000000000030',5,gen_random_uuid(),'approve','{}');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'report'->>'repair'='Replaced and tested','approved report shared to customer');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
select public.post_coordination_message('b0190000-0000-4000-8000-000000000050','job','b0190000-0000-4000-8000-000000000030',
 '{"body":"Provider-only cost discussion","visibility":"team"}');
select public.post_coordination_message('b0190000-0000-4000-8000-000000000051','job','b0190000-0000-4000-8000-000000000030',
 '{"body":"Shared completion update","visibility":"shared"}');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(jsonb_array_length(public.coordination_thread('job','b0190000-0000-4000-8000-000000000030')->'posts')=1,'customer sees shared provider reply but not provider private discussion');
select public.post_coordination_message('b0190000-0000-4000-8000-000000000052','job','b0190000-0000-4000-8000-000000000030',
 '{"body":"Customer-only planning discussion","visibility":"team"}');
select pg_temp.assert_true(jsonb_array_length(public.coordination_thread('job','b0190000-0000-4000-8000-000000000030')->'posts')=2,'customer reads own team and shared messages');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(jsonb_array_length(public.coordination_thread('job','b0190000-0000-4000-8000-000000000030')->'posts')=2,'provider cannot read customer private team discussion');
insert into fixture values('invoice',public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','generate','{"billable_rate":100,"parts_total":50,"exchange_rate":17.5,"cad_exchange_rate":1.375,"tax_percent":0}')::text);
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'->>'total_usd'='250.00','existing invoice calculation uses explicit customer charges');
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'->>'total_cad'='343.75','organization invoice includes CAD');
select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','generate','{"cad_exchange_rate":2}');
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'->>'total_cad'='343.75','organization retry preserves CAD');
select pg_temp.expect_error($q$select public.generate_provider_invoice('b0190000-0000-4000-8000-000000000030',17.5,1.375)$q$,'Use organization billing');
select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','sent');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'->>'status'='sent','customer Billing permission sees issued invoice');
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'->'export_snapshot'->'parts'='[]'::jsonb,'invoice snapshot never leaks internal unit costs');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000005',true);
select pg_temp.expect_error($q$select public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')$q$,'access denied');
select pg_temp.assert_true((select count(*)=0 from public.organization_work_orders()),'unrelated company sees no provider orders');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000007',true);
select pg_temp.assert_true((select count(*)=0 from public.work_orders where id='b0190000-0000-4000-8000-000000000030'),'legacy global owner cannot read new organization work');
select pg_temp.assert_true((select count(*)=0 from public.assets where id='b0190000-0000-4000-8000-000000000021'),'legacy provider is not silently enrolled in new company fleet');
select pg_temp.assert_true((select count(*)=0 from public.provider_service_reports(null,'b0190000-0000-4000-8000-000000000030',null)),'legacy report definer cannot cross organization boundary');
select pg_temp.expect_error($q$select public.coordination_thread('job','b0190000-0000-4000-8000-000000000030')$q$,'Access denied');
select pg_temp.expect_error($q$select public.generate_provider_invoice('b0190000-0000-4000-8000-000000000030',1)$q$,'Use organization billing');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
select public.set_organization_relationship((select value::uuid from fixture where key='provider'),public.active_organization_id(),'revoke');
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'report'->>'repair'='Replaced and tested','customer keeps approved service history after relationship ends');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error($q$select public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')$q$,'access denied');
reset role;
select pg_temp.assert_true((select count(*)=1 from public.work_orders where id='b0190000-0000-4000-8000-000000000030'),'single canonical work order retained');
select pg_temp.assert_true((select count(*)=1 from public.service_reports where work_order_id='b0190000-0000-4000-8000-000000000030'),'single canonical service report retained');
select pg_temp.assert_true((select count(*)=1 from public.invoices where work_order_id='b0190000-0000-4000-8000-000000000030'),'single canonical invoice retained');
rollback;
