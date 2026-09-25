-- NEXT-011: native CAD amounts are separate from historical USD valuations.
-- Tax rates are reviewed inputs, never inferred from an issuer's address.
alter table public.invoices add column billing_currency text not null default 'USD'
 check(billing_currency in ('USD','CAD'));
alter table public.invoices add column billing_details jsonb;

create table public.organization_billing_profiles (
 organization_id uuid primary key references public.client_orgs(id) on delete cascade,
 details jsonb not null, updated_at timestamptz not null default now()
);
alter table public.organization_billing_profiles enable row level security;
create policy billing_profile_read on public.organization_billing_profiles for select to authenticated
 using(public.organization_has_permission(organization_id,'billing'));
grant select on public.organization_billing_profiles to authenticated;
grant all on public.organization_billing_profiles to service_role;

create function public.organization_billing_profile() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare org uuid:=public.active_organization_id();
begin
 if not public.organization_has_permission(org,'billing') then raise exception 'Billing permission required'; end if;
 return jsonb_build_object('organization_id',org,'details',(select details from public.organization_billing_profiles where organization_id=org),
 'can_manage',exists(select 1 from public.organization_memberships where organization_id=org
 and profile_id=auth.uid() and status='active' and 'company_owner'=any(roles)));
end $$;

create function public.validate_invoice_issuer(p_data jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare field text; result jsonb:='{}';
begin
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Complete the company invoice profile'; end if;
 foreach field in array array['legal_name','address','contact','registration_status','tax_registration'] loop
   if jsonb_typeof(p_data->field) is distinct from 'string' or length(p_data->>field)>1000 then
     raise exception 'Enter valid company invoice details';
   end if;
   result:=result||jsonb_build_object(field,btrim(p_data->>field));
 end loop;
 if result->>'legal_name'='' or result->>'address'='' or result->>'contact'='' or
   result->>'registration_status' not in ('registered','not_registered') or
   (result->>'registration_status'='registered' and result->>'tax_registration'='') then
   raise exception 'Complete the issuer name, address, contact and registration status';
 end if;
 return result;
end $$;

create function public.save_organization_billing_profile(p_organization uuid,p_details jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare org uuid:=public.active_organization_id();
begin
 if not exists(select 1 from public.organization_memberships where organization_id=org
 and profile_id=auth.uid() and status='active' and 'company_owner'=any(roles)) then raise exception 'Company Owner required'; end if;
 if p_organization is distinct from org then raise exception 'Company changed; reopen invoice setup'; end if;
 insert into public.organization_billing_profiles(organization_id,details)
 values(org,public.validate_invoice_issuer(p_details)) on conflict(organization_id)
 do update set details=excluded.details,updated_at=now();
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(org,auth.uid(),'billing_profile_updated','{}');
end $$;

create function public.validate_cad_invoice(d jsonb,h numeric) returns jsonb
language plpgsql immutable set search_path='' as $$
declare issuer jsonb; rate numeric; parts numeric; labour numeric; subtotal numeric; tax numeric:=0;
 lines jsonb:='[]'; line jsonb; n text; r numeric; b numeric; amount numeric; k text; issued date; due date;
begin
 if jsonb_typeof(d) is distinct from 'object' then raise exception 'Complete the CAD invoice details'; end if;
 issuer:=public.validate_invoice_issuer(d->'issuer');
 foreach k in array array['customer_name','customer_address','supply_description','supply_province','tax_treatment','tax_review_note','issue_date','due_date','payment_terms'] loop
  if jsonb_typeof(d->k) is distinct from 'string' or nullif(btrim(d->>k),'') is null or length(d->>k)>2000 then
   raise exception 'Complete customer, supply, tax review, dates and payment terms';
  end if;
 end loop;
 if d->>'supply_province' not in ('AB','BC','MB','NB','NL','NS','NT','NU','ON','PE','QC','SK','YT') then raise exception 'Select the reviewed province or territory of supply'; end if;
 if d->>'tax_treatment' not in ('taxable','zero_rated','exempt','not_registered') then raise exception 'Select the reviewed tax treatment'; end if;
 if d->>'issue_date' !~ '^\d{4}-\d{2}-\d{2}$' or d->>'due_date' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Use valid invoice dates'; end if;
 issued:=(d->>'issue_date')::date;due:=(d->>'due_date')::date;
 if not isfinite(issued) or not isfinite(due) or due<issued then raise exception 'Due date cannot precede invoice date'; end if;
 rate:=(d->>'labour_rate')::numeric; parts:=(d->>'parts_total')::numeric;
 if h is null or not(h>=0 and h<10000) or rate is null or not(rate>=0 and rate<1000000) or
 parts is null or not(parts>=0 and parts<10000000) or rate<>round(rate,2) or parts<>round(parts,2) then
 raise exception 'Enter finite nonnegative CAD charges with at most two decimals'; end if;
 labour:=round(h*rate,2);subtotal:=labour+parts;
 if jsonb_typeof(d->'taxes') is distinct from 'array' then raise exception 'Review the invoice tax lines'; end if;
 if jsonb_array_length(d->'taxes')>4 then raise exception 'Use at most four tax lines'; end if;
 if d->>'tax_treatment'='taxable' then
  if jsonb_array_length(d->'taxes')=0 or issuer->>'registration_status'<>'registered' then raise exception 'Taxable invoices require registration and reviewed tax lines'; end if;
 elsif jsonb_array_length(d->'taxes')<>0 then raise exception 'Zero-tax treatment cannot include tax charges'; end if;
 if (d->>'tax_treatment'='not_registered')<>(issuer->>'registration_status'='not_registered') then raise exception 'Tax treatment must agree with issuer registration'; end if;
 for line in select value from jsonb_array_elements(d->'taxes') loop
  n:=btrim(line->>'name');r:=(line->>'rate')::numeric;b:=(line->>'base')::numeric;
  if nullif(n,'') is null or length(n)>80 or r is null or not(r>0 and r<=100) or r<>round(r,4) or
    b is null or not(b>=0 and b<=subtotal) or b<>round(b,2) then raise exception 'Enter a tax name, valid rate and taxable base within the subtotal'; end if;
  if exists(select 1 from jsonb_array_elements(lines) l where lower(l->>'name')=lower(n)) then raise exception 'Tax names must be distinct'; end if;
  amount:=round(b*r/100,2);tax:=tax+amount;
  lines:=lines||jsonb_build_array(jsonb_build_object('name',n,'rate',r,'base',b,'amount',amount));
 end loop;
 if subtotal+tax>=10000000000 then raise exception 'Invoice total exceeds the supported amount'; end if;
 -- Whitelist snapshot data: ignore client-supplied totals and review identities.
 return jsonb_build_object('issuer',issuer,'customer_name',btrim(d->>'customer_name'),
 'customer_address',btrim(d->>'customer_address'),'supply_description',btrim(d->>'supply_description'),
 'supply_province',d->>'supply_province','tax_treatment',d->>'tax_treatment',
 'tax_review_note',btrim(d->>'tax_review_note'),'issue_date',issued,'due_date',due,
 'payment_terms',btrim(d->>'payment_terms'),'labour_rate',rate,'parts_total',parts,
 'labour_total',labour,'subtotal',subtotal,'taxes',lines,'tax_total',tax,'total',subtotal+tax,
 'reviewed_by',d->>'reviewed_by');
end $$;
create or replace function public.guard_invoice_closeout() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then
   if old.status<>'draft' then raise exception 'Issued invoices must be voided, not deleted'; end if;
   return old;
 end if;
 if tg_op='INSERT' and new.status<>'draft' then raise exception 'Create a draft before issuing'; end if;
 if tg_op='UPDATE' then
   if new.id<>old.id or new.work_order_id<>old.work_order_id or new.client_id<>old.client_id or new.invoice_number<>old.invoice_number or new.billing_currency<>old.billing_currency then
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
     if new.billing_currency='USD' then
       new.export_snapshot:=public.invoice_export_snapshot(new.work_order_id)||
         jsonb_build_object('parts',coalesce(old.export_snapshot->'parts','[]'::jsonb));
     end if;
   else new.sent_at:=old.sent_at; end if;
   if new.status='paid' and old.status='sent' then new.paid_at:=now(); else new.paid_at:=old.paid_at; end if;
 end if;
 if new.billing_currency='CAD' then
   if tg_op='INSERT' or old.status='draft' then
     new.billing_details:=public.validate_cad_invoice(new.billing_details,new.labour_hours);
     new.total_cad:=(new.billing_details->>'total')::numeric;
     new.billable_rate_usd:=null;new.labour_total_usd:=null;new.parts_total_usd:=null;
     new.consumables_total_usd:=null;new.subtotal_usd:=null;new.iva_pct:=null;
     new.iva_total_usd:=null;new.total_usd:=null;new.exchange_rate:=null;
     new.total_mxn:=null;new.cad_exchange_rate:=null;
   end if;
   return new;
 end if;
 if new.billing_details is not null then raise exception 'Legacy invoices cannot carry CAD charges'; end if;
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


create or replace function public.calculate_invoice_cad() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.billing_currency='USD' and (tg_op='INSERT' or old.status='draft') then
  new.total_cad:=round(new.total_usd*new.cad_exchange_rate,2);
 end if;
 return new;
end $$;

alter function public.organization_invoice_action(uuid,text,jsonb) rename to organization_invoice_action_legacy;
revoke all on function public.organization_invoice_action_legacy(uuid,text,jsonb) from public,anon,authenticated;
create function public.organization_invoice_action(p_work_order uuid,p_action text,p_data jsonb default '{}') returns uuid
language plpgsql security definer set search_path='' as $$
declare w public.work_orders;i public.invoices;issuer jsonb;d jsonb;result uuid;
begin
 if p_action not in ('generate_cad','revise_cad') then return public.organization_invoice_action_legacy(p_work_order,p_action,p_data); end if;
 select * into w from public.work_orders where id=p_work_order for update;
 if not public.organization_provider_access(w.id,'billing') or not exists(select 1 from public.organization_service_settings
 where organization_id=w.provider_organization_id and billing_enabled and company_purpose is distinct from 'fleet') then
 raise exception 'Organization billing capability and permission required'; end if;
 select * into i from public.invoices where work_order_id=w.id and status<>'void' for update;
 if p_action='generate_cad' and i.id is not null then return i.id; end if;
 if p_action='revise_cad' and (i.id is null or i.status<>'draft' or i.billing_currency<>'CAD') then raise exception 'Only a CAD draft can be revised'; end if;
 if w.status not in ('closed','invoiced') or not exists(select 1 from public.organization_work_report_state where work_order_id=w.id and approved_at is not null)
 then raise exception 'Approve the provider report before invoicing'; end if;
 select details into issuer from public.organization_billing_profiles where organization_id=w.provider_organization_id;
 d:=public.validate_cad_invoice(p_data||jsonb_build_object('issuer',issuer,'reviewed_by',auth.uid()),coalesce(w.labour_hours,0));
 if p_action='revise_cad' then
  update public.invoices set billing_details=d,labour_hours=coalesce(w.labour_hours,0) where id=i.id;
  result:=i.id;
 else
  result:=gen_random_uuid();
  insert into public.invoices(id,work_order_id,client_id,invoice_number,billing_currency,billing_details,labour_hours,export_snapshot)
  values(result,w.id,w.client_id,'INV-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(result::text,'-',''),1,12)),
  'CAD',d,coalesce(w.labour_hours,0),public.invoice_export_snapshot(w.id)||jsonb_build_object('parts','[]'::jsonb));
  update public.work_orders set status='invoiced' where id=w.id;
 end if;
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(w.provider_organization_id,auth.uid(),'invoice_'||p_action,jsonb_build_object('invoice_id',result,'work_order_id',w.id));
 return result;
end $$;
revoke all on function public.organization_billing_profile(),public.save_organization_billing_profile(uuid,jsonb),public.organization_invoice_action(uuid,text,jsonb) from public,anon;
grant execute on function public.organization_billing_profile(),public.save_organization_billing_profile(uuid,jsonb),public.organization_invoice_action(uuid,text,jsonb) to authenticated;
revoke all on function public.validate_invoice_issuer(jsonb),public.validate_cad_invoice(jsonb,numeric) from public,anon,authenticated;

-- The job projection already allows these readers. Make the same boundary
-- available to the invoice detail/export route, including issued void history.
drop policy organization_invoice_read_boundary on public.invoices;
create policy organization_invoice_read_boundary on public.invoices as restrictive for select to authenticated
 using(not public.is_organization_provider_work(work_order_id) or public.organization_provider_access(work_order_id,'billing') or
 (public.organization_customer_access(work_order_id,true) and (status in ('sent','paid') or (status='void' and sent_at is not null))));
create policy organization_invoice_read on public.invoices for select to authenticated
 using(public.organization_provider_access(work_order_id,'billing') or
 (public.organization_customer_access(work_order_id,true) and (status in ('sent','paid') or (status='void' and sent_at is not null))));
