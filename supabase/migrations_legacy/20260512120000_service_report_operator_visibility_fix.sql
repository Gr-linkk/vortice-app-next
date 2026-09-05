-- Service reports are visible to staff and selected client-facing roles.
-- Operators and client_operator roles must not see service reports or report photos.

alter table public.service_reports enable row level security;
alter table public.service_report_photos enable row level security;

drop policy if exists "Org members read associated service reports" on public.service_reports;
drop policy if exists "Org members read associated service report photos" on public.service_report_photos;

create policy "Org members read associated service reports"
  on public.service_reports
  for select
  using (
    exists (
      select 1
      from public.work_orders wo
      join public.assets a on a.id = wo.asset_id
      join public.client_orgs co on co.owner_profile_id = a.client_id
      join public.profiles p on p.org_id = co.id
      where wo.id = service_reports.work_order_id
        and p.id = auth.uid()
        and p.role in ('client_admin', 'client_mechanic')
    )
  );

create policy "Org members read associated service report photos"
  on public.service_report_photos
  for select
  using (
    exists (
      select 1
      from public.service_reports sr
      join public.work_orders wo on wo.id = sr.work_order_id
      join public.assets a on a.id = wo.asset_id
      join public.client_orgs co on co.owner_profile_id = a.client_id
      join public.profiles p on p.org_id = co.id
      where sr.id = service_report_photos.service_report_id
        and p.id = auth.uid()
        and p.role in ('client_admin', 'client_mechanic')
    )
  );
