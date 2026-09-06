-- NOW-011: private request evidence, including existing public URL references.
update storage.buckets set public=false where id='service-request-photos';
drop policy if exists "Public can view service request photos" on storage.objects;
drop policy if exists "Authenticated users can upload service request photos" on storage.objects;

create function public.request_photo_access(p_name text,p_write boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select p_name ~ '^[0-9a-fA-F-]{36}/[^/]+$' and exists(
  select 1 from public.service_requests r join public.profiles p on p.id=auth.uid()
  where r.id::text=split_part(p_name,'/',1) and (
   (not p_write and p.role in ('owner','employee')) or
   (p.role in ('client','client_admin') and (r.client_id=p.id or exists(
    select 1 from public.client_orgs o where o.id=p.org_id and o.owner_profile_id=r.client_id)))))
$$;
revoke all on function public.request_photo_access(text,boolean) from public,anon;
grant execute on function public.request_photo_access(text,boolean) to authenticated;
create policy request_photo_read on storage.objects for select to authenticated
 using(bucket_id='service-request-photos' and public.request_photo_access(name));
create policy request_photo_upload on storage.objects for insert to authenticated
 with check(bucket_id='service-request-photos' and public.request_photo_access(name,true));
-- Do not rewrite stored URLs: clients normalize authorized legacy URLs to paths.
-- No public download or arbitrary external image URL is used by the new client.
