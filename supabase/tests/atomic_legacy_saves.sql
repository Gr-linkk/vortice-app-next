begin;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'FAIL: %',label; end if;
end $$;

insert into auth.users(id,email,raw_user_meta_data) values
 ('a0161000-0000-4000-8000-000000000001','now016-owner@example.invalid','{}'),
 ('a0161000-0000-4000-8000-000000000002','now016-client@example.invalid','{}'),
 ('a0161000-0000-4000-8000-000000000003','now016-other@example.invalid','{}'),
 ('a0161000-0000-4000-8000-000000000004','now016-tech@example.invalid','{}'),
 ('a0161000-0000-4000-8000-000000000005','now016-mechanic@example.invalid','{}'),
 ('a0161000-0000-4000-8000-000000000006','now016-operator@example.invalid','{}');
update public.profiles set role=case right(id::text,1) when '1' then 'owner'
 when '4' then 'employee' when '5' then 'client_mechanic' when '6' then 'operator' else 'client' end
 where id::text like 'a0161000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0161000-0000-4000-8000-000000000008','NOW016 company','a0161000-0000-4000-8000-000000000002');
update public.profiles set org_id='a0161000-0000-4000-8000-000000000008'
 where id in ('a0161000-0000-4000-8000-000000000002','a0161000-0000-4000-8000-000000000005','a0161000-0000-4000-8000-000000000006');
insert into public.asset_types(id,category,name) values
 ('a0161000-0000-4000-8000-000000000010','test','Test machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0161000-0000-4000-8000-000000000011','a0161000-0000-4000-8000-000000000002',
  'a0161000-0000-4000-8000-000000000010','NOW016 test machine');
insert into public.work_orders(id,title,asset_id,client_id,created_by,status,job_type) values
 ('a0161000-0000-4000-8000-000000000020','NOW016 provider inspection',
  'a0161000-0000-4000-8000-000000000011','a0161000-0000-4000-8000-000000000002',
  'a0161000-0000-4000-8000-000000000001','closed','repair');
insert into public.asset_engines(id,asset_id,label,current_hours) values
 ('a0161000-0000-4000-8000-000000000012','a0161000-0000-4000-8000-000000000011','Engine',100);
insert into public.service_requests(id,client_id,asset_id,title,request_type,description,contact_phone_or_whatsapp) values
 ('a0161000-0000-4000-8000-000000000013','a0161000-0000-4000-8000-000000000002','a0161000-0000-4000-8000-000000000011','Request','other_issue','Test repair','123');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0161000-0000-4000-8000-000000000001',true);
select public.record_manual_meter('a0161000-0000-4000-8000-000000000090','a0161000-0000-4000-8000-000000000012','a0161000-0000-4000-8000-000000000011',110,now()-interval '1 minute','Test');
select public.record_manual_meter('a0161000-0000-4000-8000-000000000090','a0161000-0000-4000-8000-000000000012','a0161000-0000-4000-8000-000000000011',110,now()-interval '1 minute','Test');
select pg_temp.assert_true((select count(*)=1 from public.hour_logs where engine_id='a0161000-0000-4000-8000-000000000012'),'manual meter retry inserts one history row');
do $$ declare blocked boolean:=false; begin
 begin perform public.record_manual_meter(gen_random_uuid(),'a0161000-0000-4000-8000-000000000012','a0161000-0000-4000-8000-000000000011',105,now(),'Delayed'); exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'lower delayed reading rejected');
 blocked:=false;
 begin perform public.record_manual_meter(gen_random_uuid(),'a0161000-0000-4000-8000-000000000012','a0161000-0000-4000-8000-000000000011',120,now()-interval '2 minutes','Old capture'); exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'older capture rejected even with higher value');
end $$;
select pg_temp.assert_true((select current_hours=110 from public.asset_engines where id='a0161000-0000-4000-8000-000000000012'),'rejected reading cannot overwrite accepted meter');
select pg_temp.assert_true((select count(*)=1 from public.hour_logs where engine_id='a0161000-0000-4000-8000-000000000012'),'rejected reading leaves no partial history');
select public.create_client_org('a0161000-0000-4000-8000-000000000091','Atomic company','a0161000-0000-4000-8000-000000000003');
select public.create_client_org('a0161000-0000-4000-8000-000000000091','Atomic company','a0161000-0000-4000-8000-000000000003');
select pg_temp.assert_true((select org_id='a0161000-0000-4000-8000-000000000091' from public.profiles where id='a0161000-0000-4000-8000-000000000003'),'organization creation links owner');
reset role;
create table public.retained_org_reference(org uuid references public.client_orgs(id));
insert into retained_org_reference values('a0161000-0000-4000-8000-000000000091');
set local role authenticated;
do $$ declare blocked boolean:=false; begin
 begin perform public.delete_client_org(gen_random_uuid(),'a0161000-0000-4000-8000-000000000091'); exception when foreign_key_violation then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'dependent organization deletion refused');
 perform pg_temp.assert_true((select org_id='a0161000-0000-4000-8000-000000000091' from public.profiles where id='a0161000-0000-4000-8000-000000000003'),'refused deletion restores membership');
end $$;
reset role;
delete from retained_org_reference;
set local role authenticated;
select public.delete_client_org('a0161000-0000-4000-8000-000000000092','a0161000-0000-4000-8000-000000000091');
select public.delete_client_org('a0161000-0000-4000-8000-000000000092','a0161000-0000-4000-8000-000000000091');
select pg_temp.assert_true((select org_id is null from public.profiles where id='a0161000-0000-4000-8000-000000000003'),'successful deletion clears membership once');
do $$ declare request jsonb:='{"title":"Atomic provider job","asset_id":"a0161000-0000-4000-8000-000000000011","client_id":"a0161000-0000-4000-8000-000000000002","created_by":"a0161000-0000-4000-8000-000000000001","job_type":"repair"}'; result uuid; blocked boolean:=false; stamp timestamptz; assignment uuid;
begin
 begin perform public.save_provider_work_order('a0161000-0000-4000-8000-000000000093',request,array['a0161000-0000-4000-8000-000000000005'::uuid],p_request=>'a0161000-0000-4000-8000-000000000013'); exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'invalid provider assignee rejected');
 perform pg_temp.assert_true(not exists(select 1 from public.work_orders where id='a0161000-0000-4000-8000-000000000093'),'invalid assignment cannot leave a new work order');
 perform pg_temp.assert_true((select generated_work_order_id is null and status='new' from public.service_requests where id='a0161000-0000-4000-8000-000000000013'),'failed conversion preserves new request');
 result:=public.save_provider_work_order('a0161000-0000-4000-8000-000000000093',request,array['a0161000-0000-4000-8000-000000000004'::uuid],p_request=>'a0161000-0000-4000-8000-000000000013');
 perform pg_temp.assert_true(public.save_provider_work_order('a0161000-0000-4000-8000-000000000093',request,array['a0161000-0000-4000-8000-000000000004'::uuid],p_request=>'a0161000-0000-4000-8000-000000000013')=result,'lost conversion response returns same job');
 perform pg_temp.assert_true(public.save_provider_work_order(gen_random_uuid(),request,array['a0161000-0000-4000-8000-000000000004'::uuid],p_request=>'a0161000-0000-4000-8000-000000000013')=result,'another conversion cannot duplicate request work');
 select updated_at into stamp from public.work_orders where id=result;
 select id into assignment from public.work_order_assignments where work_order_id=result;
 perform public.save_provider_work_order(gen_random_uuid(),'{"title":"Renamed"}',array['a0161000-0000-4000-8000-000000000004'::uuid],p_work_order=>result,p_expected_updated_at=>stamp);
 perform pg_temp.assert_true((select id=assignment from public.work_order_assignments where work_order_id=result),'unchanged assignment retains its identity');
 blocked:=false;
 begin perform public.save_provider_work_order(gen_random_uuid(),'{"title":"Stale edit"}',array[]::uuid[],p_work_order=>result,p_expected_updated_at=>stamp); exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'stale edit refused');
 select updated_at into stamp from public.work_orders where id=result;
 update public.work_order_assignments set hours_logged=2 where id=assignment;
 blocked:=false;
 begin perform public.save_provider_work_order(gen_random_uuid(),'{"title":"Would lose labour"}',array[]::uuid[],p_work_order=>result,p_expected_updated_at=>stamp); exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'removing recorded labour refused');
 perform pg_temp.assert_true((select title='Renamed' from public.work_orders where id=result),'refused assignment edit preserves work order');
end $$;
rollback;
