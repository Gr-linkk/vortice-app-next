-- Read-only operational summary. No device tokens, user IDs or secret values.
select jsonb_build_object(
  'schedule_active', coalesce((select active from cron.job where jobname='vortice-next-push'), false),
  'last_schedule_status', (select d.status from cron.job_run_details d
    join cron.job j using(jobid) where j.jobname='vortice-next-push'
    order by d.start_time desc limit 1),
  'enabled_devices', (select count(*) from public.push_devices where enabled),
  'delivery_states', (select jsonb_object_agg(status, total)
    from (select status,count(*) total from public.push_deliveries group by status) s)
) as summary;
