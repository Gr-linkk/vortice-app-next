-- Discussion authorization follows explicit organization membership, including
-- revocation of previously legacy accounts. Unmigrated fixtures retain legacy rules.
alter function public.coordination_asset_viewer(uuid,uuid) rename to coordination_asset_viewer_before_membership_context;
create function public.coordination_asset_viewer(p_asset uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from public.organization_memberships m
  where m.profile_id=p_user and m.organization_id=public.organization_for_asset(p_asset))
 then public.organization_has_permission(public.organization_for_asset(p_asset),'member',p_user)
 else public.coordination_asset_viewer_before_membership_context(p_asset,p_user) end
$$;
revoke all on function public.coordination_asset_viewer_before_membership_context(uuid,uuid),public.coordination_asset_viewer(uuid,uuid) from public,anon,authenticated;

alter function public.coordination_subject_reader(text,uuid,uuid) rename to coordination_subject_reader_before_membership_context;
create function public.coordination_subject_reader(p_kind text,p_id uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select case
 when not exists(select 1 from public.organization_memberships m where m.profile_id=p_user
  and m.organization_id=public.organization_for_asset(public.coordination_subject_asset(p_kind,p_id)))
 then public.coordination_subject_reader_before_membership_context(p_kind,p_id,p_user)
 when not public.coordination_asset_viewer(public.coordination_subject_asset(p_kind,p_id),p_user) then false
 when p_kind in ('asset','fault') then true
 when p_kind='job' then exists(select 1 from public.work_orders w where w.id=p_id and (
  public.organization_has_permission(public.organization_for_asset(w.asset_id),'approve_work',p_user)
  or (public.organization_has_permission(public.organization_for_asset(w.asset_id),'work_assigned',p_user)
   and (w.assigned_to=p_user or (not w.managed_maintenance and exists(select 1 from public.work_order_assignments x where x.work_order_id=w.id and x.profile_id=p_user))))))
 when p_kind='inspection' then exists(select 1 from public.work_orders w where w.id=p_id and w.job_type='inspection' and public.coordination_subject_reader('job',w.id,p_user))
 when p_kind='report' then exists(select 1 from public.service_reports r where r.id=p_id and public.coordination_subject_reader('job',r.work_order_id,p_user))
 when p_kind='checklist' then exists(select 1 from public.saved_checklists s where s.id=p_id
  and (s.checklist_type='operations' or public.organization_has_permission(public.organization_for_asset(s.asset_id),'work_assigned',p_user))
  and (s.work_order_id is null or public.coordination_subject_reader('job',s.work_order_id,p_user)))
 when p_kind='request' then public.organization_has_permission(public.organization_for_asset(public.coordination_subject_asset(p_kind,p_id)),'assets_manage',p_user)
 else false end
$$;
revoke all on function public.coordination_subject_reader_before_membership_context(text,uuid,uuid),public.coordination_subject_reader(text,uuid,uuid) from public,anon,authenticated;

create function public.coordination_issue_manager(p_asset uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.coordination_asset_viewer(p_asset,p_user) and case when exists(
  select 1 from public.organization_memberships m where m.organization_id=public.organization_for_asset(p_asset) and m.profile_id=p_user)
 then public.organization_has_permission(public.organization_for_asset(p_asset),'approve_work',p_user)
 else exists(select 1 from public.profiles p where p.id=p_user and p.role in ('owner','client','client_admin')) end
$$;
revoke all on function public.coordination_issue_manager(uuid,uuid) from public,anon,authenticated;

create or replace function public.submit_operations_checklist(p_operation uuid,p_data jsonb)
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
  for recipient in select p.id from public.profiles p where p.id<>actor.id and public.coordination_issue_manager(asset.id,p.id)
   and public.coordination_post_reader(post,p.id) loop
   perform public.queue_activity(recipient.id,asset.id,'checklist_issue',p_operation,'checklist-issue:'||post::text,'Checklist issue reported','Review the finding, evidence and operator safety assessment.');
  end loop;
 end loop;
 return p_operation;
end $$;
