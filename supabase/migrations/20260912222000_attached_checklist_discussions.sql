-- Attached checklist failures keep their fault discussion visible in the originating work.
create or replace function public.coordination_context_matches(p_post uuid,p_kind text,p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.coordination_posts p where p.id=p_post and (
  (p.subject_kind=p_kind and p.subject_id=p_id)
  or (p_kind='asset' and p.asset_id=p_id)
  or (p_kind='fault' and exists(select 1 from public.checklist_issue_context c where c.post_id=p.id and c.fault_id=p_id))
  or (p_kind='checklist' and p.subject_kind='fault' and exists(select 1 from public.checklist_findings c where c.run_id=p_id and c.fault_id=p.subject_id))
  or (p_kind='checklist' and p.subject_kind='job' and exists(select 1 from public.checklist_findings c join public.maintenance_requests f on f.id=c.fault_id where c.run_id=p_id and f.converted_to_work_order_id=p.subject_id))
  or (p_kind in ('job','inspection') and (
   (p.subject_kind in ('job','inspection') and p.subject_id=p_id)
   or (p.subject_kind='fault' and exists(select 1 from public.work_checklist_faults c where c.work_order_id=p_id and c.fault_id=p.subject_id))
   or (p.subject_kind='fault' and exists(select 1 from public.maintenance_requests f where f.id=p.subject_id and f.converted_to_work_order_id=p_id))
   or (p.subject_kind='checklist' and exists(select 1 from public.checklist_issue_context c join public.maintenance_requests f on f.id=c.fault_id where c.post_id=p.id and f.converted_to_work_order_id=p_id))
   or (p.subject_kind='report' and exists(select 1 from public.service_reports r where r.id=p.subject_id and r.work_order_id=p_id))
   or (p.subject_kind='request' and exists(select 1 from public.service_requests r where r.id=p.subject_id and r.generated_work_order_id=p_id))
  ))
 ))
$$;
