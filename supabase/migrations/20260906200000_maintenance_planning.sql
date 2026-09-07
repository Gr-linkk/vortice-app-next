-- NOW-013: existing service intervals drive forward maintenance planning.
-- scheduled_date remains the existing job deadline; a booking is a separate instant.
alter table public.maintenance_job_records
  add column planned_start timestamptz,
  add column estimated_minutes integer,
  add constraint maintenance_booking_duration check (
    (planned_start is null and estimated_minutes is null) or
    (planned_start is not null and estimated_minutes is not null and estimated_minutes between 15 and 10080));
create index maintenance_bookings on public.maintenance_job_records(planned_start)
  where planned_start is not null;

create function public.maintenance_planning(p_asset uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'jobs',coalesce((select jsonb_agg(jsonb_build_object(
    'id',w.id,'asset_id',w.asset_id,'asset_name',a.name,'title',w.title,
    'status',w.status,'priority',j.priority,'due_date',w.scheduled_date,
    'assigned_to',w.assigned_to,'assignee_name',p.full_name,
    'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,
    'revision',j.revision,'service_interval_id',j.service_interval_id,
    'component_name',e.label,'on_hold_reason',w.on_hold_reason,
    'can_manage',public.maintenance_can_manage_asset(a.id) and public.maintenance_can_plan(a.id)
      and public.maintenance_execution_enabled(a.id),
    'conflict',exists(select 1 from public.work_orders other
      join public.maintenance_job_records booking on booking.id=other.id
      where other.id<>w.id and other.status in ('draft','assigned','in_progress','on_hold')
        and (other.asset_id=w.asset_id or other.assigned_to=w.assigned_to)
        and booking.planned_start < j.planned_start + make_interval(mins=>j.estimated_minutes)
        and booking.planned_start + make_interval(mins=>booking.estimated_minutes) > j.planned_start)
    ) order by j.planned_start nulls last,w.scheduled_date nulls last,w.id)
    from public.work_orders w join public.maintenance_job_records j on j.id=w.id
    join public.assets a on a.id=w.asset_id left join public.profiles p on p.id=w.assigned_to
    left join public.asset_engines e on e.id=w.engine_id
    where w.status<>'closed' and public.maintenance_can_read_job(w.id)
      and (p_asset is null or a.id=p_asset)),'[]'),
  'plans',coalesce((select jsonb_agg(to_jsonb(plan)||jsonb_build_object(
    'asset_name',a.name,'component_name',e.label,'current_hours',e.current_hours,
    'can_manage',public.maintenance_can_manage_asset(a.id) and public.maintenance_execution_enabled(a.id),
    'has_open_job',exists(select 1 from public.maintenance_job_records j join public.work_orders w on w.id=j.id
      where j.service_interval_id=plan.id and w.status<>'closed'),
    'open_job_id',(select w.id from public.maintenance_job_records j join public.work_orders w on w.id=j.id
      where j.service_interval_id=plan.id and w.status<>'closed' and public.maintenance_can_read_job(w.id) limit 1)
    ) order by a.name,plan.interval_hours,plan.id)
    from public.asset_service_intervals plan join public.assets a on a.id=plan.asset_id
    left join public.asset_engines e on e.id=plan.engine_id
    where plan.is_active and public.maintenance_can_plan(a.id)
      and (p_asset is null or a.id=p_asset)),'[]'))
 where auth.uid() is not null
$$;

create function public.schedule_maintenance_job(p_job uuid,p_revision integer,p_operation uuid,p_data jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare w public.work_orders; j public.maintenance_job_records; asset uuid; deadline date;
  assigned uuid; starts timestamptz; duration integer; note text; overlap boolean;
begin
  select asset_id into asset from public.work_orders where id=p_job;
  if asset is null or not public.maintenance_can_manage_asset(asset)
    or not public.maintenance_can_plan(asset) or not public.maintenance_execution_enabled(asset)
    then raise exception 'Access denied' using errcode='42501'; end if;
  if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Schedule details are required'; end if;
  if public.maintenance_replayed(p_operation,p_job,'schedule',p_data) then return; end if;
  -- Serialize schedule decisions across assets before taking the established asset/job locks.
  perform pg_advisory_xact_lock(hashtextextended('vortice-next-maintenance-schedule',0));
  perform 1 from public.assets where id=asset for update;
  select * into j from public.maintenance_job_records where id=p_job for update;
  select * into w from public.work_orders where id=p_job for update;
  if j.id is null or not public.maintenance_can_manage_asset(asset)
    or not public.maintenance_can_plan(asset) or not public.maintenance_execution_enabled(asset)
    then raise exception 'Access denied' using errcode='42501'; end if;
  if p_revision is distinct from j.revision then
    raise exception 'This job changed; refresh before scheduling' using errcode='40001'; end if;
  if w.status not in ('draft','assigned','in_progress','on_hold') then
    raise exception 'Only open work that is not awaiting review can be scheduled'; end if;
  assigned:=nullif(p_data->>'assigned_to','')::uuid;
  perform public.maintenance_validate_assignee(asset,assigned);
  if w.assigned_to is distinct from assigned and exists(select 1 from public.maintenance_labour_sessions
    where work_order_id=p_job and stopped_at is null) then
    raise exception 'Pause running labour before changing the assignee'; end if;
  starts:=nullif(p_data->>'planned_start','')::timestamptz;
  duration:=nullif(p_data->>'estimated_minutes','')::integer;
  if (starts is null) <> (duration is null) or duration not between 15 and 10080 then
    raise exception 'Choose a start time and a duration between 15 minutes and seven days'; end if;
  if starts is not null and not isfinite(starts) then raise exception 'Invalid start time'; end if;
  deadline:=nullif(p_data->>'due_date','')::date;
  if deadline is not null and not isfinite(deadline) then raise exception 'Invalid deadline'; end if;
  if coalesce(p_data->>'priority','') not in ('low','normal','high','urgent') then raise exception 'Choose a priority'; end if;
  note:=btrim(coalesce(p_data->>'note',''));
  if length(note)<3 or length(note)>1000 then raise exception 'Explain the scheduling decision (3 to 1000 characters)'; end if;
  select exists(select 1 from public.work_orders other join public.maintenance_job_records booking on booking.id=other.id
    where other.id<>w.id and other.status in ('draft','assigned','in_progress','on_hold')
      and (other.asset_id=asset or other.assigned_to=assigned)
      and booking.planned_start < starts + make_interval(mins=>duration)
      and booking.planned_start + make_interval(mins=>booking.estimated_minutes) > starts) into overlap;
  if overlap and coalesce((p_data->>'allow_overlap')::boolean,false)=false then
    raise exception 'This booking overlaps another job for the assignee or asset. Change the time or explicitly allow the overlap.';
  end if;
  update public.maintenance_job_records set planned_start=starts,estimated_minutes=duration,
    priority=p_data->>'priority',revision=revision+1 where id=p_job;
  update public.work_orders set assigned_to=assigned,scheduled_date=deadline,
    status=case when status in ('draft','assigned') then case when assigned is null then 'draft' else 'assigned' end else status end,
    updated_at=now() where id=p_job;
  perform public.maintenance_record_operation(p_operation,p_job,'schedule',p_data);
  -- A separate immutable event preserves the previous booking without changing replay payloads.
  perform public.maintenance_record_operation(gen_random_uuid(),p_job,'schedule_previous',jsonb_build_object(
    'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,'assigned_to',w.assigned_to,
    'due_date',w.scheduled_date,'priority',j.priority,'note',note,'schedule_operation',p_operation));
end $$;
revoke all on function public.maintenance_planning(uuid),public.schedule_maintenance_job(uuid,integer,uuid,jsonb) from public,anon;
grant execute on function public.maintenance_planning(uuid),public.schedule_maintenance_job(uuid,integer,uuid,jsonb) to authenticated;

-- Extended existing job payload.
create or replace function public.maintenance_jobs(p_job uuid default null,p_asset uuid default null)
returns setof jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',w.id,'asset_id',w.asset_id,'asset_name',a.name,
 'title',w.title,'description',w.description,'status',w.status,'assigned_to',w.assigned_to,
 'assignee_name',p.full_name,'due_date',w.scheduled_date,'engine_id',w.engine_id,
 'component_name',e.label,'job_type',w.job_type,'hours_at_end',w.hours_at_end,
 'on_hold_reason',w.on_hold_reason,'blocked_category',j.blocked_category,'created_at',w.created_at,'completed_at',w.completed_at,
 'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,
 'revision',j.revision,'priority',j.priority,'service_interval_id',j.service_interval_id,
 'parent_job_id',j.parent_job_id,'hourly_cost',j.hourly_cost,'review_note',j.review_note,
 'approved_at',j.approved_at,'service_applied_at',j.service_applied_at,
 'checklist_snapshot',j.checklist_snapshot,'checklist_answers',j.checklist_answers,'evidence_paths',j.evidence_paths,
 'can_manage',public.maintenance_can_manage_asset(w.asset_id),
 'can_schedule',public.maintenance_can_plan(w.asset_id) and public.maintenance_execution_enabled(w.asset_id),
 'can_work',public.maintenance_can_work_job(w.id),
 'report',(select jsonb_build_object('diagnosis',s.cause,'repair',s.correction,'notes',s.comments) from public.service_reports s where s.work_order_id=w.id),
 'parts',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'description',r.description,'part_number',r.part_number,
 'quantity',r.quantity,'unit_cost',r.unit_cost)) from public.parts r where r.work_order_id=w.id),'[]'),
 'labour',coalesce((select jsonb_agg(to_jsonb(l) order by l.started_at,l.id) from public.maintenance_labour_sessions l where l.work_order_id=w.id),'[]'),
 'events',coalesce((select jsonb_agg(jsonb_build_object('kind',o.kind,'actor_name',actor.full_name,
 'created_at',o.created_at,'note',o.payload->>'note') order by o.created_at,o.id)
 from public.maintenance_operations o left join public.profiles actor on actor.id=o.actor_id where o.object_id=w.id),'[]'))
 from public.work_orders w join public.maintenance_job_records j on j.id=w.id
 join public.assets a on a.id=w.asset_id left join public.profiles p on p.id=w.assigned_to
 left join public.asset_engines e on e.id=w.engine_id
 where public.maintenance_can_read_job(w.id) and (p_job is null or w.id=p_job) and (p_asset is null or w.asset_id=p_asset)
 order by (w.status='closed'),case j.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end,w.scheduled_date nulls last,w.created_at desc
$$;
