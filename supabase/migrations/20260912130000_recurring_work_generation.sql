-- NEXT-002.04: one unscheduled, unassigned work order per due cycle.
-- Calendar work is generated 30 days ahead by default; meters generate when
-- their target is reached. Approval, never generation, advances the target.
alter table public.asset_service_intervals add column generation_lead_days integer not null default 30 check(generation_lead_days between 0 and 365);
alter table public.asset_inspections
 add column checklist_template_id uuid references public.checklist_templates(id),
 add column procedure_notes text not null default '',
 add column interval_months integer not null default 12 check(interval_months between 1 and 120),
 add column generation_lead_days integer not null default 30 check(generation_lead_days between 0 and 365),
 add column first_due_date date not null default current_date,
 add column is_active boolean not null default true;
alter table public.work_orders add column generation_kind text not null default 'manual' check(generation_kind in ('manual','recurring'));
alter table public.work_orders alter column created_by drop not null;
alter table public.work_orders add constraint work_author_kind check(created_by is not null or generation_kind='recurring');
create table public.recurring_work_cycles (
 id uuid primary key default gen_random_uuid(),
 asset_id uuid not null references public.assets(id),
 source_kind text not null check(source_kind in ('plan','inspection')),
 source_id uuid not null,
 cycle_key text not null,
 due_date date,
 due_meter numeric,
 meter_unit text not null check(meter_unit in ('hours','km','mi')),
 work_order_id uuid not null unique references public.work_orders(id) deferrable initially deferred,
 actor_id uuid references public.profiles(id),
 created_at timestamptz not null default now(),
 approved_at timestamptz,
 unique(source_kind,source_id,cycle_key)
);
create table public.recurring_generation_runs (
 id uuid primary key default gen_random_uuid(),
 started_at timestamptz not null default now(),
 completed_at timestamptz,
 created_count integer not null default 0,
 failures jsonb not null default '[]'
);
alter table public.recurring_work_cycles enable row level security;
alter table public.recurring_generation_runs enable row level security;
revoke all on public.recurring_work_cycles,public.recurring_generation_runs from public,anon,authenticated;
grant select on public.recurring_work_cycles to authenticated;
grant all on public.recurring_work_cycles,public.recurring_generation_runs to service_role;
create policy cycle_reader on public.recurring_work_cycles for select to authenticated using(public.maintenance_can_read_job(work_order_id));
create function public.guard_work_generation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if new.generation_kind is distinct from old.generation_kind or new.created_by is distinct from old.created_by then raise exception 'Work authorship cannot be rewritten'; end if;
 elsif new.generation_kind='recurring' then
  if new.created_by is not null or not new.managed_maintenance or not exists(select 1 from public.recurring_work_cycles c where c.work_order_id=new.id and c.asset_id=new.asset_id)
   then raise exception 'Recurring work requires a server-created cycle'; end if;
 elsif new.created_by is null then raise exception 'A work creator is required';
 end if;
 return new;
end $$;
revoke all on function public.guard_work_generation() from public,anon,authenticated;
create trigger guard_work_generation before insert or update on public.work_orders for each row execute function public.guard_work_generation();

-- Pure equipment/template scope checks for the scheduled service principal.
-- This helper does not grant access to a caller or return procedure content.
create function public.recurring_template_matches(p_template uuid,p_asset uuid,p_engine uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select p_template is null or exists(select 1 from public.checklist_templates t join public.assets a on a.id=p_asset
  where t.id=p_template and t.is_active and t.checklist_type='pm'
   and (t.client_id is null or t.client_id=a.client_id)
   and (t.asset_type_id is null or t.asset_type_id=a.asset_type_id)
   and (t.scope_asset_id is null or t.scope_asset_id=a.id)
   and (t.scope_engine_id is null or t.scope_engine_id=p_engine))
$$;
revoke all on function public.recurring_template_matches(uuid,uuid,uuid) from public,anon,authenticated;
create function public.recurring_current_template(p_template uuid) returns uuid language sql stable security definer set search_path='' as $$
 select coalesce(p.published_template_id,t.id) from public.checklist_templates t left join public.checklist_procedures p on p.id=t.procedure_id where t.id=p_template
$$;
revoke all on function public.recurring_current_template(uuid) from public,anon,authenticated;

-- The private creator below is generated from the current checked creation
-- implementation. Only the scheduler's ledger-backed path may use automation.
-- Generated private creator.
create or replace function public.create_recurring_job(p_request uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.assets; plan public.asset_service_intervals; assigned uuid;
 work_type text; materials text;
 parent public.work_orders; snapshot jsonb:='[]'; template uuid; component uuid;
begin
 select * into a from public.assets where id=(p_data->>'asset_id')::uuid;
 if a.id is null or not exists(select 1 from public.recurring_work_cycles where work_order_id=p_request and asset_id=a.id) then raise exception 'Recurring work requires a server-created cycle'; end if;
 if exists(select 1 from public.work_orders where id=p_request and generation_kind='recurring') then return p_request; end if;
 perform 1 from public.assets where id=a.id for update;
 if length(btrim(coalesce(p_data->>'title','')))<3 or length(p_data->>'title')>200
   then raise exception 'Title must contain 3 to 200 characters'; end if;
 work_type:=coalesce(nullif(p_data->>'job_type',''),case when nullif(p_data->>'service_interval_id','') is null then 'repair' else 'preventative' end);
 if work_type not in ('preventative','repair','inspection','general') then raise exception 'Choose a valid work type'; end if;
 if nullif(p_data->>'service_interval_id','') is not null and work_type<>'preventative'
   then raise exception 'A linked service plan requires preventive maintenance'; end if;
 materials:=btrim(coalesce(p_data->>'expected_materials',''));
 if length(materials)>4000 then raise exception 'Expected materials must be at most 4000 characters'; end if;
 if length(coalesce(p_data->>'description',''))>8000 then raise exception 'Instructions must be at most 8000 characters'; end if;
 assigned:=null;
 component:=coalesce(nullif(p_data->>'engine_id','')::uuid,a.primary_meter_engine_id);
 if component is not null and not exists(select 1 from public.asset_engines where id=component and asset_id=a.id)
  then raise exception 'Component belongs to another asset'; end if;
 if nullif(p_data->>'service_interval_id','') is not null then
  if not exists(select 1 from public.assets asset join public.client_capabilities c on c.client_id=asset.client_id where asset.id=a.id and c.capability_key='maintenance_planning' and c.enabled) then raise exception 'Maintenance planning is disabled'; end if;
  select * into plan from public.asset_service_intervals where id=(p_data->>'service_interval_id')::uuid for update;
  if plan.id is null or plan.asset_id<>a.id or not plan.is_active or plan.engine_id is null
   then raise exception 'Select an active component maintenance plan'; end if;
  if exists(select 1 from public.maintenance_job_records j join public.work_orders w on w.id=j.id
    where (j.service_interval_id=plan.id or plan.id=any(j.covered_plan_ids) or j.service_interval_id=any(plan.covers_plan_ids) or j.covered_plan_ids && plan.covers_plan_ids) and w.status<>'closed') then raise exception 'This plan already has an open job'; end if;
  component:=plan.engine_id; template:=plan.checklist_template_id;
 else template:=nullif(p_data->>'checklist_template_id','')::uuid;
 end if;
 if plan.id is not null then template:=public.recurring_current_template(template); end if;
 if template is not null then
  if not public.recurring_template_matches(template,a.id,component) then raise exception 'Invalid checklist template'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'description_en',description_en,
    'description_es',description_es,'requires_photo',requires_photo,'category',category,'definition',definition,'template_id',template_id) order by sort_order,id),'[]')
    into snapshot from public.checklist_items where template_id=template;
 end if;
 if cardinality(plan.covers_plan_ids)>0 then
  perform 1 from public.asset_service_intervals where id=any(plan.covers_plan_ids) order by id for update;
  if exists(select 1 from public.asset_service_intervals where id=any(plan.covers_plan_ids)
    and (not is_active or asset_id<>a.id or engine_id is distinct from component)) then raise exception 'Invalid covered plan'; end if;
  select coalesce(jsonb_agg(item order by item->>'id'),'[]') into snapshot from (
   select distinct item from (
    select value item from jsonb_array_elements(snapshot)
    union all
    select jsonb_build_object('id',i.id,'description_en',i.description_en,'description_es',i.description_es,
     'requires_photo',i.requires_photo,'category',i.category,'definition',i.definition,'template_id',i.template_id)
    from public.asset_service_intervals cp join public.checklist_items i
     on i.template_id=public.recurring_current_template(cp.checklist_template_id)
    where cp.id=any(plan.covers_plan_ids)
   ) all_items
  ) unique_items;
 end if;
 if nullif(p_data->>'parent_job_id','') is not null then
  select * into parent from public.work_orders where id=(p_data->>'parent_job_id')::uuid;
  if parent.asset_id is distinct from a.id or not public.maintenance_can_read_job(parent.id)
    then raise exception 'Invalid follow-up job'; end if;
 end if;
 insert into public.work_orders(id,asset_id,client_id,created_by,assigned_to,title,description,
   engine_id,checklist_template_id,job_type,status,scheduled_date,billable_rate,wage_rate,managed_maintenance,generation_kind)
 values(p_request,a.id,a.client_id,null,assigned,btrim(p_data->>'title'),coalesce(nullif(p_data->>'description',''),plan.notes),
   component,template,work_type,
   case when assigned is null then 'draft' else 'assigned' end,nullif(p_data->>'due_date','')::date,0,0,true,'recurring');
 insert into public.maintenance_job_records(id,priority,service_interval_id,parent_job_id,checklist_snapshot,hourly_cost,expected_materials,covered_plan_ids)
 values(p_request,coalesce(p_data->>'priority','normal'),plan.id,parent.id,snapshot,coalesce((p_data->>'hourly_cost')::numeric,0),materials,coalesce(plan.covers_plan_ids,'{}'));
 update public.work_orders set hours_at_start=(select current_hours from public.asset_engines where id=component) where id=p_request;
 insert into public.asset_history_entries(asset_id,category,kind,source_type,source_id,source_key,title,actor_name,occurred_at,job_id,managed) values(a.id,'work','recurring_work_created','work_order',p_request,'recurring:'||p_request,p_data->>'title','Automatic schedule',now(),p_request,true);
 return p_request;
end $$;
revoke all on function public.create_recurring_job(uuid,jsonb) from public,anon,authenticated;

alter table public.maintenance_job_records
 add column inspection_id uuid references public.asset_inspections(id),
 add column inspection_snapshot jsonb,
 add column inspection_result jsonb not null default '{}',
 add column inspection_applied_at timestamptz;
alter table public.inspection_submissions
 add column work_order_id uuid references public.work_orders(id),
 add column evidence_bucket text not null default 'inspection-evidence' check(evidence_bucket in ('inspection-evidence','maintenance-evidence'));

create function public.generate_recurring_for_asset(p_asset uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare a public.assets; p public.asset_service_intervals; i public.asset_inspections; certificate public.inspection_submissions;
 cycle text; job uuid; due date; created integer:=0; template uuid; meter text;
begin
 -- All generators serialize with manual creation, edits, returns and approval.
 select * into a from public.assets where id=p_asset for update;
 if not found or not exists(select 1 from public.client_capabilities c where c.client_id=a.client_id and c.capability_key='pm_checklists' and c.enabled)
  or not exists(select 1 from public.client_capabilities c where c.client_id=a.client_id and c.capability_key='maintenance_planning' and c.enabled) then return 0; end if;
 for p in select plan.* from public.asset_service_intervals plan join public.asset_engines e on e.id=plan.engine_id
  where plan.asset_id=p_asset and plan.is_active and
   ((plan.next_due_date is not null and plan.next_due_date<=current_date+plan.generation_lead_days)
    or (plan.next_due_hours is not null and e.current_hours>=plan.next_due_hours))
  order by cardinality(plan.covers_plan_ids) desc,plan.id for update of plan loop
  if exists(select 1 from public.maintenance_job_records j join public.work_orders w on w.id=j.id where w.status<>'closed'
   and (j.service_interval_id=p.id or p.id=any(j.covered_plan_ids) or j.service_interval_id=any(p.covers_plan_ids) or j.covered_plan_ids&&p.covers_plan_ids)) then continue; end if;
  cycle:=coalesce(p.next_due_hours::text,'-')||'/'||coalesce(p.next_due_date::text,'-');
  if exists(select 1 from public.recurring_work_cycles where source_kind='plan' and source_id=p.id and cycle_key=cycle) then continue; end if;
  template:=public.recurring_current_template(p.checklist_template_id);
  if (p.checklist_template_id is not null and template is null) or not public.recurring_template_matches(template,a.id,p.engine_id)
   then raise exception 'Recurring plan has an unavailable checklist'; end if;
  if exists(select 1 from public.asset_service_intervals cp where cp.id=any(p.covers_plan_ids) and
   (not cp.is_active or cp.asset_id<>a.id or cp.engine_id is distinct from p.engine_id
    or (cp.checklist_template_id is not null and public.recurring_current_template(cp.checklist_template_id) is null)
    or not public.recurring_template_matches(public.recurring_current_template(cp.checklist_template_id),a.id,p.engine_id)))
    then raise exception 'Recurring coverage has an unavailable checklist'; end if;
  select meter_unit into meter from public.asset_engines where id=p.engine_id;
  job:=gen_random_uuid();
  insert into public.recurring_work_cycles(asset_id,source_kind,source_id,cycle_key,due_date,due_meter,meter_unit,work_order_id,actor_id)
   values(a.id,'plan',p.id,cycle,p.next_due_date,p.next_due_hours,meter,job,null);
  perform public.create_recurring_job(job,jsonb_build_object('asset_id',a.id,'service_interval_id',p.id,
   'job_type','preventative','title',coalesce(nullif(p.interval_label,''),'Scheduled maintenance'),'description',p.notes,
   'due_date',p.next_due_date));
  created:=created+1;
 end loop;
 for i in select * from public.asset_inspections where asset_id=a.id and is_active order by id for update loop
  if exists(select 1 from public.maintenance_job_records j join public.work_orders w on w.id=j.id where j.inspection_id=i.id and w.status<>'closed')
   or exists(select 1 from public.inspection_submissions where inspection_id=i.id and status='pending') then continue; end if;
  select * into certificate from public.inspection_submissions where inspection_id=i.id and status='approved' order by reviewed_at desc,id desc limit 1;
  due:=coalesce(certificate.expires_on,i.first_due_date);
  if due>current_date+i.generation_lead_days then continue; end if;
  cycle:=coalesce(certificate.id::text,'initial')||'/'||due::text;
  if exists(select 1 from public.recurring_work_cycles where source_kind='inspection' and source_id=i.id and cycle_key=cycle) then continue; end if;
  template:=public.recurring_current_template(i.checklist_template_id);
  if (i.checklist_template_id is not null and template is null) or not public.recurring_template_matches(template,a.id,coalesce(i.component_id,a.primary_meter_engine_id)) then raise exception 'Inspection checklist is unavailable'; end if;
  job:=gen_random_uuid();
  select coalesce(e.meter_unit,a.meter_unit) into meter from (select 1) singleton left join public.asset_engines e on e.id=coalesce(i.component_id,a.primary_meter_engine_id);
  insert into public.recurring_work_cycles(asset_id,source_kind,source_id,cycle_key,due_date,meter_unit,work_order_id,actor_id)
   values(a.id,'inspection',i.id,cycle,due,meter,job,null);
  perform public.create_recurring_job(job,jsonb_build_object('asset_id',a.id,'engine_id',i.component_id,'job_type','inspection',
   'title',i.title,'description',coalesce(nullif(i.procedure_notes,''),certificate.procedure_notes),
   'checklist_template_id',template,'due_date',due));
  update public.maintenance_job_records set inspection_id=i.id,inspection_snapshot=to_jsonb(i)||jsonb_build_object('previous_certificate_id',certificate.id,'due_date',due) where id=job;
  insert into public.work_order_sources values(job,'inspection',i.id,to_jsonb(i)||jsonb_build_object('previous_certificate_id',certificate.id,'due_date',due),now());
  created:=created+1;
 end loop;
 return created;
end $$;
revoke all on function public.generate_recurring_for_asset(uuid) from public,anon,authenticated;

create function public.generate_recurring_work(p_asset uuid default null) returns integer
language plpgsql security definer set search_path='' as $$
declare asset uuid; created integer:=0;
begin
 if auth.uid() is null then raise exception 'Access denied'; end if;
 if p_asset is not null and not public.maintenance_can_plan(p_asset) then raise exception 'Access denied'; end if;
 for asset in select id from public.assets where (p_asset is null or id=p_asset) and public.maintenance_can_plan(id) order by id loop
  created:=created+public.generate_recurring_for_asset(asset);
 end loop;
 return created;
end $$;
revoke all on function public.generate_recurring_work(uuid) from public,anon;
grant execute on function public.generate_recurring_work(uuid) to authenticated;

create function public.run_recurring_generation() returns integer
language plpgsql security definer set search_path='' as $$
declare asset uuid; created integer:=0; run uuid:=gen_random_uuid();
begin
 insert into public.recurring_generation_runs(id) values(run);
 for asset in select a.id from public.assets a where exists(select 1 from public.client_capabilities c where c.client_id=a.client_id and c.capability_key='maintenance_planning' and c.enabled) order by a.id loop
  begin
   created:=created+public.generate_recurring_for_asset(asset);
  exception when others then
   update public.recurring_generation_runs set failures=failures||jsonb_build_array(jsonb_build_object('asset_id',asset,'message',sqlerrm)) where id=run;
  end;
 end loop;
 update public.recurring_generation_runs set completed_at=now(),created_count=created where id=run;
 return created;
end $$;
revoke all on function public.run_recurring_generation() from public,anon,authenticated;
grant execute on function public.run_recurring_generation() to service_role;

-- Inspection evidence travels with its work report. The current approved
-- certificate remains current until that same work order is approved.
alter function public.change_maintenance_job(uuid,integer,uuid,text,jsonb) rename to change_maintenance_job_before_inspection;
revoke all on function public.change_maintenance_job_before_inspection(uuid,integer,uuid,text,jsonb) from public,anon,authenticated;
create function public.change_maintenance_job(p_job uuid,p_revision integer,p_operation uuid,p_action text,p_data jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare j public.maintenance_job_records; w public.work_orders; i public.asset_inspections; result jsonb; submission public.inspection_submissions; inspected date; expires date; evidence text; actor text;
begin
 if not public.maintenance_can_work_job(p_job) then raise exception 'Access denied'; end if;
 -- Replay must exit the entire wrapper before touching historical versions.
 if public.maintenance_replayed(p_operation,p_job,p_action,p_data) then return; end if;
 perform 1 from public.assets where id=(select asset_id from public.work_orders where id=p_job) for update;
 select * into j from public.maintenance_job_records where id=p_job for update;
 if j.inspection_id is not null then
  select * into i from public.asset_inspections where id=j.inspection_id for update;
  result:=coalesce(p_data->'inspection',j.inspection_result);
  if j.inspection_applied_at is not null and p_data ? 'inspection' and result is distinct from j.inspection_result then raise exception 'Approved inspection details cannot change'; end if;
  if p_action in ('save_report','submit') and j.inspection_applied_at is null then
   if jsonb_typeof(result)<>'object' then raise exception 'Inspection details are required'; end if;
   if p_action='submit' then
    inspected:=nullif(result->>'inspected_on','')::date; expires:=nullif(result->>'expires_on','')::date;
    if inspected is null or expires is null or not isfinite(inspected) or not isfinite(expires) or inspected>current_date or inspected<date '1900-01-01' or expires<=inspected or expires>date '2200-01-01' then raise exception 'Check inspection and expiry dates'; end if;
    if length(btrim(coalesce(result->>'procedure_notes','')))<3 or length(btrim(coalesce(result->>'result_notes','')))<3 then raise exception 'Inspection procedure and result are required'; end if;
    evidence:=result->>'evidence_path';
    if evidence is null or not coalesce(p_data->'evidence_paths','[]') ? evidence or split_part(evidence,'/',1)<>p_job::text
     or not exists(select 1 from storage.objects where bucket_id='maintenance-evidence' and name=evidence) then raise exception 'Attach inspection certificate evidence to this report'; end if;
   end if;
  end if;
 end if;
 perform public.change_maintenance_job_before_inspection(p_job,p_revision,p_operation,p_action,p_data);
 if j.inspection_id is null then
  if p_action='approve' then update public.recurring_work_cycles set approved_at=coalesce(approved_at,now()) where work_order_id=p_job; end if;
  return;
 end if;
 select full_name into actor from public.profiles where id=auth.uid();
 if p_action in ('save_report','submit') and j.inspection_applied_at is null then
  update public.maintenance_job_records set inspection_result=result where id=p_job;
  if p_action='submit' then
   insert into public.inspection_submissions(id,inspection_id,work_order_id,inspected_on,expires_on,procedure_notes,result_notes,evidence_path,evidence_bucket,submitted_by,submitted_name)
    values(p_operation,i.id,p_job,inspected,expires,btrim(result->>'procedure_notes'),btrim(result->>'result_notes'),evidence,'maintenance-evidence',auth.uid(),coalesce(actor,''));
   update public.asset_inspections set revision=revision+1 where id=i.id;
  end if;
 elsif p_action in ('return','approve') and j.inspection_applied_at is null then
  select * into submission from public.inspection_submissions where inspection_id=i.id and work_order_id=p_job and status='pending' for update;
  if not found then raise exception 'Pending inspection report is missing'; end if;
  update public.inspection_submissions set status=case when p_action='approve' then 'approved' else 'returned' end,
   reviewed_by=auth.uid(),reviewed_name=coalesce(actor,''),reviewed_at=now(),review_note=coalesce(nullif(p_data->>'note',''),'Approved with work order') where id=submission.id;
  update public.asset_inspections set revision=revision+1 where id=i.id;
  if p_action='approve' then
   update public.maintenance_job_records set inspection_applied_at=now() where id=p_job;
   update public.recurring_work_cycles set approved_at=coalesce(approved_at,now()) where work_order_id=p_job;
  end if;
  insert into public.asset_history_entries(asset_id,category,kind,source_type,source_id,source_key,title,body,actor_name,occurred_at)
   values(i.asset_id,'inspection','renewal_'||p_action,'asset_inspection',i.id,'inspection-work:'||p_operation,i.title,coalesce(p_data->>'note','Approved with work order'),actor,now());
 end if;
end $$;
revoke all on function public.change_maintenance_job(uuid,integer,uuid,text,jsonb) from public,anon;
grant execute on function public.change_maintenance_job(uuid,integer,uuid,text,jsonb) to authenticated;

alter function public.maintenance_jobs(uuid,uuid) rename to maintenance_jobs_before_inspection;
revoke all on function public.maintenance_jobs_before_inspection(uuid,uuid) from public,anon,authenticated;
create function public.maintenance_jobs(p_job uuid default null,p_asset uuid default null) returns setof jsonb
language sql stable security definer set search_path='' as $$
 select data||jsonb_build_object('inspection_id',j.inspection_id,'inspection_snapshot',j.inspection_snapshot,'inspection_result',j.inspection_result,'inspection_applied_at',j.inspection_applied_at,
  'generation_kind',w.generation_kind,'cycle',(select to_jsonb(c) from public.recurring_work_cycles c where work_order_id=j.id))
 from public.maintenance_jobs_before_inspection(p_job,p_asset) data
 join public.maintenance_job_records j on j.id=(data->>'id')::uuid join public.work_orders w on w.id=j.id
$$;
revoke all on function public.maintenance_jobs(uuid,uuid) from public,anon;
grant execute on function public.maintenance_jobs(uuid,uuid) to authenticated;

alter function public.inspection_register(uuid) rename to inspection_register_before_work;
revoke all on function public.inspection_register_before_work(uuid) from public,anon,authenticated;
create function public.inspection_register(p_asset uuid default null) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(data||jsonb_build_object('open_work_order_id',(select w.id from public.work_orders w join public.maintenance_job_records j on j.id=w.id where j.inspection_id=(data->>'id')::uuid and w.status<>'closed' order by w.created_at desc,w.id limit 1))),'[]')
 from jsonb_array_elements(public.inspection_register_before_work(p_asset)) data
$$;
revoke all on function public.inspection_register(uuid) from public,anon;
grant execute on function public.inspection_register(uuid) to authenticated;

create policy approved_inspection_work_evidence_read on storage.objects for select to authenticated using(bucket_id='maintenance-evidence' and exists(
 select 1 from public.inspection_submissions s join public.asset_inspections i on i.id=s.inspection_id
 where s.evidence_bucket='maintenance-evidence' and s.evidence_path=name and s.status='approved' and public.maintenance_can_view_asset(i.asset_id)));

-- Supabase provides pg_cron. Local PostgreSQL contract runners may omit it;
-- the foreground generator still uses this exact same idempotent routine.
do $$ begin
 if exists(select 1 from pg_available_extensions where name='pg_cron') then
  create extension if not exists pg_cron with schema pg_catalog;
  perform cron.schedule('vortice-recurring-work','0 * * * *','select public.run_recurring_generation();');
 end if;
end $$;


-- Keep setup's existing authorization/replay and membership-adaptation points.
do $$ declare definition text; marker text:=' perform public.maintenance_record_operation(p_operation,p_id,''setup_''||p_kind,p_data);'; begin
 select pg_get_functiondef('public.save_maintenance_setup(uuid,text,uuid,integer,jsonb)'::regprocedure) into definition;
 if strpos(definition,marker)=0 then raise exception 'Maintenance setup extension point changed'; end if;
 definition:=replace(definition,marker,$patch$
 if p_kind='plan' and p_data ? 'generation_lead_days' then
  if (p_data->>'generation_lead_days')::integer not between 0 and 365 then raise exception 'Generate work 0 to 365 days ahead'; end if;
  update public.asset_service_intervals set generation_lead_days=(p_data->>'generation_lead_days')::integer where id=p_id;
 end if;
$patch$||marker);
 execute definition;
end $$;

do $$ declare definition text; marker text:=' perform public.maintenance_record_operation(p_operation,p_asset,''inspection_create'',p_data);'; begin
 select pg_get_functiondef('public.create_asset_inspection(uuid,uuid,jsonb)'::regprocedure) into definition;
 if strpos(definition,marker)=0 then raise exception 'Inspection setup extension point changed'; end if;
 definition:=replace(definition,marker,$patch$
 if coalesce((p_data->>'interval_months')::integer,12) not between 1 and 120 or coalesce((p_data->>'generation_lead_days')::integer,30) not between 0 and 365 then raise exception 'Check recurrence months and generation lead'; end if;
 if nullif(p_data->>'first_due_date','') is not null and (not isfinite((p_data->>'first_due_date')::date) or (p_data->>'first_due_date')::date<date '1900-01-01' or (p_data->>'first_due_date')::date>date '2200-01-01') then raise exception 'Check the first inspection due date'; end if;
 if length(coalesce(p_data->>'procedure_notes',''))>4000 then raise exception 'Procedure must be at most 4000 characters'; end if;
 if nullif(p_data->>'checklist_template_id','') is not null and not public.checklist_template_usable((p_data->>'checklist_template_id')::uuid,p_asset,component,'pm') then raise exception 'Invalid checklist template'; end if;
 update public.asset_inspections set checklist_template_id=nullif(p_data->>'checklist_template_id','')::uuid,
  procedure_notes=coalesce(p_data->>'procedure_notes',''),interval_months=coalesce((p_data->>'interval_months')::integer,12),
  generation_lead_days=coalesce((p_data->>'generation_lead_days')::integer,30),first_due_date=coalesce(nullif(p_data->>'first_due_date','')::date,current_date) where id=p_operation;
$patch$||marker);
 execute definition;
end $$;

create function public.configure_inspection_schedule(p_inspection uuid,p_revision integer,p_operation uuid,p_data jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare i public.asset_inspections; template uuid; first_due date;
begin
 select * into i from public.asset_inspections where id=p_inspection;
 if not found or not public.maintenance_can_manage_asset(i.asset_id) then raise exception 'Access denied'; end if;
 if public.maintenance_replayed(p_operation,p_inspection,'inspection_schedule',p_data) then return; end if;
 perform 1 from public.assets where id=i.asset_id for update;
 select * into i from public.asset_inspections where id=p_inspection for update;
 if i.revision is distinct from p_revision then raise exception 'Inspection changed; refresh' using errcode='40001'; end if;
 if exists(select 1 from public.maintenance_job_records j join public.work_orders w on w.id=j.id where j.inspection_id=i.id and w.status<>'closed') then raise exception 'Finish the current inspection work before changing its schedule'; end if;
 template:=public.checklist_current_template(nullif(p_data->>'checklist_template_id','')::uuid);
 if nullif(p_data->>'checklist_template_id','') is not null and template is null then raise exception 'Invalid checklist template'; end if;
 if template is not null and not public.checklist_template_usable(template,i.asset_id,i.component_id,'pm') then raise exception 'Invalid checklist template'; end if;
 first_due:=coalesce(nullif(p_data->>'first_due_date','')::date,i.first_due_date);
 if not isfinite(first_due) or first_due<date '1900-01-01' or first_due>date '2200-01-01'
  or coalesce((p_data->>'interval_months')::integer,i.interval_months) not between 1 and 120
  or coalesce((p_data->>'generation_lead_days')::integer,i.generation_lead_days) not between 0 and 365 then raise exception 'Check inspection dates and recurrence'; end if;
 if length(btrim(coalesce(p_data->>'note','')))<3 then raise exception 'Explain the inspection schedule change'; end if;
 update public.asset_inspections set checklist_template_id=template,procedure_notes=coalesce(p_data->>'procedure_notes',procedure_notes),first_due_date=first_due,
  interval_months=coalesce((p_data->>'interval_months')::integer,interval_months),generation_lead_days=coalesce((p_data->>'generation_lead_days')::integer,generation_lead_days),
  is_active=coalesce((p_data->>'is_active')::boolean,is_active),revision=revision+1 where id=i.id;
 perform public.maintenance_record_operation(p_operation,p_inspection,'inspection_schedule',p_data);
end $$;
revoke all on function public.configure_inspection_schedule(uuid,integer,uuid,jsonb) from public,anon;
grant execute on function public.configure_inspection_schedule(uuid,integer,uuid,jsonb) to authenticated;


alter function public.maintenance_work_hub(uuid) rename to maintenance_work_hub_before_execution;
revoke all on function public.maintenance_work_hub_before_execution(uuid) from public,anon,authenticated;
create function public.maintenance_work_hub(p_asset uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 result:=public.maintenance_work_hub_before_execution(p_asset);
 return jsonb_set(result,'{jobs}',coalesce((select jsonb_agg(data||jsonb_build_object(
   'meter_unit',w.meter_unit,'current_meter',e.current_hours,'due_meter',c.due_meter,'cycle_approved_at',c.approved_at,
   'returned_at',j.returned_at,'generation_kind',w.generation_kind,'inspection_id',j.inspection_id))
  from jsonb_array_elements(result->'jobs') data
  join public.work_orders w on w.id=(data->>'id')::uuid
  left join public.asset_engines e on e.id=w.engine_id
  left join public.maintenance_job_records j on j.id=w.id
  left join public.recurring_work_cycles c on c.work_order_id=w.id),'[]'));
end $$;
revoke all on function public.maintenance_work_hub(uuid) from public,anon;
grant execute on function public.maintenance_work_hub(uuid) to authenticated;
