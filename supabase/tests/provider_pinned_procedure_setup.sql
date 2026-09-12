begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_error(command text,expected text) returns void language plpgsql as $$
begin begin execute command; exception when others then if position(expected in sqlerrm)>0 then return; end if; raise; end;
raise exception 'Expected error: %',expected; end $$;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select ('b0230000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'org-work-'||n||'@example.invalid',now(),'{"onboarding_v2":true}'
from generate_series(1,6) n;
insert into auth.users(id,email) values('b0230000-0000-4000-8000-000000000007','legacy-provider@example.invalid');
update public.profiles set role='owner' where id='b0230000-0000-4000-8000-000000000007';
create temp table fixture(key text primary key,value text);grant all on fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000001',true);
insert into fixture values('provider',public.create_company_workspace('Provider company','Provider owner')::text);
select public.configure_organization_services(true,true);
insert into fixture values('mechanic_invite',public.create_membership_invite(public.active_organization_id(),array['mechanic'])->>'code');
insert into fixture values('supervisor_invite',public.create_membership_invite(public.active_organization_id(),array['supervisor'])->>'code');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000002',true);
insert into fixture values('customer',public.create_company_workspace('Customer company','Customer owner')::text);
insert into fixture values('company_code',public.organization_service_configuration()->'settings'->>'connection_code');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000001',true);
insert into fixture values('relationship',public.propose_organization_customer((select value from fixture where key='company_code'))::text);
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000002',true);
select public.set_organization_relationship((select value::uuid from fixture where key='provider'),public.active_organization_id(),'accept');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000003',true);
select public.redeem_membership_invite((select value from fixture where key='mechanic_invite'),'Assigned mechanic');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000004',true);
select public.redeem_membership_invite((select value from fixture where key='supervisor_invite'),'Provider supervisor');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000005',true);
insert into fixture values('unrelated',public.create_company_workspace('Other company','Other owner')::text);
reset role;
insert into public.asset_types(id,category,name) values('b0230000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('b0230000-0000-4000-8000-000000000021','b0230000-0000-4000-8000-000000000002','b0230000-0000-4000-8000-000000000020','Customer machine'),
 ('b0230000-0000-4000-8000-000000000022','b0230000-0000-4000-8000-000000000005','b0230000-0000-4000-8000-000000000020','Unrelated machine');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000002',true);
select public.configure_asset_meter('b0230000-0000-4000-8000-000000000021','b0230000-0000-4000-8000-000000000060','km',62000);
reset role;
insert into public.client_capabilities(client_id,capability_key,enabled) values('b0230000-0000-4000-8000-000000000001','pm_checklists',true)
 on conflict(client_id,capability_key) do update set enabled=true;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000001',true);
select public.save_checklist_procedure(gen_random_uuid(),'b0230000-0000-4000-8000-000000000040',0,'draft',
 '{"name":"Provider inspection","checklist_type":"pm","items":[{"description_en":"Verify repaired pressure","requires_photo":true,"definition":{"input_type":"number","unit":"bar","min":2,"max":4,"equipment_state":"verification"}}]}');
select public.save_checklist_procedure(gen_random_uuid(),'b0230000-0000-4000-8000-000000000040',1,'publish','{}');
insert into fixture select 'template',t.id::text from public.checklist_templates t where t.procedure_id='b0230000-0000-4000-8000-000000000040';
insert into fixture select 'item',i.id::text from public.checklist_items i where i.template_id=(select value::uuid from fixture where key='template');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000002',true);
select public.request_organization_work('b0230000-0000-4000-8000-000000000030',(select value::uuid from fixture where key='relationship'),
 'b0230000-0000-4000-8000-000000000021','Repair the pressure loss','Customer source description');
select pg_temp.assert_true(not(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030') ? 'checklist_snapshot'),'customer has no private execution metadata');
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000004',true);
create function pg_temp.change(action text,data jsonb default '{}',operation uuid default gen_random_uuid()) returns void language plpgsql as $$
begin perform public.change_organization_work('b0230000-0000-4000-8000-000000000030',
 (public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->>'revision')::integer,operation,action,data); end $$;
select pg_temp.change('configure',jsonb_build_object('checklist_template_id',(select value from fixture where key='template'),'procedure_notes','Isolate before repair; verify after restart.','service_date','2026-09-18'));
select set_config('request.jwt.claim.sub','b0230000-0000-4000-8000-000000000001',true);
select public.save_checklist_procedure(gen_random_uuid(),'b0230000-0000-4000-8000-000000000040',2,'archive','{}');
select pg_temp.change('configure',jsonb_build_object('checklist_template_id',(select value from fixture where key='template'),'procedure_notes','Keep the frozen procedure; updated visit instructions.','service_date','2026-09-19'));
select pg_temp.assert_true(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->>'procedure_notes'='Keep the frozen procedure; updated visit instructions.','unchanged retired procedure permits preparation edits');
select pg_temp.assert_true(jsonb_array_length(public.organization_work_order_context('b0230000-0000-4000-8000-000000000030')->'checklist_snapshot')=1,'retired attached instructions remain frozen');
select pg_temp.expect_error($q$select pg_temp.change('configure','{"procedure_notes":"Remove captured kit"}')$q$,'parts kit');
reset role;
rollback;
