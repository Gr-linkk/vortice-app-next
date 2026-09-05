-- Harden org-code signup so invites create the intended client-team profile.
-- Org codes are the invite into a client org; they must set both role and org_id.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_code text;
  v_org_id uuid;
  v_intended_role text;
  v_role text;
  v_subscription_tier integer;
begin
  v_org_code := upper(nullif(new.raw_user_meta_data->>'org_code_used', ''));

  if v_org_code is not null then
    select oc.org_id, oc.intended_role
      into v_org_id, v_intended_role
    from public.org_codes oc
    where oc.code = v_org_code
    limit 1;
  end if;

  v_role := coalesce(
    v_intended_role,
    nullif(new.raw_user_meta_data->>'role', ''),
    'client'
  );

  v_subscription_tier := coalesce(
    nullif(new.raw_user_meta_data->>'subscription_tier', '')::integer,
    0
  );

  insert into public.profiles (
    id,
    email,
    full_name,
    role,
    org_id,
    org_code_used,
    preferred_language,
    subscription_tier,
    created_at,
    updated_at
  )
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), new.email, ''),
    v_role,
    coalesce(v_org_id, nullif(new.raw_user_meta_data->>'org_id', '')::uuid),
    v_org_code,
    coalesce(nullif(new.raw_user_meta_data->>'preferred_language', ''), 'en'),
    v_subscription_tier,
    now(),
    now()
  )
  on conflict (id) do update set
    email = excluded.email,
    full_name = excluded.full_name,
    role = excluded.role,
    org_id = excluded.org_id,
    org_code_used = excluded.org_code_used,
    preferred_language = excluded.preferred_language,
    subscription_tier = excluded.subscription_tier,
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
