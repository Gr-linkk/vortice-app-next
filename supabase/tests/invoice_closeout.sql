begin;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'FAIL: %',label; end if;
end $$;

insert into auth.users(id,email,raw_user_meta_data) values
 ('a0160000-0000-4000-8000-000000000001','now016-owner@example.invalid','{}'),
 ('a0160000-0000-4000-8000-000000000002','now016-client@example.invalid','{}'),
 ('a0160000-0000-4000-8000-000000000003','now016-other@example.invalid','{}'),
 ('a0160000-0000-4000-8000-000000000004','now016-tech@example.invalid','{}'),
 ('a0160000-0000-4000-8000-000000000005','now016-mechanic@example.invalid','{}'),
 ('a0160000-0000-4000-8000-000000000006','now016-operator@example.invalid','{}');
update public.profiles set role=case right(id::text,1) when '1' then 'owner'
 when '4' then 'employee' when '5' then 'client_mechanic' when '6' then 'operator' else 'client' end
 where id::text like 'a0160000-%';
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0160000-0000-4000-8000-000000000008','NOW016 company','a0160000-0000-4000-8000-000000000002');
update public.profiles set org_id='a0160000-0000-4000-8000-000000000008'
 where id in ('a0160000-0000-4000-8000-000000000002','a0160000-0000-4000-8000-000000000005','a0160000-0000-4000-8000-000000000006');
insert into public.asset_types(id,category,name) values
 ('a0160000-0000-4000-8000-000000000010','test','Test machine');
insert into public.assets(id,client_id,asset_type_id,name) values
 ('a0160000-0000-4000-8000-000000000011','a0160000-0000-4000-8000-000000000002',
  'a0160000-0000-4000-8000-000000000010','NOW016 test machine');
insert into public.work_orders(id,title,asset_id,client_id,created_by,status,job_type) values
 ('a0160000-0000-4000-8000-000000000020','NOW016 provider inspection',
  'a0160000-0000-4000-8000-000000000011','a0160000-0000-4000-8000-000000000002',
  'a0160000-0000-4000-8000-000000000001','closed','repair');
update public.work_orders set labour_hours=2,billable_rate=60 where id='a0160000-0000-4000-8000-000000000020';
insert into public.parts(work_order_id,description,quantity,unit_cost,markup_pct) values
 ('a0160000-0000-4000-8000-000000000020','Original filter',2,10,15);
set local role authenticated;
select set_config('request.jwt.claim.sub','a0160000-0000-4000-8000-000000000001',true);
select public.generate_provider_invoice('a0160000-0000-4000-8000-000000000020',17.5);
select public.generate_provider_invoice('a0160000-0000-4000-8000-000000000020',18);
select pg_temp.assert_true((select count(*)=1 from public.invoices where work_order_id='a0160000-0000-4000-8000-000000000020'),'generation retry has one effect');
select pg_temp.assert_true((select status='invoiced' from public.work_orders where id='a0160000-0000-4000-8000-000000000020'),'generation advances work atomically');
select pg_temp.assert_true((select total_usd=172.84 and parts_total_usd=23 and exchange_rate=17.5 from public.invoices where work_order_id='a0160000-0000-4000-8000-000000000020'),'server calculation and retry preserve amounts');
-- Drafts are equally private for the customer owner and company administrator.
select set_config('request.jwt.claim.sub','a0160000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from public.invoices),'customer cannot see drafts');
reset role;
update public.profiles set role='client_admin' where id='a0160000-0000-4000-8000-000000000005';
set local role authenticated;
select set_config('request.jwt.claim.sub','a0160000-0000-4000-8000-000000000005',true);
select pg_temp.assert_true((select count(*)=0 from public.invoices),'administrator cannot see drafts');
select set_config('request.jwt.claim.sub','a0160000-0000-4000-8000-000000000001',true);
do $$ declare i uuid; blocked boolean:=false; begin
 select id into i from public.invoices where work_order_id='a0160000-0000-4000-8000-000000000020';
 begin perform public.change_invoice_status(i,'paid'); exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'draft cannot be marked paid');
 perform public.change_invoice_status(i,'sent');
 perform public.change_invoice_status(i,'sent');
 blocked:=false;
 begin update public.invoices set total_usd=1 where id=i; exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'direct issued amount mutation blocked');
 blocked:=false;
 begin update public.invoices set export_snapshot='{}' where id=i; exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'direct snapshot mutation blocked');
 blocked:=false;
 begin delete from public.invoices where id=i; exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'issued deletion blocked');
end $$;
update public.parts set description='Changed filter',unit_cost=90 where work_order_id='a0160000-0000-4000-8000-000000000020';
select pg_temp.assert_true((select export_snapshot->'parts'->0->>'description'='Original filter' and parts_total_usd=23 from public.invoices where work_order_id='a0160000-0000-4000-8000-000000000020'),'issued part lines are frozen');
select set_config('request.jwt.claim.sub','a0160000-0000-4000-8000-000000000005',true);
select pg_temp.assert_true((select count(*)=1 from public.invoices),'administrator reads issued invoice');
select set_config('request.jwt.claim.sub','a0160000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.invoices),'other company cannot read invoice');
select set_config('request.jwt.claim.sub','a0160000-0000-4000-8000-000000000001',true);
do $$ declare i uuid; blocked boolean:=false; begin
 select id into i from public.invoices where work_order_id='a0160000-0000-4000-8000-000000000020';
 begin perform public.change_invoice_status(i,'void'); exception when others then blocked:=true; end;
 perform pg_temp.assert_true(blocked,'void requires reason');
 perform public.change_invoice_status(i,'void','Correct wrong part');
 perform public.change_invoice_status(i,'void','Correct wrong part');
end $$;
select public.generate_provider_invoice('a0160000-0000-4000-8000-000000000020',17.5);
select pg_temp.assert_true((select count(*)=2 from public.invoices where work_order_id='a0160000-0000-4000-8000-000000000020'),'correction preserves original');
select set_config('request.jwt.claim.sub','a0160000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select count(*)=1 and bool_and(status='void') from public.invoices),'customer sees void history but not correction draft');
rollback;
