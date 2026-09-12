-- NEXT-002.22: manager-published organization channel, no direct messaging.
create table public.organization_announcements (
 id uuid primary key,
 organization_id uuid not null references public.client_orgs(id),
 author_id uuid not null references public.profiles(id),
 author_name text not null,
 title text not null check(length(title) between 3 and 160),
 body text not null check(length(body) between 1 and 4000),
 attachments jsonb not null default '[]' check(jsonb_typeof(attachments)='array' and jsonb_array_length(attachments)<=6),
 request_payload jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
create index organization_announcements_feed on public.organization_announcements(organization_id,created_at desc,id desc);
create table public.organization_announcement_receipts (
 announcement_id uuid not null references public.organization_announcements(id),
 profile_id uuid not null references public.profiles(id),
 read_at timestamptz not null default clock_timestamp(),
 primary key(announcement_id,profile_id)
);
alter table public.organization_announcements enable row level security;
alter table public.organization_announcement_receipts enable row level security;
revoke all on public.organization_announcements,public.organization_announcement_receipts from public,anon,authenticated;
grant all on public.organization_announcements,public.organization_announcement_receipts to service_role;

create function public.organization_announcement_reader(p_announcement uuid,p_profile uuid default auth.uid())
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_announcements a where a.id=p_announcement
  and public.organization_has_permission(a.organization_id,'member',p_profile))
$$;
revoke all on function public.organization_announcement_reader(uuid,uuid) from public,anon;
grant execute on function public.organization_announcement_reader(uuid,uuid) to authenticated;

create function public.organization_announcement_upload_allowed(p_path text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare parts text[]:=string_to_array(p_path,'/');
begin
 if array_length(parts,1)<>4 or parts[2] is distinct from auth.uid()::text or parts[4]!~'^[a-zA-Z0-9-]+\.(jpg|jpeg|png|webp)$' then return false; end if;
 perform parts[3]::uuid;
 return public.organization_has_permission(parts[1]::uuid,'announcements_manage')
  and not exists(select 1 from public.organization_announcements where id=parts[3]::uuid);
exception when invalid_text_representation then return false;
end $$;
create function public.organization_announcement_photo_reader(p_path text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_announcements a
  where a.attachments @> jsonb_build_array(jsonb_build_object('path',p_path))
   and public.organization_announcement_reader(a.id))
 or public.organization_announcement_upload_allowed(p_path)
$$;
revoke all on function public.organization_announcement_upload_allowed(text),public.organization_announcement_photo_reader(text) from public,anon;
grant execute on function public.organization_announcement_upload_allowed(text),public.organization_announcement_photo_reader(text) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('organization-announcements','organization-announcements',false,8388608,array['image/jpeg','image/png','image/webp']);
create policy announcement_photo_upload on storage.objects for insert to authenticated
 with check(bucket_id='organization-announcements' and public.organization_announcement_upload_allowed(name));
create policy announcement_photo_read on storage.objects for select to authenticated
 using(bucket_id='organization-announcements' and public.organization_announcement_photo_reader(name));
-- Published messages and uploaded attachments have no client update/delete path.

create function public.publish_organization_announcement(p_organization uuid,p_operation uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare previous public.organization_announcements; title text; body text; files jsonb; file jsonb; prefix text;
begin
 if p_operation is null or not coalesce(public.organization_has_permission(p_organization,'announcements_manage'),false) then raise exception 'Access denied' using errcode='42501'; end if;
 perform 1 from public.organization_memberships where organization_id=p_organization and profile_id=auth.uid() for share;
 if not coalesce(public.organization_has_permission(p_organization,'announcements_manage'),false) then raise exception 'Access denied' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,22));
 select * into previous from public.organization_announcements where id=p_operation;
 if found then
  if previous.organization_id<>p_organization or previous.author_id<>auth.uid() or previous.request_payload is distinct from p_data then raise exception 'Identifier already used for different input'; end if;
  return previous.id;
 end if;
 title:=btrim(coalesce(p_data->>'title',''));body:=btrim(coalesce(p_data->>'body',''));files:=coalesce(p_data->'attachments','[]');
 if jsonb_typeof(p_data) is distinct from 'object' or length(title) not between 3 and 160 or length(body) not between 1 and 4000
  or jsonb_typeof(files)<>'array' or jsonb_array_length(files)>6 then raise exception 'Add a title and message, with at most six photos'; end if;
 prefix:=p_organization::text||'/'||auth.uid()::text||'/'||p_operation::text||'/';
 for file in select value from jsonb_array_elements(files) loop
  if jsonb_typeof(file)<>'object' or length(coalesce(file->>'name','')) not between 1 and 120
   or left(coalesce(file->>'path',''),length(prefix))<>prefix
   or not exists(select 1 from storage.objects o where o.bucket_id='organization-announcements' and o.name=file->>'path') then raise exception 'Attachment is unavailable or belongs to another message'; end if;
 end loop;
 if (select count(distinct value->>'path') from jsonb_array_elements(files))<>jsonb_array_length(files) then raise exception 'Duplicate attachment'; end if;
 insert into public.organization_announcements(id,organization_id,author_id,author_name,title,body,attachments,request_payload)
 select p_operation,p_organization,id,coalesce(full_name,''),title,body,files,p_data from public.profiles where id=auth.uid();
 insert into public.organization_announcement_receipts(announcement_id,profile_id) values(p_operation,auth.uid());
 insert into public.notifications(user_id,title,body,type,reference_id,event_key)
 select m.profile_id,'Organization announcement','Open your organization announcements to read the update.','organization_announcement',p_operation,'organization-announcement:'||p_operation::text||':'||m.profile_id::text
 from public.organization_memberships m where m.organization_id=p_organization and m.status='active' and m.profile_id<>auth.uid()
 on conflict(event_key) do nothing;
 return p_operation;
end $$;

create function public.organization_announcement(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not coalesce(public.organization_announcement_reader(p_id),false) then raise exception 'Access denied' using errcode='42501'; end if;
 select (to_jsonb(a)-'request_payload')||jsonb_build_object('organization_name',o.name,'read_at',r.read_at)
 into result from public.organization_announcements a join public.client_orgs o on o.id=a.organization_id
 left join public.organization_announcement_receipts r on r.announcement_id=a.id and r.profile_id=auth.uid() where a.id=p_id;
 return result;
end $$;
create function public.organization_announcement_feed(p_organization uuid default null,p_before timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare organization uuid:=coalesce(p_organization,public.active_organization_id()); posts jsonb; result jsonb;
begin
 if not coalesce(public.organization_has_permission(organization,'member'),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if (p_before is null)<>(p_before_id is null) then raise exception 'Invalid page cursor'; end if;
 select coalesce(jsonb_agg(x.data order by x.created_at desc,x.id desc),'[]') into posts from (
  select a.id,a.created_at,(to_jsonb(a)-'request_payload')||jsonb_build_object('read_at',r.read_at) as data
  from public.organization_announcements a left join public.organization_announcement_receipts r on r.announcement_id=a.id and r.profile_id=auth.uid()
  where a.organization_id=organization and (p_before is null or (a.created_at,a.id)<(p_before,p_before_id)) order by a.created_at desc,a.id desc limit 51
 ) x;
 select jsonb_build_object('organization_id',o.id,'organization_name',o.name,'can_publish',public.organization_has_permission(o.id,'announcements_manage'),
  'unread_count',(select count(*) from public.organization_announcements a where a.organization_id=o.id and not exists(select 1 from public.organization_announcement_receipts r where r.announcement_id=a.id and r.profile_id=auth.uid())),
  'participant_count',(select count(*) from public.organization_memberships m where m.organization_id=o.id and m.status='active'),
  'participants',coalesce((select jsonb_agg(to_jsonb(x) order by x.name,x.id) from (select p.id,coalesce(p.full_name,'') as name,m.roles from public.organization_memberships m join public.profiles p on p.id=m.profile_id where m.organization_id=o.id and m.status='active' order by p.full_name,p.id limit 200) x),'[]'),
  'posts',coalesce((select jsonb_agg(value order by ordinality) from jsonb_array_elements(posts) with ordinality where ordinality<=50),'[]'),'has_more',jsonb_array_length(posts)>50)
 into result from public.client_orgs o where o.id=organization;
 return result;
end $$;
create function public.mark_organization_announcement_read(p_announcement uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(public.organization_announcement_reader(p_announcement),false) then raise exception 'Access denied' using errcode='42501'; end if;
 insert into public.organization_announcement_receipts(announcement_id,profile_id) values(p_announcement,auth.uid()) on conflict do nothing;
 update public.notifications set read=true where user_id=auth.uid() and type='organization_announcement' and reference_id=p_announcement;
end $$;
revoke all on function public.publish_organization_announcement(uuid,uuid,jsonb),public.organization_announcement(uuid),public.organization_announcement_feed(uuid,timestamptz,uuid),public.mark_organization_announcement_read(uuid) from public,anon,authenticated;
grant execute on function public.publish_organization_announcement(uuid,uuid,jsonb),public.organization_announcement(uuid),public.organization_announcement_feed(uuid,timestamptz,uuid),public.mark_organization_announcement_read(uuid) to authenticated;

create policy announcement_notification_boundary on public.notifications as restrictive for select to authenticated
 using(type is distinct from 'organization_announcement' or public.organization_announcement_reader(reference_id));

-- Recheck current membership before a pending organization push is leased.
create or replace function public.claim_push_deliveries(p_limit integer default 25) returns jsonb
language plpgsql security definer set search_path='' as $$
declare claimed jsonb;
begin
 perform public.queue_inspection_deadlines();
 update public.push_deliveries set status='failed',last_error='Delivery attempts exhausted'
 where status='pending' and attempts>=8 and (leased_until is null or leased_until<now());
 insert into public.push_deliveries(notification_id,device_id)
 select n.id,d.id from public.notifications n join public.push_devices d on d.user_id=n.user_id
 where d.enabled and n.event_key is not null and n.created_at>now()-interval '7 days' and not n.read
 on conflict(notification_id,device_id) do nothing;
 update public.push_deliveries x set status='cancelled',last_error='Recipient access changed'
 from public.notifications n,public.push_devices d where x.notification_id=n.id and x.device_id=d.id and x.status='pending'
 and (not d.enabled or n.user_id<>d.user_id or not case when n.type='organization_announcement' then public.organization_announcement_reader(n.reference_id,d.user_id) else public.coordination_asset_viewer(n.asset_id,d.user_id) end
  or (n.type in ('work_order','maintenance_assignment','maintenance_return') and not exists(select 1 from public.work_orders w where w.id=n.reference_id and w.assigned_to=d.user_id)));
 with picked as(select id from public.push_deliveries where status='pending' and attempts<8
   and next_attempt<=now() and (leased_until is null or leased_until<now())
   order by next_attempt,id limit least(greatest(p_limit,1),100) for update skip locked),
 updated as(update public.push_deliveries d set lease=gen_random_uuid(),leased_until=now()+interval '3 minutes',attempts=attempts+1
   from picked where d.id=picked.id returning d.*)
 select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'lease',u.lease,'token',d.token,'locale',d.locale,
  'notification_id',n.id,'user_id',n.user_id,'type',n.type,'reference_id',n.reference_id)),'[]') into claimed
 from updated u join public.push_devices d on d.id=u.device_id join public.notifications n on n.id=u.notification_id;
 return claimed;
end $$;
