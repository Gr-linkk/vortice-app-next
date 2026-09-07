-- NOW-014: client-owned internal work orders share the work-order vocabulary.
alter table public.work_orders drop constraint work_orders_job_type_check;
alter table public.work_orders add constraint work_orders_job_type_check
  check (job_type in ('preventative','repair','inspection','general'));
alter table public.maintenance_job_records add column expected_materials text not null default ''
  check (length(expected_materials)<=4000);

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
 if template is not null then
  if not exists(select 1 from public.checklist_templates where id=template and
    (asset_type_id is null or asset_type_id=a.asset_type_id)) then raise exception 'Invalid checklist template'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'description_en',description_en,
    'description_es',description_es,'requires_photo',requires_photo) order by sort_order,id),'[]')
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

create or replace function public.maintenance_planning(p_asset uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'jobs',coalesce((select jsonb_agg(jsonb_build_object(
    'id',w.id,'asset_id',w.asset_id,'asset_name',a.name,'title',w.title,
    'job_type',w.job_type,'status',w.status,'priority',j.priority,'due_date',w.scheduled_date,
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
  if coalesce(answer->>'result','') not in ('pass','na') then raise exception 'Complete every checklist item; resolve failed items first'; end if;
  if (item->>'requires_photo')::boolean and
    (coalesce(answer->>'photo_path','')='' or not j.evidence_paths ? (answer->>'photo_path'))
   then raise exception 'Required checklist photo is missing'; end if;
 end loop;
end $$;

create function public.update_internal_work_order(p_job uuid,p_revision integer,p_operation uuid,p_data jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare w public.work_orders; j public.maintenance_job_records; asset uuid; work_type text; note text;
begin
 select asset_id into asset from public.work_orders where id=p_job;
 if asset is null or not public.maintenance_can_manage_asset(asset) or not public.maintenance_execution_enabled(asset)
   then raise exception 'Access denied' using errcode='42501'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Work order details are required'; end if;
 if public.maintenance_replayed(p_operation,p_job,'edit_details',p_data) then return; end if;
 perform 1 from public.assets where id=asset for update;
 select * into j from public.maintenance_job_records where id=p_job for update;
 select * into w from public.work_orders where id=p_job for update;
 if j.id is null or not public.maintenance_can_manage_asset(asset) or not public.maintenance_execution_enabled(asset)
   then raise exception 'Access denied' using errcode='42501'; end if;
 if p_revision is distinct from j.revision then raise exception 'This work order changed; refresh before editing' using errcode='40001'; end if;
 if w.status not in ('draft','assigned') or w.started_at is not null or exists(
   select 1 from public.maintenance_labour_sessions where work_order_id=p_job)
   then raise exception 'Scope can only be edited before work starts'; end if;
 work_type:=p_data->>'job_type';
 if work_type is null or work_type not in ('preventative','repair','inspection','general') then raise exception 'Choose a valid work type'; end if;
 if j.service_interval_id is not null and work_type<>'preventative' then raise exception 'A linked service plan requires preventive maintenance'; end if;
 if length(btrim(coalesce(p_data->>'title','')))<3 or length(p_data->>'title')>200 then raise exception 'Title must contain 3 to 200 characters'; end if;
 if length(coalesce(p_data->>'description',''))>8000 then raise exception 'Instructions must be at most 8000 characters'; end if;
 if length(coalesce(p_data->>'expected_materials',''))>4000 then raise exception 'Expected materials must be at most 4000 characters'; end if;
 if coalesce(p_data->>'priority','') not in ('low','normal','high','urgent') then raise exception 'Choose a priority'; end if;
 note:=btrim(coalesce(p_data->>'note',''));
 if length(note)<3 or length(note)>1000 then raise exception 'Explain the scope change (3 to 1000 characters)'; end if;
 update public.work_orders set title=btrim(p_data->>'title'),description=p_data->>'description',job_type=work_type,updated_at=now()
   where id=p_job;
 update public.maintenance_job_records set expected_materials=btrim(coalesce(p_data->>'expected_materials','')),
   priority=p_data->>'priority',revision=revision+1 where id=p_job;
 perform public.maintenance_record_operation(p_operation,p_job,'edit_details',p_data);
 perform public.maintenance_record_operation(gen_random_uuid(),p_job,'scope_previous',jsonb_build_object(
   'title',w.title,'description',w.description,'job_type',w.job_type,'priority',j.priority,
   'expected_materials',j.expected_materials,'edit_operation',p_operation));
end $$;
revoke all on function public.update_internal_work_order(uuid,integer,uuid,jsonb) from public,anon;
grant execute on function public.update_internal_work_order(uuid,integer,uuid,jsonb) to authenticated;

