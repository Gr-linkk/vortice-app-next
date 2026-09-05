-- NOW-003 prerequisite: permissions cannot trust caller-editable signup metadata.
-- Existing profiles are untouched. Roles/membership come from a valid invite code
-- or server-managed app metadata; ordinary free signup always creates a client.
alter table public.org_codes drop constraint org_codes_intended_role_check;
alter table public.org_codes add constraint org_codes_intended_role_check check (
  intended_role in ('employee','client','operator','client_admin','client_mechanic','client_operator'));
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_code text; v_invite public.org_codes; v_role text := 'client';
  v_org uuid; v_tier integer := 0; v_owner uuid; v_capability text;
begin
  v_code := upper(nullif(btrim(new.raw_user_meta_data->>'org_code_used'),''));
  if v_code is not null then
    select * into v_invite from public.org_codes where code=v_code for update;
    if not found then raise exception 'invalidOrgCode'; end if;
    if v_invite.expires_at is not null and v_invite.expires_at<=now() then raise exception 'orgCodeExpired'; end if;
    if coalesce(v_invite.single_use,true) and
      coalesce(v_invite.use_count,0)>=coalesce(v_invite.max_uses,1) then raise exception 'orgCodeUsed'; end if;
    v_role := coalesce(v_invite.intended_role,'client');
    v_org := v_invite.org_id;
    v_capability := case when v_role='client_mechanic' then 'pm_checklists'
      when v_role in ('operator','client_operator') then 'operational_checklists' end;
    if v_capability is not null then
      select owner_profile_id into v_owner from public.client_orgs where id=v_org;
      if v_owner is null or not exists(select 1 from public.client_capabilities
        where client_id=v_owner and capability_key=v_capability and enabled) then
        raise exception 'Invite capability is not enabled';
      end if;
    end if;
  else
    -- raw_app_meta_data is managed by the auth admin API, unlike user metadata.
    v_role := coalesce(nullif(new.raw_app_meta_data->>'role',''),'client');
    v_org := nullif(new.raw_app_meta_data->>'org_id','')::uuid;
    v_tier := coalesce(nullif(new.raw_app_meta_data->>'subscription_tier','')::integer,0);
  end if;
  if v_role not in ('owner','employee','client','client_admin','client_mechanic','operator','client_operator') then
    raise exception 'Invalid assigned role'; end if;
  insert into public.profiles(id,email,full_name,role,org_id,org_code_used,
    preferred_language,subscription_tier,created_at,updated_at)
  values(new.id,new.email,coalesce(nullif(new.raw_user_meta_data->>'full_name',''),new.email,''),
    v_role,v_org,v_code,
    case when new.raw_user_meta_data->>'preferred_language'='es' then 'es' else 'en' end,
    v_tier,now(),now());
  if v_code is not null then
    update public.org_codes set use_count=coalesce(use_count,0)+1 where id=v_invite.id;
  end if;
  return new;
end $$;
revoke all on function public.handle_new_user() from public,anon,authenticated;
