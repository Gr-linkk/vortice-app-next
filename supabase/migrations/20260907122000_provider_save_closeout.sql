-- One transaction owns provider work preparation, assignment and request linkage.
create function public.touch_provider_work_order() returns trigger language plpgsql set search_path='' as $$
begin
 if not new.managed_maintenance then new.updated_at:=clock_timestamp(); end if;
 return new;
end $$;
create trigger provider_work_order_timestamp before update on public.work_orders
for each row execute function public.touch_provider_work_order();

create function public.save_provider_work_order(p_operation uuid,p_data jsonb,p_assignees uuid[],
 p_work_order uuid default null,p_request uuid default null,p_expected_updated_at timestamptz default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare receipt public.closeout_operations; w public.work_orders; next_row public.work_orders;
 request public.service_requests; result uuid; person uuid;
 payload jsonb:=jsonb_build_object('data',p_data,'assignees',p_assignees,'work_order',p_work_order,
 'request',p_request,'expected_updated_at',p_expected_updated_at);
begin
 if public.get_my_role() is distinct from 'owner' then raise exception 'Owner required for provider assignment'; end if;
 if p_assignees is null then raise exception 'Assignment list required'; end if;
 if jsonb_typeof(p_data)<>'object' or exists(select 1 from jsonb_object_keys(p_data) k where k not in
   ('title','description','asset_id','engine_id','client_id','created_by','job_type','status','assigned_to',
    'checklist_template_id','scheduled_date','hours_at_start','hours_at_end','labour_hours','notes_internal','on_hold_reason')) then
   raise exception 'Unsupported work order fields';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
   if receipt.actor_id<>auth.uid() or receipt.kind<>'provider_save' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
   return receipt.result;
 end if;
 if p_request is not null then
   if p_work_order is not null then raise exception 'Request conversion must create its work order'; end if;
   select * into request from public.service_requests where id=p_request for update;
   if not found then raise exception 'Service request unavailable'; end if;
   if request.generated_work_order_id is not null then return request.generated_work_order_id; end if;
   if request.status<>'new' then raise exception 'Service request is already handled'; end if;
 end if;
 foreach person in array p_assignees loop
   if person is null or not exists(select 1 from public.profiles where id=person and role in ('owner','employee')) then
     raise exception 'Provider technician unavailable';
   end if;
 end loop;
 if p_work_order is null then
   select * into next_row from jsonb_populate_record(null::public.work_orders,p_data);
   if next_row.created_by is distinct from auth.uid() then raise exception 'Invalid creator'; end if;
   if not exists(select 1 from public.assets where id=next_row.asset_id and client_id=next_row.client_id) then
     raise exception 'Asset does not belong to this client';
   end if;
   if next_row.engine_id is not null and not exists(select 1 from public.asset_engines where id=next_row.engine_id and asset_id=next_row.asset_id) then
     raise exception 'Component does not belong to this asset';
   end if;
   if p_request is not null and (request.client_id<>next_row.client_id or
     (request.asset_id is not null and request.asset_id<>next_row.asset_id)) then raise exception 'Request asset/client mismatch'; end if;
   result:=p_operation;
   insert into public.work_orders(id,asset_id,engine_id,client_id,created_by,job_type,title,description,status,
     assigned_to,checklist_template_id,scheduled_date,hours_at_start,notes_internal)
   values(result,next_row.asset_id,next_row.engine_id,next_row.client_id,auth.uid(),next_row.job_type,next_row.title,
     next_row.description,case when cardinality(p_assignees)>0 then 'assigned' else 'draft' end,
     p_assignees[1],next_row.checklist_template_id,next_row.scheduled_date,next_row.hours_at_start,next_row.notes_internal);
 else
   select * into w from public.work_orders where id=p_work_order for update;
   if not found or w.managed_maintenance then raise exception 'Provider work order unavailable'; end if;
   if w.status in ('closed','invoiced') then raise exception 'Completed work order cannot be reassigned'; end if;
   if p_expected_updated_at is null or w.updated_at is distinct from p_expected_updated_at then
     raise exception 'Work order changed. Refresh before editing';
   end if;
   if p_data ?| array['asset_id','client_id','created_by','job_type','status'] then raise exception 'Work order scope cannot be rewritten'; end if;
   select * into next_row from jsonb_populate_record(w,p_data);
   if exists(select 1 from public.work_order_assignments where work_order_id=w.id
     and not(profile_id=any(p_assignees)) and (hours_logged is not null or started_at is not null or completed_at is not null)) then
     raise exception 'Keep technicians with recorded labour in the assignment';
   end if;
   update public.work_orders set title=next_row.title,description=next_row.description,
     assigned_to=p_assignees[1],scheduled_date=next_row.scheduled_date,hours_at_start=next_row.hours_at_start,
     hours_at_end=next_row.hours_at_end,labour_hours=next_row.labour_hours,notes_internal=next_row.notes_internal,
     on_hold_reason=next_row.on_hold_reason,checklist_template_id=next_row.checklist_template_id,
     status=case when w.status in ('draft','assigned') then case when cardinality(p_assignees)>0 then 'assigned' else 'draft' end else w.status end
     where id=w.id;
   result:=w.id;
   delete from public.work_order_assignments where work_order_id=result and not(profile_id=any(p_assignees));
 end if;
 foreach person in array p_assignees loop
   if not exists(select 1 from public.work_order_assignments where work_order_id=result and profile_id=person) then
     insert into public.work_order_assignments(work_order_id,profile_id,role) values(result,person,'tech');
   end if;
 end loop;
 if p_request is not null then
   update public.service_requests set generated_work_order_id=result,status='resolved',handled_by=auth.uid(),handled_at=now() where id=p_request;
 end if;
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'provider_save',payload,result);
 return result;
end $$;
revoke all on function public.save_provider_work_order(uuid,jsonb,uuid[],uuid,uuid,timestamptz) from public,anon;
grant execute on function public.save_provider_work_order(uuid,jsonb,uuid[],uuid,uuid,timestamptz) to authenticated;
