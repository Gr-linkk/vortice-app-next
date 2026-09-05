-- NOW-003. Additive workflow data; existing faults and work-order links survive.
alter table public.maintenance_requests
  add column assigned_to uuid references public.profiles(id),
  add column revision integer not null default 0,
  add column resolution_note text,
  add column resolved_at timestamptz,
  add column resolved_by uuid references public.profiles(id);
alter table public.maintenance_requests drop constraint maintenance_requests_status_check;
alter table public.maintenance_requests add constraint maintenance_requests_status_check
  check (status in ('open','acknowledged','converted','in_progress','pending_review','resolved','dismissed'));
create index maintenance_requests_asset_status_idx on public.maintenance_requests(asset_id,status);
create index maintenance_requests_assigned_idx on public.maintenance_requests(assigned_to);

create table public.maintenance_fault_events (
  id uuid primary key default gen_random_uuid(),
  fault_id uuid not null references public.maintenance_requests(id) on delete cascade,
  asset_id uuid not null references public.assets(id) on delete cascade,
  operation_id uuid not null unique,
  kind text not null,
  payload jsonb not null default '{}'::jsonb,
  from_state text,
  to_state text,
  note text not null,
  actor_id uuid references public.profiles(id) on delete set null,
  actor_name text not null,
  created_at timestamptz not null default now()
);
create index maintenance_fault_events_fault_idx on public.maintenance_fault_events(fault_id,created_at);

create table public.asset_operating_states (
  asset_id uuid primary key references public.assets(id) on delete cascade,
  operating_state text not null check (operating_state in
    ('available','restricted','out_of_service','under_maintenance')),
  reason text not null check (length(btrim(reason)) between 3 and 2000),
  changed_at timestamptz not null default now(),
  changed_by uuid references public.profiles(id) on delete set null,
  changed_by_name text not null,
  unavailable_since timestamptz,
  downtime_seconds bigint not null default 0 check (downtime_seconds >= 0),
  revision integer not null default 1
);
create table public.asset_availability_events (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.assets(id) on delete cascade,
  operation_id uuid not null unique,
  from_state text not null,
  to_state text not null,
  note text not null,
  actor_id uuid references public.profiles(id) on delete set null,
  actor_name text not null,
  created_at timestamptz not null default now()
);
create index asset_availability_events_asset_idx on public.asset_availability_events(asset_id,created_at);

create function public.maintenance_can_view_asset(p_asset_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.assets a join public.profiles p on p.id = auth.uid()
    where a.id = p_asset_id and (
      p.role in ('owner','employee')
      or (p.role in ('client','client_admin') and p.org_id is null and a.client_id = p.id)
      or (p.role in ('client','client_admin','client_mechanic','operator','client_operator')
        and exists (select 1 from public.client_orgs o
          where o.id = p.org_id and o.owner_profile_id = a.client_id))
    )
  );
$$;
create function public.maintenance_can_manage_asset(p_asset_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.maintenance_can_view_asset(p_asset_id) and exists (
    select 1 from public.profiles where id=auth.uid() and role in ('owner','client','client_admin')
  );
$$;

-- All mutations go through transactional, checked RPCs. In particular, an
-- operator can no longer update arbitrary columns of a self-reported fault.
drop policy "Client reads own asset requests" on public.maintenance_requests;
drop policy "Operator manages own" on public.maintenance_requests;
drop policy "Org members see org asset flags" on public.maintenance_requests;
drop policy "Owner full access" on public.maintenance_requests;
create policy maintenance_fault_read on public.maintenance_requests for select to authenticated
  using (public.maintenance_can_view_asset(asset_id));
revoke insert,update,delete on public.maintenance_requests from public,anon,authenticated;
grant select on public.maintenance_requests to authenticated;

alter table public.maintenance_fault_events enable row level security;
alter table public.asset_operating_states enable row level security;
alter table public.asset_availability_events enable row level security;
create policy maintenance_event_read on public.maintenance_fault_events for select to authenticated
  using (public.maintenance_can_view_asset(asset_id));
create policy availability_read on public.asset_operating_states for select to authenticated
  using (public.maintenance_can_view_asset(asset_id));
create policy availability_event_read on public.asset_availability_events for select to authenticated
  using (public.maintenance_can_view_asset(asset_id));
revoke all on public.maintenance_fault_events,public.asset_operating_states,
  public.asset_availability_events from public,anon,authenticated;
grant select on public.maintenance_fault_events,public.asset_operating_states,
  public.asset_availability_events to authenticated;
grant all on public.maintenance_fault_events,public.asset_operating_states,
  public.asset_availability_events to service_role;

insert into public.maintenance_fault_events(fault_id,asset_id,operation_id,kind,
  to_state,note,actor_id,actor_name,created_at)
select f.id,f.asset_id,f.id,'reported',f.status,f.description,f.flagged_by,
  coalesce(p.full_name,'Previous reporter'),coalesce(f.created_at,now())
from public.maintenance_requests f left join public.profiles p on p.id=f.flagged_by;

-- Read summaries deliberately expose no billing fields, email or internal WO notes.
create function public.maintenance_fleet()
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',a.id,'name',a.name,'location',a.location,
    'operating_state',coalesce(s.operating_state,'unknown'),'reason',s.reason,
    'changed_at',s.changed_at,'changed_by_name',s.changed_by_name,
    'unavailable_since',s.unavailable_since,'downtime_seconds',coalesce(s.downtime_seconds,0),
    'revision',coalesce(s.revision,0),'open_faults',
    (select count(*) from public.maintenance_requests f where f.asset_id=a.id
      and f.status not in ('resolved','dismissed')),
    'urgent_faults',(select count(*) from public.maintenance_requests f where f.asset_id=a.id
      and f.status not in ('resolved','dismissed') and f.severity='urgent'))
  from public.assets a left join public.asset_operating_states s on s.asset_id=a.id
  where public.maintenance_can_view_asset(a.id) order by a.name,a.id;
$$;
create function public.maintenance_faults(p_asset_id uuid default null,p_fault_id uuid default null)
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(f) || jsonb_build_object('asset_name',a.name,
    'assignee_name',assignee.full_name,'reporter_name',reporter.full_name,'work_order_status',w.status)
  from public.maintenance_requests f
  join public.assets a on a.id=f.asset_id
  left join public.profiles assignee on assignee.id=f.assigned_to
  left join public.profiles reporter on reporter.id=f.flagged_by
  left join public.work_orders w on w.id=f.converted_to_work_order_id
  where public.maintenance_can_view_asset(f.asset_id)
    and (p_asset_id is null or f.asset_id=p_asset_id)
    and (p_fault_id is null or f.id=p_fault_id)
  order by (f.status not in ('resolved','dismissed')) desc,
    (f.severity='urgent') desc,f.updated_at desc,f.id;
$$;
create function public.maintenance_assignees(p_asset_id uuid)
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',p.id,'full_name',p.full_name,'role',p.role)
  from public.profiles p join public.assets a on a.id=p_asset_id
  where public.maintenance_can_manage_asset(a.id) and (
    ((select role from public.profiles where id=auth.uid())='owner' and p.role in ('owner','employee'))
    or (p.role in ('client','client_admin','client_mechanic') and (
      (p.org_id is null and p.id=a.client_id and p.role in ('client','client_admin'))
      or exists(select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=a.client_id)
    ))
  ) order by p.full_name,p.id;
$$;

create function public.report_maintenance_fault(p_request_id uuid,p_asset_id uuid,
  p_description text,p_severity text default 'normal')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_asset public.assets; v_fault public.maintenance_requests; v_actor text;
begin
  if not public.maintenance_can_view_asset(p_asset_id) then
    raise exception 'Access denied' using errcode='42501'; end if;
  if p_request_id is null or p_severity is null or p_severity not in ('normal','urgent')
    or p_description is null or length(btrim(p_description)) not between 3 and 4000 then
    raise exception 'A description of 3 to 4000 characters and valid severity are required'; end if;
  select * into v_asset from public.assets where id=p_asset_id for update;
  select * into v_fault from public.maintenance_requests where id=p_request_id;
  if found then
    if v_fault.flagged_by=auth.uid() and v_fault.asset_id=p_asset_id
      and v_fault.description=btrim(p_description) and v_fault.severity=p_severity then
      return v_fault.id;
    end if;
    raise exception 'This report identifier was already used; refresh and try again';
  end if;
  select full_name into v_actor from public.profiles where id=auth.uid();
  insert into public.maintenance_requests(id,asset_id,client_id,flagged_by,description,severity,status)
    values(p_request_id,p_asset_id,v_asset.client_id,auth.uid(),btrim(p_description),p_severity,'open');
  insert into public.maintenance_fault_events(fault_id,asset_id,operation_id,kind,to_state,note,actor_id,actor_name)
    values(p_request_id,p_asset_id,p_request_id,'reported','open',btrim(p_description),auth.uid(),v_actor);
  return p_request_id;
end $$;

create function public.update_maintenance_fault(p_fault_id uuid,p_expected_revision integer,
  p_operation_id uuid,p_action text,p_note text,p_assigned_to uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_fault public.maintenance_requests; v_asset_id uuid; v_manager boolean;
  v_worker boolean; v_role text; v_actor text; v_next text; v_note text;
  v_assignee_name text; v_assignee_role text; v_job uuid; v_payload jsonb; v_previous_payload jsonb;
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
      v_next := 'open';
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

create function public.change_asset_availability(p_asset_id uuid,p_expected_revision integer,
  p_operation_id uuid,p_state text,p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_previous public.asset_operating_states; v_actor text; v_old_state text;
  v_event public.asset_availability_events;
  v_since timestamptz; v_total bigint; v_down boolean;
begin
  if not public.maintenance_can_manage_asset(p_asset_id) then
    raise exception 'Access denied: manager required' using errcode='42501'; end if;
  perform 1 from public.assets where id=p_asset_id for update;
  if p_operation_id is null then raise exception 'Missing operation identifier'; end if;
  select * into v_event from public.asset_availability_events where operation_id=p_operation_id
    and asset_id=p_asset_id and actor_id=auth.uid();
  if found then
    if v_event.to_state=p_state and v_event.note=btrim(p_reason) then return p_asset_id; end if;
    raise exception 'This operation was already used. Refresh before saving again' using errcode='40001';
  end if;
  select * into v_previous from public.asset_operating_states where asset_id=p_asset_id for update;
  if p_expected_revision is distinct from coalesce(v_previous.revision,0) then
    raise exception 'Availability changed. Refresh before saving again' using errcode='40001'; end if;
  if p_state is null or p_state not in ('available','restricted','out_of_service','under_maintenance')
    or p_reason is null or length(btrim(p_reason)) not between 3 and 2000 then
    raise exception 'Choose a valid state and enter a reason of 3 to 2000 characters'; end if;
  if p_state='available' and exists(select 1 from public.maintenance_requests
    where asset_id=p_asset_id and severity='urgent' and status not in ('resolved','dismissed')) then
    raise exception 'Resolve or dismiss urgent faults before returning this asset to Available'; end if;
  v_old_state := coalesce(v_previous.operating_state,'unknown');
  v_since := v_previous.unavailable_since;
  v_total := coalesce(v_previous.downtime_seconds,0);
  v_down := p_state in ('out_of_service','under_maintenance');
  if v_down and v_since is null then v_since := now();
  elsif not v_down and v_since is not null then
    v_total := v_total + greatest(0,floor(extract(epoch from now()-v_since)))::bigint;
    v_since := null;
  end if;
  select full_name into v_actor from public.profiles where id=auth.uid();
  insert into public.asset_operating_states(asset_id,operating_state,reason,changed_at,
    changed_by,changed_by_name,unavailable_since,downtime_seconds,revision)
    values(p_asset_id,p_state,btrim(p_reason),now(),auth.uid(),v_actor,v_since,v_total,
      coalesce(v_previous.revision,0)+1)
  on conflict(asset_id) do update set operating_state=excluded.operating_state,
    reason=excluded.reason,changed_at=excluded.changed_at,changed_by=excluded.changed_by,
    changed_by_name=excluded.changed_by_name,unavailable_since=excluded.unavailable_since,
    downtime_seconds=excluded.downtime_seconds,revision=excluded.revision;
  insert into public.asset_availability_events(asset_id,operation_id,from_state,to_state,note,actor_id,actor_name)
    values(p_asset_id,p_operation_id,v_old_state,p_state,btrim(p_reason),auth.uid(),v_actor);
  return p_asset_id;
end $$;

revoke all on function public.maintenance_can_view_asset(uuid),
  public.maintenance_can_manage_asset(uuid),public.maintenance_fleet(),
  public.maintenance_faults(uuid,uuid),public.maintenance_assignees(uuid),
  public.report_maintenance_fault(uuid,uuid,text,text),
  public.update_maintenance_fault(uuid,integer,uuid,text,text,uuid),
  public.change_asset_availability(uuid,integer,uuid,text,text) from public,anon;
grant execute on function public.maintenance_can_view_asset(uuid),
  public.maintenance_can_manage_asset(uuid),public.maintenance_fleet(),
  public.maintenance_faults(uuid,uuid),public.maintenance_assignees(uuid),
  public.report_maintenance_fault(uuid,uuid,text,text),
  public.update_maintenance_fault(uuid,integer,uuid,text,text,uuid),
  public.change_asset_availability(uuid,integer,uuid,text,text) to authenticated;
