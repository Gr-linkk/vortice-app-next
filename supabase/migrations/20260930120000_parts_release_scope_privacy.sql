-- ARCH-001 / NOW-022: automatic releases share the linked inventory's validated
-- owner scope. No historical events are rewritten; the projection below hides
-- stock-backed events whose recorded scope disagrees with their inventory.
create or replace function public.release_finished_job_parts()
returns trigger language plpgsql security definer set search_path='' as $$
declare r public.job_part_requirements; s public.parts_inventory; scope uuid;
begin
 if new.status is distinct from old.status and new.status in ('pending_review','closed','invoiced','cancelled') then
  -- Keep the existing requirement row lock and quantity rule. Status updates
  -- already lock the job; concurrent parts RPCs lock that same job before its
  -- requirements. Releases do not consume or modify physical inventory.
  for r in select * from public.job_part_requirements where work_order_id=new.id and reserved_qty>0 order by id for update loop
   -- Resolve ownership from the actual job, independently of the invoking actor.
   -- A customer client_id is not the stock owner of a modern provider job.
   if new.provider_organization_id is not null then
    select owner_profile_id into scope from public.client_orgs where id=new.provider_organization_id;
    if scope is null then raise exception 'Provider stock unavailable'; end if;
   elsif new.managed_maintenance then
    scope:=new.client_id;
    if scope is null then raise exception 'Company stock unavailable'; end if;
   else
    scope:=null;
   end if;
   select * into s from public.parts_inventory where id=r.stock_id;
   if s.id is null or s.client_id is distinct from scope then
    raise exception 'Reserved stock does not belong to this work' using errcode='23514';
   end if;
   update public.job_part_requirements set reserved_qty=0,revision=revision+1 where id=r.id;
   insert into public.parts_stock_events(id,actor_id,client_id,work_order_id,stock_id,action,payload)
   values(gen_random_uuid(),coalesce(auth.uid(),new.created_by),s.client_id,
    new.id,r.stock_id,'release',jsonb_build_object('quantity',r.reserved_qty,'note','Unused reservation released at work review or close'));
  end loop;
 end if;
 return new;
end $$;

-- The public currency wrapper continues to call this private implementation.
-- A stockless requirement event remains visible within its own recorded scope.
create or replace function public.parts_workspace_before_currency(p_job uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare scope uuid; manager boolean; w public.work_orders;
begin
 scope:=public.parts_scope(p_job);
 select * into w from public.work_orders where id=p_job;
 manager:=public.parts_scope_manager(p_job);
 return jsonb_build_object('can_manage',manager,'job_title',w.title,'job_status',w.status,
 'kit_captured',w.parts_kit_captured,'has_kit',w.checklist_template_id is not null,
 'can_change',p_job is null or (w.status not in ('closed','invoiced','cancelled','pending_review') and
 (case when w.provider_organization_id is not null then public.organization_provider_access(w.id,'work') else not w.managed_maintenance or public.maintenance_can_work_job(w.id) end)),
 'can_issue',w.status in ('in_progress','on_hold'),
 'stock',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('reserved',
 coalesce((select sum(r.reserved_qty) from public.job_part_requirements r where r.stock_id=s.id),0)) order by s.description,s.location)
 from public.parts_inventory s where s.client_id is not distinct from scope),'[]'),
 'requirements',coalesce((select jsonb_agg(to_jsonb(r) order by r.description,r.id) from public.job_part_requirements r where r.work_order_id=p_job),'[]'),
 'purchases',coalesce((select jsonb_agg(to_jsonb(o)||jsonb_build_object('description',r.description,'work_order_id',r.work_order_id) order by o.created_at desc)
 from public.parts_purchase_requests o join public.job_part_requirements r on r.id=o.requirement_id
 join public.parts_inventory s on s.id=o.stock_id where s.client_id is not distinct from scope
 and (p_job is null or r.work_order_id=p_job)),'[]'),
 'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from
 (select e.action,e.created_at,e.payload,p.full_name as actor_name,s.description,s.location
 from public.parts_stock_events e join public.profiles p on p.id=e.actor_id left join public.parts_inventory s on s.id=e.stock_id
 where e.client_id is not distinct from scope
 and (e.stock_id is null or (s.id is not null and s.client_id is not distinct from scope))
 and (p_job is null or e.work_order_id=p_job)
 order by e.created_at desc limit 100) e),'[]'));
end $$;

revoke all on function public.parts_workspace_before_currency(uuid) from public,anon,authenticated;
revoke all on function public.release_finished_job_parts() from public,anon,authenticated;
