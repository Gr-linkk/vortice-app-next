-- Explicit reasons preserve the distinction between a recorded parts wait and
-- an inferred shortage. Existing on-hold records remain categorized as other.
alter table public.maintenance_job_records add column blocked_category text not null default 'other'
 check(blocked_category in ('parts','people','external','other'));
create function public.capture_maintenance_block_category()
returns trigger language plpgsql security definer set search_path='' as $$
declare category text;
begin
 if new.kind='block' then
  category:=coalesce(new.payload->>'blocked_category','other');
  if category not in ('parts','people','external','other') then raise exception 'Invalid blocked category'; end if;
  update public.maintenance_job_records set blocked_category=category where id=new.object_id;
 elsif new.kind='start' then
  update public.maintenance_job_records set blocked_category='other' where id=new.object_id;
 end if;
 return new;
end $$;
revoke all on function public.capture_maintenance_block_category() from public,anon,authenticated;
create trigger maintenance_block_category after insert on public.maintenance_operations
 for each row execute function public.capture_maintenance_block_category();

create function public.fleet_attention_rows(p_today date)
returns table(category text,rank integer,kind text,id uuid,asset_id uuid,asset_name text,
 title text,reason text,due_date date,remaining_hours numeric,managed boolean)
language sql stable security definer set search_path='' as $$
 with assets as materialized (
  select a.* from public.assets a where public.maintenance_can_manage_asset(a.id)
 ), jobs as materialized (
  select w.*,j.blocked_category from public.work_orders w join assets a on a.id=w.asset_id
  left join public.maintenance_job_records j on j.id=w.id
  where w.status not in ('closed','invoiced') and public.coordination_subject_reader('job',w.id,auth.uid())
 ), plans as materialized (
  select p.*,e.current_hours from public.asset_service_intervals p join assets a on a.id=p.asset_id
  left join public.asset_engines e on e.id=p.engine_id and e.asset_id=p.asset_id where p.is_active
 ), rows as (
  select 'unavailable'::text category,0 rank,'asset'::text kind,a.id,a.id asset_id,a.name asset_name,
   a.name title,s.reason,null::date due_date,null::numeric remaining_hours,false managed
  from assets a join public.asset_operating_states s on s.asset_id=a.id
  where s.operating_state in ('out_of_service','under_maintenance')
  union all
  select 'urgent_faults',1,'fault',f.id,a.id,a.name,f.description,f.status,null,null,false
  from public.maintenance_requests f join assets a on a.id=f.asset_id
  where f.severity='urgent' and f.status not in ('resolved','dismissed')
  union all
  select 'overdue_service',2,'plan',p.id,a.id,a.name,coalesce(p.interval_label,p.interval_hours||' h'),'',null,p.next_due_hours-p.current_hours,false
  from plans p join assets a on a.id=p.asset_id where p.next_due_hours<=p.current_hours
  union all
  select 'overdue_work',3,'job',w.id,a.id,a.name,w.title,w.status,w.scheduled_date,null,w.managed_maintenance
  from jobs w join assets a on a.id=w.asset_id where w.scheduled_date<p_today
  union all
  select 'review',4,'job',w.id,a.id,a.name,w.title,w.status,w.scheduled_date,null,w.managed_maintenance
  from jobs w join assets a on a.id=w.asset_id where w.status='pending_review'
  union all
  select 'review',4,'fault',f.id,a.id,a.name,f.description,f.status,null,null,false
  from public.maintenance_requests f join assets a on a.id=f.asset_id where f.status='pending_review'
  union all
  select 'waiting_parts',5,'job',w.id,a.id,a.name,w.title,w.on_hold_reason,w.scheduled_date,null,w.managed_maintenance
  from jobs w join assets a on a.id=w.asset_id where w.status='on_hold' and w.blocked_category='parts'
  union all
  select 'waiting_people',6,'job',w.id,a.id,a.name,w.title,coalesce(w.on_hold_reason,w.status),w.scheduled_date,null,w.managed_maintenance
  from jobs w join assets a on a.id=w.asset_id
  where (w.assigned_to is null and w.status<>'pending_review') or (w.status='on_hold' and w.blocked_category='people')
  union all
  select 'blocked_other',7,'job',w.id,a.id,a.name,w.title,w.on_hold_reason,w.scheduled_date,null,w.managed_maintenance
  from jobs w join assets a on a.id=w.asset_id where w.status='on_hold' and coalesce(w.blocked_category,'other') in ('external','other')
  union all
  select 'approaching_service',8,'plan',p.id,a.id,a.name,coalesce(p.interval_label,p.interval_hours||' h'),'',null,p.next_due_hours-p.current_hours,false
  from plans p join assets a on a.id=p.asset_id where p.next_due_hours-p.current_hours>0 and p.next_due_hours-p.current_hours<=50
  union all
  select 'upcoming_work',9,'job',w.id,a.id,a.name,w.title,w.status,w.scheduled_date,null,w.managed_maintenance
  from jobs w join assets a on a.id=w.asset_id where w.scheduled_date between p_today and p_today+7
  union all
  select 'plan_setup',10,'plan',p.id,a.id,a.name,coalesce(p.interval_label,p.interval_hours||' h'),'',null,null,false
  from plans p join assets a on a.id=p.asset_id where p.engine_id is null or p.next_due_hours is null or p.current_hours is null
  union all
  select 'plan_setup',10,'asset',a.id,a.id,a.name,a.name,'',null,null,false from assets a
  where not exists(select 1 from plans p where p.asset_id=a.id)
  union all
  select 'unassessed',11,'asset',a.id,a.id,a.name,a.name,'',null,null,false from assets a
  where not exists(select 1 from public.asset_operating_states s where s.asset_id=a.id)
 ) select * from rows
$$;
revoke all on function public.fleet_attention_rows(date) from public,anon,authenticated;

create function public.fleet_attention(p_today date default current_date,p_category text default null,
 p_offset integer default 0,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role in ('owner','client','client_admin'))
  then raise exception 'Access denied' using errcode='42501'; end if;
 if p_today is null or p_offset is null or p_offset<0 or p_limit is null or p_limit not between 1 and 200 or
 (p_category is not null and p_category not in ('unavailable','urgent_faults','overdue_service','overdue_work','review',
  'waiting_parts','waiting_people','blocked_other','approaching_service','upcoming_work','plan_setup','unassessed'))
  then raise exception 'Invalid attention filter'; end if;
 with rows as materialized (select * from public.fleet_attention_rows(p_today)),
 selected as (select distinct on(kind,id) * from rows where p_category is null or category=p_category order by kind,id,rank),
 page as (select * from selected order by rank,due_date nulls last,asset_name,kind,id offset p_offset limit p_limit)
 select jsonb_build_object('generated_at',statement_timestamp(),'today',p_today,'counts',
  (select jsonb_object_agg(c,coalesce((select count(*) from rows r where r.category=c),0))
   from unnest(array['unavailable','urgent_faults','overdue_service','overdue_work','review','waiting_parts','waiting_people',
    'blocked_other','approaching_service','upcoming_work','plan_setup','unassessed']) c),
  'items',coalesce((select jsonb_agg(to_jsonb(p)-'rank' order by rank,due_date nulls last,asset_name,kind,id) from page p),'[]'),
  'total',(select count(*) from selected),'has_more',(select count(*)>p_offset+p_limit from selected)) into result;
 return result;
end $$;
revoke all on function public.fleet_attention(date,text,integer,integer) from public,anon;
grant execute on function public.fleet_attention(date,text,integer,integer) to authenticated;

create or replace function public.maintenance_jobs(p_job uuid default null,p_asset uuid default null)
returns setof jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',w.id,'asset_id',w.asset_id,'asset_name',a.name,
 'title',w.title,'description',w.description,'status',w.status,'assigned_to',w.assigned_to,
 'assignee_name',p.full_name,'due_date',w.scheduled_date,'engine_id',w.engine_id,
 'component_name',e.label,'job_type',w.job_type,'hours_at_end',w.hours_at_end,
 'on_hold_reason',w.on_hold_reason,'blocked_category',j.blocked_category,'created_at',w.created_at,'completed_at',w.completed_at,
 'revision',j.revision,'priority',j.priority,'service_interval_id',j.service_interval_id,
 'parent_job_id',j.parent_job_id,'hourly_cost',j.hourly_cost,'review_note',j.review_note,
 'approved_at',j.approved_at,'service_applied_at',j.service_applied_at,
 'checklist_snapshot',j.checklist_snapshot,'checklist_answers',j.checklist_answers,'evidence_paths',j.evidence_paths,
 'can_manage',public.maintenance_can_manage_asset(w.asset_id),
 'can_work',public.maintenance_can_work_job(w.id),
 'report',(select jsonb_build_object('diagnosis',s.cause,'repair',s.correction,'notes',s.comments) from public.service_reports s where s.work_order_id=w.id),
 'parts',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'description',r.description,'part_number',r.part_number,
 'quantity',r.quantity,'unit_cost',r.unit_cost)) from public.parts r where r.work_order_id=w.id),'[]'),
 'labour',coalesce((select jsonb_agg(to_jsonb(l) order by l.started_at,l.id) from public.maintenance_labour_sessions l where l.work_order_id=w.id),'[]'),
 'events',coalesce((select jsonb_agg(jsonb_build_object('kind',o.kind,'actor_name',actor.full_name,
 'created_at',o.created_at,'note',o.payload->>'note') order by o.created_at,o.id)
 from public.maintenance_operations o left join public.profiles actor on actor.id=o.actor_id where o.object_id=w.id),'[]'))
 from public.work_orders w join public.maintenance_job_records j on j.id=w.id
 join public.assets a on a.id=w.asset_id left join public.profiles p on p.id=w.assigned_to
 left join public.asset_engines e on e.id=w.engine_id
 where public.maintenance_can_read_job(w.id) and (p_job is null or w.id=p_job) and (p_asset is null or w.asset_id=p_asset)
 order by (w.status='closed'),case j.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end,w.scheduled_date nulls last,w.created_at desc
$$;
