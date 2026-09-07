-- NOW-015: private company drafts and immutable published checklist versions.
-- Baseline policies call this helper even from triggers with an empty path.
create or replace function public.get_my_role() returns text language sql stable security definer set search_path='' as $$
 select role from public.profiles where id=auth.uid()
$$;
create table public.checklist_procedures (
 id uuid primary key,
 client_id uuid references public.profiles(id),
 created_by uuid not null references public.profiles(id),
 draft jsonb not null default '{}',
 revision integer not null default 0,
 published_revision integer not null default 0,
 published_template_id uuid references public.checklist_templates(id),
 archived boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table public.checklist_templates
 add column procedure_id uuid references public.checklist_procedures(id),
 add column client_id uuid references public.profiles(id),
 add column scope_asset_id uuid references public.assets(id),
 add column scope_engine_id uuid references public.asset_engines(id);
create unique index checklist_procedure_version on public.checklist_templates(procedure_id,version);
alter table public.checklist_items add column definition jsonb not null default '{}';
create table public.checklist_builder_operations (
 id uuid primary key,
 actor_id uuid not null references public.profiles(id),
 procedure_id uuid not null references public.checklist_procedures(id),
 action text not null,
 payload jsonb not null,
 result uuid not null,
 created_at timestamptz not null default now()
);

create function public.checklist_company() returns uuid language sql stable security definer set search_path='' as $$
 select case when p.role in ('owner','employee') then null
  else coalesce((select o.owner_profile_id from public.client_orgs o where o.id=p.org_id),p.id) end
 from public.profiles p where p.id=auth.uid()
$$;
create function public.checklist_can_author(p_client uuid,p_kind text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and
  ((p.role='owner' and p_client is null) or
   (p.role in ('client','client_admin') and p_client=public.checklist_company() and exists(
    select 1 from public.client_capabilities c where c.client_id=p_client and c.enabled
     and c.capability_key=case p_kind when 'operator_daily' then 'operational_checklists' else 'pm_checklists' end))))
$$;
create function public.checklist_template_visible(p_template uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.checklist_templates t join public.profiles p on p.id=auth.uid()
  where t.id=p_template and (t.client_id is null or t.client_id=public.checklist_company() or p.role in ('owner','employee'))
   and (p.role in ('owner','employee','client','client_admin')
    or (p.role='client_mechanic' and t.checklist_type='pm')
    or (p.role='operator' and t.checklist_type='operator_daily')))
$$;
create function public.checklist_template_usable(p_template uuid,p_asset uuid,p_engine uuid,p_kind text,p_new boolean default true)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.checklist_templates t join public.assets a on a.id=p_asset
  where t.id=p_template and public.maintenance_can_view_asset(a.id)
   and public.checklist_template_visible(t.id) and (t.client_id is null or t.client_id=a.client_id)
   and (not p_new or t.is_active) and t.checklist_type=p_kind
   and (t.asset_type_id is null or t.asset_type_id=a.asset_type_id)
   and (t.scope_asset_id is null or t.scope_asset_id=a.id)
   and (t.scope_engine_id is null or t.scope_engine_id=p_engine))
$$;
alter table public.checklist_procedures enable row level security;
alter table public.checklist_builder_operations enable row level security;
create policy checklist_drafts_read on public.checklist_procedures for select to authenticated
 using(public.checklist_can_author(client_id,coalesce(draft->>'checklist_type','pm')));
create policy checklist_builder_operations_read on public.checklist_builder_operations for select to authenticated using(actor_id=auth.uid());
grant select on public.checklist_procedures,public.checklist_builder_operations to authenticated;
create policy checklist_template_company_boundary on public.checklist_templates as restrictive
 for select to authenticated using(public.checklist_template_visible(id));
create policy checklist_library_read on public.checklist_templates
 for select to authenticated using(public.checklist_template_visible(id));
create policy checklist_item_company_boundary on public.checklist_items as restrictive
 for select to authenticated using(public.checklist_template_visible(template_id));
create policy checklist_library_items_read on public.checklist_items
 for select to authenticated using(public.checklist_template_visible(template_id));

create function public.guard_published_checklist() returns trigger language plpgsql set search_path='' as $$
declare template uuid; managed uuid;
begin
 if tg_table_name='checklist_templates' then
  if tg_op='INSERT' then
   if new.procedure_id is not null and current_user in ('authenticated','anon') then raise exception 'Publish through the checklist builder'; end if;
   return new;
  end if;
  if tg_op='UPDATE' and new.procedure_id is distinct from old.procedure_id then raise exception 'Published checklist ownership is immutable'; end if;
  if old.procedure_id is not null then
   if tg_op='DELETE' then
    if current_user in ('authenticated','anon') then raise exception 'Published checklists are immutable'; end if;
    return old;
   end if;
   if current_user in ('authenticated','anon') or
    (to_jsonb(new)-'is_active'-'updated_at') is distinct from (to_jsonb(old)-'is_active'-'updated_at')
     then raise exception 'Published checklists are immutable'; end if;
  end if;
 else
  template:=case when tg_op='DELETE' then old.template_id else new.template_id end;
  select procedure_id into managed from public.checklist_templates where id=template;
  if managed is not null and (tg_op='UPDATE' or current_user in ('authenticated','anon')) then
   raise exception 'Published checklist items are immutable';
  end if;
  if tg_op='UPDATE' and old.template_id<>new.template_id and exists(
   select 1 from public.checklist_templates where id=old.template_id and procedure_id is not null)
   then raise exception 'Published checklist items are immutable'; end if;
 end if;
 if tg_op='DELETE' then return old; end if; return new;
end $$;
create trigger protect_published_template before insert or update or delete on public.checklist_templates
 for each row execute function public.guard_published_checklist();
create trigger protect_published_items before insert or update or delete on public.checklist_items
 for each row execute function public.guard_published_checklist();

create function public.validate_checklist_draft(p_data jsonb,p_client uuid,p_publish boolean)
returns void language plpgsql security definer set search_path='' as $$
declare item jsonb; definition jsonb; kind text; target uuid; component uuid; lower_limit numeric; upper_limit numeric;
begin
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Checklist details are required'; end if;
 if coalesce(p_data->>'checklist_type','') not in ('pm','operator_daily') then raise exception 'Choose PM or pre-operation'; end if;
 if length(btrim(coalesce(p_data->>'name','')))<3 or length(p_data->>'name')>160 then raise exception 'Name must contain 3 to 160 characters'; end if;
 if length(coalesce(p_data->>'description',''))>4000 then raise exception 'Instructions are too long'; end if;
 if jsonb_typeof(p_data->'items') is distinct from 'array' or jsonb_array_length(p_data->'items')>100 then raise exception 'Use at most 100 checklist steps'; end if;
 if p_publish and jsonb_array_length(p_data->'items')=0 then raise exception 'Add at least one step before publishing'; end if;
 if nullif(p_data->>'asset_type_id','') is not null and not exists(select 1 from public.asset_types where id=(p_data->>'asset_type_id')::uuid)
  then raise exception 'Choose an equipment type'; end if;
 target:=nullif(p_data->>'scope_asset_id','')::uuid; component:=nullif(p_data->>'scope_engine_id','')::uuid;
 if target is not null and not exists(select 1 from public.assets a where a.id=target and public.maintenance_can_view_asset(a.id)
  and (p_client is null or a.client_id=p_client) and (nullif(p_data->>'asset_type_id','') is null or a.asset_type_id=(p_data->>'asset_type_id')::uuid))
  then raise exception 'Choose equipment in this company and type'; end if;
 if component is not null and (target is null or not exists(select 1 from public.asset_engines where id=component and asset_id=target))
  then raise exception 'Choose a component on the selected equipment'; end if;
 if p_data->>'checklist_type'='operator_daily' and component is not null then raise exception 'Pre-operation checks apply to equipment, not a PM component'; end if;
 for item in select * from jsonb_array_elements(p_data->'items') loop
  if jsonb_typeof(item) is distinct from 'object' or length(btrim(coalesce(item->>'description_en','')))<3
   or length(item->>'description_en')>2000 or length(coalesce(item->>'description_es',''))>2000
   or length(coalesce(item->>'category',''))>100 then raise exception 'Each step needs an instruction of 3 to 2000 characters'; end if;
  definition:=coalesce(item->'definition','{}'); kind:=coalesce(definition->>'input_type','check');
  if jsonb_typeof(definition)<>'object' or kind not in ('check','number','text') then raise exception 'Choose a supported response type'; end if;
  if length(coalesce(definition->>'guidance',''))>2000 or length(coalesce(definition->>'unit',''))>40 then raise exception 'Step guidance or units are too long'; end if;
  perform coalesce((definition->>'critical')::boolean,false),coalesce((definition->>'allow_na')::boolean,true),coalesce((item->>'requires_photo')::boolean,false);
  lower_limit:=nullif(definition->>'min','')::numeric; upper_limit:=nullif(definition->>'max','')::numeric;
  if lower_limit::text in ('NaN','Infinity','-Infinity') or upper_limit::text in ('NaN','Infinity','-Infinity')
   or lower_limit>upper_limit then raise exception 'Enter valid numeric limits'; end if;
  if kind<>'number' and (lower_limit is not null or upper_limit is not null) then raise exception 'Only numeric steps have limits'; end if;
 end loop;
end $$;

create function public.save_checklist_procedure(p_request uuid,p_id uuid,p_revision integer,p_action text,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare procedure public.checklist_procedures; prior public.checklist_builder_operations; company uuid;
 template uuid; item jsonb; n integer:=0; version_number integer; source uuid;
begin
 if auth.uid() is null or p_request is null or p_id is null then raise exception 'Access denied'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request::text,0));
 select * into prior from public.checklist_builder_operations where id=p_request;
 if found then
  if prior.actor_id<>auth.uid() or prior.procedure_id<>p_id or prior.action<>p_action or prior.payload is distinct from p_data
   then raise exception 'Identifier already used for different input'; end if;
  return prior.result;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
 select * into procedure from public.checklist_procedures where id=p_id for update;
 company:=case when procedure.id is null then public.checklist_company() else procedure.client_id end;
 if not public.checklist_can_author(company,coalesce(procedure.draft->>'checklist_type',p_data->>'checklist_type','pm'))
  then raise exception 'Access denied'; end if;
 if p_revision is distinct from coalesce(procedure.revision,0) then raise exception 'This checklist changed; reload before editing' using errcode='40001'; end if;
 if p_action='draft' then
  if not public.checklist_can_author(company,p_data->>'checklist_type') then raise exception 'Access denied'; end if;
  perform public.validate_checklist_draft(p_data,company,false);
  source:=nullif(p_data->>'source_template_id','')::uuid;
  if source is not null and not public.checklist_template_visible(source) then raise exception 'Access denied'; end if;
  if procedure.id is not null and procedure.archived then raise exception 'Copy an archived checklist to make changes'; end if;
  if procedure.published_template_id is not null and procedure.draft->>'checklist_type'<>p_data->>'checklist_type'
   then raise exception 'Copy the checklist to change its purpose'; end if;
  insert into public.checklist_procedures(id,client_id,created_by,draft,revision)
   values(p_id,company,auth.uid(),case when source is null then p_data else p_data||jsonb_build_object('source_version',
    (select version from public.checklist_templates where id=source)) end,1)
   on conflict(id) do update set draft=excluded.draft,revision=public.checklist_procedures.revision+1,updated_at=now();
  template:=p_id;
 elsif p_action='publish' then
  if procedure.id is null or procedure.archived then raise exception 'Save a draft before publishing'; end if;
  if procedure.published_revision=procedure.revision then raise exception 'No draft changes to publish'; end if;
  perform public.validate_checklist_draft(procedure.draft,company,true);
  select coalesce(max(version),0)+1 into version_number from public.checklist_templates where procedure_id=p_id;
  template:=gen_random_uuid();
  insert into public.checklist_templates(id,procedure_id,client_id,scope_asset_id,scope_engine_id,
   asset_type_id,checklist_type,name,description,version,created_by)
  values(template,p_id,company,nullif(procedure.draft->>'scope_asset_id','')::uuid,nullif(procedure.draft->>'scope_engine_id','')::uuid,
   nullif(procedure.draft->>'asset_type_id','')::uuid,procedure.draft->>'checklist_type',btrim(procedure.draft->>'name'),procedure.draft->>'description',version_number,auth.uid());
  for item in select * from jsonb_array_elements(procedure.draft->'items') loop
   insert into public.checklist_items(template_id,description_en,description_es,category,requires_photo,sort_order,definition)
   values(template,btrim(item->>'description_en'),nullif(btrim(item->>'description_es'),''),item->>'category',
    coalesce((item->>'requires_photo')::boolean,false),n,coalesce(item->'definition','{}')||'{"authored":true}'::jsonb);
   n:=n+1;
  end loop;
  update public.checklist_templates set is_active=false,updated_at=now() where procedure_id=p_id and id<>template and is_active;
  update public.checklist_procedures set published_template_id=template,revision=revision+1,published_revision=revision+1,updated_at=now() where id=p_id;
 elsif p_action='archive' then
  if procedure.id is null then raise exception 'Checklist not found'; end if;
  update public.checklist_templates set is_active=false,updated_at=now() where procedure_id=p_id and is_active;
  update public.checklist_procedures set archived=true,revision=revision+1,updated_at=now() where id=p_id;
  template:=p_id;
 else raise exception 'Unknown checklist action'; end if;
 insert into public.checklist_builder_operations(id,actor_id,procedure_id,action,payload,result)
 values(p_request,auth.uid(),p_id,p_action,p_data,template);
 return template;
end $$;
revoke all on function public.save_checklist_procedure(uuid,uuid,integer,text,jsonb),public.validate_checklist_draft(jsonb,uuid,boolean) from public,anon;
grant execute on function public.save_checklist_procedure(uuid,uuid,integer,text,jsonb) to authenticated;

create function public.checklist_library() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
 'can_pm',public.checklist_can_author(public.checklist_company(),'pm'),
 'can_preop',public.checklist_can_author(public.checklist_company(),'operator_daily'),
 'client_id',public.checklist_company(),
 'procedures',coalesce((select jsonb_agg(to_jsonb(p) order by p.updated_at desc) from public.checklist_procedures p
  where public.checklist_can_author(p.client_id,p.draft->>'checklist_type')),'[]'),
 'templates',coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object('items',
  coalesce((select jsonb_agg(to_jsonb(i) order by i.sort_order,i.id) from public.checklist_items i where i.template_id=t.id),'[]')) order by t.name,t.version desc)
  from public.checklist_templates t where t.is_active and public.checklist_template_visible(t.id)),'[]'),
 'asset_types',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.asset_types),'[]'),
 'assets',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'asset_type_id',a.asset_type_id,'client_id',a.client_id,
  'components',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'name',e.label) order by e.label) from public.asset_engines e where e.asset_id=a.id),'[]')) order by a.name)
  from public.assets a where public.maintenance_can_view_asset(a.id)),'[]'))
 where auth.uid() is not null
$$;
revoke all on function public.checklist_library() from public,anon;
grant execute on function public.checklist_library() to authenticated;

create function public.checklist_current_template(p_template uuid) returns uuid language sql stable security definer set search_path='' as $$
 select coalesce(p.published_template_id,t.id) from public.checklist_templates t
 left join public.checklist_procedures p on p.id=t.procedure_id where t.id=p_template and public.checklist_template_visible(t.id)
$$;

-- Provider work orders previously attempted best-effort snapshots into a table
-- absent from Next's baseline. Freeze the real published procedure in the DB.
create table public.work_order_checklist_snapshots (
 work_order_id uuid primary key references public.work_orders(id) on delete cascade,
 template_id uuid references public.checklist_templates(id),
 template_version integer,
 template_name text not null,
 template_description text,
 checklist_type text not null,
 asset_type_id uuid,
 interval_hours integer,
 interval_label text,
 source_template_updated_at timestamptz,
 items_json jsonb not null,
 updated_at timestamptz not null default now()
);
alter table public.work_order_checklist_snapshots enable row level security;
grant select on public.work_order_checklist_snapshots to authenticated;
create policy work_order_snapshot_read on public.work_order_checklist_snapshots for select to authenticated
 using(exists(select 1 from public.work_orders w where w.id=work_order_id));

create function public.guard_work_order_checklist() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.checklist_template_id is not distinct from old.checklist_template_id
  and new.asset_id is not distinct from old.asset_id and new.engine_id is not distinct from old.engine_id
  and new.client_id is not distinct from old.client_id and new.checklist_template_version is not distinct from old.checklist_template_version then return new; end if;
 if tg_op='UPDATE' and (old.started_at is not null or old.status not in ('draft','assigned') or exists(
  select 1 from public.checklist_responses where work_order_id=old.id)) then raise exception 'Checklist cannot change after work starts'; end if;
 if new.checklist_template_id is not null then
  if not exists(select 1 from public.assets where id=new.asset_id and client_id=new.client_id) then raise exception 'Work order company must match its equipment'; end if;
  if auth.uid() is not null and not public.checklist_template_usable(new.checklist_template_id,new.asset_id,new.engine_id,'pm')
   then raise exception 'Checklist is unavailable for this equipment'; end if;
  select version into new.checklist_template_version from public.checklist_templates where id=new.checklist_template_id;
 end if;
 return new;
end $$;
create trigger work_order_checklist_guard before insert or update of checklist_template_id,checklist_template_version,asset_id,engine_id,client_id on public.work_orders
 for each row execute function public.guard_work_order_checklist();
create function public.freeze_work_order_checklist() returns trigger language plpgsql security definer set search_path='' as $$
declare t public.checklist_templates;
begin
 if tg_op='UPDATE' and new.checklist_template_id is not distinct from old.checklist_template_id then return new; end if;
 if new.checklist_template_id is null then
  delete from public.work_order_checklist_snapshots where work_order_id=new.id; return new;
 end if;
 select * into t from public.checklist_templates where id=new.checklist_template_id;
 insert into public.work_order_checklist_snapshots(work_order_id,template_id,template_version,template_name,template_description,
  checklist_type,asset_type_id,interval_hours,interval_label,source_template_updated_at,items_json)
 values(new.id,t.id,t.version,t.name,t.description,t.checklist_type,t.asset_type_id,t.interval_hours,t.interval_label,t.updated_at,
  coalesce((select jsonb_agg(to_jsonb(i) order by sort_order,id) from public.checklist_items i where template_id=t.id),'[]'))
 on conflict(work_order_id) do update set template_id=excluded.template_id,template_version=excluded.template_version,
  template_name=excluded.template_name,template_description=excluded.template_description,checklist_type=excluded.checklist_type,
  asset_type_id=excluded.asset_type_id,interval_hours=excluded.interval_hours,interval_label=excluded.interval_label,
  source_template_updated_at=excluded.source_template_updated_at,items_json=excluded.items_json,updated_at=now();
 return new;
end $$;
create trigger work_order_checklist_snapshot after insert or update of checklist_template_id on public.work_orders
 for each row execute function public.freeze_work_order_checklist();

create function public.guard_plan_checklist() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.checklist_template_id is not distinct from old.checklist_template_id
  and new.asset_id=old.asset_id and new.engine_id is not distinct from old.engine_id then return new; end if;
 if new.checklist_template_id is not null and auth.uid() is not null
  and not public.checklist_template_usable(new.checklist_template_id,new.asset_id,new.engine_id,'pm')
  then raise exception 'Checklist is unavailable for this component'; end if;
 return new;
end $$;
create trigger plan_checklist_guard before insert or update of checklist_template_id,asset_id,engine_id on public.asset_service_intervals
 for each row execute function public.guard_plan_checklist();

-- Rich answers reuse the established per-item notes value for numeric/text
-- input, preserving local drafts, sync and readable historical responses.
create function public.validate_checklist_answer(p_definition jsonb,p_result text,p_value text)
returns void language plpgsql immutable set search_path='' as $$
declare kind text:=coalesce(p_definition->>'input_type','check'); number numeric; outside boolean;
begin
 if p_result in ('na','n/a') then
  if not coalesce((p_definition->>'allow_na')::boolean,true) then raise exception 'This step cannot be marked not applicable'; end if;
  return;
 end if;
 if kind='text' and length(btrim(coalesce(p_value,'')))<1 then raise exception 'Enter a response for every text step'; end if;
 if length(coalesce(p_value,''))>4000 then raise exception 'Step response is too long'; end if;
 if kind='number' then
  begin number:=btrim(p_value)::numeric; exception when others then raise exception 'Enter a valid numeric reading'; end;
  if number is null or number::text in ('NaN','Infinity','-Infinity') then raise exception 'Enter a valid numeric reading'; end if;
  outside:=coalesce(number<nullif(p_definition->>'min','')::numeric,false) or coalesce(number>nullif(p_definition->>'max','')::numeric,false);
  if outside and p_result not in ('fail','action') then raise exception 'Out-of-range readings must be flagged'; end if;
 end if;
end $$;
create function public.guard_rich_pm_answer() returns trigger language plpgsql security definer set search_path='' as $$
declare item public.checklist_items; w public.work_orders;
begin
 select * into item from public.checklist_items where id=new.checklist_item_id;
 if not exists(select 1 from public.checklist_templates where id=item.template_id and procedure_id is not null) then return new; end if;
 select * into w from public.work_orders where id=new.work_order_id;
 if w.status in ('pending_review','invoiced','closed') then raise exception 'Submitted checklist answers are locked'; end if;
 if w.checklist_template_id is distinct from item.template_id then raise exception 'Step does not belong to this work order checklist'; end if;
 perform public.validate_checklist_answer(item.definition,coalesce(new.response_status,case when new.completed then 'pass' else 'action' end),new.notes);
 return new;
end $$;
create trigger rich_pm_answer_guard before insert or update on public.checklist_responses for each row execute function public.guard_rich_pm_answer();

create function public.checklist_photo_exists(p_photos text,p_run text,p_item uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare photos jsonb; photo text; object_path text; asset uuid;
begin
 if left(p_run,6)='asset_' then asset:=substring(p_run from 7)::uuid;
 else select asset_id into asset from public.work_orders where id=p_run::uuid; end if;
 if not public.maintenance_can_view_asset(asset) then return false; end if;
 if nullif(btrim(p_photos),'') is null then return false; end if;
 begin photos:=case when left(btrim(p_photos),1)='[' then p_photos::jsonb else jsonb_build_array(p_photos) end;
 exception when others then return false; end;
 if jsonb_typeof(photos)<>'array' or jsonb_array_length(photos)=0 then return false; end if;
 for photo in select jsonb_array_elements_text(photos) loop
  object_path:=replace(photo,'https://hkjpojobdbbtjkhaudki.supabase.co/storage/v1/object/public/service-report-photos/','');
  if starts_with(object_path,'checklists/'||p_run||'/'||p_item::text||'_') and exists(
   select 1 from storage.objects where bucket_id='service-report-photos' and name=object_path) then return true; end if;
 end loop;
 return false;
end $$;
revoke all on function public.checklist_photo_exists(text,text,uuid) from public,anon;
grant execute on function public.checklist_photo_exists(text,text,uuid) to authenticated;

create function public.require_published_pm_completion() returns trigger language plpgsql security definer set search_path='' as $$
declare item public.checklist_items; response public.checklist_responses;
begin
 if new.managed_maintenance or new.status not in ('pending_review','invoiced','closed') or (tg_op='UPDATE' and old.status=new.status)
  or not exists(select 1 from public.checklist_templates where id=new.checklist_template_id and procedure_id is not null) then return new; end if;
 for item in select * from public.checklist_items where template_id=new.checklist_template_id loop
  select * into response from public.checklist_responses where work_order_id=new.id and checklist_item_id=item.id;
  if response.id is null or coalesce(response.response_status,case when response.completed then 'pass' else 'action' end) not in ('pass','n/a')
   then raise exception 'Complete the work order checklist and resolve failed steps before review'; end if;
  perform public.validate_checklist_answer(item.definition,coalesce(response.response_status,'pass'),response.notes);
  if item.requires_photo and not public.checklist_photo_exists(response.photo_url,new.id::text,item.id) then raise exception 'Required checklist photo is missing'; end if;
 end loop;
 return new;
end $$;
create trigger published_pm_completion before insert or update of status on public.work_orders for each row execute function public.require_published_pm_completion();

-- Direct PM history writes use server-owned instructions and verified evidence.
-- Atomic operator/internal completion functions already build canonical history.
create function public.guard_builder_history() returns trigger language plpgsql set search_path='' as $$
declare t public.checklist_templates; item public.checklist_items; answer jsonb; items jsonb:='[]';
begin
 if current_user not in ('authenticated','anon') then
  if tg_op='DELETE' then return old; end if; return new;
 end if;
 if tg_op<>'INSERT' and exists(select 1 from public.checklist_templates where id=old.template_id and procedure_id is not null)
  then raise exception 'Completed checklists are immutable'; end if;
 if tg_op='DELETE' then return old; end if;
 select * into t from public.checklist_templates where id=new.template_id and procedure_id is not null;
 if t.id is null then return new; end if;
 if tg_op<>'INSERT' then raise exception 'Completed checklists are immutable'; end if;
 if t.checklist_type<>'pm' or not public.checklist_template_usable(t.id,new.asset_id,
  (select engine_id from public.work_orders where id=new.work_order_id),'pm',false)
  then raise exception 'Checklist is unavailable for this equipment'; end if;
 if new.submitted_by is distinct from auth.uid() then raise exception 'Invalid checklist author'; end if;
 if new.work_order_id is not null and not exists(select 1 from public.work_orders w where w.id=new.work_order_id
  and w.asset_id=new.asset_id and w.checklist_template_id=t.id) then raise exception 'Invalid checklist work order'; end if;
 for item in select * from public.checklist_items where template_id=t.id order by sort_order,id loop
  select a into answer from jsonb_array_elements(new.snapshot->'items') a where a->>'id'=item.id::text;
  if answer is null or coalesce(answer->>'response','') not in ('pass','action','monitor','n/a') then raise exception 'Complete every checklist step'; end if;
  perform public.validate_checklist_answer(item.definition,answer->>'response',answer->>'note');
  if item.requires_photo and not public.checklist_photo_exists(answer->>'photo_url',coalesce(new.work_order_id::text,'asset_'||new.asset_id::text),item.id)
   then raise exception 'Required checklist photo is missing'; end if;
  items:=items||jsonb_build_array(to_jsonb(item)||jsonb_build_object('response',answer->>'response','note',answer->>'note','photo_url',answer->>'photo_url'));
 end loop;
 new.template_name:=t.name;
 new.submitted_by_role:=public.get_my_role();
 new.snapshot:=jsonb_set(new.snapshot,'{header}',coalesce(new.snapshot->'header','{}')||jsonb_build_object(
  'completed_by',auth.uid(),'completed_by_name',(select full_name from public.profiles where id=auth.uid())));
 new.snapshot:=jsonb_set(new.snapshot,'{items}',items);
 new.snapshot:=jsonb_set(new.snapshot,'{template}',jsonb_build_object('id',t.id,'name',t.name,'version',t.version,'checklist_type',t.checklist_type));
 return new;
end $$;
create trigger builder_history_guard before insert or update or delete on public.saved_checklists
 for each row execute function public.guard_builder_history();

-- Checklist attachments share the private report bucket. Its report-only read
-- policy did not include PM checklists, and public URLs cannot display it.
create function public.checklist_media_access(p_name text,p_write boolean) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare run text:=split_part(p_name,'/',2); asset uuid; work public.work_orders;
begin
 if split_part(p_name,'/',1)<>'checklists' then return false; end if;
 begin
  if left(run,6)='asset_' then asset:=substring(run from 7)::uuid;
  else select * into work from public.work_orders where id=run::uuid; asset:=work.asset_id; end if;
 exception when others then return false; end;
 if not public.maintenance_execution_enabled(asset) then return false; end if;
 if p_write and work.id is not null and work.status in ('pending_review','invoiced','closed') then return false; end if;
 return true;
end $$;
revoke all on function public.checklist_media_access(text,boolean) from public,anon;
grant execute on function public.checklist_media_access(text,boolean) to authenticated;
create policy authorized_checklist_photo_read on storage.objects for select to authenticated
 using(bucket_id='service-report-photos' and public.checklist_media_access(name,false));
create policy checklist_photo_write_boundary on storage.objects as restrictive for insert to authenticated
 with check(bucket_id<>'service-report-photos' or split_part(name,'/',1)<>'checklists' or public.checklist_media_access(name,true));

alter table public.checklist_assignments add column completed_run_id uuid references public.operator_checklist_runs(id);
alter table public.operator_checklist_runs
 add column assignment_id uuid references public.checklist_assignments(id),
 add column started_at timestamptz;
create unique index one_run_per_assignment on public.operator_checklist_runs(assignment_id) where assignment_id is not null;
create table public.checklist_findings (
 run_id uuid not null references public.operator_checklist_runs(id),
 item_id uuid not null references public.checklist_items(id),
 fault_id uuid not null references public.maintenance_requests(id),
 primary key(run_id,item_id)
);
alter table public.checklist_findings enable row level security;
grant select on public.checklist_findings to authenticated;
create policy checklist_findings_read on public.checklist_findings for select to authenticated
 using(exists(select 1 from public.operator_checklist_runs r where r.id=run_id and public.maintenance_can_view_asset(r.asset_id)));

create function public.guard_preop_assignment() returns trigger language plpgsql security definer set search_path='' as $$
declare person public.profiles; company uuid;
begin
 if tg_op='UPDATE' and old.status='completed' and to_jsonb(new) is distinct from to_jsonb(old) then raise exception 'Completed assignments are immutable'; end if;
 if new.status='completed' and (new.completed_run_id is null or not exists(select 1 from public.operator_checklist_runs r
  where r.id=new.completed_run_id and r.assignment_id=new.id and r.operator_id=new.assigned_to)) then raise exception 'Complete an assignment by submitting its checklist'; end if;
 if tg_op='UPDATE' and new.template_id=old.template_id and new.assigned_to=old.assigned_to
  and new.asset_id is not distinct from old.asset_id and new.org_id=old.org_id then return new; end if;
 -- Existing legacy PM assignments remain readable; new PM work uses work orders.
 if not public.maintenance_can_manage_asset(new.asset_id) then raise exception 'Access denied'; end if;
 if not public.checklist_template_usable(new.template_id,new.asset_id,null,'operator_daily') then raise exception 'Assign a published pre-operation checklist for this equipment'; end if;
 select client_id into company from public.assets where id=new.asset_id;
 select * into person from public.profiles where id=new.assigned_to;
 if person.role<>'operator' or person.org_id is distinct from new.org_id or not exists(
  select 1 from public.client_orgs where id=person.org_id and owner_profile_id=company)
  then raise exception 'Choose an operator from this company'; end if;
 if not exists(select 1 from public.client_capabilities where client_id=company and capability_key='operational_checklists' and enabled)
  then raise exception 'Pre-operation checks are disabled'; end if;
 return new;
end $$;
create trigger preop_assignment_guard before insert or update on public.checklist_assignments for each row execute function public.guard_preop_assignment();

create function public.assign_preop_checklist(p_operation uuid,p_assignment uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare person public.profiles; asset uuid:=(p_data->>'asset_id')::uuid;
begin
 if not public.maintenance_can_manage_asset(asset) then raise exception 'Access denied'; end if;
 if public.maintenance_replayed(p_operation,p_assignment,'preop_assignment',p_data) then return p_assignment; end if;
 select * into person from public.profiles where id=(p_data->>'assigned_to')::uuid;
 if length(coalesce(p_data->>'notes',''))>2000 then raise exception 'Instructions are too long'; end if;
 insert into public.checklist_assignments(id,template_id,asset_id,assigned_to,assigned_by,org_id,due_date,notes)
 values(p_assignment,(p_data->>'template_id')::uuid,asset,person.id,auth.uid(),person.org_id,nullif(p_data->>'due_date','')::date,p_data->>'notes');
 perform public.maintenance_record_operation(p_operation,p_assignment,'preop_assignment',p_data);
 return p_assignment;
end $$;
create function public.checklist_assignment_context(p_asset uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('people',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name) order by p.full_name)
  from public.profiles p join public.client_orgs o on o.id=p.org_id join public.assets a on a.client_id=o.owner_profile_id
  where a.id=p_asset and p.role='operator'),'[]'),
 'assignments',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('assignee_name',p.full_name,'template_name',t.name,'template_version',t.version) order by s.created_at desc)
  from public.checklist_assignments s join public.profiles p on p.id=s.assigned_to join public.checklist_templates t on t.id=s.template_id
  where s.asset_id=p_asset),'[]'))
 where public.maintenance_can_manage_asset(p_asset)
$$;
revoke all on function public.assign_preop_checklist(uuid,uuid,jsonb),public.checklist_assignment_context(uuid) from public,anon;
grant execute on function public.assign_preop_checklist(uuid,uuid,jsonb),public.checklist_assignment_context(uuid) to authenticated;
