-- NOW-019. Scoped opaque credentials; no privileged key in an agent runtime.
create table public.agent_connections (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid not null references public.profiles(id) on delete cascade,
 client_id uuid not null references public.profiles(id) on delete cascade,
 label text not null check(length(label) between 1 and 80),
 token_hash text not null unique,
 allow_drafts boolean not null default false,
 allow_documents boolean not null default false,
 allow_management boolean not null default false,
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default clock_timestamp()+interval '7 days',
 revoked_at timestamptz
);
create table public.agent_activity (
 id bigint generated always as identity primary key,
 connection_id uuid not null references public.agent_connections(id) on delete cascade,
 actor_id uuid references public.profiles(id) on delete set null,
 action text not null,
 outcome text not null,
 operation_id uuid,
 input_hash text,
 result_id uuid,
 result jsonb,
 created_at timestamptz not null default clock_timestamp()
);
create index agent_activity_recent on public.agent_activity(connection_id,created_at desc);
create unique index agent_draft_replay on public.agent_activity(connection_id,operation_id)
 where outcome='created';
alter table public.agent_connections enable row level security;
alter table public.agent_activity enable row level security;
revoke all on public.agent_connections,public.agent_activity from public,anon,authenticated;
revoke all on sequence public.agent_activity_id_seq from public,anon,authenticated;

create function public.agent_can_manage_fleet(p_client uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=auth.uid()
 and coalesce((to_jsonb(u)->>'banned_until')::timestamptz<=now(),true) and
 (p.role='owner' or (p.role in ('client','client_admin') and
 ((p.org_id is null and p.id=p_client) or exists(select 1 from public.client_orgs o
 where o.id=p.org_id and o.owner_profile_id=p_client)))))
$$;

create function public.agent_access_context()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role in ('owner','client','client_admin'))
 then raise exception 'Access denied'; end if;
 return jsonb_build_object(
 'owner_verification_required',exists(select 1 from public.profiles where id=auth.uid() and role='owner') and (
   coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'aal','')<>'aal2'
   or not exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified')),
 'fleets',(select coalesce(jsonb_agg(x order by x.name),'[]') from (
 select distinct a.client_id id,p.full_name name from public.assets a join public.profiles p on p.id=a.client_id
 where public.agent_can_manage_fleet(a.client_id)) x),
 'connections_truncated',(select count(*)>200 from public.agent_connections where public.agent_can_manage_fleet(client_id)),
 'connections',(select coalesce(jsonb_agg(x order by (x.revoked_at is null and x.expires_at>now()) desc,x.created_at desc),'[]') from (
 select c.id,c.actor_id,p.full_name actor_name,c.client_id,c.label,c.allow_drafts,c.allow_documents,c.allow_management,c.created_at,c.expires_at,c.revoked_at
 from public.agent_connections c join public.profiles p on p.id=c.actor_id where public.agent_can_manage_fleet(c.client_id)
 order by (c.revoked_at is null and c.expires_at>now()) desc,c.created_at desc limit 200) x),
 'activity',(select coalesce(jsonb_agg(x order by x.id desc),'[]') from (
 select e.id,e.connection_id,e.actor_id,e.action,e.outcome,e.result_id,e.created_at,c.label
 from public.agent_activity e join public.agent_connections c on c.id=e.connection_id
 where public.agent_can_manage_fleet(c.client_id) order by e.id desc limit 100) x));
end $$;

create function public.create_agent_connection(p_client uuid,p_label text,p_allow_drafts boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare secret text; conn public.agent_connections;
begin
 if not public.agent_can_manage_fleet(p_client) or not exists(select 1 from public.assets where client_id=p_client)
 then raise exception 'Access denied'; end if;
 if exists(select 1 from public.profiles where id=auth.uid() and role='owner') and (
   coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'aal','')<>'aal2'
   or not exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified'))
 then raise exception 'Owner two-factor verification required'; end if;
 if p_label is null or length(btrim(p_label)) not between 1 and 80 or p_allow_drafts is null
 then raise exception 'Enter a connection name (1 to 80 characters)'; end if;
 -- Serialize grant creation per user to enforce the cap under concurrency.
 perform 1 from public.profiles where id=auth.uid() for update;
 if (select count(*) from public.agent_connections where actor_id=auth.uid() and revoked_at is null
 and expires_at>clock_timestamp())>=10 then raise exception 'Disconnect an existing connection first'; end if;
 secret:='vna_'||encode(extensions.gen_random_bytes(32),'hex');
 insert into public.agent_connections(actor_id,client_id,label,token_hash,allow_drafts)
 values(auth.uid(),p_client,btrim(p_label),encode(extensions.digest(secret,'sha256'),'hex'),p_allow_drafts)
 returning * into conn;
 insert into public.agent_activity(connection_id,actor_id,action,outcome)
 values(conn.id,auth.uid(),'connection','created');
 return jsonb_build_object('id',conn.id,'token',secret,'expires_at',conn.expires_at);
end $$;

create function public.revoke_agent_connections(p_connection uuid default null,p_client uuid default null,p_all boolean default false)
returns integer language plpgsql security definer set search_path='' as $$
declare conn public.agent_connections; total integer:=0;
begin
 if (p_connection is not null)::int+(p_client is not null)::int+coalesce(p_all,false)::int<>1
 then raise exception 'Choose one disconnect target'; end if;
 if p_all and not exists(select 1 from public.profiles where id=auth.uid() and role='owner')
 then raise exception 'Access denied'; end if;
 if p_client is not null and not public.agent_can_manage_fleet(p_client) then raise exception 'Access denied'; end if;
 for conn in select * from public.agent_connections where revoked_at is null
 and (id=p_connection or client_id=p_client or p_all) order by id for update loop
   if conn.actor_id is distinct from auth.uid() and not public.agent_can_manage_fleet(conn.client_id)
   then raise exception 'Access denied'; end if;
   update public.agent_connections set revoked_at=clock_timestamp() where id=conn.id;
   insert into public.agent_activity(connection_id,actor_id,action,outcome)
   values(conn.id,auth.uid(),'connection','revoked');
   total:=total+1;
 end loop;
 return total;
end $$;

create function public.agent_execute(p_token text,p_action text,p_input jsonb default '{}',p_operation uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare conn public.agent_connections; answer jsonb; failure text; aid uuid; job uuid;
 fingerprint text; prior public.agent_activity; old_sub text; old_claims text;
 page integer; total integer;
begin
 if p_token is null or p_token !~ '^vna_[0-9a-f]{64}$' then return '{"error":"Access denied"}'; end if;
 select * into conn from public.agent_connections
 where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if conn.id is null or conn.revoked_at is not null or conn.expires_at<=clock_timestamp()
 then return '{"error":"Access denied"}'; end if;
 -- Bounded activity growth, including invalid requests. Grant lock serializes the limit.
 if (select count(*) from public.agent_activity where connection_id=conn.id
 and created_at>clock_timestamp()-interval '1 minute')>=60 then return '{"error":"Rate limit; retry later"}'; end if;
 old_sub:=current_setting('request.jwt.claim.sub',true);
 old_claims:=current_setting('request.jwt.claims',true);
 begin
   perform set_config('request.jwt.claim.sub',conn.actor_id::text,true);
   perform set_config('request.jwt.claims',jsonb_build_object('sub',conn.actor_id,'role','authenticated')::text,true);
   if not public.agent_can_manage_fleet(conn.client_id) then raise exception 'Access denied'; end if;
   if exists(select 1 from public.profiles where id=conn.actor_id and role='owner')
     and not exists(select 1 from auth.mfa_factors where user_id=conn.actor_id and status='verified')
   then raise exception 'Access denied'; end if;
   if p_input is null or jsonb_typeof(p_input)<>'object' or octet_length(p_input::text)>96000
   then raise exception 'Invalid input'; end if;
   if p_action='maintenance_summary' then
     if exists(select 1 from jsonb_object_keys(p_input) k where k not in ('page')) then raise exception 'Invalid input'; end if;
     page:=coalesce((p_input->>'page')::integer,0);
     if page<0 or page>10000 then raise exception 'Invalid page'; end if;
     select count(*) into total from public.assets where client_id=conn.client_id;
     select jsonb_build_object('assets',coalesce(jsonb_agg(x order by x.id),'[]'),
       'next_page',case when (page+1)*25<total then page+1 else null end)
     into answer from (
       select a.id,a.name,
       (select count(*) from public.work_orders w where w.asset_id=a.id and w.managed_maintenance and w.status<>'closed') open_work_orders,
       (select count(*)>50 from public.asset_service_intervals i where i.asset_id=a.id and i.is_active) plans_truncated,
       (select coalesce(jsonb_agg(s),'[]') from (
          select i.id,i.interval_label,i.engine_id,e.current_hours,i.next_due_hours,
          i.next_due_hours-e.current_hours hours_remaining
          from public.asset_service_intervals i left join public.asset_engines e on e.id=i.engine_id
          where i.asset_id=a.id and i.is_active order by i.next_due_hours-e.current_hours nulls last,i.id limit 50) s) plans
       from public.assets a where a.client_id=conn.client_id and public.maintenance_can_view_asset(a.id)
       order by a.id limit 25 offset page*25) x;
   elsif p_action='create_work_order_draft' then
     if not conn.allow_drafts then raise exception 'Draft permission required'; end if;
     if p_operation is null then raise exception 'Operation ID required'; end if;
     if exists(select 1 from jsonb_object_keys(p_input) k where k not in
       ('asset_id','title','description','job_type','service_interval_id','engine_id','priority','expected_materials','checklist_template_id'))
     then raise exception 'Invalid input'; end if;
     if exists(select 1 from jsonb_each(p_input) e where jsonb_typeof(e.value)<>'string') then raise exception 'Invalid input'; end if;
     if not (p_input ? 'asset_id') or not (p_input ? 'title') then raise exception 'Asset and title required'; end if;
     aid:=(p_input->>'asset_id')::uuid;
     if not exists(select 1 from public.assets where id=aid and client_id=conn.client_id)
       or not public.maintenance_can_manage_asset(aid) or not public.maintenance_execution_enabled(aid)
     then raise exception 'Access denied'; end if;
     fingerprint:=encode(extensions.digest(p_input::text,'sha256'),'hex');
     select * into prior from public.agent_activity where connection_id=conn.id
     and operation_id=p_operation and outcome='created';
     if prior.id is not null then
       if prior.action<>'create_work_order_draft' or prior.input_hash is distinct from fingerprint then raise exception 'Operation ID used with different input'; end if;
       answer:=jsonb_build_object('work_order_id',prior.result_id,'replayed',true);
     else
       if (select count(*) from public.agent_activity where connection_id=conn.id and outcome='created'
         and action='create_work_order_draft' and created_at>clock_timestamp()-interval '1 day')>=20
       then raise exception 'Daily draft limit reached'; end if;
       job:=public.create_maintenance_job(gen_random_uuid(),p_input);
       answer:=jsonb_build_object('work_order_id',job,'status','draft','replayed',false);
     end if;
   elsif p_action in ('documents','document_page','create_checklist_draft','create_plan_draft','work_order_context','assign_work_order','schedule_work_order','edit_work_order') then
     answer:=public.agent_workflow_action(conn,p_action,p_input,p_operation);
   else raise exception 'Unknown action'; end if;
 exception when others then
   -- Never expose database internals, identifiers from other fleets or submitted text.
   failure:=case when sqlerrm in ('Access denied','Invalid input','Invalid page','Unknown action',
   'Document permission required','Management permission required','Each step needs a source page and quote','Daily action limit reached','Revision required',
   'Draft permission required','Operation ID required','Asset and title required',
   'Operation ID used with different input','Daily draft limit reached') then sqlerrm
   else 'Request rejected; check the work-order fields and current permissions' end;
 end;
 perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);
 perform set_config('request.jwt.claims',coalesce(old_claims,''),true);
 -- Successful advanced writes already stored their result atomically. Reads,
 -- rejected attempts and exact retries get one additional activity entry.
 if p_action not in ('create_checklist_draft','create_plan_draft','assign_work_order','schedule_work_order','edit_work_order')
   or failure is not null or coalesce((answer->>'replayed')::boolean,false) then
  insert into public.agent_activity(connection_id,actor_id,action,outcome,operation_id,input_hash,result_id)
  values(conn.id,conn.actor_id,case when p_action in ('maintenance_summary','create_work_order_draft','documents','document_page',
   'create_checklist_draft','create_plan_draft','work_order_context','assign_work_order','schedule_work_order','edit_work_order') then p_action else 'unknown' end,
  case when failure is not null then 'rejected' when job is not null then 'created'
   when prior.id is not null or coalesce((answer->>'replayed')::boolean,false) then 'replayed' else 'read' end,
  p_operation,case when job is not null then fingerprint end,
  case when failure is null then coalesce(job,prior.result_id,(answer->>'work_order_id')::uuid,(answer->>'procedure_id')::uuid,(answer->>'plan_draft_id')::uuid) end);
 end if;
 if failure is not null then return jsonb_build_object('error',failure); end if;
 return jsonb_build_object('data',answer);
end $$;

revoke all on function public.agent_can_manage_fleet(uuid),public.agent_access_context(),
 public.create_agent_connection(uuid,text,boolean),public.revoke_agent_connections(uuid,uuid,boolean),
 public.agent_execute(text,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.agent_access_context(),public.create_agent_connection(uuid,text,boolean),
 public.revoke_agent_connections(uuid,uuid,boolean) to authenticated;
-- The opaque credential is checked inside this sole public agent entry point.
grant execute on function public.agent_execute(text,text,jsonb,uuid) to anon,authenticated;
