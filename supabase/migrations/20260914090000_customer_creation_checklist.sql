-- NEXT-008: review the scheduled day and attach a checklist during creation.
-- Preserve both older creation overloads for installed builds.
create or replace function public.customer_work_creation_context() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('equipment',coalesce((select jsonb_agg(to_jsonb(visible) order by customer_name,asset_name) from (
  select distinct r.id relationship_id,a.id asset_id,a.name asset_name,c.name customer_name,
   coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'version',t.version) order by t.name,t.version)
    from public.checklist_templates t
    join public.client_orgs provider on provider.id=r.provider_organization_id
    where t.is_active and t.checklist_type='pm'
     and (t.client_id is null or t.client_id=provider.owner_profile_id)
     and (t.asset_type_id is null or t.asset_type_id=a.asset_type_id)
     and (t.scope_asset_id is null or t.scope_asset_id=a.id)
     and (t.scope_engine_id is null or t.scope_engine_id=a.primary_meter_engine_id)), '[]'::jsonb) templates
  from public.organization_relationships r
  join public.organization_service_settings s on s.organization_id=r.provider_organization_id and s.provider_enabled
  join public.work_orders w on w.organization_relationship_id=r.id
  join public.assets a on a.id=w.asset_id
  join public.client_orgs c on c.id=r.client_organization_id and c.owner_profile_id=a.client_id
  where r.provider_organization_id=public.active_organization_id() and r.status='active'
   and public.organization_has_permission(r.provider_organization_id,'assign_work')
   and public.organization_provider_access(w.id)
 ) visible),'[]'::jsonb))
$$;

create function public.create_customer_work(p_operation uuid,p_relationship uuid,p_asset uuid,p_title text,p_note text,p_service_date date,p_checklist_template uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.organization_relationships; receipt public.closeout_operations; payload jsonb;
begin
 select * into r from public.organization_relationships where id=p_relationship for share;
 if p_operation is null or r.id is null or r.status<>'active'
  or r.provider_organization_id is distinct from public.active_organization_id()
  or not public.organization_has_permission(r.provider_organization_id,'assign_work')
  or not exists(select 1 from public.organization_service_settings where organization_id=r.provider_organization_id and provider_enabled)
  or not exists(select 1 from public.assets a join public.client_orgs c on c.owner_profile_id=a.client_id
   where a.id=p_asset and c.id=r.client_organization_id)
  or not exists(select 1 from public.work_orders w where w.organization_relationship_id=r.id and w.asset_id=p_asset and public.organization_provider_access(w.id))
 then raise exception 'Customer equipment is not available for work'; end if;
 if p_title is null or length(btrim(p_title)) not between 3 and 160 or p_note is null or length(btrim(p_note))>4000
 then raise exception 'Enter a work title and details'; end if;
 if p_service_date is not null and (not isfinite(p_service_date) or p_service_date<date '1900-01-01' or p_service_date>date '2200-01-01') then raise exception 'Choose a valid service date'; end if;
 payload:=jsonb_build_object('checklist_template_id',p_checklist_template,'service_date',p_service_date,'relationship_id',p_relationship,'asset_id',p_asset,'title',btrim(p_title),'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
  if receipt.actor_id<>auth.uid() or receipt.kind<>'customer_work_created' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
  return receipt.result;
 end if;
 insert into public.work_orders(id,organization_relationship_id,provider_organization_id,customer_organization_id,asset_id,client_id,created_by,job_type,title,description,status,scheduled_date)
 values(p_operation,r.id,r.provider_organization_id,r.client_organization_id,p_asset,(select client_id from public.assets where id=p_asset),auth.uid(),'repair',btrim(p_title),btrim(p_note),'draft',p_service_date);
 -- Attach after the row exists so the ordinary provider authorization and
 -- immutable checklist/parts snapshot triggers can resolve the work context.
 -- A rejected attachment rolls back the entire creation, including its receipt.
 if p_checklist_template is not null then
  if not public.organization_work_template_allowed(p_operation,p_checklist_template)
   then raise exception 'Choose a published provider checklist for this equipment'; end if;
  update public.work_orders set checklist_template_id=p_checklist_template where id=p_operation;
 end if;
 insert into public.organization_work_report_state(work_order_id) values(p_operation);
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'customer_work_created',payload,p_operation);
 return p_operation;
end $$;

revoke all on function public.create_customer_work(uuid,uuid,uuid,text,text,date,uuid) from public,anon;
grant execute on function public.create_customer_work(uuid,uuid,uuid,text,text,date,uuid) to authenticated;
