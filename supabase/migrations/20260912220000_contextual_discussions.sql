-- NEXT-002.19: a finding keeps one conversation from checklist to repair.
alter table public.coordination_posts drop constraint coordination_posts_subject_kind_check;
alter table public.coordination_posts add constraint coordination_posts_subject_kind_check
 check(subject_kind in ('job','fault','asset','checklist','inspection','request','report'));

create table public.checklist_issue_context (
 run_id uuid not null references public.operator_checklist_runs(id),
 item_id uuid not null references public.checklist_items(id),
 fault_id uuid not null references public.maintenance_requests(id),
 post_id uuid not null unique references public.coordination_posts(id),
 message text not null check(length(message) between 1 and 4000),
 urgency text not null check(urgency in ('normal','urgent')),
 safe_to_operate text not null check(safe_to_operate in ('safe','unsafe','unknown')),
 photo_path text,
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default clock_timestamp(),
 primary key(run_id,item_id)
);
alter table public.checklist_issue_context enable row level security;
revoke all on public.checklist_issue_context from public,anon,authenticated;
grant select on public.checklist_issue_context to authenticated;

create or replace function public.coordination_subject_asset(p_kind text,p_id uuid)
returns uuid language sql stable security definer set search_path='' as $$
 select asset_id from public.work_orders where p_kind in ('job','inspection') and id=p_id
 union all select asset_id from public.maintenance_requests where p_kind='fault' and id=p_id
 union all select id from public.assets where p_kind='asset' and id=p_id
 union all select asset_id from public.saved_checklists where p_kind='checklist' and id=p_id
 union all select asset_id from public.service_requests where p_kind='request' and id=p_id
 union all select w.asset_id from public.service_reports r join public.work_orders w on w.id=r.work_order_id where p_kind='report' and r.id=p_id
$$;

alter function public.coordination_subject_reader(text,uuid,uuid) rename to coordination_subject_reader_before_context;
create function public.coordination_subject_reader(p_kind text,p_id uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select case
 when p_kind in ('job','fault') then public.coordination_subject_reader_before_context(p_kind,p_id,p_user)
 when p_kind='inspection' then exists(select 1 from public.work_orders w where w.id=p_id and w.job_type='inspection' and public.coordination_subject_reader_before_context('job',w.id,p_user))
 when p_kind='report' then exists(select 1 from public.service_reports r where r.id=p_id and public.coordination_subject_reader_before_context('job',r.work_order_id,p_user))
 when p_kind='asset' then public.coordination_asset_viewer(p_id,p_user)
 when p_kind='checklist' then exists(select 1 from public.saved_checklists s join public.profiles p on p.id=p_user
  where s.id=p_id and public.coordination_asset_viewer(s.asset_id,p_user)
   and (s.checklist_type='operations' or p.role not in ('operator','client_operator'))
   and (s.work_order_id is null or public.coordination_subject_reader_before_context('job',s.work_order_id,p_user)))
 when p_kind='request' then exists(select 1 from public.service_requests r join public.profiles p on p.id=p_user
  where r.id=p_id and public.coordination_asset_viewer(r.asset_id,p_user)
   and (p.role in ('owner','employee') or r.client_id=p.id or (p.role in ('client','client_admin')
    and exists(select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=r.client_id))))
 else false end
$$;
revoke all on function public.coordination_subject_reader_before_context(text,uuid,uuid),public.coordination_subject_reader(text,uuid,uuid) from public,anon,authenticated;
create or replace function public.coordination_can_post(p_kind text,p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.coordination_subject_reader(p_kind,p_id,auth.uid()) and (
 p_kind in ('fault','asset','checklist','request') or exists(select 1 from public.work_orders w
  where (w.id=p_id and p_kind in ('job','inspection') or p_kind='report' and exists(select 1 from public.service_reports r where r.id=p_id and r.work_order_id=w.id))
  and (not w.managed_maintenance or public.maintenance_can_work_job(w.id))))
$$;
create policy checklist_issue_context_read on public.checklist_issue_context for select to authenticated
 using(public.coordination_post_reader(post_id,auth.uid()));

-- An originating operator can follow explicitly shared repair replies in their
-- checklist thread. This does not grant access to the job or its private report.
create or replace function public.coordination_post_reader(p_post uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.coordination_posts p join public.assets a on a.id=p.asset_id
 where p.id=p_post and p.client_id=a.client_id and public.coordination_asset_viewer(a.id,p_user)
 and (public.coordination_subject_reader(p.subject_kind,p.subject_id,p_user)
  or (p.visibility='shared' and p.subject_kind='job' and exists(
   select 1 from public.checklist_findings c join public.operator_checklist_runs r on r.id=c.run_id
    join public.maintenance_requests f on f.id=c.fault_id
    where r.operator_id=p_user and f.converted_to_work_order_id=p.subject_id)))
 and (p.visibility='shared' or p.team=public.coordination_user_team(p_user)))
$$;

create function public.coordination_context_matches(p_post uuid,p_kind text,p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.coordination_posts p where p.id=p_post and (
  (p.subject_kind=p_kind and p.subject_id=p_id)
  or (p_kind='asset' and p.asset_id=p_id)
  or (p_kind='fault' and exists(select 1 from public.checklist_issue_context c where c.post_id=p.id and c.fault_id=p_id))
  or (p_kind='checklist' and p.subject_kind='fault' and exists(select 1 from public.checklist_findings c where c.run_id=p_id and c.fault_id=p.subject_id))
  or (p_kind='checklist' and p.subject_kind='job' and exists(select 1 from public.checklist_findings c join public.maintenance_requests f on f.id=c.fault_id where c.run_id=p_id and f.converted_to_work_order_id=p.subject_id))
  or (p_kind in ('job','inspection') and (
   (p.subject_kind in ('job','inspection') and p.subject_id=p_id)
   or (p.subject_kind='fault' and exists(select 1 from public.maintenance_requests f where f.id=p.subject_id and f.converted_to_work_order_id=p_id))
   or (p.subject_kind='checklist' and exists(select 1 from public.checklist_issue_context c join public.maintenance_requests f on f.id=c.fault_id where c.post_id=p.id and f.converted_to_work_order_id=p_id))
   or (p.subject_kind='report' and exists(select 1 from public.service_reports r where r.id=p.subject_id and r.work_order_id=p_id))
   or (p.subject_kind='request' and exists(select 1 from public.service_requests r where r.id=p.subject_id and r.generated_work_order_id=p_id))
  ))
 ))
$$;
revoke all on function public.coordination_context_matches(uuid,text,uuid) from public,anon,authenticated;

create function public.coordination_subject_title(p_kind text,p_id uuid)
returns text language sql stable security definer set search_path='' as $$
 select case p_kind
 when 'job' then (select title from public.work_orders where id=p_id)
 when 'inspection' then (select title from public.work_orders where id=p_id)
 when 'fault' then (select description from public.maintenance_requests where id=p_id)
 when 'asset' then (select name from public.assets where id=p_id)
 when 'checklist' then (select template_name from public.saved_checklists where id=p_id)
 when 'request' then (select title from public.service_requests where id=p_id)
 when 'report' then (select w.title from public.service_reports r join public.work_orders w on w.id=r.work_order_id where r.id=p_id)
 end
$$;
revoke all on function public.coordination_subject_title(text,uuid) from public,anon,authenticated;

alter function public.submit_operations_checklist(uuid,jsonb) rename to submit_operations_checklist_before_context;
create function public.submit_operations_checklist(p_operation uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare issue record; data jsonb; finding record; post uuid; actor public.profiles; asset public.assets; recipient record; urgency text; message text; safe text;
begin
 if not coalesce(public.operations_can_submit((p_data->>'asset_id')::uuid),false) then raise exception 'Access denied' using errcode='42501'; end if;
 data:=coalesce(p_data->'issues','{}');
 if jsonb_typeof(data)<>'object' then raise exception 'Invalid issue details'; end if;
 for issue in select * from jsonb_each(data) loop
  if jsonb_typeof(issue.value)<>'object' or coalesce(p_data->'responses'->>issue.key,'') not in ('monitor','alert','action')
   or coalesce(issue.value->>'urgency','normal') not in ('normal','urgent')
   or coalesce(issue.value->>'safe_to_operate','unknown') not in ('safe','unsafe','unknown')
   or length(coalesce(issue.value->>'message',''))>4000
   or not exists(select 1 from public.checklist_items where id::text=issue.key and template_id::text=p_data->>'template_id')
   then raise exception 'Invalid issue details'; end if;
 end loop;
 -- Same original payload reaches the replay ledger; no retry can replace a message.
 perform public.submit_operations_checklist_before_context(p_operation,p_data);
 select * into actor from public.profiles where id=auth.uid();
 select * into asset from public.assets where id=(p_data->>'asset_id')::uuid for share;
 for finding in select f.*,i.description_en,i.definition from public.checklist_findings f join public.checklist_items i on i.id=f.item_id
  where f.run_id=p_operation and not exists(select 1 from public.checklist_issue_context c where c.run_id=f.run_id and c.item_id=f.item_id) loop
  message:=coalesce(nullif(btrim(data->finding.item_id::text->>'message'),''),nullif(btrim(p_data->'notes'->>finding.item_id::text),''),finding.description_en);
  urgency:=case when coalesce((finding.definition->>'critical')::boolean,false) or data->finding.item_id::text->>'urgency'='urgent' then 'urgent' else 'normal' end;
  safe:=coalesce(data->finding.item_id::text->>'safe_to_operate','unknown');
  post:=gen_random_uuid();
  insert into public.coordination_posts(id,subject_kind,subject_id,asset_id,client_id,author_id,author_name,team,visibility,kind,body,attachments,request_payload)
   values(post,'checklist',p_operation,asset.id,asset.client_id,actor.id,coalesce(actor.full_name,''),public.coordination_user_team(actor.id),'shared','comment',
    left(finding.description_en||E'\n'||message,4000),'[]',jsonb_build_object('run_id',p_operation,'item_id',finding.item_id,'issue',data->finding.item_id::text));
  insert into public.checklist_issue_context(run_id,item_id,fault_id,post_id,message,urgency,safe_to_operate,photo_path,created_by)
   values(p_operation,finding.item_id,finding.fault_id,post,message,urgency,safe,nullif(p_data->'photos'->>finding.item_id::text,''),actor.id);
  update public.maintenance_requests set severity=urgency,description=left('Pre-operation: '||finding.description_en||E'\n'||message,4000) where id=finding.fault_id;
  for recipient in select p.id from public.profiles p where p.id<>actor.id and p.role in ('owner','client','client_admin')
   and public.coordination_post_reader(post,p.id) loop
   perform public.queue_activity(recipient.id,asset.id,'checklist_issue',p_operation,'checklist-issue:'||post::text,'Checklist issue reported','Review the finding, evidence and operator safety assessment.');
  end loop;
 end loop;
 return p_operation;
end $$;
revoke all on function public.submit_operations_checklist_before_context(uuid,jsonb),public.submit_operations_checklist(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.submit_operations_checklist(uuid,jsonb) to authenticated;

create or replace function public.coordination_thread(p_kind text,p_id uuid,p_before timestamptz default null,p_before_id uuid default null,p_focus uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare asset uuid; result jsonb; posts jsonb; focus_time timestamptz;
begin
 if not coalesce(public.coordination_subject_reader(p_kind,p_id,auth.uid()),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if (p_before is null)<>(p_before_id is null) then raise exception 'Invalid page cursor'; end if;
 if p_focus is not null then
  select created_at into focus_time from public.coordination_posts
  where id=p_focus and public.coordination_context_matches(id,p_kind,p_id) and public.coordination_post_reader(id,auth.uid());
  if not found then raise exception 'Message is unavailable' using errcode='42501'; end if;
 end if;
 asset:=public.coordination_subject_asset(p_kind,p_id);
 select jsonb_build_object('id',p_id,'subject_kind',p_kind,'asset_id',a.id,'asset_name',a.name,
  'title',public.coordination_subject_title(p_kind,p_id),
  'managed',coalesce((select managed_maintenance from public.work_orders where p_kind='job' and id=p_id),false),
  'can_post',public.coordination_can_post(p_kind,p_id),'team',public.coordination_user_team(auth.uid()))
 into result from public.assets a where a.id=asset;
 select coalesce(jsonb_agg(x.data order by x.created_at desc,x.id desc),'[]') into posts from (
  select p.id,p.created_at,(to_jsonb(p)-'request_payload'-'client_id')||jsonb_build_object(
   'issue_context',(select to_jsonb(c)-'created_by' from public.checklist_issue_context c where c.post_id=p.id),
   'mentions',coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'name',u.full_name) order by u.full_name,u.id)
    from public.coordination_mentions m join public.profiles u on u.id=m.user_id where m.post_id=p.id),'[]'),
   'acknowledgements',coalesce((select jsonb_agg(jsonb_build_object('user_id',k.user_id,'name',k.user_name,'created_at',k.created_at)
    order by k.created_at,k.user_id) from public.coordination_acknowledgements k where k.post_id=p.id),'[]')) as data
  from public.coordination_posts p where public.coordination_context_matches(p.id,p_kind,p_id)
   and public.coordination_post_reader(p.id,auth.uid())
   and (p_before is null or (p.created_at,p.id)<(p_before,p_before_id))
   and (p_focus is null or (p.created_at,p.id)<=(focus_time,p_focus))
  order by p.created_at desc,p.id desc limit 51
 ) x;
 return result||jsonb_build_object('posts',coalesce((select jsonb_agg(value order by ordinality)
  from jsonb_array_elements(posts) with ordinality where ordinality<=50),'[]'),'has_more',jsonb_array_length(posts)>50);
end $$;

create or replace function public.coordination_upload_allowed(p_name text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare pieces text[]:=string_to_array(p_name,'/');
begin
 if array_length(pieces,1)<>5 or pieces[1] not in ('job','fault','asset','checklist','inspection','request','report') or pieces[3]<>auth.uid()::text
  or pieces[5]!~'^[a-zA-Z0-9-]+\.(jpg|jpeg|png|webp)$' then return false; end if;
 perform pieces[4]::uuid;
 return coalesce(public.coordination_can_post(pieces[1],pieces[2]::uuid),false)
  and not exists(select 1 from public.coordination_posts where id=pieces[4]::uuid);
exception when invalid_text_representation then return false;
end $$;
