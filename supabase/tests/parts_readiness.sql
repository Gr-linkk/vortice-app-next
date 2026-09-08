begin;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$ begin
  if ok is distinct from true then raise exception 'FAIL: %', label; end if;
end $$;
create function pg_temp.expect_error(command text, expected text) returns void
language plpgsql as $$ begin
  begin execute command;
  exception when others then
    if position(expected in sqlerrm)>0 then return; end if;
    raise;
  end;
  raise exception 'Expected error containing: %',expected;
end $$;

insert into auth.users(id,email,raw_user_meta_data)
select ('a0140000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'now014-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NOW014 '||right(id::text,1) where id::text like 'a0140000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0140000-0000-4000-8000-000000000010','Company A','a0140000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0140000-0000-4000-8000-000000000010'
 where id in ('a0140000-0000-4000-8000-000000000001','a0140000-0000-4000-8000-000000000002','a0140000-0000-4000-8000-000000000004','a0140000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0140000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a0140000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a0140000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0140000-0000-4000-8000-000000000021','a0140000-0000-4000-8000-000000000001','a0140000-0000-4000-8000-000000000020','A vessel'),
 ('a0140000-0000-4000-8000-000000000022','a0140000-0000-4000-8000-000000000003','a0140000-0000-4000-8000-000000000020','B vessel');

set local role authenticated;
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.parts_workspace(null) is not null,'parts workspace available');
reset role;
insert into public.checklist_templates(id,name,checklist_type) values
 ('a0140000-0000-4000-8000-000000000060','Filter service','pm');
insert into public.pm_parts_requirements(id,template_id,description,part_number,qty,unit) values
 ('a0140000-0000-4000-8000-000000000061','a0140000-0000-4000-8000-000000000060','Filter','F-1',2,'ea');
set local role authenticated;
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000030',
 '{"asset_id":"a0140000-0000-4000-8000-000000000021","title":"Friday service","job_type":"preventative",
 "assigned_to":"a0140000-0000-4000-8000-000000000002","checklist_template_id":"a0140000-0000-4000-8000-000000000060"}');
select pg_temp.assert_true(jsonb_array_length(public.parts_workspace('a0140000-0000-4000-8000-000000000030')->'requirements')=1,'kit captured on creation');
reset role;
update public.pm_parts_requirements set qty=9 where id='a0140000-0000-4000-8000-000000000061';
select pg_temp.assert_true((select required_qty=2 from public.job_part_requirements where work_order_id='a0140000-0000-4000-8000-000000000030'),'kit changes leave job snapshot unchanged');
set local role authenticated;
create function pg_temp.change(action text,data jsonb,operation uuid default gen_random_uuid()) returns jsonb language sql as $$
 select public.parts_change('a0140000-0000-4000-8000-000000000030',operation,action,data)
$$;
create function pg_temp.req() returns jsonb language sql as $$
 select jsonb_build_object('requirement_id',r->>'id','revision',r->'revision')
 from jsonb_array_elements(public.parts_workspace('a0140000-0000-4000-8000-000000000030')->'requirements') r
 limit 1
$$;
create function pg_temp.purchase() returns jsonb language sql as $$
 select jsonb_build_object('purchase_id',p->>'id','revision',p->'revision')
 from jsonb_array_elements(public.parts_workspace('a0140000-0000-4000-8000-000000000030')->'purchases') p limit 1
$$;
select pg_temp.change('stock_create','{"description":"Filter","part_number":"F-1","location":"Main store","unit":"ea","unit_cost":10}',
 'a0140000-0000-4000-8000-000000000080');
select pg_temp.change('stock_count','{"stock_id":"a0140000-0000-4000-8000-000000000080","revision":0,"quantity":1,"minimum":2,"note":"Opening count"}');
select pg_temp.change('link',pg_temp.req()||'{"stock_id":"a0140000-0000-4000-8000-000000000080"}');
select pg_temp.change('reserve',pg_temp.req()||'{"quantity":1}');
select pg_temp.expect_error($q$select pg_temp.change('reserve',pg_temp.req()||'{"quantity":1}')$q$,'Not enough');
select pg_temp.expect_error($q$select pg_temp.change('stock_count','{"stock_id":"a0140000-0000-4000-8000-000000000080","revision":1,"quantity":0,"note":"Count"}')$q$,'below reserved');
select pg_temp.change('request',pg_temp.req()||'{"quantity":1}');
select pg_temp.expect_error($q$select pg_temp.change('request',pg_temp.req()||'{"quantity":1}')$q$,'unmet requirement');
select pg_temp.change('order',pg_temp.purchase()||'{"supplier":"Local supplier","reference":"PO-22","expected_date":"2026-09-11"}');
-- Half receipt and exact replay must add only 0.5 on hand.
select pg_temp.change('receive',pg_temp.purchase()||'{"quantity":0.5,"unit_cost":12}',
 'a0140000-0000-4000-8000-000000000081');
select pg_temp.change('receive',pg_temp.purchase()||'{"revision":1,"quantity":0.5,"unit_cost":12}',
 'a0140000-0000-4000-8000-000000000081');
select pg_temp.assert_true((public.parts_workspace('a0140000-0000-4000-8000-000000000030')->'stock'->0->>'qty_on_hand')::numeric=1.5,'receipt replay does not duplicate stock');
select pg_temp.expect_error($q$select pg_temp.change('receive',pg_temp.purchase()||'{"quantity":0.5,"unit_cost":13}','a0140000-0000-4000-8000-000000000081')$q$,'different input');
select pg_temp.change('receive',pg_temp.purchase()||'{"quantity":0.5,"unit_cost":12}');
select pg_temp.change('reserve',pg_temp.req()||'{"quantity":1}');
select pg_temp.expect_error($q$select pg_temp.change('issue',pg_temp.req()||'{"quantity":2}')$q$,'Start work');
select public.change_maintenance_job('a0140000-0000-4000-8000-000000000030',0,gen_random_uuid(),'start','{}');
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error($q$select pg_temp.change('stock_create','{"description":"X","location":"X"}')$q$,'Manager');
select pg_temp.change('issue',pg_temp.req()||'{"quantity":2}');
select pg_temp.assert_true((select (j->'parts'->0->>'quantity')::numeric=2 and (j->'parts'->0->>'unit_cost')::numeric=11 from public.maintenance_jobs('a0140000-0000-4000-8000-000000000030') j),'issue records weighted internal parts cost');
select pg_temp.change('return',pg_temp.req()||'{"quantity":1}');
select pg_temp.assert_true((public.parts_workspace('a0140000-0000-4000-8000-000000000030')->'stock'->0->>'qty_on_hand')::numeric=1,'return restores stock');
select pg_temp.assert_true((select (j->'parts'->0->>'quantity')::numeric=1 from public.maintenance_jobs('a0140000-0000-4000-8000-000000000030') j),'return corrects job cost quantity');
select pg_temp.expect_error($q$select public.change_maintenance_job('a0140000-0000-4000-8000-000000000030',1,gen_random_uuid(),'remove_part',jsonb_build_object('part_id',(select j->'parts'->0->>'id' from public.maintenance_jobs('a0140000-0000-4000-8000-000000000030') j)))$q$,'Parts readiness');
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(jsonb_array_length(public.parts_workspace(null)->'stock')=0,'other company sees no stock');
select pg_temp.expect_error($q$select public.parts_workspace('a0140000-0000-4000-8000-000000000030')$q$,'Access denied');
select pg_temp.expect_error($q$select public.parts_change(null,gen_random_uuid(),'stock_count','{"stock_id":"a0140000-0000-4000-8000-000000000080","revision":4,"quantity":10,"note":"Attack"}')$q$,'Stock unavailable');
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000004',true);
select pg_temp.expect_error($q$select public.parts_workspace(null)$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000001',true);
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000031',
 '{"asset_id":"a0140000-0000-4000-8000-000000000021","title":"Second service","job_type":"preventative","checklist_template_id":"a0140000-0000-4000-8000-000000000060"}');
create function pg_temp.req2() returns jsonb language sql as $$
 select jsonb_build_object('requirement_id',r->>'id','revision',r->'revision') from jsonb_array_elements(public.parts_workspace('a0140000-0000-4000-8000-000000000031')->'requirements') r limit 1
$$;
select public.parts_change('a0140000-0000-4000-8000-000000000031',gen_random_uuid(),'link',pg_temp.req2()||'{"stock_id":"a0140000-0000-4000-8000-000000000080"}');
select public.parts_change('a0140000-0000-4000-8000-000000000031',gen_random_uuid(),'reserve',pg_temp.req2()||'{"quantity":1}');
select pg_temp.expect_error($q$select pg_temp.change('reserve',pg_temp.req()||'{"quantity":1}')$q$,'Not enough');
select pg_temp.assert_true((public.parts_readiness_summary()->'a0140000-0000-4000-8000-000000000030'->>'short')::int=1,'planning exposes shared-stock shortage');
select public.parts_change('a0140000-0000-4000-8000-000000000031',gen_random_uuid(),'release',pg_temp.req2()||'{"quantity":1}');
select pg_temp.change('reserve',pg_temp.req()||'{"quantity":1}');
select pg_temp.expect_error($q$select pg_temp.change('requirement_edit',pg_temp.req()||'{"revision":0,"quantity":5}')$q$,'changed');
reset role;
update public.work_orders set status='pending_review' where id='a0140000-0000-4000-8000-000000000030';
select pg_temp.assert_true((select reserved_qty=0 from public.job_part_requirements where work_order_id='a0140000-0000-4000-8000-000000000030'),'review releases unused reservations');
-- Provider jobs use provider stock, never company stock or internal invoices.
insert into public.work_orders(id,asset_id,client_id,created_by,assigned_to,title,job_type,status) values
 ('a0140000-0000-4000-8000-000000000032','a0140000-0000-4000-8000-000000000021','a0140000-0000-4000-8000-000000000001',
 'a0140000-0000-4000-8000-000000000005','a0140000-0000-4000-8000-000000000006','Provider job','repair','in_progress');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000005',true);
select public.parts_change('a0140000-0000-4000-8000-000000000032','a0140000-0000-4000-8000-000000000083','stock_create','{"description":"Seal","location":"Provider van","unit_cost":25}');
select public.parts_change('a0140000-0000-4000-8000-000000000032',gen_random_uuid(),'stock_count','{"stock_id":"a0140000-0000-4000-8000-000000000083","revision":0,"quantity":1,"note":"Opening count"}');
select public.parts_change('a0140000-0000-4000-8000-000000000032','a0140000-0000-4000-8000-000000000084','requirement_add','{"description":"Seal","quantity":1}');
select pg_temp.expect_error($q$select public.parts_change('a0140000-0000-4000-8000-000000000032',gen_random_uuid(),'link','{"requirement_id":"a0140000-0000-4000-8000-000000000084","revision":0,"stock_id":"a0140000-0000-4000-8000-000000000080"}')$q$,'Stock unavailable');
select public.parts_change('a0140000-0000-4000-8000-000000000032',gen_random_uuid(),'link','{"requirement_id":"a0140000-0000-4000-8000-000000000084","revision":0,"stock_id":"a0140000-0000-4000-8000-000000000083"}');
select public.parts_change('a0140000-0000-4000-8000-000000000032',gen_random_uuid(),'reserve','{"requirement_id":"a0140000-0000-4000-8000-000000000084","revision":1,"quantity":1}');
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000006',true);
select public.parts_change('a0140000-0000-4000-8000-000000000032',gen_random_uuid(),'issue','{"requirement_id":"a0140000-0000-4000-8000-000000000084","revision":2,"quantity":1}');
select pg_temp.assert_true((select quantity=1 and unit_cost=25 and markup_pct=15 from public.parts where stock_requirement_id='a0140000-0000-4000-8000-000000000084'),'provider usage preserves billing markup');
select pg_temp.expect_error($q$delete from public.parts where stock_requirement_id='a0140000-0000-4000-8000-000000000084'$q$,'Parts readiness');
-- Company checklist kits remain editable, private, and survive publication.
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000001',true);
select public.save_checklist_procedure(gen_random_uuid(),'a0140000-0000-4000-8000-000000000090',0,'draft',
 '{"name":"Company filter service","checklist_type":"pm","items":[{"description_en":"Replace filter"}]}');
select public.save_checklist_procedure(gen_random_uuid(),'a0140000-0000-4000-8000-000000000090',1,'publish','{}');
create function pg_temp.kit_template() returns uuid language sql as $$
 select id from public.checklist_templates where procedure_id='a0140000-0000-4000-8000-000000000090' and is_active
$$;
insert into public.pm_parts_requirements(template_id,description,part_number,qty,unit)
 values(pg_temp.kit_template(),'Company filter','CF-1',2,'ea');
select public.create_maintenance_job('a0140000-0000-4000-8000-000000000095',
 jsonb_build_object('asset_id','a0140000-0000-4000-8000-000000000021','title','Pinned kit service',
 'job_type','preventative','checklist_template_id',pg_temp.kit_template()));
select public.save_checklist_procedure(gen_random_uuid(),'a0140000-0000-4000-8000-000000000090',2,'draft',
 '{"name":"Company filter service revised","checklist_type":"pm","items":[{"description_en":"Replace filter and inspect seal"}]}');
select public.save_checklist_procedure(gen_random_uuid(),'a0140000-0000-4000-8000-000000000090',3,'publish','{}');
select pg_temp.assert_true((select qty=2 from public.pm_parts_requirements where template_id=pg_temp.kit_template()),'new publication inherits kit');
update public.pm_parts_requirements set qty=3 where template_id=pg_temp.kit_template();
select pg_temp.assert_true((public.parts_workspace('a0140000-0000-4000-8000-000000000095')->'requirements'->0->>'required_qty')::numeric=2,'kit edit after republish preserves existing job');
select set_config('test.parts_kit',pg_temp.kit_template()::text,true);
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select qty=3 from public.pm_parts_requirements where template_id=current_setting('test.parts_kit')::uuid),'company mechanic can read kit');
update public.pm_parts_requirements set qty=20 where template_id=current_setting('test.parts_kit')::uuid;
select pg_temp.assert_true((select qty=3 from public.pm_parts_requirements where template_id=current_setting('test.parts_kit')::uuid),'mechanic cannot edit standard kit');
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.pm_parts_requirements where template_id=current_setting('test.parts_kit')::uuid),'another company cannot read private kit parts');
reset role;
rollback;
