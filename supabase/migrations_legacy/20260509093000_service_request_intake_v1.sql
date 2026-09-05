alter table public.service_requests
  add column if not exists other_asset_name text,
  add column if not exists contact_phone_or_whatsapp text not null default '',
  add column if not exists photo_urls text[] not null default '{}';

comment on column public.service_requests.other_asset_name is
  'Client-entered asset label when the requested machine is not in their asset list.';
comment on column public.service_requests.contact_phone_or_whatsapp is
  'Best callback number or WhatsApp contact supplied with the request.';
comment on column public.service_requests.photo_urls is
  'Public photo URLs attached to the service request intake packet.';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'service-request-photos',
  'service-request-photos',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Authenticated users can upload service request photos"
  on storage.objects;
create policy "Authenticated users can upload service request photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'service-request-photos'
    and auth.uid() is not null
  );

drop policy if exists "Public can view service request photos"
  on storage.objects;
create policy "Public can view service request photos"
  on storage.objects for select to public
  using (bucket_id = 'service-request-photos');
