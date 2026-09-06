-- NOW-009: explicit custody and versioned inspection evidence.
create table public.asset_custody (
 asset_id uuid primary key references public.assets(id) on delete cascade,
 site text not null check(length(btrim(site)) between 1 and 200),
 responsible_id uuid not null references public.profiles(id),
 responsible_name text not null,
 lifecycle text not null check(lifecycle in ('active','stored','retired')),
 revision integer not null default 1
);
create table public.asset_custody_events (
 id uuid primary key,
 asset_id uuid not null references public.assets(id) on delete cascade,
 previous jsonb not null,
 current_state jsonb not null,
 reason text not null check(length(btrim(reason)) between 3 and 2000),
 actor_id uuid not null references public.profiles(id),
 actor_name text not null,
 created_at timestamptz not null default clock_timestamp()
);
create index custody_event_asset on public.asset_custody_events(asset_id,created_at desc);
create table public.asset_inspections (
 id uuid primary key,
 asset_id uuid not null references public.assets(id) on delete cascade,
 component_id uuid references public.asset_engines(id),
 title text not null check(length(btrim(title)) between 3 and 200),
 revision integer not null default 0,
 created_at timestamptz not null default clock_timestamp()
);
create table public.inspection_submissions (
 id uuid primary key,
 inspection_id uuid not null references public.asset_inspections(id) on delete cascade,
 inspected_on date not null,
 expires_on date not null check(expires_on>=inspected_on),
 procedure_notes text not null check(length(btrim(procedure_notes)) between 3 and 4000),
 result_notes text not null check(length(btrim(result_notes)) between 3 and 4000),
 evidence_path text not null,
 submitted_by uuid not null references public.profiles(id),
 submitted_name text not null,
 submitted_at timestamptz not null default clock_timestamp(),
 status text not null default 'pending' check(status in ('pending','approved','returned')),
 reviewed_by uuid references public.profiles(id),
 reviewed_name text,
 reviewed_at timestamptz,
 review_note text
);
create unique index inspection_one_pending on public.inspection_submissions(inspection_id) where status='pending';
create index inspection_versions on public.inspection_submissions(inspection_id,submitted_at desc);

alter table public.asset_custody enable row level security;
alter table public.asset_custody_events enable row level security;
alter table public.asset_inspections enable row level security;
alter table public.inspection_submissions enable row level security;
revoke all on public.asset_custody,public.asset_custody_events,public.asset_inspections,public.inspection_submissions from public,anon,authenticated;
grant select on public.asset_custody,public.asset_custody_events,public.asset_inspections,public.inspection_submissions to authenticated;
grant all on public.asset_custody,public.asset_custody_events,public.asset_inspections,public.inspection_submissions to service_role;
create policy custody_read on public.asset_custody for select to authenticated using(public.maintenance_can_view_asset(asset_id));
create policy custody_events_read on public.asset_custody_events for select to authenticated using(public.maintenance_can_view_asset(asset_id));
create policy inspections_read on public.asset_inspections for select to authenticated using(public.maintenance_can_view_asset(asset_id));
create policy inspection_versions_read on public.inspection_submissions for select to authenticated using(exists(
 select 1 from public.asset_inspections i where i.id=inspection_id and public.maintenance_can_view_asset(i.asset_id)));

create function public.inspection_can_submit(p_asset uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select public.maintenance_can_view_asset(p_asset) and exists(select 1 from public.profiles
 where id=auth.uid() and role in ('owner','employee','client','client_admin','client_mechanic'))
$$;
create function public.asset_assurance_context(p_asset uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(public.maintenance_can_view_asset(p_asset),false) then raise exception 'Access denied' using errcode='42501'; end if;
 return jsonb_build_object('asset',(select jsonb_build_object('id',id,'name',name,'location',location) from public.assets where id=p_asset),
 'can_manage',public.maintenance_can_manage_asset(p_asset),'can_submit',public.inspection_can_submit(p_asset),
 'custody',(select to_jsonb(c) from public.asset_custody c where asset_id=p_asset),
 'transfers',coalesce((select jsonb_agg(to_jsonb(e) order by created_at desc,id desc) from public.asset_custody_events e where asset_id=p_asset),'[]'),
 'people',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name) order by p.full_name,p.id)
 from public.profiles p join public.assets a on a.id=p_asset where p.role in ('client','client_admin','client_mechanic','operator','client_operator')
 and (p.id=a.client_id or exists(select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=a.client_id))),'[]'),
 'components',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',label) order by label,id) from public.asset_engines where asset_id=p_asset),'[]'));
end $$;

create function public.transfer_asset_custody(p_asset uuid,p_revision integer,p_operation uuid,p_data jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare old_state public.asset_custody; new_state public.asset_custody; person public.profiles; actor text;
begin
 if not coalesce(public.maintenance_can_manage_asset(p_asset),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Invalid transfer'; end if;
 if public.maintenance_replayed(p_operation,p_asset,'custody_transfer',p_data) then return; end if;
 perform 1 from public.assets where id=p_asset for update;
 select * into old_state from public.asset_custody where asset_id=p_asset;
 if p_revision is distinct from coalesce(old_state.revision,0) then raise exception 'Record changed' using errcode='40001'; end if;
 select p.* into person from public.profiles p join public.assets a on a.id=p_asset
 where p.id=(p_data->>'responsible_id')::uuid and p.role in ('client','client_admin','client_mechanic','operator','client_operator')
 and (p.id=a.client_id or exists(select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=a.client_id));
 if person.id is null then raise exception 'Choose a responsible member of this company'; end if;
 if length(btrim(coalesce(p_data->>'reason',''))) not between 3 and 2000 then raise exception 'A transfer reason is required'; end if;
 select full_name into actor from public.profiles where id=auth.uid();
 insert into public.asset_custody(asset_id,site,responsible_id,responsible_name,lifecycle)
 values(p_asset,btrim(p_data->>'site'),person.id,coalesce(person.full_name,''),p_data->>'lifecycle')
 on conflict(asset_id) do update set site=excluded.site,responsible_id=excluded.responsible_id,
 responsible_name=excluded.responsible_name,lifecycle=excluded.lifecycle,revision=public.asset_custody.revision+1
 returning * into new_state;
 insert into public.asset_custody_events(id,asset_id,previous,current_state,reason,actor_id,actor_name)
 values(p_operation,p_asset,coalesce(to_jsonb(old_state),'{}'),to_jsonb(new_state),btrim(p_data->>'reason'),auth.uid(),coalesce(actor,''));
 update public.assets set location=new_state.site,maintenance_revision=maintenance_revision+1 where id=p_asset;
 perform public.maintenance_record_operation(p_operation,p_asset,'custody_transfer',p_data);
 insert into public.asset_history_entries(asset_id,category,kind,source_type,source_id,source_key,title,body,detail,actor_name,occurred_at)
 values(p_asset,'asset','custody_transferred','custody',p_asset,'custody:'||p_operation,
 new_state.site,btrim(p_data->>'reason'),jsonb_build_object('location',new_state.site,'previous_location',old_state.site,
 'assignee',new_state.responsible_name,'lifecycle',new_state.lifecycle),actor,clock_timestamp());
end $$;

create function public.inspection_register(p_asset uuid default null) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('asset_name',a.name,'component_name',e.label,
 'site',coalesce(c.site,a.location),'responsible_name',c.responsible_name,'lifecycle',c.lifecycle,
 'can_manage',public.maintenance_can_manage_asset(a.id),'can_submit',public.inspection_can_submit(a.id),
 'approved',(select to_jsonb(s) from public.inspection_submissions s where s.inspection_id=i.id and s.status='approved' order by s.reviewed_at desc,s.id desc limit 1),
 'pending',(select to_jsonb(s) from public.inspection_submissions s where s.inspection_id=i.id and s.status='pending'),
 'versions',coalesce((select jsonb_agg(to_jsonb(s) order by s.submitted_at desc,s.id desc) from public.inspection_submissions s where s.inspection_id=i.id),'[]'))
 order by a.name,i.title,i.id),'[]')
 from public.asset_inspections i join public.assets a on a.id=i.asset_id
 left join public.asset_engines e on e.id=i.component_id left join public.asset_custody c on c.asset_id=a.id
 where (p_asset is null or a.id=p_asset) and public.maintenance_can_view_asset(a.id)
$$;

create function public.create_asset_inspection(p_asset uuid,p_operation uuid,p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare component uuid:=nullif(p_data->>'component_id','')::uuid;
begin
 if not coalesce(public.maintenance_can_manage_asset(p_asset),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Invalid inspection'; end if;
 if public.maintenance_replayed(p_operation,p_asset,'inspection_create',p_data) then return p_operation; end if;
 if component is not null and not exists(select 1 from public.asset_engines where id=component and asset_id=p_asset) then raise exception 'Component belongs to another asset'; end if;
 insert into public.asset_inspections(id,asset_id,component_id,title) values(p_operation,p_asset,component,btrim(p_data->>'title'));
 perform public.maintenance_record_operation(p_operation,p_asset,'inspection_create',p_data);
 insert into public.asset_history_entries(asset_id,category,kind,source_type,source_id,source_key,title,occurred_at,actor_name)
 values(p_asset,'inspection','inspection_required','asset_inspection',p_operation,'inspection:'||p_operation,btrim(p_data->>'title'),clock_timestamp(),
 (select full_name from public.profiles where id=auth.uid()));
 return p_operation;
end $$;

create function public.change_asset_inspection(p_inspection uuid,p_revision integer,p_operation uuid,p_action text,p_data jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare item public.asset_inspections; submission public.inspection_submissions; actor text; evidence text;
 inspected date; expires date;
begin
 select * into item from public.asset_inspections where id=p_inspection;
 if not found or not coalesce(public.inspection_can_submit(item.asset_id),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_action is null or p_action not in ('submit','approve','return') or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Invalid inspection action'; end if;
 if p_action<>'submit' and not public.maintenance_can_manage_asset(item.asset_id) then raise exception 'Only a manager can review' using errcode='42501'; end if;
 if public.maintenance_replayed(p_operation,p_inspection,'inspection_'||p_action,p_data) then return; end if;
 select * into item from public.asset_inspections where id=p_inspection for update;
 if p_revision is distinct from item.revision then raise exception 'Record changed' using errcode='40001'; end if;
 select full_name into actor from public.profiles where id=auth.uid();
 if p_action='submit' then
  inspected:=(p_data->>'inspected_on')::date; expires:=(p_data->>'expires_on')::date;
  if inspected is null or expires is null or not isfinite(inspected) or not isfinite(expires)
   or inspected>current_date or inspected<date '1900-01-01' or expires<inspected or expires>date '2200-01-01' then raise exception 'Check inspection and expiry dates'; end if;
  evidence:=p_data->>'evidence_path';
  if evidence is null or evidence not in (item.asset_id::text||'/'||auth.uid()::text||'/'||p_operation::text||'.jpg',item.asset_id::text||'/'||auth.uid()::text||'/'||p_operation::text||'.png')
    or not exists(select 1 from storage.objects where bucket_id='inspection-evidence' and name=evidence) then raise exception 'Upload inspection evidence first'; end if;
  if exists(select 1 from public.inspection_submissions where inspection_id=item.id and status='pending') then raise exception 'Review the pending renewal first'; end if;
  insert into public.inspection_submissions(id,inspection_id,inspected_on,expires_on,procedure_notes,result_notes,evidence_path,submitted_by,submitted_name)
  values(p_operation,item.id,inspected,expires,btrim(p_data->>'procedure_notes'),btrim(p_data->>'result_notes'),evidence,auth.uid(),coalesce(actor,''));
 else
  select * into submission from public.inspection_submissions where id=(p_data->>'submission_id')::uuid and inspection_id=item.id and status='pending' for update;
  if not found then raise exception 'Pending renewal not found'; end if;
  if length(btrim(coalesce(p_data->>'note',''))) not between 3 and 2000 then raise exception 'A review note is required'; end if;
  update public.inspection_submissions set status=case when p_action='approve' then 'approved' else 'returned' end,
   reviewed_by=auth.uid(),reviewed_name=coalesce(actor,''),reviewed_at=clock_timestamp(),review_note=btrim(p_data->>'note') where id=submission.id;
 end if;
 update public.asset_inspections set revision=revision+1 where id=item.id;
 perform public.maintenance_record_operation(p_operation,p_inspection,'inspection_'||p_action,p_data);
 insert into public.asset_history_entries(asset_id,category,kind,source_type,source_id,source_key,title,body,actor_name,occurred_at)
 values(item.asset_id,'inspection','renewal_'||p_action,'asset_inspection',item.id,'inspection:'||p_operation,item.title,
 coalesce(p_data->>'note',p_data->>'result_notes',''),actor,clock_timestamp());
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('inspection-evidence','inspection-evidence',false,10485760,array['image/jpeg','image/png']);
create function public.inspection_evidence_asset(p_name text) returns uuid
language plpgsql immutable set search_path='' as $$
begin
 if p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png)$' then return null; end if;
 return split_part(p_name,'/',1)::uuid;
exception when invalid_text_representation then return null;
end $$;
create policy inspection_evidence_read on storage.objects for select to authenticated using(
 bucket_id='inspection-evidence' and public.maintenance_can_view_asset(public.inspection_evidence_asset(name)));
create policy inspection_evidence_insert on storage.objects for insert to authenticated with check(
 bucket_id='inspection-evidence' and public.inspection_can_submit(public.inspection_evidence_asset(name)) and split_part(name,'/',2)=auth.uid()::text);
-- Committed evidence is immutable; only the uploader may discard an unsubmitted object.
create policy inspection_evidence_discard on storage.objects for delete to authenticated using(
 bucket_id='inspection-evidence' and public.inspection_can_submit(public.inspection_evidence_asset(name))
 and split_part(name,'/',2)=auth.uid()::text and not exists(select 1 from public.inspection_submissions where evidence_path=name));

revoke all on function public.inspection_can_submit(uuid),public.asset_assurance_context(uuid),
 public.transfer_asset_custody(uuid,integer,uuid,jsonb),public.inspection_register(uuid),public.create_asset_inspection(uuid,uuid,jsonb),
 public.change_asset_inspection(uuid,integer,uuid,text,jsonb),public.inspection_evidence_asset(text) from public,anon,authenticated;
grant execute on function public.inspection_can_submit(uuid),public.asset_assurance_context(uuid),
 public.transfer_asset_custody(uuid,integer,uuid,jsonb),public.inspection_register(uuid),public.create_asset_inspection(uuid,uuid,jsonb),
 public.change_asset_inspection(uuid,integer,uuid,text,jsonb),public.inspection_evidence_asset(text) to authenticated;
