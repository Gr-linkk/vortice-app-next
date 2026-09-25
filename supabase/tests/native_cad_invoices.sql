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
-- First invoice starts from approved work, with explicit issuer and reviewed tax.
select pg_temp.expect_error($q$select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','generate_cad','{}')$q$,'company invoice profile');
select public.save_organization_billing_profile(public.active_organization_id(),'{"legal_name":"Test Canadian Workshop Ltd.","address":"123 Demo Road, Vancouver, BC, Canada","contact":"billing@example.invalid","registration_status":"registered","tax_registration":"GST/HST: TEST-ONLY"}');
select pg_temp.expect_error($q$select public.save_organization_billing_profile(gen_random_uuid(),'{}')$q$,'Company changed');
create temp table cad_payload(data jsonb);grant all on cad_payload to authenticated;
insert into cad_payload values('{"customer_name":"Test Canadian Fleet Ltd.","customer_address":"456 Sample Way, Vancouver, BC, Canada","supply_description":"Pressure repair and replacement seal","supply_province":"BC","tax_treatment":"taxable","tax_review_note":"Synthetic test only: GST on full subtotal and separate reviewed parts base.","issue_date":"2026-09-25","due_date":"2026-10-25","payment_terms":"Due in 30 days","labour_rate":100,"parts_total":50.01,"taxes":[{"name":"GST","rate":5,"base":250.01},{"name":"PST","rate":7,"base":50.01}],"total":1}');
select pg_temp.expect_error($q$select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','generate_cad',(select data||'{"labour_rate":"NaN"}' from cad_payload))$q$,'finite nonnegative');
select pg_temp.expect_error($q$select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','generate_cad',(select data||'{"taxes":[{"name":"GST","rate":-5,"base":250}]}' from cad_payload))$q$,'valid rate');
select pg_temp.expect_error($q$select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','generate_cad',(select data||'{"due_date":"2026-01-01"}' from cad_payload))$q$,'Due date');
select pg_temp.expect_error($q$select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','generate_cad',(select data||'{"tax_review_note":""}' from cad_payload))$q$,'tax review');
insert into fixture values('invoice',public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','generate_cad',(select data from cad_payload))::text);
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'->>'total_cad'='266.01','server rounds separate tax lines and ignores submitted total');
select pg_temp.assert_true((select count(*)=1 from public.invoices where id=(select value::uuid from fixture where key='invoice')),'billing provider can open and export own invoice');
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'->>'total_usd' is null,'native CAD never masquerades as USD');
select pg_temp.assert_true(public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','generate_cad','{}')=(select value::uuid from fixture where key='invoice'),'generation retry returns same draft');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'='null'::jsonb,'CAD draft is private');
select pg_temp.assert_true((select count(*)=0 from public.invoices where id=(select value::uuid from fixture where key='invoice')),'customer cannot open private CAD draft');
select pg_temp.assert_true((select count(*)=0 from public.organization_billing_profiles),'customer cannot read provider issuer profile');
select pg_temp.expect_error($q$select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','revise_cad',(select data from cad_payload))$q$,'billing capability and permission');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error('select public.organization_billing_profile()','Billing permission');
select pg_temp.expect_error($q$select public.save_organization_billing_profile(public.active_organization_id(),'{}')$q$,'Company Owner');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','revise_cad',(select data||'{"parts_total":60.01}' from cad_payload));
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'->>'total_cad'='276.01','draft revision recalculates native total');
select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','sent');
select public.save_organization_billing_profile(public.active_organization_id(),'{"legal_name":"Later company name","address":"Later address","contact":"later@example.invalid","registration_status":"registered","tax_registration":"OTHER"}');
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'->'billing_details'->'issuer'->>'legal_name'='Test Canadian Workshop Ltd.','issued issuer remains frozen after profile changes');
select pg_temp.expect_error($q$select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','revise_cad',(select data from cad_payload))$q$,'Only a CAD draft');
reset role;
select pg_temp.expect_error($q$update public.invoices set billing_details=billing_details||'{"parts_total":1}' where id=(select value::uuid from fixture where key='invoice')$q$,'frozen');
select pg_temp.expect_error($q$update public.invoices set billing_currency='USD' where id=(select value::uuid from fixture where key='invoice')$q$,'identity');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'->>'total_cad'='276.01','customer sees the same issued CAD total');
select set_config('request.jwt.claim.sub','b0190000-0000-4000-8000-000000000001',true);
select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','void','{"reason":"Correct reviewed tax treatment"}');
select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','generate_cad',(select data||'{"tax_treatment":"zero_rated","taxes":[]}' from cad_payload));
select pg_temp.assert_true(public.organization_work_order_context('b0190000-0000-4000-8000-000000000030')->'invoice'->>'total_cad'='250.01','void and correction retain explicit reviewed zero tax');
select public.set_company_purpose('fleet');
select pg_temp.expect_error($q$select public.organization_invoice_action('b0190000-0000-4000-8000-000000000030','sent')$q$,'billing capability and permission');
reset role;
select pg_temp.assert_true((select count(*)=2 from public.invoices where work_order_id='b0190000-0000-4000-8000-000000000030'),'correction preserves prior invoice');
rollback;
