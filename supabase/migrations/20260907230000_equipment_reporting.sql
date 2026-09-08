-- NOW-024: one authorized, transaction-consistent report; no source mutations.
create function public.equipment_report(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; cutoff timestamptz := least(p_to, now());
begin
 if auth.uid() is null or not exists(select 1 from public.profiles
   where id=auth.uid() and role in ('owner','client','client_admin')) then
   raise exception 'Access denied';
 end if;
 if p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to)
   or p_from>=cutoff or p_to-p_from>interval '366 days' then
   raise exception 'Select a past or current period of at most 366 days';
 end if;
 with assets as materialized (
   select a.id,a.name,a.location,a.client_id,a.created_at from public.assets a
   where public.maintenance_can_manage_asset(a.id)
 ), receipts as (
   select w.id,w.asset_id,w.title,s.snapshot,s.submitted_at
   from public.work_orders w join assets a on a.id=w.asset_id
   join lateral (select sc.snapshot,sc.submitted_at from public.saved_checklists sc
     where sc.work_order_id=w.id and sc.snapshot->>'managed_maintenance'='true'
     order by sc.submitted_at desc,sc.id desc limit 1) s on true
   where w.managed_maintenance and public.maintenance_can_read_job(w.id)
     and (public.get_my_role()='owner' or w.client_id=a.client_id)
     and s.submitted_at>=p_from and s.submitted_at<cutoff
 ), internal as (
   select r.*,
     round(coalesce(l.hours,0)*coalesce((snapshot->>'hourly_cost')::numeric,0),2) labour,
     round(coalesce(p.cost,0),2) parts,
     (case when coalesce(l.hours,0)>0 and coalesce((snapshot->>'hourly_cost')::numeric,0)=0
       then 1 else 0 end + coalesce(p.unpriced,0) +
       case when coalesce(l.hours,0)=0 and jsonb_array_length(coalesce(snapshot->'parts','[]'))=0 then 1 else 0 end)::int gaps
   from receipts r
   left join lateral (select sum(extract(epoch from
     (x->>'stopped_at')::timestamptz-(x->>'started_at')::timestamptz)/3600) hours
     from jsonb_array_elements(coalesce(snapshot->'labour','[]')) x) l on true
   left join lateral (select sum((x->>'quantity')::numeric*(x->>'unit_cost')::numeric) cost,
     count(*) filter(where coalesce((x->>'unit_cost')::numeric,0)=0 and (x->>'quantity')::numeric>0) unpriced
     from jsonb_array_elements(coalesce(snapshot->'parts','[]')) x) p on true
 ), missing_receipts as (
   select w.id,w.asset_id,w.title,j.approved_at occurred_at
   from public.work_orders w join assets a on a.id=w.asset_id
   join public.maintenance_job_records j on j.id=w.id
   where w.managed_maintenance and public.maintenance_can_read_job(w.id)
     and (public.get_my_role()='owner' or w.client_id=a.client_id)
     and j.approved_at>=p_from and j.approved_at<cutoff
     and not exists(select 1 from public.saved_checklists s
       where s.work_order_id=w.id and s.snapshot->>'managed_maintenance'='true')
 ), invoices as (
   select i.id,w.asset_id,i.invoice_number title,i.sent_at occurred_at,i.total_usd cost
   from public.invoices i join public.work_orders w on w.id=i.work_order_id join assets a on a.id=w.asset_id
   where not w.managed_maintenance and i.status in ('sent','paid')
     and i.sent_at>=p_from and i.sent_at<cutoff
     and (public.get_my_role()='owner' or i.client_id=auth.uid() or exists(
       select 1 from public.profiles p join public.client_orgs o on o.id=p.org_id
       where p.id=auth.uid() and p.role='client_admin' and o.owner_profile_id=i.client_id))
 ), uncosted as (
   select w.id,w.asset_id,
     case when public.coordination_subject_reader('job',w.id,auth.uid()) then w.title else '' end title,
     w.completed_at occurred_at
   from public.work_orders w join assets a on a.id=w.asset_id
   where not w.managed_maintenance and w.completed_at>=p_from and w.completed_at<cutoff
   and public.can_read_provider_report(w.id)
   and (public.get_my_role()='owner' or w.client_id=a.client_id)
   and w.status in ('completed','invoiced','closed')
   and not exists(select 1 from public.invoices i where i.work_order_id=w.id and i.status in ('sent','paid'))
 ), event_points as (
   -- Legacy events at identical timestamps have no reliable within-time order.
   select e.asset_id,e.created_at,(array_agg(e.id order by e.id))[1] id,
     case when count(distinct e.to_state)=1 then min(e.to_state) else 'unknown' end to_state,
     case when count(*)=1 then min(e.note) else '' end note
   from public.asset_availability_events e join assets a on a.id=e.asset_id
   where e.created_at<cutoff
   group by e.asset_id,e.created_at
 ), events as (
   select e.*,lead(e.created_at,1,cutoff) over(partition by e.asset_id order by e.created_at) until_at
   from event_points e
 ), spans as (
   select e.asset_id,e.id,e.note,e.to_state,e.created_at,
     greatest(e.created_at,p_from) from_at,least(e.until_at,cutoff) until_at
   from events e where e.until_at>p_from
 ), faults as (
   select f.id,f.asset_id,f.description,f.created_at,
     lower(btrim(regexp_replace(f.description,'\s+',' ','g'))) match_key
   from public.maintenance_requests f join assets a on a.id=f.asset_id
   where f.created_at>=p_from and f.created_at<cutoff and f.status<>'dismissed'
 ), repeats as (
   select asset_id,min(description) description,count(*) count,
     jsonb_agg(id order by created_at,id) ids
   from faults group by asset_id,match_key having count(*)>1
 ), records as (
   select asset_id,id,'internal' kind,title,submitted_at occurred_at,
     labour,parts,0::numeric outside,0::numeric hours,gaps from internal
   union all select asset_id,id,'invoice',title,occurred_at,0,0,coalesce(cost,0),0,
     case when coalesce(cost,0)=0 then 1 else 0 end from invoices
   union all select asset_id,id,'internal_missing',title,occurred_at,0,0,0,0,1 from missing_receipts
   union all select asset_id,id,'uncosted',title,occurred_at,0,0,0,0,1 from uncosted
   union all select asset_id,id,'downtime',note,from_at,0,0,0,
     extract(epoch from until_at-from_at)/3600,0 from spans
     where to_state in ('out_of_service','under_maintenance') and until_at>from_at
   union all select asset_id,id,'fault',description,created_at,0,0,0,0,0 from faults
 )
 select jsonb_build_object('generated_at',now(),'from',p_from,'to',cutoff,'currency','USD',
   'assets',coalesce(jsonb_agg(item order by (item->>'total')::numeric desc,item->>'name',item->>'id'),'[]'))
 into result from (
   select jsonb_build_object('id',a.id,'name',a.name,'location',a.location,
     'labour',coalesce(r.labour,0),'parts',coalesce(r.parts,0),'outside',coalesce(r.outside,0),
     'total',coalesce(r.labour,0)+coalesce(r.parts,0)+coalesce(r.outside,0),
     'unavailable_hours',coalesce(r.hours,0),'cost_gaps',coalesce(r.gaps,0),
     'unknown_hours',greatest(0,extract(epoch from cutoff-greatest(p_from,coalesce(a.created_at,p_from)))/3600-
       coalesce((select sum(extract(epoch from until_at-greatest(from_at,coalesce(a.created_at,p_from)))/3600)
       from spans where asset_id=a.id and to_state<>'unknown'
         and until_at>greatest(from_at,coalesce(a.created_at,p_from))),0)),
     'fault_count',(select count(*) from faults where asset_id=a.id),
     'repeats',coalesce((select jsonb_agg(jsonb_build_object('description',description,'count',count,'ids',ids)
       order by count desc,description) from repeats where asset_id=a.id),'[]'),
     'records',coalesce(r.rows,'[]')) item
   from assets a left join lateral (
     select sum(labour) labour,sum(parts) parts,sum(outside) outside,sum(hours) hours,sum(gaps) gaps,
       jsonb_agg(to_jsonb(records)-'asset_id' order by occurred_at desc,id) rows
     from records where asset_id=a.id
   ) r on true
 ) report;
 return result;
end $$;
revoke all on function public.equipment_report(timestamptz,timestamptz) from public,anon;
grant execute on function public.equipment_report(timestamptz,timestamptz) to authenticated;
