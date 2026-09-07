-- Human review evidence uses the existing fleet/asset boundaries. Read-only;
-- it cannot publish checklists or apply maintenance proposals.
create function public.agent_plan_review_context(p_draft uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.agent_plan_drafts; doc public.maintenance_documents; procedure jsonb;
 history jsonb; component uuid; existing uuid; total integer;
begin
 select * into p from public.agent_plan_drafts where id=p_draft;
 if p.id is null or not public.agent_can_manage_fleet(p.client_id)
  or not public.maintenance_can_manage_asset(p.asset_id) then raise exception 'Access denied'; end if;
 select * into doc from public.maintenance_documents where id=p.document_id and client_id=p.client_id;
 if doc.id is null then raise exception 'Source unavailable'; end if;
 component:=(p.draft->>'engine_id')::uuid;
 existing:=coalesce((p.draft->>'existing_plan_id')::uuid,p.applied_plan_id);
 if p.draft ? 'checklist_procedure_id' then
  select jsonb_build_object('id',c.id,'name',c.draft->>'name','published_template_id',c.published_template_id,'archived',c.archived)
   into procedure from public.checklist_procedures c
   where c.id=(p.draft->>'checklist_procedure_id')::uuid and c.client_id=p.client_id;
 end if;
 select count(*) into total from public.work_orders w join public.maintenance_job_records j on j.id=w.id
  where w.asset_id=p.asset_id and w.engine_id=component and j.service_applied_at is not null
   and public.maintenance_can_read_job(w.id);
 select coalesce(jsonb_agg(x order by x.service_applied_at desc,x.work_order_id),'[]') into history from (
  select w.id work_order_id,w.title,w.hours_at_end,j.service_applied_at,
   coalesce(j.service_interval_id=existing,false) matches_task
  from public.work_orders w join public.maintenance_job_records j on j.id=w.id
  where w.asset_id=p.asset_id and w.engine_id=component and j.service_applied_at is not null
   and public.maintenance_can_read_job(w.id)
  order by j.service_applied_at desc,w.id limit 20
 ) x;
 return jsonb_build_object('proposal',to_jsonb(p),'catalog',public.maintenance_asset_context(p.asset_id),
  'procedure',procedure,'document',jsonb_build_object('title',doc.title,'created_at',doc.created_at),
  'meter_log',(select jsonb_build_object('hours',h.hours,'logged_at',h.logged_at) from public.hour_logs h
   where h.asset_id=p.asset_id and h.engine_id=component order by h.logged_at desc,h.id desc limit 1),
  'approved_services',history,'services_truncated',total>20);
end $$;
revoke all on function public.agent_plan_review_context(uuid) from public,anon;
grant execute on function public.agent_plan_review_context(uuid) to authenticated;
