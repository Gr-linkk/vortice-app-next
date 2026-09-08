-- NOW-022: scoped stock and frozen job requirements over existing PM kits.
alter table public.parts_inventory
 add column client_id uuid references public.profiles(id),
 add column unit text not null default 'ea',
 add column average_unit_cost numeric(12,4) not null default 0,
 add column revision integer not null default 0;
update public.parts_inventory set average_unit_cost=coalesce(last_unit_cost,0);
alter table public.work_orders add column parts_kit_captured boolean not null default false;
create table public.job_part_requirements (
 id uuid primary key default gen_random_uuid(),
 work_order_id uuid not null references public.work_orders(id),
 source_requirement_id uuid,
 description text not null check(length(btrim(description)) between 1 and 300),
 part_number text,
 unit text not null default 'ea',
 required_qty numeric(8,2) not null check(required_qty>=0 and required_qty<1000000),
 stock_id uuid references public.parts_inventory(id),
 reserved_qty numeric(8,2) not null default 0 check(reserved_qty>=0),
 used_qty numeric(8,2) not null default 0 check(used_qty>=0),
 revision integer not null default 0,
 unique(work_order_id,source_requirement_id)
);
create table public.parts_purchase_requests (
 id uuid primary key,
 requirement_id uuid not null references public.job_part_requirements(id),
 stock_id uuid not null references public.parts_inventory(id),
 quantity numeric(8,2) not null check(quantity>0 and quantity<1000000),
 received_qty numeric(8,2) not null default 0 check(received_qty>=0 and received_qty<=quantity),
 status text not null default 'requested' check(status in ('requested','ordered','received','cancelled')),
 supplier text not null default '',
 reference text not null default '',
 expected_date date,
 revision integer not null default 0,
 created_at timestamptz not null default now()
);
create table public.parts_stock_events (
 id uuid primary key,
 actor_id uuid not null references public.profiles(id),
 client_id uuid references public.profiles(id),
 work_order_id uuid references public.work_orders(id),
 stock_id uuid references public.parts_inventory(id),
 action text not null,
 payload jsonb not null,
 created_at timestamptz not null default now()
);
alter table public.parts add column stock_requirement_id uuid references public.job_part_requirements(id);
create unique index parts_one_stock_requirement on public.parts(stock_requirement_id);
create index job_parts_stock on public.job_part_requirements(stock_id);
create index job_parts_job on public.job_part_requirements(work_order_id);
alter table public.job_part_requirements enable row level security;
alter table public.parts_purchase_requests enable row level security;
alter table public.parts_stock_events enable row level security;
revoke all on public.job_part_requirements,public.parts_purchase_requests,public.parts_stock_events from public,anon,authenticated;
grant all on public.job_part_requirements,public.parts_purchase_requests,public.parts_stock_events to service_role;
-- Legacy global rows remain provider stock. All inventory writes now use RPCs.
revoke insert,update,delete on public.parts_inventory from authenticated,anon;
create policy parts_inventory_scoped_rpc on public.parts_inventory as restrictive
 for all to authenticated using(false) with check(false);

create function public.parts_job_access(p_job uuid,p_manage boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w join public.profiles p on p.id=auth.uid()
 where w.id=p_job and case when w.managed_maintenance then
 public.maintenance_can_read_job(w.id) and (not p_manage or public.maintenance_can_manage_asset(w.asset_id))
 else p.role='owner' or (not p_manage and p.role='employee' and
 (w.assigned_to=p.id or exists(select 1 from public.work_order_assignments a where a.work_order_id=w.id and a.profile_id=p.id))) end)
$$;
create function public.parts_scope(p_job uuid default null)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare w public.work_orders; p public.profiles; result uuid;
begin
 select * into p from public.profiles where id=auth.uid();
 if p.id is null then raise exception 'Access denied'; end if;
 if p_job is not null then
  if not public.parts_job_access(p_job) then raise exception 'Access denied'; end if;
  select * into w from public.work_orders where id=p_job;
  return case when w.managed_maintenance then w.client_id else null end;
 end if;
 if p.role in ('owner','employee') then return null; end if;
 if p.role not in ('client','client_admin','client_mechanic') then raise exception 'Access denied'; end if;
 select owner_profile_id into result from public.client_orgs where id=p.org_id;
 if result is null and p.role='client' then result:=p.id; end if;
 if result is null then raise exception 'Access denied'; end if;
 return result;
end $$;

create function public.capture_job_parts()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.checklist_template_id is not null and not new.parts_kit_captured then
  insert into public.job_part_requirements(work_order_id,source_requirement_id,description,part_number,unit,required_qty)
  select new.id,r.id,r.description,r.part_number,coalesce(nullif(btrim(r.unit),''),'ea'),r.qty
  from public.pm_parts_requirements r where r.template_id=new.checklist_template_id and r.qty>0;
  update public.work_orders set parts_kit_captured=true where id=new.id;
 end if;
 return new;
end $$;
create trigger capture_job_parts after insert on public.work_orders for each row execute function public.capture_job_parts();

create function public.parts_workspace(p_job uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare scope uuid; manager boolean; w public.work_orders;
begin
 scope:=public.parts_scope(p_job);
 select * into w from public.work_orders where id=p_job;
 manager:=case when p_job is not null then public.parts_job_access(p_job,true)
 else exists(select 1 from public.profiles where id=auth.uid() and role in ('owner','client','client_admin')) end;
 return jsonb_build_object('can_manage',manager,'job_title',w.title,'job_status',w.status,
 'kit_captured',w.parts_kit_captured,'has_kit',w.checklist_template_id is not null,
 'can_change',p_job is null or (w.status not in ('closed','invoiced','cancelled','pending_review') and
 (not w.managed_maintenance or public.maintenance_can_work_job(w.id))),
 'can_issue',w.status in ('in_progress','on_hold'),
 'stock',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('reserved',
 coalesce((select sum(r.reserved_qty) from public.job_part_requirements r where r.stock_id=s.id),0)) order by s.description,s.location)
 from public.parts_inventory s where s.client_id is not distinct from scope),'[]'),
 'requirements',coalesce((select jsonb_agg(to_jsonb(r) order by r.description,r.id) from public.job_part_requirements r where r.work_order_id=p_job),'[]'),
 'purchases',coalesce((select jsonb_agg(to_jsonb(o)||jsonb_build_object('description',r.description,'work_order_id',r.work_order_id) order by o.created_at desc)
 from public.parts_purchase_requests o join public.job_part_requirements r on r.id=o.requirement_id
 join public.parts_inventory s on s.id=o.stock_id where s.client_id is not distinct from scope
 and (p_job is null or r.work_order_id=p_job)),'[]'),
 'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from
 (select e.action,e.created_at,e.payload,p.full_name as actor_name,s.description,s.location
 from public.parts_stock_events e join public.profiles p on p.id=e.actor_id left join public.parts_inventory s on s.id=e.stock_id
 where e.client_id is not distinct from scope and (p_job is null or e.work_order_id=p_job)
 order by e.created_at desc limit 100) e),'[]'));
end $$;

create function public.parts_change(p_job uuid,p_operation uuid,p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare scope uuid; manager boolean; w public.work_orders; r public.job_part_requirements;
 s public.parts_inventory; o public.parts_purchase_requests; previous public.parts_stock_events;
 sid uuid; qty numeric; available numeric; cost numeric; part public.parts; rid uuid;
begin
 scope:=public.parts_scope(p_job);
 if p_operation is null or p_data is null or p_action is null then raise exception 'Invalid operation'; end if;
 -- One scope lock serializes reservations, counts and receipts across jobs.
 perform pg_advisory_xact_lock(hashtextextended('parts:'||coalesce(scope::text,'provider'),0));
 select * into previous from public.parts_stock_events where id=p_operation;
 if found then
  if previous.actor_id<>auth.uid() or previous.work_order_id is distinct from p_job or previous.action<>p_action or previous.payload<>p_data
  then raise exception 'Operation reused with different input'; end if;
  return public.parts_workspace(p_job);
 end if;
 manager:=case when p_job is not null then public.parts_job_access(p_job,true)
 else exists(select 1 from public.profiles where id=auth.uid() and role in ('owner','client','client_admin')) end;
 if p_job is not null then
  select * into w from public.work_orders where id=p_job for update;
  if w.status in ('closed','invoiced','cancelled','pending_review') and p_action not in ('receive','cancel_purchase','stock_create','stock_count','release') then raise exception 'Work is closed or awaiting review'; end if;
  if w.managed_maintenance and not public.maintenance_can_work_job(p_job) then raise exception 'Access denied'; end if;
 end if;
 if not manager and p_action not in ('issue','return','release') then raise exception 'Manager access required'; end if;
 if p_action not in ('stock_create','stock_count') and p_job is null then raise exception 'Open the work order to change its parts'; end if;
 if p_action in ('issue','return') and w.status not in ('in_progress','on_hold') then raise exception 'Start work before recording use'; end if;
 if p_data ? 'requirement_id' then
  select * into r from public.job_part_requirements where id=(p_data->>'requirement_id')::uuid and work_order_id=p_job for update;
  if r.id is null then raise exception 'Requirement unavailable'; end if;
  if r.revision is distinct from (p_data->>'revision')::int then raise exception 'Parts changed. Refresh and try again'; end if;
  sid:=r.stock_id;
 end if;
 if p_data ? 'purchase_id' then
  select x.* into o from public.parts_purchase_requests x join public.job_part_requirements j on j.id=x.requirement_id
  where x.id=(p_data->>'purchase_id')::uuid and j.work_order_id=p_job for update of x;
  if o.id is null then raise exception 'Purchase unavailable'; end if;
  if o.revision is distinct from (p_data->>'revision')::int then raise exception 'Purchase changed. Refresh and try again'; end if;
  sid:=o.stock_id;
 end if;
 if p_action in ('link','stock_count') then sid:=(p_data->>'stock_id')::uuid; end if;
 if sid is not null then
  select * into s from public.parts_inventory where id=sid and client_id is not distinct from scope for update;
  if s.id is null then raise exception 'Stock unavailable'; end if;
  select s.qty_on_hand-coalesce(sum(reserved_qty),0) into available from public.job_part_requirements where stock_id=sid;
 end if;
 if p_data ? 'quantity' then
  qty:=(p_data->>'quantity')::numeric;
  if qty is null or qty<0 or qty>=1000000 or qty<>round(qty,2) or qty='NaN'::numeric then raise exception 'Enter a valid quantity with at most two decimals'; end if;
 end if;
 if p_action in ('reserve','release','request','receive','issue','return') and (qty is null or qty<=0) then raise exception 'Quantity must be positive'; end if;
 if p_action in ('link','requirement_edit','reserve','release','request','issue','return') and r.id is null then raise exception 'Requirement unavailable'; end if;
 if p_action in ('reserve','release','request','receive','issue','return','stock_count') and s.id is null then raise exception 'Choose stock first'; end if;
 if p_action='stock_create' then
  if length(btrim(coalesce(p_data->>'description',''))) not between 1 and 300 or length(btrim(coalesce(p_data->>'location',''))) not between 1 and 120 then raise exception 'Description and location required'; end if;
  cost:=coalesce((p_data->>'unit_cost')::numeric,0);
  if cost<0 or cost>=100000000 or cost='NaN'::numeric then raise exception 'Invalid cost'; end if;
  sid:=p_operation;
  insert into public.parts_inventory(id,client_id,description,part_number,location,unit,qty_on_hand,min_stock_level,last_unit_cost,average_unit_cost)
  values(sid,scope,btrim(p_data->>'description'),nullif(btrim(p_data->>'part_number'),''),btrim(p_data->>'location'),coalesce(nullif(btrim(p_data->>'unit'),''),'ea'),0,0,cost,cost);
 elsif p_action='stock_count' then
  if s.revision is distinct from (p_data->>'revision')::int then raise exception 'Stock changed. Refresh and try again'; end if;
  if qty is null or qty<s.qty_on_hand-available then raise exception 'Count cannot be below reserved stock'; end if;
  if length(btrim(coalesce(p_data->>'note','')))<3 then raise exception 'Explain the stock adjustment'; end if;
  cost:=coalesce((p_data->>'minimum')::numeric,s.min_stock_level,0);
  if cost<0 or cost>=1000000 or cost='NaN'::numeric then raise exception 'Invalid minimum'; end if;
  update public.parts_inventory set qty_on_hand=qty,min_stock_level=cost,revision=revision+1 where id=sid;
 elsif p_action='import_kit' then
  if w.parts_kit_captured then raise exception 'Kit already captured'; end if;
  insert into public.job_part_requirements(work_order_id,source_requirement_id,description,part_number,unit,required_qty)
  select w.id,x.id,x.description,x.part_number,coalesce(nullif(btrim(x.unit),''),'ea'),x.qty from public.pm_parts_requirements x where x.template_id=w.checklist_template_id and x.qty>0;
  update public.work_orders set parts_kit_captured=true where id=w.id;
 elsif p_action='requirement_add' then
  if qty is null or qty<=0 then raise exception 'Quantity must be positive'; end if;
  insert into public.job_part_requirements(id,work_order_id,description,part_number,unit,required_qty)
  values(p_operation,p_job,btrim(p_data->>'description'),nullif(btrim(p_data->>'part_number'),''),coalesce(nullif(btrim(p_data->>'unit'),''),'ea'),qty);
 elsif p_action='requirement_edit' then
  if qty is null or qty<r.reserved_qty+r.used_qty then raise exception 'Release or return parts before reducing requirements'; end if;
  update public.job_part_requirements set required_qty=qty,revision=revision+1 where id=r.id;
 elsif p_action='link' then
  if s.id is null or r.reserved_qty+r.used_qty>0 or exists(select 1 from public.parts_purchase_requests where requirement_id=r.id and status in ('requested','ordered')) then raise exception 'Release parts and finish purchases before changing stock'; end if;
  if lower(s.unit)<>lower(r.unit) then raise exception 'Stock unit must match the requirement'; end if;
  update public.job_part_requirements set stock_id=sid,revision=revision+1 where id=r.id;
 elsif p_action='reserve' then
  if qty>available or qty>r.required_qty-r.reserved_qty-r.used_qty then raise exception 'Not enough available stock or remaining requirement'; end if;
  update public.job_part_requirements set reserved_qty=reserved_qty+qty,revision=revision+1 where id=r.id;
 elsif p_action='release' then
  if qty>r.reserved_qty then raise exception 'Quantity exceeds reservation'; end if;
  update public.job_part_requirements set reserved_qty=reserved_qty-qty,revision=revision+1 where id=r.id;
 elsif p_action='request' then
  if qty>greatest(r.required_qty-r.reserved_qty-r.used_qty-coalesce((select sum(quantity-received_qty) from public.parts_purchase_requests where requirement_id=r.id and status in ('requested','ordered')),0),0) then raise exception 'Quantity exceeds unmet requirement'; end if;
  insert into public.parts_purchase_requests(id,requirement_id,stock_id,quantity) values(p_operation,r.id,sid,qty);
  update public.job_part_requirements set revision=revision+1 where id=r.id;
 elsif p_action='order' then
  if o.id is null or o.status<>'requested' then raise exception 'Purchase must be requested'; end if;
  if length(btrim(coalesce(p_data->>'supplier','')))=0 then raise exception 'Supplier required'; end if;
  update public.parts_purchase_requests set status='ordered',supplier=btrim(p_data->>'supplier'),reference=coalesce(p_data->>'reference',''),expected_date=nullif(p_data->>'expected_date','')::date,revision=revision+1 where id=o.id;
 elsif p_action='cancel_purchase' then
  if o.id is null or o.status not in ('requested','ordered') then raise exception 'Purchase cannot be cancelled'; end if;
  update public.parts_purchase_requests set status='cancelled',revision=revision+1 where id=o.id;
 elsif p_action='receive' then
  if o.id is null or o.status<>'ordered' or qty>o.quantity-o.received_qty then raise exception 'Quantity exceeds outstanding order'; end if;
  cost:=(p_data->>'unit_cost')::numeric;
  if cost is null or cost<0 or cost>=100000000 or cost='NaN'::numeric then raise exception 'Invalid cost'; end if;
  update public.parts_inventory set average_unit_cost=round((qty_on_hand*average_unit_cost+qty*cost)/(qty_on_hand+qty),4),
   qty_on_hand=qty_on_hand+qty,last_unit_cost=cost,revision=revision+1 where id=sid;
  update public.parts_purchase_requests set received_qty=received_qty+qty,status=case when received_qty+qty=quantity then 'received' else 'ordered' end,revision=revision+1 where id=o.id;
 elsif p_action in ('issue','return') then
  if p_action='issue' and (qty>r.reserved_qty or qty>s.qty_on_hand) then raise exception 'Quantity exceeds reserved stock'; end if;
  if p_action='return' and qty>r.used_qty then raise exception 'Quantity exceeds used parts'; end if;
  perform set_config('app.parts_stock_write','on',true);
  select * into part from public.parts where stock_requirement_id=r.id for update;
  if p_action='issue' then
   if part.id is null then
    insert into public.parts(work_order_id,description,part_number,quantity,unit_cost,markup_pct,logged_by,stock_requirement_id)
    values(p_job,s.description,s.part_number,qty,s.average_unit_cost,case when w.managed_maintenance then 0 else 15 end,auth.uid(),r.id);
   else
    update public.parts set unit_cost=round((quantity*unit_cost+qty*s.average_unit_cost)/(quantity+qty),2),quantity=quantity+qty where id=part.id;
   end if;
   update public.parts_inventory set qty_on_hand=qty_on_hand-qty,revision=revision+1 where id=sid;
   update public.job_part_requirements set reserved_qty=reserved_qty-qty,used_qty=used_qty+qty,revision=revision+1 where id=r.id;
  else
   if part.id is null then raise exception 'Used part record unavailable'; end if;
   if part.quantity=qty then delete from public.parts where id=part.id;
   else update public.parts set quantity=quantity-qty where id=part.id; end if;
   update public.parts_inventory set average_unit_cost=round((qty_on_hand*average_unit_cost+qty*part.unit_cost)/(qty_on_hand+qty),4),
    qty_on_hand=qty_on_hand+qty,revision=revision+1 where id=sid;
   update public.job_part_requirements set used_qty=used_qty-qty,revision=revision+1 where id=r.id;
  end if;
  perform set_config('app.parts_stock_write','off',true);
 else raise exception 'Unknown parts action';
 end if;
 insert into public.parts_stock_events(id,actor_id,client_id,work_order_id,stock_id,action,payload)
 values(p_operation,auth.uid(),scope,p_job,sid,p_action,p_data);
 return public.parts_workspace(p_job);
end $$;

create function public.protect_stock_part()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then
  if new.stock_requirement_id is not null and current_setting('app.parts_stock_write',true) is distinct from 'on'
  then raise exception 'Use Parts readiness to record stock-linked parts'; end if;
  return new;
 end if;
 if (old.stock_requirement_id is not null or (tg_op='UPDATE' and new.stock_requirement_id is not null))
 and current_setting('app.parts_stock_write',true) is distinct from 'on' then
 raise exception 'Use Parts readiness to return stock-linked parts'; end if;
 if tg_op='DELETE' then return old; end if; return new;
end $$;
create trigger protect_stock_part before insert or update or delete on public.parts for each row execute function public.protect_stock_part();
-- Finishing or cancelling work returns unused reservations to availability.
-- No stock is consumed implicitly, and outstanding deliveries remain receivable.
create function public.release_finished_job_parts()
returns trigger language plpgsql security definer set search_path='' as $$
declare r public.job_part_requirements;
begin
 if new.status is distinct from old.status and new.status in ('pending_review','closed','invoiced','cancelled') then
  for r in select * from public.job_part_requirements where work_order_id=new.id and reserved_qty>0 for update loop
   update public.job_part_requirements set reserved_qty=0,revision=revision+1 where id=r.id;
   insert into public.parts_stock_events(id,actor_id,client_id,work_order_id,stock_id,action,payload)
   values(gen_random_uuid(),coalesce(auth.uid(),new.created_by),case when new.managed_maintenance then new.client_id else null end,
    new.id,r.stock_id,'release',jsonb_build_object('quantity',r.reserved_qty,'note','Unused reservation released at work review or close'));
  end loop;
 end if;
 return new;
end $$;
create trigger release_finished_job_parts after update of status on public.work_orders for each row execute function public.release_finished_job_parts();

create function public.parts_readiness_summary()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(x.work_order_id,jsonb_build_object('requirements',x.total,'short',x.short,'unreserved',x.unreserved)),'{}')
 from (select r.work_order_id,count(*) as total,
 count(*) filter(where r.required_qty-r.used_qty-r.reserved_qty>greatest(coalesce(s.qty_on_hand,0)-coalesce((select sum(z.reserved_qty) from public.job_part_requirements z where z.stock_id=s.id),0),0)) as short,
 count(*) filter(where r.required_qty>r.used_qty+r.reserved_qty) as unreserved
 from public.job_part_requirements r left join public.parts_inventory s on s.id=r.stock_id
 where public.parts_job_access(r.work_order_id) and r.required_qty>0 group by r.work_order_id) x
$$;
revoke all on function public.parts_job_access(uuid,boolean),public.parts_scope(uuid),public.capture_job_parts(),public.protect_stock_part(),public.release_finished_job_parts(),public.parts_workspace(uuid),public.parts_change(uuid,uuid,text,jsonb),public.parts_readiness_summary() from public,anon;
grant execute on function public.parts_workspace(uuid),public.parts_change(uuid,uuid,text,jsonb) to authenticated;
grant execute on function public.parts_readiness_summary() to authenticated;

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
 'quantity',r.quantity,'unit_cost',r.unit_cost,'stock_requirement_id',r.stock_requirement_id)) from public.parts r where r.work_order_id=w.id),'[]'),
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
