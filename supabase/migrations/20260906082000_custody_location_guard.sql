-- Preserve the explicit transfer journal when legacy asset forms write location.
create function public.guard_custody_location() returns trigger
language plpgsql security definer set search_path='' as $$
declare recorded_site text;
begin
 if new.location is distinct from old.location then
  select site into recorded_site from public.asset_custody where asset_id=old.id;
  if found and new.location is distinct from recorded_site then
   raise exception 'Use Record transfer to change the site of an asset with custody history';
  end if;
 end if;
 return new;
end $$;
revoke all on function public.guard_custody_location() from public,anon,authenticated;
create trigger guard_custody_location before update of location on public.assets
 for each row execute function public.guard_custody_location();
