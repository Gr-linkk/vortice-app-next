-- Shared work-order checklist v1.
-- Owner/employee still creates and manages the WO. Assigned client mechanics can
-- see only their assigned WO and contribute to its checklist responses.

-- The first push attempt may have created this before hitting an optional-table
-- policy later in the file, so keep this migration rerunnable until recorded.
drop policy if exists "Assigned profiles can view assigned work orders"
  on public.work_orders;

create policy "Assigned profiles can view assigned work orders"
  on public.work_orders
  for select
  using (
    exists (
      select 1
      from public.work_order_assignments woa
      where woa.work_order_id = work_orders.id
        and woa.profile_id = auth.uid()
    )
  );

-- Snapshot table exists in newer local migration sets but not every live DB yet.
-- Add policy only when the table is present; checklist screen can still fall
-- back to live templates/items without snapshots.
do $$
begin
  if to_regclass('public.work_order_checklist_snapshots') is not null then
    drop policy if exists "Assigned profiles can view WO checklist snapshots"
      on public.work_order_checklist_snapshots;

    create policy "Assigned profiles can view WO checklist snapshots"
      on public.work_order_checklist_snapshots
      for select
      using (
        exists (
          select 1
          from public.work_order_assignments woa
          where woa.work_order_id = work_order_checklist_snapshots.work_order_id
            and woa.profile_id = auth.uid()
        )
      );
  end if;
end $$;

drop policy if exists "Assigned profiles can view WO checklist responses"
  on public.checklist_responses;
drop policy if exists "Assigned profiles can insert WO checklist responses"
  on public.checklist_responses;
drop policy if exists "Assigned profiles can update WO checklist responses"
  on public.checklist_responses;

create policy "Assigned profiles can view WO checklist responses"
  on public.checklist_responses
  for select
  using (
    exists (
      select 1
      from public.work_order_assignments woa
      where woa.work_order_id = checklist_responses.work_order_id
        and woa.profile_id = auth.uid()
    )
  );

create policy "Assigned profiles can insert WO checklist responses"
  on public.checklist_responses
  for insert
  with check (
    completed_by = auth.uid()
    and exists (
      select 1
      from public.work_order_assignments woa
      where woa.work_order_id = checklist_responses.work_order_id
        and woa.profile_id = auth.uid()
    )
  );

create policy "Assigned profiles can update WO checklist responses"
  on public.checklist_responses
  for update
  using (
    exists (
      select 1
      from public.work_order_assignments woa
      where woa.work_order_id = checklist_responses.work_order_id
        and woa.profile_id = auth.uid()
    )
  )
  with check (
    completed_by = auth.uid()
    and exists (
      select 1
      from public.work_order_assignments woa
      where woa.work_order_id = checklist_responses.work_order_id
        and woa.profile_id = auth.uid()
    )
  );
