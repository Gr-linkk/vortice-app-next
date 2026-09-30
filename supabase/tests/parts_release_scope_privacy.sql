-- ARCH-001 / NOW-022: rollback-only retained ledger privacy regression.
begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_error(command text,expected text) returns void language plpgsql as $$
begin begin execute command; exception when others then if position(expected in sqlerrm)>0 then return; end if; raise; end;
raise exception 'Expected error: %',expected; end $$;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select ('a0520000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'org-work-'||n||'@example.invalid',now(),'{"onboarding_v2":true}'
from generate_series(1,6) n;
insert into auth.users(id,email) values('a0520000-0000-4000-8000-000000000007','legacy-provider@example.invalid'),('a0520000-0000-4000-8000-000000000008','legacy-client@example.invalid');
update public.profiles set role='client' where id='a0520000-0000-4000-8000-000000000008';
update public.profiles set role='owner' where id='a0520000-0000-4000-8000-000000000007';
create temp table fixture(key text primary key,value text);grant all on fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000001',true);
insert into fixture values('provider',public.create_company_workspace('Provider company','Provider owner')::text);
select public.configure_organization_services(true,true);
insert into fixture values('mechanic_invite',public.create_membership_invite(public.active_organization_id(),array['mechanic'])->>'code');
insert into fixture values('supervisor_invite',public.create_membership_invite(public.active_organization_id(),array['supervisor'])->>'code');
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000002',true);
insert into fixture values('customer',public.create_company_workspace('Customer company','Customer owner')::text);
insert into fixture values('company_code',public.organization_service_configuration()->'settings'->>'connection_code');
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000001',true);
insert into fixture values('relationship',public.propose_organization_customer((select value from fixture where key='company_code'))::text);
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000002',true);
select public.set_organization_relationship((select value::uuid from fixture where key='provider'),public.active_organization_id(),'accept');
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000003',true);
select public.redeem_membership_invite((select value from fixture where key='mechanic_invite'),'Assigned mechanic');
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000004',true);
select public.redeem_membership_invite((select value from fixture where key='supervisor_invite'),'Provider supervisor');
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000005',true);
insert into fixture values('unrelated',public.create_company_workspace('Other company','Other owner')::text);
reset role;
insert into public.asset_types(id,category,name) values('a0520000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0520000-0000-4000-8000-000000000021','a0520000-0000-4000-8000-000000000002','a0520000-0000-4000-8000-000000000020','Customer machine'),
 ('a0520000-0000-4000-8000-000000000022','a0520000-0000-4000-8000-000000000005','a0520000-0000-4000-8000-000000000020','Unrelated machine');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000002',true);
select public.request_organization_work('a0520000-0000-4000-8000-000000000030',(select value::uuid from fixture where key='relationship'),
 'a0520000-0000-4000-8000-000000000021','Repair customer machine','Customer request details');
select public.request_organization_work('a0520000-0000-4000-8000-000000000030',(select value::uuid from fixture where key='relationship'),
 'a0520000-0000-4000-8000-000000000021','Repair customer machine','Customer request details');
select pg_temp.assert_true((select count(*)=1 from public.organization_work_orders()),'customer request appears in common Work Orders projection once');
select pg_temp.assert_true((select count(*)=0 from public.work_orders where id='a0520000-0000-4000-8000-000000000030'),'customer cannot read private raw work row');
select pg_temp.assert_true(not(public.organization_work_order_context('a0520000-0000-4000-8000-000000000030')->'work_order' ? 'notes_internal'),'customer work projection excludes internal notes');
select pg_temp.expect_error($q$select public.request_organization_work(gen_random_uuid(),(select value::uuid from fixture where key='relationship'),'a0520000-0000-4000-8000-000000000022','Foreign asset','Not allowed')$q$,'not available');
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true(not public.maintenance_can_view_asset('a0520000-0000-4000-8000-000000000021'),'service order does not open customer private fleet');
select public.change_organization_work('a0520000-0000-4000-8000-000000000030',0,gen_random_uuid(),'assign','{"assigned_to":"a0520000-0000-4000-8000-000000000003"}');
select pg_temp.expect_error($q$select public.organization_invoice_action('a0520000-0000-4000-8000-000000000030','generate','{"billable_rate":100}')$q$,'billing capability and permission');
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000003',true);
select public.change_organization_work('a0520000-0000-4000-8000-000000000030',1,'a0520000-0000-4000-8000-000000000031','start','{}');
select public.change_organization_work('a0520000-0000-4000-8000-000000000030',1,'a0520000-0000-4000-8000-000000000031','start','{}');
reset role;
update public.maintenance_labour_sessions set started_at='2026-09-01T10:00:00Z',stopped_at='2026-09-01T12:00:00Z'
 where work_order_id='a0520000-0000-4000-8000-000000000030';
set local role authenticated;
select public.change_organization_work('a0520000-0000-4000-8000-000000000030',2,gen_random_uuid(),'add_part','{"description":"Private-cost seal","quantity":2,"unit_cost":17}');
select public.change_organization_work('a0520000-0000-4000-8000-000000000030',3,gen_random_uuid(),'save_report','{"diagnosis":"Worn seal","repair":"Replaced and tested","labour_hours":2}');

select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000001',true);
select public.parts_change(null,'a0520000-0000-4000-8000-000000000080','stock_create','{"description":"Synthetic confidential provider stock","location":"Synthetic private provider store","unit_cost":123,"cost_currency":"CAD"}');
select public.parts_change(null,gen_random_uuid(),'stock_count','{"stock_id":"a0520000-0000-4000-8000-000000000080","revision":0,"quantity":2,"note":"Synthetic opening count"}');
select public.parts_change('a0520000-0000-4000-8000-000000000030','a0520000-0000-4000-8000-000000000081','requirement_add','{"description":"Synthetic requirement","quantity":2}');
select public.parts_change('a0520000-0000-4000-8000-000000000030',gen_random_uuid(),'link','{"requirement_id":"a0520000-0000-4000-8000-000000000081","revision":0,"stock_id":"a0520000-0000-4000-8000-000000000080"}');
select public.parts_change('a0520000-0000-4000-8000-000000000030',gen_random_uuid(),'reserve','{"requirement_id":"a0520000-0000-4000-8000-000000000081","revision":1,"quantity":1}');
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000003',true);
select public.change_organization_work('a0520000-0000-4000-8000-000000000030',4,'a0520000-0000-4000-8000-000000000090','submit','{"diagnosis":"Worn seal","repair":"Replaced and tested","labour_hours":2}');
reset role;
select pg_temp.assert_true((select reserved_qty=0 and revision=3 from public.job_part_requirements where id='a0520000-0000-4000-8000-000000000081'),'automatic release clears reservation and advances revision once');
select pg_temp.assert_true((select qty_on_hand=2 and revision=1 from public.parts_inventory where id='a0520000-0000-4000-8000-000000000080'),'automatic release preserves physical stock and inventory revision');
select pg_temp.assert_true((select count(*)=1 and bool_and(client_id='a0520000-0000-4000-8000-000000000001') from public.parts_stock_events where work_order_id='a0520000-0000-4000-8000-000000000030' and action='release'),'modern automatic release records actual provider owner once');
set local role authenticated;
select public.change_organization_work('a0520000-0000-4000-8000-000000000030',4,'a0520000-0000-4000-8000-000000000090','submit','{"diagnosis":"Worn seal","repair":"Replaced and tested","labour_hours":2}');
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true((select count(*)=1 from jsonb_array_elements(public.parts_workspace('a0520000-0000-4000-8000-000000000030')->'events') e where e->>'action'='release' and e->>'description'='Synthetic confidential provider stock' and e->>'location'='Synthetic private provider store' and (e->'payload'->>'quantity')::numeric=1),'owning modern provider reads release once after exact submit replay');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.parts_workspace(null)->'events') e where e->>'action'='requirement_add' and e->>'description' is null),'legitimate stockless requirement event remains visible');
select pg_temp.assert_true(public.parts_workspace(null)->>'cost_currency'='CAD','currency wrapper remains intact');
select pg_temp.expect_error($q$select public.parts_workspace_before_currency(null)$q$,'permission denied');
-- Deliberately historical mis-scoped records: the entire event, including its
-- payload, must be hidden, even when the event's own client_id matches a reader.
reset role;
insert into public.parts_stock_events(id,actor_id,client_id,work_order_id,stock_id,action,payload)
select gen_random_uuid(),'a0520000-0000-4000-8000-000000000001',scope,'a0520000-0000-4000-8000-000000000030',
 'a0520000-0000-4000-8000-000000000080','release','{"quantity":17,"private_marker":"historical-modern-secret"}'
from unnest(array[null::uuid,'a0520000-0000-4000-8000-000000000002'::uuid,'a0520000-0000-4000-8000-000000000005'::uuid]) scope;
set local role authenticated;
do $$
declare reader uuid; events jsonb;
begin
 foreach reader in array array['a0520000-0000-4000-8000-000000000007'::uuid,'a0520000-0000-4000-8000-000000000002'::uuid,'a0520000-0000-4000-8000-000000000005'::uuid] loop
  perform set_config('request.jwt.claim.sub',reader::text,true);
  events:=public.parts_workspace(null)->'events';
  perform pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(events) e where e->>'description'='Synthetic confidential provider stock' or e->>'location'='Synthetic private provider store' or e->'payload'->>'private_marker'='historical-modern-secret' or e->'payload'->>'note'='Unused reservation released at work review or close'),'legacy, customer and unrelated modern readers see no modern stock-backed event');
  perform pg_temp.expect_error($q$select public.parts_workspace('a0520000-0000-4000-8000-000000000030')$q$,'Access denied');
 end loop;
end $$;
reset role;
select pg_temp.assert_true((select count(*)=3 from public.parts_stock_events where payload->>'private_marker'='historical-modern-secret'),'defensive read does not rewrite historical events');
-- Each supported release status executes the same trigger independently. The
-- direct seeds isolate trigger behavior; ordinary RPC submit was proved above.
select set_config('request.jwt.claim.sub','',true);
do $$
declare state text; releases integer;
begin
 foreach state in array array['pending_review','closed','invoiced'] loop
  update public.work_orders set status='in_progress' where id='a0520000-0000-4000-8000-000000000030';
  update public.job_part_requirements set reserved_qty=1 where id='a0520000-0000-4000-8000-000000000081';
  select count(*) into releases from public.parts_stock_events where work_order_id='a0520000-0000-4000-8000-000000000030' and action='release';
  update public.work_orders set status=state where id='a0520000-0000-4000-8000-000000000030';
  update public.work_orders set status=state where id='a0520000-0000-4000-8000-000000000030';
  perform pg_temp.assert_true((select reserved_qty=0 from public.job_part_requirements where id='a0520000-0000-4000-8000-000000000081'),'each finish status releases unused quantity');
  perform pg_temp.assert_true((select count(*)=releases+1 from public.parts_stock_events where work_order_id='a0520000-0000-4000-8000-000000000030' and action='release'),'same-status update creates no duplicate release');
  perform pg_temp.assert_true((select qty_on_hand=2 from public.parts_inventory where id='a0520000-0000-4000-8000-000000000080'),'each finish status conserves physical stock');
  perform pg_temp.assert_true(exists(select 1 from public.parts_stock_events where work_order_id='a0520000-0000-4000-8000-000000000030' and action='release' and client_id='a0520000-0000-4000-8000-000000000001' and actor_id='a0520000-0000-4000-8000-000000000002'),'trigger without auth uses creator but derives scope from stock ownership');
 end loop;
end $$;
-- Cancellation is not an accepted retained work status. Verify that boundary,
-- then exercise the existing dormant branch under a rollback-only constraint.
update public.work_orders set status='in_progress' where id='a0520000-0000-4000-8000-000000000030';
update public.job_part_requirements set reserved_qty=1 where id='a0520000-0000-4000-8000-000000000081';
select pg_temp.expect_error($q$update public.work_orders set status='cancelled' where id='a0520000-0000-4000-8000-000000000030'$q$,'work_orders_status_check');
select pg_temp.assert_true((select reserved_qty=1 from public.job_part_requirements where id='a0520000-0000-4000-8000-000000000081'),'unsupported cancellation leaves reservation intact');
alter table public.work_orders drop constraint work_orders_status_check;
alter table public.work_orders add constraint work_orders_status_check check(status in ('draft','assigned','in_progress','on_hold','pending_review','closed','invoiced','cancelled'));
update public.work_orders set status='cancelled' where id='a0520000-0000-4000-8000-000000000030';
select pg_temp.assert_true((select reserved_qty=0 from public.job_part_requirements where id='a0520000-0000-4000-8000-000000000081'),'dormant cancellation branch releases correctly');
-- Snapshot all release events; neither invalid mutation below may add one.
create temp table releases_before_invalid as select count(*) as count from public.parts_stock_events where action='release';
-- Invalid links must reject atomically without manufacturing a cross-scope
-- event. NULL stock is invalid for positive reserved_qty, not a stockless event.
update public.work_orders set status='in_progress' where id='a0520000-0000-4000-8000-000000000030';
update public.job_part_requirements set stock_id=null,reserved_qty=1 where id='a0520000-0000-4000-8000-000000000081';
select pg_temp.expect_error($q$update public.work_orders set status='closed' where id='a0520000-0000-4000-8000-000000000030'$q$,'Reserved stock does not belong to this work');
select pg_temp.assert_true((select status='in_progress' from public.work_orders where id='a0520000-0000-4000-8000-000000000030'),'invalid stockless reservation rolls back work status');
insert into public.parts_inventory(id,client_id,description,location,qty_on_hand) values
 ('a0520000-0000-4000-8000-000000000100',null,'Legacy stock','Legacy store',2),
 ('a0520000-0000-4000-8000-000000000101','a0520000-0000-4000-8000-000000000008','Client stock','Client store',2);
insert into public.parts_inventory(id,client_id,description,location,qty_on_hand,cost_currency) values('a0520000-0000-4000-8000-000000000107',null,'Foreign CAD legacy stock','Foreign store',2,'CAD');
update public.job_part_requirements set stock_id='a0520000-0000-4000-8000-000000000107' where id='a0520000-0000-4000-8000-000000000081';
select pg_temp.expect_error($q$update public.work_orders set status='closed' where id='a0520000-0000-4000-8000-000000000030'$q$,'Reserved stock does not belong to this work');
select pg_temp.assert_true((select reserved_qty=1 from public.job_part_requirements where id='a0520000-0000-4000-8000-000000000081'),'foreign NULL-scoped stock does not release modern reservation');
insert into public.parts_inventory(id,client_id,description,location,qty_on_hand,cost_currency) values('a0520000-0000-4000-8000-000000000108','a0520000-0000-4000-8000-000000000005','Other modern CAD stock','Other modern store',2,'CAD');
update public.job_part_requirements set stock_id='a0520000-0000-4000-8000-000000000108' where id='a0520000-0000-4000-8000-000000000081';
select pg_temp.expect_error($q$update public.work_orders set status='closed' where id='a0520000-0000-4000-8000-000000000030'$q$,'Reserved stock does not belong to this work');
select pg_temp.assert_true((select reserved_qty=1 and revision=7 from public.job_part_requirements where id='a0520000-0000-4000-8000-000000000081'),'foreign modern stock failure preserves reservation and revision');
select pg_temp.assert_true((select count(*)=(select count from releases_before_invalid) from public.parts_stock_events where action='release'),'malformed reservation failures add no ledger event');
-- Valid row sorts before the malformed row. Its attempted release must also
-- roll back when the later reservation fails ownership validation.
update public.job_part_requirements set stock_id='a0520000-0000-4000-8000-000000000080' where id='a0520000-0000-4000-8000-000000000081';
insert into public.job_part_requirements(id,work_order_id,description,required_qty,stock_id,reserved_qty) values
 ('a0520000-0000-4000-8000-000000000109','a0520000-0000-4000-8000-000000000030','Malformed later reservation',1,'a0520000-0000-4000-8000-000000000108',1);
select pg_temp.expect_error($q$update public.work_orders set status='closed' where id='a0520000-0000-4000-8000-000000000030'$q$,'Reserved stock does not belong to this work');
select pg_temp.assert_true((select bool_and(reserved_qty=1) from public.job_part_requirements where id in ('a0520000-0000-4000-8000-000000000081','a0520000-0000-4000-8000-000000000109')),'later malformed reservation rolls back earlier valid release');
select pg_temp.assert_true((select revision=7 from public.job_part_requirements where id='a0520000-0000-4000-8000-000000000081'),'later failure rolls back earlier valid requirement revision');
select pg_temp.assert_true((select status='in_progress' from public.work_orders where id='a0520000-0000-4000-8000-000000000030'),'later malformed reservation rolls back status');
select pg_temp.assert_true((select count(*)=(select count from releases_before_invalid) from public.parts_stock_events where action='release'),'later malformed reservation rolls back earlier valid ledger insertion');
update public.job_part_requirements set reserved_qty=0 where id='a0520000-0000-4000-8000-000000000109';
-- Inverse historical corruption: own event scope with foreign linked stock.
insert into public.parts_stock_events(id,actor_id,client_id,stock_id,action,payload) values(gen_random_uuid(),'a0520000-0000-4000-8000-000000000001','a0520000-0000-4000-8000-000000000001','a0520000-0000-4000-8000-000000000107','release','{"private_marker":"inverse-history-secret"}');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.parts_workspace(null)->'events') e where e->'payload'->>'private_marker'='inverse-history-secret' or e->>'description'='Foreign CAD legacy stock'),'own event scope cannot expose another inventory scope');
reset role;
select set_config('request.jwt.claim.sub','',true);
update public.job_part_requirements set stock_id='a0520000-0000-4000-8000-000000000080',reserved_qty=0 where id='a0520000-0000-4000-8000-000000000081';
-- Compatibility jobs with correctly owned legacy and managed-client stock.
insert into public.assets(id,client_id,asset_type_id,name) values('a0520000-0000-4000-8000-000000000102','a0520000-0000-4000-8000-000000000008','a0520000-0000-4000-8000-000000000020','Legacy client machine');
insert into public.work_orders(id,asset_id,client_id,created_by,title,job_type,status,managed_maintenance) values
 ('a0520000-0000-4000-8000-000000000103','a0520000-0000-4000-8000-000000000102','a0520000-0000-4000-8000-000000000008','a0520000-0000-4000-8000-000000000007','Legacy provider work','repair','in_progress',false),
 ('a0520000-0000-4000-8000-000000000104','a0520000-0000-4000-8000-000000000102','a0520000-0000-4000-8000-000000000008','a0520000-0000-4000-8000-000000000008','Managed client work','repair','in_progress',true);
insert into public.job_part_requirements(id,work_order_id,description,required_qty,stock_id,reserved_qty) values
 ('a0520000-0000-4000-8000-000000000105','a0520000-0000-4000-8000-000000000103','Legacy requirement',1,'a0520000-0000-4000-8000-000000000100',1),
 ('a0520000-0000-4000-8000-000000000106','a0520000-0000-4000-8000-000000000104','Client requirement',1,'a0520000-0000-4000-8000-000000000101',1);
update public.work_orders set status='closed' where id in ('a0520000-0000-4000-8000-000000000103','a0520000-0000-4000-8000-000000000104');
select pg_temp.assert_true((select bool_and(reserved_qty=0) from public.job_part_requirements where id in ('a0520000-0000-4000-8000-000000000105','a0520000-0000-4000-8000-000000000106')),'legacy and managed-client releases clear reservations');
select pg_temp.assert_true((select bool_and(qty_on_hand=2) from public.parts_inventory where id in ('a0520000-0000-4000-8000-000000000100','a0520000-0000-4000-8000-000000000101')),'legacy and managed releases preserve physical stock');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000007',true);
select pg_temp.assert_true((select count(*)=1 from jsonb_array_elements(public.parts_workspace('a0520000-0000-4000-8000-000000000103')->'events') e where e->>'action'='release' and e->>'description'='Legacy stock'),'legacy NULL-scoped release remains readable');
select set_config('request.jwt.claim.sub','a0520000-0000-4000-8000-000000000008',true);
select pg_temp.assert_true((select count(*)=1 from jsonb_array_elements(public.parts_workspace('a0520000-0000-4000-8000-000000000104')->'events') e where e->>'action'='release' and e->>'description'='Client stock'),'managed-client release remains readable');
select 'PASS retained automatic release privacy, malformed history, status transitions and scope compatibility';
rollback;
