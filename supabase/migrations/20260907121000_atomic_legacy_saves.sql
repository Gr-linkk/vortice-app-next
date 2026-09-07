-- NOW-016: receipts and atomic saves for existing online workflows.
create table public.closeout_operations (
 id uuid primary key, actor_id uuid not null references public.profiles(id),
 kind text not null, payload jsonb not null, result uuid not null,
 created_at timestamptz not null default now()
);
alter table public.closeout_operations enable row level security;
revoke all on public.closeout_operations from public,anon,authenticated;
grant all on public.closeout_operations to service_role;

alter table public.hour_logs add column source text not null default 'legacy';
alter table public.asset_engines add column meter_captured_at timestamptz;

create function public.record_manual_meter(p_operation uuid,p_engine uuid,p_asset uuid,p_hours numeric,
 p_captured_at timestamptz,p_notes text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare e public.asset_engines; receipt public.closeout_operations;
 payload jsonb:=jsonb_build_object('engine',p_engine,'asset',p_asset,'hours',p_hours,'captured_at',p_captured_at,'notes',p_notes);
begin
 if auth.uid() is null or not public.maintenance_can_view_asset(p_asset) then raise exception 'Asset access required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
   if receipt.actor_id<>auth.uid() or receipt.kind<>'meter' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
   return receipt.result;
 end if;
 select * into e from public.asset_engines where id=p_engine and asset_id=p_asset for update;
 if not found then raise exception 'Component unavailable'; end if;
 if p_hours is null or p_hours<0 or p_hours>=1000000000 or p_hours='NaN'::numeric then raise exception 'Invalid meter reading'; end if;
 if p_captured_at is null or p_captured_at>now()+interval '5 minutes' then raise exception 'Invalid reading time'; end if;
 if p_hours<coalesce(e.current_hours,0) or p_captured_at<e.meter_captured_at then
   raise exception 'A newer meter reading was accepted. Refresh and correct this submission';
 end if;
 insert into public.hour_logs(id,engine_id,asset_id,hours,logged_by,logged_at,source,notes)
 values(p_operation,p_engine,p_asset,p_hours,auth.uid(),p_captured_at,'manual',p_notes);
 update public.asset_engines set current_hours=p_hours,meter_captured_at=p_captured_at,
 maintenance_revision=maintenance_revision+1 where id=p_engine;
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'meter',payload,p_operation);
 return p_operation;
end $$;

create function public.create_client_org(p_operation uuid,p_name text,p_owner uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare p public.profiles; receipt public.closeout_operations; result uuid;
 payload jsonb:=jsonb_build_object('name',btrim(p_name),'owner',p_owner);
begin
 if public.get_my_role() is distinct from 'owner' then raise exception 'Owner required'; end if;
 if nullif(btrim(p_name),'') is null then raise exception 'Organization name required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
   if receipt.actor_id<>auth.uid() or receipt.kind<>'create_org' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
   return receipt.result;
 end if;
 select * into p from public.profiles where id=p_owner for update;
 if not found or p.role<>'client' then raise exception 'A client owner is required'; end if;
 if p.org_id is not null or exists(select 1 from public.client_orgs where owner_profile_id=p_owner) then
   raise exception 'Client already belongs to an organization';
 end if;
 insert into public.client_orgs(id,name,owner_profile_id) values(p_operation,btrim(p_name),p_owner) returning id into result;
 update public.profiles set org_id=result where id=p_owner;
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'create_org',payload,result);
 return result;
end $$;

create function public.delete_client_org(p_operation uuid,p_org uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare receipt public.closeout_operations;
 payload jsonb:=jsonb_build_object('org',p_org);
begin
 if public.get_my_role() is distinct from 'owner' then raise exception 'Owner required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
   if receipt.actor_id<>auth.uid() or receipt.kind<>'delete_org' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
   return receipt.result;
 end if;
 perform 1 from public.client_orgs where id=p_org for update;
 update public.profiles set org_id=null where org_id=p_org;
 -- Any dependent-record refusal rolls membership changes back with the delete.
 delete from public.client_orgs where id=p_org;
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'delete_org',payload,p_org);
 return p_org;
end $$;

revoke all on function public.record_manual_meter(uuid,uuid,uuid,numeric,timestamptz,text),
 public.create_client_org(uuid,text,uuid),public.delete_client_org(uuid,uuid) from public,anon;
grant execute on function public.record_manual_meter(uuid,uuid,uuid,numeric,timestamptz,text),
 public.create_client_org(uuid,text,uuid),public.delete_client_org(uuid,uuid) to authenticated;
