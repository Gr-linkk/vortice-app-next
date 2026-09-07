-- NOW-012. One managed work order owns repair execution; fault resolution stays explicit.
create or replace function public.maintenance_faults(p_asset_id uuid default null,p_fault_id uuid default null)
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(f) || jsonb_build_object('asset_name',a.name,
    'assigned_to',case when w.managed_maintenance then w.assigned_to else f.assigned_to end,
    'assignee_name',assignee.full_name,'reporter_name',reporter.full_name,'work_order_status',w.status,
    'work_order_managed',coalesce(w.managed_maintenance,false),
    'can_open_work_order',case when w.managed_maintenance then public.maintenance_can_read_job(w.id)
      else exists(select 1 from public.profiles where id=auth.uid() and role in ('owner','employee')) end,
    'can_plan_repair',public.maintenance_can_manage_asset(a.id) and public.maintenance_execution_enabled(a.id))
  from public.maintenance_requests f join public.assets a on a.id=f.asset_id
  left join public.work_orders w on w.id=f.converted_to_work_order_id
  left join public.profiles assignee on assignee.id=case when w.managed_maintenance then w.assigned_to else f.assigned_to end
  left join public.profiles reporter on reporter.id=f.flagged_by
  where public.maintenance_can_view_asset(f.asset_id)
    and (p_asset_id is null or f.asset_id=p_asset_id) and (p_fault_id is null or f.id=p_fault_id)
  order by (f.status not in ('resolved','dismissed')) desc,(f.severity='urgent') desc,f.created_at desc,f.id;
$$;

create function public.plan_fault_work_order(p_fault uuid,p_revision integer,p_request uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare f public.maintenance_requests; w public.work_orders; asset uuid; job uuid;
  next_state text; actor text;
begin
  if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Work order details are required'; end if;
  select asset_id into asset from public.maintenance_requests where id=p_fault;
  if asset is null or not public.maintenance_can_manage_asset(asset)
    or not public.maintenance_execution_enabled(asset) then raise exception 'Access denied' using errcode='42501'; end if;
  if public.maintenance_replayed(p_request,p_fault,'fault_work_order',p_data) then
    return (select converted_to_work_order_id from public.maintenance_requests where id=p_fault);
  end if;
  perform 1 from public.assets where id=asset for update;
  select * into f from public.maintenance_requests where id=p_fault for update;
  if p_revision is distinct from f.revision then raise exception 'This fault changed; refresh before editing' using errcode='40001'; end if;
  if f.status in ('resolved','dismissed') then raise exception 'Reopen this fault before planning a repair'; end if;
  if f.converted_to_work_order_id is not null then raise exception 'This fault already has a work order'; end if;
  if nullif(p_data->>'asset_id','') is not null and (p_data->>'asset_id')::uuid<>asset
    then raise exception 'Work order must belong to the same asset'; end if;
  job:=nullif(p_data->>'job_id','')::uuid;
  if job is null then
    job:=gen_random_uuid();
    perform public.create_maintenance_job(job,p_data || jsonb_build_object('asset_id',asset));
  end if;
  select * into w from public.work_orders where id=job for update;
  if w.id is null or w.asset_id<>asset or not w.managed_maintenance
    or not public.maintenance_can_read_job(job) then raise exception 'Choose a work order on this asset'; end if;
  if w.status not in ('draft','assigned','in_progress','on_hold') then
    raise exception 'Choose an open work order that is not awaiting review'; end if;
  next_state:=case when w.status in ('in_progress','on_hold') then 'in_progress' else 'acknowledged' end;
  update public.maintenance_requests set converted_to_work_order_id=job,assigned_to=w.assigned_to,
    status=next_state,revision=revision+1,updated_at=now() where id=p_fault;
  select full_name into actor from public.profiles where id=auth.uid();
  insert into public.maintenance_fault_events(fault_id,asset_id,operation_id,kind,payload,from_state,to_state,note,actor_id,actor_name)
    values(p_fault,asset,p_request,'create_work_order',jsonb_build_object('work_order_id',job),f.status,next_state,
      'Repair planned in linked work order',auth.uid(),coalesce(actor,'Manager'));
  perform public.maintenance_record_operation(p_request,p_fault,'fault_work_order',p_data);
  return job;
end $$;
revoke all on function public.plan_fault_work_order(uuid,integer,uuid,jsonb) from public,anon;
grant execute on function public.plan_fault_work_order(uuid,integer,uuid,jsonb) to authenticated;

create function public.sync_work_order_faults()
returns trigger language plpgsql security definer set search_path='' as $$
declare f public.maintenance_requests; next_state text; actor text;
begin
  if not new.managed_maintenance or (new.status is not distinct from old.status
    and new.assigned_to is not distinct from old.assigned_to) then return new; end if;
  next_state:=case when new.status='closed' then 'pending_review'
    when new.status in ('in_progress','on_hold','pending_review') then 'in_progress' else 'acknowledged' end;
  select full_name into actor from public.profiles where id=auth.uid();
  for f in select * from public.maintenance_requests where converted_to_work_order_id=new.id
    and status not in ('resolved','dismissed') order by id for update loop
    update public.maintenance_requests set status=next_state,assigned_to=new.assigned_to,
      revision=revision+1,updated_at=now() where id=f.id;
    insert into public.maintenance_fault_events(fault_id,asset_id,operation_id,kind,payload,from_state,to_state,note,actor_id,actor_name)
      values(f.id,f.asset_id,gen_random_uuid(),'work_order_progress',jsonb_build_object('work_order_id',new.id,'status',new.status),
        f.status,next_state,'Work order: '||new.status,auth.uid(),coalesce(actor,'Maintenance'));
  end loop;
  return new;
end $$;
revoke all on function public.sync_work_order_faults() from public,anon,authenticated;
create trigger sync_work_order_faults after update of status,assigned_to on public.work_orders
  for each row execute function public.sync_work_order_faults();

create or replace function public.change_maintenance_job(p_job uuid,p_revision integer,p_operation uuid,p_action text,p_data jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare w public.work_orders; j public.maintenance_job_records; plan public.asset_service_intervals;
 manager boolean; note text:=btrim(coalesce(p_data->>'note','')); next_state text; session_id uuid;
begin
 if not public.maintenance_can_work_job(p_job) then raise exception 'Access denied'; end if;
 if public.maintenance_replayed(p_operation,p_job,p_action,p_data) then return; end if;
 -- Serialize with fault review/linking before taking job and fault row locks.
 perform 1 from public.assets where id=(select asset_id from public.work_orders where id=p_job) for update;
 select * into j from public.maintenance_job_records where id=p_job for update;
 select * into w from public.work_orders where id=p_job for update;
 -- Recheck after waiting for the lock: assignment may have changed meanwhile.
 if not public.maintenance_can_work_job(p_job) then raise exception 'Access denied'; end if;
 if j.revision is distinct from p_revision then raise exception 'This job changed; refresh before editing' using errcode='40001'; end if;
 manager:=public.maintenance_can_manage_asset(w.asset_id);
 next_state:=w.status;
 if p_action='assign' then
  if not manager or w.status in ('closed','pending_review') then raise exception 'Assignment is not allowed'; end if;
  if exists(select 1 from public.maintenance_labour_sessions where work_order_id=p_job and stopped_at is null)
   then raise exception 'Pause labour before reassigning'; end if;
  if nullif(p_data->>'assigned_to','') is null then raise exception 'Choose an assignee'; end if;
  perform public.maintenance_validate_assignee(w.asset_id,(p_data->>'assigned_to')::uuid);
  update public.work_orders set assigned_to=(p_data->>'assigned_to')::uuid where id=p_job;
  if w.status='draft' then next_state:='assigned'; end if;
 elsif p_action='start' then
  if w.status not in ('assigned','in_progress','on_hold','draft') then raise exception 'Work cannot start in this state'; end if;
  insert into public.maintenance_labour_sessions(id,work_order_id,actor_id) values(p_operation,p_job,auth.uid());
  update public.work_orders set started_at=coalesce(started_at,now()),on_hold_reason=null where id=p_job;
  next_state:='in_progress';
 elsif p_action='pause' then
  session_id:=nullif(p_data->>'session_id','')::uuid;
  update public.maintenance_labour_sessions set stopped_at=clock_timestamp()
   where work_order_id=p_job and stopped_at is null and (id=session_id or session_id is null)
    and (actor_id=auth.uid() or manager);
  if not found then raise exception 'No running labour session'; end if;
 elsif p_action='block' then
  if w.status not in ('assigned','in_progress') or length(note)<3 then raise exception 'A blocked reason is required for active work'; end if;
  if exists(select 1 from public.maintenance_labour_sessions where work_order_id=p_job and stopped_at is null)
   then raise exception 'Pause labour before blocking work'; end if;
  update public.work_orders set on_hold_reason=note where id=p_job;
  next_state:='on_hold';
 elsif p_action in ('save_report','submit') then
  if w.status not in ('in_progress','on_hold') then raise exception 'Start or resume work before writing a report'; end if;
  if nullif(p_data->>'completion_hours','') is not null and not
    ((p_data->>'completion_hours')::numeric>=0 and (p_data->>'completion_hours')::numeric<1000000000)
   then raise exception 'A valid completion meter is required'; end if;
  insert into public.service_reports(work_order_id,cause,correction,comments)
   values(p_job,p_data->>'diagnosis',p_data->>'repair',p_data->>'notes')
   on conflict(managed_job_id) do update set cause=excluded.cause,correction=excluded.correction,comments=excluded.comments,updated_at=now();
  update public.maintenance_job_records set checklist_answers=coalesce(p_data->'answers','{}'),
   evidence_paths=coalesce(p_data->'evidence_paths','[]') where id=p_job;
  update public.work_orders set hours_at_end=nullif(p_data->>'completion_hours','')::numeric where id=p_job;
  perform public.maintenance_validate_report(p_job,p_action='submit');
  if p_action='submit' then
   if exists(select 1 from public.maintenance_labour_sessions where work_order_id=p_job and stopped_at is null)
    then raise exception 'Pause labour before submitting'; end if;
   next_state:='pending_review';
  end if;
 elsif p_action='add_part' then
  if w.status not in ('in_progress','on_hold') then raise exception 'Parts can only change during work'; end if;
  if length(btrim(coalesce(p_data->>'description','')))<2 or coalesce((p_data->>'quantity')::numeric,0)<=0
   or coalesce((p_data->>'unit_cost')::numeric,-1)<0
   or (p_data->>'unit_cost')::numeric>=100000000 or (p_data->>'quantity')::numeric>=1000000
    then raise exception 'Enter a part, positive quantity and nonnegative cost'; end if;
  insert into public.parts(id,work_order_id,description,part_number,quantity,unit_cost,markup_pct,logged_by)
   values(p_operation,p_job,btrim(p_data->>'description'),p_data->>'part_number',(p_data->>'quantity')::numeric,(p_data->>'unit_cost')::numeric,0,auth.uid());
 elsif p_action='remove_part' then
  if w.status not in ('in_progress','on_hold') then raise exception 'Parts can only change during work'; end if;
  delete from public.parts where id=(p_data->>'part_id')::uuid and work_order_id=p_job;
  if not found then raise exception 'Part no longer exists'; end if;
 elsif p_action='return' then
  if not manager or w.status<>'pending_review' or length(note)<3 then raise exception 'Return requires a manager and reason'; end if;
  update public.maintenance_job_records set review_note=note where id=p_job;
  next_state:='in_progress';
 elsif p_action='reopen' then
  if not manager or w.status<>'closed' or length(note)<3 then raise exception 'Reopen requires a manager and reason'; end if;
  if j.service_interval_id is not null then
    perform 1 from public.asset_service_intervals where id=j.service_interval_id for update;
  end if;
  if j.service_interval_id is not null and exists(select 1 from public.maintenance_job_records other
    join public.work_orders ow on ow.id=other.id where other.id<>p_job and other.service_interval_id=j.service_interval_id and ow.status<>'closed')
   then raise exception 'This plan already has an open job'; end if;
  update public.work_orders set completed_at=null where id=p_job;
  update public.maintenance_job_records set review_note=note,approved_by=null,approved_at=null where id=p_job;
  next_state:='in_progress';
 elsif p_action='approve' then
  if not manager or w.status<>'pending_review' then raise exception 'Only a manager can approve submitted work'; end if;
  perform public.maintenance_validate_report(p_job,true);
  if exists(select 1 from public.maintenance_labour_sessions where work_order_id=p_job and stopped_at is null)
   then raise exception 'Pause labour before approval'; end if;
  if j.service_interval_id is not null and j.service_applied_at is null then
   select * into plan from public.asset_service_intervals where id=j.service_interval_id for update;
   if plan.asset_id<>w.asset_id or plan.engine_id is distinct from w.engine_id or not plan.is_active
    then raise exception 'Maintenance plan no longer matches this job'; end if;
   if w.hours_at_end is null or w.hours_at_end<0 or w.hours_at_end>=1000000000 or w.hours_at_end<coalesce(plan.last_service_hours,0)
      or w.hours_at_end<coalesce(w.hours_at_start,0) then raise exception 'A valid completion meter is required'; end if;
   update public.asset_service_intervals set last_service_hours=w.hours_at_end,
     next_due_hours=w.hours_at_end+interval_hours,revision=revision+1 where id=plan.id;
   update public.asset_engines set current_hours=greatest(current_hours,w.hours_at_end),
    maintenance_revision=maintenance_revision+1 where id=w.engine_id;
   update public.service_reminders set engine_id=w.engine_id,interval_hours=plan.interval_hours,
    due_at_hours=w.hours_at_end+plan.interval_hours,acknowledged=false,
    threshold_50hr_sent=false,threshold_10hr_sent=false,threshold_due_sent=false
    where service_interval_id=plan.id and asset_id=w.asset_id;
   if not found then
    insert into public.service_reminders(asset_id,engine_id,service_interval_id,interval_hours,due_at_hours)
     values(w.asset_id,w.engine_id,plan.id,plan.interval_hours,w.hours_at_end+plan.interval_hours);
   end if;
   update public.maintenance_job_records set service_applied_at=now() where id=p_job;
  end if;
  update public.work_orders set completed_at=now(),labour_hours=(select coalesce(sum(extract(epoch from stopped_at-started_at)/3600),0)
   from public.maintenance_labour_sessions where work_order_id=p_job) where id=p_job;
  update public.maintenance_job_records set approved_by=auth.uid(),approved_at=now(),review_note=nullif(note,'') where id=p_job;
  insert into public.saved_checklists(id,asset_id,client_id,template_id,template_name,checklist_type,source_type,
   submitted_by,submitted_by_role,current_hours,general_notes,work_order_id,snapshot)
  values(p_operation,w.asset_id,w.client_id,w.checklist_template_id,w.title,'maintenance','work_order',
   auth.uid(),(select role from public.profiles where id=auth.uid()),w.hours_at_end,note,w.id,
   jsonb_build_object('managed_maintenance',true,'asset_id',w.asset_id,
    'header',jsonb_build_object('completed_by',w.assigned_to,'completed_by_name',(select full_name from public.profiles where id=w.assigned_to),
       'approved_by',auth.uid(),'current_hours',w.hours_at_end,'component_id',w.engine_id,'service_interval_id',j.service_interval_id),
    'items',coalesce((select jsonb_agg(item||jsonb_build_object('response',j.checklist_answers->(item->>'id')->>'result'))
      from jsonb_array_elements(j.checklist_snapshot) item),'[]'),
    'checklist_answers',j.checklist_answers,'evidence_paths',j.evidence_paths,'hourly_cost',j.hourly_cost,
    'labour',coalesce((select jsonb_agg(to_jsonb(l) order by l.started_at,l.id) from public.maintenance_labour_sessions l where l.work_order_id=w.id),'[]'),
    'parts',coalesce((select jsonb_agg(to_jsonb(p) order by p.id) from public.parts p where p.work_order_id=w.id),'[]'),
    'report',(select jsonb_build_object('diagnosis',cause,'repair',correction,'notes',comments) from public.service_reports where work_order_id=w.id)));
  next_state:='closed';
 else raise exception 'Unknown maintenance action';
 end if;
 update public.work_orders set status=next_state,updated_at=now() where id=p_job;
 update public.maintenance_job_records set revision=revision+1 where id=p_job;
 perform public.maintenance_record_operation(p_operation,p_job,p_action,p_data);
end $$;

create or replace function public.update_maintenance_fault(p_fault_id uuid,p_expected_revision integer,
  p_operation_id uuid,p_action text,p_note text,p_assigned_to uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_fault public.maintenance_requests; v_asset_id uuid; v_manager boolean;
  v_worker boolean; v_role text; v_actor text; v_next text; v_note text;
  v_assignee_name text; v_assignee_role text; v_job uuid; v_payload jsonb; v_previous_payload jsonb; v_link public.work_orders;
begin
  select asset_id into v_asset_id from public.maintenance_requests where id=p_fault_id;
  if v_asset_id is null or not public.maintenance_can_view_asset(v_asset_id) then
    raise exception 'Access denied' using errcode='42501'; end if;
  -- Lock in asset->fault order, shared with availability and reporting RPCs.
  perform 1 from public.assets where id=v_asset_id for update;
  select * into v_fault from public.maintenance_requests where id=p_fault_id for update;
  if p_operation_id is null then raise exception 'Missing operation identifier'; end if;
  v_payload := jsonb_build_object('action',p_action,'note',btrim(coalesce(p_note,'')),'assigned_to',p_assigned_to);
  select payload into v_previous_payload from public.maintenance_fault_events
    where operation_id=p_operation_id and fault_id=p_fault_id and actor_id=auth.uid();
  if found then
    if v_previous_payload=v_payload then return p_fault_id; end if;
    raise exception 'This operation was already used. Refresh before saving again' using errcode='40001';
  end if;
  if p_expected_revision is distinct from v_fault.revision then
    raise exception 'This fault changed. Refresh before saving again' using errcode='40001'; end if;
  select role,full_name into v_role,v_actor from public.profiles where id=auth.uid();
  v_manager := public.maintenance_can_manage_asset(v_asset_id);
  v_worker := v_manager or (v_fault.assigned_to=auth.uid() and v_role in ('employee','client_mechanic'));
  v_next := v_fault.status;
  v_note := btrim(coalesce(p_note,''));
  if length(v_note) not between 3 and 2000 then raise exception 'A note of 3 to 2000 characters is required'; end if;
  if p_action in ('acknowledge','assign','resolve','dismiss','reopen','create_work_order') then
    if not v_manager then raise exception 'Access denied: manager required' using errcode='42501'; end if;
  elsif p_action in ('start','submit','note') then
    if v_worker is not true then raise exception 'Access denied: assigned mechanic required' using errcode='42501'; end if;
  else raise exception 'Unknown fault action'; end if;
  if p_action <> 'reopen' and v_fault.status in ('resolved','dismissed') then
    raise exception 'Reopen this fault before changing it'; end if;

  select * into v_link from public.work_orders where id=v_fault.converted_to_work_order_id;
  if v_link.managed_maintenance then
    if p_action in ('start','submit','assign','create_work_order') then
      raise exception 'Open the linked work order to manage the repair';
    end if;
    if p_action='resolve' and v_link.status<>'closed' then
      raise exception 'Approve the linked work order before resolving this fault';
    end if;
    if p_action='reopen' and v_fault.status='pending_review' then
      raise exception 'Open and reopen the work order to request further repair';
    end if;
  end if;

  case p_action
    when 'acknowledge' then
      if v_fault.status <> 'open' then raise exception 'Only reported faults can be acknowledged'; end if;
      v_next := 'acknowledged';
    when 'start' then
      if v_fault.status not in ('open','acknowledged','converted') then raise exception 'Repair is already started or awaiting review'; end if;
      v_next := 'in_progress';
    when 'submit' then
      if v_fault.status <> 'in_progress' then raise exception 'Start repair before submitting for review'; end if;
      v_next := 'pending_review';
    when 'resolve' then
      if v_fault.status <> 'pending_review' then raise exception 'Repair must be submitted for review before resolution'; end if;
      v_next := 'resolved';
    when 'dismiss' then v_next := 'dismissed';
    when 'reopen' then
      if v_fault.status not in ('resolved','dismissed','pending_review') then raise exception 'Only closed or reviewed faults can be reopened'; end if;
      v_next := case when v_link.managed_maintenance and v_link.status='closed' then 'pending_review' else 'open' end;
    when 'assign' then
      select m->>'full_name',m->>'role' into v_assignee_name,v_assignee_role
        from public.maintenance_assignees(v_asset_id) m where (m->>'id')::uuid=p_assigned_to;
      if not found then raise exception 'Choose an eligible mechanic from this fleet'; end if;
      v_note := v_assignee_name || ': ' || v_note;
    when 'create_work_order' then
      if v_role <> 'owner' then raise exception 'Access denied: provider owner required' using errcode='42501'; end if;
      if v_fault.converted_to_work_order_id is not null then return p_fault_id; end if;
      insert into public.work_orders(asset_id,client_id,created_by,job_type,status,title,description)
        select a.id,a.client_id,auth.uid(),'repair','draft',left(v_fault.description,120),
          v_fault.description || E'\n\n' || v_note from public.assets a where a.id=v_asset_id
        returning id into v_job;
    else null;
  end case;

  update public.maintenance_requests set
    status=v_next, revision=revision+1, updated_at=now(),
    assigned_to=case when p_action='assign' then p_assigned_to else assigned_to end,
    converted_to_work_order_id=coalesce(v_job,converted_to_work_order_id),
    resolution_note=case when p_action in ('resolve','dismiss') then v_note
      when p_action='reopen' then null else resolution_note end,
    resolved_at=case when p_action in ('resolve','dismiss') then now()
      when p_action='reopen' then null else resolved_at end,
    resolved_by=case when p_action in ('resolve','dismiss') then auth.uid()
      when p_action='reopen' then null else resolved_by end
    where id=p_fault_id;
  insert into public.maintenance_fault_events(fault_id,asset_id,operation_id,kind,payload,
    from_state,to_state,note,actor_id,actor_name)
    values(p_fault_id,v_asset_id,p_operation_id,p_action,v_payload,v_fault.status,v_next,v_note,auth.uid(),v_actor);
  return p_fault_id;
end $$;

-- Keep durable field actions serialized with fault planning and review.
-- Preserve device-recorded labour time and existing authorization/revision checks.
create or replace function public.apply_maintenance_field_action(p_job uuid,p_revision integer,
 p_operation uuid,p_action text,p_data jsonb,p_recorded_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare payload jsonb; sessions uuid[]; started timestamptz; effective_time timestamptz;
begin
 if p_action not in ('start','pause','block','save_report','submit','add_part','remove_part')
  then raise exception 'Unsupported field action'; end if;
 if not public.maintenance_can_work_job(p_job) then raise exception 'Access denied'; end if;
 payload:=p_data || jsonb_build_object('_recorded_at',p_recorded_at);
 if public.maintenance_replayed(p_operation,p_job,p_action,payload) then return; end if;
 perform 1 from public.assets where id=(select asset_id from public.work_orders where id=p_job) for update;
 perform 1 from public.maintenance_job_records where id=p_job for update;
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
