-- Reviewed, bounded, additive fleet imports. Preview performs no writes.
create table public.fleet_import_batches (
 id uuid primary key, actor_id uuid not null references public.profiles(id),
 client_id uuid not null references public.profiles(id), payload jsonb not null,
 result jsonb not null, created_at timestamptz not null default now()
);
alter table public.fleet_import_batches enable row level security;
revoke all on public.fleet_import_batches from anon,authenticated;

create function public.fleet_import_allowed(p_client uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and p_client is not null and
 case when public.get_my_role()='member' then exists(
   select 1 from public.client_orgs o where o.id=public.active_organization_id()
    and o.owner_profile_id=p_client and public.organization_has_permission(o.id,'assets_manage'))
 when public.get_my_role()='owner' then exists(select 1 from public.legacy_provider_tenants where client_id=p_client)
 else false end
$$;

create function public.fleet_import_context(p_client uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare clients jsonb; selected uuid;
begin
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(o.name,p.full_name,p.email)) order by p.full_name),'[]')
 into clients from public.profiles p left join public.client_orgs o on o.owner_profile_id=p.id
 where public.fleet_import_allowed(p.id);
 selected:=coalesce(p_client,(clients->0->>'id')::uuid);
 if not coalesce(public.fleet_import_allowed(selected),false) then raise exception 'Fleet management access required'; end if;
 return jsonb_build_object('clients',clients,'client_id',selected,
 'assets',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'serial_number',serial_number)) from public.assets where client_id=selected),'[]'),
 'templates',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'asset_type_id',t.asset_type_id)) from public.checklist_templates t
  where t.checklist_type='pm' and t.is_active and t.scope_asset_id is null and t.scope_engine_id is null
   and (t.client_id is null or t.client_id=selected) and public.checklist_template_visible(t.id)),'[]'));
end $$;

create function public.import_fleet(p_operation uuid,p_client uuid,p_assets jsonb,p_preview boolean default true)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; c jsonb; plan jsonb; i integer:=0; ci integer; errors jsonb:='[]';
names text[]:='{}'; serials text[]:='{}'; labels text[]; equipment_name text; equipment_serial text; unit text;
 asset uuid; component uuid; plan_id uuid; result jsonb:='[]'; receipt public.fleet_import_batches;
 value numeric; stamp timestamptz; org uuid; total_components integer:=0; primary_count integer; template uuid;
begin
 if not coalesce(public.fleet_import_allowed(p_client),false) then raise exception 'Fleet management access required'; end if;
 if p_operation is null or p_preview is null or jsonb_typeof(p_assets) is distinct from 'array'
  or jsonb_array_length(p_assets) not between 1 and 500 or octet_length(p_assets::text)>2000000
 then raise exception 'Import 1 to 500 equipment records, within 2 MB'; end if;
 org:=public.active_organization_id();
 if public.get_my_role()='member' then
  perform 1 from public.organization_memberships where profile_id=auth.uid() and organization_id=org for share;
  if not public.fleet_import_allowed(p_client) then raise exception 'Fleet management access changed'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('fleet-import:'||p_client::text,0));
 perform pg_advisory_xact_lock(hashtextextended('fleet-import-operation:'||p_operation::text,0));
 select * into receipt from public.fleet_import_batches where id=p_operation;
 if found then
  if receipt.actor_id<>auth.uid() or receipt.client_id<>p_client or receipt.payload<>p_assets then raise exception 'Retry input differs'; end if;
  return receipt.result;
 end if;
 for a in select * from jsonb_array_elements(p_assets) loop
  i:=i+1; ci:=0; labels:='{}'; primary_count:=0;
  begin
   if jsonb_typeof(a) is distinct from 'object' then raise exception 'Equipment row required'; end if;
   equipment_name:=lower(btrim(coalesce(a->>'name',''))); equipment_serial:=lower(btrim(coalesce(a->>'serial_number','')));
   if length(equipment_name) not between 1 and 200 then raise exception 'Equipment name is required (up to 200 characters)'; end if;
   if equipment_name=any(names) or (equipment_serial<>'' and equipment_serial=any(serials)) then raise exception 'Repeated equipment identity in this import'; end if;
   names:=array_append(names,equipment_name); if equipment_serial<>'' then serials:=array_append(serials,equipment_serial); end if;
   if exists(select 1 from public.assets x where x.client_id=p_client and (lower(btrim(x.name))=equipment_name or (equipment_serial<>'' and lower(btrim(x.serial_number))=equipment_serial)))
    then raise exception 'Equipment already exists in this fleet; exclude it or correct its identity'; end if;
   if not exists(select 1 from public.asset_types where id=(a->>'asset_type_id')::uuid) then raise exception 'Choose an equipment type'; end if;
   if coalesce(a->>'meter_unit','') not in ('hours','km','mi') then raise exception 'Choose hours, km or mi'; end if;
   if nullif(a->>'year','') is not null and (a->>'year')::integer not between 1900 and extract(year from now())+2 then raise exception 'Invalid equipment year'; end if;
   if greatest(length(coalesce(a->>'serial_number','')),length(coalesce(a->>'make','')),length(coalesce(a->>'model','')),length(coalesce(a->>'location','')))>200 or length(coalesce(a->>'notes',''))>4000 then raise exception 'Equipment text is too long'; end if;
   if jsonb_typeof(a->'components') is distinct from 'array' or jsonb_array_length(a->'components')>50 then raise exception 'At most 50 components per equipment'; end if;
   for c in select * from jsonb_array_elements(a->'components') loop
    ci:=ci+1; total_components:=total_components+1;
    if coalesce((c->>'primary_meter')::boolean,false) then
     primary_count:=primary_count+1;
     if primary_count>1 or c->>'meter_unit'<>a->>'meter_unit' then raise exception 'Choose one primary meter matching the equipment unit'; end if;
    end if;
    if length(btrim(coalesce(c->>'label',''))) not between 2 and 120 then raise exception 'Component name must contain 2 to 120 characters'; end if;
    if lower(btrim(c->>'label'))=any(labels) then raise exception 'Repeated component name'; end if;
    labels:=array_append(labels,lower(btrim(c->>'label')));
    if coalesce(c->>'meter_unit','') not in ('hours','km','mi') then raise exception 'Invalid component meter unit'; end if;
    if coalesce(c->>'kind','other') not in ('engine','other','main','port','starboard','wing','generator','auxiliary') then raise exception 'Invalid component kind'; end if;
    if greatest(length(coalesce(c->>'serial_number','')),length(coalesce(c->>'make','')),length(coalesce(c->>'model','')))>200 then raise exception 'Component text is too long'; end if;
    value:=nullif(c->>'current_hours','')::numeric;
    if value is not null and (value<0 or value>=1000000000 or value='NaN'::numeric) then raise exception 'Invalid opening meter'; end if;
    if jsonb_typeof(c->'plans') is distinct from 'array' or jsonb_array_length(c->'plans')>25 then raise exception 'At most 25 plans per component'; end if;
    for plan in select * from jsonb_array_elements(c->'plans') loop
     if public.get_my_role()<>'owner' and not exists(select 1 from public.client_capabilities where client_id=p_client and capability_key='maintenance_planning' and enabled) then raise exception 'Enable maintenance planning for this fleet before importing service plans'; end if;
     if public.get_my_role()='member' and not public.organization_has_permission(org,'planning') then raise exception 'Planning permission is required to import service plans'; end if;
     template:=public.checklist_current_template(nullif(plan->>'template_id','')::uuid);
     if nullif(plan->>'template_id','') is not null and (template is null or not exists(select 1 from public.checklist_templates t where t.id=template and t.is_active
       and t.checklist_type='pm' and t.scope_asset_id is null and t.scope_engine_id is null
       and (t.client_id is null or t.client_id=p_client) and (t.asset_type_id is null or t.asset_type_id=(a->>'asset_type_id')::uuid)
       and public.checklist_template_visible(t.id))) then raise exception 'Checklist is unavailable or incompatible with this equipment type'; end if;
     if length(btrim(coalesce(plan->>'interval_label',''))) not between 2 and 200 then raise exception 'Service name required'; end if;
     if coalesce((plan->>'interval_hours')::integer,0)<0 or coalesce((plan->>'interval_hours')::integer,0)>10000000 then raise exception 'Invalid service meter interval'; end if;
     if coalesce((plan->>'interval_hours')::integer,0)>0 and (value is null or nullif(plan->>'last_service_hours','') is null or (plan->>'last_service_hours')::numeric<0 or (plan->>'last_service_hours')::numeric>value) then raise exception 'Service meter baseline must be between zero and the opening meter'; end if;
     if nullif(plan->>'interval_months','') is not null and ((plan->>'interval_months')::integer not between 1 and 120 or nullif(plan->>'last_service_date','') is null) then raise exception 'Calendar interval requires 1 to 120 months and last-service date'; end if;
     if nullif(plan->>'last_service_date','') is not null and ((plan->>'last_service_date')::date>current_date or not isfinite((plan->>'last_service_date')::date)) then raise exception 'Last-service date cannot be in the future'; end if;
     if coalesce((plan->>'interval_hours')::integer,0)=0 and nullif(plan->>'interval_months','') is null then raise exception 'Service interval required'; end if;
    end loop;
   end loop;
  exception when others then
   errors:=errors||jsonb_build_array(jsonb_build_object('row',i,'component',ci,'message',sqlerrm));
  end;
 end loop;
 if total_components>1000 then raise exception 'Import at most 1000 components at a time'; end if;
 if jsonb_array_length(errors)>0 then
  if p_preview then return jsonb_build_object('errors',errors,'assets','[]'::jsonb,'imported',false); end if;
  raise exception 'Import needs review: %',errors;
 end if;
 if p_preview then return jsonb_build_object('errors','[]'::jsonb,'equipment_count',i,'component_count',total_components,'imported',false); end if;
 for a in select * from jsonb_array_elements(p_assets) loop
  asset:=gen_random_uuid();
  perform public.create_asset_with_engine(a||jsonb_build_object('id',asset,'client_id',p_client),null);
  for c in select * from jsonb_array_elements(a->'components') loop
   component:=gen_random_uuid(); unit:=c->>'meter_unit'; value:=nullif(c->>'current_hours','')::numeric;
   insert into public.asset_engines(id,asset_id,label,kind,make,model,serial_number,meter_unit,current_hours)
   values(component,asset,btrim(c->>'label'),coalesce(c->>'kind','other'),c->>'make',c->>'model',c->>'serial_number',unit,null);
   if coalesce((c->>'primary_meter')::boolean,false) then
    if unit<>a->>'meter_unit' or (select primary_meter_engine_id is not null from public.assets where id=asset) then raise exception 'One primary meter with the equipment unit is required'; end if;
    update public.assets set primary_meter_engine_id=component where id=asset;
   end if;
   if value is not null then
    stamp:=clock_timestamp();
    perform public.record_component_meter(gen_random_uuid(),component,asset,value,unit,stamp,'Opening reading from reviewed fleet import '||p_operation::text);
   end if;
   for plan in select * from jsonb_array_elements(c->'plans') loop
    plan_id:=gen_random_uuid();
    perform public.save_maintenance_setup(gen_random_uuid(),'plan',plan_id,0,jsonb_build_object(
      'interval_label',plan->>'interval_label','interval_hours',plan->'interval_hours','interval_months',plan->'interval_months',
      'last_service_hours',plan->'last_service_hours','last_service_date',plan->>'last_service_date','checklist_template_id',plan->>'template_id',
      'asset_id',asset,'engine_id',component,'recurrence_mode','completion','is_active',true,'change_reason','Reviewed fleet import baseline'));
   end loop;
  end loop;
  result:=result||jsonb_build_array(jsonb_build_object('id',asset,'name',a->>'name'));
 end loop;
 result:=jsonb_build_object('errors','[]'::jsonb,'assets',result,'equipment_count',i,'component_count',total_components,'imported',true,'operation_id',p_operation);
 insert into public.fleet_import_batches(id,actor_id,client_id,payload,result) values(p_operation,auth.uid(),p_client,p_assets,result);
 return result;
end $$;
revoke all on function public.fleet_import_allowed(uuid),public.fleet_import_context(uuid),public.import_fleet(uuid,uuid,jsonb,boolean) from public,anon;
grant execute on function public.fleet_import_context(uuid),public.import_fleet(uuid,uuid,jsonb,boolean) to authenticated;
revoke all on function public.fleet_import_allowed(uuid) from authenticated;
