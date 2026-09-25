-- NEXT-011: customer invoicing belongs to a service provider, never an
-- own-equipment-only company. Keep existing invoice history readable.
create or replace function public.configure_organization_services(
 p_provider_enabled boolean,p_billing_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
declare org uuid:=public.active_organization_id(); purpose text;
begin
 if not exists(select 1 from public.organization_memberships where organization_id=org
  and profile_id=auth.uid() and status='active' and 'company_owner'=any(roles))
 then raise exception 'Company Owner required'; end if;
 select company_purpose into purpose from public.organization_service_settings
  where organization_id=org for update;
 if purpose='fleet' and p_provider_enabled then
  raise exception 'Choose Service provider or Both before enabling customer work';
 end if;
 if p_billing_enabled and (not p_provider_enabled or purpose='fleet') then
  raise exception 'Customer billing requires a service provider company';
 end if;
 update public.organization_service_settings set provider_enabled=p_provider_enabled,
  billing_enabled=p_billing_enabled,updated_at=now() where organization_id=org;
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(org,auth.uid(),'service_settings_changed',
  jsonb_build_object('provider_enabled',p_provider_enabled,'billing_enabled',p_billing_enabled));
end $$;

-- Changing a provider company to Fleet owner also retires its customer-billing
-- capability. Old issued invoices remain readable; they are not rewritten.
create or replace function public.keep_company_purpose_consistent() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.company_purpose is not distinct from old.company_purpose
  and new.provider_enabled is distinct from old.provider_enabled then
  new.company_purpose:=null;
 end if;
 if new.company_purpose='fleet' then
  new.billing_enabled:=false;
 end if;
 return new;
end $$;

create function public.guard_fleet_owner_invoice() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and (old.status<>'draft' or new.status<>'sent') then
  return new;
 end if;
 if exists(select 1 from public.work_orders w
  join public.organization_service_settings s on s.organization_id=w.provider_organization_id
  where w.id=new.work_order_id and s.company_purpose='fleet') then
  raise exception 'Customer billing requires a service provider company';
 end if;
 return new;
end $$;
create trigger invoice_fleet_owner_boundary before insert or update on public.invoices
for each row execute function public.guard_fleet_owner_invoice();
