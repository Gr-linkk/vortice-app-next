-- NOW-016: atomic generation, issued snapshots and server-enforced correction.
alter table public.invoices add column export_snapshot jsonb;
alter table public.invoices add column void_reason text;
alter table public.invoices drop constraint invoices_work_order_id_key;
create unique index invoices_active_work_order on public.invoices(work_order_id) where status <> 'void';
drop policy "Owner full access" on public.invoices;
create policy "Owner reads invoices" on public.invoices for select to authenticated using(public.get_my_role()='owner');
create policy "Owner updates invoices" on public.invoices for update to authenticated using(public.get_my_role()='owner') with check(public.get_my_role()='owner');
create policy "Owner deletes drafts" on public.invoices for delete to authenticated using(public.get_my_role()='owner');

drop policy "Client reads own" on public.invoices;
drop policy "Org admin sees org invoices" on public.invoices;
create policy "Customers read issued invoices" on public.invoices for select to authenticated
using ((status in ('sent','paid') or (status='void' and sent_at is not null)) and
 (client_id=auth.uid() or exists(select 1 from public.profiles p join public.client_orgs o on o.id=p.org_id
 where p.id=auth.uid() and p.role='client_admin' and o.owner_profile_id=invoices.client_id)));

create function public.invoice_export_snapshot(p_work_order uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('client_name',p.full_name,'client_email',p.email,'client_phone',p.phone,
 'work_order_title',w.title,'asset_name',a.name,'asset_make_model',concat_ws(' ',a.make,a.model),
 'asset_serial_number',a.serial_number,'parts',coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at,t.id)
 from public.parts t where t.work_order_id=w.id),'[]'::jsonb))
 from public.work_orders w join public.profiles p on p.id=w.client_id join public.assets a on a.id=w.asset_id
 where w.id=p_work_order
$$;
revoke all on function public.invoice_export_snapshot(uuid) from public,anon,authenticated;

create function public.guard_invoice_closeout() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then
   if old.status<>'draft' then raise exception 'Issued invoices must be voided, not deleted'; end if;
   return old;
 end if;
 if tg_op='INSERT' and new.status<>'draft' then raise exception 'Create a draft before issuing'; end if;
 if tg_op='UPDATE' then
   if new.id<>old.id or new.work_order_id<>old.work_order_id or new.client_id<>old.client_id or new.invoice_number<>old.invoice_number then
     raise exception 'Invoice identity is immutable';
   end if;
   if old.status<>'draft' and
     (to_jsonb(new)-array['status','paid_at','updated_at','void_reason']) is distinct from
     (to_jsonb(old)-array['status','paid_at','updated_at','void_reason']) then
     raise exception 'Issued invoice details are frozen; void and create a correction';
   end if;
   if new.status<>old.status and not ((old.status='draft' and new.status in ('sent','void')) or
     (old.status='sent' and new.status in ('paid','void'))) then raise exception 'Invalid invoice transition'; end if;
   if new.status='void' and old.status<>'void' and nullif(btrim(new.void_reason),'') is null then
     raise exception 'A void reason is required';
   end if;
   if old.status='void' and new is distinct from old then raise exception 'Voided invoices are immutable'; end if;
   if new.status='sent' and old.status='draft' then
     new.sent_at:=now();
     -- Financial part lines were frozen at generation; issue freezes contact/asset labels.
     new.export_snapshot:=public.invoice_export_snapshot(new.work_order_id)||
       jsonb_build_object('parts',coalesce(old.export_snapshot->'parts','[]'::jsonb));
   else new.sent_at:=old.sent_at; end if;
   if new.status='paid' and old.status='sent' then new.paid_at:=now(); else new.paid_at:=old.paid_at; end if;
 end if;
 if tg_op='INSERT' or old.status='draft' then
   if new.labour_hours is null or new.labour_hours<0 or new.billable_rate_usd is null or new.billable_rate_usd<0
      or new.parts_total_usd is null or new.parts_total_usd<0 or new.consumables_total_usd is null or new.consumables_total_usd<0
      or new.exchange_rate is null or new.exchange_rate<=0 or new.iva_pct is null or new.iva_pct<0
      or new.labour_hours='NaN'::numeric or new.billable_rate_usd='NaN'::numeric or new.parts_total_usd='NaN'::numeric
      or new.consumables_total_usd='NaN'::numeric or new.exchange_rate='NaN'::numeric or new.iva_pct='NaN'::numeric then
     raise exception 'Invoice values must be finite and nonnegative with a positive exchange rate';
   end if;
   if tg_op='UPDATE' and (new.labour_hours is distinct from old.labour_hours or new.billable_rate_usd is distinct from old.billable_rate_usd) then
     new.labour_total_usd:=round(new.labour_hours*new.billable_rate_usd,2);
   end if;
   if new.labour_total_usd is null or new.labour_total_usd<0 or new.labour_total_usd='NaN'::numeric then raise exception 'Invalid labour total'; end if;
   new.subtotal_usd:=new.labour_total_usd+new.parts_total_usd+new.consumables_total_usd;
   new.iva_total_usd:=round(new.subtotal_usd*new.iva_pct/100,2);
   new.total_usd:=new.subtotal_usd+new.iva_total_usd;
   new.total_mxn:=round(new.total_usd*new.exchange_rate,2);
 end if;
 return new;
end $$;

-- Preserve available legacy labels/parts before enabling immutability. Historical
-- data cannot reconstruct an earlier export; this is an explicit upgrade snapshot.
update public.invoices i set export_snapshot=public.invoice_export_snapshot(i.work_order_id),
 sent_at=case when status in ('sent','paid') then coalesce(sent_at,created_at) else sent_at end;
create trigger invoice_closeout before insert or update or delete on public.invoices
for each row execute function public.guard_invoice_closeout();

create function public.generate_provider_invoice(p_work_order uuid,p_exchange_rate numeric) returns uuid
language plpgsql security definer set search_path='' as $$
declare w public.work_orders; existing uuid; result uuid:=gen_random_uuid(); hours numeric; labour numeric; rate numeric; parts numeric;
begin
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
 parts_total_usd,consumables_total_usd,exchange_rate,export_snapshot)
 values(result,w.id,w.client_id,'INV-'||to_char(now(),'YYYYMMDD')||'-'||upper(substring(replace(result::text,'-',''),1,12)),hours,rate,labour,round(parts,2),round(labour*0.05,2),p_exchange_rate,
 public.invoice_export_snapshot(w.id));
 update public.work_orders set status='invoiced' where id=w.id;
 return result;
end $$;
revoke all on function public.generate_provider_invoice(uuid,numeric) from public,anon;
grant execute on function public.generate_provider_invoice(uuid,numeric) to authenticated;

create function public.change_invoice_status(p_invoice uuid,p_status text,p_reason text default null) returns void
language plpgsql security invoker set search_path='' as $$
declare i public.invoices;
begin
 if public.get_my_role() is distinct from 'owner' then raise exception 'Owner required'; end if;
 select * into i from public.invoices where id=p_invoice for update;
 if not found then raise exception 'Invoice unavailable'; end if;
 if i.status=p_status then return; end if;
 update public.invoices set status=p_status,void_reason=case when p_status='void' then p_reason else void_reason end where id=p_invoice;
end $$;
revoke all on function public.change_invoice_status(uuid,text,text) from public,anon;
grant execute on function public.change_invoice_status(uuid,text,text) to authenticated;
