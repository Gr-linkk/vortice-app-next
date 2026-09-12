-- NEXT-002.05/.08/.15/.18: the provider adapter uses the same work order,
-- checklist snapshot, labour sessions, report and evidence identities.
alter table public.organization_work_report_state
 add column checklist_answers jsonb not null default '{}',
 add column evidence_paths jsonb not null default '[]',
 add column procedure_notes text not null default '',
 add column returned_at timestamptz,
 add column legacy_labour_hours numeric not null default 0;
update public.organization_work_report_state s set legacy_labour_hours=coalesce(w.labour_hours,0)
 from public.work_orders w where w.id=s.work_order_id;
alter table public.maintenance_labour_sessions drop constraint maintenance_labour_sessions_work_order_id_fkey;
alter table public.maintenance_labour_sessions add constraint maintenance_labour_sessions_work_order_id_fkey
 foreign key(work_order_id) references public.work_orders(id);

create function public.organization_default_work_meter() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.provider_organization_id is not null and new.engine_id is null then
  select primary_meter_engine_id,meter_unit into new.engine_id,new.meter_unit from public.assets where id=new.asset_id;
 end if;
 return new;
end $$;
create trigger organization_default_work_meter before insert on public.work_orders for each row execute function public.organization_default_work_meter();
revoke all on function public.organization_default_work_meter() from public,anon,authenticated;
update public.work_orders w set engine_id=a.primary_meter_engine_id,meter_unit=a.meter_unit from public.assets a
 where w.asset_id=a.id and w.provider_organization_id is not null and w.engine_id is null and w.started_at is null;
create or replace function public.organization_provider_meter_access(p_asset uuid,p_engine uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w where w.provider_organization_id is not null and w.asset_id=p_asset
 and w.engine_id is not distinct from p_engine and public.organization_provider_access(w.id,'work')
 and (w.status in ('in_progress','on_hold') or (w.status='pending_review' and public.organization_provider_access(w.id,'manage'))))
$$;

create function public.organization_work_template_allowed(p_work_order uuid,p_template uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w join public.assets a on a.id=w.asset_id
 join public.client_orgs o on o.id=w.provider_organization_id join public.checklist_templates t on t.id=p_template
 where w.id=p_work_order and t.is_active and t.checklist_type='pm'
 and (t.client_id is null or t.client_id=o.owner_profile_id)
 and (t.asset_type_id is null or t.asset_type_id=a.asset_type_id)
 and (t.scope_asset_id is null or t.scope_asset_id=a.id)
 and (t.scope_engine_id is null or t.scope_engine_id=w.engine_id))
$$;
revoke all on function public.organization_work_template_allowed(uuid,uuid) from public,anon,authenticated;

-- Modern members use the same company library through their permissions.
-- A service relationship never makes the customer's library the provider's.
create or replace function public.checklist_template_visible(p_template uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.checklist_templates t join public.profiles p on p.id=auth.uid()
 where t.id=p_template and (t.client_id is null or t.client_id=public.checklist_company() or p.role in ('owner','employee'))
 and (p.role in ('owner','employee','client','client_admin')
 or (p.role='client_mechanic' and t.checklist_type='pm')
 or (p.role='operator' and t.checklist_type='operator_daily')
 or (p.role='member' and public.organization_has_permission(public.active_organization_id(),'member')
 and case when t.checklist_type='pm' then public.organization_has_permission(public.active_organization_id(),'planning')
  or public.organization_has_permission(public.active_organization_id(),'work_assigned')
 else public.organization_has_permission(public.active_organization_id(),'preop') end)))
$$;

-- Reuse immutable snapshot capture. Keep its ordinary tenant checks intact.
do $$ declare body text; old text; replacement text; begin
 body:=pg_get_functiondef('public.guard_work_order_checklist()'::regprocedure);
 old:='if auth.uid() is not null and not public.checklist_template_usable(new.checklist_template_id,new.asset_id,new.engine_id,''pm'')';
 replacement:='if auth.uid() is not null and not (case when new.provider_organization_id is not null then
 public.organization_provider_access(new.id,''manage'') and public.organization_work_template_allowed(new.id,new.checklist_template_id)
 else public.checklist_template_usable(new.checklist_template_id,new.asset_id,new.engine_id,''pm'') end)';
 if position(old in body)=0 then raise exception 'Checklist scope guard changed'; end if;
 execute replace(body,old,replacement);
 body:=pg_get_functiondef('public.require_published_pm_completion()'::regprocedure);
 old:='if new.managed_maintenance or';
 if position(old in body)=0 then raise exception 'Checklist completion guard changed'; end if;
 execute replace(body,old,'if new.provider_organization_id is not null or new.managed_maintenance or');
end $$;

-- Provider completion below validates the frozen instructions and private
-- evidence. Direct modern order writes remain denied by existing restrictive RLS.
create function public.organization_validate_work_report(p_work_order uuid,p_complete boolean) returns void
language plpgsql security definer set search_path='' as $$
declare state public.organization_work_report_state; item jsonb; answer jsonb; path text; key text;
begin
 select * into state from public.organization_work_report_state where work_order_id=p_work_order;
 if jsonb_typeof(state.checklist_answers) is distinct from 'object' or jsonb_typeof(state.evidence_paths) is distinct from 'array'
 or jsonb_array_length(state.evidence_paths)>24 then raise exception 'Invalid report answers or evidence'; end if;
 for key in select jsonb_object_keys(state.checklist_answers) loop
  if not exists(select 1 from public.work_order_checklist_snapshots s,jsonb_array_elements(s.items_json) i
   where s.work_order_id=p_work_order and i->>'id'=key) then raise exception 'Answer does not belong to this work'; end if;
 end loop;
 for path in select jsonb_array_elements_text(state.evidence_paths) loop
  if split_part(path,'/',1)<>p_work_order::text or not exists(select 1 from storage.objects
   where bucket_id='maintenance-evidence' and name=path) then raise exception 'Evidence upload is incomplete'; end if;
 end loop;
 for item in select i from public.work_order_checklist_snapshots s,jsonb_array_elements(s.items_json) i where s.work_order_id=p_work_order loop
  answer:=state.checklist_answers->(item->>'id');
  if answer is not null and (jsonb_typeof(answer)<>'object' or length(coalesce(answer->>'note',''))>4000 or length(coalesce(answer->>'issue_note',''))>4000)
   then raise exception 'Invalid checklist answer'; end if;
  if p_complete then
   perform public.validate_checklist_answer(coalesce(item->'definition','{}'),answer->>'result',answer->>'note');
   if coalesce(answer->>'result','') not in ('pass','na','n/a') then raise exception 'Complete every checklist step and resolve failed steps'; end if;
   if (item->>'requires_photo')::boolean and not state.evidence_paths ? coalesce(answer->>'photo_path','')
    then raise exception 'Attach the required photo for each step'; end if;
  end if;
 end loop;
end $$;
revoke all on function public.organization_validate_work_report(uuid,boolean) from public,anon,authenticated;

create function public.organization_work_labour_hours(p_work_order uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce((select legacy_labour_hours from public.organization_work_report_state where work_order_id=p_work_order),0)
 +coalesce((select sum(extract(epoch from stopped_at-started_at)/3600) from public.maintenance_labour_sessions
 where work_order_id=p_work_order and stopped_at is not null),0)
$$;
revoke all on function public.organization_work_labour_hours(uuid) from public,anon,authenticated;

create or replace function public.change_organization_work(p_work_order uuid,p_revision integer,p_operation uuid,p_action text,p_data jsonb default '{}') returns void
language plpgsql security definer set search_path='' as $$
declare w public.work_orders; state public.organization_work_report_state; receipt public.closeout_operations;
 payload jsonb; manager boolean; report uuid; meter numeric; template uuid; at_time timestamptz:=clock_timestamp();
begin
 select * into w from public.work_orders where id=p_work_order for update;
 if w.id is null or not public.organization_provider_access(w.id,'work') then raise exception 'Organization work access denied' using errcode='42501'; end if;
 select * into state from public.organization_work_report_state where work_order_id=w.id for update;
 if p_operation is null or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Work operation is required'; end if;
 payload:=jsonb_build_object('work_order',w.id,'action',p_action,'data',p_data);
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
  if receipt.actor_id<>auth.uid() or receipt.kind<>'organization_work' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
  return;
 end if;
 if state.revision is distinct from p_revision then raise exception 'Work order changed; refresh'; end if;
 manager:=public.organization_provider_access(w.id,'manage');
 if p_action='configure' then
  if not manager or w.status not in ('draft','assigned') or w.started_at is not null then raise exception 'Prepare this work before starting'; end if;
  template:=nullif(p_data->>'checklist_template_id','')::uuid;
  if template is not null and not public.organization_work_template_allowed(w.id,template) then raise exception 'Choose a published provider checklist for this equipment'; end if;
  if length(coalesce(p_data->>'procedure_notes',''))>8000 then raise exception 'Procedure notes are too long'; end if;
  update public.work_orders set checklist_template_id=template,scheduled_date=nullif(p_data->>'service_date','')::date where id=w.id;
  update public.organization_work_report_state set procedure_notes=btrim(coalesce(p_data->>'procedure_notes','')),checklist_answers='{}' where work_order_id=w.id;
 elsif p_action='assign' then
  if not manager or w.status not in ('draft','assigned','in_progress','on_hold') then raise exception 'Assignment is not allowed'; end if;
  if not public.organization_has_permission(w.provider_organization_id,'work_assigned',(p_data->>'assigned_to')::uuid) then raise exception 'Choose a provider teammate'; end if;
  if exists(select 1 from public.maintenance_labour_sessions where work_order_id=w.id and stopped_at is null) then raise exception 'Pause running labour before reassigning'; end if;
  update public.work_orders set assigned_to=(p_data->>'assigned_to')::uuid,status=case when status='draft' then 'assigned' else status end where id=w.id;
  insert into public.work_order_assignments(work_order_id,profile_id,role) values(w.id,(p_data->>'assigned_to')::uuid,'tech') on conflict(work_order_id,profile_id) do nothing;
  delete from public.work_order_assignments where work_order_id=w.id and profile_id<>(p_data->>'assigned_to')::uuid;
 elsif p_action in ('start','resume') then
  if w.status not in ('assigned','in_progress','on_hold') then raise exception 'Assign this work order first'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,11));
  if exists(select 1 from public.maintenance_labour_sessions where actor_id=auth.uid() and stopped_at is null) then raise exception 'Pause your running labour timer first'; end if;
  if w.started_at is null then
   meter:=nullif(p_data->>'meter_value','')::numeric;
   if meter is not null and not(meter>=0 and meter<1000000000) then raise exception 'Enter a valid meter reading'; end if;
   if w.engine_id is not null then
    if p_data->>'meter_unit' is distinct from w.meter_unit then raise exception 'Confirm the starting meter unit'; end if;
    if meter is null then raise exception 'Enter the starting meter reading'; end if;
    update public.work_orders set status='in_progress' where id=w.id;
    perform public.record_component_meter(gen_random_uuid(),w.engine_id,w.asset_id,meter,w.meter_unit,at_time,'Provider work start');
   end if;
   update public.work_orders set hours_at_start=meter where id=w.id;
  end if;
  insert into public.maintenance_labour_sessions(id,work_order_id,actor_id,started_at) values(p_operation,w.id,auth.uid(),at_time);
  update public.work_orders set status='in_progress',started_at=coalesce(started_at,at_time),on_hold_reason=null where id=w.id;
 elsif p_action='pause' then
  if w.status not in ('in_progress','on_hold') or not exists(select 1 from public.maintenance_labour_sessions where work_order_id=w.id and actor_id=auth.uid() and stopped_at is null)
   then raise exception 'No running timer on this work'; end if;
  update public.maintenance_labour_sessions set stopped_at=at_time where work_order_id=w.id and actor_id=auth.uid() and stopped_at is null;
 elsif p_action='block' then
  if w.status not in ('assigned','in_progress','on_hold') or length(btrim(coalesce(p_data->>'note','')))<3 or length(p_data->>'note')>2000 then raise exception 'Describe what is blocking the work'; end if;
  update public.maintenance_labour_sessions set stopped_at=at_time where work_order_id=w.id and stopped_at is null;
  update public.work_orders set status='on_hold',on_hold_reason=btrim(p_data->>'note') where id=w.id;
 elsif p_action in ('save_report','submit') then
  if w.status not in ('in_progress','on_hold') then raise exception 'Start work before writing the report'; end if;
  if length(coalesce(p_data->>'diagnosis',''))>8000 or length(coalesce(p_data->>'repair',''))>16000 or length(coalesce(p_data->>'notes',''))>4000 then raise exception 'Report text is too long'; end if;
  if p_action='submit' and (length(btrim(coalesce(p_data->>'diagnosis','')))<3 or length(btrim(coalesce(p_data->>'repair','')))<3)
   then raise exception 'Describe the diagnosis and repair'; end if;
  report:=coalesce(state.report_id,gen_random_uuid());
  insert into public.service_reports(id,work_order_id,cause,correction,comments,submitted_by,evidence_pending)
   values(report,w.id,p_data->>'diagnosis',p_data->>'repair',p_data->>'notes',auth.uid(),false)
   on conflict(id) do update set cause=excluded.cause,correction=excluded.correction,comments=excluded.comments,updated_at=now();
  update public.organization_work_report_state set report_id=report,
   checklist_answers=coalesce(p_data->'answers',checklist_answers),evidence_paths=coalesce(p_data->'evidence_paths',evidence_paths)
   where work_order_id=w.id;
  meter:=nullif(p_data->>'meter_value','')::numeric;
  if meter is not null and (p_data->>'meter_unit' is distinct from w.meter_unit or not(meter>=coalesce(w.hours_at_start,0) and meter<1000000000)) then raise exception 'Completion reading or unit is invalid'; end if;
  if p_action='submit' then
   if w.engine_id is not null and meter is null then raise exception 'Enter the completion reading'; end if;
   perform public.organization_validate_work_report(w.id,true);
   update public.maintenance_labour_sessions set stopped_at=at_time where work_order_id=w.id and actor_id=auth.uid() and stopped_at is null;
   if exists(select 1 from public.maintenance_labour_sessions where work_order_id=w.id and stopped_at is null) then raise exception 'Ask teammates to pause their labour before review'; end if;
   update public.organization_work_report_state set review_note=null,returned_at=null where work_order_id=w.id;
  else perform public.organization_validate_work_report(w.id,false); end if;
  update public.work_orders set hours_at_end=meter,status=case when p_action='submit' then 'pending_review' else status end where id=w.id;
 elsif p_action='add_part' then
  if w.status not in ('in_progress','on_hold') then raise exception 'Parts can change only during work'; end if;
  if length(btrim(coalesce(p_data->>'description','')))<2 or not((p_data->>'quantity')::numeric>0 and (p_data->>'quantity')::numeric<100000)
   or not((p_data->>'unit_cost')::numeric>=0 and (p_data->>'unit_cost')::numeric<1000000) then raise exception 'Enter a part, quantity and internal cost'; end if;
  insert into public.parts(id,work_order_id,description,quantity,unit_cost,markup_pct,logged_by)
   values(p_operation,w.id,btrim(p_data->>'description'),(p_data->>'quantity')::numeric,(p_data->>'unit_cost')::numeric,0,auth.uid());
 elsif p_action='return' then
  if not manager or w.status<>'pending_review' or length(btrim(coalesce(p_data->>'note','')))<3 or length(p_data->>'note')>2000 then raise exception 'Return requires a manager and reason'; end if;
  update public.work_orders set status='in_progress' where id=w.id;
  update public.organization_work_report_state set review_note=btrim(p_data->>'note'),returned_at=at_time where work_order_id=w.id;
 elsif p_action='approve' then
  if not manager or w.status<>'pending_review' then raise exception 'A manager must approve submitted work'; end if;
  if exists(select 1 from public.maintenance_labour_sessions where work_order_id=w.id and stopped_at is null) then raise exception 'Pause running labour before approval'; end if;
  perform public.organization_validate_work_report(w.id,true);
  if w.engine_id is not null and w.hours_at_end is not null then
   perform public.record_component_meter(gen_random_uuid(),w.engine_id,w.asset_id,w.hours_at_end,w.meter_unit,at_time,'Approved provider work completion');
  end if;
  update public.organization_work_report_state set published_report=(select jsonb_build_object('id',s.id,'diagnosis',s.cause,'repair',s.correction,
   'notes',s.comments,'approved_at',at_time,'approved_by_name',(select full_name from public.profiles where id=auth.uid()),
   'checklist_snapshot',coalesce((select items_json from public.work_order_checklist_snapshots where work_order_id=w.id),'[]'),
   'answers',organization_work_report_state.checklist_answers,'evidence_paths',organization_work_report_state.evidence_paths,
   'procedure_notes',organization_work_report_state.procedure_notes,'meter_unit',w.meter_unit,'completion_meter',w.hours_at_end)
   from public.service_reports s where s.id=state.report_id),approved_at=at_time,approved_by=auth.uid(),returned_at=null where work_order_id=w.id;
  update public.work_orders set status='closed',completed_at=at_time where id=w.id;
 else raise exception 'Unknown work action'; end if;
 update public.work_orders set labour_hours=public.organization_work_labour_hours(w.id) where id=w.id;
 update public.organization_work_report_state set revision=revision+1 where work_order_id=w.id;
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'organization_work',payload,w.id);
end $$;

alter function public.organization_work_order_context(uuid) rename to organization_work_order_context_before_execution;
create function public.organization_work_order_context(p_work_order uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; w public.work_orders; state public.organization_work_report_state;
begin
 result:=public.organization_work_order_context_before_execution(p_work_order);
 select * into w from public.work_orders where id=p_work_order;
 select * into state from public.organization_work_report_state where work_order_id=w.id;
 if (result->>'is_provider')::boolean then
  return result||jsonb_build_object('returned_at',state.returned_at,'procedure_notes',state.procedure_notes,
   'checklist_snapshot',coalesce((select items_json from public.work_order_checklist_snapshots where work_order_id=w.id),'[]'),
   'checklist_name',(select template_name from public.work_order_checklist_snapshots where work_order_id=w.id),
   'answers',state.checklist_answers,'evidence_paths',state.evidence_paths,
   'current_meter',(select current_hours from public.asset_engines where id=w.engine_id),
   'labour_hours',public.organization_work_labour_hours(w.id),
   'labour',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('actor_name',p.full_name) order by s.started_at,s.id)
    from public.maintenance_labour_sessions s join public.profiles p on p.id=s.actor_id where s.work_order_id=w.id),'[]'),
   'templates',case when public.organization_provider_access(w.id,'manage') then coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'version',t.version) order by t.name,t.version)
    from public.checklist_templates t where public.organization_work_template_allowed(w.id,t.id)
    and (t.procedure_id is null or exists(select 1 from public.checklist_procedures p where p.id=t.procedure_id and p.published_template_id=t.id and not p.archived))),'[]') else '[]' end,
   'sources',coalesce((select jsonb_agg(jsonb_build_object('kind',s.source_kind,'id',s.source_id,'snapshot',s.snapshot) order by s.created_at)
    from public.work_order_sources s where s.work_order_id=w.id and s.source_kind='service_request'),'[]'));
 end if;
 return result;
end $$;
revoke all on function public.organization_work_order_context_before_execution(uuid) from public,anon,authenticated;
grant execute on function public.organization_work_order_context(uuid),public.change_organization_work(uuid,integer,uuid,text,jsonb) to authenticated;

create function public.organization_work_evidence_access(p_path text,p_write boolean) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w where w.id=public.maintenance_evidence_job(p_path) and w.provider_organization_id is not null
 and case when p_write then split_part(p_path,'/',2)=auth.uid()::text and w.status in ('in_progress','on_hold') and public.organization_provider_access(w.id,'work')
 else public.organization_provider_access(w.id) or (public.organization_customer_access(w.id) and exists(
  select 1 from public.organization_work_report_state s where s.work_order_id=w.id and s.published_report->'evidence_paths' ? p_path)) end)
$$;
revoke all on function public.organization_work_evidence_access(text,boolean) from public,anon;
grant execute on function public.organization_work_evidence_access(text,boolean) to authenticated;
create policy organization_work_evidence_upload on storage.objects for insert to authenticated
 with check(bucket_id='maintenance-evidence' and public.organization_work_evidence_access(name,true));
create policy organization_work_evidence_read on storage.objects for select to authenticated
 using(bucket_id='maintenance-evidence' and public.organization_work_evidence_access(name,false));

-- Only the pages named by attached frozen provider instructions are shared.
do $$ declare body text; old text; replacement text; begin
 body:=pg_get_functiondef('public.checklist_source_reader(uuid,uuid)'::regprocedure);
 old:='and public.coordination_subject_reader(''job'',s.work_order_id,auth.uid())';
 replacement:=old||' and (not public.is_organization_provider_work(s.work_order_id) or public.organization_provider_access(s.work_order_id)
 or (public.organization_customer_access(s.work_order_id) and exists(select 1 from public.organization_work_report_state ps where ps.work_order_id=s.work_order_id and ps.published_report is not null)))';
 if position(old in body)=0 then raise exception 'Checklist source reader changed'; end if;
 execute replace(body,old,replacement);
end $$;
alter function public.checklist_source_reader(uuid,uuid) rename to checklist_source_reader_before_provider;
create function public.checklist_source_reader(p_template uuid,p_item uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.checklist_source_reader_before_provider(p_template,p_item)
 or exists(select 1 from public.work_order_checklist_snapshots s where s.template_id=p_template
 and public.organization_provider_access(s.work_order_id)
 and exists(select 1 from jsonb_array_elements(s.items_json) i where i->>'id'=p_item::text))
$$;
revoke all on function public.checklist_source_reader_before_provider(uuid,uuid),public.checklist_source_reader(uuid,uuid) from public,anon,authenticated;
-- Replace callers so they bind the new function rather than the renamed OID.
do $$ declare body text; begin
 body:=pg_get_functiondef('public.checklist_source_page(uuid,uuid,uuid,integer)'::regprocedure); execute body;
 body:=pg_get_functiondef('public.maintenance_document_object_access(text,boolean)'::regprocedure); execute body;
end $$;
