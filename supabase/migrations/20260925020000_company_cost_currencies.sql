-- NEXT-011: preserve the denomination of every saved cost. Existing money is
-- USD; new Canadian work may use CAD without reinterpreting earlier records.
alter table public.organization_service_settings add column cost_currency text not null default 'USD' check(cost_currency in ('USD','CAD'));
alter table public.organization_service_settings alter column cost_currency set default 'CAD';
alter table public.work_orders add column cost_currency text not null default 'USD' check(cost_currency in ('USD','CAD'));
alter table public.work_orders alter column cost_currency drop default;
alter table public.parts_inventory add column cost_currency text not null default 'USD' check(cost_currency in ('USD','CAD'));
alter table public.parts_inventory alter column cost_currency drop default;
alter table public.parts add column cost_currency text not null default 'USD' check(cost_currency in ('USD','CAD'));
alter table public.parts alter column cost_currency drop default;

create function public.company_cost_currency(p_client uuid) returns text
language sql stable security definer set search_path='' as $$
 select coalesce((select s.cost_currency from public.client_orgs o join public.organization_service_settings s on s.organization_id=o.id where o.owner_profile_id=p_client),'USD')
$$;
revoke all on function public.company_cost_currency(uuid) from public,anon,authenticated;
create function public.configure_organization_cost_currency(p_currency text) returns void
language plpgsql security definer set search_path='' as $$
declare org uuid:=public.active_organization_id();
begin
 if not exists(select 1 from public.organization_memberships where organization_id=org and profile_id=auth.uid() and status='active' and 'company_owner'=any(roles)) then raise exception 'Company Owner required'; end if;
 if p_currency is null or p_currency not in ('CAD','USD') then raise exception 'Choose CAD or USD'; end if;
 update public.organization_service_settings set cost_currency=p_currency,updated_at=now() where organization_id=org;
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(org,auth.uid(),'cost_currency_changed',jsonb_build_object('currency',p_currency));
end $$;
revoke all on function public.configure_organization_cost_currency(text) from public,anon;
grant execute on function public.configure_organization_cost_currency(text) to authenticated;

create function public.guard_cost_currency() returns trigger
language plpgsql security definer set search_path='' as $$
declare expected text; stock_currency text;
begin
 if tg_op='UPDATE' and new.cost_currency is distinct from old.cost_currency then raise exception 'Saved cost currency is immutable; create a separate record'; end if;
 if tg_table_name='work_orders' then
  if tg_op='INSERT' and new.cost_currency is null then
   new.cost_currency:=case when new.provider_organization_id is not null then
    (select cost_currency from public.organization_service_settings where organization_id=new.provider_organization_id)
    when new.managed_maintenance and new.generation_kind='recurring' then public.company_cost_currency(new.client_id) else 'USD' end;
  end if;
 elsif tg_table_name='parts_inventory' then
  if tg_op='INSERT' then new.cost_currency:=coalesce(new.cost_currency,'USD'); end if;
 else
  select cost_currency into expected from public.work_orders where id=new.work_order_id;
  if tg_op='INSERT' then new.cost_currency:=coalesce(new.cost_currency,expected); end if;
  if new.cost_currency is distinct from expected then raise exception 'Part cost currency must match the work order'; end if;
  if new.stock_requirement_id is not null then
   select s.cost_currency into stock_currency from public.job_part_requirements r join public.parts_inventory s on s.id=r.stock_id where r.id=new.stock_requirement_id;
   if stock_currency is distinct from expected then raise exception 'Stock and work order currencies differ; use stock recorded in the job currency'; end if;
  end if;
 end if;
 return new;
end $$;
create trigger work_cost_currency before insert or update on public.work_orders for each row execute function public.guard_cost_currency();
create trigger stock_cost_currency before insert or update on public.parts_inventory for each row execute function public.guard_cost_currency();
create trigger part_cost_currency before insert or update on public.parts for each row execute function public.guard_cost_currency();

create function public.guard_stock_currency_link() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.stock_id is not null and exists(select 1 from public.parts_inventory s join public.work_orders w on w.id=new.work_order_id where s.id=new.stock_id and s.cost_currency<>w.cost_currency) then
 raise exception 'Stock and work order currencies differ; use stock recorded in the job currency'; end if;
 return new;
end $$;
create trigger stock_currency_link before insert or update on public.job_part_requirements for each row execute function public.guard_stock_currency_link();

-- Pin the currency alongside the existing immutable approval receipt/history.
create function public.snapshot_cost_currency() returns trigger
language plpgsql security definer set search_path='' as $$
declare currency text;
begin
 if tg_table_name='saved_checklists' then
  select cost_currency into currency from public.work_orders where id=new.work_order_id;
  if currency is not null then new.snapshot:=new.snapshot||jsonb_build_object('cost_currency',currency); end if;
 else
  select cost_currency into currency from public.work_orders where id=new.job_id;
  if currency is not null and (new.detail ? 'total_cost' or new.detail ? 'hourly_cost' or new.detail ? 'unit_cost') then
   new.detail:=new.detail||jsonb_build_object('cost_currency',currency);
  end if;
 end if;
 return new;
end $$;
create trigger receipt_cost_currency before insert on public.saved_checklists for each row execute function public.snapshot_cost_currency();
create trigger history_cost_currency before insert on public.asset_history_entries for each row execute function public.snapshot_cost_currency();

-- Keep the existing checked creation/replay and stock ledger implementations.
-- Fail the migration if the reviewed adaptation point does not match.
do $$ declare definition text; marker text;
begin
 select replace(pg_get_functiondef('public.create_maintenance_job(uuid,jsonb)'::regprocedure),chr(13),'') into definition;
 marker:='engine_id,checklist_template_id,job_type,status,scheduled_date,billable_rate,wage_rate,managed_maintenance)';
 if strpos(definition,marker)=0 then raise exception 'Maintenance currency columns did not match'; end if;
 definition:=replace(definition,marker,'engine_id,checklist_template_id,job_type,status,scheduled_date,billable_rate,wage_rate,managed_maintenance,cost_currency)');
 marker:='nullif(p_data->>''due_date'','''')::date,0,0,true);';
 if strpos(definition,marker)=0 then raise exception 'Maintenance currency values did not match'; end if;
 definition:=replace(definition,marker,'nullif(p_data->>''due_date'','''')::date,0,0,true,coalesce(p_data->>''cost_currency'',''USD''));');
 execute definition;
 select replace(pg_get_functiondef('public.parts_change(uuid,uuid,text,jsonb)'::regprocedure),chr(13),'') into definition;
 marker:='last_unit_cost,average_unit_cost)';
 if strpos(definition,marker)=0 then raise exception 'Stock currency columns did not match'; end if;
 definition:=replace(definition,marker,'last_unit_cost,average_unit_cost,cost_currency)');
 marker:='''ea''),0,0,cost,cost);';
 if strpos(definition,marker)=0 then raise exception 'Stock currency values did not match'; end if;
 definition:=replace(definition,marker,'''ea''),0,0,cost,cost,coalesce(p_data->>''cost_currency'',''USD''));');
 execute definition;
end $$;

alter function public.maintenance_asset_context(uuid) rename to maintenance_asset_context_before_currency;
revoke all on function public.maintenance_asset_context_before_currency(uuid) from public,anon,authenticated;
create function public.maintenance_asset_context(p_asset uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare data jsonb;
begin
 data:=public.maintenance_asset_context_before_currency(p_asset);
 return data||jsonb_build_object('cost_currency',public.company_cost_currency((data->'asset'->>'client_id')::uuid));
end $$;
alter function public.maintenance_jobs(uuid,uuid) rename to maintenance_jobs_before_currency;
revoke all on function public.maintenance_jobs_before_currency(uuid,uuid) from public,anon,authenticated;
create function public.maintenance_jobs(p_job uuid default null,p_asset uuid default null) returns setof jsonb language sql stable security definer set search_path='' as $$
 select data||jsonb_build_object('cost_currency',w.cost_currency)
 from public.maintenance_jobs_before_currency(p_job,p_asset) data join public.work_orders w on w.id=(data->>'id')::uuid
$$;
alter function public.parts_workspace(uuid) rename to parts_workspace_before_currency;
revoke all on function public.parts_workspace_before_currency(uuid) from public,anon,authenticated;
create function public.parts_workspace(p_job uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare data jsonb;currency text;
begin
 data:=public.parts_workspace_before_currency(p_job);
 if p_job is not null then select cost_currency into currency from public.work_orders where id=p_job;
 else currency:=public.company_cost_currency(public.parts_scope(p_job)); end if;
 return data||jsonb_build_object('cost_currency',currency);
end $$;
revoke all on function public.maintenance_asset_context(uuid),public.maintenance_jobs(uuid,uuid),public.parts_workspace(uuid) from public,anon;
grant execute on function public.maintenance_asset_context(uuid),public.maintenance_jobs(uuid,uuid),public.parts_workspace(uuid) to authenticated;

-- NEXT-011: group currencies without conversion; keep USD fields compatible for old readers.
create or replace function public.equipment_report(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; cutoff timestamptz := least(p_to, now());
begin
 if auth.uid() is null or not (exists(select 1 from public.profiles
   where id=auth.uid() and role in ('owner','client','client_admin')) or public.organization_has_permission(public.active_organization_id(),'planning')) then
   raise exception 'Access denied';
 end if;
 if p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to)
   or p_from>=cutoff or p_to-p_from>interval '366 days' then
   raise exception 'Select a past or current period of at most 366 days';
 end if;
 with assets as materialized (
   select a.id,a.name,a.location,a.client_id,a.created_at from public.assets a
   where public.maintenance_can_manage_asset(a.id)
 ), receipts as (
   select w.id,w.asset_id,w.title,s.snapshot,s.submitted_at
   from public.work_orders w join assets a on a.id=w.asset_id
   join lateral (select sc.snapshot,sc.submitted_at from public.saved_checklists sc
     where sc.work_order_id=w.id and sc.snapshot->>'managed_maintenance'='true'
     order by sc.submitted_at desc,sc.id desc limit 1) s on true
   where w.managed_maintenance and public.maintenance_can_read_job(w.id)
     and (public.get_my_role()='owner' or w.client_id=a.client_id)
     and s.submitted_at>=p_from and s.submitted_at<cutoff
 ), internal as (
   select r.*,
     round(coalesce(l.hours,0)*coalesce((snapshot->>'hourly_cost')::numeric,0),2) labour,
     round(coalesce(p.cost,0),2) parts,
     (case when coalesce(l.hours,0)>0 and coalesce((snapshot->>'hourly_cost')::numeric,0)=0
       then 1 else 0 end + coalesce(p.unpriced,0) +
       case when coalesce(l.hours,0)=0 and jsonb_array_length(coalesce(snapshot->'parts','[]'))=0 then 1 else 0 end)::int gaps
   from receipts r
   left join lateral (select sum(extract(epoch from
     (x->>'stopped_at')::timestamptz-(x->>'started_at')::timestamptz)/3600) hours
     from jsonb_array_elements(coalesce(snapshot->'labour','[]')) x) l on true
   left join lateral (select sum((x->>'quantity')::numeric*(x->>'unit_cost')::numeric) cost,
     count(*) filter(where coalesce((x->>'unit_cost')::numeric,0)=0 and (x->>'quantity')::numeric>0) unpriced
     from jsonb_array_elements(coalesce(snapshot->'parts','[]')) x) p on true
 ), missing_receipts as (
   select w.id,w.asset_id,w.title,j.approved_at occurred_at
   from public.work_orders w join assets a on a.id=w.asset_id
   join public.maintenance_job_records j on j.id=w.id
   where w.managed_maintenance and public.maintenance_can_read_job(w.id)
     and (public.get_my_role()='owner' or w.client_id=a.client_id)
     and j.approved_at>=p_from and j.approved_at<cutoff
     and not exists(select 1 from public.saved_checklists s
       where s.work_order_id=w.id and s.snapshot->>'managed_maintenance'='true')
 ), invoices as (
   select i.id,w.asset_id,i.invoice_number title,i.sent_at occurred_at,case when i.billing_currency='CAD' then i.total_cad else i.total_usd end cost,i.billing_currency currency
   from public.invoices i join public.work_orders w on w.id=i.work_order_id join assets a on a.id=w.asset_id
   where not w.managed_maintenance and i.status in ('sent','paid')
     and i.sent_at>=p_from and i.sent_at<cutoff
     and (public.get_my_role()='owner' or public.organization_customer_access(w.id,true) or i.client_id=auth.uid() or exists(
       select 1 from public.profiles p join public.client_orgs o on o.id=p.org_id
       where p.id=auth.uid() and p.role='client_admin' and o.owner_profile_id=i.client_id))
 ), uncosted as (
   select w.id,w.asset_id,
     case when public.coordination_subject_reader('job',w.id,auth.uid()) then w.title else '' end title,
     w.completed_at occurred_at
   from public.work_orders w join assets a on a.id=w.asset_id
   where not w.managed_maintenance and w.completed_at>=p_from and w.completed_at<cutoff
   and public.can_read_provider_report(w.id)
   and (public.get_my_role()='owner' or w.client_id=a.client_id)
   and w.status in ('completed','invoiced','closed')
   and not exists(select 1 from public.invoices i where i.work_order_id=w.id and i.status in ('sent','paid'))
 ), event_points as (
   -- Legacy events at identical timestamps have no reliable within-time order.
   select e.asset_id,e.created_at,(array_agg(e.id order by e.id))[1] id,
     case when count(distinct e.to_state)=1 then min(e.to_state) else 'unknown' end to_state,
     case when count(*)=1 then min(e.note) else '' end note
   from public.asset_availability_events e join assets a on a.id=e.asset_id
   where e.created_at<cutoff
   group by e.asset_id,e.created_at
 ), events as (
   select e.*,lead(e.created_at,1,cutoff) over(partition by e.asset_id order by e.created_at) until_at
   from event_points e
 ), spans as (
   select e.asset_id,e.id,e.note,e.to_state,e.created_at,
     greatest(e.created_at,p_from) from_at,least(e.until_at,cutoff) until_at
   from events e where e.until_at>p_from
 ), faults as (
   select f.id,f.asset_id,f.description,f.created_at,
     lower(btrim(regexp_replace(f.description,'\s+',' ','g'))) match_key
   from public.maintenance_requests f join assets a on a.id=f.asset_id
   where f.created_at>=p_from and f.created_at<cutoff and f.status<>'dismissed'
 ), repeats as (
   select asset_id,min(description) description,count(*) count,
     jsonb_agg(id order by created_at,id) ids
   from faults group by asset_id,match_key having count(*)>1
 ), records as (
   select asset_id,id,'internal' kind,title,submitted_at occurred_at,
     labour,parts,0::numeric outside,0::numeric hours,gaps,coalesce(snapshot->>'cost_currency','USD') currency from internal
   union all select asset_id,id,'invoice',title,occurred_at,0,0,coalesce(cost,0),0,
     case when coalesce(cost,0)=0 then 1 else 0 end,currency from invoices
   union all select asset_id,id,'internal_missing',title,occurred_at,0,0,0,0,1,null from missing_receipts
   union all select asset_id,id,'uncosted',title,occurred_at,0,0,0,0,1,null from uncosted
   union all select asset_id,id,'downtime',note,from_at,0,0,0,
     extract(epoch from until_at-from_at)/3600,0,null from spans
     where to_state in ('out_of_service','under_maintenance') and until_at>from_at
   union all select asset_id,id,'fault',description,created_at,0,0,0,0,0,null from faults
 )
 select jsonb_build_object('generated_at',now(),'from',p_from,'to',cutoff,'currency','USD',
   'preferred_currency',coalesce((select cost_currency from public.organization_service_settings where organization_id=public.active_organization_id()),'USD'),
   'currencies',coalesce((select jsonb_agg(currency order by currency) from (select distinct currency from records where currency is not null) currencies),'["USD"]'),
   'assets',coalesce(jsonb_agg(item order by (item->>'total')::numeric desc,item->>'name',item->>'id'),'[]'))
 into result from (
   select jsonb_build_object('id',a.id,'name',a.name,'location',a.location,
     'labour',coalesce(r.labour,0),'parts',coalesce(r.parts,0),'outside',coalesce(r.outside,0),
     'total',coalesce(r.labour,0)+coalesce(r.parts,0)+coalesce(r.outside,0),
     'unavailable_hours',coalesce(r.hours,0),'cost_gaps',coalesce(r.gaps,0),
     'unknown_hours',greatest(0,extract(epoch from cutoff-greatest(p_from,coalesce(a.created_at,p_from)))/3600-
       coalesce((select sum(extract(epoch from until_at-greatest(from_at,coalesce(a.created_at,p_from)))/3600)
       from spans where asset_id=a.id and to_state<>'unknown'
         and until_at>greatest(from_at,coalesce(a.created_at,p_from))),0)),
     'fault_count',(select count(*) from faults where asset_id=a.id),
     'repeats',coalesce((select jsonb_agg(jsonb_build_object('description',description,'count',count,'ids',ids)
       order by count desc,description) from repeats where asset_id=a.id),'[]'),
     'records',coalesce(r.rows,'[]'),
     'amounts_by_currency',coalesce((select jsonb_object_agg(currency,totals) from (
       select currency,jsonb_build_object('labour',sum(labour),'parts',sum(parts),'outside',sum(outside),'total',sum(labour+parts+outside)) totals
       from records where asset_id=a.id and currency is not null group by currency
     ) money),'{}')) item
   from assets a left join lateral (
     select sum(labour) filter(where currency='USD') labour,sum(parts) filter(where currency='USD') parts,sum(outside) filter(where currency='USD') outside,sum(hours) hours,sum(gaps) gaps,
       jsonb_agg(to_jsonb(records)-'asset_id' order by occurred_at desc,id) rows
     from records where asset_id=a.id
   ) r on true
 ) report;
 return result;
end $$;
revoke all on function public.equipment_report(timestamptz,timestamptz) from public,anon;
grant execute on function public.equipment_report(timestamptz,timestamptz) to authenticated;
