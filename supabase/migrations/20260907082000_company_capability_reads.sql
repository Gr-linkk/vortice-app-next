-- Company staff must see the switches used by native workflow/navigation gates.
-- Mutation remains owner-only under the existing policies.
create policy "Company members can read their capabilities"
on public.client_capabilities for select to authenticated
using (client_id = public.checklist_company());
