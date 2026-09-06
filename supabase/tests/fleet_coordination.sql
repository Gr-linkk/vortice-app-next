begin;
create function pg_temp.assert_true(ok boolean,label text) returns void
language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'FAIL: %',label; end if;
end $$;
create function pg_temp.expect_error(command text,expected text) returns void
language plpgsql as $$ begin
 begin execute command;
 exception when others then
  if position(expected in sqlerrm)>0 then return; end if;
  raise;
 end;
 raise exception 'Expected error containing: %',expected;
end $$;

insert into auth.users(id,email,raw_user_meta_data)
select ('a0070000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'now007-'||n||'@example.invalid','{}'::jsonb from generate_series(1,9) n;
update public.profiles set role=case right(id::text,1)
 when '1' then 'client' when '2' then 'client_mechanic' when '3' then 'client'
 when '4' then 'operator' when '5' then 'owner' when '6' then 'employee'
 when '7' then 'client_admin' when '8' then 'client_mechanic' else 'employee' end,
 full_name='NOW007 '||right(id::text,1) where id::text like 'a0070000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0070000-0000-4000-8000-000000000010','Company A','a0070000-0000-4000-8000-000000000001');
update public.profiles set org_id='a0070000-0000-4000-8000-000000000010'
 where id in ('a0070000-0000-4000-8000-000000000001','a0070000-0000-4000-8000-000000000002',
 'a0070000-0000-4000-8000-000000000004','a0070000-0000-4000-8000-000000000007','a0070000-0000-4000-8000-000000000008');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0070000-0000-4000-8000-000000000001','pm_checklists',true),
 ('a0070000-0000-4000-8000-000000000001','maintenance_planning',true);
insert into public.asset_types(id,category,name) values
 ('a0070000-0000-4000-8000-000000000020','test','Machine');
insert into public.assets(id,client_id,asset_type_id,name,location) values
 ('a0070000-0000-4000-8000-000000000021','a0070000-0000-4000-8000-000000000001','a0070000-0000-4000-8000-000000000020','A vessel','North dock'),
 ('a0070000-0000-4000-8000-000000000022','a0070000-0000-4000-8000-000000000003','a0070000-0000-4000-8000-000000000020','B vessel','South dock');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000001',true);
select public.create_maintenance_job('a0070000-0000-4000-8000-000000000030',
 '{"asset_id":"a0070000-0000-4000-8000-000000000021","title":"Repair cooling leak","assigned_to":"a0070000-0000-4000-8000-000000000002","priority":"urgent","due_date":"2026-09-05"}');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000002',true);
select public.post_coordination_message('a0070000-0000-4000-8000-000000000040','job',
 'a0070000-0000-4000-8000-000000000030',
 '{"kind":"handover","visibility":"team","body":"Leak found at the pump seal","isolation":"isolated","next_steps":"Replace seal and check under load","mentions":["a0070000-0000-4000-8000-000000000001"]}');
select public.post_coordination_message('a0070000-0000-4000-8000-000000000040','job',
 'a0070000-0000-4000-8000-000000000030',
 '{"kind":"handover","visibility":"team","body":"Leak found at the pump seal","isolation":"isolated","next_steps":"Replace seal and check under load","mentions":["a0070000-0000-4000-8000-000000000001"]}');
select pg_temp.assert_true(jsonb_array_length(public.coordination_thread('job',
 'a0070000-0000-4000-8000-000000000030')->'posts')=1,'retry creates one handover');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(jsonb_array_length(public.coordination_inbox())=1,'mention is delivered once');
select public.acknowledge_handover('a0070000-0000-4000-8000-000000000040');
select public.acknowledge_handover('a0070000-0000-4000-8000-000000000040');
select pg_temp.assert_true(jsonb_array_length(public.coordination_thread('job',
 'a0070000-0000-4000-8000-000000000030')->'posts'->0->'acknowledgements')=1,'acknowledgment is idempotent');
select pg_temp.assert_true(public.coordination_inbox()->0->>'read'='true','acknowledgment also marks the mention read');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.coordination_thread('job','a0070000-0000-4000-8000-000000000030')$q$,'Access denied');
select pg_temp.assert_true(public.coordination_inbox()='[]','other company has no mentions');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000004',true);
select pg_temp.expect_error($q$select public.coordination_thread('job','a0070000-0000-4000-8000-000000000030')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000008',true);
select pg_temp.expect_error($q$select public.coordination_thread('job','a0070000-0000-4000-8000-000000000030')$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000006',true);
select pg_temp.expect_error($q$select public.coordination_thread('job','a0070000-0000-4000-8000-000000000030')$q$,'Access denied');

-- A provider-only note is absent from company reads, while a shared update is visible.
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000005',true);
select pg_temp.assert_true(jsonb_array_length(public.coordination_thread('job','a0070000-0000-4000-8000-000000000030')->'posts')=0,'provider cannot read company-team notes');
select public.post_coordination_message('a0070000-0000-4000-8000-000000000042','job','a0070000-0000-4000-8000-000000000030',
 '{"body":"Provider private cost discussion","visibility":"team"}');
select public.post_coordination_message('a0070000-0000-4000-8000-000000000043','job','a0070000-0000-4000-8000-000000000030',
 '{"body":"Seal delivery confirmed","visibility":"shared","mentions":["a0070000-0000-4000-8000-000000000001"]}');
select pg_temp.assert_true(jsonb_array_length(public.coordination_thread('job','a0070000-0000-4000-8000-000000000030')->'posts')=2,'provider sees own private note and shared update');
select pg_temp.expect_error($q$select public.post_coordination_message(gen_random_uuid(),'job','a0070000-0000-4000-8000-000000000030',
 '{"body":"Private with invalid mention","mentions":["a0070000-0000-4000-8000-000000000001"]}')$q$,'Mention recipient');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(jsonb_array_length(public.coordination_thread('job','a0070000-0000-4000-8000-000000000030')->'posts')=2,'company sees its handover and shared update only');
select pg_temp.assert_true(position('Provider private' in public.coordination_thread('job','a0070000-0000-4000-8000-000000000030')::text)=0,'private body is not returned');
select pg_temp.assert_true(jsonb_array_length(public.coordination_people('job','a0070000-0000-4000-8000-000000000030'))=2,'team mentions include assigned mechanic and company admin only');

-- Storage uses the same subject and audience rules; posted objects are immutable.
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000002',true);
insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'coordination-attachments',
 'job/a0070000-0000-4000-8000-000000000030/a0070000-0000-4000-8000-000000000002/a0070000-0000-4000-8000-000000000041/photo.jpg');
select public.post_coordination_message('a0070000-0000-4000-8000-000000000041','job','a0070000-0000-4000-8000-000000000030',
 '{"body":"Seal photo before replacement","attachments":[{"name":"Seal.jpg","path":"job/a0070000-0000-4000-8000-000000000030/a0070000-0000-4000-8000-000000000002/a0070000-0000-4000-8000-000000000041/photo.jpg"}]}');
select pg_temp.assert_true((select count(*)=1 from storage.objects where bucket_id='coordination-attachments'),'author can read posted photo');
do $$ begin
 begin delete from storage.objects where bucket_id='coordination-attachments';
 exception when insufficient_privilege then
  -- Hosted Storage may reject even a zero-row DELETE before RLS evaluation.
  if position('Direct deletion from storage tables is not allowed' in sqlerrm)=0 then raise; end if;
 end;
end $$;
update storage.objects set name='changed.jpg' where bucket_id='coordination-attachments';
select pg_temp.assert_true((select count(*)=1 from storage.objects where bucket_id='coordination-attachments'),'posted photo cannot be deleted or replaced');
select pg_temp.expect_error($q$select public.post_coordination_message('a0070000-0000-4000-8000-000000000041','job','a0070000-0000-4000-8000-000000000030','{"body":"Changed retry"}')$q$,'different input');
select pg_temp.expect_error($q$select public.post_coordination_message(gen_random_uuid(),'job','a0070000-0000-4000-8000-000000000030','{"body":"Bad mention","mentions":["a0070000-0000-4000-8000-000000000003"]}')$q$,'Mention recipient');
select pg_temp.expect_error($q$select public.post_coordination_message(gen_random_uuid(),'job','a0070000-0000-4000-8000-000000000030','{"body":"Incomplete handover","kind":"handover"}')$q$,'Handover requires');
select pg_temp.expect_error($q$select public.post_coordination_message(gen_random_uuid(),'job','a0070000-0000-4000-8000-000000000030','{"body":"Invalid attachment","attachments":[{"name":"Other.jpg","path":"elsewhere.jpg"}]}')$q$,'Attachment is missing');
select pg_temp.expect_error($q$select public.acknowledge_handover('a0070000-0000-4000-8000-000000000040')$q$,'another participant');
select pg_temp.expect_error($q$select count(*) from public.coordination_posts$q$,'permission denied');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000005',true);
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='coordination-attachments'),'provider cannot sign or read company-team photo');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='coordination-attachments'),'foreign company cannot read photo');
select pg_temp.expect_error($q$insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'coordination-attachments',
 'job/a0070000-0000-4000-8000-000000000030/a0070000-0000-4000-8000-000000000003/a0070000-0000-4000-8000-000000000080/photo.jpg')$q$,'row-level security');

-- Capability disablement retains history but blocks new execution collaboration.
reset role;
update public.client_capabilities set enabled=false where client_id='a0070000-0000-4000-8000-000000000001' and capability_key='pm_checklists';
set local role authenticated;
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.coordination_thread('job','a0070000-0000-4000-8000-000000000030')->>'can_post'='false','disabled execution is read-only');
select pg_temp.expect_error($q$select public.post_coordination_message(gen_random_uuid(),'job','a0070000-0000-4000-8000-000000000030','{"body":"Should fail"}')$q$,'Access denied');
reset role;
update public.client_capabilities set enabled=true where client_id='a0070000-0000-4000-8000-000000000001' and capability_key='pm_checklists';
set local role authenticated;

-- Fault discussions remain available to the reporting operator and the fleet.
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000004',true);
select public.report_maintenance_fault('a0070000-0000-4000-8000-000000000060','a0070000-0000-4000-8000-000000000021','Exhaust leak','urgent');
select public.post_coordination_message('a0070000-0000-4000-8000-000000000061','fault','a0070000-0000-4000-8000-000000000060',
 '{"body":"Machine isolated at the dock","mentions":["a0070000-0000-4000-8000-000000000001"]}');
select pg_temp.assert_true(jsonb_array_length(public.coordination_thread('fault','a0070000-0000-4000-8000-000000000060')->'posts')=1,'operator can discuss a fault');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.coordination_thread('fault','a0070000-0000-4000-8000-000000000060')$q$,'Access denied');

-- Reassignment removes private job/inbox access without granting it through a mention.
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000001',true);
select public.post_coordination_message('a0070000-0000-4000-8000-000000000044','job','a0070000-0000-4000-8000-000000000030',
 '{"body":"Please prepare the handover","mentions":["a0070000-0000-4000-8000-000000000002"]}');
select public.change_maintenance_job('a0070000-0000-4000-8000-000000000030',0,gen_random_uuid(),'assign',
 '{"assigned_to":"a0070000-0000-4000-8000-000000000008"}');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.coordination_inbox()='[]','revoked participant loses inbox access');
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='coordination-attachments'),'revoked participant loses photo access');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000008',true);
select public.acknowledge_handover('a0070000-0000-4000-8000-000000000040');
select pg_temp.assert_true(jsonb_array_length(public.coordination_thread('job','a0070000-0000-4000-8000-000000000030')->'posts')=4,'next mechanic sees prior team handover');
-- History retains the part's identity and quantity after removal.
select public.change_maintenance_job('a0070000-0000-4000-8000-000000000030',1,gen_random_uuid(),'start','{}');
select public.change_maintenance_job('a0070000-0000-4000-8000-000000000030',2,
 'a0070000-0000-4000-8000-000000000070','add_part','{"description":"Pump seal","part_number":"SEAL-42","quantity":2,"unit_cost":12.5}');
select public.change_maintenance_job('a0070000-0000-4000-8000-000000000030',3,
 'a0070000-0000-4000-8000-000000000071','remove_part','{"part_id":"a0070000-0000-4000-8000-000000000070"}');
select pg_temp.assert_true(jsonb_array_length(public.asset_history('a0070000-0000-4000-8000-000000000021','parts')->'entries')=2,'history includes part addition and removal');
select pg_temp.assert_true(position('SEAL-42' in (public.asset_history('a0070000-0000-4000-8000-000000000021','parts')->'entries'->0)::text)>0,'removed part retains its identifying detail');
select pg_temp.assert_true(jsonb_array_length(public.asset_history('a0070000-0000-4000-8000-000000000021','parts','SEAL-42')->'entries')=2,'search includes part identification');
select pg_temp.assert_true(jsonb_array_length(public.asset_history('a0070000-0000-4000-8000-000000000021','parts','does not match')->'entries')=0,'unmatched search is empty');
select pg_temp.assert_true(jsonb_array_length(public.asset_history('a0070000-0000-4000-8000-000000000021',null,'','2100-01-01','2101-01-01')->'entries')=0,'date range is applied on the server');
select pg_temp.expect_error($q$select public.asset_history('a0070000-0000-4000-8000-000000000021','bad-category')$q$,'Invalid history filter');
select pg_temp.expect_error($q$select count(*) from public.asset_history_entries$q$,'permission denied');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(position('Provider private' in public.asset_history('a0070000-0000-4000-8000-000000000021')::text)=0,'private provider notes do not leak through history');
create temporary table page_checkpoint as select public.asset_history('a0070000-0000-4000-8000-000000000021',p_limit=>1) as page;
select pg_temp.assert_true((select page->>'has_more'='true' from page_checkpoint),'bounded history reports more rows');
select pg_temp.assert_true((select public.asset_history('a0070000-0000-4000-8000-000000000021',
 p_before=>(page->'entries'->0->>'occurred_at')::timestamptz,p_before_id=>(page->'entries'->0->>'id')::uuid,
 p_limit=>1,p_as_of=>(page->>'as_of')::timestamptz)->'entries'->0->>'id'<>page->'entries'->0->>'id' from page_checkpoint),'next page does not repeat the cursor row');
reset role;
update public.assets set location='East pier' where id='a0070000-0000-4000-8000-000000000021';
set local role authenticated;
select pg_temp.assert_true(position('North dock' in public.asset_history('a0070000-0000-4000-8000-000000000021','asset','East pier')::text)>0,'location change records previous and current values');
select pg_temp.assert_true((select jsonb_array_length(public.asset_history('a0070000-0000-4000-8000-000000000021',
 p_search=>'East pier',p_as_of=>(page->>'as_of')::timestamptz)->'entries')=0 from page_checkpoint),'export snapshot excludes events captured after its cutoff');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true(jsonb_array_length(public.asset_history('a0070000-0000-4000-8000-000000000021','parts')->'entries')=0,'operator does not gain private job parts through history');
select pg_temp.assert_true(position('Leak found at the pump seal' in public.asset_history('a0070000-0000-4000-8000-000000000021')::text)=0,'operator cannot read a mechanic handover through history');
select pg_temp.assert_true(jsonb_array_length(public.asset_history('a0070000-0000-4000-8000-000000000021','fault')->'entries')>0,'operator retains fleet fault history');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000003',true);
select pg_temp.expect_error($q$select public.asset_history('a0070000-0000-4000-8000-000000000021')$q$,'Access denied');
-- Fleet indicators and their lists use the same scoped rows.
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'unassessed')::int=1,'company B sees only its own unassessed asset');
select pg_temp.assert_true(position('A vessel' in public.fleet_attention('2026-09-06')::text)=0,'overview excludes another company');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000004',true);
select pg_temp.expect_error($q$select public.fleet_attention()$q$,'Access denied');
select set_config('request.jwt.claim.sub','a0070000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'urgent_faults')::int=1,'urgent fault is actionable');
select pg_temp.assert_true(jsonb_array_length(public.fleet_attention('2026-09-06','urgent_faults')->'items')=1,'count matches filtered items');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'overdue_work')::int=1,'local calendar identifies overdue work');
select pg_temp.assert_true((public.fleet_attention('2026-09-05')->'counts'->>'upcoming_work')::int=1,'work due today is upcoming');
select pg_temp.assert_true((public.fleet_attention('2026-09-06',null,0,1)->>'has_more')::boolean,'attention pagination reports remainder');
select public.change_maintenance_job('a0070000-0000-4000-8000-000000000030',4,gen_random_uuid(),'pause','{}');
select pg_temp.expect_error($q$select public.change_maintenance_job('a0070000-0000-4000-8000-000000000030',5,gen_random_uuid(),'block','{"note":"Seal kit delayed","blocked_category":"inventory"}')$q$,'Invalid blocked category');
select public.change_maintenance_job('a0070000-0000-4000-8000-000000000030',5,gen_random_uuid(),'block','{"note":"Seal kit delayed","blocked_category":"parts"}');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'waiting_parts')::int=1,'explicit parts block appears in its bucket');
select pg_temp.assert_true((select j->>'blocked_category'='parts' from public.maintenance_jobs('a0070000-0000-4000-8000-000000000030') j),'job returns blocked category');
select pg_temp.assert_true((select count(*)=count(distinct (i->>'kind',i->>'id')) from jsonb_array_elements(public.fleet_attention('2026-09-06')->'items') i),'priority list has distinct source records');
select public.change_maintenance_job('a0070000-0000-4000-8000-000000000030',6,gen_random_uuid(),'start','{}');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'waiting_parts')::int=0,'resuming work clears its parts wait');
select public.change_maintenance_job('a0070000-0000-4000-8000-000000000030',7,gen_random_uuid(),'pause','{}');
select public.change_maintenance_job('a0070000-0000-4000-8000-000000000030',8,gen_random_uuid(),'block','{"note":"Waiting for specialist","blocked_category":"people"}');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'waiting_people')::int=1,'people blocks are explicit');
select public.change_asset_availability('a0070000-0000-4000-8000-000000000021',0,gen_random_uuid(),'out_of_service','Isolated for repair');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'unavailable')::int=1,'unavailable assets have their own indicator');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'unassessed')::int=0,'recorded availability removes unknown status');
select pg_temp.expect_error($q$select public.fleet_attention('2026-09-06','invalid')$q$,'Invalid attention filter');
-- An old mentioned post remains a usable deep link after more than one page.
reset role;
insert into public.coordination_posts(id,subject_kind,subject_id,asset_id,client_id,author_id,author_name,team,visibility,kind,body,request_payload)
select ('a0070000-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,'job','a0070000-0000-4000-8000-000000000030',
 'a0070000-0000-4000-8000-000000000021','a0070000-0000-4000-8000-000000000001','a0070000-0000-4000-8000-000000000001',
 'Company manager','company','team','comment','Later shift note '||n,'{}' from generate_series(1,55) n;
insert into public.asset_engines(id,asset_id,label,current_hours) values
 ('a0070000-0000-4000-8000-000000000080','a0070000-0000-4000-8000-000000000021','Generator',1000);
insert into public.asset_service_intervals(id,asset_id,engine_id,interval_hours,next_due_hours) values
 ('a0070000-0000-4000-8000-000000000081','a0070000-0000-4000-8000-000000000021','a0070000-0000-4000-8000-000000000080',250,950),
 ('a0070000-0000-4000-8000-000000000082','a0070000-0000-4000-8000-000000000021','a0070000-0000-4000-8000-000000000080',500,1050),
 ('a0070000-0000-4000-8000-000000000083','a0070000-0000-4000-8000-000000000021',null,750,null);
set local role authenticated;
select pg_temp.assert_true((public.coordination_thread('job','a0070000-0000-4000-8000-000000000030')->>'has_more')::boolean,'thread pages are bounded');
select pg_temp.assert_true(public.coordination_thread('job','a0070000-0000-4000-8000-000000000030',p_focus=>'a0070000-0000-4000-8000-000000000040')->'posts'->0->>'id'='a0070000-0000-4000-8000-000000000040','deep link opens old mentioned note');
select pg_temp.expect_error($q$select public.coordination_thread('job','a0070000-0000-4000-8000-000000000030',p_focus=>'a0070000-0000-4000-8000-000000000042')$q$,'Message is unavailable');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'overdue_service')::int=1,'overdue service compares actual component meter');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'approaching_service')::int=1,'50-hour boundary is included');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'plan_setup')::int=1,'incomplete plan setup is visible');
reset role;
update public.asset_engines set current_hours=999 where id='a0070000-0000-4000-8000-000000000080';
update public.work_orders set status='closed' where id='a0070000-0000-4000-8000-000000000030';
update public.maintenance_requests set status='resolved' where id='a0070000-0000-4000-8000-000000000060';
set local role authenticated;
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'approaching_service')::int=0,'51 hours is outside the approaching bucket');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'urgent_faults')::int=0,'resolved fault leaves the urgent indicator');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'overdue_work')::int=0,'closed work leaves overdue indicator');
rollback;
