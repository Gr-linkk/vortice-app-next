-- NEXT-002.06: state-aware steps and immutable, exact-page procedure links.
alter function public.validate_checklist_draft(jsonb,uuid,boolean) rename to validate_checklist_draft_before_sources;
create function public.validate_checklist_draft(p_data jsonb,p_client uuid,p_publish boolean)
returns void language plpgsql security definer set search_path='' as $$
declare item jsonb; def jsonb; source jsonb;
begin
 perform public.validate_checklist_draft_before_sources(p_data,p_client,p_publish);
 for item in select * from jsonb_array_elements(p_data->'items') loop
  def:=coalesce(item->'definition','{}');
  if coalesce(def->>'equipment_state','') not in ('','walk_around','stopped','before_start','start_up','running','shutdown','isolated','maintenance','restart','verification') then raise exception 'Choose a supported equipment state'; end if;
  source:=case when def ? 'procedure_source' and def->'procedure_source'<>'null'::jsonb then def->'procedure_source'
   when nullif(def->>'source_document_id','') is not null then jsonb_build_object('document_id',def->'source_document_id','page',def->'source_page') end;
  if source is not null then
   if jsonb_typeof(source)<>'object' or length(coalesce(source->>'section',''))>200 or not exists(
    select 1 from public.maintenance_documents d join public.maintenance_document_pages p on p.document_id=d.id
    where d.id::text=source->>'document_id' and p.page::text=source->>'page' and d.client_id=p_client
     and not d.archived and public.agent_can_manage_fleet(d.client_id)) then
     raise exception 'Choose a saved procedure page in this company';
   end if;
  end if;
 end loop;
end $$;
revoke all on function public.validate_checklist_draft_before_sources(jsonb,uuid,boolean),public.validate_checklist_draft(jsonb,uuid,boolean) from public,anon,authenticated;

create function public.checklist_source_reader(p_template uuid,p_item uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.checklist_items i
 join public.checklist_templates t on t.id=i.template_id where i.id=p_item and t.id=p_template and (
  public.checklist_can_author(t.client_id,t.checklist_type)
  or exists(select 1 from public.assets a where public.coordination_asset_viewer(a.id,auth.uid())
   and public.checklist_template_usable(t.id,a.id,null,t.checklist_type))
  or exists(select 1 from public.checklist_assignments a where a.template_id=t.id and a.assigned_to=auth.uid()
   and a.status in ('pending','in_progress') and public.coordination_asset_viewer(a.asset_id,auth.uid()))
  or exists(select 1 from public.work_order_checklist_snapshots s where s.template_id=t.id
   and public.coordination_subject_reader('job',s.work_order_id,auth.uid())
   and exists(select 1 from jsonb_array_elements(s.items_json) x where x->>'id'=i.id::text))
 ))
$$;
revoke all on function public.checklist_source_reader(uuid,uuid) from public,anon,authenticated;

create function public.checklist_source_page(p_template uuid default null,p_item uuid default null,p_document uuid default null,p_page integer default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare source jsonb; result jsonb;
begin
 if auth.uid() is null then raise exception 'Access denied' using errcode='42501'; end if;
 if p_item is not null or p_template is not null then
  if not coalesce(public.checklist_source_reader(p_template,p_item),false) then raise exception 'Access denied' using errcode='42501'; end if;
  select coalesce(nullif(definition->'procedure_source','null'::jsonb),jsonb_build_object('document_id',definition->'source_document_id','page',definition->'source_page')) into source from public.checklist_items where id=p_item and template_id=p_template;
  if source->>'document_id' is distinct from p_document::text or source->>'page' is distinct from p_page::text then raise exception 'Procedure source changed' using errcode='42501'; end if;
 elsif not exists(select 1 from public.maintenance_documents where id=p_document and public.agent_can_manage_fleet(client_id)) then
  raise exception 'Access denied' using errcode='42501';
 end if;
 select jsonb_build_object('document_id',d.id,'title',d.title,'page',p.page,'object_path',p.object_path)
 into result from public.maintenance_documents d join public.maintenance_document_pages p on p.document_id=d.id
 where d.id=p_document and p.page=p_page;
 if result is null then raise exception 'Procedure unavailable' using errcode='42501'; end if;
 return result;
end $$;
revoke all on function public.checklist_source_page(uuid,uuid,uuid,integer) from public,anon;
grant execute on function public.checklist_source_page(uuid,uuid,uuid,integer) to authenticated;

alter function public.maintenance_document_object_access(text,boolean) rename to maintenance_document_object_access_before_sources;
create function public.maintenance_document_object_access(p_path text,p_write boolean)
returns boolean language sql stable security definer set search_path='' as $$
 select public.maintenance_document_object_access_before_sources(p_path,p_write)
 or (not p_write and exists(select 1 from public.maintenance_document_pages p
  join public.maintenance_documents d on d.id=p.document_id
  join public.checklist_items i on (
   coalesce(i.definition->'procedure_source'->>'document_id',i.definition->>'source_document_id')=d.id::text
   and coalesce(i.definition->'procedure_source'->>'page',i.definition->>'source_page')=p.page::text)
  join public.checklist_templates t on t.id=i.template_id and t.client_id=d.client_id
  where p.object_path=p_path and public.checklist_source_reader(t.id,i.id)))
$$;
revoke all on function public.maintenance_document_object_access_before_sources(text,boolean) from public,anon,authenticated;
grant execute on function public.maintenance_document_object_access(text,boolean) to authenticated;
-- Existing policy expression points to the old function OID after rename.
alter policy maintenance_document_upload on storage.objects with check(bucket_id='maintenance-documents' and public.maintenance_document_object_access(name,true));
alter policy maintenance_document_read on storage.objects using(bucket_id='maintenance-documents' and public.maintenance_document_object_access(name,false));
