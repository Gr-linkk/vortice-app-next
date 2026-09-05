-- ============================================================
-- Service Requests MVP
-- Created: 2026-05-07
-- Purpose: Always-on client portal request inbox for Vórtice service.
--
-- Product intent:
-- - Clients/client admins can ask Vórtice for service.
-- - Field/operator flags do not automatically become Vórtice inbox items.
-- - Owner/employee staff triage requests; work-order generation is deferred.
-- ============================================================

create table if not exists public.service_requests (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(id) on delete cascade,
  asset_id uuid references public.assets(id) on delete set null,
  title text not null check (length(trim(title)) > 0),
  description text not null check (length(trim(description)) > 0),
  urgency text not null default 'normal' check (urgency in ('normal', 'urgent')),
  status text not null default 'new' check (status in ('new', 'resolved', 'declined')),
  source_maintenance_request_id uuid references public.maintenance_requests(id) on delete set null,
  generated_work_order_id uuid references public.work_orders(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  handled_at timestamptz,
  handled_by uuid references public.profiles(id) on delete set null,
  constraint service_requests_handled_status_check check (
    (status = 'new' and handled_at is null and handled_by is null)
    or (status in ('resolved', 'declined'))
  )
);

comment on table public.service_requests is
  'Always-on client/admin requests for Vórtice service. Staff triage these before creating work orders.';
comment on column public.service_requests.status is
  'Client labels: new=Sent, resolved=Being handled, declined=Declined.';
comment on column public.service_requests.urgency is
  'Visual treatment only for MVP; no notification or escalation behavior.';
comment on column public.service_requests.generated_work_order_id is
  'Reserved for later explicit staff-generated work orders; not automatic.';

create index if not exists service_requests_client_created_idx
  on public.service_requests(client_id, created_at desc);
create index if not exists service_requests_status_created_idx
  on public.service_requests(status, created_at desc);
create index if not exists service_requests_asset_id_idx
  on public.service_requests(asset_id)
  where asset_id is not null;

create or replace function public.set_service_requests_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_service_requests_updated_at
  on public.service_requests;

create trigger trg_service_requests_updated_at
  before update on public.service_requests
  for each row
  execute function public.set_service_requests_updated_at();

alter table public.service_requests enable row level security;

-- Staff can see and manage the triage inbox.
create policy "Staff can read service requests"
  on public.service_requests for select
  using (public.get_my_role() in ('owner', 'employee'));

create policy "Staff can manage service requests"
  on public.service_requests for all
  using (public.get_my_role() in ('owner', 'employee'))
  with check (public.get_my_role() in ('owner', 'employee'));

-- Client owners can submit and read their own requests.
create policy "Clients can read own service requests"
  on public.service_requests for select
  using (client_id = auth.uid());

create policy "Clients can submit own service requests"
  on public.service_requests for insert
  with check (
    client_id = auth.uid()
    and status = 'new'
    and generated_work_order_id is null
    and handled_at is null
    and handled_by is null
    and (
      asset_id is null
      or exists (
        select 1 from public.assets a
        where a.id = asset_id and a.client_id = auth.uid()
      )
    )
  );

-- Client admins can submit/read for their org owner profile. Operators/mechanics
-- are intentionally excluded from direct service request creation in this MVP.
create policy "Client admins can read org service requests"
  on public.service_requests for select
  using (
    exists (
      select 1
      from public.client_orgs co
      join public.profiles p on p.org_id = co.id
      where p.id = auth.uid()
        and p.role = 'client_admin'
        and co.owner_profile_id = service_requests.client_id
    )
  );

create policy "Client admins can submit org service requests"
  on public.service_requests for insert
  with check (
    status = 'new'
    and generated_work_order_id is null
    and handled_at is null
    and handled_by is null
    and exists (
      select 1
      from public.client_orgs co
      join public.profiles p on p.org_id = co.id
      where p.id = auth.uid()
        and p.role = 'client_admin'
        and co.owner_profile_id = service_requests.client_id
    )
    and (
      asset_id is null
      or exists (
        select 1 from public.assets a
        where a.id = asset_id and a.client_id = service_requests.client_id
      )
    )
  );

create policy "Service role full access service requests"
  on public.service_requests for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');
