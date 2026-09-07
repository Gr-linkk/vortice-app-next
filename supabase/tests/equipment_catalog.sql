begin;
create temporary table expected_equipment (id uuid primary key, name text, category text);
insert into expected_equipment values
 ('00000000-0000-0000-0000-00000000000e', 'Pump', 'Industrial Equipment'),
 ('00000000-0000-0000-0000-00000000000f', 'Marine Crane', 'Lifting Equipment'),
 ('00000000-0000-0000-0000-000000000010', 'Diesel Engine', 'Power Generation'),
 ('00000000-0000-0000-0000-000000000011', 'RIB / Inflatable Boat', 'Marine Vessels'),
 ('00000000-0000-0000-0000-000000000012', 'Aluminum Skiff', 'Marine Vessels'),
 ('00000000-0000-0000-0000-000000000013', 'Cabin Cruiser', 'Marine Vessels'),
 ('00000000-0000-0000-0000-000000000014', 'Commercial Trawler', 'Commercial Fishing'),
 ('00000000-0000-0000-0000-000000000015', 'Purse Seiner', 'Commercial Fishing'),
 ('00000000-0000-0000-0000-000000000016', 'Tugboat', 'Marine Vessels'),
 ('00000000-0000-0000-0000-000000000017', 'Backhoe Loader', 'Heavy Equipment'),
 ('00000000-0000-0000-0000-000000000018', 'Skid Steer', 'Heavy Equipment'),
 ('00000000-0000-0000-0000-000000000019', 'Dump Truck', 'Heavy Equipment'),
 ('00000000-0000-0000-0000-00000000001a', 'Motor Grader', 'Heavy Equipment'),
 ('00000000-0000-0000-0000-00000000001b', 'Forklift', 'Heavy Equipment'),
 ('00000000-0000-0000-0000-00000000001c', 'Telehandler', 'Heavy Equipment'),
 ('00000000-0000-0000-0000-00000000001d', 'Road Roller', 'Heavy Equipment'),
 ('00000000-0000-0000-0000-00000000001e', 'Mobile Crane', 'Lifting Equipment'),
 ('00000000-0000-0000-0000-00000000001f', 'Tower Crane', 'Lifting Equipment'),
 ('00000000-0000-0000-0000-000000000020', 'Davit', 'Lifting Equipment');
do $$ begin
 if exists (select 1 from expected_equipment e left join public.asset_types t on t.id=e.id
  where t.id is null or t.name<>e.name or t.category<>e.category or t.tracking_unit<>'engine_hours')
 then raise exception 'Expanded standard equipment catalog is incomplete or incorrect'; end if;
end $$;
grant select on expected_equipment to authenticated, anon;
set local role authenticated;
select set_config('request.jwt.claim.sub','01800000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"01800000-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $$ begin
 if (select count(*) from public.asset_types t join expected_equipment e on e.id=t.id)<>19
 then raise exception 'Authenticated users must be able to select every new equipment type'; end if;
end $$;
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claim.role','anon',true);
select set_config('request.jwt.claims','{"role":"anon"}',true);
do $$ begin
 if exists (select 1 from public.asset_types t join expected_equipment e on e.id=t.id)
 then raise exception 'Anonymous catalog access must remain denied'; end if;
end $$;
reset role;
rollback;
