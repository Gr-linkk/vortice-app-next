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
select ('a0090000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'e2e-009-'||n||'@example.invalid','{}'::jsonb from generate_series(1,7) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '7' then 'client_admin' else 'employee' end,
 full_name='E2E-009 '||right(id::text,1) where id::text like 'a0090000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0090000-0000-4000-8000-000000000010','Company A','a0090000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0090000-0000-4000-8000-000000000010'
 where id in ('a0090000-0000-4000-8000-000000000001','a0090000-0000-4000-8000-000000000002','a0090000-0000-4000-8000-000000000004','a0090000-0000-4000-8000-000000000007');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0090000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a0090000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a0090000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0090000-0000-4000-8000-000000000021','a0090000-0000-4000-8000-000000000001','a0090000-0000-4000-8000-000000000020','A vessel'),
 ('a0090000-0000-4000-8000-000000000022','a0090000-0000-4000-8000-000000000003','a0090000-0000-4000-8000-000000000020','B vessel');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000001',true);
select public.transfer_asset_custody('a0090000-0000-4000-8000-000000000021',0,'a0090000-0000-4000-8000-000000000030',
 '{"site":"E2E-009 North dock","responsible_id":"a0090000-0000-4000-8000-000000000002","lifecycle":"active","reason":"Assigned for morning service"}');
select public.transfer_asset_custody('a0090000-0000-4000-8000-000000000021',0,'a0090000-0000-4000-8000-000000000030',
 '{"site":"E2E-009 North dock","responsible_id":"a0090000-0000-4000-8000-000000000002","lifecycle":"active","reason":"Assigned for morning service"}');
select pg_temp.assert_true((select count(*)=1 from public.asset_custody_events),'retry creates one transfer');
select pg_temp.assert_true((select location='E2E-009 North dock' from public.assets where id='a0090000-0000-4000-8000-000000000021'),'location saved atomically');
select pg_temp.expect_error($q$select public.transfer_asset_custody('a0090000-0000-4000-8000-000000000021',0,gen_random_uuid(),'{"site":"South"}')$q$,'changed');
select pg_temp.expect_error($q$select public.transfer_asset_custody('a0090000-0000-4000-8000-000000000021',1,gen_random_uuid(),'{"responsible_id":"a0090000-0000-4000-8000-000000000003"}')$q$,'member of this company');
select pg_temp.expect_error($q$select public.transfer_asset_custody('a0090000-0000-4000-8000-000000000021',1,gen_random_uuid(),'{"responsible_id":"a0090000-0000-4000-8000-000000000002","reason":""}')$q$,'reason');
select public.transfer_asset_custody('a0090000-0000-4000-8000-000000000021',1,'a0090000-0000-4000-8000-000000000031',
 '{"site":"E2E-009 Dry store","responsible_id":"a0090000-0000-4000-8000-000000000001","lifecycle":"stored","reason":"Inspection pending before launch"}');
select pg_temp.assert_true((select previous->>'site'='E2E-009 North dock' and current_state->>'site'='E2E-009 Dry store' from public.asset_custody_events where id='a0090000-0000-4000-8000-000000000031'),'old and new transfer state retained');
select pg_temp.expect_error($q$update public.asset_custody set site='Bypass'$q$,'permission denied');
select pg_temp.expect_error($q$delete from public.asset_custody_events$q$,'permission denied');
select pg_temp.expect_error($q$select public.save_maintenance_setup(gen_random_uuid(),'asset','a0090000-0000-4000-8000-000000000021',2,
 '{"name":"A vessel","location":"Unrecorded move"}')$q$,'Record transfer');
select public.create_asset_inspection('a0090000-0000-4000-8000-000000000021','a0090000-0000-4000-8000-000000000040','{"title":"E2E-009 Lifting inspection"}');
select public.create_asset_inspection('a0090000-0000-4000-8000-000000000021','a0090000-0000-4000-8000-000000000040','{"title":"E2E-009 Lifting inspection"}');
select pg_temp.assert_true(jsonb_array_length(public.inspection_register())=1,'create retry returns one requirement');
select pg_temp.expect_error($q$select public.create_asset_inspection('a0090000-0000-4000-8000-000000000021','a0090000-0000-4000-8000-000000000040','{"title":"Changed request"}')$q$,'different input');
select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error($q$select public.transfer_asset_custody('a0090000-0000-4000-8000-000000000021',2,gen_random_uuid(),'{}')$q$,'Access denied');
select pg_temp.expect_error($q$select public.create_asset_inspection('a0090000-0000-4000-8000-000000000021',gen_random_uuid(),'{"title":"No permission"}')$q$,'Access denied');
insert into storage.objects(id,bucket_id,name) values('a0090000-0000-4000-8000-000000000060','inspection-evidence',
 'a0090000-0000-4000-8000-000000000021/a0090000-0000-4000-8000-000000000002/a0090000-0000-4000-8000-000000000050.jpg');
select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',0,'a0090000-0000-4000-8000-000000000050','submit',
 '{"inspected_on":"2026-01-01","expires_on":"2026-06-01","procedure_notes":"E2E-009 Procedure version 1","result_notes":"Test load passed","evidence_path":"a0090000-0000-4000-8000-000000000021/a0090000-0000-4000-8000-000000000002/a0090000-0000-4000-8000-000000000050.jpg"}');
select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',0,'a0090000-0000-4000-8000-000000000050','submit',
 '{"inspected_on":"2026-01-01","expires_on":"2026-06-01","procedure_notes":"E2E-009 Procedure version 1","result_notes":"Test load passed","evidence_path":"a0090000-0000-4000-8000-000000000021/a0090000-0000-4000-8000-000000000002/a0090000-0000-4000-8000-000000000050.jpg"}');
select pg_temp.assert_true((public.inspection_register()->0->>'revision')::int=1,'submission retry advances once');
select pg_temp.expect_error($q$select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',1,gen_random_uuid(),'approve','{}')$q$,'Only a manager');
do $$ begin
 delete from storage.objects where id='a0090000-0000-4000-8000-000000000060';
exception when insufficient_privilege then
 -- Hosted Storage additionally forbids SQL DELETE; the API is checked live.
 if position('Direct deletion from storage tables' in sqlerrm)=0 then raise; end if;
end $$;
select pg_temp.assert_true((select count(*)=1 from storage.objects where id='a0090000-0000-4000-8000-000000000060'),'submitted evidence cannot be removed');
select pg_temp.expect_error($q$update public.inspection_submissions set result_notes='Tampered'$q$,'permission denied');
select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error($q$select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',1,gen_random_uuid(),'approve','{"submission_id":"a0090000-0000-4000-8000-000000000050","note":""}')$q$,'review note');
select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',1,'a0090000-0000-4000-8000-000000000051','approve',
 '{"submission_id":"a0090000-0000-4000-8000-000000000050","note":"Evidence verified by manager"}');
select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',1,'a0090000-0000-4000-8000-000000000051','approve',
 '{"submission_id":"a0090000-0000-4000-8000-000000000050","note":"Evidence verified by manager"}');
select pg_temp.assert_true(public.inspection_register()->0->'approved'->>'id'='a0090000-0000-4000-8000-000000000050','approved certificate survives reopen');
select pg_temp.expect_error($q$select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',2,gen_random_uuid(),'submit','{"inspected_on":"2099-01-01","expires_on":"2099-02-01"}')$q$,'dates');
select pg_temp.expect_error($q$select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',2,gen_random_uuid(),'submit','{"inspected_on":"2026-01-01","expires_on":"2025-02-01"}')$q$,'dates');
select pg_temp.expect_error($q$select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',2,gen_random_uuid(),'submit','{"inspected_on":"2026-01-01","expires_on":"2027-01-01"}')$q$,'evidence');
insert into storage.objects(id,bucket_id,name) values('a0090000-0000-4000-8000-000000000061','inspection-evidence',
 'a0090000-0000-4000-8000-000000000021/a0090000-0000-4000-8000-000000000001/a0090000-0000-4000-8000-000000000052.png');
select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',2,'a0090000-0000-4000-8000-000000000052','submit',
 '{"inspected_on":"2026-02-01","expires_on":"2027-02-01","procedure_notes":"E2E-009 Procedure version 2","result_notes":"Renewed after full test","evidence_path":"a0090000-0000-4000-8000-000000000021/a0090000-0000-4000-8000-000000000001/a0090000-0000-4000-8000-000000000052.png"}');
select pg_temp.assert_true(public.inspection_register()->0->'approved'->>'expires_on'='2026-06-01' and public.inspection_register()->0->'pending'->>'expires_on'='2027-02-01','pending renewal does not hide expired approval');
select pg_temp.expect_error($q$select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',2,gen_random_uuid(),'approve','{}')$q$,'changed');
select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',3,'a0090000-0000-4000-8000-000000000053','return',
 '{"submission_id":"a0090000-0000-4000-8000-000000000052","note":"Add test pressure to result"}');
select pg_temp.assert_true(jsonb_array_length(public.inspection_register()->0->'versions')=2 and public.inspection_register()->0->'approved'->>'id'='a0090000-0000-4000-8000-000000000050','returned version preserves current certificate');
select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true((public.asset_assurance_context('a0090000-0000-4000-8000-000000000021')->>'can_submit')::boolean=false,'operator read only');
select pg_temp.expect_error($q$select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',4,gen_random_uuid(),'submit','{}')$q$,'Access denied');
select pg_temp.assert_true((select count(*)=2 from public.inspection_submissions),'operator reads version history');
select set_config('request.jwt.claim.sub','a0090000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(jsonb_array_length(public.inspection_register())=0,'company B register excludes A');
select pg_temp.assert_true((select count(*)=0 from public.asset_custody),'company B cannot read custody');
select pg_temp.assert_true((select count(*)=0 from public.inspection_submissions),'company B cannot read submissions');
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='inspection-evidence' and name like 'a0090000-%'),'company B cannot read evidence');
select pg_temp.expect_error($q$select public.asset_assurance_context('a0090000-0000-4000-8000-000000000021')$q$,'Access denied');
select pg_temp.expect_error($q$select public.change_asset_inspection('a0090000-0000-4000-8000-000000000040',4,gen_random_uuid(),'approve','{}')$q$,'Access denied');
select pg_temp.expect_error($q$insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'inspection-evidence','a0090000-0000-4000-8000-000000000021/a0090000-0000-4000-8000-000000000003/a0090000-0000-4000-8000-000000000054.jpg')$q$,'row-level security');
reset role;
rollback;
