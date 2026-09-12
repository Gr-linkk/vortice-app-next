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
select ('a2050000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'next205-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NOW013 '||right(id::text,1) where id::text like 'a2050000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a2050000-0000-4000-8000-000000000010','Company A','a2050000-0000-4000-8000-000000000001');
update public.profiles set org_id='a2050000-0000-4000-8000-000000000010'
 where id in ('a2050000-0000-4000-8000-000000000001','a2050000-0000-4000-8000-000000000002','a2050000-0000-4000-8000-000000000004','a2050000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a2050000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a2050000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a2050000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a2050000-0000-4000-8000-000000000021','a2050000-0000-4000-8000-000000000001','a2050000-0000-4000-8000-000000000020','A vessel'),
 ('a2050000-0000-4000-8000-000000000022','a2050000-0000-4000-8000-000000000003','a2050000-0000-4000-8000-000000000020','B vessel');
insert into public.checklist_templates(id,name,checklist_type,is_active,created_by) values('a2050000-0000-4000-8000-000000000040','Attached task','pm',true,'a2050000-0000-4000-8000-000000000005');
insert into public.checklist_items(id,template_id,sort_order,description_en,requires_photo,definition) values('a2050000-0000-4000-8000-000000000041','a2050000-0000-4000-8000-000000000040',1,'Check hydraulic seal',false,'{"input_type":"check"}');
set local role authenticated;
select set_config('request.jwt.claim.sub','a2050000-0000-4000-8000-000000000001',true);
select public.create_maintenance_job('a2050000-0000-4000-8000-000000000030','{"asset_id":"a2050000-0000-4000-8000-000000000021","title":"Hydraulic inspection","job_type":"inspection","checklist_template_id":"a2050000-0000-4000-8000-000000000040"}');
select public.change_maintenance_job('a2050000-0000-4000-8000-000000000030',0,gen_random_uuid(),'start','{}');
select public.change_maintenance_job('a2050000-0000-4000-8000-000000000030',1,gen_random_uuid(),'pause','{}');
select public.change_maintenance_job('a2050000-0000-4000-8000-000000000030',2,'a2050000-0000-4000-8000-000000000060','save_report','{"diagnosis":"Small seal leak","repair":"Inspection underway","answers":{"a2050000-0000-4000-8000-000000000041":{"result":"fail","issue_note":"Leak appears when warm","fault_requested":true}}}');
select public.change_maintenance_job('a2050000-0000-4000-8000-000000000030',2,'a2050000-0000-4000-8000-000000000060','save_report','{"diagnosis":"Small seal leak","repair":"Inspection underway","answers":{"a2050000-0000-4000-8000-000000000041":{"result":"fail","issue_note":"Leak appears when warm","fault_requested":true}}}');
select pg_temp.assert_true((select jsonb_array_length(j->'checklist_faults')=1 and (j->'checklist_faults'->0->'answer_snapshot'->>'issue_note')='Leak appears when warm' from public.maintenance_jobs('a2050000-0000-4000-8000-000000000030') j),'one fault retains exact failed task and narrative');
select pg_temp.expect_error($q$select public.change_maintenance_job('a2050000-0000-4000-8000-000000000030',3,gen_random_uuid(),'submit','{"diagnosis":"Small seal leak","repair":"Inspection underway","answers":{"a2050000-0000-4000-8000-000000000041":{"result":"fail"}}}')$q$,'resolve failed');
select public.change_maintenance_job('a2050000-0000-4000-8000-000000000030',3,gen_random_uuid(),'submit','{"diagnosis":"Small seal leak","repair":"Seal replaced and tested","answers":{"a2050000-0000-4000-8000-000000000041":{"result":"pass","note":"Verified warm operation"}}}');
select public.change_maintenance_job('a2050000-0000-4000-8000-000000000030',4,gen_random_uuid(),'return','{"note":"Describe the operating test duration"}');
select pg_temp.assert_true((select j->>'returned_at' is not null and j->>'review_note'='Describe the operating test duration' and j->'report'->>'repair'='Seal replaced and tested' and j->'checklist_answers'->'a2050000-0000-4000-8000-000000000041'->>'note'='Verified warm operation' from public.maintenance_jobs('a2050000-0000-4000-8000-000000000030') j),'returned work preserves input with the reviewer comment');
select public.change_maintenance_job('a2050000-0000-4000-8000-000000000030',5,gen_random_uuid(),'submit','{"diagnosis":"Small seal leak","repair":"Seal replaced and tested for thirty minutes","answers":{"a2050000-0000-4000-8000-000000000041":{"result":"pass","note":"Verified warm operation"}}}');
select pg_temp.assert_true((select j->>'returned_at' is null from public.maintenance_jobs('a2050000-0000-4000-8000-000000000030') j),'resubmission returns to review state');
select set_config('request.jwt.claim.sub','a2050000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.work_checklist_faults where work_order_id='a2050000-0000-4000-8000-000000000030'),'another company cannot read attached fault detail');
reset role;
select pg_temp.assert_true((select count(*)=1 from public.work_checklist_faults where work_order_id='a2050000-0000-4000-8000-000000000030'),'fault save retry produces one source record');
rollback;
