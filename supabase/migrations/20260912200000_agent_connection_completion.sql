-- NEXT-002.20: explicit host verification and human-reviewed work proposals.
create table public.agent_work_proposals (
 id uuid primary key default gen_random_uuid(),
 connection_id uuid not null references public.agent_connections(id),
 client_id uuid not null references public.profiles(id),
 work_order_id uuid not null references public.work_orders(id),
 action text not null check(action in ('assign_work_order','schedule_work_order','edit_work_order')),
 input jsonb not null,
 before_snapshot jsonb not null,
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 status text not null default 'pending' check(status in ('pending','applied','rejected')),
 reviewed_by uuid references public.profiles(id),
 reviewed_at timestamptz,
 review_operation uuid unique
);
alter table public.agent_work_proposals enable row level security;
revoke all on public.agent_work_proposals from public,anon,authenticated;
grant all on public.agent_work_proposals to service_role;
create index agent_work_proposals_pending on public.agent_work_proposals(client_id,created_at) where status='pending';

create function public.validate_agent_work_proposal(p_job uuid,p_action text,p_input jsonb) returns void
language plpgsql stable security definer set search_path='' as $$
declare person uuid; moment timestamptz; day date; duration integer; asset uuid;
begin
 select asset_id into asset from public.work_orders where id=p_job;
 person:=nullif(p_input->>'assigned_to','')::uuid;
 if p_action='assign_work_order' and person is null then raise exception 'Invalid input'; end if;
 if person is not null and not exists(select 1 from jsonb_array_elements(public.maintenance_asset_context(asset)->'assignees') p where p->>'id'=person::text)
  then raise exception 'Invalid input'; end if;
 if p_action in ('schedule_work_order','edit_work_order') and length(btrim(coalesce(p_input->>'note',''))) not between 3 and 1000 then raise exception 'Invalid input'; end if;
 if p_action='schedule_work_order' then
  if not (p_input ?& array['assigned_to','due_date','planned_start','priority']) then raise exception 'Invalid input'; end if;
  moment:=nullif(p_input->>'planned_start','')::timestamptz;
  day:=nullif(p_input->>'due_date','')::date;
  duration:=nullif(p_input->>'estimated_minutes','')::integer;
  if duration is not null and duration not between 15 and 10080 then raise exception 'Invalid input'; end if;
 end if;
 if p_action in ('schedule_work_order','edit_work_order') and coalesce(p_input->>'priority','') not in ('low','normal','high','urgent') then raise exception 'Invalid input'; end if;
 if p_action='edit_work_order' then
  if not(p_input ?& array['title','description','expected_materials','job_type','priority'])
   or length(btrim(coalesce(p_input->>'title',''))) not between 3 and 200
   or length(p_input->>'description')>8000 or length(p_input->>'expected_materials')>4000
   or coalesce(p_input->>'job_type','') not in ('repair','preventative','inspection','general') then raise exception 'Invalid input'; end if;
 end if;
end $$;
revoke all on function public.validate_agent_work_proposal(uuid,text,jsonb) from public,anon,authenticated;

create function public.agent_work_review_context(p_proposal uuid default null,p_client uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Access denied'; end if;
 if p_proposal is not null and not exists(select 1 from public.agent_work_proposals p
  join public.work_orders w on w.id=p.work_order_id where p.id=p_proposal
  and public.agent_can_manage_fleet(p.client_id) and public.maintenance_can_manage_asset(w.asset_id))
 then raise exception 'Access denied'; end if;
 if p_client is not null and not public.agent_can_manage_fleet(p_client) then raise exception 'Access denied'; end if;
 return coalesce((select jsonb_agg(data order by data->>'created_at') from (
  select to_jsonb(p)||jsonb_build_object('work_title',w.title,'asset_name',a.name,'asset_id',a.id,
   'connection_label',c.label,'current_revision',j.revision,
   'current_person',(select full_name from public.profiles where id=w.assigned_to),
   'proposed_person',(select full_name from public.profiles where id=nullif(p.input->>'assigned_to','')::uuid),
   'previous_person',(select full_name from public.profiles where id=nullif(p.before_snapshot->>'assigned_to','')::uuid),
   'can_apply',p.status='pending' and j.revision=(p.input->>'revision')::integer,
   'current',jsonb_build_object('title',w.title,'description',w.description,'job_type',w.job_type,'assigned_to',w.assigned_to,
    'due_date',w.scheduled_date,'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,
    'priority',j.priority,'expected_materials',j.expected_materials)) data
  from public.agent_work_proposals p join public.work_orders w on w.id=p.work_order_id
  join public.maintenance_job_records j on j.id=w.id join public.assets a on a.id=w.asset_id
  join public.agent_connections c on c.id=p.connection_id
  where (p_proposal is null or p.id=p_proposal) and (p_client is null or p.client_id=p_client)
  and (p_proposal is not null or p.status='pending')
  and public.agent_can_manage_fleet(p.client_id) and public.maintenance_can_manage_asset(a.id)
  order by p.created_at,p.id limit 100
 ) permitted),'[]');
end $$;
revoke all on function public.agent_work_review_context(uuid,uuid) from public,anon;
grant execute on function public.agent_work_review_context(uuid,uuid) to authenticated;

create function public.review_agent_work_proposal(p_proposal uuid,p_operation uuid,p_action text)
returns void language plpgsql security definer set search_path='' as $$
declare proposal public.agent_work_proposals; w public.work_orders; rev integer; payload jsonb;
begin
 if auth.uid() is null or p_operation is null or p_action not in ('apply','reject') then raise exception 'Access denied'; end if;
 select * into proposal from public.agent_work_proposals where id=p_proposal for update;
 select * into w from public.work_orders where id=proposal.work_order_id;
 if proposal.id is null or not public.agent_can_manage_fleet(proposal.client_id)
  or not public.maintenance_can_manage_asset(w.asset_id) then raise exception 'Access denied'; end if;
 if proposal.status<>'pending' then
  if proposal.review_operation=p_operation and proposal.reviewed_by=auth.uid()
   and proposal.status=(case p_action when 'apply' then 'applied' else 'rejected' end) then return; end if;
  raise exception 'Proposal already reviewed';
 end if;
 if p_action='apply' then
  rev:=(proposal.input->>'revision')::integer;
  payload:=proposal.input-'work_order_id'-'revision';
  if proposal.action='assign_work_order' then
   perform public.change_maintenance_job(w.id,rev,p_operation,'assign',payload);
  elsif proposal.action='schedule_work_order' then
   perform public.schedule_maintenance_job(w.id,rev,p_operation,payload||'{"allow_overlap":false}'::jsonb);
  else
   perform public.update_internal_work_order(w.id,rev,p_operation,payload);
  end if;
 end if;
 update public.agent_work_proposals set status=case p_action when 'apply' then 'applied' else 'rejected' end,
  reviewed_by=auth.uid(),reviewed_at=now(),review_operation=p_operation where id=proposal.id;
 insert into public.agent_activity(connection_id,actor_id,action,outcome,result_id)
 values(proposal.connection_id,auth.uid(),'review_work_proposal',case p_action when 'apply' then 'applied' else 'rejected' end,proposal.id);
end $$;
revoke all on function public.review_agent_work_proposal(uuid,uuid,text) from public,anon;
grant execute on function public.review_agent_work_proposal(uuid,uuid,text) to authenticated;

-- Modify the established checked implementations without duplicating their
-- token validation, role intersection, rate limit, audit or replay handling.
do $$ declare original text; updated text; begin
 original:=replace(pg_get_functiondef('public.agent_workflow_action(public.agent_connections,text,jsonb,uuid)'::regprocedure),chr(13),'');
 updated:=replace(original,replace($old$  if action='assign_work_order' then
   perform public.change_maintenance_job(jid,rev,gen_random_uuid(),'assign',payload);
  elsif action='schedule_work_order' then
   perform public.schedule_maintenance_job(jid,rev,gen_random_uuid(),payload||'{"allow_overlap":false}'::jsonb);
  elsif action='edit_work_order' then
   perform public.update_internal_work_order(jid,rev,gen_random_uuid(),payload);
  end if;
  rid:=jid;
  answer:=jsonb_build_object('work_order_id',jid,'revision',(select revision from public.maintenance_job_records where id=jid));$old$,chr(13),''),
 $new$  if not exists(select 1 from public.maintenance_job_records where id=jid and revision=rev) then raise exception 'Revision required'; end if;
  perform public.validate_agent_work_proposal(jid,action,input);
  rid:=gen_random_uuid();
  insert into public.agent_work_proposals(id,connection_id,client_id,work_order_id,action,input,before_snapshot,created_by)
  select rid,c.id,c.client_id,jid,action,input,jsonb_build_object('title',w.title,'description',w.description,'job_type',w.job_type,
   'assigned_to',w.assigned_to,'due_date',w.scheduled_date,'planned_start',j.planned_start,'estimated_minutes',j.estimated_minutes,
   'priority',j.priority,'expected_materials',j.expected_materials),c.actor_id
  from public.work_orders w join public.maintenance_job_records j on j.id=w.id where w.id=jid;
  answer:=jsonb_build_object('proposal_id',rid,'work_order_id',jid,'status','pending','review_required',true);$new$);
 if updated=original then raise exception 'Agent proposal adaptation did not match'; end if;
 execute updated;

 original:=replace(pg_get_functiondef('public.agent_execute(text,text,jsonb,uuid)'::regprocedure),chr(13),'');
 updated:=replace(original,replace($old$   if p_action='maintenance_summary' then$old$,chr(13),''),$new$   if p_action='connection_test' then
     if p_input<>'{}'::jsonb or p_operation is not null then raise exception 'Invalid input'; end if;
     answer:=jsonb_build_object('connected',true,'connection_id',conn.id,'fleet_id',conn.client_id,'label',conn.label,
      'expires_at',conn.expires_at,'tested_at',clock_timestamp(),'allow_drafts',conn.allow_drafts,
      'allow_documents',conn.allow_documents,'allow_management_proposals',conn.allow_management,'human_review_required',true);
   elsif p_action='maintenance_summary' then$new$);
 updated:=replace(updated,replace($old$case when p_action in ('maintenance_summary','create_work_order_draft','documents','document_page',$old$,chr(13),''),
  $new$case when p_action in ('connection_test','maintenance_summary','create_work_order_draft','documents','document_page',$new$);
 updated:=replace(updated,'e.current_hours,i.next_due_hours,','e.current_hours,e.meter_unit,i.next_due_hours,i.next_due_date,i.interval_months,');
 if updated=original or position('connected' in updated)=0 then raise exception 'Agent connection test adaptation did not match'; end if;
 execute updated;

 original:=replace(pg_get_functiondef('public.agent_access_context()'::regprocedure),chr(13),'');
 updated:=replace(original,replace($old$where id=auth.uid() and role in ('owner','client','client_admin')$old$,chr(13),''),
  $new$where id=auth.uid() and (role in ('owner','client','client_admin') or (role='member' and public.organization_has_permission(public.active_organization_id(),'assets_manage')))$new$);
 updated:=replace(updated,'c.created_at,c.expires_at,c.revoked_at','c.created_at,c.expires_at,c.revoked_at,
  (select max(e.created_at) from public.agent_activity e where e.connection_id=c.id and e.action=''connection_test'' and e.outcome=''read'') last_tested_at');
 updated:=replace(updated,'e.result_id,e.created_at,c.label','e.result_id,e.created_at,c.label,
  exists(select 1 from public.agent_work_proposals p where p.id=e.result_id) work_proposal');
 if updated=original or position('last_tested_at' in updated)=0 then raise exception 'Agent setup context adaptation did not match'; end if;
 execute updated;
end $$;


-- The established *_hours columns retain numeric meter values; agent context
-- now carries the immutable unit and calendar target beside every value.
do $$ declare original text; updated text; begin
 original:=replace(pg_get_functiondef('public.agent_workflow_action(public.agent_connections,text,jsonb,uuid)'::regprocedure),chr(13),'');
 updated:=replace(original,replace($old$'interval_label','interval_hours','existing_plan_id'$old$,chr(13),''),$new$'interval_label','interval_hours','meter_unit','existing_plan_id'$new$);
 updated:=replace(updated,replace($old$'current_hours',e.current_hours,$old$,chr(13),''),$new$'current_hours',e.current_hours,'meter_unit',e.meter_unit,$new$);
 updated:=replace(updated,replace($old$'hours',h.hours,'logged_at',h.logged_at$old$,chr(13),''),$new$'hours',h.hours,'meter_unit',h.meter_unit,'logged_at',h.logged_at$new$);
 updated:=replace(updated,replace($old$i.next_due_hours,i.revision,i.is_active$old$,chr(13),''),$new$i.next_due_hours,i.next_due_date,i.interval_months,(select meter_unit from public.asset_engines where id=i.engine_id) meter_unit,i.revision,i.is_active$new$);
 updated:=replace(updated,replace($old$w.title,w.hours_at_end,j.service_interval_id$old$,chr(13),''),$new$w.title,w.hours_at_end,w.meter_unit,j.service_interval_id$new$);
 updated:=replace(updated,replace($old$  select current_hours into meter from public.asset_engines where id=(input->>'engine_id')::uuid;
  payload:=input||jsonb_build_object('recorded_current_hours',meter,$old$,chr(13),''),$new$  if not exists(select 1 from public.asset_engines where id=(input->>'engine_id')::uuid
   and meter_unit=coalesce(input->>'meter_unit','hours')) then raise exception 'Invalid input'; end if;
  select current_hours into meter from public.asset_engines where id=(input->>'engine_id')::uuid;
  payload:=input||jsonb_build_object('meter_unit',coalesce(input->>'meter_unit','hours'),'recorded_current_hours',meter,$new$);
 if updated=original or position('and meter_unit=coalesce(input' in updated)=0 then raise exception 'Agent meter context adaptation did not match'; end if;
 execute updated;

 original:=replace(pg_get_functiondef('public.apply_agent_plan_draft(uuid,uuid,jsonb)'::regprocedure),chr(13),'');
 updated:=replace(original,replace($old$ if meter is null or meter is distinct from (p_data->>'review_current_hours')::numeric then$old$,chr(13),''),
 $new$ if not exists(select 1 from public.asset_engines where id=(p_data->>'engine_id')::uuid
  and meter_unit=coalesce(p_data->>'meter_unit','hours')
  and meter_unit=coalesce(proposal.draft->>'meter_unit','hours')) then raise exception 'Meter unit changed; review the source and create a new proposal'; end if;
 if meter is null or meter is distinct from (p_data->>'review_current_hours')::numeric then$new$);
 updated:=replace(updated,replace($old$'interval_label',p_data->>'interval_label','interval_hours',p_data->>'interval_hours',$old$,chr(13),''),
 $new$'interval_label',p_data->>'interval_label','interval_hours',p_data->>'interval_hours','meter_unit',p_data->>'meter_unit',$new$);
 updated:=replace(updated,replace($old$ plan:=coalesce((proposal.draft->>'existing_plan_id')::uuid,gen_random_uuid());$old$,chr(13),''),
 $new$ payload:=payload||coalesce((select jsonb_object_agg(key,value) from jsonb_each(p_data)
  where key in ('interval_months','recurrence_mode','last_service_date','anchor_hours','anchor_date','generation_lead_days','notes','covers_plan_ids')),'{}'::jsonb);
 if length(btrim(coalesce(p_data->>'change_reason','')))>=3 then payload:=payload||jsonb_build_object('change_reason',p_data->>'change_reason'); end if;
 plan:=coalesce((proposal.draft->>'existing_plan_id')::uuid,gen_random_uuid());$new$);
 if updated=original or position('Meter unit changed' in updated)=0 then raise exception 'Agent plan meter review adaptation did not match'; end if;
 execute updated;

 original:=replace(pg_get_functiondef('public.agent_plan_review_context(uuid)'::regprocedure),chr(13),'');
 updated:=replace(original,'w.title,w.hours_at_end,j.service_applied_at','w.title,w.hours_at_end,w.meter_unit,j.service_applied_at');
 updated:=replace(updated,replace($old$'hours',h.hours,'logged_at',h.logged_at$old$,chr(13),''),$new$'hours',h.hours,'meter_unit',h.meter_unit,'logged_at',h.logged_at$new$);
 if updated=original then raise exception 'Agent historical meter review adaptation did not match'; end if;
 execute updated;
end $$;
