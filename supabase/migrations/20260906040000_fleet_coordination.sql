-- NOW-007: scoped discussions, immutable asset history and actionable fleet data.
-- Existing completion and fault transitions remain owned by their checked RPCs.
create table public.coordination_posts (
 id uuid primary key,
 subject_kind text not null check(subject_kind in ('job','fault')),
 subject_id uuid not null,
 asset_id uuid not null references public.assets(id) on delete restrict,
 client_id uuid not null references public.profiles(id),
 author_id uuid not null references public.profiles(id),
 author_name text not null,
 team text not null check(team in ('provider','company')),
 visibility text not null check(visibility in ('team','shared')),
 kind text not null check(kind in ('comment','handover')),
 body text not null,
 isolation text,
 next_steps text,
 attachments jsonb not null default '[]',
 request_payload jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
create index coordination_posts_subject on public.coordination_posts(subject_kind,subject_id,created_at desc,id desc);
create index coordination_posts_asset on public.coordination_posts(asset_id,created_at desc);
create table public.coordination_mentions (
 post_id uuid not null references public.coordination_posts(id),
 user_id uuid not null references public.profiles(id),
 read_at timestamptz,
 primary key(post_id,user_id)
);
create index coordination_mentions_user on public.coordination_mentions(user_id,post_id);
create table public.coordination_acknowledgements (
 post_id uuid not null references public.coordination_posts(id),
 user_id uuid not null references public.profiles(id),
 user_name text not null,
 created_at timestamptz not null default clock_timestamp(),
 primary key(post_id,user_id)
);
alter table public.coordination_posts enable row level security;
alter table public.coordination_mentions enable row level security;
alter table public.coordination_acknowledgements enable row level security;
revoke all on public.coordination_posts,public.coordination_mentions,public.coordination_acknowledgements from public,anon,authenticated;
grant all on public.coordination_posts,public.coordination_mentions,public.coordination_acknowledgements to service_role;

-- Parameterized private predicates also check proposed mention recipients.
create function public.coordination_asset_viewer(p_asset uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.assets a join public.profiles p on p.id=p_user
 where a.id=p_asset and (p.role in ('owner','employee')
  or (p.role in ('client','client_admin') and p.org_id is null and a.client_id=p.id)
  or (p.role in ('client','client_admin','client_mechanic','operator','client_operator')
   and exists(select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=a.client_id))))
$$;
create function public.coordination_subject_asset(p_kind text,p_id uuid)
returns uuid language sql stable security definer set search_path='' as $$
 select asset_id from public.work_orders where p_kind='job' and id=p_id
 union all select asset_id from public.maintenance_requests where p_kind='fault' and id=p_id
$$;
create function public.coordination_subject_reader(p_kind text,p_id uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.coordination_asset_viewer(public.coordination_subject_asset(p_kind,p_id),p_user)
 and (p_kind='fault' or exists(select 1 from public.work_orders w join public.profiles p on p.id=p_user
  where w.id=p_id and p_kind='job' and (
   (w.managed_maintenance and (p.role in ('owner','client','client_admin')
     or (p.role in ('employee','client_mechanic') and w.assigned_to=p.id)))
   or (not w.managed_maintenance and (p.role in ('owner','employee') or exists(
    select 1 from public.work_order_assignments x where x.work_order_id=w.id and x.profile_id=p.id))))))
$$;
create function public.coordination_user_team(p_user uuid)
returns text language sql stable security definer set search_path='' as $$
 select case when role in ('owner','employee') then 'provider' else 'company' end
 from public.profiles where id=p_user
$$;
create function public.coordination_post_reader(p_post uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.coordination_posts p join public.assets a on a.id=p.asset_id
 where p.id=p_post and p.client_id=a.client_id
 and public.coordination_subject_reader(p.subject_kind,p.subject_id,p_user)
 and (p.visibility='shared' or p.team=public.coordination_user_team(p_user)))
$$;
create function public.coordination_can_post(p_kind text,p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.coordination_subject_reader(p_kind,p_id,auth.uid()) and (
 p_kind='fault' or exists(select 1 from public.work_orders w where w.id=p_id
  and (not w.managed_maintenance or public.maintenance_can_work_job(w.id))))
$$;
revoke all on function public.coordination_asset_viewer(uuid,uuid),public.coordination_subject_asset(text,uuid),
 public.coordination_subject_reader(text,uuid,uuid),public.coordination_user_team(uuid),
 public.coordination_post_reader(uuid,uuid),public.coordination_can_post(text,uuid) from public,anon,authenticated;

create function public.coordination_people(p_kind text,p_id uuid,p_visibility text default 'team')
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(public.coordination_can_post(p_kind,p_id),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_visibility is null or p_visibility not in ('team','shared') then raise exception 'Invalid visibility'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'role',p.role) order by p.full_name,p.id)
 from public.profiles p where p.id<>auth.uid() and public.coordination_subject_reader(p_kind,p_id,p.id)
 and (p_visibility='shared' or public.coordination_user_team(p.id)=public.coordination_user_team(auth.uid()))),'[]');
end $$;

create function public.post_coordination_message(p_operation uuid,p_kind text,p_id uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare previous public.coordination_posts; asset uuid; client uuid; actor public.profiles;
 message_kind text:=coalesce(p_data->>'kind','comment'); visibility text:=coalesce(p_data->>'visibility','team');
 body text:=btrim(coalesce(p_data->>'body','')); next_steps text:=btrim(coalesce(p_data->>'next_steps',''));
 mentions jsonb:=coalesce(p_data->'mentions','[]'); attachments jsonb:=coalesce(p_data->'attachments','[]');
 recipient uuid; attachment jsonb; prefix text;
begin
 if not coalesce(public.coordination_can_post(p_kind,p_id),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_operation is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Invalid message'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,7));
 select * into previous from public.coordination_posts where id=p_operation;
 if found then
  if previous.author_id<>auth.uid() or previous.subject_kind<>p_kind or previous.subject_id<>p_id
   or previous.request_payload<>p_data then raise exception 'Operation already used with different input'; end if;
  return previous.id;
 end if;
 asset:=public.coordination_subject_asset(p_kind,p_id);
 select client_id into client from public.assets where id=asset for share;
 if p_kind='job' then perform 1 from public.work_orders where id=p_id for share;
 else perform 1 from public.maintenance_requests where id=p_id for share; end if;
 if not coalesce(public.coordination_can_post(p_kind,p_id),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if message_kind not in ('comment','handover') or visibility not in ('team','shared')
  or length(body) not between 3 and 4000 then raise exception 'Enter a message of 3 to 4000 characters'; end if;
 if message_kind='handover' and (length(next_steps) not between 3 and 3000
  or coalesce(p_data->>'isolation','') not in ('isolated','not_isolated','not_required','unknown'))
  then raise exception 'Handover requires isolation status and next-shift work'; end if;
 if jsonb_typeof(mentions)<>'array' or jsonb_array_length(mentions)>10
  or jsonb_typeof(attachments)<>'array' or jsonb_array_length(attachments)>6 then raise exception 'Invalid mentions or attachments'; end if;
 if (select count(distinct value) from jsonb_array_elements(mentions))<>jsonb_array_length(mentions)
  then raise exception 'Duplicate mention'; end if;
 for recipient in select value::uuid from jsonb_array_elements_text(mentions) loop
  if recipient=auth.uid() or not coalesce(public.coordination_subject_reader(p_kind,p_id,recipient),false)
   or (visibility='team' and public.coordination_user_team(recipient)<>public.coordination_user_team(auth.uid()))
   then raise exception 'Mention recipient cannot access this message'; end if;
 end loop;
 prefix:=p_kind||'/'||p_id||'/'||auth.uid()||'/'||p_operation||'/';
 for attachment in select value from jsonb_array_elements(attachments) loop
  if jsonb_typeof(attachment)<>'object' or length(coalesce(attachment->>'name','')) not between 1 and 120
   or left(coalesce(attachment->>'path',''),length(prefix))<>prefix
   or not exists(select 1 from storage.objects o where o.bucket_id='coordination-attachments' and o.name=attachment->>'path')
   then raise exception 'Attachment is missing or belongs to another message'; end if;
 end loop;
 if (select count(distinct value->>'path') from jsonb_array_elements(attachments))<>jsonb_array_length(attachments)
  then raise exception 'Duplicate attachment'; end if;
 select * into actor from public.profiles where id=auth.uid();
 insert into public.coordination_posts(id,subject_kind,subject_id,asset_id,client_id,author_id,author_name,team,
  visibility,kind,body,isolation,next_steps,attachments,request_payload)
 values(p_operation,p_kind,p_id,asset,client,actor.id,actor.full_name,public.coordination_user_team(actor.id),
  visibility,message_kind,body,case when message_kind='handover' then p_data->>'isolation' end,
  case when message_kind='handover' then next_steps end,attachments,p_data);
 insert into public.coordination_mentions(post_id,user_id) select p_operation,value::uuid from jsonb_array_elements_text(mentions);
 return p_operation;
end $$;

create function public.coordination_thread(p_kind text,p_id uuid,p_before timestamptz default null,p_before_id uuid default null,p_focus uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare asset uuid; result jsonb; posts jsonb; focus_time timestamptz;
begin
 if not coalesce(public.coordination_subject_reader(p_kind,p_id,auth.uid()),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if (p_before is null)<>(p_before_id is null) then raise exception 'Invalid page cursor'; end if;
 if p_focus is not null then
  select created_at into focus_time from public.coordination_posts
  where id=p_focus and subject_kind=p_kind and subject_id=p_id and public.coordination_post_reader(id,auth.uid());
  if not found then raise exception 'Message is unavailable' using errcode='42501'; end if;
 end if;
 asset:=public.coordination_subject_asset(p_kind,p_id);
 select jsonb_build_object('id',p_id,'subject_kind',p_kind,'asset_id',a.id,'asset_name',a.name,
  'title',case when p_kind='job' then (select title from public.work_orders where id=p_id)
    else (select description from public.maintenance_requests where id=p_id) end,
  'managed',coalesce((select managed_maintenance from public.work_orders where p_kind='job' and id=p_id),false),
  'can_post',public.coordination_can_post(p_kind,p_id),'team',public.coordination_user_team(auth.uid()))
 into result from public.assets a where a.id=asset;
 select coalesce(jsonb_agg(x.data order by x.created_at desc,x.id desc),'[]') into posts from (
  select p.id,p.created_at,(to_jsonb(p)-'request_payload'-'client_id')||jsonb_build_object(
   'mentions',coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'name',u.full_name) order by u.full_name,u.id)
    from public.coordination_mentions m join public.profiles u on u.id=m.user_id where m.post_id=p.id),'[]'),
   'acknowledgements',coalesce((select jsonb_agg(jsonb_build_object('user_id',k.user_id,'name',k.user_name,'created_at',k.created_at)
    order by k.created_at,k.user_id) from public.coordination_acknowledgements k where k.post_id=p.id),'[]')) as data
  from public.coordination_posts p where p.subject_kind=p_kind and p.subject_id=p_id
   and public.coordination_post_reader(p.id,auth.uid())
   and (p_before is null or (p.created_at,p.id)<(p_before,p_before_id))
   and (p_focus is null or (p.created_at,p.id)<=(focus_time,p_focus))
  order by p.created_at desc,p.id desc limit 51
 ) x;
 return result||jsonb_build_object('posts',coalesce((select jsonb_agg(value order by ordinality)
  from jsonb_array_elements(posts) with ordinality where ordinality<=50),'[]'),'has_more',jsonb_array_length(posts)>50);
end $$;
create function public.coordination_inbox()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(x.data order by x.created_at desc,x.id desc),'[]') from (
  select p.id,p.created_at,jsonb_build_object('id',p.id,'user_id',m.user_id,'title',p.author_name,
  'body',left(p.body,160),'type','discussion_'||p.subject_kind,'reference_id',p.subject_id,
  'read',m.read_at is not null,'created_at',p.created_at) as data
  from public.coordination_mentions m join public.coordination_posts p on p.id=m.post_id
  where m.user_id=auth.uid() and public.coordination_post_reader(p.id,auth.uid())
  order by p.created_at desc,p.id desc limit 100
 ) x
$$;
create function public.mark_coordination_read(p_post uuid default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Access denied' using errcode='42501'; end if;
 update public.coordination_mentions set read_at=coalesce(read_at,clock_timestamp())
 where user_id=auth.uid() and (p_post is null or post_id=p_post) and public.coordination_post_reader(post_id,auth.uid());
end $$;
create function public.acknowledge_handover(p_post uuid)
returns void language plpgsql security definer set search_path='' as $$
declare p public.coordination_posts;
begin
 select * into p from public.coordination_posts where id=p_post;
 if not coalesce(public.coordination_post_reader(p_post,auth.uid()),false)
  or not coalesce(public.coordination_can_post(p.subject_kind,p.subject_id),false)
  then raise exception 'Access denied' using errcode='42501'; end if;
 if p.kind<>'handover' or p.author_id=auth.uid() then raise exception 'Only another participant can acknowledge a handover'; end if;
 insert into public.coordination_acknowledgements(post_id,user_id,user_name)
 select p_post,id,full_name from public.profiles where id=auth.uid() on conflict do nothing;
 perform public.mark_coordination_read(p_post);
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('coordination-attachments','coordination-attachments',false,8388608,array['image/jpeg','image/png','image/webp']);
create function public.coordination_upload_allowed(p_name text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare pieces text[]:=string_to_array(p_name,'/');
begin
 if array_length(pieces,1)<>5 or pieces[1] not in ('job','fault') or pieces[3]<>auth.uid()::text
  or pieces[5]!~'^[a-zA-Z0-9-]+\.(jpg|jpeg|png|webp)$' then return false; end if;
 perform pieces[4]::uuid;
 return coalesce(public.coordination_can_post(pieces[1],pieces[2]::uuid),false)
  and not exists(select 1 from public.coordination_posts where id=pieces[4]::uuid);
exception when invalid_text_representation then return false;
end $$;
create function public.coordination_attachment_readable(p_name text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.coordination_posts p where p.attachments @> jsonb_build_array(jsonb_build_object('path',p_name))
  and public.coordination_post_reader(p.id,auth.uid()))
 or (public.coordination_upload_allowed(p_name) and not exists(select 1 from public.coordination_posts p
  where p.attachments @> jsonb_build_array(jsonb_build_object('path',p_name))))
$$;
create policy coordination_photo_read on storage.objects for select to authenticated
 using(bucket_id='coordination-attachments' and public.coordination_attachment_readable(name));
create policy coordination_photo_upload on storage.objects for insert to authenticated
 with check(bucket_id='coordination-attachments' and public.coordination_upload_allowed(name));
-- No client UPDATE or DELETE policy, including staged files. A concurrent
-- discard must never remove an object while another request commits its post.
-- The composer holds photos locally until submission and retries fixed paths.
revoke all on function public.coordination_people(text,uuid,text),public.post_coordination_message(uuid,text,uuid,jsonb),
 public.coordination_thread(text,uuid,timestamptz,uuid,uuid),public.coordination_inbox(),public.mark_coordination_read(uuid),
 public.acknowledge_handover(uuid),public.coordination_upload_allowed(text),public.coordination_attachment_readable(text) from public,anon;
grant execute on function public.coordination_people(text,uuid,text),public.post_coordination_message(uuid,text,uuid,jsonb),
 public.coordination_thread(text,uuid,timestamptz,uuid,uuid),public.coordination_inbox(),public.mark_coordination_read(uuid),
 public.acknowledge_handover(uuid),public.coordination_upload_allowed(text),public.coordination_attachment_readable(text) to authenticated;

create table public.asset_history_entries (
 id uuid primary key default gen_random_uuid(),
 asset_id uuid not null references public.assets(id) on delete cascade,
 category text not null check(category in ('asset','usage','inspection','fault','availability','work','service','parts','discussion')),
 kind text not null,
 source_type text not null,
 source_id uuid not null,
 source_key text not null unique,
 job_id uuid,
 post_id uuid,
 managed boolean not null default false,
 title text not null,
 body text not null default '',
 detail jsonb not null default '{}',
 actor_name text,
 occurred_at timestamptz not null,
 recorded_at timestamptz not null default clock_timestamp()
);
create index asset_history_page on public.asset_history_entries(asset_id,occurred_at desc,id desc);
create index asset_history_category on public.asset_history_entries(asset_id,category,occurred_at desc,id desc);
alter table public.asset_history_entries enable row level security;
revoke all on public.asset_history_entries from public,anon,authenticated;
grant all on public.asset_history_entries to service_role;

create function public.asset_history_readable(p_entry public.asset_history_entries)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare role_name text:=(select role from public.profiles where id=auth.uid());
begin
 if not coalesce(public.maintenance_can_view_asset(p_entry.asset_id),false) then return false; end if;
 if p_entry.post_id is not null then return public.coordination_post_reader(p_entry.post_id,auth.uid()); end if;
 if p_entry.job_id is null then return true; end if;
 if not p_entry.managed and p_entry.category='inspection' then return true; end if;
 if not p_entry.managed and p_entry.category='parts' then
  return role_name='owner' or exists(select 1 from public.work_orders where id=p_entry.job_id and assigned_to=auth.uid());
 end if;
 if exists(select 1 from public.work_orders where id=p_entry.job_id) then
  return public.coordination_subject_reader('job',p_entry.job_id,auth.uid());
 end if;
 return role_name='owner' or (p_entry.managed and public.maintenance_can_manage_asset(p_entry.asset_id));
end $$;
create function public.asset_history(p_asset uuid,p_category text default null,p_search text default '',
 p_from timestamptz default null,p_to timestamptz default null,p_before timestamptz default null,
 p_before_id uuid default null,p_limit integer default 50,p_as_of timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; entries jsonb; cutoff timestamptz:=least(coalesce(p_as_of,statement_timestamp()),statement_timestamp());
begin
 if not coalesce(public.maintenance_can_view_asset(p_asset),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if (p_category is not null and p_category not in ('asset','usage','inspection','fault','availability','work','service','parts','discussion'))
  or length(coalesce(p_search,''))>200 or p_limit is null or p_limit not between 1 and 200
  or (p_from is not null and p_to is not null and p_from>=p_to)
  or (p_before is null)<>(p_before_id is null) then raise exception 'Invalid history filter'; end if;
 select jsonb_build_object('asset_id',id,'asset_name',name,'as_of',cutoff) into result from public.assets where id=p_asset;
 select coalesce(jsonb_agg(to_jsonb(e)-'source_key'-'recorded_at' order by e.occurred_at desc,e.id desc),'[]') into entries
 from (select h.* from public.asset_history_entries h where h.asset_id=p_asset
  and h.recorded_at<=cutoff and public.asset_history_readable(h)
  and (p_category is null or h.category=p_category)
  and (p_from is null or h.occurred_at>=p_from) and (p_to is null or h.occurred_at<p_to)
  and (p_before is null or (h.occurred_at,h.id)<(p_before,p_before_id))
  and (btrim(coalesce(p_search,''))='' or position(lower(btrim(p_search)) in lower(h.title||' '||h.body||' '||h.detail::text))>0)
  order by h.occurred_at desc,h.id desc limit p_limit+1) e;
 return result||jsonb_build_object('entries',coalesce((select jsonb_agg(value order by ordinality)
  from jsonb_array_elements(entries) with ordinality where ordinality<=p_limit),'[]'),
  'has_more',jsonb_array_length(entries)>p_limit);
end $$;
revoke all on function public.asset_history_readable(public.asset_history_entries) from public,anon,authenticated;
revoke all on function public.asset_history(uuid,text,text,timestamptz,timestamptz,timestamptz,uuid,integer,timestamptz) from public,anon;
grant execute on function public.asset_history(uuid,text,text,timestamptz,timestamptz,timestamptz,uuid,integer,timestamptz) to authenticated;

-- One serializer owns live capture and initial historical snapshots. It copies
-- explicit user-facing fields, never whole work orders or billing records.
create function public.capture_asset_history_row(p_table text,r jsonb,previous jsonb,p_op text,p_snapshot boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare asset uuid; job uuid; post uuid; source uuid:=nullif(r->>'id','')::uuid; actor uuid;
 category text; kind text; title text:=''; body text:=''; detail jsonb:='{}'; w public.work_orders;
 recorded_time timestamptz; event_key text; payload jsonb; report public.service_reports;
 snapshot_kind boolean:=p_snapshot; current_post public.coordination_posts; actor_name text;
begin
 actor:=coalesce(case when p_snapshot then null else auth.uid() end,nullif(r->>'actor_id','')::uuid,nullif(r->>'logged_by','')::uuid,
  nullif(r->>'submitted_by','')::uuid,nullif(r->>'operator_id','')::uuid);
 recorded_time:=case when p_snapshot then coalesce(nullif(r->>'created_at','')::timestamptz,statement_timestamp()) else clock_timestamp() end;
 if p_table='assets' then
  asset:=source; category:='asset'; title:=r->>'name'; kind:=case when p_op='INSERT' then 'asset_recorded' else 'asset_changed' end;
  detail:=jsonb_build_object('location',r->>'location','make',r->>'make','model',r->>'model','serial_number',r->>'serial_number');
  if p_op='UPDATE' then
   if (r-'updated_at'-'maintenance_revision')=(previous-'updated_at'-'maintenance_revision') then return; end if;
   detail:=detail||jsonb_build_object('previous_location',previous->>'location','previous_name',previous->>'name',
    'ownership_changed',(r->>'client_id') is distinct from (previous->>'client_id'));
  end if;
 elsif p_table='asset_engines' then
  asset:=(r->>'asset_id')::uuid; title:=r->>'label'; category:='asset'; kind:='component_recorded';
  detail:=jsonb_build_object('component',r->>'label','make',r->>'make','model',r->>'model','serial_number',r->>'serial_number',
   'hours',r->'current_hours');
  if p_op='UPDATE' then
   if (r-'updated_at'-'maintenance_revision')=(previous-'updated_at'-'maintenance_revision') then return; end if;
   kind:='component_changed';
   if r->'current_hours' is distinct from previous->'current_hours' then
    category:='usage'; kind:='meter_updated'; detail:=detail||jsonb_build_object('previous_hours',previous->'current_hours');
   end if;
  end if;
 elsif p_table='asset_service_intervals' then
  asset:=(r->>'asset_id')::uuid; category:='service'; kind:=case p_op when 'INSERT' then 'plan_recorded' when 'DELETE' then 'plan_removed' else 'plan_changed' end;
  title:=coalesce(r->>'interval_label',(r->>'interval_hours')||' h');
  detail:=jsonb_build_object('interval_hours',r->'interval_hours','last_service_hours',r->'last_service_hours',
   'next_due_hours',r->'next_due_hours','active',r->'is_active');
  if p_op='UPDATE' and (r-'revision')=(previous-'revision') then return; end if;
 elsif p_table='hour_logs' then
  asset:=(r->>'asset_id')::uuid; job:=nullif(r->>'work_order_id','')::uuid; category:='usage';
  kind:=case p_op when 'INSERT' then 'hours_logged' when 'DELETE' then 'reading_removed' else 'reading_corrected' end;
  title:=coalesce((select label from public.asset_engines where id=nullif(r->>'engine_id','')::uuid),'');
  body:=coalesce(r->>'notes',''); detail:=jsonb_build_object('hours',r->'hours');
  if p_op='UPDATE' then
   if r=previous then return; end if;
   detail:=detail||jsonb_build_object('previous_hours',previous->'hours');
  end if;
  if p_snapshot then recorded_time:=coalesce(nullif(r->>'logged_at','')::timestamptz,recorded_time); end if;
 elsif p_table='work_orders' then
  if (r->>'managed_maintenance')::boolean then return; end if;
  job:=source; asset:=(r->>'asset_id')::uuid; category:='work'; title:=r->>'title'; body:=coalesce(r->>'description','');
  kind:=case p_op when 'INSERT' then 'job_recorded' when 'DELETE' then 'job_removed' else 'job_changed' end;
  detail:=jsonb_build_object('status',r->>'status','scheduled_date',r->>'scheduled_date',
   'assignee',(select full_name from public.profiles where id=nullif(r->>'assigned_to','')::uuid));
  if p_op='UPDATE' then
   if (r-'updated_at')=(previous-'updated_at') then return; end if;
   detail:=detail||jsonb_build_object('previous_status',previous->>'status');
  end if;
 elsif p_table='maintenance_operations' then
  job:=(r->>'object_id')::uuid; select * into w from public.work_orders where id=job;
  if not found or r->>'kind'='remove_part' then return; end if;
  asset:=w.asset_id; title:=w.title; kind:='maintenance_'||(r->>'kind'); category:='work'; payload:=r->'payload';
  body:=coalesce(payload->>'note',''); detail:='{}'; snapshot_kind:=false;
  recorded_time:=(r->>'created_at')::timestamptz; event_key:='maintenance:'||source;
  if r->>'kind'='add_part' then
   category:='parts'; title:=payload->>'description';
   detail:=jsonb_build_object('part_number',payload->>'part_number','quantity',payload->'quantity','unit_cost',payload->'unit_cost',
    'total_cost',(payload->>'quantity')::numeric*(payload->>'unit_cost')::numeric);
  elsif r->>'kind' in ('save_report','submit') then
   category:='service'; body:=coalesce(payload->>'diagnosis','');
   detail:=jsonb_build_object('diagnosis',payload->>'diagnosis','repair',payload->>'repair','notes',payload->>'notes',
    'hours',payload->'completion_hours','photo_count',jsonb_array_length(coalesce(payload->'evidence_paths','[]')));
  elsif r->>'kind'='approve' then
   category:='service';
   -- The approval receipt is authoritative even after reopening or later edits.
   select s.snapshot into payload from public.saved_checklists s where s.id=source;
   detail:=jsonb_build_object('hours',payload->'header'->'current_hours','diagnosis',payload->'report'->>'diagnosis',
    'repair',payload->'report'->>'repair','notes',payload->'report'->>'notes',
    'parts',coalesce(payload->'parts','[]'),'hourly_cost',payload->'hourly_cost',
    'photo_count',jsonb_array_length(coalesce(payload->'evidence_paths','[]')),
    'checklist_count',jsonb_array_length(coalesce(payload->'items','[]')));
   detail:=detail||jsonb_build_object('labour_hours',(select coalesce(sum(extract(epoch from
    ((s->>'stopped_at')::timestamptz-(s->>'started_at')::timestamptz))/3600),0)
    from jsonb_array_elements(coalesce(payload->'labour','[]')) s));
   detail:=detail||jsonb_build_object('total_cost',coalesce((detail->>'labour_hours')::numeric,0)*coalesce((detail->>'hourly_cost')::numeric,0)
    +(select coalesce(sum((p->>'quantity')::numeric*(p->>'unit_cost')::numeric),0) from jsonb_array_elements(coalesce(payload->'parts','[]')) p));
  elsif r->>'kind'='assign' then
   detail:=jsonb_build_object('assignee',(select full_name from public.profiles where id=nullif(payload->>'assigned_to','')::uuid));
  elsif r->>'kind'='block' then
   detail:=jsonb_build_object('blocked_category',coalesce(payload->>'blocked_category','other'));
  end if;
 elsif p_table='parts' then
  job:=(r->>'work_order_id')::uuid; select * into w from public.work_orders where id=job;
  if w.managed_maintenance and p_op<>'DELETE' then return; end if;
  asset:=w.asset_id; category:='parts'; title:=r->>'description';
  kind:=case p_op when 'INSERT' then 'part_recorded' when 'DELETE' then 'part_removed' else 'part_changed' end;
  detail:=jsonb_build_object('part_number',r->>'part_number','quantity',r->'quantity','unit_cost',r->'unit_cost',
   'total_cost',(r->>'quantity')::numeric*(r->>'unit_cost')::numeric);
  if p_op='UPDATE' then
   if (r-'updated_at')=(previous-'updated_at') then return; end if;
   detail:=detail||jsonb_build_object('previous_quantity',previous->'quantity');
  end if;
 elsif p_table='service_reports' then
  job:=(r->>'work_order_id')::uuid; select * into w from public.work_orders where id=job;
  if w.managed_maintenance then return; end if;
  asset:=w.asset_id; category:='service'; title:=w.title; body:=coalesce(r->>'complaint','');
  kind:=case p_op when 'INSERT' then 'report_recorded' when 'DELETE' then 'report_removed' else 'report_changed' end;
  if p_op='UPDATE' and (r-'updated_at')=(previous-'updated_at') then return; end if;
  detail:=jsonb_build_object('diagnosis',r->>'cause','repair',r->>'correction','notes',r->>'comments','signed_at',r->>'signed_at');
 elsif p_table='saved_checklists' then
  job:=nullif(r->>'work_order_id','')::uuid; select * into w from public.work_orders where id=job;
  if w.managed_maintenance then return; end if;
  asset:=(r->>'asset_id')::uuid; category:='inspection'; title:=r->>'template_name';
  kind:=case p_op when 'INSERT' then 'inspection_submitted' when 'DELETE' then 'inspection_removed' else 'inspection_changed' end;
  if p_op='UPDATE' and (r-'updated_at')=(previous-'updated_at') then return; end if;
  body:=coalesce(r->>'general_notes',''); snapshot_kind:=false;
  detail:=jsonb_build_object('hours',r->'current_hours','checklist_type',r->>'checklist_type');
  if p_snapshot then recorded_time:=coalesce(nullif(r->>'submitted_at','')::timestamptz,recorded_time); end if;
 elsif p_table='operator_checklist_runs' then
  asset:=(r->>'asset_id')::uuid; category:='inspection'; kind:='operator_run_recorded';
  title:=coalesce((select name from public.checklist_templates where id=(r->>'template_id')::uuid),'');
  body:=coalesce(r->>'notes',''); detail:=jsonb_build_object('trip_hours',r->'trip_hours','fuel_added',r->'fuel_added','completed_at',r->>'completed_at');
  if p_op='UPDATE' and r=previous then return; end if;
 elsif p_table='maintenance_fault_events' then
  asset:=(r->>'asset_id')::uuid; category:='fault'; kind:='fault_'||(r->>'kind'); source:=(r->>'fault_id')::uuid;
  title:=coalesce((select description from public.maintenance_requests where id=source),''); body:=r->>'note';
  detail:=jsonb_build_object('previous_status',r->>'from_state','status',r->>'to_state'); snapshot_kind:=false;
  recorded_time:=(r->>'created_at')::timestamptz; event_key:='fault:'||(r->>'id'); actor_name:=r->>'actor_name';
 elsif p_table='asset_availability_events' then
  asset:=(r->>'asset_id')::uuid; category:='availability'; kind:='availability_changed'; title:=''; body:=r->>'note';
  detail:=jsonb_build_object('previous_status',r->>'from_state','status',r->>'to_state'); snapshot_kind:=false;
  recorded_time:=(r->>'created_at')::timestamptz; event_key:='availability:'||source; actor_name:=r->>'actor_name';
 elsif p_table='service_report_photos' then
  select * into report from public.service_reports where id=(r->>'service_report_id')::uuid;
  job:=report.work_order_id; select * into w from public.work_orders where id=job;
  asset:=w.asset_id; category:='service'; title:=w.title; body:=coalesce(r->>'caption','');
  kind:=case p_op when 'INSERT' then 'report_photo_added' when 'DELETE' then 'report_photo_removed' else 'report_photo_changed' end;
  detail:=jsonb_build_object('report_id',report.id,'photo_count',1);
 elsif p_table='coordination_posts' then
  post:=source; asset:=(r->>'asset_id')::uuid; category:='discussion'; kind:=r->>'kind'; title:=''; body:=r->>'body';
  actor_name:=r->>'author_name'; snapshot_kind:=false; recorded_time:=(r->>'created_at')::timestamptz;
  detail:=jsonb_build_object('subject_kind',r->>'subject_kind','subject_id',r->>'subject_id','visibility',r->>'visibility',
   'isolation',r->>'isolation','next_steps',r->>'next_steps','photo_count',jsonb_array_length(coalesce(r->'attachments','[]')));
  event_key:='post:'||source;
 elsif p_table='coordination_acknowledgements' then
  post:=(r->>'post_id')::uuid; select * into current_post from public.coordination_posts where id=post;
  source:=post; asset:=current_post.asset_id; category:='discussion'; kind:='handover_acknowledged'; title:='';
  actor_name:=r->>'user_name'; snapshot_kind:=false; recorded_time:=(r->>'created_at')::timestamptz;
  detail:=jsonb_build_object('subject_kind',current_post.subject_kind,'subject_id',current_post.subject_id);
  event_key:='ack:'||post||':'||(r->>'user_id');
 else return;
 end if;
 if asset is null then return; end if;
 if job is not null then select * into w from public.work_orders where id=job; end if;
 if snapshot_kind then
  detail:=detail||jsonb_build_object('historical_snapshot',true,'original_recorded_at',recorded_time);
  recorded_time:=statement_timestamp();
 end if;
 insert into public.asset_history_entries(asset_id,category,kind,source_type,source_id,source_key,job_id,post_id,managed,
  title,body,detail,actor_name,occurred_at)
 values(asset,category,kind,p_table,source,coalesce(event_key,case when p_snapshot then p_table||':snapshot:'||source else gen_random_uuid()::text end),
  job,post,coalesce(w.managed_maintenance,false),coalesce(title,''),coalesce(body,''),jsonb_strip_nulls(detail),
  coalesce(actor_name,(select full_name from public.profiles where id=actor)),recorded_time)
 on conflict(source_key) do nothing;
end $$;
create function public.capture_asset_history_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform public.capture_asset_history_row(TG_TABLE_NAME,case when TG_OP='DELETE' then to_jsonb(old) else to_jsonb(new) end,
  case when TG_OP='INSERT' then '{}'::jsonb else to_jsonb(old) end,TG_OP,false);
 if TG_OP='DELETE' then return old; else return new; end if;
end $$;
revoke all on function public.capture_asset_history_row(text,jsonb,jsonb,text,boolean),public.capture_asset_history_trigger() from public,anon,authenticated;

-- Capture existing evidence before installing live triggers. Mutable records
-- are labeled snapshots; immutable operations retain their recorded timestamps.
do $$
declare source_table text; record jsonb;
begin
 foreach source_table in array array['assets','asset_engines','asset_service_intervals','hour_logs','work_orders',
  'parts','service_reports','saved_checklists','operator_checklist_runs','maintenance_fault_events',
  'asset_availability_events','maintenance_operations','service_report_photos'] loop
  for record in execute format('select to_jsonb(t) from public.%I t',source_table) loop
   perform public.capture_asset_history_row(source_table,record,'{}','INSERT',true);
  end loop;
 end loop;
end $$;
create trigger history_assets after insert or update on public.assets for each row execute function public.capture_asset_history_trigger();
create trigger history_components after insert or update on public.asset_engines for each row execute function public.capture_asset_history_trigger();
create trigger history_plans after insert or update or delete on public.asset_service_intervals for each row execute function public.capture_asset_history_trigger();
create trigger history_hours after insert or update or delete on public.hour_logs for each row execute function public.capture_asset_history_trigger();
create trigger history_work after insert or update on public.work_orders for each row execute function public.capture_asset_history_trigger();
create trigger history_work_removed before delete on public.work_orders for each row execute function public.capture_asset_history_trigger();
create trigger history_parts after insert or update on public.parts for each row execute function public.capture_asset_history_trigger();
create trigger history_parts_removed before delete on public.parts for each row execute function public.capture_asset_history_trigger();
create trigger history_reports after insert or update or delete on public.service_reports for each row execute function public.capture_asset_history_trigger();
create trigger history_checks after insert or update or delete on public.saved_checklists for each row execute function public.capture_asset_history_trigger();
create trigger history_operator after insert or update on public.operator_checklist_runs for each row execute function public.capture_asset_history_trigger();
create trigger history_faults after insert on public.maintenance_fault_events for each row execute function public.capture_asset_history_trigger();
create trigger history_availability after insert on public.asset_availability_events for each row execute function public.capture_asset_history_trigger();
create trigger history_maintenance after insert on public.maintenance_operations for each row execute function public.capture_asset_history_trigger();
create trigger history_report_photos after insert or update or delete on public.service_report_photos for each row execute function public.capture_asset_history_trigger();
create trigger history_discussion after insert on public.coordination_posts for each row execute function public.capture_asset_history_trigger();
create trigger history_acknowledgements after insert on public.coordination_acknowledgements for each row execute function public.capture_asset_history_trigger();
