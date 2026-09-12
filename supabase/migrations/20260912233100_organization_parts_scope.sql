-- Preserve the same checked stock ledger while giving modern providers their
-- own company stock. NULL remains exclusively the original provider's scope.
create or replace function public.parts_job_access(p_job uuid,p_manage boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w join public.profiles p on p.id=auth.uid()
 where w.id=p_job and case
 when w.provider_organization_id is not null then public.organization_provider_access(w.id,case when p_manage then 'manage' else 'read' end)
 when w.managed_maintenance then public.maintenance_can_read_job(w.id) and (not p_manage or public.maintenance_can_manage_asset(w.asset_id))
 else p.role='owner' or (not p_manage and p.role='employee' and
 (w.assigned_to=p.id or exists(select 1 from public.work_order_assignments a where a.work_order_id=w.id and a.profile_id=p.id))) end)
$$;

create or replace function public.parts_scope(p_job uuid default null)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare w public.work_orders; p public.profiles; result uuid;
begin
 select * into p from public.profiles where id=auth.uid();
 if p.id is null then raise exception 'Access denied'; end if;
 if p_job is not null then
  if not public.parts_job_access(p_job) then raise exception 'Access denied'; end if;
  select * into w from public.work_orders where id=p_job;
  if w.provider_organization_id is not null then
   select owner_profile_id into result from public.client_orgs where id=w.provider_organization_id;
   if result is null then raise exception 'Provider stock unavailable'; end if;
   return result;
  end if;
  return case when w.managed_maintenance then w.client_id else null end;
 end if;
 if p.role='member' then
  if not public.organization_has_permission(public.active_organization_id(),'parts') then raise exception 'Access denied'; end if;
  select owner_profile_id into result from public.client_orgs where id=public.active_organization_id();
  if result is null then raise exception 'Company stock unavailable'; end if;
  return result;
 end if;
 if p.role in ('owner','employee') then return null; end if;
 if p.role not in ('client','client_admin','client_mechanic') then raise exception 'Access denied'; end if;
 select owner_profile_id into result from public.client_orgs where id=p.org_id;
 if result is null and p.role='client' then result:=p.id; end if;
 if result is null then raise exception 'Access denied'; end if;
 return result;
end $$;

create function public.parts_scope_manager(p_job uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select case when p_job is not null then public.parts_job_access(p_job,true)
 else exists(select 1 from public.profiles p where p.id=auth.uid() and
 case when p.role='member' then public.organization_has_permission(public.active_organization_id(),'planning')
 else p.role in ('owner','client','client_admin') end) end
$$;
revoke all on function public.parts_scope_manager(uuid) from public,anon;
grant execute on function public.parts_scope_manager(uuid) to authenticated;

do $$
declare definition text; signature text; marker text;
begin
 foreach signature in array array['public.parts_workspace(uuid)','public.parts_change(uuid,uuid,text,jsonb)'] loop
  select replace(pg_get_functiondef(signature::regprocedure),chr(13),'') into definition;
  marker:=replace($m$manager:=case when p_job is not null then public.parts_job_access(p_job,true)
 else exists(select 1 from public.profiles where id=auth.uid() and role in ('owner','client','client_admin')) end;$m$,chr(13),'');
  if strpos(definition,marker)=0 then raise exception 'Parts manager adaptation did not match %',signature; end if;
  definition:=replace(definition,marker,'manager:=public.parts_scope_manager(p_job);');
  if signature='public.parts_workspace(uuid)' then
   marker:='(not w.managed_maintenance or public.maintenance_can_work_job(w.id))';
   if strpos(definition,marker)=0 then raise exception 'Parts workspace access adaptation did not match'; end if;
   definition:=replace(definition,marker,'(case when w.provider_organization_id is not null then public.organization_provider_access(w.id,''work'') else not w.managed_maintenance or public.maintenance_can_work_job(w.id) end)');
  else
   marker:='previous.actor_id<>auth.uid() or previous.work_order_id is distinct from p_job or previous.action<>p_action or previous.payload<>p_data';
   if strpos(definition,marker)=0 then raise exception 'Parts replay scope adaptation did not match'; end if;
   definition:=replace(definition,marker,marker||' or previous.client_id is distinct from scope');
   marker:='if w.managed_maintenance and not public.maintenance_can_work_job(p_job) then raise exception ''Access denied''; end if;';
   if strpos(definition,marker)=0 then raise exception 'Parts write access adaptation did not match'; end if;
   definition:=replace(definition,marker,marker||E'\n  if w.provider_organization_id is not null and not public.organization_provider_access(p_job,''work'') then raise exception ''Access denied''; end if;');
  end if;
  execute definition;
 end loop;
end $$;

-- Provider requests begin without a checklist; configuring their first one
-- captures its parts exactly once just as INSERT does for internal work.
create function public.guard_provider_parts_template() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.provider_organization_id is not null and old.parts_kit_captured
  and new.checklist_template_id is distinct from old.checklist_template_id then
  raise exception 'This work already captured its parts kit. Create separate work to use another checklist.';
 end if;
 return new;
end $$;
create trigger guard_provider_parts_template before update of checklist_template_id on public.work_orders
 for each row execute function public.guard_provider_parts_template();
create trigger capture_configured_provider_parts after update of checklist_template_id on public.work_orders
 for each row when(new.provider_organization_id is not null and not new.parts_kit_captured
 and new.checklist_template_id is not null and new.checklist_template_id is distinct from old.checklist_template_id)
 execute function public.capture_job_parts();
revoke all on function public.guard_provider_parts_template() from public,anon,authenticated;
