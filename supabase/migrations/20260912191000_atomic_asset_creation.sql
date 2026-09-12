-- Asset and optional first engine commit together. The asset UUID is also the
-- operation identity, so a lost response can be retried without another row.
-- Match the existing engine form's position choices and retain historic kinds.
alter table public.asset_engines drop constraint asset_engines_kind_check;
alter table public.asset_engines add constraint asset_engines_kind_check
 check(kind in ('engine','other','main','port','starboard','wing','generator','auxiliary'));
create function public.create_asset_with_engine(p_data jsonb,p_engine jsonb default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); asset uuid; client uuid; org uuid; receipt public.closeout_operations; payload jsonb;
begin
 if actor is null then raise exception 'Sign in first'; end if;
 if jsonb_typeof(p_data) is distinct from 'object' or (p_engine is not null and jsonb_typeof(p_engine)<>'object')
 then raise exception 'Asset details required'; end if;
 asset:=(p_data->>'id')::uuid; client:=(p_data->>'client_id')::uuid;
 if asset is null or client is null or length(btrim(coalesce(p_data->>'name',''))) not between 1 and 200
 then raise exception 'Asset identity, company and name required'; end if;
 if public.get_my_role()='member' then
  org:=public.active_organization_id();
  perform 1 from public.organization_memberships where organization_id=org and profile_id=actor for share;
  if not exists(select 1 from public.client_orgs where id=org and owner_profile_id=client)
   or not public.organization_has_permission(org,'assets_manage') then raise exception 'Asset management required'; end if;
 elsif public.get_my_role() is distinct from 'owner' or not exists(select 1 from public.legacy_provider_tenants where client_id=client)
 then raise exception 'Asset management required'; end if;
 payload:=jsonb_build_object('asset',p_data,'engine',p_engine);
 perform pg_advisory_xact_lock(hashtextextended(asset::text,0));
 select * into receipt from public.closeout_operations where id=asset;
 if found then
  if receipt.actor_id<>actor or receipt.kind<>'asset_create' or receipt.payload<>payload
  then raise exception 'Retry input differs'; end if;
  return receipt.result;
 end if;
 insert into public.assets(id,client_id,asset_type_id,name,make,model,year,serial_number,location,notes,meter_unit)
 values(asset,client,(p_data->>'asset_type_id')::uuid,btrim(p_data->>'name'),p_data->>'make',p_data->>'model',
 (p_data->>'year')::integer,p_data->>'serial_number',p_data->>'location',p_data->>'notes',coalesce(p_data->>'meter_unit','hours'));
 if p_engine is not null then
  if length(btrim(coalesce(p_engine->>'label',''))) not between 1 and 120 then raise exception 'Engine label required'; end if;
  insert into public.asset_engines(asset_id,label,kind,make,model,serial_number,meter_unit)
  values(asset,btrim(p_engine->>'label'),coalesce(p_engine->>'kind','main'),p_engine->>'make',p_engine->>'model',
   p_engine->>'serial_number',coalesce(p_engine->>'meter_unit','hours'));
 end if;
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(asset,actor,'asset_create',payload,asset);
 return asset;
end $$;

create function public.can_manage_equipment_engine(p_asset uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select public.maintenance_can_view_asset(p_asset) and
 (public.get_my_role()='owner' or (public.get_my_role()='member' and public.organization_asset_permission(p_asset,'assets_manage')))
$$;
create policy organization_engines_read on public.asset_engines for select to authenticated
 using(public.organization_asset_permission(asset_id,'member'));
create policy organization_engines_manage on public.asset_engines for all to authenticated
 using(public.organization_asset_permission(asset_id,'assets_manage'))
 with check(public.organization_asset_permission(asset_id,'assets_manage'));
create policy engine_company_read_boundary on public.asset_engines as restrictive for select to authenticated
 using(public.maintenance_can_view_asset(asset_id));
create policy engine_company_insert_boundary on public.asset_engines as restrictive for insert to authenticated
 with check(public.can_manage_equipment_engine(asset_id));
create policy engine_company_update_boundary on public.asset_engines as restrictive for update to authenticated
 using(public.can_manage_equipment_engine(asset_id)) with check(public.can_manage_equipment_engine(asset_id));
create policy engine_company_delete_boundary on public.asset_engines as restrictive for delete to authenticated
 using(public.can_manage_equipment_engine(asset_id));
create function public.preserve_engine_asset_identity() returns trigger language plpgsql set search_path='' as $$
begin
 if new.asset_id is distinct from old.asset_id then raise exception 'An engine cannot move between assets'; end if;
 return new;
end $$;
create trigger engine_asset_identity before update on public.asset_engines for each row execute function public.preserve_engine_asset_identity();
revoke all on function public.create_asset_with_engine(jsonb,jsonb),public.can_manage_equipment_engine(uuid) from public,anon;
grant execute on function public.create_asset_with_engine(jsonb,jsonb),public.can_manage_equipment_engine(uuid) to authenticated;
revoke all on function public.preserve_engine_asset_identity() from public,anon,authenticated;
