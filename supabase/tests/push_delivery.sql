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
set local role authenticated;
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000001',true);
select public.create_maintenance_job('a0060000-0000-4000-8000-000000000030',
 '{"asset_id":"a0060000-0000-4000-8000-000000000021","title":"Repair seal","assigned_to":"a0060000-0000-4000-8000-000000000002","priority":"high"}');
select pg_temp.assert_true((select count(*)=1 from public.maintenance_jobs() j
 where j->>'id'='a0060000-0000-4000-8000-000000000030'),'manager creates one internal job');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000002',true);
select public.register_push_device('a0110000-0000-4000-8000-000000000201','synthetic-next-mechanic-token','en');
select pg_temp.assert_true((select count(*)=1 from public.notifications where user_id=auth.uid() and type='maintenance_assignment'),'assignment reaches assigned mechanic once');
select pg_temp.expect_error($q$select public.claim_push_deliveries(1)$q$,'permission denied');
select pg_temp.expect_error($q$insert into public.notifications(user_id,title) values('a0060000-0000-4000-8000-000000000003','Spoofed')$q$,'permission denied');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000001',true);
select public.register_push_device('a0110000-0000-4000-8000-000000000202','synthetic-next-manager-token','es');
select public.report_maintenance_fault('a0110000-0000-4000-8000-000000000203','a0060000-0000-4000-8000-000000000021','NOW011 urgent leak','urgent');
select pg_temp.assert_true((select count(*)=1 from public.notifications where user_id=auth.uid() and type='urgent_fault'),'urgent fault reaches company manager');
reset role;
do $$declare claims jsonb; first_claim jsonb;
begin
 claims:=public.claim_push_deliveries(25);
 perform pg_temp.assert_true(jsonb_array_length(claims)=2,'one delivery per relevant registered device');
 perform pg_temp.assert_true(public.claim_push_deliveries(25)='[]'::jsonb,'concurrent worker cannot claim leased work');
 first_claim:=claims->0;
 perform public.finish_push_delivery((first_claim->>'id')::uuid,gen_random_uuid(),true);
 perform pg_temp.assert_true((select status='pending' from public.push_deliveries where id=(first_claim->>'id')::uuid),'wrong lease cannot acknowledge');
 perform public.finish_push_delivery((first_claim->>'id')::uuid,(first_claim->>'lease')::uuid,false,'temporary');
 perform pg_temp.assert_true((select status='pending' and next_attempt>now() and last_error='temporary' from public.push_deliveries where id=(first_claim->>'id')::uuid),'temporary failure retains retry with backoff');
 first_claim:=claims->1;
 perform public.finish_push_delivery((first_claim->>'id')::uuid,(first_claim->>'lease')::uuid,true);
 perform pg_temp.assert_true((select status='sent' and sent_at is not null from public.push_deliveries where id=(first_claim->>'id')::uuid),'acknowledged delivery records FCM acceptance');
end $$;
insert into public.asset_inspections(id,asset_id,title) values('a0110000-0000-4000-8000-000000000204','a0060000-0000-4000-8000-000000000021','NOW011 deadline');
insert into public.inspection_submissions(id,inspection_id,inspected_on,expires_on,procedure_notes,result_notes,evidence_path,submitted_by,submitted_name,status,reviewed_at)
 values('a0110000-0000-4000-8000-000000000205','a0110000-0000-4000-8000-000000000204',current_date-10,current_date+5,'Checked','Passed','test',
 'a0060000-0000-4000-8000-000000000001','Test','approved',now());
select public.queue_inspection_deadlines();
select public.queue_inspection_deadlines();
select pg_temp.assert_true((select count(*)=1 from public.notifications where type='inspection_due' and user_id='a0060000-0000-4000-8000-000000000001'),'deadline milestone not repeated on scheduler retries');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.notifications where asset_id='a0060000-0000-4000-8000-000000000021'),'other company sees no activity');
rollback;
