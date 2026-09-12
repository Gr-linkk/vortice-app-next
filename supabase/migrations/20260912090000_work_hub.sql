-- NEXT-002.02: the common work hub includes scoped history.
-- Existing maintenance_planning remains a forward-only compatibility reader.
create function public.maintenance_work_hub(p_asset uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'jobs',coalesce((select jsonb_agg(jsonb_build_object(
    'id',w.id,'asset_id',w.asset_id,'asset_name',a.name,'title',w.title,
    'job_type',w.job_type,'status',w.status,'priority',j.priority,'due_date',w.scheduled_date,
    'assigned_to',w.assigned_to,'assignee_name',p.full_name,
    'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,
    'revision',j.revision,'service_interval_id',j.service_interval_id,
    'component_name',e.label,'engine_id',w.engine_id,'on_hold_reason',w.on_hold_reason,
    'blocked_category',j.blocked_category,
    'can_manage',public.maintenance_can_manage_asset(a.id) and public.maintenance_can_plan(a.id)
      and public.maintenance_execution_enabled(a.id),
    'conflict',w.status in ('draft','assigned','in_progress','on_hold') and exists(select 1 from public.work_orders other
      join public.maintenance_job_records booking on booking.id=other.id
      where other.id<>w.id and other.status in ('draft','assigned','in_progress','on_hold')
        and (other.asset_id=w.asset_id or other.assigned_to=w.assigned_to)
        and booking.planned_start < j.planned_start + make_interval(mins=>j.estimated_minutes)
        and booking.planned_start + make_interval(mins=>booking.estimated_minutes) > j.planned_start)
    ) order by j.planned_start nulls last,w.scheduled_date nulls last,w.id)
    from public.work_orders w join public.maintenance_job_records j on j.id=w.id
    join public.assets a on a.id=w.asset_id left join public.profiles p on p.id=w.assigned_to
    left join public.asset_engines e on e.id=w.engine_id
    where public.maintenance_can_read_job(w.id)
      and (p_asset is null or a.id=p_asset)),'[]'),
  'plans',coalesce((select jsonb_agg(to_jsonb(plan)||jsonb_build_object(
    'asset_name',a.name,'component_name',e.label,'current_hours',e.current_hours,
    'can_manage',public.maintenance_can_manage_asset(a.id) and public.maintenance_execution_enabled(a.id),
    'has_open_job',exists(select 1 from public.maintenance_job_records j join public.work_orders w on w.id=j.id
      where (j.service_interval_id=plan.id or plan.id=any(j.covered_plan_ids)) and w.status<>'closed'),
    'open_job_id',(select w.id from public.maintenance_job_records j join public.work_orders w on w.id=j.id
      where (j.service_interval_id=plan.id or plan.id=any(j.covered_plan_ids)) and w.status<>'closed' and public.maintenance_can_read_job(w.id) limit 1)
    ) order by a.name,plan.interval_hours,plan.id)
    from public.asset_service_intervals plan join public.assets a on a.id=plan.asset_id
    left join public.asset_engines e on e.id=plan.engine_id
    where plan.is_active and public.maintenance_can_plan(a.id)
      and (p_asset is null or a.id=p_asset)),'[]'))
 where auth.uid() is not null
$$;
revoke all on function public.maintenance_work_hub(uuid) from public,anon;
grant execute on function public.maintenance_work_hub(uuid) to authenticated;
