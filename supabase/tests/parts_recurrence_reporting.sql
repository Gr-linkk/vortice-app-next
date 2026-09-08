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
select ('a0250000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'combined025-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='Combined025 '||right(id::text,1) where id::text like 'a0250000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0250000-0000-4000-8000-000000000010','Company A','a0250000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0250000-0000-4000-8000-000000000010'
 where id in ('a0250000-0000-4000-8000-000000000001','a0250000-0000-4000-8000-000000000002','a0250000-0000-4000-8000-000000000004','a0250000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0250000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a0250000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a0250000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0250000-0000-4000-8000-000000000021','a0250000-0000-4000-8000-000000000001','a0250000-0000-4000-8000-000000000020','A vessel'),
 ('a0250000-0000-4000-8000-000000000022','a0250000-0000-4000-8000-000000000003','a0250000-0000-4000-8000-000000000020','B vessel');

-- now() is fixed throughout this rollback transaction. Backdate only the
-- receipt default so the report's exclusive query-time cutoff includes it.
alter table public.saved_checklists alter column submitted_at set default (now()-interval '2 seconds');
insert into public.checklist_templates(id,name,checklist_type) values
 ('a0250000-0000-4000-8000-000000000060','Complete 500 hour kit','pm'),
 ('a0250000-0000-4000-8000-000000000062','Included 250 hour tasks','pm');
insert into public.checklist_items(id,template_id,description_en,requires_photo) values
 ('a0250000-0000-4000-8000-000000000063','a0250000-0000-4000-8000-000000000062','Inspect filter housing',false);
insert into public.pm_parts_requirements(id,template_id,description,part_number,qty,unit) values
 ('a0250000-0000-4000-8000-000000000061','a0250000-0000-4000-8000-000000000060','Filter','F-1',3,'ea'),
 ('a0250000-0000-4000-8000-000000000064','a0250000-0000-4000-8000-000000000062','Smaller kit must not be summed','F-1',2,'ea');
create function pg_temp.plans() returns setof public.asset_service_intervals language sql security definer as $$
 select * from public.asset_service_intervals
$$;
create function pg_temp.job() returns jsonb language sql as $$
 select j from public.maintenance_jobs('a0250000-0000-4000-8000-000000000050') j
$$;
create function pg_temp.change(action text,data jsonb,operation uuid default gen_random_uuid()) returns jsonb language sql as $$
 select public.parts_change('a0250000-0000-4000-8000-000000000050',operation,action,data)
$$;
create function pg_temp.req() returns jsonb language sql as $$
 select jsonb_build_object('requirement_id',r->>'id','revision',r->'revision')
 from jsonb_array_elements(public.parts_workspace('a0250000-0000-4000-8000-000000000050')->'requirements') r limit 1
$$;
create function pg_temp.report_asset() returns jsonb language sql as $$
 select a from jsonb_array_elements(public.equipment_report(now()-interval '1 day',now()+interval '1 day')->'assets') a
 where a->>'id'='a0250000-0000-4000-8000-000000000021'
$$;
create function pg_temp.submit_data() returns jsonb language sql as $$
 select jsonb_build_object('diagnosis','Scheduled service','repair','Replaced filters and inspected housing',
 'completion_hours',7500,'answers',jsonb_build_object('a0250000-0000-4000-8000-000000000063',jsonb_build_object('result','pass')))
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0250000-0000-4000-8000-000000000001',true);
select public.save_maintenance_setup(gen_random_uuid(),'component','a0250000-0000-4000-8000-000000000040',0,
 '{"asset_id":"a0250000-0000-4000-8000-000000000021","label":"Main engine","current_hours":6700}');
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0250000-0000-4000-8000-000000000041',0,
 '{"asset_id":"a0250000-0000-4000-8000-000000000021","engine_id":"a0250000-0000-4000-8000-000000000040","interval_label":"250 hour service","interval_hours":250,"last_service_hours":6700,"recurrence_mode":"fixed","anchor_hours":7000,"checklist_template_id":"a0250000-0000-4000-8000-000000000062"}');
select public.save_maintenance_setup(gen_random_uuid(),'plan','a0250000-0000-4000-8000-000000000044',0,
 '{"asset_id":"a0250000-0000-4000-8000-000000000021","engine_id":"a0250000-0000-4000-8000-000000000040","interval_label":"500 hour service","interval_hours":500,"last_service_hours":6700,"recurrence_mode":"fixed","anchor_hours":7500,"checklist_template_id":"a0250000-0000-4000-8000-000000000060","covers_plan_ids":["a0250000-0000-4000-8000-000000000041"]}');
select public.create_maintenance_job('a0250000-0000-4000-8000-000000000050',
 '{"asset_id":"a0250000-0000-4000-8000-000000000021","service_interval_id":"a0250000-0000-4000-8000-000000000044","job_type":"preventative","title":"Combined 500 hour service","assigned_to":"a0250000-0000-4000-8000-000000000002"}');
select pg_temp.assert_true(jsonb_array_length(pg_temp.job()->'checklist_snapshot')=1,'included service checklist captured');
select pg_temp.assert_true(jsonb_array_length(public.parts_workspace('a0250000-0000-4000-8000-000000000050')->'requirements')=1,'only selected complete kit captured, no smaller-kit duplication');
reset role;
update public.pm_parts_requirements set qty=9 where id='a0250000-0000-4000-8000-000000000061';
set local role authenticated;
select pg_temp.assert_true((public.parts_workspace('a0250000-0000-4000-8000-000000000050')->'requirements'->0->>'required_qty')::numeric=3,'job kit remains frozen after standard-kit edit');
select pg_temp.change('stock_create','{"description":"Filter","part_number":"F-1","location":"Store","unit":"ea","unit_cost":20}','a0250000-0000-4000-8000-000000000080');
select pg_temp.change('stock_count','{"stock_id":"a0250000-0000-4000-8000-000000000080","revision":0,"quantity":3,"note":"Opening count"}');
select pg_temp.change('link',pg_temp.req()||'{"stock_id":"a0250000-0000-4000-8000-000000000080"}');
select pg_temp.change('reserve',pg_temp.req()||'{"quantity":3}');
select set_config('request.jwt.claim.sub','a0250000-0000-4000-8000-000000000002',true);
select public.change_maintenance_job('a0250000-0000-4000-8000-000000000050',0,gen_random_uuid(),'start','{}');
select pg_temp.change('issue',pg_temp.req()||'{"quantity":3}');
select pg_temp.change('return',pg_temp.req()||'{"quantity":1}');
select pg_temp.assert_true((pg_temp.job()->'parts'->0->>'quantity')::numeric=2 and (pg_temp.job()->'parts'->0->>'unit_cost')::numeric=20,'net issue cost recorded by real inventory APIs');
select public.change_maintenance_job('a0250000-0000-4000-8000-000000000050',1,gen_random_uuid(),'pause','{}');
select public.change_maintenance_job('a0250000-0000-4000-8000-000000000050',2,gen_random_uuid(),'submit',pg_temp.submit_data());
select set_config('request.jwt.claim.sub','a0250000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true((pg_temp.report_asset()->>'total')::numeric=0,'submitted but unapproved parts excluded');
select public.change_maintenance_job('a0250000-0000-4000-8000-000000000050',3,'a0250000-0000-4000-8000-000000000090','approve','{}');
select public.change_maintenance_job('a0250000-0000-4000-8000-000000000050',3,'a0250000-0000-4000-8000-000000000090','approve','{}');
select pg_temp.assert_true((select next_due_hours=7750 from pg_temp.plans() where id='a0250000-0000-4000-8000-000000000041'),'included recurrence advances');
select pg_temp.assert_true((select next_due_hours=8000 from pg_temp.plans() where id='a0250000-0000-4000-8000-000000000044'),'primary recurrence advances once despite replay');
select pg_temp.assert_true((pg_temp.report_asset()->>'parts')::numeric=40 and (pg_temp.report_asset()->>'total')::numeric=40,'report reconciles net issued approved cost');
select pg_temp.assert_true((select count(*)=1 from jsonb_array_elements(pg_temp.report_asset()->'records') r where r->>'kind'='internal'),'covered services and approval replay do not duplicate expense');
select public.change_maintenance_job('a0250000-0000-4000-8000-000000000050',4,gen_random_uuid(),'reopen','{"note":"Return an unused filter"}');
select pg_temp.change('return',pg_temp.req()||'{"quantity":1}');
select pg_temp.assert_true((pg_temp.report_asset()->>'parts')::numeric=40,'later stock return cannot rewrite approved receipt');
select public.change_maintenance_job('a0250000-0000-4000-8000-000000000050',5,gen_random_uuid(),'submit',pg_temp.submit_data());
reset role;
alter table public.saved_checklists alter column submitted_at set default (now()-interval '1 second');
set local role authenticated;
select public.change_maintenance_job('a0250000-0000-4000-8000-000000000050',6,'a0250000-0000-4000-8000-000000000091','approve','{}');
select public.change_maintenance_job('a0250000-0000-4000-8000-000000000050',6,'a0250000-0000-4000-8000-000000000091','approve','{}');
select pg_temp.assert_true((pg_temp.report_asset()->>'parts')::numeric=20 and (pg_temp.report_asset()->>'total')::numeric=20,'latest approval replaces earlier expense');
select pg_temp.assert_true((select count(*)=1 from jsonb_array_elements(pg_temp.report_asset()->'records') r where r->>'kind'='internal'),'reapproval remains one report record');
select pg_temp.assert_true((select next_due_hours=7750 from pg_temp.plans() where id='a0250000-0000-4000-8000-000000000041'),'reapproval does not advance included recurrence again');
select pg_temp.assert_true((select next_due_hours=8000 from pg_temp.plans() where id='a0250000-0000-4000-8000-000000000044'),'reapproval does not advance primary recurrence again');
select set_config('request.jwt.claim.sub','a0250000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(pg_temp.report_asset() is null,'other company cannot see report asset or cost');
select pg_temp.expect_error($q$select public.parts_workspace('a0250000-0000-4000-8000-000000000050')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0250000-0000-4000-8000-000000000006',true);
select pg_temp.expect_error($q$select public.equipment_report(now()-interval '1 day',now()+interval '1 day')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0250000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error($q$select public.equipment_report(now()-interval '1 day',now()+interval '1 day')$q$,'Access denied');
rollback;
