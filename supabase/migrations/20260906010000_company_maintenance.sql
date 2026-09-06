-- NOW-006: shared company/provider execution, separate from customer billing.
alter table public.work_orders add column managed_maintenance boolean not null default false;
alter table public.assets add column maintenance_revision integer not null default 0;
alter table public.asset_engines add column maintenance_revision integer not null default 0;
alter table public.asset_service_intervals
 add column engine_id uuid references public.asset_engines(id),
 add column last_service_hours numeric(10,1) check(last_service_hours>=0 and last_service_hours<1000000000),
 add column next_due_hours numeric(10,1) check(next_due_hours>=0 and next_due_hours<1000000000),
 add column revision integer not null default 0;

create table public.maintenance_job_records (
 id uuid primary key references public.work_orders(id) on delete restrict,
 revision integer not null default 0,
 priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
 service_interval_id uuid references public.asset_service_intervals(id),
 parent_job_id uuid references public.work_orders(id),
 checklist_snapshot jsonb not null default '[]',
 checklist_answers jsonb not null default '{}',
 evidence_paths jsonb not null default '[]',
 hourly_cost numeric(10,2) not null default 0 check(hourly_cost>=0 and hourly_cost<100000000),
 approved_by uuid references public.profiles(id),
 approved_at timestamptz,
 service_applied_at timestamptz,
 review_note text
);
create table public.maintenance_labour_sessions (
 id uuid primary key,
 work_order_id uuid not null references public.maintenance_job_records(id),
 actor_id uuid not null references public.profiles(id),
 started_at timestamptz not null default clock_timestamp(),
 stopped_at timestamptz,
 check(stopped_at is null or stopped_at>=started_at)
);
create unique index maintenance_one_running_timer on public.maintenance_labour_sessions(actor_id)
 where stopped_at is null;
create table public.maintenance_operations (
 id uuid primary key,
 object_id uuid not null,
 actor_id uuid not null references public.profiles(id),
 kind text not null,
 payload jsonb not null,
 created_at timestamptz not null default now()
);
create index maintenance_operations_object on public.maintenance_operations(object_id,created_at);

create function public.maintenance_execution_enabled(p_asset uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.maintenance_can_view_asset(p_asset) and exists(
  select 1 from public.profiles p where p.id=auth.uid() and
   (p.role in ('owner','employee') or
    (p.role in ('client','client_admin','client_mechanic') and exists(
      select 1 from public.client_capabilities c join public.assets a on a.client_id=c.client_id
       where a.id=p_asset and c.capability_key='pm_checklists' and c.enabled))))
$$;
create function public.maintenance_can_read_job(p_job uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w join public.profiles p on p.id=auth.uid()
  where w.id=p_job and w.managed_maintenance and public.maintenance_can_view_asset(w.asset_id)
    and (p.role in ('owner','client','client_admin') or
     (p.role in ('employee','client_mechanic') and w.assigned_to=p.id)))
$$;
create function public.maintenance_can_work_job(p_job uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.maintenance_can_read_job(p_job) and exists(select 1 from public.work_orders w
 where w.id=p_job and public.maintenance_execution_enabled(w.asset_id))
$$;

-- Security-definer operations are the sole write interface for managed jobs.
-- Restrictive policies compose with inherited permissive policies.
create policy managed_work_orders_rpc_only on public.work_orders as restrictive
 for all to authenticated using(not managed_maintenance) with check(not managed_maintenance);
-- Use a definer predicate because direct reads of managed records are denied.
create function public.is_managed_maintenance(p_job uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders where id=p_job and managed_maintenance)
$$;
create policy managed_reports_rpc_only on public.service_reports as restrictive
 for all to authenticated using(not public.is_managed_maintenance(work_order_id))
 with check(not public.is_managed_maintenance(work_order_id));
create policy managed_parts_rpc_only on public.parts as restrictive
 for all to authenticated using(not public.is_managed_maintenance(work_order_id))
 with check(not public.is_managed_maintenance(work_order_id));
create policy managed_responses_rpc_only on public.checklist_responses as restrictive
 for all to authenticated using(not public.is_managed_maintenance(work_order_id))
 with check(not public.is_managed_maintenance(work_order_id));
create policy managed_assignments_rpc_only on public.work_order_assignments as restrictive
 for all to authenticated using(not public.is_managed_maintenance(work_order_id))
 with check(not public.is_managed_maintenance(work_order_id));
create policy managed_hours_rpc_only on public.hour_logs as restrictive
 for all to authenticated using(not public.is_managed_maintenance(work_order_id))
 with check(not public.is_managed_maintenance(work_order_id));
create policy internal_jobs_no_invoice on public.invoices as restrictive
 for all to authenticated using(not public.is_managed_maintenance(work_order_id))
 with check(not public.is_managed_maintenance(work_order_id));
create policy managed_history_read on public.saved_checklists as restrictive
 for select to authenticated using(not public.is_managed_maintenance(work_order_id) or public.maintenance_can_read_job(work_order_id));
create policy managed_history_write on public.saved_checklists as restrictive
 for insert to authenticated with check(not public.is_managed_maintenance(work_order_id));

alter table public.maintenance_job_records enable row level security;
alter table public.maintenance_labour_sessions enable row level security;
alter table public.maintenance_operations enable row level security;
revoke all on public.maintenance_job_records,public.maintenance_labour_sessions,public.maintenance_operations
 from public,anon,authenticated;
grant all on public.maintenance_job_records,public.maintenance_labour_sessions,public.maintenance_operations to service_role;

create function public.maintenance_replayed(p_operation uuid,p_object uuid,p_kind text,p_payload jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
declare previous public.maintenance_operations;
begin
 if auth.uid() is null or p_operation is null then raise exception 'Access denied'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into previous from public.maintenance_operations where id=p_operation;
 if found then
  if previous.actor_id<>auth.uid() or previous.object_id<>p_object or previous.kind<>p_kind
   or previous.payload<>p_payload then raise exception 'Operation already used with different input'; end if;
  return true;
 end if;
 return false;
end $$;

create function public.maintenance_record_operation(p_operation uuid,p_object uuid,p_kind text,p_payload jsonb)
returns void language sql security definer set search_path='' as $$
 insert into public.maintenance_operations(id,object_id,actor_id,kind,payload)
 values(p_operation,p_object,auth.uid(),p_kind,p_payload)
$$;

create function public.maintenance_validate_assignee(p_asset uuid,p_assignee uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_assignee is null then return; end if;
 if not exists(select 1 from public.profiles p join public.assets a on a.id=p_asset
  where p.id=p_assignee and (p.role in ('owner','employee') or
    (p.role in ('client','client_admin','client_mechanic') and
     (p.id=a.client_id or exists(select 1 from public.client_orgs o
       where o.id=p.org_id and o.owner_profile_id=a.client_id))))) then
  raise exception 'Invalid assignee';
 end if;
 -- Company managers cannot assign provider personnel without provider authority.
 if not exists(select 1 from public.profiles where id=auth.uid() and role='owner') and
    exists(select 1 from public.profiles where id=p_assignee and role in ('owner','employee')) then
  raise exception 'Invalid assignee';
 end if;
end $$;

create function public.create_maintenance_job(p_request uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.assets; plan public.asset_service_intervals; assigned uuid;
 parent public.work_orders; snapshot jsonb:='[]'; template uuid; component uuid;
begin
 select * into a from public.assets where id=(p_data->>'asset_id')::uuid;
 if a.id is null or not public.maintenance_can_manage_asset(a.id)
  or not public.maintenance_execution_enabled(a.id) then raise exception 'Access denied'; end if;
 if public.maintenance_replayed(p_request,p_request,'created',p_data) then return p_request; end if;
 if length(btrim(coalesce(p_data->>'title','')))<3 or length(p_data->>'title')>200
   then raise exception 'Title must contain 3 to 200 characters'; end if;
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
   component,template,case when plan.id is null then 'repair' else 'preventative' end,
   case when assigned is null then 'draft' else 'assigned' end,nullif(p_data->>'due_date','')::date,0,0,true);
 insert into public.maintenance_job_records(id,priority,service_interval_id,parent_job_id,checklist_snapshot,hourly_cost)
 values(p_request,coalesce(p_data->>'priority','normal'),plan.id,parent.id,snapshot,coalesce((p_data->>'hourly_cost')::numeric,0));
 update public.work_orders set hours_at_start=(select current_hours from public.asset_engines where id=component) where id=p_request;
 perform public.maintenance_record_operation(p_request,p_request,'created',p_data);
 return p_request;
end $$;

create function public.maintenance_jobs(p_job uuid default null,p_asset uuid default null)
returns setof jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',w.id,'asset_id',w.asset_id,'asset_name',a.name,
 'title',w.title,'description',w.description,'status',w.status,'assigned_to',w.assigned_to,
 'assignee_name',p.full_name,'due_date',w.scheduled_date,'engine_id',w.engine_id,
 'component_name',e.label,'job_type',w.job_type,'hours_at_end',w.hours_at_end,
 'on_hold_reason',w.on_hold_reason,'created_at',w.created_at,'completed_at',w.completed_at,
 'revision',j.revision,'priority',j.priority,'service_interval_id',j.service_interval_id,
 'parent_job_id',j.parent_job_id,'hourly_cost',j.hourly_cost,'review_note',j.review_note,
 'approved_at',j.approved_at,'service_applied_at',j.service_applied_at,
 'checklist_snapshot',j.checklist_snapshot,'checklist_answers',j.checklist_answers,'evidence_paths',j.evidence_paths,
 'can_manage',public.maintenance_can_manage_asset(w.asset_id),
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

revoke all on function public.maintenance_replayed(uuid,uuid,text,jsonb),
 public.maintenance_record_operation(uuid,uuid,text,jsonb),public.maintenance_validate_assignee(uuid,uuid) from public,anon,authenticated;
revoke all on function public.create_maintenance_job(uuid,jsonb),public.maintenance_jobs(uuid,uuid),
 public.maintenance_execution_enabled(uuid),public.maintenance_can_read_job(uuid),public.maintenance_can_work_job(uuid),public.is_managed_maintenance(uuid) from public,anon;
grant execute on function public.create_maintenance_job(uuid,jsonb),public.maintenance_jobs(uuid,uuid),
 public.maintenance_execution_enabled(uuid),public.maintenance_can_read_job(uuid),public.maintenance_can_work_job(uuid),public.is_managed_maintenance(uuid) to authenticated;

-- Private job evidence is isolated from inherited, broadly readable buckets.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('maintenance-evidence','maintenance-evidence',false,10485760,array['image/jpeg','image/png','image/webp']);
create function public.maintenance_evidence_job(p_name text)
returns uuid language plpgsql immutable set search_path='' as $$
begin return split_part(p_name,'/',1)::uuid;
exception when invalid_text_representation then return null;
end $$;
create policy maintenance_evidence_read on storage.objects for select to authenticated
 using(bucket_id='maintenance-evidence' and public.maintenance_can_read_job(public.maintenance_evidence_job(name)));
create policy maintenance_evidence_upload on storage.objects for insert to authenticated
 with check(bucket_id='maintenance-evidence' and split_part(name,'/',2)=auth.uid()::text
  and public.maintenance_can_work_job(public.maintenance_evidence_job(name)));
-- No replacement/deletion: submitted evidence must remain stable for reviewers.

create function public.maintenance_validate_report(p_job uuid,p_complete boolean)
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
  then raise exception 'Diagnosis and repair notes are required'; end if;
 for item in select jsonb_array_elements(j.checklist_snapshot) loop
  answer:=j.checklist_answers->(item->>'id');
  if coalesce(answer->>'result','') not in ('pass','na') then raise exception 'Complete every checklist item; resolve failed items first'; end if;
  if (item->>'requires_photo')::boolean and
    (coalesce(answer->>'photo_path','')='' or not j.evidence_paths ? (answer->>'photo_path'))
   then raise exception 'Required checklist photo is missing'; end if;
 end loop;
end $$;

create function public.change_maintenance_job(p_job uuid,p_revision integer,p_operation uuid,p_action text,p_data jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare w public.work_orders; j public.maintenance_job_records; plan public.asset_service_intervals;
 manager boolean; note text:=btrim(coalesce(p_data->>'note','')); next_state text; session_id uuid;
begin
 if not public.maintenance_can_work_job(p_job) then raise exception 'Access denied'; end if;
 if public.maintenance_replayed(p_operation,p_job,p_action,p_data) then return; end if;
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
   on conflict(work_order_id) do update set cause=excluded.cause,correction=excluded.correction,comments=excluded.comments,updated_at=now();
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
revoke all on function public.maintenance_validate_report(uuid,boolean) from public,anon,authenticated;
revoke all on function public.change_maintenance_job(uuid,integer,uuid,text,jsonb) from public,anon;
grant execute on function public.change_maintenance_job(uuid,integer,uuid,text,jsonb) to authenticated;

create policy component_plans_rpc_only on public.asset_service_intervals as restrictive
 for all to authenticated using(engine_id is null) with check(engine_id is null);

create function public.maintenance_can_plan(p_asset uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.maintenance_can_manage_asset(p_asset) and exists(select 1 from public.profiles p
 where p.id=auth.uid() and (p.role='owner' or exists(select 1 from public.client_capabilities c
 join public.assets a on a.client_id=c.client_id where a.id=p_asset and c.capability_key='maintenance_planning' and c.enabled)))
$$;
create function public.maintenance_workspace()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('assets',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'client_id',a.client_id) order by a.name)
 from public.assets a where public.maintenance_can_view_asset(a.id)),'[]'),
 'asset_types',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.asset_types),'[]'),
 'clients',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name) order by p.full_name)
 from public.profiles p where p.role in ('client','client_admin') and (exists(select 1 from public.profiles me where me.id=auth.uid() and me.role='owner')
 or p.id=auth.uid() or exists(select 1 from public.profiles me join public.client_orgs o on o.id=me.org_id where me.id=auth.uid() and o.owner_profile_id=p.id))),'[]'))
 where auth.uid() is not null
$$;
create function public.maintenance_asset_context(p_asset uuid)
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
 'templates',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name)) from public.checklist_templates t
  where t.checklist_type='pm' and (t.asset_type_id=a.asset_type_id or t.asset_type_id is null)),'[]'),
 'assignees',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'role',p.role) order by p.full_name)
 from public.profiles p where (p.role in ('client','client_admin','client_mechanic') and
   (p.id=a.client_id or exists(select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=a.client_id)))
  or (p.role in ('owner','employee') and exists(select 1 from public.profiles me where me.id=auth.uid() and me.role='owner'))),'[]'))
 into result from public.assets a where a.id=p_asset;
 return result;
end $$;

create function public.save_maintenance_setup(p_operation uuid,p_kind text,p_id uuid,p_revision integer,p_data jsonb)
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
  template:=nullif(p_data->>'checklist_template_id','')::uuid;
  if template is not null and not exists(select 1 from public.checklist_templates t join public.assets asset_row on asset_row.id=asset
    where t.id=template and t.checklist_type='pm' and (t.asset_type_id=asset_row.asset_type_id or t.asset_type_id is null)) then raise exception 'Invalid checklist template'; end if;
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
revoke all on function public.maintenance_can_plan(uuid),public.maintenance_workspace(),
 public.maintenance_asset_context(uuid),public.save_maintenance_setup(uuid,text,uuid,integer,jsonb) from public,anon;
grant execute on function public.maintenance_can_plan(uuid),public.maintenance_workspace(),
 public.maintenance_asset_context(uuid),public.save_maintenance_setup(uuid,text,uuid,integer,jsonb) to authenticated;
