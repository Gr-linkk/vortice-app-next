-- Minimal Supabase-owned objects for testing our entire baseline on vanilla PG.
-- This file is local-test scaffolding, never a hosted migration.
do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema auth;
create schema storage;
create schema extensions;
create table auth.users (
 id uuid primary key, email text,
 raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}'
);
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
create function auth.role() returns text language sql stable as $$
 select nullif(current_setting('request.jwt.claim.role',true),'')
$$;
create table storage.buckets(id text primary key,name text,public boolean,
 file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key,bucket_id text,name text);
alter table storage.objects enable row level security;
grant select,insert,update,delete on storage.objects to authenticated,anon,service_role;
grant usage on schema public,auth,storage,extensions to authenticated,anon,service_role;
alter default privileges in schema public grant all on tables to authenticated,anon,service_role;
set search_path=public,extensions;
