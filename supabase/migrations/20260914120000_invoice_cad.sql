-- NEXT-010: CAD conversion alongside the canonical USD and saved MXN amounts.
-- No historical backfill: an issued invoice must keep its original valuation.
alter table public.invoices add column cad_exchange_rate numeric(12,6);
alter table public.invoices add column total_cad numeric(12,2);
alter table public.invoices add constraint invoice_cad_rate_valid check
 (cad_exchange_rate is null or (cad_exchange_rate > 0 and cad_exchange_rate < 1000000));

create function public.calculate_invoice_cad() returns trigger
language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' or old.status='draft' then
   new.total_cad:=round(new.total_usd*new.cad_exchange_rate,2);
 end if;
 return new;
end $$;
-- PostgreSQL runs same-event triggers alphabetically: canonical totals first.
create trigger invoice_closeout_cad before insert or update on public.invoices
 for each row execute function public.calculate_invoice_cad();

create function public.generate_provider_invoice(p_work_order uuid,p_exchange_rate numeric,p_cad_exchange_rate numeric) returns uuid
language plpgsql security definer set search_path='' as $$
declare w public.work_orders; existing uuid; result uuid:=gen_random_uuid(); hours numeric; labour numeric; rate numeric; parts numeric;
begin
 if public.is_organization_provider_work(p_work_order) then raise exception 'Use organization billing'; end if;
 if p_cad_exchange_rate is null or p_cad_exchange_rate<=0 or p_cad_exchange_rate>=1000000 then raise exception 'Invalid CAD exchange rate'; end if;
 if public.get_my_role() is distinct from 'owner' then raise exception 'Owner required'; end if;
 select * into w from public.work_orders where id=p_work_order for update;
 if not found then raise exception 'Work order unavailable'; end if;
 select id into existing from public.invoices where work_order_id=w.id and status<>'void';
 if existing is not null then
   update public.work_orders set status='invoiced' where id=w.id;
   return existing;
 end if;
 if w.status not in ('closed','invoiced') or w.managed_maintenance then
   raise exception 'Only completed provider work can be invoiced';
 end if;
 if exists(select 1 from public.service_reports where work_order_id=w.id and evidence_pending) then
   raise exception 'Finish pending report evidence before generating an invoice';
 end if;
 if p_exchange_rate is null or p_exchange_rate<=0 or p_exchange_rate='NaN'::numeric then raise exception 'Invalid exchange rate'; end if;
 if exists(select 1 from public.work_order_assignments where work_order_id=w.id and role='tech' and hours_logged is not null) then
   select coalesce(sum(coalesce(hours_logged,0)),0),coalesce(sum(coalesce(hours_logged,0)*coalesce(billable_rate,60)),0)
   into hours,labour from public.work_order_assignments where work_order_id=w.id and role='tech';
   rate:=case when hours>0 then labour/hours else 60 end;
 else hours:=coalesce(w.labour_hours,0); rate:=coalesce(w.billable_rate,60); labour:=hours*rate; end if;
 select coalesce(sum(quantity*unit_cost*(1+coalesce(markup_pct,0)/100)),0) into parts from public.parts where work_order_id=w.id;
 insert into public.invoices(id,work_order_id,client_id,invoice_number,labour_hours,billable_rate_usd,labour_total_usd,
 parts_total_usd,consumables_total_usd,exchange_rate,cad_exchange_rate,export_snapshot)
 values(result,w.id,w.client_id,'INV-'||to_char(now(),'YYYYMMDD')||'-'||upper(substring(replace(result::text,'-',''),1,12)),hours,rate,labour,round(parts,2),round(labour*0.05,2),p_exchange_rate,p_cad_exchange_rate,
 public.invoice_export_snapshot(w.id));
 update public.work_orders set status='invoiced' where id=w.id;
 return result;
end $$;
revoke all on function public.generate_provider_invoice(uuid,numeric,numeric) from public,anon;
grant execute on function public.generate_provider_invoice(uuid,numeric,numeric) to authenticated;

create or replace function public.organization_invoice_action(p_work_order uuid,p_action text,p_data jsonb default '{}') returns uuid
language plpgsql security definer set search_path='' as $$
declare w public.work_orders; i public.invoices; result uuid; rate numeric; part_total numeric;
begin
 select * into w from public.work_orders where id=p_work_order for update;
 if not public.organization_provider_access(w.id,'billing') or not exists(select 1 from public.organization_service_settings where organization_id=w.provider_organization_id and billing_enabled)
 then raise exception 'Organization billing capability and permission required'; end if;
 select * into i from public.invoices where work_order_id=w.id and status<>'void' for update;
 if p_action='generate' then
 if i.id is not null then return i.id; end if;
 if w.status<>'closed' or not exists(select 1 from public.organization_work_report_state where work_order_id=w.id and approved_at is not null)
 then raise exception 'Approve the provider report before invoicing'; end if;
 rate:=(p_data->>'billable_rate')::numeric;part_total:=coalesce((p_data->>'parts_total')::numeric,0);
 if rate is null or rate<0 or rate>=1000000 or part_total<0 or part_total>=10000000 then raise exception 'Enter valid customer charges'; end if;
 result:=gen_random_uuid();
 insert into public.invoices(id,work_order_id,client_id,invoice_number,labour_hours,billable_rate_usd,labour_total_usd,parts_total_usd,consumables_total_usd,exchange_rate,cad_exchange_rate,iva_pct,export_snapshot)
 values(result,w.id,w.client_id,'INV-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(result::text,'-',''),1,12)),coalesce(w.labour_hours,0),rate,
 round(coalesce(w.labour_hours,0)*rate,2),part_total,0,coalesce((p_data->>'exchange_rate')::numeric,1),(p_data->>'cad_exchange_rate')::numeric,coalesce((p_data->>'tax_percent')::numeric,0),
 jsonb_build_object('parts','[]'::jsonb));
 update public.work_orders set status='invoiced' where id=w.id;
 elsif p_action in ('sent','paid','void') then
 if i.id is null then raise exception 'Generate the invoice first'; end if;
 if i.status<>p_action then update public.invoices set status=p_action,void_reason=case when p_action='void' then p_data->>'reason' else void_reason end where id=i.id; end if;
 result:=i.id;
 else raise exception 'Unknown invoice action'; end if;
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(w.provider_organization_id,auth.uid(),'invoice_'||p_action,jsonb_build_object('invoice_id',result,'work_order_id',w.id));
 return result;
end $$;

