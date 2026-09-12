-- Final coordination adapter after contextual/attached-checklist wrappers.
-- Provider orders share their selected record; partner fleet and private team
-- discussions stay isolated even from the legacy global provider accounts.
create function public.coordination_related_order(p_kind text,p_id uuid) returns uuid
language sql stable security definer set search_path='' as $$
 select id from public.work_orders where p_kind in ('job','inspection') and id=p_id
 union all select work_order_id from public.service_reports where p_kind='report' and id=p_id
 union all select generated_work_order_id from public.service_requests where p_kind='request' and id=p_id
 union all select work_order_id from public.saved_checklists where p_kind='checklist' and id=p_id
$$;
create function public.organization_work_person_access(p_order uuid,p_user uuid,p_side text default 'either') returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w join public.organization_relationships r on r.id=w.organization_relationship_id where w.id=p_order and (
 (p_side in ('either','provider') and r.status='active' and public.organization_has_permission(w.provider_organization_id,'member',p_user)
 and (p_user<>auth.uid() or w.provider_organization_id=public.active_organization_id()) and (
 public.organization_has_permission(w.provider_organization_id,'review_work',p_user) or public.organization_has_permission(w.provider_organization_id,'billing',p_user)
 or (public.organization_has_permission(w.provider_organization_id,'work_assigned',p_user) and (w.assigned_to=p_user or exists(
 select 1 from public.work_order_assignments x where x.work_order_id=w.id and x.profile_id=p_user)))))
 or (p_side in ('either','customer') and public.organization_has_permission(w.customer_organization_id,'member',p_user)
 and (p_user<>auth.uid() or w.customer_organization_id=public.active_organization_id()) and (
 public.organization_has_permission(w.customer_organization_id,'review_work',p_user) or w.created_by=p_user))))
$$;
create or replace function public.coordination_asset_viewer(p_asset uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.assets a join public.profiles p on p.id=p_user where a.id=p_asset and case
 when exists(select 1 from public.organization_memberships m where m.profile_id=p_user and m.organization_id=public.organization_for_asset(a.id))
 then public.organization_has_permission(public.organization_for_asset(a.id),'member',p_user)
 and (p_user<>auth.uid() or p.role<>'member' or public.organization_for_asset(a.id)=public.active_organization_id())
 when p.role='member' then false
 when p.role in ('owner','employee') then exists(select 1 from public.legacy_provider_tenants t where t.client_id=a.client_id)
 else (p.role in ('client','client_admin') and p.org_id is null and a.client_id=p.id)
 or (p.role in ('client','client_admin','client_mechanic','operator','client_operator') and exists(select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=a.client_id)) end)
$$;
alter function public.coordination_subject_reader(text,uuid,uuid) rename to coordination_subject_reader_before_org_provider;
create function public.coordination_subject_reader(p_kind text,p_id uuid,p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select case when public.is_organization_provider_work(public.coordination_related_order(p_kind,p_id)) then
 public.organization_work_person_access(public.coordination_related_order(p_kind,p_id),p_user) and (
 p_kind not in ('report','checklist') or public.organization_work_person_access(public.coordination_related_order(p_kind,p_id),p_user,'provider')
 or exists(select 1 from public.organization_work_report_state where work_order_id=public.coordination_related_order(p_kind,p_id) and approved_at is not null))
 else public.coordination_subject_reader_before_org_provider(p_kind,p_id,p_user) end
$$;
create function public.coordination_subject_team(p_kind text,p_id uuid,p_user uuid) returns text
language sql stable security definer set search_path='' as $$
 select case when public.is_organization_provider_work(public.coordination_related_order(p_kind,p_id)) then
 case when public.organization_work_person_access(public.coordination_related_order(p_kind,p_id),p_user,'provider') then 'provider' else 'company' end
 else public.coordination_user_team(p_user) end
$$;
alter function public.coordination_post_reader(uuid,uuid) rename to coordination_post_reader_before_org_provider;
create function public.coordination_post_reader(p_post uuid,p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.coordination_posts p join public.assets a on a.id=p.asset_id where p.id=p_post and p.client_id=a.client_id and
 case when public.is_organization_provider_work(public.coordination_related_order(p.subject_kind,p.subject_id)) then
 public.coordination_subject_reader(p.subject_kind,p.subject_id,p_user) and
 (p.visibility='shared' or p.team=public.coordination_subject_team(p.subject_kind,p.subject_id,p_user))
 else public.coordination_post_reader_before_org_provider(p_post,p_user) end)
$$;
-- These replacements change team selection only, preserving the established
-- attachment validation, mentions, replay ledger and pagination implementation.
do $$ declare sig regprocedure; definition text; updated text; begin
 foreach sig in array array['public.post_coordination_message(uuid,text,uuid,jsonb)'::regprocedure,
 'public.coordination_people(text,uuid,text)'::regprocedure,
 'public.coordination_thread(text,uuid,timestamptz,uuid,uuid)'::regprocedure] loop
 definition:=pg_get_functiondef(sig);
 updated:=replace(replace(replace(replace(definition,
 'public.coordination_user_team(actor.id)','public.coordination_subject_team(p_kind,p_id,actor.id)'),
 'public.coordination_user_team(auth.uid())','public.coordination_subject_team(p_kind,p_id,auth.uid())'),
 'public.coordination_user_team(p.id)','public.coordination_subject_team(p_kind,p_id,p.id)'),
 'public.coordination_user_team(recipient)','public.coordination_subject_team(p_kind,p_id,recipient)');
 if updated=definition then raise exception 'Coordination team adaptation did not match %',sig; end if;
 execute updated;
 end loop;
end $$;
revoke all on function public.coordination_related_order(text,uuid),public.organization_work_person_access(uuid,uuid,text),
 public.coordination_subject_team(text,uuid,uuid),public.coordination_subject_reader_before_org_provider(text,uuid,uuid),
 public.coordination_post_reader_before_org_provider(uuid,uuid),public.coordination_subject_reader(text,uuid,uuid),public.coordination_post_reader(uuid,uuid)
 from public,anon,authenticated;
