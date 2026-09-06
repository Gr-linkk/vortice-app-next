-- Server-selected recipients, durable per-device delivery, and revocable tokens.
alter table public.notifications add column event_key text unique, add column asset_id uuid references public.assets(id) on delete cascade;
revoke insert,update,delete on public.notifications from authenticated,anon;
grant update(read) on public.notifications to authenticated;
drop policy "Authenticated users can insert notifications" on public.notifications;
create table public.push_devices (
 id uuid primary key,user_id uuid not null references public.profiles(id) on delete cascade,
 token text not null unique,locale text not null default 'en',enabled boolean not null default true,updated_at timestamptz not null default now()
);
create table public.push_deliveries (
 id uuid primary key default gen_random_uuid(),notification_id uuid not null references public.notifications(id) on delete cascade,
 device_id uuid not null references public.push_devices(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','sent','failed','cancelled')),
 attempts integer not null default 0,next_attempt timestamptz not null default now(),
 lease uuid,leased_until timestamptz,last_error text,sent_at timestamptz,
 unique(notification_id,device_id)
);
alter table public.push_devices enable row level security;
alter table public.push_deliveries enable row level security;
revoke all on public.push_devices,public.push_deliveries from public,anon,authenticated;
grant all on public.push_devices,public.push_deliveries to service_role;

create function public.register_push_device(p_device uuid,p_token text,p_locale text default 'en')
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or length(p_token)<20 or length(p_token)>4096 then raise exception 'Invalid device registration'; end if;
 delete from public.push_devices where token=p_token and id<>p_device;
 insert into public.push_devices(id,user_id,token,locale) values(p_device,auth.uid(),p_token,case when p_locale='es' then 'es' else 'en' end)
 on conflict(id) do update set user_id=auth.uid(),token=excluded.token,locale=excluded.locale,enabled=true,updated_at=now();
end $$;
create function public.unregister_push_device(p_device uuid) returns void language sql security definer set search_path='' as $$
 update public.push_devices set enabled=false where id=p_device and user_id=auth.uid()
$$;
revoke all on function public.register_push_device(uuid,text,text),public.unregister_push_device(uuid) from public,anon;
grant execute on function public.register_push_device(uuid,text,text),public.unregister_push_device(uuid) to authenticated;

create function public.queue_activity(p_user uuid,p_asset uuid,p_kind text,p_reference uuid,p_event text,p_title text,p_body text)
returns void language sql security definer set search_path='' as $$
 insert into public.notifications(user_id,asset_id,type,reference_id,event_key,title,body)
 select p_user,p_asset,p_kind,p_reference,p_event||':'||p_user::text,p_title,p_body
 where public.coordination_asset_viewer(p_asset,p_user)
 on conflict(event_key) do nothing
$$;
revoke all on function public.queue_activity(uuid,uuid,text,uuid,text,text,text) from public,anon,authenticated;

create function public.capture_push_activity() returns trigger language plpgsql security definer set search_path='' as $$
declare recipient record; asset uuid; event text; kind text; subject uuid; title text; body text;
begin
 if tg_table_name='work_orders' then
  if new.assigned_to is not null and (tg_op='INSERT' or old.assigned_to is distinct from new.assigned_to) then
   perform public.queue_activity(new.assigned_to,new.asset_id,case when new.managed_maintenance then 'maintenance_assignment' else 'work_order' end,new.id,
     'assignment:'||new.id::text||':'||clock_timestamp()::text,'Work assigned','Open this job to review your assignment.');
  end if;
  return new;
 elsif tg_table_name='maintenance_operations' then
  if new.kind<>'return' then return new; end if;
  perform public.queue_activity(w.assigned_to,w.asset_id,'maintenance_return',w.id,'returned:'||new.id::text,
   'Report returned','Review the manager feedback and update your report.') from public.work_orders w where w.id=new.object_id;
  return new;
 elsif tg_table_name='maintenance_requests' then
  if new.severity<>'urgent' or (tg_op='UPDATE' and old.severity='urgent') then return new; end if;
  asset:=new.asset_id;subject:=new.id;kind:='urgent_fault';event:='urgent-fault:'||new.id::text;
  title:='Urgent fault reported';body:='Review the fault and asset availability.';
 end if;
 for recipient in select p.id from public.profiles p where p.role in ('owner','client','client_admin')
   and public.coordination_asset_viewer(asset,p.id) loop
  perform public.queue_activity(recipient.id,asset,kind,subject,event,title,body);
 end loop;
 return new;
end $$;
revoke all on function public.capture_push_activity() from public,anon,authenticated;
create trigger push_assignment after insert or update of assigned_to on public.work_orders for each row execute function public.capture_push_activity();
create trigger push_return after insert on public.maintenance_operations for each row execute function public.capture_push_activity();
create trigger push_urgent after insert or update of severity on public.maintenance_requests for each row execute function public.capture_push_activity();

create function public.queue_inspection_deadlines() returns void language plpgsql security definer set search_path='' as $$
declare due record; recipient record; milestone text;
begin
 for due in select i.id,i.asset_id,s.id version_id,s.expires_on from public.asset_inspections i
  cross join lateral(select id,expires_on from public.inspection_submissions where inspection_id=i.id and status='approved'
   order by reviewed_at desc,id desc limit 1) s where s.expires_on<=current_date+30 loop
  milestone:=case when due.expires_on<current_date then 'expired' when due.expires_on<=current_date+7 then '7-days' else '30-days' end;
  for recipient in select p.id from public.profiles p where p.role in ('owner','client','client_admin')
    and public.coordination_asset_viewer(due.asset_id,p.id) loop
   perform public.queue_activity(recipient.id,due.asset_id,'inspection_due',due.asset_id,
    'inspection:'||due.version_id::text||':'||milestone,'Inspection deadline',
    case when milestone='expired' then 'An inspection has expired.' else 'An inspection expires on '||due.expires_on::text||'.' end);
  end loop;
 end loop;
end $$;
revoke all on function public.queue_inspection_deadlines() from public,anon,authenticated;
grant execute on function public.queue_inspection_deadlines() to service_role;

create function public.claim_push_deliveries(p_limit integer default 25) returns jsonb
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
 and (not d.enabled or n.user_id<>d.user_id or not public.coordination_asset_viewer(n.asset_id,d.user_id)
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
create function public.finish_push_delivery(p_delivery uuid,p_lease uuid,p_success boolean,p_error text default null,p_invalid_token boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare device uuid;
begin
 update public.push_deliveries set status=case when p_success then 'sent' when p_invalid_token or attempts>=8 then 'failed' else 'pending' end,
  sent_at=case when p_success then now() end,last_error=left(p_error,500),lease=null,leased_until=null,
  next_attempt=now()+make_interval(secs=>least(3600,30*power(2,attempts)::integer))
 where id=p_delivery and lease=p_lease returning device_id into device;
 if p_invalid_token and device is not null then update public.push_devices set enabled=false where id=device; end if;
end $$;
revoke all on function public.claim_push_deliveries(integer),public.finish_push_delivery(uuid,uuid,boolean,text,boolean) from public,anon,authenticated;
grant execute on function public.claim_push_deliveries(integer),public.finish_push_delivery(uuid,uuid,boolean,text,boolean) to service_role;
