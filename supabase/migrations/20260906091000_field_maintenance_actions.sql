-- Preserve device-recorded labour time and existing authorization/revision checks.
create function public.apply_maintenance_field_action(p_job uuid,p_revision integer,
 p_operation uuid,p_action text,p_data jsonb,p_recorded_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare payload jsonb; sessions uuid[]; started timestamptz; effective_time timestamptz;
begin
 if p_action not in ('start','pause','block','save_report','submit','add_part','remove_part')
  then raise exception 'Unsupported field action'; end if;
 if not public.maintenance_can_work_job(p_job) then raise exception 'Access denied'; end if;
 payload:=p_data || jsonb_build_object('_recorded_at',p_recorded_at);
 perform 1 from public.maintenance_job_records where id=p_job for update;
 if public.maintenance_replayed(p_operation,p_job,p_action,payload) then return; end if;
 if p_recorded_at is null or p_recorded_at>clock_timestamp()+interval '5 minutes'
  or p_recorded_at<clock_timestamp()-interval '30 days'
  then raise exception 'Device time is invalid or this change is older than 30 days'; end if;
 -- Tolerate a slightly fast device clock without creating future-running
 -- sessions that violate the existing stop-time constraint on a quick pause.
 effective_time:=least(p_recorded_at,clock_timestamp());
 if p_action='pause' then
  select array_agg(id),max(started_at) into sessions,started from public.maintenance_labour_sessions
   where work_order_id=p_job and stopped_at is null
    and (id=nullif(p_data->>'session_id','')::uuid or nullif(p_data->>'session_id','') is null)
    and (actor_id=auth.uid() or public.maintenance_can_manage_asset((select asset_id from public.work_orders where id=p_job)));
  if effective_time<started then raise exception 'Pause time precedes start time'; end if;
 end if;
 perform public.change_maintenance_job(p_job,p_revision,p_operation,p_action,payload);
 if p_action='start' then
  if exists(select 1 from public.maintenance_labour_sessions where actor_id=auth.uid()
    and id<>p_operation and stopped_at>effective_time)
    then raise exception 'Recorded labour overlaps an existing session'; end if;
  update public.maintenance_labour_sessions set started_at=effective_time where id=p_operation;
  update public.work_orders set started_at=least(started_at,effective_time) where id=p_job;
 elsif p_action='pause' then
  update public.maintenance_labour_sessions set stopped_at=effective_time where id=any(sessions);
 end if;
end $$;
revoke all on function public.apply_maintenance_field_action(uuid,integer,uuid,text,jsonb,timestamptz) from public,anon;
grant execute on function public.apply_maintenance_field_action(uuid,integer,uuid,text,jsonb,timestamptz) to authenticated;
