-- Staff-created/internal work orders need the same checklist response access as
-- assigned profiles. Without this, internal PM checklist submits can save local
-- answers but fail the remote upsert under RLS before history/PM closeout runs.

drop policy if exists "Staff read WO checklist responses"
  on public.checklist_responses;
drop policy if exists "Staff insert WO checklist responses"
  on public.checklist_responses;
drop policy if exists "Staff update WO checklist responses"
  on public.checklist_responses;
drop policy if exists "Staff manage WO checklist responses"
  on public.checklist_responses;

create policy "Staff read WO checklist responses"
  on public.checklist_responses
  for select
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  );

create policy "Staff insert WO checklist responses"
  on public.checklist_responses
  for insert
  with check (
    completed_by = auth.uid()
    and exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  );

create policy "Staff update WO checklist responses"
  on public.checklist_responses
  for update
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  )
  with check (
    completed_by = auth.uid()
    and exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  );
