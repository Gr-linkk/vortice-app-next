-- NOW-008: provider jobs support additional reports; managed jobs keep one
-- canonical report for draft, submit, approval and immutable snapshots.
-- Existing report IDs, content, dates and authorization policies are preserved.
alter table public.service_reports
 add column managed_job_id uuid unique references public.maintenance_job_records(id);
update public.service_reports s set managed_job_id=w.id
 from public.work_orders w where w.id=s.work_order_id and w.managed_maintenance;

create function public.set_service_report_managed_job()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 -- Never accept a caller-supplied discriminator. The linked job owns it.
 select case when w.managed_maintenance then w.id else null end
  into new.managed_job_id from public.work_orders w where w.id=new.work_order_id;
 return new;
end $$;
revoke all on function public.set_service_report_managed_job() from public,anon,authenticated;
create trigger set_report_managed_job before insert or update on public.service_reports
 for each row execute function public.set_service_report_managed_job();
alter table public.service_reports drop constraint service_reports_work_order_id_key;
create index service_reports_work_order_index on public.service_reports(work_order_id);

-- Client reports must not depend on reading provider-only work-order rows.
create function public.can_read_provider_report(p_work_order uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w join public.profiles p on p.id=auth.uid()
  where w.id=p_work_order and not w.managed_maintenance and
   (p.role in ('owner','employee') or
    (p.role in ('client','client_admin','client_mechanic') and w.status in ('closed','invoiced')
     and public.maintenance_can_view_asset(w.asset_id))))
$$;
revoke all on function public.can_read_provider_report(uuid) from public,anon;
grant execute on function public.can_read_provider_report(uuid) to authenticated;
create policy completed_provider_reports_read on public.service_reports
 for select to authenticated using(public.can_read_provider_report(work_order_id));
create policy completed_provider_report_photos_read on public.service_report_photos
 for select to authenticated using(exists(select 1 from public.service_reports s
  where s.id=service_report_id and public.can_read_provider_report(s.work_order_id)));

create function public.provider_service_reports(p_report uuid default null,
 p_work_order uuid default null,p_asset uuid default null)
returns setof jsonb language sql stable security definer set search_path='' as $$
 select (to_jsonb(s)-'managed_job_id')||jsonb_build_object('asset_id',w.asset_id,
  'work_orders',jsonb_build_object('asset_id',w.asset_id,'assets',jsonb_build_object('name',a.name)))
 from public.service_reports s join public.work_orders w on w.id=s.work_order_id
 left join public.assets a on a.id=w.asset_id
 where public.can_read_provider_report(w.id)
  and (p_report is null or s.id=p_report)
  and (p_work_order is null or w.id=p_work_order)
  and (p_asset is null or w.asset_id=p_asset)
 order by s.created_at desc,s.id desc
$$;
revoke all on function public.provider_service_reports(uuid,uuid,uuid) from public,anon;
grant execute on function public.provider_service_reports(uuid,uuid,uuid) to authenticated;

-- Provider asset scope already exists in the maintenance RPC. Apply the same
-- read scope to legacy asset labels so a fresh technician cache works too.
create policy provider_team_reads_assets on public.assets for select to authenticated
 using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='employee'));

create function public.provider_report_media_readable(p_bucket text,p_name text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('owner','employee'))
 or case p_bucket
  when 'signatures' then exists(select 1 from public.service_reports s
   where public.can_read_provider_report(s.work_order_id) and
    (s.tech_signature_url=p_name or right(s.tech_signature_url,
      length('/storage/v1/object/public/signatures/'||p_name))='/storage/v1/object/public/signatures/'||p_name))
  when 'service-report-photos' then exists(select 1 from public.service_report_photos photo
   join public.service_reports s on s.id=photo.service_report_id
   where public.can_read_provider_report(s.work_order_id) and
    (photo.photo_url=p_name or right(photo.photo_url,
      length('/storage/v1/object/public/service-report-photos/'||p_name))='/storage/v1/object/public/service-report-photos/'||p_name))
  else false end
$$;
revoke all on function public.provider_report_media_readable(text,text) from public,anon;
grant execute on function public.provider_report_media_readable(text,text) to authenticated;
drop policy "Authenticated read signatures" on storage.objects;
drop policy "Authenticated read report photos" on storage.objects;
create policy authorized_provider_report_media_read on storage.objects for select to authenticated
 using(bucket_id in ('signatures','service-report-photos') and
  public.provider_report_media_readable(bucket_id,name));

-- Same transactional workflow; only the report upsert conflict target changes.
create or replace function public.change_maintenance_job(p_job uuid,p_revision integer,p_operation uuid,p_action text,p_data jsonb)
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
