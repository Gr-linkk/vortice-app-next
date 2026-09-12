-- New company workspaces start with the core checklist and work workflows.
-- Keep the existing capability gates and all explicit/legacy configuration.
alter function public.create_company_workspace(text,text)
 rename to create_company_workspace_before_core_defaults;
revoke all on function public.create_company_workspace_before_core_defaults(text,text)
 from public,anon,authenticated;

create function public.create_company_workspace(p_name text,p_full_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare organization uuid; actor uuid:=auth.uid(); initialized jsonb;
begin
 organization:=public.create_company_workspace_before_core_defaults(p_name,p_full_name);
 with added as (
  insert into public.client_capabilities(client_id,capability_key,enabled,updated_by)
  select actor,key,true,actor from unnest(array['pm_checklists','operational_checklists','maintenance_planning']) key
  on conflict(client_id,capability_key) do nothing returning capability_key
 ) select coalesce(jsonb_agg(capability_key order by capability_key),'[]'::jsonb) into initialized from added;
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(organization,actor,'core_capabilities_initialized',jsonb_build_object('capabilities',initialized));
 return organization;
end $$;
revoke all on function public.create_company_workspace(text,text) from public,anon;
grant execute on function public.create_company_workspace(text,text) to authenticated;
