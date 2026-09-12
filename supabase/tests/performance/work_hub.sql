-- Disposable database only. The runner bootstraps the complete migration chain.
-- This population reproduces the per-asset authorization multiplier missed by
-- small correctness fixtures: 340 assets, 1,500 jobs and 340 maintenance plans (a 10x growth case).
begin;
set local plan_cache_mode = force_generic_plan;
set local statement_timeout = '30s';
create function pg_temp.fixture_id(n integer) returns uuid language sql immutable as $$
 select ('b0035000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
$$;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select pg_temp.fixture_id(n),'hub-perf-'||n||'@example.invalid',now(),
 case when n=4 then '{"onboarding_v2":true}'::jsonb else '{}'::jsonb end
from generate_series(1,4) n;
update public.profiles set role=case id when pg_temp.fixture_id(1) then 'owner'
 when pg_temp.fixture_id(2) then 'client' else 'client_mechanic' end
where id in (pg_temp.fixture_id(1),pg_temp.fixture_id(2),pg_temp.fixture_id(3));
insert into public.client_orgs(id,name,owner_profile_id)
values(pg_temp.fixture_id(10),'Populated performance fleet',pg_temp.fixture_id(2));
update public.profiles set org_id=pg_temp.fixture_id(10)
where id in (pg_temp.fixture_id(2),pg_temp.fixture_id(3));
insert into public.client_capabilities(client_id,capability_key,enabled)
values(pg_temp.fixture_id(2),'pm_checklists',true),(pg_temp.fixture_id(2),'maintenance_planning',true);
set local role authenticated;
select set_config('request.jwt.claim.sub',pg_temp.fixture_id(4)::text,true);
select public.create_company_workspace('Separate modern performance company','Modern owner');
reset role;
insert into public.asset_types(id,category,name) values(pg_temp.fixture_id(20),'test','Performance machine');
insert into public.assets(id,client_id,asset_type_id,name)
select pg_temp.fixture_id(1000+n),pg_temp.fixture_id(2),pg_temp.fixture_id(20),'Performance machine '||n
from generate_series(1,340) n;
insert into public.asset_engines(id,asset_id,label,current_hours)
select pg_temp.fixture_id(2000+n),pg_temp.fixture_id(1000+n),'Main meter',240
from generate_series(1,340) n;
insert into public.asset_service_intervals(id,asset_id,engine_id,interval_hours,interval_label,last_service_hours,next_due_hours)
select pg_temp.fixture_id(3000+n),pg_temp.fixture_id(1000+n),pg_temp.fixture_id(2000+n),250,'250-hour service',0,250
from generate_series(1,340) n;
insert into public.work_orders(id,asset_id,engine_id,client_id,created_by,assigned_to,job_type,status,title,managed_maintenance,scheduled_date)
select pg_temp.fixture_id(4000+n),pg_temp.fixture_id(1001+(n-1)%340),pg_temp.fixture_id(2001+(n-1)%340),
 pg_temp.fixture_id(2),pg_temp.fixture_id(1),pg_temp.fixture_id(case when n%2=0 then 3 else 1 end),
 'preventative','assigned','Performance service '||n,true,current_date+(n%30)
from generate_series(1,1500) n;
insert into public.maintenance_job_records(id,service_interval_id,planned_start,estimated_minutes)
select pg_temp.fixture_id(4000+n),pg_temp.fixture_id(3001+(n-1)%340),
 now()+make_interval(days=>n%30,hours=>n%8),60 from generate_series(1,1500) n;
analyze public.assets;
analyze public.work_orders;
analyze public.maintenance_job_records;
analyze public.asset_service_intervals;
create temp table hub_timings(actor integer,sample integer,elapsed_ms numeric);
grant select,insert on hub_timings to authenticated;

create function pg_temp.measure_hub(actor integer, expected integer, expected_plans integer, label text)
returns void language plpgsql as $$
declare started timestamptz; elapsed numeric; data jsonb; repetition integer; asset uuid;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.fixture_id(actor)::text,true);
 for repetition in 1..3 loop
  started:=clock_timestamp();
  data:=public.maintenance_work_hub(null);
  elapsed:=extract(epoch from clock_timestamp()-started)*1000;
  insert into pg_temp.hub_timings values(actor,repetition,elapsed);
  if jsonb_array_length(data->'jobs')<>expected or jsonb_array_length(data->'plans')<>expected_plans then
   raise exception 'Scope changed for %: jobs %, plans %',label,jsonb_array_length(data->'jobs'),jsonb_array_length(data->'plans');
  end if;
  raise notice 'PERF % sample %: % ms, % jobs, % plans',label,repetition,round(elapsed,1),expected,expected_plans;
  if elapsed>3000 then raise exception 'Work hub exceeded 3000 ms budget for %: % ms',label,elapsed; end if;
 end loop;
 -- A real parameter, including a non-null asset, must retain the same boundary.
 asset:=pg_temp.fixture_id(1001);
 data:=public.maintenance_work_hub(asset);
 if exists(select 1 from jsonb_array_elements(data->'jobs') j where (j->>'asset_id')::uuid<>asset) then
  raise exception 'Asset filter broadened for %',label;
 end if;
 if actor=4 and jsonb_array_length(data->'jobs')<>0 then raise exception 'Cross-company leak'; end if;
end $$;
set local role authenticated;
select pg_temp.measure_hub(1,1500,340,'provider owner');
select pg_temp.measure_hub(2,1500,340,'fleet owner');
select pg_temp.measure_hub(3,750,0,'assigned mechanic');
select pg_temp.measure_hub(4,0,0,'separate modern owner');
-- A company with no access must not pay for authorizing every other company's
-- work. Compare medians on the same machine; the fixed allowance absorbs small
-- scheduler noise while the absolute budget above still limits all readers.
do $$ declare populated numeric; isolated numeric; budget numeric; begin
 select percentile_cont(0.5) within group(order by elapsed_ms) into populated
 from pg_temp.hub_timings where actor=2;
 select percentile_cont(0.5) within group(order by elapsed_ms) into isolated
 from pg_temp.hub_timings where actor=4;
 budget:=populated*0.4+100;
 raise notice 'PERF isolation overhead: % ms; budget % ms',round(isolated,1),round(budget,1);
 if isolated>budget then raise exception 'Unrelated-company hub repeats hidden-work processing: % ms exceeds % ms',isolated,budget; end if;
end $$;
rollback;
