begin;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'FAIL: %',label; end if;
end $$;

insert into auth.users(id,email,raw_user_meta_data) values
 ('a0162000-0000-4000-8000-000000000001','now016-owner@example.invalid','{}'),
 ('a0162000-0000-4000-8000-000000000002','now016-client@example.invalid','{}'),
 ('a0162000-0000-4000-8000-000000000003','now016-other@example.invalid','{}'),
 ('a0162000-0000-4000-8000-000000000004','now016-tech@example.invalid','{}'),
 ('a0162000-0000-4000-8000-000000000005','now016-mechanic@example.invalid','{}'),
 ('a0162000-0000-4000-8000-000000000006','now016-operator@example.invalid','{}');
update public.profiles set role=case right(id::text,1) when '1' then 'owner'
 when '4' then 'employee' when '5' then 'client_mechanic' when '6' then 'operator' else 'client' end
 where id::text like 'a0162000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0162000-0000-4000-8000-000000000008','NOW016 company','a0162000-0000-4000-8000-000000000002');
update public.profiles set org_id='a0162000-0000-4000-8000-000000000008'
 where id in ('a0162000-0000-4000-8000-000000000002','a0162000-0000-4000-8000-000000000005','a0162000-0000-4000-8000-000000000006');
insert into public.asset_types(id,category,name) values
 ('a0162000-0000-4000-8000-000000000010','test','Test machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0162000-0000-4000-8000-000000000011','a0162000-0000-4000-8000-000000000002',
  'a0162000-0000-4000-8000-000000000010','NOW016 test machine');
insert into public.work_orders(id,title,asset_id,client_id,created_by,status,job_type) values
 ('a0162000-0000-4000-8000-000000000020','NOW016 provider inspection',
  'a0162000-0000-4000-8000-000000000011','a0162000-0000-4000-8000-000000000002',
  'a0162000-0000-4000-8000-000000000001','closed','repair');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0162000-0000-4000-8000-000000000002',true);
select public.begin_request_submission('a0162000-0000-4000-8000-000000000091','a0162000-0000-4000-8000-000000000090',
 '{"client_id":"a0162000-0000-4000-8000-000000000002","asset_id":"a0162000-0000-4000-8000-000000000011","title":"Breakdown","request_type":"breakdown","description":"Saved problem","contact_phone_or_whatsapp":"123"}');
select public.begin_request_submission('a0162000-0000-4000-8000-000000000091','a0162000-0000-4000-8000-000000000090',
 '{"client_id":"a0162000-0000-4000-8000-000000000002","asset_id":"a0162000-0000-4000-8000-000000000011","title":"Breakdown","request_type":"breakdown","description":"Saved problem","contact_phone_or_whatsapp":"123"}');
select pg_temp.assert_true((select count(*)=1 and bool_and(evidence_pending) from public.service_requests where id='a0162000-0000-4000-8000-000000000090'),'request retry preserves one pending original');
do $$ declare blocked boolean:=false; begin
 begin perform public.finish_evidence_submission('a0162000-0000-4000-8000-000000000091','request','a0162000-0000-4000-8000-000000000090',array['a0162000-0000-4000-8000-000000000090/a0162000-0000-4000-8000-000000000091/photo.jpg']); exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'missing request photo cannot complete');
end $$;
insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'service-request-photos','a0162000-0000-4000-8000-000000000090/a0162000-0000-4000-8000-000000000091/photo.jpg');
select public.finish_evidence_submission('a0162000-0000-4000-8000-000000000091','request','a0162000-0000-4000-8000-000000000090',array['a0162000-0000-4000-8000-000000000090/a0162000-0000-4000-8000-000000000091/photo.jpg']);
select public.finish_evidence_submission('a0162000-0000-4000-8000-000000000091','request','a0162000-0000-4000-8000-000000000090',array['a0162000-0000-4000-8000-000000000090/a0162000-0000-4000-8000-000000000091/photo.jpg']);
select pg_temp.assert_true((select not evidence_pending and cardinality(photo_urls)=1 and description='Saved problem' from public.service_requests where id='a0162000-0000-4000-8000-000000000090'),'request text and evidence complete together');
do $$ declare blocked boolean:=false; begin
 begin perform public.finish_evidence_submission('a0162000-0000-4000-8000-000000000091','request','a0162000-0000-4000-8000-000000000090',array[]::text[]); exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'retry cannot erase accepted evidence');
end $$;
select set_config('request.jwt.claim.sub','a0162000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(not public.request_photo_access('a0162000-0000-4000-8000-000000000090/a0162000-0000-4000-8000-000000000091/photo.jpg'),'other company cannot read nested evidence');
select set_config('request.jwt.claim.sub','a0162000-0000-4000-8000-000000000001',true);
update public.work_orders set status='in_progress' where id='a0162000-0000-4000-8000-000000000020';
select public.begin_report_submission('a0162000-0000-4000-8000-000000000093','a0162000-0000-4000-8000-000000000092',
 '{"work_order_id":"a0162000-0000-4000-8000-000000000020","complaint":"Leak","cause":"Seal","correction":"Replaced","comments":"Pressure tested"}');
select public.begin_report_submission('a0162000-0000-4000-8000-000000000093','a0162000-0000-4000-8000-000000000092',
 '{"work_order_id":"a0162000-0000-4000-8000-000000000020","complaint":"Leak","cause":"Seal","correction":"Replaced","comments":"Pressure tested"}');
do $$ declare blocked boolean:=false; begin
 begin update public.work_orders set status='closed' where id='a0162000-0000-4000-8000-000000000020'; exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'cannot close work with pending evidence');
end $$;
insert into storage.objects(id,bucket_id,name) values
 (gen_random_uuid(),'service-report-photos','a0162000-0000-4000-8000-000000000092/a0162000-0000-4000-8000-000000000093/photo.jpg'),
 (gen_random_uuid(),'signatures','a0162000-0000-4000-8000-000000000020_a0162000-0000-4000-8000-000000000093_signature.png');
select public.finish_evidence_submission('a0162000-0000-4000-8000-000000000093','report','a0162000-0000-4000-8000-000000000092',
 array['a0162000-0000-4000-8000-000000000092/a0162000-0000-4000-8000-000000000093/photo.jpg'],
 'a0162000-0000-4000-8000-000000000020_a0162000-0000-4000-8000-000000000093_signature.png');
select public.finish_evidence_submission('a0162000-0000-4000-8000-000000000093','report','a0162000-0000-4000-8000-000000000092',
 array['a0162000-0000-4000-8000-000000000092/a0162000-0000-4000-8000-000000000093/photo.jpg'],
 'a0162000-0000-4000-8000-000000000020_a0162000-0000-4000-8000-000000000093_signature.png');
select pg_temp.assert_true((select count(*)=1 from public.service_report_photos where service_report_id='a0162000-0000-4000-8000-000000000092'),'photo row retry is exactly once');
select pg_temp.assert_true((select not evidence_pending and tech_signature_url is not null and signed_at is not null from public.service_reports where id='a0162000-0000-4000-8000-000000000092'),'report signature and photos complete');
update public.work_orders set status='closed' where id='a0162000-0000-4000-8000-000000000020';
rollback;
