-- NEXT-002.14: preserve the established selected complete-kit snapshot.
-- Covered checklist tasks do not implicitly add smaller kits: the selected
-- kit already contains its complete requirements (NOW-023). The existing
-- capture_job_parts trigger is shared by manual and generated work.

-- Asset inspection readers may see a certificate without permission to open
-- its private execution record. Return a work link only to allowed readers.
create or replace function public.inspection_register(p_asset uuid default null) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(data||jsonb_build_object('open_work_order_id',(
  select w.id from public.work_orders w join public.maintenance_job_records j on j.id=w.id
  where j.inspection_id=(data->>'id')::uuid and w.status<>'closed' and public.maintenance_can_read_job(w.id)
  order by w.created_at desc,w.id limit 1))),'[]')
 from jsonb_array_elements(public.inspection_register_before_work(p_asset)) data
$$;
