-- NEXT-002.18/.01. Additive identity and organization authorization.
-- Existing provider accounts remain legacy; new company users never receive
-- the platform/provider 'owner' role. No accounts, assets or records are reset.
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check check
 (role in ('owner','employee','client','operator','client_admin','client_mechanic','client_operator','member'));

create table public.organization_memberships (
 organization_id uuid not null references public.client_orgs(id),
 profile_id uuid not null references public.profiles(id),
 roles text[] not null default '{}', permissions text[] not null default '{}',
 status text not null default 'active' check(status in ('active','revoked')),
 created_by uuid references public.profiles(id), created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 primary key(organization_id,profile_id),
 check(cardinality(roles)>0 and roles <@ array['company_owner','supervisor','mechanic','operator']),
 check(permissions <@ array['team_admin','billing','inspection_manage','announcements_manage'])
);
create table public.organization_identity_context (
 profile_id uuid primary key references public.profiles(id),
 active_organization_id uuid references public.client_orgs(id)
);
create table public.organization_membership_events (
 id bigint generated always as identity primary key,
 organization_id uuid not null references public.client_orgs(id),
 actor_id uuid references public.profiles(id), subject_id uuid references public.profiles(id),
 action text not null, detail jsonb not null default '{}', created_at timestamptz not null default now()
);
create table public.organization_invitations (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.client_orgs(id),
 token_hash text not null unique, roles text[] not null, permissions text[] not null default '{}',
 contact text, expires_at timestamptz not null, created_by uuid not null references public.profiles(id),
 redeemed_by uuid references public.profiles(id), redeemed_at timestamptz, revoked_at timestamptz,
 created_at timestamptz not null default now(),
 check(cardinality(roles)>0 and roles <@ array['company_owner','supervisor','mechanic','operator']),
 check(permissions <@ array['team_admin','billing','inspection_manage','announcements_manage'])
);
create table public.organization_relationships (
 id uuid primary key default gen_random_uuid(), provider_organization_id uuid not null references public.client_orgs(id),
 client_organization_id uuid not null references public.client_orgs(id),
 status text not null default 'proposed' check(status in ('proposed','active','revoked')),
 proposed_by uuid not null references public.profiles(id), accepted_by uuid references public.profiles(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(provider_organization_id,client_organization_id), check(provider_organization_id<>client_organization_id)
);
-- Freeze the legacy provider's previously authorized tenants. New companies
-- are not silently enrolled into that global owner/employee service account.
create table public.legacy_provider_tenants(client_id uuid primary key references public.profiles(id));
create table public.legacy_provider_identities(profile_id uuid primary key references public.profiles(id));
insert into public.legacy_provider_identities select id from public.profiles;
insert into public.legacy_provider_tenants select distinct id from public.profiles where role in ('client','client_admin')
union select distinct client_id from public.assets;
alter table public.legacy_provider_tenants enable row level security;
alter table public.legacy_provider_identities enable row level security;
revoke all on public.legacy_provider_tenants from public,anon,authenticated;
revoke all on public.legacy_provider_identities from public,anon,authenticated;
create function public.register_legacy_provider_tenant() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.role<>'member' then insert into public.legacy_provider_identities values(new.id) on conflict do nothing; end if;
 if new.role in ('client','client_admin') then insert into public.legacy_provider_tenants values(new.id) on conflict do nothing; end if;
 return new;
end $$;
create trigger legacy_provider_tenant_registration after insert on public.profiles for each row execute function public.register_legacy_provider_tenant();

-- Backfill only previously affiliated company profiles. Existing provider and
-- platform roles are deliberately not converted into customer-company owners.
insert into public.organization_memberships(organization_id,profile_id,roles)
select o.id,p.id,case when o.owner_profile_id=p.id then array['company_owner']
 when p.role in ('client','client_admin') then array['supervisor']
 when p.role='client_mechanic' then array['mechanic'] else array['operator'] end
from public.client_orgs o join public.profiles p on (p.org_id=o.id or p.id=o.owner_profile_id)
where p.role in ('client','client_admin','client_mechanic','operator','client_operator')
on conflict do nothing;
insert into public.organization_identity_context(profile_id,active_organization_id)
select p.id,p.org_id from public.profiles p where exists(select 1 from public.organization_memberships m
 where m.profile_id=p.id and m.organization_id=p.org_id) on conflict do nothing;

create function public.organization_has_permission(p_organization_id uuid,p_permission text,p_profile_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(exists(select 1 from public.organization_memberships m where m.organization_id=p_organization_id
 and m.profile_id=p_profile_id and m.status='active' and (
 p_permission='member' or 'company_owner'=any(m.roles) or p_permission=any(m.permissions)
 or (p_permission in ('assets_manage','planning','assign_work','review_work','approve_work') and 'supervisor'=any(m.roles))
 or (p_permission in ('work_assigned','reports','labour','parts') and m.roles && array['supervisor','mechanic'])
 or (p_permission in ('preop','readings','issues','handover','discussions') and cardinality(m.roles)>0)
 )),false)
$$;
create function public.active_organization_id() returns uuid
language sql stable security definer set search_path='' as $$
 select coalesce((select c.active_organization_id from public.organization_identity_context c
 where c.profile_id=auth.uid() and public.organization_has_permission(c.active_organization_id,'member')),
 (select m.organization_id from public.organization_memberships m where m.profile_id=auth.uid()
 and m.status='active' order by m.created_at,m.organization_id limit 1))
$$;
create function public.organization_for_asset(p_asset uuid) returns uuid
language sql stable security definer set search_path='' as $$
 select o.id from public.assets a join public.client_orgs o on o.owner_profile_id=a.client_id
 where a.id=p_asset order by o.created_at,o.id limit 1
$$;
create function public.organization_asset_permission(p_asset uuid,p_permission text) returns boolean
language sql stable security definer set search_path='' as $$
 select public.organization_for_asset(p_asset)=public.active_organization_id()
 and public.organization_has_permission(public.organization_for_asset(p_asset),p_permission)
$$;

alter table public.organization_memberships enable row level security;
alter table public.organization_identity_context enable row level security;
alter table public.organization_membership_events enable row level security;
alter table public.organization_invitations enable row level security;
alter table public.organization_relationships enable row level security;
revoke all on public.organization_memberships,public.organization_identity_context,
 public.organization_membership_events,public.organization_invitations,public.organization_relationships from public,anon,authenticated;
grant select on public.organization_memberships,public.organization_membership_events,public.organization_relationships to authenticated;
grant all on public.organization_memberships,public.organization_identity_context,
 public.organization_membership_events,public.organization_invitations,public.organization_relationships to service_role;
create policy memberships_read on public.organization_memberships for select to authenticated
 using(profile_id=auth.uid() or public.organization_has_permission(organization_id,'team_admin'));
create policy membership_events_read on public.organization_membership_events for select to authenticated
 using(public.organization_has_permission(organization_id,'team_admin'));
create policy organization_relationships_read on public.organization_relationships for select to authenticated
 using(public.organization_has_permission(provider_organization_id,'member') or public.organization_has_permission(client_organization_id,'member'));
create policy membership_org_read on public.client_orgs for select to authenticated
 using(public.organization_has_permission(id,'member'));

-- Identity is not an authorization editor. Keep legacy provider administration,
-- while pending/modern members can edit only ordinary personal profile fields.
alter table public.profiles enable row level security;
revoke all on public.profiles from anon;
create policy identity_update on public.profiles for update to authenticated
 using(id=auth.uid() or public.get_my_role()='owner') with check(id=auth.uid() or public.get_my_role()='owner');
create function public.guard_profile_authority() returns trigger
language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') and old.role='member' and old.id<>auth.uid()
 then raise exception 'Use organization membership administration'; end if;
 if current_user in ('authenticated','anon') and (public.get_my_role() is distinct from 'owner' or old.role='member')
 and (new.id is distinct from old.id or new.role is distinct from old.role or new.org_id is distinct from old.org_id
 or new.subscription_tier is distinct from old.subscription_tier or new.billable_rate is distinct from old.billable_rate
 or new.email is distinct from old.email or new.org_code_used is distinct from old.org_code_used)
 then raise exception 'Organization authority must be changed through membership administration'; end if;
 return new;
end $$;
create trigger profiles_authority_guard before update on public.profiles for each row execute function public.guard_profile_authority();
create function public.identity_visible_to_legacy_provider(p_profile uuid) returns boolean language sql stable security definer set search_path='' as $$
 select p_profile=auth.uid() or public.get_my_role() not in ('owner','employee')
 or exists(select 1 from public.legacy_provider_identities where profile_id=p_profile)
$$;
create policy modern_identity_privacy on public.profiles as restrictive for select to authenticated
 using(role<>'member' or public.identity_visible_to_legacy_provider(id));

create function public.organization_context() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('active_organization_id',public.active_organization_id(),
 'onboarding_required',p.role='member' and public.active_organization_id() is null,
 'memberships',coalesce((select jsonb_agg(jsonb_build_object('organization_id',m.organization_id,'name',o.name,
 'owner_profile_id',o.owner_profile_id,'roles',m.roles,'permissions',m.permissions,'status',m.status)
 order by o.name) from public.organization_memberships m join public.client_orgs o on o.id=m.organization_id
 where m.profile_id=p.id and m.status='active'),'[]'::jsonb),
 'route_role',case when p.role<>'member' then p.role
 when m.roles && array['company_owner','supervisor'] then 'client_admin'
 when 'mechanic'=any(m.roles) then 'client_mechanic' else 'operator' end,
 'roles',coalesce(to_jsonb(m.roles),'[]'), 'permissions',coalesce(to_jsonb(m.permissions),'[]'))
 from public.profiles p left join public.organization_memberships m on m.profile_id=p.id
 and m.organization_id=public.active_organization_id() and m.status='active' where p.id=auth.uid()
$$;

create function public.set_active_organization(p_organization_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not public.organization_has_permission(p_organization_id,'member') then raise exception 'Organization access denied'; end if;
 insert into public.organization_identity_context values(auth.uid(),p_organization_id)
 on conflict(profile_id) do update set active_organization_id=excluded.active_organization_id;
 -- The legacy field is a transport for existing asset queries, never authority
 -- for modern members. Updating it also keeps older clients in the same scope.
 update public.profiles set org_id=p_organization_id,updated_at=now() where id=auth.uid() and role='member';
 return public.organization_context();
end $$;

create function public.create_company_workspace(p_name text,p_full_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_org uuid; v_actor uuid:=auth.uid();
begin
 if v_actor is null then raise exception 'Sign in first'; end if;
 perform 1 from public.profiles where id=v_actor for update;
 if not exists(select 1 from auth.users where id=v_actor and (email_confirmed_at is not null or phone_confirmed_at is not null))
 then raise exception 'Verify your email or phone first'; end if;
 if length(btrim(p_name)) not between 2 and 120 or length(btrim(p_full_name)) not between 1 and 120
 then raise exception 'Enter your name and company name'; end if;
 if exists(select 1 from public.organization_memberships where profile_id=v_actor and status='active')
 then raise exception 'An organization is already available'; end if;
 if not exists(select 1 from public.profiles where id=v_actor and role='member')
 then raise exception 'Existing accounts keep their current organization'; end if;
 -- Assets still use the owning profile as their stable tenant key. One owned
 -- organization per identity avoids ambiguous historic asset tenancy.
 if exists(select 1 from public.client_orgs where owner_profile_id=v_actor) then raise exception 'Company already exists'; end if;
 insert into public.client_orgs(name,owner_profile_id) values(btrim(p_name),v_actor) returning id into v_org;
 insert into public.organization_memberships(organization_id,profile_id,roles,created_by)
 values(v_org,v_actor,array['company_owner'],v_actor);
 update public.profiles set full_name=btrim(p_full_name),org_id=v_org,updated_at=now() where id=v_actor;
 perform public.set_active_organization(v_org);
 insert into public.organization_membership_events(organization_id,actor_id,subject_id,action)
 values(v_org,v_actor,v_actor,'company_created');
 return v_org;
end $$;

create function public.organization_team(p_organization_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.organization_has_permission(p_organization_id,'team_admin') then raise exception 'Team administration required'; end if;
 return jsonb_build_object('members',coalesce((select jsonb_agg(jsonb_build_object('profile_id',m.profile_id,
 'name',p.full_name,'email',p.email,'roles',m.roles,'permissions',m.permissions,'status',m.status) order by p.full_name)
 from public.organization_memberships m join public.profiles p on p.id=m.profile_id where m.organization_id=p_organization_id),'[]'),
 'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'roles',i.roles,'permissions',i.permissions,'contact',i.contact,
 'expires_at',i.expires_at,'redeemed_at',i.redeemed_at,'revoked_at',i.revoked_at) order by i.created_at desc)
 from public.organization_invitations i where i.organization_id=p_organization_id),'[]'));
end $$;

create function public.create_membership_invite(p_organization_id uuid,p_roles text[],p_permissions text[] default '{}',p_contact text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_token text:=upper(replace(gen_random_uuid()::text,'-','')); v_id uuid;
begin
 perform 1 from public.client_orgs where id=p_organization_id for update;
 if not public.organization_has_permission(p_organization_id,'team_admin') then raise exception 'Team administration required'; end if;
 if (p_roles && array['company_owner'] or cardinality(p_permissions)>0)
 and not exists(select 1 from public.organization_memberships where organization_id=p_organization_id and profile_id=auth.uid()
 and status='active' and 'company_owner'=any(roles)) then raise exception 'Only a Company Owner can delegate permissions or owner access'; end if;
 insert into public.organization_invitations(organization_id,token_hash,roles,permissions,contact,expires_at,created_by)
 values(p_organization_id,encode(extensions.digest(v_token,'sha256'),'hex'),p_roles,p_permissions,
 nullif(lower(btrim(p_contact)),''),now()+interval '7 days',auth.uid()) returning id into v_id;
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(p_organization_id,auth.uid(),'invitation_created',jsonb_build_object('invitation_id',v_id,'roles',p_roles,'permissions',p_permissions));
 return jsonb_build_object('id',v_id,'code',v_token,'expires_at',now()+interval '7 days');
end $$;

create function public.revoke_membership_invite(p_invitation_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_org uuid;
begin
 select organization_id into v_org from public.organization_invitations where id=p_invitation_id for update;
 if not public.organization_has_permission(v_org,'team_admin') then raise exception 'Team administration required'; end if;
 update public.organization_invitations set revoked_at=now() where id=p_invitation_id and redeemed_at is null;
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(v_org,auth.uid(),'invitation_revoked',jsonb_build_object('invitation_id',p_invitation_id));
end $$;

create function public.redeem_membership_invite(p_code text,p_full_name text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_invite public.organization_invitations; v_user auth.users; v_old public.organization_memberships;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 select * into v_user from auth.users where id=auth.uid();
 if v_user.email_confirmed_at is null and v_user.phone_confirmed_at is null then raise exception 'Verify your email or phone first'; end if;
 select * into v_invite from public.organization_invitations
 where token_hash=encode(extensions.digest(upper(btrim(p_code)),'sha256'),'hex') for update;
 if not found then raise exception 'Invitation not found'; end if;
 if v_invite.redeemed_by=auth.uid() then
 if public.organization_has_permission(v_invite.organization_id,'member') then return v_invite.organization_id; end if;
 raise exception 'Invitation already used';
 end if;
 if v_invite.revoked_at is not null then raise exception 'Invitation revoked'; end if;
 if v_invite.expires_at<=now() then raise exception 'Invitation expired'; end if;
 if v_invite.redeemed_at is not null then raise exception 'Invitation already used'; end if;
 if not public.organization_has_permission(v_invite.organization_id,'team_admin',v_invite.created_by)
 then raise exception 'Inviter no longer has team access'; end if;
 if (v_invite.roles && array['company_owner'] or cardinality(v_invite.permissions)>0) and not exists(
 select 1 from public.organization_memberships where organization_id=v_invite.organization_id
 and profile_id=v_invite.created_by and status='active' and 'company_owner'=any(roles))
 then raise exception 'Inviter can no longer delegate these permissions'; end if;
 if v_invite.contact is not null and not (
 (v_user.email_confirmed_at is not null and lower(v_user.email)=v_invite.contact)
 or (v_user.phone_confirmed_at is not null and v_invite.contact !~ '@'
 and regexp_replace(v_user.phone,'[^0-9]','','g')=regexp_replace(v_invite.contact,'[^0-9]','','g')))
 then raise exception 'Use the email or phone named in this invitation'; end if;
 -- Re-inviting an active member never silently replaces their roles.
 select * into v_old from public.organization_memberships where organization_id=v_invite.organization_id and profile_id=auth.uid() for update;
 if found and v_old.status='active' then raise exception 'You already belong to this company'; end if;
 if exists(select 1 from public.profiles where id=auth.uid() and role in ('owner','employee'))
 then raise exception 'Legacy provider accounts cannot be converted through an invitation'; end if;
 insert into public.organization_memberships(organization_id,profile_id,roles,permissions,created_by)
 values(v_invite.organization_id,auth.uid(),v_invite.roles,v_invite.permissions,v_invite.created_by)
 on conflict(organization_id,profile_id) do update set roles=excluded.roles,permissions=excluded.permissions,status='active',updated_at=now();
 update public.profiles set role='member',full_name=coalesce(nullif(btrim(p_full_name),''),full_name),updated_at=now() where id=auth.uid();
 update public.organization_invitations set redeemed_by=auth.uid(),redeemed_at=now() where id=v_invite.id;
 perform public.set_active_organization(v_invite.organization_id);
 insert into public.organization_membership_events(organization_id,actor_id,subject_id,action,detail)
 values(v_invite.organization_id,auth.uid(),auth.uid(),'invitation_redeemed',jsonb_build_object('invitation_id',v_invite.id));
 return v_invite.organization_id;
end $$;

create function public.update_organization_membership(p_organization_id uuid,p_profile_id uuid,p_roles text[],p_permissions text[],p_status text default 'active')
returns void language plpgsql security definer set search_path='' as $$
declare v_old public.organization_memberships; v_owner boolean;
begin
 -- Serialize all owner-count decisions in the same organization.
 perform 1 from public.client_orgs where id=p_organization_id for update;
 if not public.organization_has_permission(p_organization_id,'team_admin') then raise exception 'Team administration required'; end if;
 select exists(select 1 from public.organization_memberships where organization_id=p_organization_id and profile_id=auth.uid()
 and status='active' and 'company_owner'=any(roles)) into v_owner;
 select * into v_old from public.organization_memberships where organization_id=p_organization_id and profile_id=p_profile_id for update;
 if not found then raise exception 'Member not found'; end if;
 if not v_owner and ('company_owner'=any(v_old.roles) or 'company_owner'=any(p_roles) or v_old.permissions<>p_permissions)
 then raise exception 'Only a Company Owner can delegate permissions or change an owner'; end if;
 if 'company_owner'=any(v_old.roles) and v_old.status='active' and (p_status<>'active' or not 'company_owner'=any(p_roles))
 and not exists(select 1 from public.organization_memberships where organization_id=p_organization_id and profile_id<>p_profile_id
 and status='active' and 'company_owner'=any(roles)) then raise exception 'Keep at least one active Company Owner'; end if;
 update public.organization_memberships set roles=p_roles,permissions=p_permissions,status=p_status,updated_at=now()
 where organization_id=p_organization_id and profile_id=p_profile_id;
 -- Once explicitly edited, the membership is the sole authority. Keeping a
 -- legacy client_admin role here would bypass later revocation/delegation.
 update public.profiles set role='member',updated_at=now() where id=p_profile_id
 and role not in ('owner','employee');
 if p_status='revoked' then
 update public.organization_identity_context set active_organization_id=null where profile_id=p_profile_id and active_organization_id=p_organization_id;
 update public.profiles set org_id=null where id=p_profile_id and org_id=p_organization_id and role='member';
 end if;
 insert into public.organization_membership_events(organization_id,actor_id,subject_id,action,detail)
 values(p_organization_id,auth.uid(),p_profile_id,'membership_updated',jsonb_build_object('before',to_jsonb(v_old),
 'roles',p_roles,'permissions',p_permissions,'status',p_status));
end $$;

create function public.set_organization_relationship(p_provider uuid,p_client uuid,p_action text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if p_action='propose' then
 if not public.organization_has_permission(p_provider,'team_admin') then raise exception 'Provider team administration required'; end if;
 insert into public.organization_relationships(provider_organization_id,client_organization_id,proposed_by)
 values(p_provider,p_client,auth.uid()) on conflict(provider_organization_id,client_organization_id)
 do update set status='proposed',proposed_by=auth.uid(),accepted_by=null,updated_at=now()
 where organization_relationships.status='revoked' returning id into v_id;
 elsif p_action='accept' then
 if not public.organization_has_permission(p_client,'team_admin') then raise exception 'Client team administration required'; end if;
 update public.organization_relationships set status='active',accepted_by=auth.uid(),updated_at=now()
 where provider_organization_id=p_provider and client_organization_id=p_client and status='proposed' returning id into v_id;
 elsif p_action='revoke' then
 if not(public.organization_has_permission(p_client,'team_admin') or public.organization_has_permission(p_provider,'team_admin'))
 then raise exception 'Team administration required'; end if;
 update public.organization_relationships set status='revoked',updated_at=now()
 where provider_organization_id=p_provider and client_organization_id=p_client returning id into v_id;
 else raise exception 'Invalid relationship action'; end if;
 if v_id is null then raise exception 'Relationship is not available for this action'; end if;
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(case when p_action='accept' then p_client else p_provider end,auth.uid(),'relationship_'||p_action,
 jsonb_build_object('relationship_id',v_id));
 return v_id;
end $$;

-- Modern membership branch; unchanged legacy behavior is kept explicitly.
create or replace function public.maintenance_can_view_asset(p_asset_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.assets a join public.profiles p on p.id=auth.uid() where a.id=p_asset_id and (
 (p.role='member' and public.organization_asset_permission(a.id,'member'))
 or (p.role in ('owner','employee') and exists(select 1 from public.legacy_provider_tenants t where t.client_id=a.client_id))
 or (p.role in ('client','client_admin') and p.org_id is null and a.client_id=p.id)
 or (p.role in ('client','client_admin','client_mechanic','operator','client_operator') and exists(
 select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=a.client_id))))
$$;
create or replace function public.maintenance_can_manage_asset(p_asset_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.maintenance_can_view_asset(p_asset_id) and exists(select 1 from public.profiles p where p.id=auth.uid() and
 (p.role in ('owner','client','client_admin') or (p.role='member' and public.organization_asset_permission(p_asset_id,'assets_manage'))))
$$;
create policy organization_assets_read on public.assets for select to authenticated using(public.organization_asset_permission(id,'member'));
create policy organization_assets_insert on public.assets for insert to authenticated with check(exists(
 select 1 from public.client_orgs o where o.id=public.active_organization_id() and o.owner_profile_id=client_id
 and public.organization_has_permission(o.id,'assets_manage')));
create policy organization_assets_update on public.assets for update to authenticated
 using(public.organization_asset_permission(id,'assets_manage')) with check(public.organization_asset_permission(id,'assets_manage'));
create policy modern_asset_read_boundary on public.assets as restrictive for select to authenticated
 using(public.get_my_role()<>'member' or public.organization_asset_permission(id,'member'));
create policy modern_asset_insert_boundary on public.assets as restrictive for insert to authenticated
 with check(public.get_my_role()<>'member' or exists(select 1 from public.client_orgs o where o.id=public.active_organization_id()
 and o.owner_profile_id=client_id and public.organization_has_permission(o.id,'assets_manage')));
create policy modern_asset_update_boundary on public.assets as restrictive for update to authenticated
 using(public.get_my_role()<>'member' or public.organization_asset_permission(id,'assets_manage'))
 with check(public.get_my_role()<>'member' or public.organization_asset_permission(id,'assets_manage'));

create or replace function public.maintenance_execution_enabled(p_asset uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.maintenance_can_view_asset(p_asset) and exists(select 1 from public.profiles p where p.id=auth.uid()
 and (p.role in ('owner','employee') or ((p.role in ('client','client_admin','client_mechanic')
 or (p.role='member' and public.organization_asset_permission(p_asset,'work_assigned'))) and exists(
 select 1 from public.client_capabilities c join public.assets a on a.client_id=c.client_id
 where a.id=p_asset and c.capability_key='pm_checklists' and c.enabled))))
$$;
create or replace function public.maintenance_can_read_job(p_job uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w join public.profiles p on p.id=auth.uid()
 where w.id=p_job and w.managed_maintenance and public.maintenance_can_view_asset(w.asset_id) and (
 p.role in ('owner','client','client_admin')
 or (p.role='member' and public.organization_asset_permission(w.asset_id,'review_work'))
 or ((p.role in ('employee','client_mechanic') or (p.role='member' and public.organization_asset_permission(w.asset_id,'work_assigned')))
 and (w.assigned_to=p.id or exists(select 1 from public.work_order_assignments x where x.work_order_id=w.id and x.profile_id=p.id)))))
$$;
create or replace function public.maintenance_can_plan(p_asset uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.maintenance_can_manage_asset(p_asset) and exists(select 1 from public.profiles p where p.id=auth.uid()
 and (p.role='owner' or ((p.role<>'member' or public.organization_asset_permission(p_asset,'planning')) and exists(
 select 1 from public.client_capabilities c join public.assets a on a.client_id=c.client_id where a.id=p_asset
 and c.capability_key='maintenance_planning' and c.enabled))))
$$;
create or replace function public.operations_can_submit(p_asset uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.maintenance_can_view_asset(p_asset) and exists(select 1 from public.profiles p where p.id=auth.uid()
 and (p.role in ('owner','employee') or ((p.role<>'member' or public.organization_asset_permission(p_asset,'preop')) and exists(
 select 1 from public.assets a join public.client_capabilities c on c.client_id=a.client_id
 where a.id=p_asset and c.capability_key='operational_checklists' and c.enabled))))
$$;
create or replace function public.maintenance_validate_assignee(p_asset uuid,p_assignee uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_assignee is null then return; end if;
 if not exists(select 1 from public.profiles p join public.assets a on a.id=p_asset where p.id=p_assignee and (
 p.role in ('owner','employee') or (p.role='member' and public.organization_has_permission(public.organization_for_asset(a.id),'work_assigned',p.id))
 or (p.role in ('client','client_admin','client_mechanic') and (p.id=a.client_id or exists(select 1 from public.client_orgs o
 where o.id=p.org_id and o.owner_profile_id=a.client_id))))) then raise exception 'Invalid assignee'; end if;
 if public.get_my_role()<>'owner' and exists(select 1 from public.profiles where id=p_assignee and role in ('owner','employee'))
 then raise exception 'Invalid assignee'; end if;
end $$;
create function public.inspection_can_manage(p_asset uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select case when public.get_my_role()='member' then public.organization_asset_permission(p_asset,'inspection_manage')
 else public.maintenance_can_manage_asset(p_asset) end
$$;
create or replace function public.inspection_can_submit(p_asset uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select public.maintenance_can_view_asset(p_asset) and exists(select 1 from public.profiles p where p.id=auth.uid() and (
 p.role in ('owner','employee','client','client_admin','client_mechanic') or
 (p.role='member' and (public.organization_asset_permission(p_asset,'work_assigned') or public.organization_asset_permission(p_asset,'inspection_manage')))))
$$;
create or replace function public.checklist_company() returns uuid language sql stable security definer set search_path='' as $$
 select case when p.role in ('owner','employee') then null when p.role='member' then
 (select o.owner_profile_id from public.client_orgs o where o.id=public.active_organization_id())
 else coalesce((select o.owner_profile_id from public.client_orgs o where o.id=p.org_id),p.id) end
 from public.profiles p where p.id=auth.uid()
$$;
create or replace function public.agent_can_manage_fleet(p_client uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=auth.uid()
 and coalesce((to_jsonb(u)->>'banned_until')::timestamptz<=now(),true) and (
 p.role='owner' or (p.role='member' and public.organization_has_permission(public.active_organization_id(),'assets_manage')
 and p_client=public.checklist_company()) or (p.role in ('client','client_admin') and
 ((p.org_id is null and p.id=p_client) or exists(select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=p_client)))))
$$;
create or replace function public.checklist_can_author(p_client uuid,p_kind text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and (p.role='owner' or
 ((p.role in ('client','client_admin') or (p.role='member' and public.organization_has_permission(public.active_organization_id(),'planning')))
 and p_client=public.checklist_company() and exists(select 1 from public.client_capabilities c where c.client_id=p_client and c.enabled
 and c.capability_key=case p_kind when 'operator_daily' then 'operational_checklists' else 'pm_checklists' end))))
$$;

-- Preserve the reviewed bodies, replacing only permission predicates. Fail
-- loudly on schema drift so these adaptations cannot silently stop applying.
do $$ declare body text; updated text; sig regprocedure; begin
 sig:='public.save_maintenance_setup(uuid,text,uuid,integer,jsonb)'::regprocedure;
 body:=pg_get_functiondef(sig);
 updated:=replace(body,$old$me.role not in ('owner','client','client_admin')$old$,
 $new$(me.role not in ('owner','client','client_admin') and not (me.role='member' and public.organization_has_permission(public.active_organization_id(),'assets_manage')))$new$);
 if updated=body then raise exception 'save_maintenance_setup membership adaptation did not match'; end if;
 execute updated;
 foreach sig in array array['public.create_asset_inspection(uuid,uuid,jsonb)'::regprocedure,
 'public.change_asset_inspection(uuid,integer,uuid,text,jsonb)'::regprocedure,
 coalesce(to_regprocedure('public.inspection_register_before_work(uuid)'), 'public.inspection_register(uuid)'::regprocedure)] loop
 body:=pg_get_functiondef(sig); updated:=replace(body,'public.maintenance_can_manage_asset(', 'public.inspection_can_manage(');
 if updated=body then raise exception 'Inspection permission adaptation did not match %',sig; end if;
 execute updated;
 end loop;
end $$;

-- Phone identities have no email address. A modern metadata flag selects only
-- the least-privileged pending membership, never an owner or organization.
-- Existing invitation/password onboarding continues through its prior branch.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_code text; v_invite public.org_codes; v_role text:='client'; v_org uuid; v_tier integer:=0; v_owner uuid; v_capability text;
begin
 if new.raw_user_meta_data->>'onboarding_v2'='true' then
 insert into public.profiles(id,email,phone,full_name,role,preferred_language)
 values(new.id,coalesce(new.email,''),new.phone,'','member',case when new.raw_user_meta_data->>'preferred_language'='es' then 'es' else 'en' end);
 return new;
 end if;
 v_code:=upper(nullif(btrim(new.raw_user_meta_data->>'org_code_used'),''));
 if v_code is not null then
 select * into v_invite from public.org_codes where code=v_code for update;
 if not found then raise exception 'invalidOrgCode'; end if;
 if v_invite.expires_at is not null and v_invite.expires_at<=now() then raise exception 'orgCodeExpired'; end if;
 if coalesce(v_invite.single_use,true) and coalesce(v_invite.use_count,0)>=coalesce(v_invite.max_uses,1) then raise exception 'orgCodeUsed'; end if;
 v_role:=coalesce(v_invite.intended_role,'client'); v_org:=v_invite.org_id;
 v_capability:=case when v_role='client_mechanic' then 'pm_checklists' when v_role in ('operator','client_operator') then 'operational_checklists' end;
 if v_capability is not null then
 select owner_profile_id into v_owner from public.client_orgs where id=v_org;
 if v_owner is null or not exists(select 1 from public.client_capabilities where client_id=v_owner and capability_key=v_capability and enabled)
 then raise exception 'Invite capability is not enabled'; end if;
 end if;
 else
 v_role:=coalesce(nullif(new.raw_app_meta_data->>'role',''),'client');
 v_org:=nullif(new.raw_app_meta_data->>'org_id','')::uuid;
 v_tier:=coalesce(nullif(new.raw_app_meta_data->>'subscription_tier','')::integer,0);
 end if;
 if v_role not in ('owner','employee','client','client_admin','client_mechanic','operator','client_operator') then raise exception 'Invalid assigned role'; end if;
 insert into public.profiles(id,email,phone,full_name,role,org_id,org_code_used,preferred_language,subscription_tier,created_at,updated_at)
 values(new.id,coalesce(new.email,''),new.phone,coalesce(nullif(new.raw_user_meta_data->>'full_name',''),new.email,''),v_role,v_org,v_code,
 case when new.raw_user_meta_data->>'preferred_language'='es' then 'es' else 'en' end,v_tier,now(),now());
 if v_code is not null then update public.org_codes set use_count=coalesce(use_count,0)+1 where id=v_invite.id; end if;
 return new;
end $$;

revoke all on function public.handle_new_user() from public,anon,authenticated;
revoke all on function public.register_legacy_provider_tenant() from public,anon,authenticated;
do $$ declare v record; begin
 for v in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
 and p.proname in ('organization_has_permission','active_organization_id','organization_for_asset','organization_asset_permission',
 'organization_context','set_active_organization','create_company_workspace','organization_team','create_membership_invite','identity_visible_to_legacy_provider',
 'revoke_membership_invite','redeem_membership_invite','update_organization_membership','set_organization_relationship') loop
 execute format('revoke all on function %s from public,anon',v.sig);
 execute format('grant execute on function %s to authenticated',v.sig);
 end loop;
end $$;
