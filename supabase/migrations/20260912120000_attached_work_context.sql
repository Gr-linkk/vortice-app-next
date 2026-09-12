-- NEXT-002.03/.05/.07/.08: source context and the attached execution record.
alter table public.maintenance_job_records add column returned_at timestamptz;
create table public.work_order_sources (
 work_order_id uuid not null references public.work_orders(id) on delete restrict,
 source_kind text not null check(source_kind in ('asset','fault','plan','inspection','service_request')),
 source_id uuid not null,
 snapshot jsonb not null,
 created_at timestamptz not null default now(),
 primary key(work_order_id,source_kind,source_id)
);
create table public.work_checklist_faults (
 work_order_id uuid not null references public.work_orders(id) on delete restrict,
 item_id uuid not null,
 fault_id uuid not null unique references public.maintenance_requests(id) on delete restrict,
 answer_snapshot jsonb not null,
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 primary key(work_order_id,item_id)
);
alter table public.work_order_sources enable row level security;
alter table public.work_checklist_faults enable row level security;
revoke all on public.work_order_sources,public.work_checklist_faults from public,anon,authenticated;
grant select on public.work_order_sources,public.work_checklist_faults to authenticated;
grant all on public.work_order_sources,public.work_checklist_faults to service_role;
create function public.work_context_can_read(p_job uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and public.parts_job_access(p_job)
$$;
revoke all on function public.work_context_can_read(uuid) from public,anon;
grant execute on function public.work_context_can_read(uuid) to authenticated;
create policy work_source_read on public.work_order_sources for select to authenticated using(public.work_context_can_read(work_order_id));
create policy work_fault_read on public.work_checklist_faults for select to authenticated using(public.work_context_can_read(work_order_id));

create function public.capture_work_source() returns trigger language plpgsql security definer set search_path='' as $$
declare p public.asset_service_intervals; w public.work_orders;
begin
 if tg_table_name='maintenance_job_records' then
  if new.service_interval_id is null then return new; end if;
  select * into p from public.asset_service_intervals where id=new.service_interval_id;
  insert into public.work_order_sources values(new.id,'plan',p.id,to_jsonb(p),now()) on conflict do nothing;
 elsif tg_table_name='maintenance_requests' then
  if new.converted_to_work_order_id is null then return new; end if;
  select * into w from public.work_orders where id=new.converted_to_work_order_id;
  if w.asset_id is distinct from new.asset_id then raise exception 'Fault and work must belong to the same asset'; end if;
  insert into public.work_order_sources values(w.id,'fault',new.id,jsonb_build_object('title',new.description,'severity',new.severity,'asset_id',new.asset_id),now()) on conflict do nothing;
 elsif tg_table_name='service_requests' then
  if new.generated_work_order_id is null then return new; end if;
  select * into w from public.work_orders where id=new.generated_work_order_id;
  if (new.asset_id is not null and w.asset_id is distinct from new.asset_id) or w.client_id is distinct from new.client_id then raise exception 'Request and work must belong to the same customer asset'; end if;
  insert into public.work_order_sources values(w.id,'service_request',new.id,jsonb_build_object('title',new.title,'description',new.description,'urgency',new.urgency,'photo_urls',new.photo_urls),now()) on conflict do nothing;
 end if;
 return new;
end $$;
revoke all on function public.capture_work_source() from public,anon,authenticated;
create trigger capture_plan_source after insert on public.maintenance_job_records for each row execute function public.capture_work_source();
create trigger capture_fault_source after insert or update of converted_to_work_order_id on public.maintenance_requests for each row execute function public.capture_work_source();
create trigger capture_request_source after insert or update of generated_work_order_id on public.service_requests for each row execute function public.capture_work_source();

-- Retain the checked backend action in one place; the wrapper adds contextual
-- results atomically. Fault reporting does not close failed steps or the asset.
alter function public.change_maintenance_job(uuid,integer,uuid,text,jsonb) rename to change_maintenance_job_before_context;
revoke all on function public.change_maintenance_job_before_context(uuid,integer,uuid,text,jsonb) from public,anon,authenticated;
create function public.change_maintenance_job(p_job uuid,p_revision integer,p_operation uuid,p_action text,p_data jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare j public.maintenance_job_records; w public.work_orders; item jsonb; answer jsonb; fault uuid; description text;
begin
 perform public.change_maintenance_job_before_context(p_job,p_revision,p_operation,p_action,p_data);
 if p_action='return' then update public.maintenance_job_records set returned_at=coalesce(returned_at,now()) where id=p_job;
 elsif p_action in ('submit','approve') then update public.maintenance_job_records set returned_at=null where id=p_job;
 end if;
 if p_action not in ('save_report','submit') then return; end if;
 select * into j from public.maintenance_job_records where id=p_job for update;
 select * into w from public.work_orders where id=p_job;
 for item in select value from jsonb_array_elements(j.checklist_snapshot) loop
  answer:=j.checklist_answers->(item->>'id');
  if answer->>'result'<>'fail' or coalesce((answer->>'fault_requested')::boolean,false)=false then continue; end if;
  if exists(select 1 from public.work_checklist_faults where work_order_id=p_job and item_id=(item->>'id')::uuid) then continue; end if;
  description:=left(concat_ws(E'\n',item->>'description_en',nullif(btrim(answer->>'issue_note'),'')),4000);
  fault:=public.report_maintenance_fault(gen_random_uuid(),w.asset_id,description,'normal');
  insert into public.work_checklist_faults(work_order_id,item_id,fault_id,answer_snapshot,created_by)
   values(p_job,(item->>'id')::uuid,fault,answer,auth.uid());
 end loop;
end $$;
revoke all on function public.change_maintenance_job(uuid,integer,uuid,text,jsonb) from public,anon;
grant execute on function public.change_maintenance_job(uuid,integer,uuid,text,jsonb) to authenticated;

alter function public.maintenance_jobs(uuid,uuid) rename to maintenance_jobs_before_context;
revoke all on function public.maintenance_jobs_before_context(uuid,uuid) from public,anon,authenticated;
create function public.maintenance_jobs(p_job uuid default null,p_asset uuid default null)
returns setof jsonb language sql stable security definer set search_path='' as $$
 select source_row||jsonb_build_object('returned_at',j.returned_at,'current_meter',e.current_hours,
 'sources',coalesce((select jsonb_agg(to_jsonb(s) order by created_at,source_kind,source_id) from public.work_order_sources s where work_order_id=j.id),'[]'),
 'checklist_faults',coalesce((select jsonb_agg(to_jsonb(f) order by created_at,item_id) from public.work_checklist_faults f where work_order_id=j.id),'[]'))
 from public.maintenance_jobs_before_context(p_job,p_asset) source_row
 join public.maintenance_job_records j on j.id=(source_row->>'id')::uuid
 left join public.asset_engines e on e.id=(source_row->>'engine_id')::uuid
$$;
revoke all on function public.maintenance_jobs(uuid,uuid) from public,anon;
grant execute on function public.maintenance_jobs(uuid,uuid) to authenticated;
