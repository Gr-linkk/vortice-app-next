-- NEXT-006: purpose is company configuration, not a new working role.
alter table public.organization_service_settings add column company_purpose text
 check (company_purpose in ('fleet','service','both'));

create table public.company_onboarding_operations (
 actor_id uuid not null references public.profiles(id) on delete cascade,
 operation_id uuid not null,
 organization_id uuid not null references public.client_orgs(id) on delete cascade,
 request jsonb not null,
 primary key(actor_id,operation_id)
);
alter table public.company_onboarding_operations enable row level security;
revoke all on public.company_onboarding_operations from public,anon,authenticated;
grant all on public.company_onboarding_operations to service_role;

create function public.create_company_with_purpose(p_name text,p_full_name text,p_purpose text,p_operation uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); org uuid; prior public.company_onboarding_operations;
 request jsonb:=jsonb_build_object('name',btrim(p_name),'full_name',btrim(p_full_name),'purpose',p_purpose);
begin
 if actor is null then raise exception 'Sign in first'; end if;
 if p_purpose is null or p_purpose not in ('fleet','service','both') or p_operation is null
 then raise exception 'Choose how your company will use the app'; end if;
 perform 1 from public.profiles where id=actor for update;
 select * into prior from public.company_onboarding_operations where actor_id=actor and operation_id=p_operation;
 if found then
  if prior.request<>request then raise exception 'This setup attempt already saved different details'; end if;
  if not public.organization_has_permission(prior.organization_id,'member') then raise exception 'Organization access denied'; end if;
  return prior.organization_id;
 end if;
 org:=public.create_company_workspace(p_name,p_full_name);
 update public.organization_service_settings set company_purpose=p_purpose,
  provider_enabled=p_purpose in ('service','both'),updated_at=now() where organization_id=org;
 insert into public.company_onboarding_operations values(actor,p_operation,org,request);
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(org,actor,'company_purpose_selected',jsonb_build_object('purpose',p_purpose));
 return org;
end $$;

create function public.set_company_purpose(p_purpose text) returns void
language plpgsql security definer set search_path='' as $$
declare org uuid:=public.active_organization_id();
begin
 if p_purpose is null or p_purpose not in ('fleet','service','both') then raise exception 'Choose how your company will use the app'; end if;
 if not exists(select 1 from public.organization_memberships where organization_id=org and profile_id=auth.uid()
  and status='active' and 'company_owner'=any(roles)) then raise exception 'Company Owner required'; end if;
 update public.organization_service_settings set company_purpose=p_purpose,
  provider_enabled=p_purpose in ('service','both'),updated_at=now() where organization_id=org;
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(org,auth.uid(),'company_purpose_selected',jsonb_build_object('purpose',p_purpose));
end $$;

-- Older clients can still change provider settings. Never leave the selected
-- purpose inconsistent with that capability; null retains an unchosen default.
create function public.keep_company_purpose_consistent() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.company_purpose is not distinct from old.company_purpose
  and new.provider_enabled is distinct from old.provider_enabled then
  new.company_purpose:=null;
 end if;
 return new;
end $$;
create trigger company_purpose_consistency before update on public.organization_service_settings
for each row execute function public.keep_company_purpose_consistent();

alter function public.organization_context() rename to organization_context_before_purpose;
revoke all on function public.organization_context_before_purpose() from public,anon,authenticated;
create function public.organization_context() returns jsonb
language sql stable security definer set search_path='' as $$
 select context || jsonb_build_object('memberships',coalesce((
  select jsonb_agg(member || jsonb_build_object('company_purpose',settings.company_purpose,
   'provider_enabled',coalesce(settings.provider_enabled,false)) order by position)
  from jsonb_array_elements(context->'memberships') with ordinality entries(member,position)
  left join public.organization_service_settings settings on settings.organization_id=(member->>'organization_id')::uuid
 ),'[]'::jsonb)) from (select public.organization_context_before_purpose() context) base
$$;
revoke all on function public.create_company_with_purpose(text,text,text,uuid),public.set_company_purpose(text),public.organization_context() from public,anon;
grant execute on function public.create_company_with_purpose(text,text,text,uuid),public.set_company_purpose(text),public.organization_context() to authenticated;

-- A provider may create follow-up customer work only for equipment already
-- shared through that active relationship. A relationship alone exposes no fleet.
create function public.customer_work_creation_context() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('equipment',coalesce((select jsonb_agg(to_jsonb(visible) order by customer_name,asset_name) from (
  select distinct r.id relationship_id,a.id asset_id,a.name asset_name,c.name customer_name
  from public.organization_relationships r
  join public.organization_service_settings s on s.organization_id=r.provider_organization_id and s.provider_enabled
  join public.work_orders w on w.organization_relationship_id=r.id
  join public.assets a on a.id=w.asset_id
  join public.client_orgs c on c.id=r.client_organization_id and c.owner_profile_id=a.client_id
  where r.provider_organization_id=public.active_organization_id() and r.status='active'
   and public.organization_has_permission(r.provider_organization_id,'assign_work')
   and public.organization_provider_access(w.id)
 ) visible),'[]'::jsonb))
$$;

create function public.create_customer_work(p_operation uuid,p_relationship uuid,p_asset uuid,p_title text,p_note text default '') returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.organization_relationships; receipt public.closeout_operations; payload jsonb;
begin
 select * into r from public.organization_relationships where id=p_relationship for share;
 if p_operation is null or r.id is null or r.status<>'active'
  or r.provider_organization_id is distinct from public.active_organization_id()
  or not public.organization_has_permission(r.provider_organization_id,'assign_work')
  or not exists(select 1 from public.organization_service_settings where organization_id=r.provider_organization_id and provider_enabled)
  or not exists(select 1 from public.assets a join public.client_orgs c on c.owner_profile_id=a.client_id
   where a.id=p_asset and c.id=r.client_organization_id)
  or not exists(select 1 from public.work_orders w where w.organization_relationship_id=r.id and w.asset_id=p_asset and public.organization_provider_access(w.id))
 then raise exception 'Customer equipment is not available for work'; end if;
 if p_title is null or length(btrim(p_title)) not between 3 and 160 or p_note is null or length(btrim(p_note))>4000
 then raise exception 'Enter a work title and details'; end if;
 payload:=jsonb_build_object('relationship_id',p_relationship,'asset_id',p_asset,'title',btrim(p_title),'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
  if receipt.actor_id<>auth.uid() or receipt.kind<>'customer_work_created' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
  return receipt.result;
 end if;
 insert into public.work_orders(id,organization_relationship_id,provider_organization_id,customer_organization_id,asset_id,client_id,created_by,job_type,title,description,status)
 values(p_operation,r.id,r.provider_organization_id,r.client_organization_id,p_asset,(select client_id from public.assets where id=p_asset),auth.uid(),'repair',btrim(p_title),btrim(p_note),'draft');
 insert into public.organization_work_report_state(work_order_id) values(p_operation);
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'customer_work_created',payload,p_operation);
 return p_operation;
end $$;
revoke all on function public.customer_work_creation_context(),public.create_customer_work(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.customer_work_creation_context(),public.create_customer_work(uuid,uuid,uuid,text,text) to authenticated;
