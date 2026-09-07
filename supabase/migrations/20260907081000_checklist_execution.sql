-- NOW-015: preserve current managed work and atomic operator contracts.
create or replace function public.create_maintenance_job(p_request uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.assets; plan public.asset_service_intervals; assigned uuid;
 work_type text; materials text;
 parent public.work_orders; snapshot jsonb:='[]'; template uuid; component uuid;
begin
 select * into a from public.assets where id=(p_data->>'asset_id')::uuid;
 if a.id is null or not public.maintenance_can_manage_asset(a.id)
  or not public.maintenance_execution_enabled(a.id) then raise exception 'Access denied'; end if;
 if public.maintenance_replayed(p_request,p_request,'created',p_data) then return p_request; end if;
 if length(btrim(coalesce(p_data->>'title','')))<3 or length(p_data->>'title')>200
   then raise exception 'Title must contain 3 to 200 characters'; end if;
 work_type:=coalesce(nullif(p_data->>'job_type',''),case when nullif(p_data->>'service_interval_id','') is null then 'repair' else 'preventative' end);
 if work_type not in ('preventative','repair','inspection','general') then raise exception 'Choose a valid work type'; end if;
 if nullif(p_data->>'service_interval_id','') is not null and work_type<>'preventative'
   then raise exception 'A linked service plan requires preventive maintenance'; end if;
 materials:=btrim(coalesce(p_data->>'expected_materials',''));
 if length(materials)>4000 then raise exception 'Expected materials must be at most 4000 characters'; end if;
 if length(coalesce(p_data->>'description',''))>8000 then raise exception 'Instructions must be at most 8000 characters'; end if;
 assigned:=nullif(p_data->>'assigned_to','')::uuid;
 perform public.maintenance_validate_assignee(a.id,assigned);
 component:=nullif(p_data->>'engine_id','')::uuid;
 if component is not null and not exists(select 1 from public.asset_engines where id=component and asset_id=a.id)
  then raise exception 'Component belongs to another asset'; end if;
 if nullif(p_data->>'service_interval_id','') is not null then
  if not public.maintenance_can_plan(a.id) then raise exception 'Maintenance planning is disabled'; end if;
  select * into plan from public.asset_service_intervals where id=(p_data->>'service_interval_id')::uuid for update;
  if plan.id is null or plan.asset_id<>a.id or not plan.is_active or plan.engine_id is null
   then raise exception 'Select an active component maintenance plan'; end if;
  if exists(select 1 from public.maintenance_job_records j join public.work_orders w on w.id=j.id
    where j.service_interval_id=plan.id and w.status<>'closed') then raise exception 'This plan already has an open job'; end if;
  component:=plan.engine_id; template:=plan.checklist_template_id;
 else template:=nullif(p_data->>'checklist_template_id','')::uuid;
 end if;
 if plan.id is not null then template:=public.checklist_current_template(template); end if;
 if template is not null then
  if not public.checklist_template_usable(template,a.id,component,'pm') then raise exception 'Invalid checklist template'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'description_en',description_en,
    'description_es',description_es,'requires_photo',requires_photo,'category',category,'definition',definition) order by sort_order,id),'[]')
    into snapshot from public.checklist_items where template_id=template;
 end if;
 if nullif(p_data->>'parent_job_id','') is not null then
  select * into parent from public.work_orders where id=(p_data->>'parent_job_id')::uuid;
  if parent.asset_id is distinct from a.id or not public.maintenance_can_read_job(parent.id)
    then raise exception 'Invalid follow-up job'; end if;
 end if;
 insert into public.work_orders(id,asset_id,client_id,created_by,assigned_to,title,description,
   engine_id,checklist_template_id,job_type,status,scheduled_date,billable_rate,wage_rate,managed_maintenance)
 values(p_request,a.id,a.client_id,auth.uid(),assigned,btrim(p_data->>'title'),p_data->>'description',
   component,template,work_type,
   case when assigned is null then 'draft' else 'assigned' end,nullif(p_data->>'due_date','')::date,0,0,true);
 insert into public.maintenance_job_records(id,priority,service_interval_id,parent_job_id,checklist_snapshot,hourly_cost,expected_materials)
 values(p_request,coalesce(p_data->>'priority','normal'),plan.id,parent.id,snapshot,coalesce((p_data->>'hourly_cost')::numeric,0),materials);
 update public.work_orders set hours_at_start=(select current_hours from public.asset_engines where id=component) where id=p_request;
 perform public.maintenance_record_operation(p_request,p_request,'created',p_data);
 return p_request;
end $$;

create or replace function public.maintenance_asset_context(p_asset uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not public.maintenance_can_view_asset(p_asset) then raise exception 'Access denied'; end if;
 select jsonb_build_object('asset',to_jsonb(a),'can_manage',public.maintenance_can_manage_asset(a.id),
 'can_plan',public.maintenance_can_plan(a.id),'can_execute',public.maintenance_execution_enabled(a.id),
 'components',coalesce((select jsonb_agg(to_jsonb(e) order by e.label) from public.asset_engines e where e.asset_id=a.id),'[]'),
 'plans',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('component_name',e.label,'current_hours',e.current_hours,
  'open_job_id',(select w.id from public.work_orders w join public.maintenance_job_records j on j.id=w.id
    where j.service_interval_id=p.id and w.status<>'closed' limit 1)) order by p.interval_label,p.id)
  from public.asset_service_intervals p left join public.asset_engines e on e.id=p.engine_id where p.asset_id=a.id),'[]'),
 'templates',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'version',t.version,'scope_engine_id',t.scope_engine_id)) from public.checklist_templates t
  where t.is_active and t.checklist_type='pm' and public.checklist_template_visible(t.id) and (t.client_id is null or t.client_id=a.client_id) and (t.scope_asset_id is null or t.scope_asset_id=a.id) and (t.asset_type_id=a.asset_type_id or t.asset_type_id is null)),'[]'),
 'assignees',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'role',p.role) order by p.full_name)
 from public.profiles p where (p.role in ('client','client_admin','client_mechanic') and
   (p.id=a.client_id or exists(select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=a.client_id)))
  or (p.role in ('owner','employee') and exists(select 1 from public.profiles me where me.id=auth.uid() and me.role='owner'))),'[]'))
 into result from public.assets a where a.id=p_asset;
 return result;
end $$;

create or replace function public.save_maintenance_setup(p_operation uuid,p_kind text,p_id uuid,p_revision integer,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.assets; e public.asset_engines; plan public.asset_service_intervals;
 client uuid; asset uuid; component uuid; me public.profiles; template uuid; interval_value integer; baseline numeric;
begin
 select * into me from public.profiles where id=auth.uid();
 if me.role is null or me.role not in ('owner','client','client_admin') then raise exception 'Access denied'; end if;
 if public.maintenance_replayed(p_operation,p_id,'setup_'||p_kind,p_data) then return p_id; end if;
 if p_kind='asset' then
  select * into a from public.assets where id=p_id for update;
  if a.id is not null then
   if not public.maintenance_can_manage_asset(a.id) then raise exception 'Access denied'; end if;
   if a.maintenance_revision is distinct from p_revision then raise exception 'Asset changed; refresh' using errcode='40001'; end if;
   client:=a.client_id;
  elsif me.role='owner' then
   client:=(p_data->>'client_id')::uuid;
   if not exists(select 1 from public.profiles where id=client and role in ('client','client_admin')) then raise exception 'Select a company owner'; end if;
  else
   select coalesce(o.owner_profile_id,me.id) into client from (select 1) singleton
    left join public.client_orgs o on o.id=me.org_id;
  end if;
  if length(btrim(coalesce(p_data->>'name','')))<2 then raise exception 'Asset name is required'; end if;
  if a.id is null then
   insert into public.assets(id,client_id,asset_type_id,name,make,model,serial_number,location)
    values(p_id,client,(p_data->>'asset_type_id')::uuid,btrim(p_data->>'name'),p_data->>'make',p_data->>'model',p_data->>'serial_number',p_data->>'location');
  else
   update public.assets set name=btrim(p_data->>'name'),make=p_data->>'make',model=p_data->>'model',
    serial_number=p_data->>'serial_number',location=p_data->>'location',maintenance_revision=maintenance_revision+1 where id=p_id;
  end if;
 elsif p_kind='component' then
  select * into e from public.asset_engines where id=p_id for update;
  asset:=coalesce(e.asset_id,(p_data->>'asset_id')::uuid);
  if not public.maintenance_can_manage_asset(asset) then raise exception 'Access denied'; end if;
  if e.id is not null and e.maintenance_revision is distinct from p_revision then raise exception 'Component changed; refresh' using errcode='40001'; end if;
  if length(btrim(coalesce(p_data->>'label','')))<2 then raise exception 'Component name is required'; end if;
  if e.id is null then
   if not (coalesce((p_data->>'current_hours')::numeric,0)>=0 and coalesce((p_data->>'current_hours')::numeric,0)<1000000000)
    then raise exception 'Meter must be finite and nonnegative'; end if;
   insert into public.asset_engines(id,asset_id,label,kind,current_hours)
    values(p_id,asset,btrim(p_data->>'label'),coalesce(p_data->>'kind','engine'),coalesce((p_data->>'current_hours')::numeric,0));
  else
   -- Meter corrections belong to the existing meter/history workflow, not rename.
   update public.asset_engines set label=btrim(p_data->>'label'),maintenance_revision=maintenance_revision+1 where id=p_id;
  end if;
 elsif p_kind='plan' then
  select * into plan from public.asset_service_intervals where id=p_id for update;
  asset:=coalesce(plan.asset_id,(p_data->>'asset_id')::uuid);
  if not public.maintenance_can_plan(asset) then raise exception 'Access denied'; end if;
  if plan.id is not null and plan.revision is distinct from p_revision then raise exception 'Plan changed; refresh' using errcode='40001'; end if;
  if exists(select 1 from public.work_orders w join public.maintenance_job_records j on j.id=w.id
   where j.service_interval_id=p_id and w.status<>'closed') then raise exception 'Finish the open job before changing this plan'; end if;
  component:=(p_data->>'engine_id')::uuid;
  if not exists(select 1 from public.asset_engines where id=component and asset_id=asset) then raise exception 'Select a component of this asset'; end if;
  if plan.engine_id is not null and plan.engine_id<>component then raise exception 'Create a separate plan for another component'; end if;
  template:=public.checklist_current_template(nullif(p_data->>'checklist_template_id','')::uuid);
  if template is not null and not public.checklist_template_usable(template,asset,component,'pm') then raise exception 'Invalid checklist template'; end if;
  interval_value:=(p_data->>'interval_hours')::integer;
  baseline:=coalesce((p_data->>'last_service_hours')::numeric,0);
  if interval_value is null or interval_value<=0 or baseline<0 then raise exception 'Enter a positive interval and nonnegative baseline'; end if;
  if plan.id is not null and plan.last_service_hours is not null and baseline<>plan.last_service_hours then raise exception 'Service baseline changes only through approved completion'; end if;
  insert into public.asset_service_intervals(id,asset_id,engine_id,interval_label,interval_hours,checklist_template_id,last_service_hours,next_due_hours,is_active)
   values(p_id,asset,component,p_data->>'interval_label',interval_value,template,baseline,baseline+interval_value,coalesce((p_data->>'is_active')::boolean,true))
   on conflict(id) do update set engine_id=excluded.engine_id,interval_label=excluded.interval_label,
    interval_hours=excluded.interval_hours,checklist_template_id=excluded.checklist_template_id,
    last_service_hours=excluded.last_service_hours,next_due_hours=excluded.next_due_hours,is_active=excluded.is_active,revision=public.asset_service_intervals.revision+1;
  update public.service_reminders set engine_id=component,interval_hours=interval_value,
    due_at_hours=baseline+interval_value,acknowledged=not coalesce((p_data->>'is_active')::boolean,true),
    threshold_50hr_sent=false,threshold_10hr_sent=false,threshold_due_sent=false
    where service_interval_id=p_id and asset_id=asset;
  if not found then
    insert into public.service_reminders(asset_id,engine_id,service_interval_id,interval_hours,due_at_hours,acknowledged)
    values(asset,component,p_id,interval_value,baseline+interval_value,not coalesce((p_data->>'is_active')::boolean,true));
  end if;
 else raise exception 'Unknown setup action';
 end if;
 perform public.maintenance_record_operation(p_operation,p_id,'setup_'||p_kind,p_data);
 return p_id;
end $$;

create or replace function public.maintenance_validate_report(p_job uuid,p_complete boolean)
returns void language plpgsql security definer set search_path='' as $$
declare j public.maintenance_job_records; s public.service_reports; item jsonb; path text; answer jsonb;
begin
 select * into j from public.maintenance_job_records where id=p_job;
 select * into s from public.service_reports where work_order_id=p_job;
 if jsonb_typeof(j.evidence_paths)<>'array' or jsonb_typeof(j.checklist_answers)<>'object'
  then raise exception 'Invalid report data'; end if;
 for path in select jsonb_array_elements_text(j.evidence_paths) loop
  if split_part(path,'/',1)<>p_job::text or not exists(select 1 from storage.objects
   where bucket_id='maintenance-evidence' and name=path) then raise exception 'Evidence upload is incomplete'; end if;
 end loop;
 if not p_complete then return; end if;
 if length(btrim(coalesce(s.cause,'')))<3 or length(btrim(coalesce(s.correction,'')))<3
  then raise exception 'Findings and work performed are required'; end if;
 for item in select jsonb_array_elements(j.checklist_snapshot) loop
  answer:=j.checklist_answers->(item->>'id');
  perform public.validate_checklist_answer(coalesce(item->'definition','{}'),answer->>'result',answer->>'note');
  if coalesce(answer->>'result','') not in ('pass','na') then raise exception 'Complete every checklist item; resolve failed items first'; end if;
  if (item->>'requires_photo')::boolean and
    (coalesce(answer->>'photo_path','')='' or not j.evidence_paths ? (answer->>'photo_path'))
   then raise exception 'Required checklist photo is missing'; end if;
 end loop;
end $$;

create or replace function public.maintenance_jobs(p_job uuid default null,p_asset uuid default null)
returns setof jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',w.id,'asset_id',w.asset_id,'asset_name',a.name,
 'title',w.title,'description',w.description,'status',w.status,'assigned_to',w.assigned_to,
 'assignee_name',p.full_name,'due_date',w.scheduled_date,'engine_id',w.engine_id,
 'component_name',e.label,'job_type',w.job_type,'hours_at_end',w.hours_at_end,
 'on_hold_reason',w.on_hold_reason,'blocked_category',j.blocked_category,'created_at',w.created_at,'completed_at',w.completed_at,
 'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,
 'started_at',w.started_at,'hours_at_start',w.hours_at_start,'expected_materials',j.expected_materials,
 'revision',j.revision,'priority',j.priority,'service_interval_id',j.service_interval_id,
 'parent_job_id',j.parent_job_id,'hourly_cost',j.hourly_cost,'review_note',j.review_note,
 'approved_at',j.approved_at,'service_applied_at',j.service_applied_at,
 'checklist_template_id',w.checklist_template_id,'checklist_template_version',w.checklist_template_version,'checklist_template_name',(select template_name from public.work_order_checklist_snapshots where work_order_id=w.id),'checklist_snapshot',j.checklist_snapshot,'checklist_answers',j.checklist_answers,'evidence_paths',j.evidence_paths,
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
   jsonb_build_object('managed_maintenance',true,'asset_id',w.asset_id,'template',jsonb_build_object('id',w.checklist_template_id,'version',w.checklist_template_version,'name',(select template_name from public.work_order_checklist_snapshots where work_order_id=w.id)),
    'header',jsonb_build_object('completed_by',w.assigned_to,'completed_by_name',(select full_name from public.profiles where id=w.assigned_to),
       'approved_by',auth.uid(),'current_hours',w.hours_at_end,'component_id',w.engine_id,'service_interval_id',j.service_interval_id),
    'items',coalesce((select jsonb_agg(item||jsonb_build_object('response',j.checklist_answers->(item->>'id')->>'result','note',j.checklist_answers->(item->>'id')->>'note','photo_path',j.checklist_answers->(item->>'id')->>'photo_path'))
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

create or replace function public.submit_operations_checklist(p_operation uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare asset public.assets; template public.checklist_templates; actor public.profiles;
 prior public.operations_submissions; item public.checklist_items; response text; note text; photo text;
 completed timestamptz; started timestamptz; assignment public.checklist_assignments; fault uuid; hours numeric; items jsonb:='[]'; snapshot jsonb; prefix text; total integer:=0;
begin
 select * into asset from public.assets where id=(p_data->>'asset_id')::uuid;
 if not public.operations_can_submit(asset.id) then raise exception 'Access denied'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into prior from public.operations_submissions where id=p_operation;
 if found then
  if prior.actor_id<>auth.uid() or prior.payload<>p_data then raise exception 'Identifier already used for different input'; end if;
  return p_operation;
 end if;
 select * into actor from public.profiles where id=auth.uid();
 select * into template from public.checklist_templates where id=(p_data->>'template_id')::uuid;
 started:=coalesce((p_data->>'started_at')::timestamptz,(p_data->>'completed_at')::timestamptz);
 if nullif(p_data->>'assignment_id','') is not null then
  select * into assignment from public.checklist_assignments where id=(p_data->>'assignment_id')::uuid for update;
  if assignment.id is null or assignment.assigned_to<>auth.uid() or assignment.asset_id is distinct from asset.id
   or assignment.template_id<>template.id or assignment.status not in ('pending','in_progress') then raise exception 'Assignment is unavailable or already completed'; end if;
 end if;
 if template.id is null or not public.checklist_template_usable(template.id,asset.id,null,'operator_daily',false)
  or (not template.is_active and assignment.id is null and (template.procedure_id is null or started>template.updated_at))
  or template.version is distinct from (p_data->>'template_version')::integer
  then raise exception 'Checklist changed or is unavailable; reload it before submitting' using errcode='40001'; end if;
 if p_data->>'run_type' not in ('pre_departure','post_trip') then raise exception 'Invalid run type'; end if;
 completed:=(p_data->>'completed_at')::timestamptz;
 if completed is null or started is null or started>completed or started<now()-interval '30 days' or completed>now()+interval '5 minutes' or completed<now()-interval '30 days'
  then raise exception 'Invalid completion time'; end if;
 if nullif(p_data->>'assignment_id','') is not null then
  select * into assignment from public.checklist_assignments where id=(p_data->>'assignment_id')::uuid for update;
  if assignment.id is null or assignment.assigned_to<>auth.uid() or assignment.asset_id is distinct from asset.id
   or assignment.template_id<>template.id or assignment.status not in ('pending','in_progress') then raise exception 'Assignment is unavailable or already completed'; end if;
 end if;
 hours:=nullif(p_data->>'current_hours','')::numeric;
 if hours<0 or hours>=1000000000 then raise exception 'Invalid hours'; end if;
 if jsonb_typeof(p_data->'responses') is distinct from 'object' or jsonb_typeof(p_data->'photos') is distinct from 'object'
  or jsonb_typeof(p_data->'notes') is distinct from 'object' then raise exception 'Invalid answers'; end if;
 prefix:=asset.id::text||'/'||auth.uid()::text||'/'||p_operation::text||'/';
 for item in select * from public.checklist_items where template_id=template.id order by sort_order,id loop
  total:=total+1; response:=p_data->'responses'->>item.id::text;
  note:=btrim(coalesce(p_data->'notes'->>item.id::text,''));photo:=nullif(p_data->'photos'->>item.id::text,'');
  if response is null or response not in ('pass','monitor','alert','action','n/a') then raise exception 'Answer every checklist item'; end if;
  if response in ('monitor','alert','action') and length(note)=0 then raise exception 'Add a note for flagged items'; end if;
  perform public.validate_checklist_answer(item.definition,response,note);
  if item.requires_photo and photo is null then raise exception 'Required photo is missing'; end if;
  if photo is not null and (photo not in (prefix||item.id::text||'.jpg',prefix||item.id::text||'.png',prefix||item.id::text||'.webp')
    or not exists(select 1 from storage.objects where bucket_id='operator-evidence' and name=photo))
    then raise exception 'Photo must upload before completion'; end if;
  items:=items||jsonb_build_array(jsonb_build_object('id',item.id,'description_en',item.description_en,
   'description_es',item.description_es,'category',item.category,'sort_order',item.sort_order,
   'definition',item.definition,'response',case response when 'alert' then 'monitor' else response end,'note',note,'photo_url',photo));
 end loop;
 if total=0 or total<>(select count(*) from jsonb_object_keys(p_data->'responses'))
  or exists(select 1 from jsonb_object_keys(p_data->'photos') k where not exists(select 1 from public.checklist_items where template_id=template.id and id::text=k))
  then raise exception 'Checklist items changed; reload before submitting' using errcode='40001'; end if;
 insert into public.operations_submissions values(p_operation,auth.uid(),asset.id,p_data,now());
 insert into public.operator_checklist_runs(id,asset_id,template_id,operator_id,run_type,completed_at,notes,assignment_id,started_at)
  values(p_operation,asset.id,template.id,auth.uid(),p_data->>'run_type',completed,p_data->>'general_notes',assignment.id,started);
 if assignment.id is not null then
  update public.checklist_assignments set status='completed',completed_run_id=p_operation,completed_at=completed,updated_at=now() where id=assignment.id;
 end if;
 for item in select * from public.checklist_items where template_id=template.id order by sort_order,id loop
  response:=p_data->'responses'->>item.id::text;
  if response in ('monitor','alert','action') then
   fault:=gen_random_uuid();
   perform public.report_maintenance_fault(fault,asset.id,left('Pre-operation: '||template.name||' — '||item.description_en||E'\n'||coalesce(p_data->'notes'->>item.id::text,''),4000),
    case when coalesce((item.definition->>'critical')::boolean,false) then 'urgent' else 'normal' end);
   insert into public.checklist_findings(run_id,item_id,fault_id) values(p_operation,item.id,fault);
  end if;
 end loop;
 insert into public.operator_checklist_responses(run_id,checklist_item_id,result,response_status,notes,photo_url)
 select p_operation,(i->>'id')::uuid,
  case i->>'response' when 'pass' then 'good' when 'n/a' then 'not_applicable' else 'needs_attention' end,
  case i->>'response' when 'monitor' then 'alert' when 'n/a' then null else i->>'response' end,i->>'note',i->>'photo_url'
 from jsonb_array_elements(items) i;
 snapshot:=jsonb_build_object('asset_id',asset.id,'template',to_jsonb(template),'items',items,
  'header',jsonb_build_object('asset_id',asset.id,'checklist_name',template.name,'completed_by',auth.uid(),
   'completed_by_name',actor.full_name,'submitted_at',completed,'current_hours',hours,'general_notes',p_data->>'general_notes',
   'run_id',p_operation,'run_type',p_data->>'run_type','assignment_id',assignment.id,'started_at',started,'follow_up_faults',coalesce((select jsonb_agg(jsonb_build_object('item_id',item_id,'fault_id',fault_id)) from public.checklist_findings where run_id=p_operation),'[]')),
  'source',jsonb_build_object('source_type','operator'),'submitted_by_role',actor.role);
 insert into public.saved_checklists(id,asset_id,client_id,template_id,template_name,checklist_type,source_type,
  submitted_by,submitted_by_role,submitted_at,current_hours,general_notes,snapshot)
 values(p_operation,asset.id,asset.client_id,template.id,template.name,'operations','operator',auth.uid(),actor.role,
  completed,hours,p_data->>'general_notes',snapshot);
 return p_operation;
end $$;
