do $$ begin
 if exists(select 1 from public.now008_report_upgrade_snapshot old
  left join public.service_reports s on s.id=old.id where (to_jsonb(s)-'managed_job_id') is distinct from old.original)
  then raise exception 'Report content or timestamps changed during upgrade'; end if;
 if (select count(*) from public.asset_history_entries)<>(select original_count from public.now008_history_upgrade_snapshot)
  then raise exception 'Upgrade created artificial history entries'; end if;
 if not exists(select 1 from public.service_reports where work_order_id='a0080000-0000-4000-8000-000000000030'
  and managed_job_id=work_order_id) then raise exception 'Managed report was not bound'; end if;
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000001',false);
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000030',3,gen_random_uuid(),'submit',
 '{"diagnosis":"Test diagnosis","repair":"Submitted after upgrade"}');
select public.change_maintenance_job('a0080000-0000-4000-8000-000000000030',4,gen_random_uuid(),'approve','{}');
insert into public.service_reports(work_order_id,complaint) values
 ('a0080000-0000-4000-8000-000000000020','Provider follow-up after upgrade');
reset role;
do $$ begin
 if (select count(*) from public.service_reports where work_order_id='a0080000-0000-4000-8000-000000000020')<>2
  then raise exception 'Provider follow-up failed'; end if;
 if (select count(*) from public.service_reports where work_order_id='a0080000-0000-4000-8000-000000000030')<>1
  then raise exception 'Managed report duplicated'; end if;
 if not exists(select 1 from public.saved_checklists where work_order_id='a0080000-0000-4000-8000-000000000030'
  and snapshot->'report'->>'repair'='Submitted after upgrade') then raise exception 'Approval failed'; end if;
end $$;
