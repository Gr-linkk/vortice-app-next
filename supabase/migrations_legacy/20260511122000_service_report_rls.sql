-- Service reports are client-visible vessel records, but only through
-- work orders for assets the current user can see. Report writing remains a
-- Vórtice staff workflow; clients get read-only access.

alter table public.service_reports enable row level security;
alter table public.service_report_photos enable row level security;

create index if not exists service_reports_work_order_id_idx
  on public.service_reports(work_order_id);

create index if not exists service_report_photos_service_report_id_idx
  on public.service_report_photos(service_report_id);

drop policy if exists "Staff read service reports" on public.service_reports;
drop policy if exists "Staff manage service reports" on public.service_reports;
drop policy if exists "Clients read own asset service reports" on public.service_reports;
drop policy if exists "Org members read associated service reports" on public.service_reports;
drop policy if exists "Service role full access service reports" on public.service_reports;

drop policy if exists "Staff read service report photos" on public.service_report_photos;
drop policy if exists "Staff manage service report photos" on public.service_report_photos;
drop policy if exists "Clients read own asset service report photos" on public.service_report_photos;
drop policy if exists "Org members read associated service report photos" on public.service_report_photos;
drop policy if exists "Service role full access service report photos" on public.service_report_photos;

create policy "Staff read service reports"
  on public.service_reports
  for select
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  );

create policy "Staff manage service reports"
  on public.service_reports
  for all
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  )
  with check (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  );

create policy "Clients read own asset service reports"
  on public.service_reports
  for select
  using (
    exists (
      select 1
      from public.work_orders wo
      join public.assets a on a.id = wo.asset_id
      where wo.id = service_reports.work_order_id
        and a.client_id = auth.uid()
    )
  );

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
        and p.role in ('client_admin', 'client_mechanic', 'operator', 'client_operator')
    )
  );

create policy "Service role full access service reports"
  on public.service_reports
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

create policy "Staff read service report photos"
  on public.service_report_photos
  for select
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  );

create policy "Staff manage service report photos"
  on public.service_report_photos
  for all
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  )
  with check (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  );

create policy "Clients read own asset service report photos"
  on public.service_report_photos
  for select
  using (
    exists (
      select 1
      from public.service_reports sr
      join public.work_orders wo on wo.id = sr.work_order_id
      join public.assets a on a.id = wo.asset_id
      where sr.id = service_report_photos.service_report_id
        and a.client_id = auth.uid()
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
        and p.role in ('client_admin', 'client_mechanic', 'operator', 'client_operator')
    )
  );

create policy "Service role full access service report photos"
  on public.service_report_photos
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');
