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
select ('a0060000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'now006-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='NOW006 '||right(id::text,1) where id::text like 'a0060000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0060000-0000-4000-8000-000000000010','Company A','a0060000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0060000-0000-4000-8000-000000000010'
 where id in ('a0060000-0000-4000-8000-000000000001','a0060000-0000-4000-8000-000000000002','a0060000-0000-4000-8000-000000000004','a0060000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0060000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a0060000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a0060000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0060000-0000-4000-8000-000000000021','a0060000-0000-4000-8000-000000000001','a0060000-0000-4000-8000-000000000020','A vessel'),
 ('a0060000-0000-4000-8000-000000000022','a0060000-0000-4000-8000-000000000003','a0060000-0000-4000-8000-000000000020','B vessel');
insert into public.client_capabilities(client_id,capability_key,enabled) values('a0060000-0000-4000-8000-000000000001','operational_checklists',true);
insert into public.checklist_templates(id,name,checklist_type,asset_type_id) values('a0110000-0000-4000-8000-000000000001','NOW011 daily','operator_daily','a0060000-0000-4000-8000-000000000020');
insert into public.checklist_items(id,template_id,description_en,requires_photo) values('a0110000-0000-4000-8000-000000000002','a0110000-0000-4000-8000-000000000001','Check seal',true);
create function pg_temp.operator_payload() returns jsonb language sql as $$select jsonb_build_object(
 'asset_id','a0060000-0000-4000-8000-000000000021','template_id','a0110000-0000-4000-8000-000000000001',
 'template_version',1,'run_type','pre_departure','completed_at',now()-interval '1 hour','current_hours',200,
 'responses',jsonb_build_object('a0110000-0000-4000-8000-000000000002','monitor'),
 'notes',jsonb_build_object('a0110000-0000-4000-8000-000000000002','Small leak'),
 'photos',jsonb_build_object('a0110000-0000-4000-8000-000000000002','a0060000-0000-4000-8000-000000000021/a0060000-0000-4000-8000-000000000004/a0110000-0000-4000-8000-000000000003/a0110000-0000-4000-8000-000000000002.jpg'))$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000004',true);
select pg_temp.expect_error($q$select public.submit_operations_checklist('a0110000-0000-4000-8000-000000000003',pg_temp.operator_payload())$q$,'Photo must upload');
select pg_temp.assert_true((select count(*)=0 from public.operator_checklist_runs where id='a0110000-0000-4000-8000-000000000003'),'failed media leaves no partial run');
insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'operator-evidence','a0060000-0000-4000-8000-000000000021/a0060000-0000-4000-8000-000000000004/a0110000-0000-4000-8000-000000000003/a0110000-0000-4000-8000-000000000002.jpg');
select public.submit_operations_checklist('a0110000-0000-4000-8000-000000000003',pg_temp.operator_payload());
select public.submit_operations_checklist('a0110000-0000-4000-8000-000000000003',pg_temp.operator_payload());
select pg_temp.assert_true((select count(*)=1 from public.operator_checklist_runs where id='a0110000-0000-4000-8000-000000000003'),'exact retry creates one run');
select pg_temp.assert_true((select count(*)=1 from public.operator_checklist_responses where run_id='a0110000-0000-4000-8000-000000000003' and response_status='alert' and photo_url is not null),'exact retry creates one response with private photo');
select pg_temp.assert_true((select count(*)=1 from public.saved_checklists where id='a0110000-0000-4000-8000-000000000003' and snapshot->'items'->0->>'response'='monitor'),'exact retry creates one saved history');
select pg_temp.expect_error($q$select public.submit_operations_checklist('a0110000-0000-4000-8000-000000000003',pg_temp.operator_payload()||'{"current_hours":201}')$q$,'different input');
select pg_temp.expect_error($q$update public.operator_checklist_responses set notes='overwritten' where run_id='a0110000-0000-4000-8000-000000000003'$q$,'permission denied');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.submit_operations_checklist(gen_random_uuid(),pg_temp.operator_payload())$q$,'Access denied');
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='operator-evidence'),'other company cannot read evidence');
reset role;
select pg_temp.assert_true((select not public from storage.buckets where id='operator-evidence'),'operator bucket private');
rollback;