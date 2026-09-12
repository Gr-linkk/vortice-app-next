begin;
insert into auth.users(id,email,raw_user_meta_data)
values('a0162000-0000-4000-8000-000000000001','land-catalog@example.invalid','{}');
create temporary table expected_land(id uuid primary key,name text,category text);
insert into expected_land values
 ('00000000-0000-0000-0000-000000000023','Compact / Mini Excavator','Heavy Equipment'),
 ('00000000-0000-0000-0000-000000000024','Compact Track Loader','Heavy Equipment'),
 ('00000000-0000-0000-0000-000000000025','Agricultural Tractor','Agriculture & Grounds'),
 ('00000000-0000-0000-0000-000000000026','Zero-Turn Mower','Agriculture & Grounds'),
 ('00000000-0000-0000-0000-000000000027','Boom Lift','Lifting Equipment'),
 ('00000000-0000-0000-0000-000000000028','Scissor Lift','Lifting Equipment');
grant select on expected_land to authenticated,anon;
do $$ begin
 -- Initial IDs 001-00d are provisioned by seed data, outside local migrations.
 if (select count(*) from public.asset_types where id between '00000000-0000-0000-0000-00000000000e'::uuid and '00000000-0000-0000-0000-000000000022'::uuid)<>21
 then raise exception 'Prior migrated catalog IDs must remain intact'; end if;
 if exists(select 1 from expected_land e left join public.asset_types t using(id) where t.id is null or t.name<>e.name or t.category<>e.category or t.tracking_unit<>'engine_hours')
 then raise exception 'Land catalog must contain six correctly named hours-based types'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0162000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"a0162000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
 if (select count(*) from public.asset_types t join expected_land e using(id))<>6
 then raise exception 'Signed-in users must be able to choose all six new types'; end if;
end $$;
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claim.role','anon',true);
select set_config('request.jwt.claims','{"role":"anon"}',true);
do $$ begin
 if exists(select 1 from public.asset_types t join expected_land e using(id))
 then raise exception 'Anonymous catalog access must remain denied'; end if;
end $$;
reset role;
rollback;
