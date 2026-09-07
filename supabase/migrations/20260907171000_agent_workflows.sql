-- Document-backed drafts and explicitly delegated work management.
grant execute on function public.agent_can_manage_fleet(uuid) to authenticated;

-- Owners may also review company-private document drafts. Shared starter
-- creation remains the default in the existing owner checklist editor.
create or replace function public.checklist_can_author(p_client uuid,p_kind text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and
  (p.role='owner' or (p.role in ('client','client_admin') and p_client=public.checklist_company() and exists(
    select 1 from public.client_capabilities c where c.client_id=p_client and c.enabled
     and c.capability_key=case p_kind when 'operator_daily' then 'operational_checklists' else 'pm_checklists' end))))
$$;

create table public.maintenance_documents (
 id uuid primary key, client_id uuid not null references public.profiles(id),
 created_by uuid not null references public.profiles(id),
 title text not null check(length(title) between 3 and 160),
 created_at timestamptz not null default now(), archived boolean not null default false
);
create table public.maintenance_document_pages (
 document_id uuid not null references public.maintenance_documents(id),
 page integer not null check(page between 1 and 30),
 object_path text not null unique, primary key(document_id,page)
);
alter table public.maintenance_documents enable row level security;
alter table public.maintenance_document_pages enable row level security;
revoke all on public.maintenance_documents,public.maintenance_document_pages from public,anon,authenticated;
grant select on public.maintenance_documents,public.maintenance_document_pages to authenticated;
create policy document_manager_read on public.maintenance_documents for select to authenticated
 using(public.agent_can_manage_fleet(client_id));
create policy document_page_manager_read on public.maintenance_document_pages for select to authenticated
 using(exists(select 1 from public.maintenance_documents d where d.id=document_id and public.agent_can_manage_fleet(d.client_id)));

create table public.agent_plan_drafts (
 id uuid primary key, client_id uuid not null references public.profiles(id),
 asset_id uuid not null references public.assets(id), document_id uuid not null references public.maintenance_documents(id),
 created_by uuid not null references public.profiles(id), draft jsonb not null,
 created_at timestamptz not null default now(), applied_plan_id uuid references public.asset_service_intervals(id),
 applied_operation uuid, applied_payload jsonb, applied_by uuid references public.profiles(id)
);
alter table public.agent_plan_drafts enable row level security;
revoke all on public.agent_plan_drafts from public,anon,authenticated;
grant select on public.agent_plan_drafts to authenticated;
create policy agent_plan_manager_read on public.agent_plan_drafts for select to authenticated using(public.agent_can_manage_fleet(client_id));
alter table public.asset_service_intervals add column source_agent_plan_id uuid references public.agent_plan_drafts(id);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('maintenance-documents','maintenance-documents',false,5242880,array['image/jpeg','image/png']);
create function public.maintenance_document_object_access(p_path text,p_write boolean)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.maintenance_documents d where d.id::text=split_part(p_path,'/',1)
 and public.agent_can_manage_fleet(d.client_id) and (not p_write or (not d.archived
 and d.created_by=auth.uid() and split_part(p_path,'/',2) ~ '^([1-9]|[12][0-9]|30)\.(jpg|png)$'
 and array_length(string_to_array(p_path,'/'),1)=2
 and not exists(select 1 from public.maintenance_document_pages p where p.document_id=d.id))))
$$;
create policy maintenance_document_upload on storage.objects for insert to authenticated
 with check(bucket_id='maintenance-documents' and public.maintenance_document_object_access(name,true));
create policy maintenance_document_read on storage.objects for select to authenticated
 using(bucket_id='maintenance-documents' and public.maintenance_document_object_access(name,false));
-- No update/delete policy: a source cited by a draft cannot silently change.

create function public.save_maintenance_document(p_id uuid,p_client uuid,p_title text,p_pages integer default null)
returns void language plpgsql security definer set search_path='' as $$
declare d public.maintenance_documents; n integer; path text;
begin
 if p_id is null or not public.agent_can_manage_fleet(p_client) then raise exception 'Access denied'; end if;
 perform 1 from public.profiles where id=p_client for update;
 select * into d from public.maintenance_documents where id=p_id for update;
 if d.id is null then
  if p_pages is not null or (select count(*) from public.maintenance_documents where client_id=p_client)>499
    then raise exception 'Document limit reached'; end if;
  insert into public.maintenance_documents(id,client_id,created_by,title) values(p_id,p_client,auth.uid(),btrim(p_title));
  return;
 end if;
 if d.client_id<>p_client or d.created_by<>auth.uid() or d.title<>btrim(p_title) or d.archived
 then raise exception 'Document identity changed'; end if;
 if p_pages is null then return; end if;
 if p_pages not between 1 and 30 then raise exception 'Use 1 to 30 pages'; end if;
 if exists(select 1 from public.maintenance_document_pages where document_id=p_id) then
  if (select count(*) from public.maintenance_document_pages where document_id=p_id)<>p_pages then raise exception 'Pages already finalized'; end if;
  return;
 end if;
 for n in 1..p_pages loop
  select name into path from storage.objects where bucket_id='maintenance-documents'
    and name in (p_id::text||'/'||n||'.jpg',p_id::text||'/'||n||'.png') order by name limit 1;
  if path is null then raise exception 'Upload every page before finishing'; end if;
  insert into public.maintenance_document_pages values(p_id,n,path);
 end loop;
end $$;
revoke all on function public.save_maintenance_document(uuid,uuid,text,integer) from public,anon;
grant execute on function public.save_maintenance_document(uuid,uuid,text,integer) to authenticated;

-- Preserve the original three-argument API and add a distinct explicit-scope API.
create function public.create_agent_workflow_connection(p_client uuid,p_label text,p_allow_drafts boolean,
 p_allow_documents boolean,p_allow_management boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;
begin
 if p_allow_documents is null or p_allow_management is null then raise exception 'Choose permissions'; end if;
 answer:=public.create_agent_connection(p_client,p_label,p_allow_drafts);
 update public.agent_connections set allow_documents=p_allow_documents,allow_management=p_allow_management
 where id=(answer->>'id')::uuid;
 return answer;
end $$;
revoke all on function public.create_agent_workflow_connection(uuid,text,boolean,boolean,boolean) from public,anon;
grant execute on function public.create_agent_workflow_connection(uuid,text,boolean,boolean,boolean) to authenticated;

create function public.agent_workflow_action(c public.agent_connections,action text,input jsonb,operation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare aid uuid; jid uuid; doc public.maintenance_documents; page_row public.maintenance_document_pages;
 prior public.agent_activity; fingerprint text; answer jsonb; payload jsonb; rid uuid;
 item jsonb; n integer; rev integer; context jsonb; allowed text[]; existing public.asset_service_intervals; meter numeric;
begin
 if action in ('documents','document_page','create_checklist_draft','create_plan_draft') and not c.allow_documents then raise exception 'Document permission required'; end if;
 if action in ('assign_work_order','schedule_work_order','edit_work_order') and not c.allow_management then raise exception 'Management permission required'; end if;
 allowed:=case action
  when 'documents' then array['page'] when 'document_page' then array['document_id','page']
  when 'create_checklist_draft' then array['document_id','asset_id','name','description','checklist_type','items']
  when 'create_plan_draft' then array['document_id','asset_id','engine_id','interval_label','interval_hours','existing_plan_id','checklist_procedure_id','source_page','source_quote','notes']
  when 'work_order_context' then array['asset_id']
  when 'assign_work_order' then array['work_order_id','revision','assigned_to']
  when 'schedule_work_order' then array['work_order_id','revision','assigned_to','due_date','planned_start','estimated_minutes','priority','note']
  when 'edit_work_order' then array['work_order_id','revision','title','description','job_type','expected_materials','priority','note'] end;
 if allowed is null or exists(select 1 from jsonb_object_keys(input) k where not(k=any(allowed))) then raise exception 'Invalid input'; end if;
 if exists(select 1 from jsonb_each(input) e where e.key not in ('items','page','source_page','interval_hours','revision','estimated_minutes') and jsonb_typeof(e.value)<>'string')
 then raise exception 'Invalid input'; end if;
 if action='documents' then
  n:=coalesce((input->>'page')::integer,0);
  if n not between 0 and 10000 then raise exception 'Invalid page'; end if;
  select jsonb_build_object('documents',coalesce(jsonb_agg(x),'[]'),'next_page',case when (select count(*) from public.maintenance_documents where client_id=c.client_id and not archived)>(n+1)*25 then n+1 end)
  into answer from (select d.id,d.title,d.created_at,(select count(*) from public.maintenance_document_pages where document_id=d.id) pages
   from public.maintenance_documents d where d.client_id=c.client_id and not d.archived order by d.id limit 25 offset n*25) x;
  return answer;
 end if;
 if action in ('document_page','create_checklist_draft','create_plan_draft') then
  select * into doc from public.maintenance_documents where id=(input->>'document_id')::uuid and client_id=c.client_id and not archived;
  if doc.id is null then raise exception 'Access denied'; end if;
 end if;
 if action='document_page' then
  select * into page_row from public.maintenance_document_pages where document_id=doc.id and page=(input->>'page')::integer;
  if page_row.document_id is null then raise exception 'Invalid page'; end if;
  return jsonb_build_object('document_id',doc.id,'title',doc.title,'page',page_row.page,'object_path',page_row.object_path);
 end if;
 if action in ('create_checklist_draft','create_plan_draft','work_order_context') then
  aid:=(input->>'asset_id')::uuid;
 else
  jid:=(input->>'work_order_id')::uuid;
  select asset_id into aid from public.work_orders where id=jid and managed_maintenance;
 end if;
 if aid is null or not exists(select 1 from public.assets where id=aid and client_id=c.client_id)
  or not public.maintenance_can_manage_asset(aid) then raise exception 'Access denied'; end if;
 if action='work_order_context' then
  context:=public.maintenance_asset_context(aid);
  -- Deliberately exclude costs, reports, signatures and unrelated profile fields.
  return jsonb_build_object('assignees',context->'assignees','templates',context->'templates',
   'components',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'label',e.label,'current_hours',e.current_hours,
    'latest_meter_log',(select jsonb_build_object('hours',h.hours,'logged_at',h.logged_at) from public.hour_logs h where h.engine_id=e.id and h.asset_id=aid order by h.logged_at desc,h.id desc limit 1))) from public.asset_engines e where e.asset_id=aid),'[]'),
   'service_plans',coalesce((select jsonb_agg(x) from (select i.id,i.engine_id,i.interval_label,i.interval_hours,i.last_service_hours recorded_last_service_hours,
    i.next_due_hours,i.revision,i.is_active from public.asset_service_intervals i where i.asset_id=aid order by i.id limit 100) x),'[]'),
   'plans_truncated',(select count(*)>100 from public.asset_service_intervals where asset_id=aid),
   'approved_services',coalesce((select jsonb_agg(x) from (select w.id work_order_id,w.engine_id,w.title,w.hours_at_end,j.service_interval_id,j.service_applied_at
    from public.work_orders w join public.maintenance_job_records j on j.id=w.id where w.asset_id=aid and j.service_applied_at is not null
    order by j.service_applied_at desc,w.id limit 50) x),'[]'),
   'services_truncated',(select count(*)>50 from public.work_orders w join public.maintenance_job_records j on j.id=w.id where w.asset_id=aid and j.service_applied_at is not null),
   'work_orders',coalesce((select jsonb_agg(x) from (select w.id,w.title,w.description,w.job_type,w.status,w.assigned_to,
    w.scheduled_date due_date,j.revision,j.priority,j.expected_materials,j.planned_start,j.estimated_minutes
    from public.work_orders w join public.maintenance_job_records j on j.id=w.id where w.asset_id=aid
    and w.status<>'closed' and public.maintenance_can_read_job(w.id) order by w.id limit 100) x),'[]'),
   'truncated',(select count(*)>100 from public.work_orders where asset_id=aid and managed_maintenance and status<>'closed'));
 end if;
 if operation is null then raise exception 'Operation ID required'; end if;
 if action='create_checklist_draft' and not public.checklist_can_author(c.client_id,input->>'checklist_type') then raise exception 'Access denied'; end if;
 if action='create_plan_draft' and not public.maintenance_can_plan(aid) then raise exception 'Access denied'; end if;
 if action not in ('create_checklist_draft','create_plan_draft') and not public.maintenance_execution_enabled(aid) then raise exception 'Access denied'; end if;
 fingerprint:=encode(extensions.digest(input::text,'sha256'),'hex');
 select * into prior from public.agent_activity where connection_id=c.id and operation_id=operation and outcome='created';
 if prior.id is not null then
  if prior.action<>action or prior.input_hash is distinct from fingerprint then raise exception 'Operation ID used with different input'; end if;
  return prior.result||'{"replayed":true}'::jsonb;
 end if;
 if (select count(*) from public.agent_activity e where e.connection_id=c.id and e.outcome='created' and e.action<>'connection'
  and e.created_at>clock_timestamp()-interval '1 day')>=100 then raise exception 'Daily action limit reached'; end if;
 if action='create_plan_draft' then
  if not exists(select 1 from public.asset_engines where id=(input->>'engine_id')::uuid and asset_id=aid)
   or length(btrim(coalesce(input->>'interval_label',''))) not between 3 and 160
   or coalesce(input->>'interval_hours','') !~ '^[1-9][0-9]{0,6}$' or (input->>'interval_hours')::integer>1000000
   or length(btrim(coalesce(input->>'source_quote',''))) not between 3 and 1000
   or length(coalesce(input->>'notes',''))>2000
   or not exists(select 1 from public.maintenance_document_pages where document_id=doc.id and page=(input->>'source_page')::integer)
   then raise exception 'Invalid input'; end if;
  if input ? 'checklist_procedure_id' and not exists(select 1 from public.checklist_procedures p where p.id=(input->>'checklist_procedure_id')::uuid
    and p.client_id=c.client_id and not p.archived and p.draft->>'checklist_type'='pm'
    and p.draft->>'scope_asset_id'=aid::text and p.draft->>'source_document_id'=doc.id::text)
   then raise exception 'Access denied'; end if;
  if input ? 'existing_plan_id' then
   select * into existing from public.asset_service_intervals where id=(input->>'existing_plan_id')::uuid
    and asset_id=aid and engine_id=(input->>'engine_id')::uuid;
   if existing.id is null then raise exception 'Access denied'; end if;
  end if;
  select current_hours into meter from public.asset_engines where id=(input->>'engine_id')::uuid;
  payload:=input||jsonb_build_object('recorded_current_hours',meter,'recorded_last_service_hours',existing.last_service_hours,
   'proposed_next_due_hours',existing.last_service_hours+(input->>'interval_hours')::integer,
   'hours_remaining',existing.last_service_hours+(input->>'interval_hours')::integer-meter);
  rid:=gen_random_uuid();
  insert into public.agent_plan_drafts(id,client_id,asset_id,document_id,created_by,draft)
   values(rid,c.client_id,aid,doc.id,c.actor_id,payload);
  answer:=jsonb_build_object('plan_draft_id',rid,'status','draft','review_required',true,'equipment_context',
   payload-'items'-'source_quote'-'notes');
 elsif action='create_checklist_draft' then
  if not public.checklist_can_author(c.client_id,input->>'checklist_type') then raise exception 'Access denied'; end if;
  if jsonb_typeof(input->'items') is distinct from 'array' or jsonb_array_length(input->'items') not between 1 and 100
   then raise exception 'Invalid input'; end if;
  payload:=jsonb_build_object('name',input->>'name','description',coalesce(input->>'description',''),
   'checklist_type',input->>'checklist_type','scope_asset_id',aid,'source_document_id',doc.id,'source_document_title',doc.title,'items','[]'::jsonb);
  for item in select * from jsonb_array_elements(input->'items') loop
   if jsonb_typeof(item)<>'object' or exists(select 1 from jsonb_object_keys(item) k where k not in ('description_en','description_es','category','requires_photo','definition','source_page','source_quote'))
    or length(btrim(coalesce(item->>'source_quote',''))) not between 3 and 1000
    or not exists(select 1 from public.maintenance_document_pages where document_id=doc.id and page=(item->>'source_page')::integer)
    then raise exception 'Each step needs a source page and quote'; end if;
   if item ? 'definition' and (jsonb_typeof(item->'definition')<>'object' or exists(select 1 from jsonb_object_keys(item->'definition') k
     where k not in ('input_type','guidance','critical','allow_na','unit','min','max'))) then raise exception 'Invalid input'; end if;
   item:=jsonb_set(item,'{definition}',coalesce(item->'definition','{}')||jsonb_build_object(
    'source_document_id',doc.id,'source_page',item->'source_page','source_quote',item->>'source_quote'));
   payload:=jsonb_set(payload,'{items}',(payload->'items')||jsonb_build_array(item));
  end loop;
  rid:=gen_random_uuid();
  insert into public.checklist_procedures(id,client_id,created_by,draft) values(rid,c.client_id,c.actor_id,payload);
  perform public.save_checklist_procedure(gen_random_uuid(),rid,0,'draft',payload);
  answer:=jsonb_build_object('procedure_id',rid,'status','draft','review_required',true);
 else
  if not public.maintenance_execution_enabled(aid) then raise exception 'Access denied'; end if;
  rev:=(input->>'revision')::integer;
  if rev is null or rev<0 then raise exception 'Revision required'; end if;
  payload:=input-'work_order_id'-'revision';
  if action='assign_work_order' then
   perform public.change_maintenance_job(jid,rev,gen_random_uuid(),'assign',payload);
  elsif action='schedule_work_order' then
   perform public.schedule_maintenance_job(jid,rev,gen_random_uuid(),payload||'{"allow_overlap":false}'::jsonb);
  elsif action='edit_work_order' then
   perform public.update_internal_work_order(jid,rev,gen_random_uuid(),payload);
  end if;
  rid:=jid;
  answer:=jsonb_build_object('work_order_id',jid,'revision',(select revision from public.maintenance_job_records where id=jid));
 end if;
 insert into public.agent_activity(connection_id,actor_id,action,outcome,operation_id,input_hash,result_id,result)
 values(c.id,c.actor_id,action,'created',operation,fingerprint,rid,answer);
 return answer||'{"replayed":false}'::jsonb;
end $$;
revoke all on function public.agent_workflow_action(public.agent_connections,text,jsonb,uuid) from public,anon,authenticated;

-- Only a human app session can activate a plan, after editing its proposed
-- interval and providing an explicit last-service baseline. No agent tool calls
-- this function, and opaque connection keys are not authenticated JWTs.
create function public.apply_agent_plan_draft(p_draft uuid,p_operation uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare proposal public.agent_plan_drafts; plan uuid; payload jsonb; meter numeric; plan_revision integer;
begin
 select * into proposal from public.agent_plan_drafts where id=p_draft for update;
 if proposal.id is null or not public.agent_can_manage_fleet(proposal.client_id)
  or not public.maintenance_can_plan(proposal.asset_id) or p_operation is null then raise exception 'Access denied'; end if;
 if proposal.applied_plan_id is not null then
  if proposal.applied_operation<>p_operation or proposal.applied_payload is distinct from p_data then raise exception 'This proposal was already applied; edit its existing plan'; end if;
  return proposal.applied_plan_id;
 end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>16000
   or nullif(p_data->>'last_service_hours','') is null then raise exception 'Enter the verified last-service hours'; end if;
 if coalesce((p_data->>'source_reviewed')::boolean,false)=false then raise exception 'Verify the manual, current meter and service history'; end if;
 perform 1 from public.assets where id=proposal.asset_id for update;
 select current_hours into meter from public.asset_engines where id=(p_data->>'engine_id')::uuid and asset_id=proposal.asset_id for update;
 if meter is null or meter is distinct from (p_data->>'review_current_hours')::numeric then raise exception 'Current hours changed or are unknown; refresh and verify'; end if;
 if (p_data->>'last_service_hours')::numeric>meter then raise exception 'Last service cannot be beyond the current meter'; end if;
 if proposal.draft ? 'checklist_procedure_id' and not exists(select 1 from public.checklist_procedures
  where id=(proposal.draft->>'checklist_procedure_id')::uuid and not archived and published_template_id is not null)
  then raise exception 'Review and publish the proposed checklist first'; end if;
 payload:=jsonb_build_object('asset_id',proposal.asset_id,'engine_id',p_data->>'engine_id',
  'interval_label',p_data->>'interval_label','interval_hours',p_data->>'interval_hours',
  'last_service_hours',p_data->>'last_service_hours','is_active',coalesce(p_data->'is_active','true'::jsonb),'checklist_template_id',p_data->>'checklist_template_id');
 plan:=coalesce((proposal.draft->>'existing_plan_id')::uuid,gen_random_uuid());
 plan_revision:=case when proposal.draft ? 'existing_plan_id' then (p_data->>'revision')::integer else 0 end;
 if proposal.draft ? 'existing_plan_id' and not exists(select 1 from public.asset_service_intervals where id=plan and asset_id=proposal.asset_id)
  then raise exception 'Plan unavailable'; end if;
 perform public.save_maintenance_setup(gen_random_uuid(),'plan',plan,plan_revision,payload);
 update public.asset_service_intervals set source_agent_plan_id=proposal.id where id=plan;
 update public.agent_plan_drafts set applied_plan_id=plan,applied_operation=p_operation,applied_payload=p_data,applied_by=auth.uid() where id=proposal.id;
 return plan;
end $$;
revoke all on function public.apply_agent_plan_draft(uuid,uuid,jsonb) from public,anon;
grant execute on function public.apply_agent_plan_draft(uuid,uuid,jsonb) to authenticated;
