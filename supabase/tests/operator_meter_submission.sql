begin;
create function pg_temp.ok(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.denied(command text) returns void language plpgsql as $$
begin begin execute command; exception when insufficient_privilege then return; end; raise exception 'Expected access denial'; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('b0390000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'operator-meter-'||n||'@example.invalid','{}' from generate_series(1,5) n;
update public.profiles set role=case right(id::text,1) when '1' then 'client' when '2' then 'operator' when '3' then 'client_mechanic' when '4' then 'client' else 'operator' end,full_name='Discussion test' where id::text like 'b0390000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('b0390000-0000-4000-8000-000000000010','Discussion company A','b0390000-0000-4000-8000-000000000001'),
 ('b0390000-0000-4000-8000-000000000011','Discussion company B','b0390000-0000-4000-8000-000000000004');
update public.profiles set org_id=case when right(id::text,1) in ('1','2','3') then 'b0390000-0000-4000-8000-000000000010'::uuid else 'b0390000-0000-4000-8000-000000000011'::uuid end where id::text like 'b0390000-%';
insert into public.client_capabilities(client_id,capability_key,enabled)
select 'b0390000-0000-4000-8000-000000000001',k,true from unnest(array['pm_checklists','operational_checklists','maintenance_planning']) k;
insert into public.asset_types(id,category,name) values('b0390000-0000-4000-8000-000000000020','test','Source equipment');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('b0390000-0000-4000-8000-000000000021','b0390000-0000-4000-8000-000000000001','b0390000-0000-4000-8000-000000000020','Source A'),
 ('b0390000-0000-4000-8000-000000000022','b0390000-0000-4000-8000-000000000004','b0390000-0000-4000-8000-000000000020','Source B');
create temp table meter_payload(data jsonb); grant all on meter_payload to authenticated;
create function pg_temp.meter_changed(command text) returns void language plpgsql as $$
begin begin execute command; exception when serialization_failure then
 if position('equipment meter changed' in sqlerrm)>0 then return; end if; raise; end;
 raise exception 'Expected explicit meter identity rejection'; end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0390000-0000-4000-8000-000000000001',true);
select public.save_checklist_procedure(gen_random_uuid(),'b0390000-0000-4000-8000-000000000030',0,'draft','{"name":"Meter snapshot check","checklist_type":"operator_daily","items":[{"description_en":"Check guards"}]}');
select public.save_checklist_procedure(gen_random_uuid(),'b0390000-0000-4000-8000-000000000030',1,'publish','{}');
insert into meter_payload select jsonb_build_object('asset_id','b0390000-0000-4000-8000-000000000021','template_id',t.id,'template_version',1,'run_type','pre_departure','started_at',now(),'completed_at',now(),'responses',jsonb_build_object(i.id,'pass'),'notes','{}'::jsonb,'photos','{}'::jsonb,'current_hours',72,'meter_unit','hours') from public.checklist_templates t join public.checklist_items i on i.template_id=t.id where t.procedure_id='b0390000-0000-4000-8000-000000000030';
select set_config('request.jwt.claim.sub','b0390000-0000-4000-8000-000000000002',true);
select pg_temp.meter_changed($q$select public.submit_operations_checklist('b0390000-0000-4000-8000-000000000040',data||'{"meter_unit":"km"}') from meter_payload$q$);
select pg_temp.ok((select count(*)=0 from public.saved_checklists where id='b0390000-0000-4000-8000-000000000040'),'rejected unit mismatch creates no run snapshot');
select public.submit_operations_checklist('b0390000-0000-4000-8000-000000000040',(select data from meter_payload));
reset role;
update public.assets set meter_unit='km' where id='b0390000-0000-4000-8000-000000000021';
set local role authenticated;
select set_config('request.jwt.claim.sub','b0390000-0000-4000-8000-000000000002',true);
select public.submit_operations_checklist('b0390000-0000-4000-8000-000000000040',(select data from meter_payload));
select pg_temp.ok((select meter_unit='hours' and current_hours=72 and snapshot->'header'->>'meter_unit'='hours' from public.saved_checklists where id='b0390000-0000-4000-8000-000000000040'),'accepted retry retains exact original meter unit');
select pg_temp.meter_changed($q$select public.submit_operations_checklist('b0390000-0000-4000-8000-000000000041',data) from meter_payload$q$);
rollback;
