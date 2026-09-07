-- Preserve original request/report identity across interrupted media uploads.
alter table public.closeout_operations add column completion_payload jsonb;
alter table public.service_requests add column submission_id uuid;
alter table public.service_requests add column submitted_by uuid references public.profiles(id);
alter table public.service_requests add column evidence_pending boolean not null default false;
alter table public.service_reports add column submission_id uuid;
alter table public.service_reports add column submitted_by uuid references public.profiles(id);
alter table public.service_reports add column evidence_pending boolean not null default false;
update storage.buckets set file_size_limit=10485760,allowed_mime_types=array['image/jpeg','image/png','image/webp']
 where id='service-report-photos';
update storage.buckets set file_size_limit=2097152,allowed_mime_types=array['image/png'] where id='signatures';

create function public.begin_request_submission(p_operation uuid,p_request uuid,p_data jsonb,p_expected_submission uuid default null) returns void
language plpgsql security definer set search_path='' as $$
declare r public.service_requests; input public.service_requests; receipt public.closeout_operations;
 payload jsonb:=jsonb_build_object('request',p_request,'data',p_data,'expected',p_expected_submission);
begin
 select * into input from jsonb_populate_record(null::public.service_requests,p_data);
 if public.get_my_role() not in ('client','client_admin') or auth.uid() is null or
   not(input.client_id=auth.uid() or exists(select 1 from public.profiles p join public.client_orgs o on o.id=p.org_id
     where p.id=auth.uid() and o.owner_profile_id=input.client_id)) then raise exception 'Client access required'; end if;
 if input.asset_id is not null and not exists(select 1 from public.assets where id=input.asset_id and client_id=input.client_id) then raise exception 'Asset unavailable'; end if;
 if nullif(btrim(input.description),'') is null or nullif(btrim(input.contact_phone_or_whatsapp),'') is null or
   (input.asset_id is null and nullif(btrim(input.other_asset_name),'') is null) then raise exception 'Complete the request details'; end if;
 if input.engine_hours<0 or input.engine_hours='NaN'::numeric then raise exception 'Invalid engine hours'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
   if receipt.actor_id<>auth.uid() or receipt.kind<>'request_submission' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
   return;
 end if;
 select * into r from public.service_requests where id=p_request for update;
 if found then
   if r.submitted_by is distinct from auth.uid() or r.client_id<>input.client_id or r.submission_id is distinct from p_expected_submission or not r.evidence_pending then
     raise exception 'Request already submitted or changed. Open the original request';
   end if;
   -- Staff may already have converted the request while its photos were pending.
   -- Evidence correction is allowed, but cannot silently change its work scope.
   if r.status<>'new' and (r.asset_id is distinct from input.asset_id or r.description is distinct from input.description
     or r.title is distinct from input.title or r.request_type is distinct from input.request_type) then raise exception 'Handled request details are frozen'; end if;
   update public.service_requests set title=input.title,description=input.description,asset_id=input.asset_id,
     other_asset_name=input.other_asset_name,request_type=input.request_type,engine_hours=input.engine_hours,
     contact_phone_or_whatsapp=input.contact_phone_or_whatsapp,submission_id=p_operation,evidence_pending=true where id=p_request;
 else
   insert into public.service_requests(id,client_id,asset_id,title,description,other_asset_name,contact_phone_or_whatsapp,request_type,engine_hours,
     submission_id,submitted_by,evidence_pending)
   values(p_request,input.client_id,input.asset_id,input.title,input.description,input.other_asset_name,input.contact_phone_or_whatsapp,
     input.request_type,input.engine_hours,p_operation,auth.uid(),true);
 end if;
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'request_submission',payload,p_request);
end $$;

create function public.provider_report_author(p_work_order uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w where w.id=p_work_order and not w.managed_maintenance and
   (public.get_my_role()='owner' or (public.get_my_role()='employee' and (w.assigned_to=auth.uid() or exists(
     select 1 from public.work_order_assignments a where a.work_order_id=w.id and a.profile_id=auth.uid())))))
$$;

create function public.begin_report_submission(p_operation uuid,p_report uuid,p_data jsonb,p_expected_submission uuid default null) returns void
language plpgsql security definer set search_path='' as $$
declare r public.service_reports; input public.service_reports; receipt public.closeout_operations;
 payload jsonb:=jsonb_build_object('report',p_report,'data',p_data,'expected',p_expected_submission);
begin
 select * into input from jsonb_populate_record(null::public.service_reports,p_data);
 if not public.provider_report_author(input.work_order_id) then raise exception 'Assigned provider author required'; end if;
 if nullif(btrim(coalesce(input.complaint,'')||coalesce(input.cause,'')||coalesce(input.correction,'')||coalesce(input.comments,'')),'') is null then
   raise exception 'Report text required';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_report::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
   if receipt.actor_id<>auth.uid() or receipt.kind<>'report_submission' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
   return;
 end if;
 select * into r from public.service_reports where id=p_report for update;
 if found then
   if r.submitted_by is distinct from auth.uid() or r.work_order_id<>input.work_order_id or r.submission_id is distinct from p_expected_submission or not r.evidence_pending then
     raise exception 'Report already submitted or changed. Open the original report';
   end if;
   update public.service_reports set complaint=input.complaint,cause=input.cause,correction=input.correction,collateral=input.collateral,
     comments=input.comments,submission_id=p_operation,evidence_pending=true,updated_at=now() where id=p_report;
 else
   insert into public.service_reports(id,work_order_id,complaint,cause,correction,collateral,comments,submission_id,submitted_by,evidence_pending)
   values(p_report,input.work_order_id,input.complaint,input.cause,input.correction,input.collateral,input.comments,p_operation,auth.uid(),true);
 end if;
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'report_submission',payload,p_report);
end $$;

create function public.finish_evidence_submission(p_operation uuid,p_kind text,p_record uuid,p_photos text[],p_signature text default null) returns void
language plpgsql security definer set search_path='' as $$
declare path text; r public.service_requests; report public.service_reports; position integer:=0; receipt public.closeout_operations;
 completion jsonb:=jsonb_build_object('photos',p_photos,'signature',p_signature);
begin
 if p_photos is null or cardinality(p_photos)>30 then raise exception 'Invalid photo list'; end if;
 select * into receipt from public.closeout_operations where id=p_operation;
 if not found or receipt.actor_id<>auth.uid() or receipt.result<>p_record or receipt.kind<>p_kind||'_submission' then raise exception 'Submission unavailable'; end if;
 if p_kind='request' then
   select * into r from public.service_requests where id=p_record for update;
   if not found or not public.request_photo_access(p_record::text||'/check.jpg',true) or r.submission_id<>p_operation then raise exception 'Request changed or access revoked'; end if;
 elsif p_kind='report' then
   select * into report from public.service_reports where id=p_record for update;
   if not found or not public.provider_report_author(report.work_order_id) or report.submission_id<>p_operation then raise exception 'Report changed or access revoked'; end if;
 else raise exception 'Unsupported submission'; end if;
 select * into receipt from public.closeout_operations where id=p_operation for update;
 if receipt.completion_payload is not null then
   if receipt.completion_payload<>completion then raise exception 'Completed evidence is immutable'; end if;
   return;
 end if;
 foreach path in array p_photos loop
   if path not like p_record::text||'/'||p_operation::text||'/%' or path like '%..%' or not exists(select 1 from storage.objects
     where bucket_id=case when p_kind='request' then 'service-request-photos' else 'service-report-photos' end and name=path) then
     raise exception 'Photo upload is incomplete';
   end if;
 end loop;
 if p_kind='request' then
   update public.service_requests set photo_urls=p_photos,evidence_pending=false where id=p_record;
 else
   if p_signature is not null and (p_signature not like report.work_order_id::text||'_'||p_operation::text||'_%'
     or not exists(select 1 from storage.objects where bucket_id='signatures' and name=p_signature)) then raise exception 'Signature upload is incomplete'; end if;
   foreach path in array p_photos loop
     insert into public.service_report_photos(id,service_report_id,photo_url,sort_order,uploaded_by)
       values(md5(p_record::text||path)::uuid,p_record,path,position,auth.uid()) on conflict(id) do nothing;
     position:=position+1;
   end loop;
   update public.service_reports set tech_signature_url=p_signature,
     signed_at=case when p_signature is null then null else coalesce(signed_at,receipt.created_at) end,
     evidence_pending=false where id=p_record;
 end if;
 update public.closeout_operations set completion_payload=completion where id=p_operation;
end $$;

-- Request paths now include immutable submission IDs. Retain legacy two-part paths.
create or replace function public.request_photo_access(p_name text,p_write boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select p_name ~ '^[0-9a-fA-F-]{36}/[^/]+(/[^/]+)?$' and p_name not like '%..%' and exists(
  select 1 from public.service_requests r join public.profiles p on p.id=auth.uid()
  where r.id::text=split_part(p_name,'/',1) and (
   (not p_write and p.role in ('owner','employee')) or
   (p.role in ('client','client_admin') and (r.client_id=p.id or exists(
    select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=r.client_id)))))
$$;

create function public.require_completed_provider_evidence() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not new.managed_maintenance and new.status in ('closed','invoiced') and old.status is distinct from new.status and
   exists(select 1 from public.service_reports where work_order_id=new.id and evidence_pending) then
   raise exception 'Finish pending report evidence before completing or invoicing work';
 end if;
 return new;
end $$;
create trigger provider_evidence_completion before update of status on public.work_orders for each row execute function public.require_completed_provider_evidence();
revoke all on function public.begin_request_submission(uuid,uuid,jsonb,uuid),public.begin_report_submission(uuid,uuid,jsonb,uuid),
 public.provider_report_author(uuid),public.finish_evidence_submission(uuid,text,uuid,text[],text) from public,anon;
grant execute on function public.begin_request_submission(uuid,uuid,jsonb,uuid),public.begin_report_submission(uuid,uuid,jsonb,uuid),
 public.provider_report_author(uuid),public.finish_evidence_submission(uuid,text,uuid,text[],text) to authenticated;
