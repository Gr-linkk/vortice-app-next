begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.must_fail(command text) returns void language plpgsql as $$
begin begin execute command; exception when others then return; end; raise exception 'Unexpected success: %',command; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('a0140000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'fleet-import-'||n||'@example.invalid','{"onboarding_v2":true}'::jsonb from generate_series(1,3)n;
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0140000-0000-4000-8000-000000000011','Import A','a0140000-0000-4000-8000-000000000001'),
 ('a0140000-0000-4000-8000-000000000012','Import B','a0140000-0000-4000-8000-000000000002');
insert into public.organization_memberships(organization_id,profile_id,roles) values
 ('a0140000-0000-4000-8000-000000000011','a0140000-0000-4000-8000-000000000001',array['company_owner']),
 ('a0140000-0000-4000-8000-000000000012','a0140000-0000-4000-8000-000000000002',array['company_owner']),
 ('a0140000-0000-4000-8000-000000000011','a0140000-0000-4000-8000-000000000003',array['operator']);
insert into public.organization_identity_context values
 ('a0140000-0000-4000-8000-000000000001','a0140000-0000-4000-8000-000000000011'),
 ('a0140000-0000-4000-8000-000000000002','a0140000-0000-4000-8000-000000000012'),
 ('a0140000-0000-4000-8000-000000000003','a0140000-0000-4000-8000-000000000011');
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0140000-0000-4000-8000-000000000001','maintenance_planning',true),
 ('a0140000-0000-4000-8000-000000000001','pm_checklists',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000001',true);
select public.save_checklist_procedure('a0140000-0000-4000-8000-000000000091','a0140000-0000-4000-8000-000000000090',0,'draft',
 '{"name":"Imported service checklist","checklist_type":"pm","items":[{"description_en":"Check connections","category":"Service","definition":{}}]}');
select public.save_checklist_procedure('a0140000-0000-4000-8000-000000000092','a0140000-0000-4000-8000-000000000090',1,'publish','{}');
do $$ declare data jsonb:='[{"name":"Import excavator","asset_type_id":"00000000-0000-0000-0000-000000000023","serial_number":"001234","meter_unit":"hours","components":[{"label":"Main engine","kind":"main","meter_unit":"hours","current_hours":125.5,"primary_meter":true,"plans":[{"interval_label":"250 hour service","interval_hours":250,"last_service_hours":100,"interval_months":6,"last_service_date":"2026-01-01"}]}]}]';
 client uuid:='a0140000-0000-4000-8000-000000000001'; operation uuid:='a0140000-0000-4000-8000-000000000021'; result jsonb; asset uuid; bad jsonb;
begin
 data:=jsonb_set(data,'{0,components,0,plans,0,template_id}',to_jsonb((select id from public.checklist_templates where procedure_id='a0140000-0000-4000-8000-000000000090')));
 perform pg_temp.assert_true((public.fleet_import_context()->>'client_id')::uuid=client,'context selects only own fleet');
 result:=public.import_fleet(operation,client,data,true);
 perform pg_temp.assert_true(result->'errors'='[]'::jsonb,'valid preview');
 perform pg_temp.assert_true(not exists(select 1 from public.assets where client_id=client),'preview creates nothing');
 bad:=data||jsonb_build_array(jsonb_set(data->0,'{name}','"Bad row"')||'{"serial_number":"OTHER","meter_unit":"gallons"}');
 perform pg_temp.assert_true(jsonb_array_length(public.import_fleet(operation,client,bad,true)->'errors')=1,'preview reports bad units');
 perform pg_temp.must_fail(format('select public.import_fleet(%L,%L,%L,false)',operation,client,bad));
 perform pg_temp.assert_true(not exists(select 1 from public.assets where client_id=client),'invalid batch is atomic');
 bad:=jsonb_set(data,'{0,components,0,plans,0,template_id}','"a0140000-0000-4000-8000-000000000099"');
 perform pg_temp.assert_true(jsonb_array_length(public.import_fleet(operation,client,bad,true)->'errors')=1,'unavailable checklist rejected before import');
 result:=public.import_fleet(operation,client,data,false);
 asset:=(result->'assets'->0->>'id')::uuid;
 perform pg_temp.assert_true(result->>'imported'='true','commit returns receipt');
 perform pg_temp.assert_true(public.import_fleet(operation,client,data,false)=result,'lost response retry returns same receipt');
 perform pg_temp.assert_true((select count(*)=1 from public.assets where client_id=client),'retry creates no duplicate');
 perform pg_temp.assert_true((select serial_number='001234' from public.assets where id=asset),'serial leading zeroes preserved');
 perform pg_temp.assert_true((select current_hours=125.5 from public.asset_engines where asset_id=asset),'opening meter recorded');
 perform pg_temp.assert_true((select count(*)=1 from public.hour_logs where asset_id=asset),'opening history recorded once');
 perform pg_temp.must_fail(format('select public.import_fleet(%L,%L,%L,false)',operation,client,jsonb_set(data,'{0,name}','"Changed retry"')));
 perform pg_temp.assert_true(jsonb_array_length(public.import_fleet(gen_random_uuid(),client,data,true)->'errors')=1,'existing fleet duplicate rejected');
end $$;
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000003',true);
select pg_temp.must_fail($q$select public.fleet_import_context()$q$);
select pg_temp.must_fail($q$select public.import_fleet(gen_random_uuid(),'a0140000-0000-4000-8000-000000000001','[]',false)$q$);
select set_config('request.jwt.claim.sub','a0140000-0000-4000-8000-000000000002',true);
select pg_temp.must_fail($q$select public.fleet_import_context('a0140000-0000-4000-8000-000000000001')$q$);
select pg_temp.must_fail($q$select public.import_fleet(gen_random_uuid(),'a0140000-0000-4000-8000-000000000001','[]',false)$q$);
select pg_temp.assert_true((public.fleet_import_context()->'assets')='[]'::jsonb,'other company sees no imported records');
reset role;
select pg_temp.assert_true((select last_service_hours=100 and interval_hours=250 and last_service_date='2026-01-01'::date from public.asset_service_intervals p join public.assets a on a.id=p.asset_id where a.client_id='a0140000-0000-4000-8000-000000000001'),'service baseline preserved');
select pg_temp.assert_true((select p.checklist_template_id=t.id from public.asset_service_intervals p join public.assets a on a.id=p.asset_id cross join public.checklist_templates t where a.client_id='a0140000-0000-4000-8000-000000000001' and t.procedure_id='a0140000-0000-4000-8000-000000000090'),'selected published checklist is attached to the imported plan');
set local role anon;
select pg_temp.must_fail($q$select public.import_fleet(gen_random_uuid(),'a0140000-0000-4000-8000-000000000001','[]',false)$q$);
reset role;
select pg_temp.assert_true((select count(*)=1 from public.fleet_import_batches where client_id='a0140000-0000-4000-8000-000000000001'),'one durable batch receipt');
rollback;
