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
-- Distinct stocks for the customer, legacy global provider, and modern provider.
select public.parts_change(null,'b0148000-0000-4000-8000-000000000081','stock_create','{"description":"Customer filter","location":"Customer store","unit_cost":1}');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000007',true);
select public.parts_change(null,'b0148000-0000-4000-8000-000000000082','stock_create','{"description":"Global filter","location":"Legacy store","unit_cost":2}');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000001',true);
select public.parts_change(null,'b0148000-0000-4000-8000-000000000080','stock_create','{"description":"Provider filter","location":"Provider store","unit_cost":10,"cost_currency":"CAD"}');
select public.parts_change(null,gen_random_uuid(),'stock_count','{"stock_id":"b0148000-0000-4000-8000-000000000080","revision":0,"quantity":1,"note":"Opening count"}');
select pg_temp.assert_true(jsonb_array_length(public.parts_workspace(null)->'stock')=1,'provider sees only its company stock');
select pg_temp.assert_true(public.parts_workspace(null)->'stock'->0->>'client_id'='b0148000-0000-4000-8000-000000000001','provider stock belongs to provider owner identity');
select pg_temp.assert_true(public.parts_workspace('b0148000-0000-4000-8000-000000000030')->'stock'->0->>'id'='b0148000-0000-4000-8000-000000000080','provider job resolves provider company stock');
reset role;
insert into public.checklist_templates(id,name,checklist_type,is_active,client_id) values
 ('b0148000-0000-4000-8000-000000000060','Provider kit','pm',true,'b0148000-0000-4000-8000-000000000001'),
 ('b0148000-0000-4000-8000-000000000062','Other provider kit','pm',true,'b0148000-0000-4000-8000-000000000001');
insert into public.pm_parts_requirements(id,template_id,description,part_number,qty,unit) values
 ('b0148000-0000-4000-8000-000000000061','b0148000-0000-4000-8000-000000000060','Filter','F-1',2,'ea'),
 ('b0148000-0000-4000-8000-000000000063','b0148000-0000-4000-8000-000000000062','Other filter','F-2',9,'ea');
insert into public.organization_memberships(organization_id,profile_id,roles) values
 ((select value::uuid from fixture where key='provider'),'b0148000-0000-4000-8000-000000000006',array['operator']),
 ((select value::uuid from fixture where key='unrelated'),'b0148000-0000-4000-8000-000000000001',array['supervisor']);
set local role authenticated;
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000001',true);
select public.change_organization_work('b0148000-0000-4000-8000-000000000030',0,'b0148000-0000-4000-8000-000000000070','configure','{"checklist_template_id":"b0148000-0000-4000-8000-000000000060","procedure_notes":"Replace filter"}');
select public.change_organization_work('b0148000-0000-4000-8000-000000000030',0,'b0148000-0000-4000-8000-000000000070','configure','{"checklist_template_id":"b0148000-0000-4000-8000-000000000060","procedure_notes":"Replace filter"}');
select pg_temp.assert_true(jsonb_array_length(public.parts_workspace('b0148000-0000-4000-8000-000000000030')->'requirements')=1,'configure captures one kit once');
select pg_temp.expect_error($q$select public.change_organization_work('b0148000-0000-4000-8000-000000000030',1,gen_random_uuid(),'configure','{"checklist_template_id":"b0148000-0000-4000-8000-000000000062"}')$q$,'already captured');
select pg_temp.expect_error($q$select public.change_organization_work('b0148000-0000-4000-8000-000000000030',1,gen_random_uuid(),'configure','{}')$q$,'already captured');
reset role;
update public.pm_parts_requirements set qty=8 where id='b0148000-0000-4000-8000-000000000061';
select pg_temp.assert_true((select required_qty=2 from public.job_part_requirements where work_order_id='b0148000-0000-4000-8000-000000000030'),'later kit edits preserve captured quantity');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true((public.parts_workspace(null)->>'can_manage')::boolean,'supervisor manages company stock');
select public.change_organization_work('b0148000-0000-4000-8000-000000000030',1,gen_random_uuid(),'assign','{"assigned_to":"b0148000-0000-4000-8000-000000000003"}');
create function pg_temp.change(action text,data jsonb,operation uuid default gen_random_uuid()) returns jsonb language sql as $$
 select public.parts_change('b0148000-0000-4000-8000-000000000030',operation,action,data)
$$;
create function pg_temp.req() returns jsonb language sql as $$
 select jsonb_build_object('requirement_id',r->>'id','revision',r->'revision')
 from jsonb_array_elements(public.parts_workspace('b0148000-0000-4000-8000-000000000030')->'requirements')r limit 1
$$;
create function pg_temp.purchase() returns jsonb language sql as $$
 select jsonb_build_object('purchase_id',p->>'id','revision',p->'revision')
 from jsonb_array_elements(public.parts_workspace('b0148000-0000-4000-8000-000000000030')->'purchases')p limit 1
$$;
select pg_temp.expect_error($q$select pg_temp.change('link',pg_temp.req()||'{"stock_id":"b0148000-0000-4000-8000-000000000081"}')$q$,'Stock unavailable');
select pg_temp.expect_error($q$select pg_temp.change('link',pg_temp.req()||'{"stock_id":"b0148000-0000-4000-8000-000000000082"}')$q$,'Stock unavailable');
select pg_temp.change('link',pg_temp.req()||'{"stock_id":"b0148000-0000-4000-8000-000000000080"}');
do $$ declare data jsonb:=pg_temp.req()||'{"quantity":1}'; op uuid:=gen_random_uuid(); begin
 perform pg_temp.change('reserve',data,op); perform pg_temp.change('reserve',data,op);
 perform pg_temp.assert_true((public.parts_workspace('b0148000-0000-4000-8000-000000000030')->'requirements'->0->>'reserved_qty')::numeric=1,'reservation replay does not double reserve');
end $$;
select pg_temp.change('request',pg_temp.req()||'{"quantity":1}');
select pg_temp.change('order',pg_temp.purchase()||'{"supplier":"Parts supplier","reference":"PO-PROVIDER"}');
do $$ declare data jsonb:=pg_temp.purchase()||'{"quantity":1,"unit_cost":12}'; op uuid:=gen_random_uuid(); begin
 perform pg_temp.change('receive',data,op); perform pg_temp.change('receive',data,op);
 perform pg_temp.assert_true((public.parts_workspace('b0148000-0000-4000-8000-000000000030')->'stock'->0->>'qty_on_hand')::numeric=2,'receipt replay adds stock once');
end $$;
select pg_temp.change('reserve',pg_temp.req()||'{"quantity":1}');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(not(public.parts_workspace(null)->>'can_manage')::boolean,'mechanic can read stock without managing it');
select pg_temp.expect_error($q$select public.parts_change(null,gen_random_uuid(),'stock_create','{"description":"No","location":"No"}')$q$,'Manager');
select public.change_organization_work('b0148000-0000-4000-8000-000000000030',2,gen_random_uuid(),'start','{}');
do $$ declare data jsonb:=pg_temp.req()||'{"quantity":2}'; op uuid:=gen_random_uuid(); begin
 perform pg_temp.change('issue',data,op); perform pg_temp.change('issue',data,op);
 perform pg_temp.assert_true((public.parts_workspace('b0148000-0000-4000-8000-000000000030')->'stock'->0->>'qty_on_hand')::numeric=0,'use replay consumes stock once');
 perform pg_temp.assert_true((public.parts_workspace('b0148000-0000-4000-8000-000000000030')->'requirements'->0->>'used_qty')::numeric=2,'use keeps one recorded quantity');
end $$;
do $$ declare data jsonb:=pg_temp.req()||'{"quantity":1}'; op uuid:=gen_random_uuid(); begin
 perform pg_temp.change('return',data,op); perform pg_temp.change('return',data,op);
 perform pg_temp.assert_true((public.parts_workspace('b0148000-0000-4000-8000-000000000030')->'stock'->0->>'qty_on_hand')::numeric=1,'return replay restores stock once');
end $$;
reset role;
select pg_temp.assert_true((select quantity=1 and unit_cost=11 from public.parts where work_order_id='b0148000-0000-4000-8000-000000000030'),'canonical consumed parts use provider weighted cost');
update public.organization_memberships set status='revoked' where profile_id='b0148000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.expect_error($q$select public.parts_workspace('b0148000-0000-4000-8000-000000000030')$q$,'Access denied');
select pg_temp.expect_error($q$select public.parts_workspace(null)$q$,'Access denied');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000006',true);
select pg_temp.expect_error($q$select public.parts_workspace(null)$q$,'Access denied');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error($q$select public.parts_workspace('b0148000-0000-4000-8000-000000000030')$q$,'Access denied');
select pg_temp.assert_true(public.parts_workspace(null)->'stock'->0->>'id'='b0148000-0000-4000-8000-000000000081','customer keeps separate own company stock');
select public.create_maintenance_job('b0148000-0000-4000-8000-000000000040','{"asset_id":"b0148000-0000-4000-8000-000000000021","title":"Internal repair","job_type":"repair"}');
select pg_temp.assert_true(public.parts_workspace('b0148000-0000-4000-8000-000000000040')->'stock'->0->>'id'='b0148000-0000-4000-8000-000000000081','modern internal work keeps customer stock');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000007',true);
select pg_temp.expect_error($q$select public.parts_workspace('b0148000-0000-4000-8000-000000000030')$q$,'Access denied');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.parts_workspace(null)->'stock') s
 where s->>'id'='b0148000-0000-4000-8000-000000000082') and not exists(
 select 1 from jsonb_array_elements(public.parts_workspace(null)->'stock') s
 where s->>'id' in ('b0148000-0000-4000-8000-000000000080','b0148000-0000-4000-8000-000000000081')),
 'legacy owner keeps global stock without company stock');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000001',true);
select public.set_active_organization((select value::uuid from fixture where key='unrelated'));
select pg_temp.assert_true(jsonb_array_length(public.parts_workspace(null)->'stock')=0,'switching active company changes stock scope');
select pg_temp.expect_error($q$select public.parts_change(null,'b0148000-0000-4000-8000-000000000080','stock_create','{"description":"Provider filter","location":"Provider store","unit_cost":10,"cost_currency":"CAD"}')$q$,'different input');
select public.set_active_organization((select value::uuid from fixture where key='provider'));
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000002',true);
select public.set_organization_relationship((select value::uuid from fixture where key='provider'),public.active_organization_id(),'revoke');
select set_config('request.jwt.claim.sub','b0148000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error($q$select public.parts_workspace('b0148000-0000-4000-8000-000000000030')$q$,'Access denied');
reset role;
select pg_temp.assert_true((select qty_on_hand=0 from public.parts_inventory where id='b0148000-0000-4000-8000-000000000081'),'customer stock never consumed');
select pg_temp.assert_true((select qty_on_hand=0 from public.parts_inventory where id='b0148000-0000-4000-8000-000000000082'),'legacy stock never consumed');
rollback;
