-- NEXT-002.15: unit-tagged readings, without rewriting historical values.
-- Legacy *_hours column names remain API compatibility storage. Their physical
-- unit is explicit and frozen on execution/history records; no stored conversion.
alter table public.assets add column meter_unit text not null default 'hours'
 check(meter_unit in ('hours','km','mi'));
alter table public.assets add column primary_meter_engine_id uuid references public.asset_engines(id);
alter table public.asset_engines add column meter_unit text not null default 'hours'
 check(meter_unit in ('hours','km','mi'));
alter table public.work_orders add column meter_unit text not null default 'hours'
 check(meter_unit in ('hours','km','mi'));
alter table public.hour_logs add column meter_unit text not null default 'hours'
 check(meter_unit in ('hours','km','mi'));
alter table public.service_reports add column meter_unit text not null default 'hours'
 check(meter_unit in ('hours','km','mi'));
alter table public.saved_checklists add column meter_unit text not null default 'hours'
 check(meter_unit in ('hours','km','mi'));
alter table public.service_reminders add column meter_unit text not null default 'hours'
 check(meter_unit in ('hours','km','mi'));
alter table public.maintenance_job_records add column meter_applied_at timestamptz;

create function public.meter_identity_guard() returns trigger language plpgsql set search_path='' as $$
declare meter public.asset_engines; unit text;
begin
 if tg_table_name='asset_engines' then
  if tg_op='UPDATE' and new.meter_unit is distinct from old.meter_unit and
    (coalesce(old.current_hours,0)<>0 or old.meter_captured_at is not null
     or exists(select 1 from public.hour_logs where engine_id=old.id)
     or exists(select 1 from public.asset_service_intervals where engine_id=old.id)
     or exists(select 1 from public.work_orders where engine_id=old.id)) then
   raise exception 'Recorded meter units cannot change; add a separate meter';
  end if;
  if new.meter_unit<>'hours' and new.telemetry_channel is not null then
   raise exception 'Hour telemetry cannot supply a distance meter';
  end if;
 elsif tg_table_name='assets' then
  if tg_op='UPDATE' and old.primary_meter_engine_id is not null and
    (new.primary_meter_engine_id is distinct from old.primary_meter_engine_id or new.meter_unit is distinct from old.meter_unit) then
   raise exception 'The primary meter is recorded; its identity and unit cannot change';
  end if;
  if new.primary_meter_engine_id is not null then
   select * into meter from public.asset_engines where id=new.primary_meter_engine_id;
   if meter.asset_id is distinct from new.id or meter.meter_unit is distinct from new.meter_unit then
    raise exception 'Select a matching meter of this asset';
   end if;
  end if;
 elsif tg_table_name='work_orders' then
  select coalesce(e.meter_unit,a.meter_unit) into unit from public.assets a
   left join public.asset_engines e on e.id=coalesce(new.engine_id,a.primary_meter_engine_id) and e.asset_id=a.id
   where a.id=new.asset_id;
  if tg_op='INSERT' then new.meter_unit:=coalesce(unit,'hours');
  elsif new.meter_unit is distinct from old.meter_unit or (new.engine_id is distinct from old.engine_id and unit is distinct from old.meter_unit) then
   raise exception 'Work meter units are frozen; create separate work for another unit';
  end if;
 end if;
 return new;
end $$;
create trigger meter_engine_identity before insert or update on public.asset_engines
 for each row execute function public.meter_identity_guard();
create trigger meter_asset_identity before insert or update on public.assets
 for each row execute function public.meter_identity_guard();
create trigger meter_work_identity before insert or update on public.work_orders
 for each row execute function public.meter_identity_guard();

create function public.meter_history_snapshot() returns trigger language plpgsql set search_path='' as $$
declare unit text;
begin
 if tg_op='UPDATE' then
  if new.meter_unit is distinct from old.meter_unit then raise exception 'Historical meter units cannot change'; end if;
  return new;
 end if;
 if tg_table_name='hour_logs' or tg_table_name='service_reminders' then
  select meter_unit into unit from public.asset_engines where id=new.engine_id;
 else
  select meter_unit into unit from public.work_orders where id=new.work_order_id;
 end if;
 if unit is null and tg_table_name in ('hour_logs','saved_checklists') then
  select meter_unit into unit from public.assets where id=new.asset_id;
 end if;
 new.meter_unit:=coalesce(unit,'hours');
 if tg_table_name='saved_checklists' then
  new.snapshot:=jsonb_set(coalesce(new.snapshot,'{}'),'{meter_unit}',to_jsonb(new.meter_unit));
  if jsonb_typeof(new.snapshot->'header')='object' then
   new.snapshot:=jsonb_set(new.snapshot,'{header,meter_unit}',to_jsonb(new.meter_unit));
  end if;
 end if;
 return new;
end $$;
create trigger meter_log_snapshot before insert or update on public.hour_logs for each row execute function public.meter_history_snapshot();
create trigger meter_report_snapshot before insert or update on public.service_reports for each row execute function public.meter_history_snapshot();
create trigger meter_checklist_snapshot before insert or update on public.saved_checklists for each row execute function public.meter_history_snapshot();
create trigger meter_reminder_snapshot before insert or update on public.service_reminders for each row execute function public.meter_history_snapshot();

create function public.record_component_meter(p_operation uuid,p_engine uuid,p_asset uuid,p_value numeric,
 p_unit text,p_captured_at timestamptz,p_notes text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare e public.asset_engines; receipt public.closeout_operations;
 payload jsonb:=jsonb_build_object('engine',p_engine,'asset',p_asset,'value',p_value,'unit',p_unit,'captured_at',p_captured_at,'notes',p_notes);
begin
 if auth.uid() is null or not public.maintenance_can_view_asset(p_asset) then raise exception 'Asset access required'; end if;
 if p_operation is null then raise exception 'Operation identity is required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
  if receipt.actor_id<>auth.uid() or receipt.kind<>'component_meter' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
  return receipt.result;
 end if;
 select * into e from public.asset_engines where id=p_engine and asset_id=p_asset for update;
 if not found then raise exception 'Component unavailable'; end if;
 if p_unit is distinct from e.meter_unit then raise exception 'Meter unit changed; refresh before recording'; end if;
 if p_value is null or p_value<0 or p_value>=1000000000 or p_value='NaN'::numeric then raise exception 'Invalid meter reading'; end if;
 if p_captured_at is null or not isfinite(p_captured_at) or p_captured_at>now()+interval '5 minutes' then raise exception 'Invalid reading time'; end if;
 if p_value<coalesce(e.current_hours,0) or p_captured_at<e.meter_captured_at then
  raise exception 'A newer meter reading was accepted. Refresh and correct this submission';
 end if;
 insert into public.hour_logs(id,engine_id,asset_id,hours,meter_unit,logged_by,logged_at,source,notes)
 values(p_operation,p_engine,p_asset,p_value,p_unit,auth.uid(),p_captured_at,'manual',p_notes);
 update public.asset_engines set current_hours=p_value,meter_captured_at=p_captured_at,
  maintenance_revision=maintenance_revision+1 where id=p_engine;
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'component_meter',payload,p_operation);
 return p_operation;
end $$;
revoke all on function public.record_component_meter(uuid,uuid,uuid,numeric,text,timestamptz,text) from public,anon;
grant execute on function public.record_component_meter(uuid,uuid,uuid,numeric,text,timestamptz,text) to authenticated;

create function public.configure_asset_meter(p_asset uuid,p_operation uuid,p_unit text,p_value numeric) returns uuid
language plpgsql security definer set search_path='' as $$
declare a public.assets; meter uuid; payload jsonb:=jsonb_build_object('unit',p_unit,'value',p_value);
begin
 if auth.uid() is null or not public.maintenance_can_manage_asset(p_asset) then raise exception 'Access denied'; end if;
 if p_operation is null or p_unit is null or p_unit not in ('hours','km','mi') then raise exception 'Choose a supported meter unit'; end if;
 select * into a from public.assets where id=p_asset for update;
 if public.maintenance_replayed(p_operation,p_asset,'configure_meter',payload) then return a.primary_meter_engine_id; end if;
 meter:=a.primary_meter_engine_id;
 if meter is null then
  meter:=gen_random_uuid();
  insert into public.asset_engines(id,asset_id,label,kind,current_hours,meter_unit)
   values(meter,p_asset,'Asset meter','other',0,p_unit);
  update public.assets set primary_meter_engine_id=meter,meter_unit=p_unit,maintenance_revision=maintenance_revision+1 where id=p_asset;
 elsif a.meter_unit is distinct from p_unit then raise exception 'Recorded meter units cannot change; add a separate meter';
 end if;
 perform public.record_component_meter(p_operation,meter,p_asset,p_value,p_unit,clock_timestamp(),'Primary asset meter');
 perform public.maintenance_record_operation(p_operation,p_asset,'configure_meter',payload);
 return meter;
end $$;
revoke all on function public.configure_asset_meter(uuid,uuid,text,numeric) from public,anon;
grant execute on function public.configure_asset_meter(uuid,uuid,text,numeric) to authenticated;
create function public.snapshot_history_meter_unit() returns trigger language plpgsql security definer set search_path='' as $$
declare unit text;
begin
 if not new.detail ?| array['hours','current_hours','interval_hours','last_service_hours','next_due_hours'] then return new; end if;
 if new.job_id is not null then select meter_unit into unit from public.work_orders where id=new.job_id;
 elsif new.source_type='asset_engines' then select meter_unit into unit from public.asset_engines where id=new.source_id;
 elsif new.source_type='hour_logs' then select meter_unit into unit from public.hour_logs where id=new.source_id;
 elsif new.source_type='asset_service_intervals' then select e.meter_unit into unit from public.asset_service_intervals p join public.asset_engines e on e.id=p.engine_id where p.id=new.source_id;
 end if;
 if unit is null then select meter_unit into unit from public.assets where id=new.asset_id; end if;
 new.detail:=new.detail||jsonb_build_object('meter_unit',coalesce(unit,'hours'));
 return new;
end $$;
revoke all on function public.snapshot_history_meter_unit() from public,anon,authenticated;
create trigger snapshot_history_meter_unit before insert on public.asset_history_entries for each row execute function public.snapshot_history_meter_unit();


-- Meter-aware existing interfaces. Existing grants and checked lifecycle are retained.

create or replace function public.record_manual_meter(p_operation uuid,p_engine uuid,p_asset uuid,p_hours numeric,
 p_captured_at timestamptz,p_notes text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare e public.asset_engines; receipt public.closeout_operations;
 payload jsonb:=jsonb_build_object('engine',p_engine,'asset',p_asset,'hours',p_hours,'captured_at',p_captured_at,'notes',p_notes);
begin
 if auth.uid() is null or not public.maintenance_can_view_asset(p_asset) then raise exception 'Asset access required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
   if receipt.actor_id<>auth.uid() or receipt.kind<>'meter' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
   return receipt.result;
 end if;
 select * into e from public.asset_engines where id=p_engine and asset_id=p_asset for update;
 if not found then raise exception 'Component unavailable'; end if;
 if e.meter_unit<>'hours' then raise exception 'Use unit-aware meter capture for distance readings'; end if;
 if p_hours is null or p_hours<0 or p_hours>=1000000000 or p_hours='NaN'::numeric then raise exception 'Invalid meter reading'; end if;
 if p_captured_at is null or p_captured_at>now()+interval '5 minutes' then raise exception 'Invalid reading time'; end if;
 if p_hours<coalesce(e.current_hours,0) or p_captured_at<e.meter_captured_at then
   raise exception 'A newer meter reading was accepted. Refresh and correct this submission';
 end if;
 insert into public.hour_logs(id,engine_id,asset_id,hours,logged_by,logged_at,source,notes)
 values(p_operation,p_engine,p_asset,p_hours,auth.uid(),p_captured_at,'manual',p_notes);
 update public.asset_engines set current_hours=p_hours,meter_captured_at=p_captured_at,
 maintenance_revision=maintenance_revision+1 where id=p_engine;
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'meter',payload,p_operation);
 return p_operation;
end $$;

create or replace function public.save_maintenance_setup(p_operation uuid,p_kind text,p_id uuid,p_revision integer,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.assets; e public.asset_engines; plan public.asset_service_intervals;
 client uuid; asset uuid; component uuid; me public.profiles; template uuid; interval_value integer; baseline numeric;
 mode text; months integer; first_hours numeric; first_date date; service_date date; covers uuid[]; covered uuid;
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
   insert into public.asset_engines(id,asset_id,label,kind,current_hours,meter_unit)
    values(p_id,asset,btrim(p_data->>'label'),coalesce(p_data->>'kind','engine'),coalesce((p_data->>'current_hours')::numeric,0),coalesce(p_data->>'meter_unit',(select meter_unit from public.assets where id=asset),'hours'));
  else
   if p_data ? 'meter_unit' and p_data->>'meter_unit' is distinct from e.meter_unit then raise exception 'Recorded meter units cannot change; add a separate meter'; end if;
   -- Meter corrections belong to the existing meter/history workflow, not rename.
   update public.asset_engines set label=btrim(p_data->>'label'),maintenance_revision=maintenance_revision+1 where id=p_id;
  end if;
 elsif p_kind='plan' then
  perform 1 from public.assets where id=coalesce((select asset_id from public.asset_service_intervals where id=p_id),(p_data->>'asset_id')::uuid) for update;
  select * into plan from public.asset_service_intervals where id=p_id for update;
  asset:=coalesce(plan.asset_id,(p_data->>'asset_id')::uuid);
  if not public.maintenance_can_plan(asset) then raise exception 'Access denied'; end if;
  if plan.id is not null and plan.revision is distinct from p_revision then raise exception 'Plan changed; refresh' using errcode='40001'; end if;
  if exists(select 1 from public.work_orders w join public.maintenance_job_records j on j.id=w.id
   where (j.service_interval_id=p_id or p_id=any(j.covered_plan_ids)) and w.status<>'closed') then raise exception 'Finish the open job before changing this plan'; end if;
  component:=(p_data->>'engine_id')::uuid;
  if not exists(select 1 from public.asset_engines where id=component and asset_id=asset) then raise exception 'Select a component of this asset'; end if;
  if plan.engine_id is not null and plan.engine_id<>component then raise exception 'Create a separate plan for another component'; end if;
  template:=public.checklist_current_template(nullif(p_data->>'checklist_template_id','')::uuid);
  if template is not null and not public.checklist_template_usable(template,asset,component,'pm') then raise exception 'Invalid checklist template'; end if;
  interval_value:=coalesce(nullif(p_data->>'interval_hours','')::integer,0);
  baseline:=coalesce(nullif(p_data->>'last_service_hours','')::numeric,0);
  mode:=coalesce(p_data->>'recurrence_mode',plan.recurrence_mode,'completion');
  months:=case when p_data ? 'interval_months' then nullif(p_data->>'interval_months','')::integer else plan.interval_months end;
  service_date:=coalesce(nullif(p_data->>'last_service_date','')::date,plan.last_service_date);
  first_hours:=nullif(p_data->>'anchor_hours','')::numeric;
  first_date:=nullif(p_data->>'anchor_date','')::date;
  select coalesce(array_agg(distinct value::uuid),'{}') into covers
   from jsonb_array_elements_text(coalesce(p_data->'covers_plan_ids',to_jsonb(plan.covers_plan_ids),'[]'));
  if interval_value<0 or interval_value>10000000 or (interval_value=0 and months is null)
    or baseline<0 or baseline>=1000000000 or mode not in ('completion','fixed')
    or (months is not null and months not between 1 and 120)
   then raise exception 'Enter a valid meter or calendar interval'; end if;
  if plan.id is not null and plan.last_service_hours is not null and baseline<>plan.last_service_hours
   then raise exception 'Service baseline changes only through approved completion'; end if;
  if service_date>current_date then raise exception 'Last service date cannot be in the future'; end if;
  if plan.last_service_date is not null and service_date is distinct from plan.last_service_date
   then raise exception 'Service date changes only through approved completion'; end if;
  if mode='fixed' then
   -- Keeping an unchanged anchor preserves the current occurrence when editing names or checklists.
   if interval_value>0 then
    first_hours:=coalesce(first_hours,plan.anchor_hours);
    if first_hours is null or first_hours<0 or first_hours>=1000000000 then raise exception 'Choose the first meter target'; end if;
   end if;
   if months is not null then
    first_date:=coalesce(first_date,plan.anchor_date);
    if first_date is null then raise exception 'Choose the first date target'; end if;
   end if;
  elsif months is not null and service_date is null then raise exception 'Enter the last service date';
  end if;
  if plan.id is not null and (mode is distinct from plan.recurrence_mode or interval_value<>plan.interval_hours
    or months is distinct from plan.interval_months or first_hours is distinct from plan.anchor_hours
    or first_date is distinct from plan.anchor_date or covers is distinct from plan.covers_plan_ids)
    and length(btrim(coalesce(p_data->>'change_reason','')))<3 then raise exception 'Explain the schedule adjustment'; end if;
  -- Deliberately flat coverage: no hidden transitive tasks or circular service packages.
  if cardinality(covers)>20 or p_id=any(covers) then raise exception 'Invalid service coverage'; end if;
  if cardinality(covers)>0 and exists(select 1 from public.asset_service_intervals where p_id=any(covers_plan_ids))
    then raise exception 'A covered plan cannot cover other plans'; end if;
  foreach covered in array covers loop
   if not exists(select 1 from public.asset_service_intervals where id=covered and asset_id=asset and engine_id=component
     and is_active and cardinality(covers_plan_ids)=0) then raise exception 'Choose active uncovered plans on this component'; end if;
   if exists(select 1 from public.maintenance_job_records j join public.work_orders w on w.id=j.id
    where (j.service_interval_id=covered or covered=any(j.covered_plan_ids)) and w.status<>'closed')
    then raise exception 'Finish the open covered job first'; end if;
  end loop;
  insert into public.asset_service_intervals(id,asset_id,engine_id,interval_label,interval_hours,checklist_template_id,
    last_service_hours,next_due_hours,is_active,recurrence_mode,interval_months,anchor_hours,anchor_date,last_service_date,next_due_date,covers_plan_ids)
   values(p_id,asset,component,p_data->>'interval_label',interval_value,template,baseline,
    case when interval_value=0 then null when mode='completion' then baseline+interval_value
     when plan.recurrence_mode='fixed' and first_hours=plan.anchor_hours then
      case when interval_value=plan.interval_hours then plan.next_due_hours
       else public.maintenance_next_hours(baseline,interval_value,mode,first_hours) end
     else first_hours end,
    coalesce((p_data->>'is_active')::boolean,true),mode,months,case when mode='fixed' and interval_value>0 then first_hours end,
    case when mode='fixed' and months is not null then first_date end,service_date,
    case when months is null then null when mode='completion' then public.maintenance_next_date(service_date,months,mode,null)
     when plan.recurrence_mode='fixed' and first_date=plan.anchor_date then
      case when months=plan.interval_months then plan.next_due_date
       else public.maintenance_next_date(coalesce(service_date,first_date-1),months,mode,first_date) end
     else first_date end,covers)
   on conflict(id) do update set interval_label=excluded.interval_label,engine_id=excluded.engine_id,
    interval_hours=excluded.interval_hours,checklist_template_id=excluded.checklist_template_id,
    last_service_hours=excluded.last_service_hours,next_due_hours=excluded.next_due_hours,is_active=excluded.is_active,
    recurrence_mode=excluded.recurrence_mode,interval_months=excluded.interval_months,anchor_hours=excluded.anchor_hours,
    anchor_date=excluded.anchor_date,last_service_date=excluded.last_service_date,next_due_date=excluded.next_due_date,
    covers_plan_ids=excluded.covers_plan_ids,revision=public.asset_service_intervals.revision+1;
  perform public.maintenance_sync_plan_reminder(p_id);
 else raise exception 'Unknown setup action';
 end if;
 perform public.maintenance_record_operation(p_operation,p_id,'setup_'||p_kind,p_data);
 return p_id;
end $$;

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
 perform 1 from public.assets where id=a.id for update;
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
 component:=coalesce(nullif(p_data->>'engine_id','')::uuid,a.primary_meter_engine_id);
 if component is not null and not exists(select 1 from public.asset_engines where id=component and asset_id=a.id)
  then raise exception 'Component belongs to another asset'; end if;
 if nullif(p_data->>'service_interval_id','') is not null then
  if not public.maintenance_can_plan(a.id) then raise exception 'Maintenance planning is disabled'; end if;
  select * into plan from public.asset_service_intervals where id=(p_data->>'service_interval_id')::uuid for update;
  if plan.id is null or plan.asset_id<>a.id or not plan.is_active or plan.engine_id is null
   then raise exception 'Select an active component maintenance plan'; end if;
  if exists(select 1 from public.maintenance_job_records j join public.work_orders w on w.id=j.id
    where (j.service_interval_id=plan.id or plan.id=any(j.covered_plan_ids) or j.service_interval_id=any(plan.covers_plan_ids) or j.covered_plan_ids && plan.covers_plan_ids) and w.status<>'closed') then raise exception 'This plan already has an open job'; end if;
  component:=plan.engine_id; template:=plan.checklist_template_id;
 else template:=nullif(p_data->>'checklist_template_id','')::uuid;
 end if;
 if plan.id is not null then template:=public.checklist_current_template(template); end if;
 if template is not null then
  if not public.checklist_template_usable(template,a.id,component,'pm') then raise exception 'Invalid checklist template'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'description_en',description_en,
    'description_es',description_es,'requires_photo',requires_photo,'category',category,'definition',definition,'template_id',template_id) order by sort_order,id),'[]')
    into snapshot from public.checklist_items where template_id=template;
 end if;
 if cardinality(plan.covers_plan_ids)>0 then
  perform 1 from public.asset_service_intervals where id=any(plan.covers_plan_ids) order by id for update;
  if exists(select 1 from public.asset_service_intervals where id=any(plan.covers_plan_ids)
    and (not is_active or asset_id<>a.id or engine_id is distinct from component)) then raise exception 'Invalid covered plan'; end if;
  select coalesce(jsonb_agg(item order by item->>'id'),'[]') into snapshot from (
   select distinct item from (
    select value item from jsonb_array_elements(snapshot)
    union all
    select jsonb_build_object('id',i.id,'description_en',i.description_en,'description_es',i.description_es,
     'requires_photo',i.requires_photo,'category',i.category,'definition',i.definition,'template_id',i.template_id)
    from public.asset_service_intervals cp join public.checklist_items i
     on i.template_id=public.checklist_current_template(cp.checklist_template_id)
    where cp.id=any(plan.covers_plan_ids)
   ) all_items
  ) unique_items;
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
 insert into public.maintenance_job_records(id,priority,service_interval_id,parent_job_id,checklist_snapshot,hourly_cost,expected_materials,covered_plan_ids)
 values(p_request,coalesce(p_data->>'priority','normal'),plan.id,parent.id,snapshot,coalesce((p_data->>'hourly_cost')::numeric,0),materials,coalesce(plan.covers_plan_ids,'{}'));
 update public.work_orders set hours_at_start=(select current_hours from public.asset_engines where id=component) where id=p_request;
 perform public.maintenance_record_operation(p_request,p_request,'created',p_data);
 return p_request;
end $$;

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
  if w.started_at is null and w.engine_id is not null then
   if p_data ? 'meter_unit' and p_data->>'meter_unit' is distinct from w.meter_unit then raise exception 'Meter unit changed; refresh before starting'; end if;
   if w.meter_unit<>'hours' and (p_data->>'meter_unit' is distinct from w.meter_unit or nullif(p_data->>'start_meter','') is null) then raise exception 'Enter the starting meter in the work unit'; end if;
   if nullif(p_data->>'start_meter','') is not null then
    perform public.record_component_meter(p_operation,w.engine_id,w.asset_id,(p_data->>'start_meter')::numeric,w.meter_unit,clock_timestamp(),'Work start');
   end if;
   update public.work_orders set hours_at_start=(select current_hours from public.asset_engines where id=w.engine_id) where id=p_job;
  end if;
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
  if (p_data ? 'meter_unit' or w.meter_unit<>'hours') and p_data->>'meter_unit' is distinct from w.meter_unit then
   raise exception 'Meter unit changed; reopen the work before entering readings';
  end if;
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
    -- The asset lock above also serializes concurrent creation and reopening.
    -- Reserve the original job's frozen coverage, even if its plan was edited.
    perform 1 from public.asset_service_intervals
     where id=j.service_interval_id or id=any(j.covered_plan_ids) order by id for update;
  end if;
  if j.service_interval_id is not null and exists(select 1 from public.maintenance_job_records other
    join public.work_orders ow on ow.id=other.id where other.id<>p_job and ow.status<>'closed'
     and (other.service_interval_id=j.service_interval_id
      or j.service_interval_id=any(other.covered_plan_ids)
      or other.service_interval_id=any(j.covered_plan_ids)
      or other.covered_plan_ids && j.covered_plan_ids))
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
   if ((plan.interval_hours>0 or exists(select 1 from public.asset_service_intervals where id=any(j.covered_plan_ids) and interval_hours>0)) and w.hours_at_end is null) or (w.hours_at_end is not null and (w.hours_at_end<0 or w.hours_at_end>=1000000000 or w.hours_at_end<coalesce(plan.last_service_hours,0) or w.hours_at_end<coalesce(w.hours_at_start,0))) then raise exception 'A valid completion meter is required'; end if;
   perform public.maintenance_apply_recurrence(p_job,w.hours_at_end);
   update public.asset_engines set current_hours=greatest(current_hours,w.hours_at_end),
    maintenance_revision=maintenance_revision+1 where id=w.engine_id;
   update public.maintenance_job_records set service_applied_at=now() where id=p_job;
  end if;
  if w.hours_at_end is not null and w.engine_id is not null and j.meter_applied_at is null then
   if w.hours_at_end<coalesce(w.hours_at_start,0) then raise exception 'Completion meter cannot precede the starting meter'; end if;
   insert into public.hour_logs(id,engine_id,asset_id,hours,logged_by,logged_at,source,notes)
    values(p_operation,w.engine_id,w.asset_id,w.hours_at_end,auth.uid(),now(),'manual','Approved work completion');
   update public.asset_engines set current_hours=greatest(current_hours,w.hours_at_end),maintenance_revision=maintenance_revision+1 where id=w.engine_id;
   update public.maintenance_job_records set meter_applied_at=now() where id=p_job;
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
       'approved_by',auth.uid(),'current_hours',w.hours_at_end,'component_id',w.engine_id,'service_interval_id',j.service_interval_id,'covered_plan_ids',to_jsonb(j.covered_plan_ids)),
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

create or replace function public.maintenance_jobs(p_job uuid default null,p_asset uuid default null)
returns setof jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',w.id,'asset_id',w.asset_id,'asset_name',a.name,
 'title',w.title,'description',w.description,'status',w.status,'assigned_to',w.assigned_to,
 'assignee_name',p.full_name,'due_date',w.scheduled_date,'engine_id',w.engine_id,
 'component_name',e.label,'meter_unit',w.meter_unit,'job_type',w.job_type,'hours_at_end',w.hours_at_end,
 'on_hold_reason',w.on_hold_reason,'blocked_category',j.blocked_category,'created_at',w.created_at,'completed_at',w.completed_at,
 'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,
 'started_at',w.started_at,'hours_at_start',w.hours_at_start,'expected_materials',j.expected_materials,
 'revision',j.revision,'priority',j.priority,'service_interval_id',j.service_interval_id,
 'covered_plan_ids',to_jsonb(j.covered_plan_ids),'covered_plan_names',coalesce((select jsonb_agg(cp.interval_label order by cp.id) from public.asset_service_intervals cp where cp.id=any(j.covered_plan_ids)),'[]'),'parent_job_id',j.parent_job_id,'hourly_cost',j.hourly_cost,'review_note',j.review_note,
 'approved_at',j.approved_at,'service_applied_at',j.service_applied_at,
 'checklist_template_id',w.checklist_template_id,'checklist_template_version',w.checklist_template_version,'checklist_template_name',(select template_name from public.work_order_checklist_snapshots where work_order_id=w.id),'checklist_snapshot',j.checklist_snapshot,'checklist_answers',j.checklist_answers,'evidence_paths',j.evidence_paths,
 'can_manage',public.maintenance_can_manage_asset(w.asset_id),
 'can_schedule',public.maintenance_can_plan(w.asset_id) and public.maintenance_execution_enabled(w.asset_id),
 'can_work',public.maintenance_can_work_job(w.id),
 'report',(select jsonb_build_object('diagnosis',s.cause,'repair',s.correction,'notes',s.comments) from public.service_reports s where s.work_order_id=w.id),
 'parts',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'description',r.description,'part_number',r.part_number,
 'quantity',r.quantity,'unit_cost',r.unit_cost,'stock_requirement_id',to_jsonb(r)->'stock_requirement_id')) from public.parts r where r.work_order_id=w.id),'[]'),
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

create or replace function public.maintenance_asset_context(p_asset uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not public.maintenance_can_view_asset(p_asset) then raise exception 'Access denied'; end if;
 select jsonb_build_object('asset',to_jsonb(a),'can_manage',public.maintenance_can_manage_asset(a.id),
 'can_plan',public.maintenance_can_plan(a.id),'can_execute',public.maintenance_execution_enabled(a.id),
 'components',coalesce((select jsonb_agg(to_jsonb(e) order by e.label) from public.asset_engines e where e.asset_id=a.id),'[]'),
 'plans',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('component_name',e.label,'meter_unit',e.meter_unit,'current_hours',e.current_hours,
  'open_job_id',(select w.id from public.work_orders w join public.maintenance_job_records j on j.id=w.id
    where (j.service_interval_id=p.id or p.id=any(j.covered_plan_ids)) and w.status<>'closed' limit 1)) order by p.interval_label,p.id)
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

create or replace function public.maintenance_planning(p_asset uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'jobs',coalesce((select jsonb_agg(jsonb_build_object(
    'id',w.id,'asset_id',w.asset_id,'asset_name',a.name,'title',w.title,
    'job_type',w.job_type,'status',w.status,'priority',j.priority,'due_date',w.scheduled_date,
    'assigned_to',w.assigned_to,'assignee_name',p.full_name,
    'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,
    'revision',j.revision,'service_interval_id',j.service_interval_id,
    'component_name',e.label,'meter_unit',e.meter_unit,'on_hold_reason',w.on_hold_reason,
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
    'asset_name',a.name,'component_name',e.label,'meter_unit',e.meter_unit,'current_hours',e.current_hours,
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

create or replace function public.maintenance_work_hub(p_asset uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'jobs',coalesce((select jsonb_agg(jsonb_build_object(
    'id',w.id,'asset_id',w.asset_id,'asset_name',a.name,'title',w.title,
    'job_type',w.job_type,'status',w.status,'priority',j.priority,'due_date',w.scheduled_date,
    'assigned_to',w.assigned_to,'assignee_name',p.full_name,
    'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,
    'revision',j.revision,'service_interval_id',j.service_interval_id,
    'component_name',e.label,'meter_unit',w.meter_unit,'engine_id',w.engine_id,'on_hold_reason',w.on_hold_reason,
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
    'asset_name',a.name,'component_name',e.label,'meter_unit',e.meter_unit,'current_hours',e.current_hours,
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
