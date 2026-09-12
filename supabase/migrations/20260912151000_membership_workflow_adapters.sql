-- Membership context must follow the chosen company through existing native
-- maintenance, assignments and inspection surfaces.
create or replace function public.guard_preop_assignment() returns trigger language plpgsql security definer set search_path='' as $$
declare person public.profiles; company uuid;
begin
 if tg_op='UPDATE' and old.status='completed' and to_jsonb(new) is distinct from to_jsonb(old) then raise exception 'Completed assignments are immutable'; end if;
 if new.status='completed' and (new.completed_run_id is null or not exists(select 1 from public.operator_checklist_runs r
 where r.id=new.completed_run_id and r.assignment_id=new.id and r.operator_id=new.assigned_to)) then raise exception 'Complete an assignment by submitting its checklist'; end if;
 if tg_op='UPDATE' and new.template_id=old.template_id and new.assigned_to=old.assigned_to and new.asset_id is not distinct from old.asset_id and new.org_id=old.org_id then return new; end if;
 if not public.maintenance_can_manage_asset(new.asset_id) then raise exception 'Access denied'; end if;
 if not public.checklist_template_usable(new.template_id,new.asset_id,null,'operator_daily') then raise exception 'Assign a published pre-operation checklist for this equipment'; end if;
 select client_id into company from public.assets where id=new.asset_id;
 select * into person from public.profiles where id=new.assigned_to;
 if person.role='member' then
 if new.org_id is distinct from public.organization_for_asset(new.asset_id)
 or not public.organization_has_permission(new.org_id,'preop',person.id) then raise exception 'Choose a team member from this company'; end if;
 elsif person.role<>'operator' or person.org_id is distinct from new.org_id or not exists(
 select 1 from public.client_orgs where id=person.org_id and owner_profile_id=company) then raise exception 'Choose an operator from this company'; end if;
 if not exists(select 1 from public.client_capabilities where client_id=company and capability_key='operational_checklists' and enabled)
 then raise exception 'Pre-operation checks are disabled'; end if;
 return new;
end $$;
create or replace function public.assign_preop_checklist(p_operation uuid,p_assignment uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare person public.profiles; asset uuid:=(p_data->>'asset_id')::uuid;
begin
 if not public.maintenance_can_manage_asset(asset) then raise exception 'Access denied'; end if;
 if public.maintenance_replayed(p_operation,p_assignment,'preop_assignment',p_data) then return p_assignment; end if;
 select * into person from public.profiles where id=(p_data->>'assigned_to')::uuid;
 if length(coalesce(p_data->>'notes',''))>2000 then raise exception 'Instructions are too long'; end if;
 insert into public.checklist_assignments(id,template_id,asset_id,assigned_to,assigned_by,org_id,due_date,notes)
 values(p_assignment,(p_data->>'template_id')::uuid,asset,person.id,auth.uid(),
 case when person.role='member' then public.organization_for_asset(asset) else person.org_id end,nullif(p_data->>'due_date','')::date,p_data->>'notes');
 perform public.maintenance_record_operation(p_operation,p_assignment,'preop_assignment',p_data);
 return p_assignment;
end $$;
create or replace function public.checklist_assignment_context(p_asset uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('people',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name) order by p.full_name)
 from public.profiles p where (p.role='member' and public.organization_has_permission(public.organization_for_asset(p_asset),'preop',p.id))
 or (p.role='operator' and exists(select 1 from public.client_orgs o join public.assets a on a.client_id=o.owner_profile_id
 where a.id=p_asset and o.id=p.org_id))),'[]'),
 'assignments',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('assignee_name',p.full_name,'template_name',t.name,'template_version',t.version) order by s.created_at desc)
 from public.checklist_assignments s join public.profiles p on p.id=s.assigned_to join public.checklist_templates t on t.id=s.template_id where s.asset_id=p_asset),'[]'))
 where public.maintenance_can_manage_asset(p_asset)
$$;
do $$ declare definition text; updated text; begin
 definition:=pg_get_functiondef('public.maintenance_asset_context(uuid)'::regprocedure);
 updated:=replace(definition,$old$from public.profiles p where (p.role in ('client','client_admin','client_mechanic')$old$,
 $new$from public.profiles p where (p.role='member' and public.organization_has_permission(public.organization_for_asset(a.id),'work_assigned',p.id)) or (p.role in ('client','client_admin','client_mechanic')$new$);
 if updated=definition then raise exception 'Maintenance assignee context adaptation did not match'; end if;
 execute updated;
end $$;

-- A restrictive UPDATE check must examine proposed tenant fields, not only
-- look up the old asset row through its ID.
drop policy organization_assets_update on public.assets;
create policy organization_assets_update on public.assets for update to authenticated
 using(public.organization_asset_permission(id,'assets_manage')) with check(exists(select 1 from public.client_orgs o
 where o.id=public.active_organization_id() and o.owner_profile_id=client_id and public.organization_has_permission(o.id,'assets_manage')));
drop policy modern_asset_update_boundary on public.assets;
create policy modern_asset_update_boundary on public.assets as restrictive for update to authenticated
 using(public.get_my_role()<>'member' or public.organization_asset_permission(id,'assets_manage'))
 with check(public.get_my_role()<>'member' or exists(select 1 from public.client_orgs o where o.id=public.active_organization_id()
 and o.owner_profile_id=client_id and public.organization_has_permission(o.id,'assets_manage')));

-- Old assigned-to/self-owner read policies cannot outlive modern revocation.
do $$ declare tab text; begin
 foreach tab in array array['asset_engines','hour_logs','saved_checklists','checklist_assignments','asset_history_entries','work_orders','service_requests'] loop
 execute format('create policy modern_membership_read_boundary on public.%I as restrictive for select to authenticated using(public.get_my_role()<>''member'' or public.organization_asset_permission(asset_id,''member''))',tab);
 end loop;
end $$;

revoke all on function public.inspection_can_manage(uuid),public.guard_profile_authority() from public,anon;
grant execute on function public.inspection_can_manage(uuid) to authenticated;
