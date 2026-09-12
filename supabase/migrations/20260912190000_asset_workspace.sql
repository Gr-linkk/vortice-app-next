-- Home and Assets share one authorized set of equipment, counted once per filter.
create or replace function public.asset_workspace(p_today date default current_date)
returns jsonb language sql stable security definer set search_path='' as $$
 with visible as materialized (
   select a.id,a.name,a.location from public.assets a where public.coordination_asset_viewer(a.id,auth.uid())
 ), attention as materialized (
   select r.* from public.fleet_attention_rows(p_today) r join visible a on a.id=r.asset_id
 ), inspections as materialized (
   select i from jsonb_array_elements(public.inspection_register(null)) i
 ), flags as (
   select r.asset_id,r.category from attention r
   union
   select (i->>'asset_id')::uuid,'inspection_expired' from inspections
    where i->'approved' is not null and i->'approved'<>'null'::jsonb and (i->'approved'->>'expires_on')::date<p_today
   union
   select (i->>'asset_id')::uuid,'inspection_upcoming' from inspections
    where (i->'approved'->>'expires_on')::date between p_today and p_today+30
   union
   select (i->>'asset_id')::uuid,'inspection_pending' from inspections
    where i->'pending' is not null and i->'pending'<>'null'::jsonb
   union
   select (i->>'asset_id')::uuid,'inspection_unverified' from inspections
    where i->'approved' is null or i->'approved'='null'::jsonb
 ), rows as (
   select a.id,a.name,a.location,
    coalesce((select jsonb_agg(f.category order by f.category) from flags f where f.asset_id=a.id),'[]') categories,
    coalesce((select jsonb_agg(to_jsonb(r) order by r.rank,r.due_date nulls last,r.id) from attention r where r.asset_id=a.id),'[]') attention,
    coalesce((select jsonb_agg(i) from inspections where (i->>'asset_id')::uuid=a.id),'[]') inspections,
    (select count(*) from public.work_orders w where w.asset_id=a.id and w.status not in ('closed','invoiced') and public.maintenance_can_read_job(w.id)) open_work,
    (select count(*) from public.maintenance_requests f where f.asset_id=a.id and f.status not in ('resolved','dismissed') and public.coordination_subject_reader('fault',f.id,auth.uid())) open_faults
   from visible a
 ) select jsonb_build_object('generated_at',now(),'today',p_today,
   'items',coalesce((select jsonb_agg(to_jsonb(r) order by r.name,r.id) from rows r),'[]'),
   'counts',coalesce((select jsonb_object_agg(category,n) from (select f.category,count(distinct f.asset_id) n from flags f join visible a on a.id=f.asset_id group by f.category)c),'{}'),
   'total',(select count(*) from visible))
 where auth.uid() is not null
$$;
revoke all on function public.asset_workspace(date) from public,anon;
grant execute on function public.asset_workspace(date) to authenticated;
