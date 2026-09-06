create table public.operations_submissions (
 id uuid primary key, actor_id uuid not null references public.profiles(id),
 asset_id uuid not null references public.assets(id),payload jsonb not null,
 created_at timestamptz not null default now()
);
alter table public.operations_submissions enable row level security;
revoke all on public.operations_submissions from public,anon,authenticated;
grant all on public.operations_submissions to service_role;

create function public.operations_can_submit(p_asset uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.maintenance_can_view_asset(p_asset) and exists(select 1 from public.profiles p
  where p.id=auth.uid() and (p.role in ('owner','employee') or exists(
   select 1 from public.assets a join public.client_capabilities c on c.client_id=a.client_id
    where a.id=p_asset and c.capability_key='operational_checklists' and c.enabled)))
$$;
revoke all on function public.operations_can_submit(uuid) from public,anon;
grant execute on function public.operations_can_submit(uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('operator-evidence','operator-evidence',false,10485760,array['image/jpeg','image/png','image/webp']);
create function public.operator_evidence_access(p_name text,p_write boolean)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare pieces text[]:=string_to_array(p_name,'/'); asset uuid; actor uuid; run uuid;
begin
 if array_length(pieces,1)<>4 then return false; end if;
 begin asset:=pieces[1]::uuid;actor:=pieces[2]::uuid;run:=pieces[3]::uuid;
 exception when invalid_text_representation then return false; end;
 if p_write then return actor=auth.uid() and public.operations_can_submit(asset)
   and not exists(select 1 from public.operations_submissions where id=run); end if;
 return public.maintenance_can_view_asset(asset) and (actor=auth.uid() or exists(
  select 1 from public.operator_checklist_runs r join public.operator_checklist_responses x on x.run_id=r.id
   where r.id=run and r.asset_id=asset and x.photo_url=p_name));
end $$;
revoke all on function public.operator_evidence_access(text,boolean) from public,anon;
grant execute on function public.operator_evidence_access(text,boolean) to authenticated;
create policy operator_evidence_insert on storage.objects for insert to authenticated
 with check(bucket_id='operator-evidence' and public.operator_evidence_access(name,true));
create policy operator_evidence_read on storage.objects for select to authenticated
 using(bucket_id='operator-evidence' and public.operator_evidence_access(name,false));

create function public.submit_operations_checklist(p_operation uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare asset public.assets; template public.checklist_templates; actor public.profiles;
 prior public.operations_submissions; item public.checklist_items; response text; note text; photo text;
 completed timestamptz; hours numeric; items jsonb:='[]'; snapshot jsonb; prefix text; total integer:=0;
begin
 select * into asset from public.assets where id=(p_data->>'asset_id')::uuid;
 if not public.operations_can_submit(asset.id) then raise exception 'Access denied'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into prior from public.operations_submissions where id=p_operation;
 if found then
  if prior.actor_id<>auth.uid() or prior.payload<>p_data then raise exception 'Identifier already used for different input'; end if;
  return p_operation;
 end if;
 select * into actor from public.profiles where id=auth.uid();
 select * into template from public.checklist_templates where id=(p_data->>'template_id')::uuid;
 if template.id is null or not template.is_active or template.checklist_type<>'operator_daily'
  or (template.asset_type_id is not null and template.asset_type_id<>asset.asset_type_id)
  or template.version is distinct from (p_data->>'template_version')::integer
  then raise exception 'Checklist changed or is unavailable; reload it before submitting' using errcode='40001'; end if;
 if p_data->>'run_type' not in ('pre_departure','post_trip') then raise exception 'Invalid run type'; end if;
 completed:=(p_data->>'completed_at')::timestamptz;
 if completed is null or completed>now()+interval '5 minutes' or completed<now()-interval '30 days'
  then raise exception 'Invalid completion time'; end if;
 hours:=nullif(p_data->>'current_hours','')::numeric;
 if hours<0 or hours>=1000000000 then raise exception 'Invalid hours'; end if;
 if jsonb_typeof(p_data->'responses') is distinct from 'object' or jsonb_typeof(p_data->'photos') is distinct from 'object'
  or jsonb_typeof(p_data->'notes') is distinct from 'object' then raise exception 'Invalid answers'; end if;
 prefix:=asset.id::text||'/'||auth.uid()::text||'/'||p_operation::text||'/';
 for item in select * from public.checklist_items where template_id=template.id order by sort_order,id loop
  total:=total+1; response:=p_data->'responses'->>item.id::text;
  note:=btrim(coalesce(p_data->'notes'->>item.id::text,''));photo:=nullif(p_data->'photos'->>item.id::text,'');
  if response is null or response not in ('pass','monitor','alert','action','n/a') then raise exception 'Answer every checklist item'; end if;
  if response in ('monitor','alert','action') and length(note)=0 then raise exception 'Add a note for flagged items'; end if;
  if item.requires_photo and photo is null then raise exception 'Required photo is missing'; end if;
  if photo is not null and (photo not in (prefix||item.id::text||'.jpg',prefix||item.id::text||'.png',prefix||item.id::text||'.webp')
    or not exists(select 1 from storage.objects where bucket_id='operator-evidence' and name=photo))
    then raise exception 'Photo must upload before completion'; end if;
  items:=items||jsonb_build_array(jsonb_build_object('id',item.id,'description_en',item.description_en,
   'description_es',item.description_es,'category',item.category,'sort_order',item.sort_order,
   'response',case response when 'alert' then 'monitor' else response end,'note',note,'photo_url',photo));
 end loop;
 if total=0 or total<>(select count(*) from jsonb_object_keys(p_data->'responses'))
  or exists(select 1 from jsonb_object_keys(p_data->'photos') k where not exists(select 1 from public.checklist_items where template_id=template.id and id::text=k))
  then raise exception 'Checklist items changed; reload before submitting' using errcode='40001'; end if;
 insert into public.operations_submissions values(p_operation,auth.uid(),asset.id,p_data,now());
 insert into public.operator_checklist_runs(id,asset_id,template_id,operator_id,run_type,completed_at,notes)
  values(p_operation,asset.id,template.id,auth.uid(),p_data->>'run_type',completed,p_data->>'general_notes');
 insert into public.operator_checklist_responses(run_id,checklist_item_id,result,response_status,notes,photo_url)
 select p_operation,(i->>'id')::uuid,
  case i->>'response' when 'pass' then 'good' when 'n/a' then 'not_applicable' else 'needs_attention' end,
  case i->>'response' when 'monitor' then 'alert' when 'n/a' then null else i->>'response' end,i->>'note',i->>'photo_url'
 from jsonb_array_elements(items) i;
 snapshot:=jsonb_build_object('asset_id',asset.id,'template',to_jsonb(template),'items',items,
  'header',jsonb_build_object('asset_id',asset.id,'checklist_name',template.name,'completed_by',auth.uid(),
   'completed_by_name',actor.full_name,'submitted_at',completed,'current_hours',hours,'general_notes',p_data->>'general_notes',
   'run_id',p_operation,'run_type',p_data->>'run_type'),
  'source',jsonb_build_object('source_type','operator'),'submitted_by_role',actor.role);
 insert into public.saved_checklists(id,asset_id,client_id,template_id,template_name,checklist_type,source_type,
  submitted_by,submitted_by_role,submitted_at,current_hours,general_notes,snapshot)
 values(p_operation,asset.id,asset.client_id,template.id,template.name,'operations','operator',auth.uid(),actor.role,
  completed,hours,p_data->>'general_notes',snapshot);
 return p_operation;
end $$;
revoke all on function public.submit_operations_checklist(uuid,jsonb) from public,anon;
grant execute on function public.submit_operations_checklist(uuid,jsonb) to authenticated;
-- Legacy clients cannot create partial runs or modify accepted responses.
revoke insert,update,delete on public.operator_checklist_runs,public.operator_checklist_responses from authenticated,anon;
create policy operations_runs_read on public.operator_checklist_runs for select to authenticated
 using(public.maintenance_can_view_asset(asset_id));
create policy operations_responses_read on public.operator_checklist_responses for select to authenticated
 using(exists(select 1 from public.operator_checklist_runs r where r.id=run_id and public.maintenance_can_view_asset(r.asset_id)));
create policy operator_history_insert_guard on public.saved_checklists as restrictive for insert to authenticated with check(source_type<>'operator');
create policy operator_history_update_guard on public.saved_checklists as restrictive for update to authenticated using(source_type<>'operator') with check(source_type<>'operator');
create policy operator_history_delete_guard on public.saved_checklists as restrictive for delete to authenticated using(source_type<>'operator');
