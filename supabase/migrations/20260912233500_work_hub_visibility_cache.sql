-- Resolve asset visibility and shared permission flags once per read. A separate
-- materialized candidate barrier prevents nested job authorization from running
-- for jobs on assets the actor cannot see. Existing can_read_job/can_plan helpers
-- both require can_view_asset, so this prefilter preserves their exact scope.
-- The open-job lookup reuses visible IDs; has_open_job remains existence-only.
-- Preserve existing grants, including the private base hub, via CREATE OR REPLACE.
create or replace function public.maintenance_planning(p_asset uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 with visible_assets as materialized (
   select visible_asset.id from public.assets visible_asset
   where public.maintenance_can_view_asset(visible_asset.id)
 ), asset_permissions as materialized (
   select visible_asset.id,
     public.maintenance_can_manage_asset(visible_asset.id) as can_manage,
     public.maintenance_can_plan(visible_asset.id) as can_plan,
     public.maintenance_execution_enabled(visible_asset.id) as execution_enabled
   from visible_assets visible_asset
 ), visible_job_candidates as materialized (
   select candidate_work.id
   from public.work_orders candidate_work
   join public.maintenance_job_records candidate_job on candidate_job.id=candidate_work.id
   join visible_assets visible_asset on visible_asset.id=candidate_work.asset_id
 ), visible_job_ids as materialized (
   select candidate.id from visible_job_candidates candidate
   where public.maintenance_can_read_job(candidate.id)
 )
 select jsonb_build_object(
  'jobs',coalesce((select jsonb_agg(jsonb_build_object(
    'id',w.id,'asset_id',w.asset_id,'asset_name',a.name,'title',w.title,
    'job_type',w.job_type,'status',w.status,'priority',j.priority,'due_date',w.scheduled_date,
    'assigned_to',w.assigned_to,'assignee_name',p.full_name,
    'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,
    'revision',j.revision,'service_interval_id',j.service_interval_id,
    'component_name',e.label,'meter_unit',e.meter_unit,'on_hold_reason',w.on_hold_reason,
    'can_manage',permissions.can_manage and permissions.can_plan
      and permissions.execution_enabled,
    'conflict',exists(select 1 from public.work_orders other
      join public.maintenance_job_records booking on booking.id=other.id
      where other.id<>w.id and other.status in ('draft','assigned','in_progress','on_hold')
        and (other.asset_id=w.asset_id or other.assigned_to=w.assigned_to)
        and booking.planned_start < j.planned_start + make_interval(mins=>j.estimated_minutes)
        and booking.planned_start + make_interval(mins=>booking.estimated_minutes) > j.planned_start)
    ) order by j.planned_start nulls last,w.scheduled_date nulls last,w.id)
    from public.work_orders w join public.maintenance_job_records j on j.id=w.id
    join public.assets a on a.id=w.asset_id join asset_permissions permissions on permissions.id=a.id left join public.profiles p on p.id=w.assigned_to
    left join public.asset_engines e on e.id=w.engine_id
    where w.status<>'closed' and w.id in (select id from visible_job_ids)
      and (p_asset is null or a.id=p_asset)),'[]'),
  'plans',coalesce((select jsonb_agg(to_jsonb(plan)||jsonb_build_object(
    'asset_name',a.name,'component_name',e.label,'meter_unit',e.meter_unit,'current_hours',e.current_hours,
    'can_manage',permissions.can_manage and permissions.execution_enabled,
    'has_open_job',exists(select 1 from public.maintenance_job_records j join public.work_orders w on w.id=j.id
      where (j.service_interval_id=plan.id or plan.id=any(j.covered_plan_ids)) and w.status<>'closed'),
    'open_job_id',(select w.id from public.maintenance_job_records j join public.work_orders w on w.id=j.id
      where (j.service_interval_id=plan.id or plan.id=any(j.covered_plan_ids)) and w.status<>'closed' and w.id in (select id from visible_job_ids) limit 1)
    ) order by a.name,plan.interval_hours,plan.id)
    from public.asset_service_intervals plan join public.assets a on a.id=plan.asset_id join asset_permissions permissions on permissions.id=a.id
    left join public.asset_engines e on e.id=plan.engine_id
    where plan.is_active and permissions.can_plan
      and (p_asset is null or a.id=p_asset)),'[]'))
 where auth.uid() is not null
$$;

create or replace function public.maintenance_work_hub_before_execution(p_asset uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 with visible_assets as materialized (
   select visible_asset.id from public.assets visible_asset
   where public.maintenance_can_view_asset(visible_asset.id)
 ), asset_permissions as materialized (
   select visible_asset.id,
     public.maintenance_can_manage_asset(visible_asset.id) as can_manage,
     public.maintenance_can_plan(visible_asset.id) as can_plan,
     public.maintenance_execution_enabled(visible_asset.id) as execution_enabled
   from visible_assets visible_asset
 ), visible_job_candidates as materialized (
   select candidate_work.id
   from public.work_orders candidate_work
   join public.maintenance_job_records candidate_job on candidate_job.id=candidate_work.id
   join visible_assets visible_asset on visible_asset.id=candidate_work.asset_id
 ), visible_job_ids as materialized (
   select candidate.id from visible_job_candidates candidate
   where public.maintenance_can_read_job(candidate.id)
 )
 select jsonb_build_object(
  'jobs',coalesce((select jsonb_agg(jsonb_build_object(
    'id',w.id,'asset_id',w.asset_id,'asset_name',a.name,'title',w.title,
    'job_type',w.job_type,'status',w.status,'priority',j.priority,'due_date',w.scheduled_date,
    'assigned_to',w.assigned_to,'assignee_name',p.full_name,
    'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,
    'revision',j.revision,'service_interval_id',j.service_interval_id,
    'component_name',e.label,'meter_unit',w.meter_unit,'engine_id',w.engine_id,'on_hold_reason',w.on_hold_reason,
    'blocked_category',j.blocked_category,
    'can_manage',permissions.can_manage and permissions.can_plan
      and permissions.execution_enabled,
    'conflict',w.status in ('draft','assigned','in_progress','on_hold') and exists(select 1 from public.work_orders other
      join public.maintenance_job_records booking on booking.id=other.id
      where other.id<>w.id and other.status in ('draft','assigned','in_progress','on_hold')
        and (other.asset_id=w.asset_id or other.assigned_to=w.assigned_to)
        and booking.planned_start < j.planned_start + make_interval(mins=>j.estimated_minutes)
        and booking.planned_start + make_interval(mins=>booking.estimated_minutes) > j.planned_start)
    ) order by j.planned_start nulls last,w.scheduled_date nulls last,w.id)
    from public.work_orders w join public.maintenance_job_records j on j.id=w.id
    join public.assets a on a.id=w.asset_id join asset_permissions permissions on permissions.id=a.id left join public.profiles p on p.id=w.assigned_to
    left join public.asset_engines e on e.id=w.engine_id
    where w.id in (select id from visible_job_ids)
      and (p_asset is null or a.id=p_asset)),'[]'),
  'plans',coalesce((select jsonb_agg(to_jsonb(plan)||jsonb_build_object(
    'asset_name',a.name,'component_name',e.label,'meter_unit',e.meter_unit,'current_hours',e.current_hours,
    'can_manage',permissions.can_manage and permissions.execution_enabled,
    'has_open_job',exists(select 1 from public.maintenance_job_records j join public.work_orders w on w.id=j.id
      where (j.service_interval_id=plan.id or plan.id=any(j.covered_plan_ids)) and w.status<>'closed'),
    'open_job_id',(select w.id from public.maintenance_job_records j join public.work_orders w on w.id=j.id
      where (j.service_interval_id=plan.id or plan.id=any(j.covered_plan_ids)) and w.status<>'closed' and w.id in (select id from visible_job_ids) limit 1)
    ) order by a.name,plan.interval_hours,plan.id)
    from public.asset_service_intervals plan join public.assets a on a.id=plan.asset_id join asset_permissions permissions on permissions.id=a.id
    left join public.asset_engines e on e.id=plan.engine_id
    where plan.is_active and permissions.can_plan
      and (p_asset is null or a.id=p_asset)),'[]'))
 where auth.uid() is not null
$$;
