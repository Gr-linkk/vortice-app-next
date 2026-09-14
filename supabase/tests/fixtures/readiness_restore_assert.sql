-- Only scripts/test-database.sh --restore-drill loads this in a disposable DB.
begin;
do $$ begin
  if (select count(*) from public.invoices where
      work_order_id='a0160000-0000-4000-8000-000000000020') <> 2 then
    raise exception 'Restored invoice correction history is incomplete';
  end if;
  if not exists(select 1 from public.invoices where
      work_order_id='a0160000-0000-4000-8000-000000000020' and status='void'
      and export_snapshot->'parts'->0->>'description'='Original filter') then
    raise exception 'Restored original invoice snapshot is incomplete';
  end if;
  if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relkind='r' and not c.relrowsecurity) then
    raise exception 'Restored public table is missing RLS';
  end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0160000-0000-4000-8000-000000000003',true);
do $$ begin
  if exists(select 1 from public.invoices) then
    raise exception 'Restored other-company invoice isolation failed';
  end if;
end $$;
select set_config('request.jwt.claim.sub','a0160000-0000-4000-8000-000000000002',true);
do $$ begin
  if (select count(*) from public.invoices) <> 1 or
      exists(select 1 from public.invoices where status <> 'void') then
    raise exception 'Restored customer draft privacy or void history failed';
  end if;
end $$;
rollback;
