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
select public.apply_maintenance_field_action('a0060000-0000-4000-8000-000000000030',0,
 'a0060000-0000-4000-8000-000000000031','start','{}',now()-interval '2 hours');
select public.apply_maintenance_field_action('a0060000-0000-4000-8000-000000000030',1,
 'a0060000-0000-4000-8000-000000000032','pause','{}',now()-interval '1 hour');
select public.apply_maintenance_field_action('a0060000-0000-4000-8000-000000000030',0,
 'a0060000-0000-4000-8000-000000000031','start','{}',now()-interval '2 hours');
select pg_temp.assert_true((select jsonb_array_length(j->'labour')=1 and
 ((j->'labour'->0->>'stopped_at')::timestamptz-(j->'labour'->0->>'started_at')::timestamptz)=interval '1 hour'
 from public.maintenance_jobs('a0060000-0000-4000-8000-000000000030') j),'offline labour and exact retry preserve one real hour');
select pg_temp.expect_error($q$select public.apply_maintenance_field_action('a0060000-0000-4000-8000-000000000030',2,
 'a0060000-0000-4000-8000-000000000031','start','{}',now()-interval '3 hours')$q$,'different');
select pg_temp.expect_error($q$select public.apply_maintenance_field_action('a0060000-0000-4000-8000-000000000030',0,
 gen_random_uuid(),'save_report','{}',now())$q$,'changed');
select pg_temp.expect_error($q$select public.apply_maintenance_field_action('a0060000-0000-4000-8000-000000000030',2,
 gen_random_uuid(),'start','{}',now()+interval '1 day')$q$,'Device time');
select set_config('request.jwt.claim.sub','a0060000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.apply_maintenance_field_action('a0060000-0000-4000-8000-000000000030',2,
 gen_random_uuid(),'start','{}',now())$q$,'Access denied');
rollback;