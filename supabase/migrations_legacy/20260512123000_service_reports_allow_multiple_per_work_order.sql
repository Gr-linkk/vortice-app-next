-- Allow multiple service reports per work order.
-- Earlier app code upserted on work_order_id, so some environments may have
-- a legacy unique constraint/index there. Drop only unique single-column
-- work_order_id constraints/indexes, then keep a normal lookup index.

do $$
declare
  work_order_attnum smallint;
  constraint_record record;
  index_record record;
begin
  select attnum
    into work_order_attnum
    from pg_attribute
   where attrelid = 'public.service_reports'::regclass
     and attname = 'work_order_id'
     and not attisdropped;

  if work_order_attnum is null then
    return;
  end if;

  for constraint_record in
    select conname
      from pg_constraint
     where conrelid = 'public.service_reports'::regclass
       and contype = 'u'
       and conkey = array[work_order_attnum]
  loop
    execute format(
      'alter table public.service_reports drop constraint if exists %I',
      constraint_record.conname
    );
  end loop;

  for index_record in
    select indexrelid::regclass::text as index_name
      from pg_index
     where indrelid = 'public.service_reports'::regclass
       and indisunique
       and not indisprimary
       and array(select k from unnest(indkey) as k) = array[work_order_attnum]
  loop
    execute format('drop index if exists %s', index_record.index_name);
  end loop;
end $$;

create index if not exists service_reports_work_order_id_idx
  on public.service_reports(work_order_id);
