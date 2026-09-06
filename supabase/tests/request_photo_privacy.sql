begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
select pg_temp.assert_true((select not public from storage.buckets where id='service-request-photos'),
 'request evidence bucket must be private');
insert into auth.users(id,email,raw_user_meta_data)
select ('a0110000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'request-photo-'||n||'@example.invalid','{}'::jsonb from generate_series(1,3) n;
update public.profiles set role=case right(id::text,1) when '3' then 'owner' else 'client' end
 where id::text like 'a0110000-%';
insert into public.service_requests(id,client_id,title,description,contact_phone_or_whatsapp)
values('a0110000-0000-4000-8000-000000000010','a0110000-0000-4000-8000-000000000001','Test','Test photo privacy','Synthetic');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0110000-0000-4000-8000-000000000001',true);
insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'service-request-photos','a0110000-0000-4000-8000-000000000010/test.png');
select pg_temp.assert_true((select count(*)=1 from storage.objects where bucket_id='service-request-photos' and name='a0110000-0000-4000-8000-000000000010/test.png'),'own request image readable');
select set_config('request.jwt.claim.sub','a0110000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='service-request-photos'),'another company denied');
do $$ begin
 begin
  insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'service-request-photos','a0110000-0000-4000-8000-000000000010/foreign.png');
  raise exception 'Foreign upload incorrectly allowed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','a0110000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=1 from storage.objects where bucket_id='service-request-photos' and name='a0110000-0000-4000-8000-000000000010/test.png'),'provider can view request evidence');
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='service-request-photos'),'anonymous image rows denied');
rollback;
