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
select ('a2040000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'next204-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NOW013 '||right(id::text,1) where id::text like 'a2040000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a2040000-0000-4000-8000-000000000010','Company A','a2040000-0000-4000-8000-000000000001');
update public.profiles set org_id='a2040000-0000-4000-8000-000000000010'
 where id in ('a2040000-0000-4000-8000-000000000001','a2040000-0000-4000-8000-000000000002','a2040000-0000-4000-8000-000000000004','a2040000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a2040000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a2040000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a2040000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a2040000-0000-4000-8000-000000000021','a2040000-0000-4000-8000-000000000001','a2040000-0000-4000-8000-000000000020','A vessel'),
 ('a2040000-0000-4000-8000-000000000022','a2040000-0000-4000-8000-000000000003','a2040000-0000-4000-8000-000000000020','B vessel');
insert into public.checklist_templates(id,name,checklist_type,is_active,created_by) values('a2040000-0000-4000-8000-000000000040','Truck PM','pm',true,'a2040000-0000-4000-8000-000000000005');
insert into public.checklist_items(id,template_id,sort_order,description_en,requires_photo,definition) values('a2040000-0000-4000-8000-000000000042','a2040000-0000-4000-8000-000000000040',1,'Check hydraulic seal',false,'{"input_type":"check"}');
create function pg_temp.cycle_job(kind text,source uuid) returns uuid language sql as $$ select work_order_id from public.recurring_work_cycles where source_kind=kind and source_id=source order by created_at desc,id desc limit 1 $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a2040000-0000-4000-8000-000000000001',true);
select public.configure_asset_meter('a2040000-0000-4000-8000-000000000021',gen_random_uuid(),'km',62000);
select public.save_maintenance_setup(gen_random_uuid(),'plan','a2040000-0000-4000-8000-000000000041',0,
 jsonb_build_object('asset_id','a2040000-0000-4000-8000-000000000021','engine_id',(select primary_meter_engine_id from public.assets where id='a2040000-0000-4000-8000-000000000021'),
 'interval_label','Truck PM','interval_hours',10000,'last_service_hours',52000,'interval_months',12,'last_service_date',(current_date-interval '12 months')::date,'checklist_template_id','a2040000-0000-4000-8000-000000000040'));
select pg_temp.assert_true(public.generate_recurring_work('a2040000-0000-4000-8000-000000000021')=1,'due truck generates one work order');
select pg_temp.assert_true(public.generate_recurring_work('a2040000-0000-4000-8000-000000000021')=0,'repeat foreground generation creates no duplicates');
select pg_temp.assert_true((select j->>'status'='draft' and j->>'assigned_to' is null and j->>'planned_start' is null and j->>'meter_unit'='km' and jsonb_array_length(j->'checklist_snapshot')=1 and j->>'generation_kind'='recurring' from public.maintenance_jobs(pg_temp.cycle_job('plan','a2040000-0000-4000-8000-000000000041')) j),'generated work freezes tasks with due context but no appointment or worker');
select public.change_maintenance_job(pg_temp.cycle_job('plan','a2040000-0000-4000-8000-000000000041'),0,gen_random_uuid(),'start','{"meter_unit":"km","start_meter":62000}');
select public.change_maintenance_job(pg_temp.cycle_job('plan','a2040000-0000-4000-8000-000000000041'),1,gen_random_uuid(),'pause','{}');
select public.change_maintenance_job(pg_temp.cycle_job('plan','a2040000-0000-4000-8000-000000000041'),2,gen_random_uuid(),'submit','{"meter_unit":"km","completion_hours":62000,"diagnosis":"Scheduled inspection","repair":"Serviced and tested","answers":{"a2040000-0000-4000-8000-000000000042":{"result":"pass"}}}');
select public.change_maintenance_job(pg_temp.cycle_job('plan','a2040000-0000-4000-8000-000000000041'),3,'a2040000-0000-4000-8000-000000000060','approve','{}');
select public.change_maintenance_job(pg_temp.cycle_job('plan','a2040000-0000-4000-8000-000000000041'),3,'a2040000-0000-4000-8000-000000000060','approve','{}');
select pg_temp.assert_true((select (p->>'next_due_hours')::numeric=72000 from jsonb_array_elements(public.maintenance_planning()->'plans') p where p->>'id'='a2040000-0000-4000-8000-000000000041'),'approved generated truck service advances correct km target');
select pg_temp.assert_true(public.generate_recurring_work('a2040000-0000-4000-8000-000000000021')=0,'next cycle is not generated early from old due meter');
select public.change_maintenance_job(pg_temp.cycle_job('plan','a2040000-0000-4000-8000-000000000041'),4,gen_random_uuid(),'reopen','{"note":"Add completion details"}');
select public.change_maintenance_job(pg_temp.cycle_job('plan','a2040000-0000-4000-8000-000000000041'),5,gen_random_uuid(),'submit','{"meter_unit":"km","completion_hours":62000,"diagnosis":"Scheduled inspection","repair":"Serviced and tested for thirty minutes","answers":{"a2040000-0000-4000-8000-000000000042":{"result":"pass"}}}');
select public.change_maintenance_job(pg_temp.cycle_job('plan','a2040000-0000-4000-8000-000000000041'),6,gen_random_uuid(),'approve','{}');
select pg_temp.assert_true((select (p->>'next_due_hours')::numeric=72000 from jsonb_array_elements(public.maintenance_planning()->'plans') p where p->>'id'='a2040000-0000-4000-8000-000000000041'),'reopened approval cannot advance target twice');
reset role;
select pg_temp.assert_true((select created_by is null and generation_kind='recurring' from public.work_orders where id=pg_temp.cycle_job('plan','a2040000-0000-4000-8000-000000000041')),'system authorship does not impersonate manager');
select pg_temp.expect_error($q$insert into public.work_orders(id,asset_id,client_id,title,job_type,created_by,managed_maintenance,generation_kind) values(gen_random_uuid(),'a2040000-0000-4000-8000-000000000021','a2040000-0000-4000-8000-000000000001','Spoofed recurring work','inspection',null,true,'recurring')$q$,'server-created cycle');
insert into public.asset_inspections(id,asset_id,title,first_due_date,procedure_notes) values('a2040000-0000-4000-8000-000000000050','a2040000-0000-4000-8000-000000000021','Annual safety inspection',current_date,'Inspect and certify');
insert into public.inspection_submissions(id,inspection_id,inspected_on,expires_on,procedure_notes,result_notes,evidence_path,submitted_by,submitted_name,status,reviewed_at)
 values('a2040000-0000-4000-8000-000000000051','a2040000-0000-4000-8000-000000000050',current_date-365,current_date+10,'Prior approved procedure','Prior approved result','historical-certificate.jpg','a2040000-0000-4000-8000-000000000001','Manager','approved',now()-interval '365 days');
set local role authenticated;
select set_config('request.jwt.claim.sub','a2040000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.generate_recurring_work('a2040000-0000-4000-8000-000000000021')=1,'inspection generates before expiry');
select pg_temp.assert_true(public.inspection_register()->0->>'open_work_order_id'=pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050')::text,'inspection links directly to generated work');
select public.change_maintenance_job(pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050'),0,gen_random_uuid(),'start','{"meter_unit":"km","start_meter":62000}');
select public.change_maintenance_job(pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050'),1,gen_random_uuid(),'pause','{}');
insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'maintenance-evidence',pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050')||'/a2040000-0000-4000-8000-000000000001/a2040000-0000-4000-8000-000000000070.jpg');
create function pg_temp.inspection_result() returns jsonb language sql as $$ select jsonb_build_object('meter_unit','km','diagnosis','Annual inspection due','repair','Inspection performed and certified','completion_hours',62000,
 'evidence_paths',jsonb_build_array(pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050')||'/a2040000-0000-4000-8000-000000000001/a2040000-0000-4000-8000-000000000070.jpg'),
 'inspection',jsonb_build_object('inspected_on',current_date,'expires_on',(current_date+interval '12 months')::date,'procedure_notes','Inspection procedure current revision','result_notes','Passed required inspection tests','evidence_path',pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050')||'/a2040000-0000-4000-8000-000000000001/a2040000-0000-4000-8000-000000000070.jpg')) $$;
select public.change_maintenance_job(pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050'),2,gen_random_uuid(),'submit',pg_temp.inspection_result());
select pg_temp.assert_true(public.inspection_register()->0->'approved'->>'id'='a2040000-0000-4000-8000-000000000051' and public.inspection_register()->0->'pending'->>'work_order_id'=pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050')::text,'old certificate remains current while work awaits review');
select public.change_maintenance_job(pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050'),3,gen_random_uuid(),'return','{"note":"Clarify test procedure"}');
select pg_temp.assert_true(public.inspection_register()->0->'approved'->>'id'='a2040000-0000-4000-8000-000000000051','returned inspection preserves current certificate');
select public.change_maintenance_job(pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050'),4,'a2040000-0000-4000-8000-000000000071','submit',pg_temp.inspection_result());
select public.change_maintenance_job(pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050'),5,'a2040000-0000-4000-8000-000000000072','approve','{"note":"Procedure verified"}');
select public.change_maintenance_job(pg_temp.cycle_job('inspection','a2040000-0000-4000-8000-000000000050'),5,'a2040000-0000-4000-8000-000000000072','approve','{"note":"Procedure verified"}');
select pg_temp.assert_true(public.inspection_register()->0->'approved'->>'id'='a2040000-0000-4000-8000-000000000071' and jsonb_array_length(public.inspection_register()->0->'versions')=3,'work approval promotes one new certificate and retains returned and prior versions');
select pg_temp.assert_true(public.generate_recurring_work('a2040000-0000-4000-8000-000000000021')=0,'inspection approval advances the next certificate cycle');
select set_config('request.jwt.claim.sub','a2040000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.generate_recurring_work('a2040000-0000-4000-8000-000000000021')$q$,'Access denied');
select pg_temp.expect_error($q$select public.run_recurring_generation()$q$,'permission denied');
select pg_temp.assert_true((select count(*)=0 from public.recurring_work_cycles),'another company cannot see recurrence work');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role service_role;
select pg_temp.assert_true(public.run_recurring_generation()=0,'unattended scheduler shares completed cycle deduplication');
reset role;
rollback;
