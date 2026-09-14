-- Aggregate-only operational check. No record contents, tokens or cron commands.
begin read only;
select jsonb_build_object(
  'checked_at', now(),
  'tables_without_rls', (select coalesce(jsonb_agg(c.relname order by c.relname),'[]'::jsonb)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity),
  'public_buckets', (select coalesce(jsonb_agg(id order by id),'[]'::jsonb)
    from storage.buckets where public),
  'buckets_without_file_limits', (select coalesce(jsonb_agg(id order by id),'[]'::jsonb)
    from storage.buckets where file_size_limit is null or allowed_mime_types is null),
  'storage_object_count', (select count(*) from storage.objects),
  'push_schedule_active', coalesce((select active from cron.job where jobname='vortice-next-push'),false),
  'push_last_run_age_seconds', (select extract(epoch from now()-max(d.start_time))::bigint
    from cron.job_run_details d join cron.job j using(jobid) where j.jobname='vortice-next-push'),
  'push_schedule_failures_24h', (select count(*) from cron.job_run_details d join cron.job j using(jobid)
    where j.jobname='vortice-next-push' and d.start_time>now()-interval '24 hours' and d.status='failed'),
  'enabled_push_devices', (select count(*) from public.push_devices where enabled),
  'push_delivery_states', (select coalesce(jsonb_object_agg(status,total),'{}'::jsonb)
    from (select status,count(*) total from public.push_deliveries group by status) d),
  'overdue_push_deliveries', (select count(*) from public.push_deliveries
    where status='pending' and next_attempt<now()-interval '15 minutes'
      and (leased_until is null or leased_until<now())),
  'applied_migrations', (select coalesce(jsonb_agg(version order by version),'[]'::jsonb)
    from supabase_migrations.schema_migrations)
) as readiness;
commit;
