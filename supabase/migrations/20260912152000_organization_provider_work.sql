-- Organization provider work uses the existing Work Order, report, parts,
-- assignment and invoice identities. The existing provider lane remains intact.
alter table public.work_orders add column organization_relationship_id uuid references public.organization_relationships(id);
alter table public.work_orders add column provider_organization_id uuid references public.client_orgs(id);
alter table public.work_orders add column customer_organization_id uuid references public.client_orgs(id);
alter table public.work_orders add constraint organization_provider_scope check
 ((provider_organization_id is null and customer_organization_id is null and organization_relationship_id is null)
 or (provider_organization_id is not null and customer_organization_id is not null and organization_relationship_id is not null and not managed_maintenance));
create table public.organization_service_settings (
 organization_id uuid primary key references public.client_orgs(id) on delete cascade,
 connection_code text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,16)),
 provider_enabled boolean not null default false,billing_enabled boolean not null default false,updated_at timestamptz not null default now()
);
insert into public.organization_service_settings(organization_id) select id from public.client_orgs;
create function public.initialize_organization_service_settings() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.organization_service_settings(organization_id) values(new.id); return new; end $$;
create trigger organization_service_settings_init after insert on public.client_orgs for each row execute function public.initialize_organization_service_settings();
-- A version/snapshot beside the canonical provider report, not another report
-- or order system. Working report content lives in service_reports.
create table public.organization_work_report_state (
 work_order_id uuid primary key references public.work_orders(id), revision integer not null default 0,
 report_id uuid references public.service_reports(id), published_report jsonb,review_note text,
 approved_by uuid references public.profiles(id),approved_at timestamptz
);
alter table public.organization_service_settings enable row level security;
alter table public.organization_work_report_state enable row level security;
revoke all on public.organization_service_settings,public.organization_work_report_state from public,anon,authenticated;
grant all on public.organization_service_settings,public.organization_work_report_state to service_role;

create function public.organization_provider_access(p_work_order uuid,p_permission text default 'read') returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w join public.organization_relationships r on r.id=w.organization_relationship_id
 where w.id=p_work_order and r.status='active' and w.provider_organization_id=public.active_organization_id()
 and public.organization_has_permission(w.provider_organization_id,'member') and
 case when p_permission='manage' then public.organization_has_permission(w.provider_organization_id,'review_work')
 when p_permission='billing' then public.organization_has_permission(w.provider_organization_id,'billing')
 when p_permission='work' then public.organization_has_permission(w.provider_organization_id,'review_work') or
 (public.organization_has_permission(w.provider_organization_id,'work_assigned') and (w.assigned_to=auth.uid() or exists(
 select 1 from public.work_order_assignments x where x.work_order_id=w.id and x.profile_id=auth.uid())))
 else public.organization_has_permission(w.provider_organization_id,'review_work') or public.organization_has_permission(w.provider_organization_id,'billing')
 or (public.organization_has_permission(w.provider_organization_id,'work_assigned') and (w.assigned_to=auth.uid() or exists(
 select 1 from public.work_order_assignments x where x.work_order_id=w.id and x.profile_id=auth.uid()))) end)
$$;
create function public.organization_customer_access(p_work_order uuid,p_billing boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w where w.id=p_work_order and w.customer_organization_id=public.active_organization_id()
 and public.organization_has_permission(w.customer_organization_id,'member') and
 case when p_billing then public.organization_has_permission(w.customer_organization_id,'billing')
 else public.organization_has_permission(w.customer_organization_id,'review_work') or w.created_by=auth.uid() end)
$$;
create function public.is_organization_provider_work(p_work_order uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders where id=p_work_order and provider_organization_id is not null)
$$;
create function public.organization_service_configuration() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare org uuid:=public.active_organization_id();
begin
 if not public.organization_has_permission(org,'member') then raise exception 'Organization access denied'; end if;
 return jsonb_build_object('organization_id',org,'can_admin',public.organization_has_permission(org,'team_admin'),'settings',(select to_jsonb(s) from public.organization_service_settings s where s.organization_id=org),
 'can_manage',exists(select 1 from public.organization_memberships where organization_id=org and profile_id=auth.uid() and status='active' and 'company_owner'=any(roles)),
 'relationships',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('provider_name',p.name,'client_name',c.name) order by r.created_at desc)
 from public.organization_relationships r join public.client_orgs p on p.id=r.provider_organization_id join public.client_orgs c on c.id=r.client_organization_id
 where org in (r.provider_organization_id,r.client_organization_id)),'[]'));
end $$;
create function public.configure_organization_services(p_provider_enabled boolean,p_billing_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
declare org uuid:=public.active_organization_id();
begin
 if not exists(select 1 from public.organization_memberships where organization_id=org and profile_id=auth.uid() and status='active' and 'company_owner'=any(roles))
 then raise exception 'Company Owner required'; end if;
 update public.organization_service_settings set provider_enabled=p_provider_enabled,billing_enabled=p_billing_enabled,updated_at=now() where organization_id=org;
 insert into public.organization_membership_events(organization_id,actor_id,action,detail)
 values(org,auth.uid(),'service_settings_changed',jsonb_build_object('provider_enabled',p_provider_enabled,'billing_enabled',p_billing_enabled));
end $$;
create function public.propose_organization_customer(p_connection_code text) returns uuid language plpgsql security definer set search_path='' as $$
declare customer uuid; org uuid:=public.active_organization_id();
begin
 if not public.organization_has_permission(org,'team_admin') or not exists(select 1 from public.organization_service_settings where organization_id=org and provider_enabled)
 then raise exception 'Provider work and team administration required'; end if;
 select organization_id into customer from public.organization_service_settings where connection_code=upper(btrim(p_connection_code));
 if customer is null then raise exception 'Company code not found'; end if;
 return public.set_organization_relationship(org,customer,'propose');
end $$;
create function public.organization_service_request_context() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare org uuid:=public.active_organization_id();
begin
 if not public.organization_has_permission(org,'issues') then raise exception 'Organization access denied'; end if;
 return jsonb_build_object('providers',coalesce((select jsonb_agg(jsonb_build_object('relationship_id',r.id,'name',o.name) order by o.name)
 from public.organization_relationships r join public.client_orgs o on o.id=r.provider_organization_id join public.organization_service_settings s on s.organization_id=o.id
 where r.client_organization_id=org and r.status='active' and s.provider_enabled),'[]'),
 'assets',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name) order by a.name) from public.assets a
 where public.organization_asset_permission(a.id,'member')),'[]'));
end $$;

create function public.organization_work_order_context(p_work_order uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare w public.work_orders; provider boolean:=public.organization_provider_access(p_work_order);customer boolean:=public.organization_customer_access(p_work_order);state public.organization_work_report_state;
begin
 if not provider and not customer then raise exception 'Organization work access denied'; end if;
 select * into w from public.work_orders where id=p_work_order;
 select * into state from public.organization_work_report_state where work_order_id=w.id;
 return jsonb_build_object('work_order',case when provider then to_jsonb(w) else to_jsonb(w)-array['notes_internal','billable_rate','wage_rate','labour_hours','hours_at_start','hours_at_end'] end,
 'revision',state.revision,'asset_name',(select name from public.assets where id=w.asset_id),
 'provider_name',(select name from public.client_orgs where id=w.provider_organization_id),'customer_name',(select name from public.client_orgs where id=w.customer_organization_id),
 'is_provider',provider,'can_work',public.organization_provider_access(w.id,'work'),'can_manage',public.organization_provider_access(w.id,'manage'),
 'can_bill',public.organization_provider_access(w.id,'billing') and exists(select 1 from public.organization_service_settings where organization_id=w.provider_organization_id and billing_enabled),
 'assignee_name',(select full_name from public.profiles where id=w.assigned_to),
 'people',case when public.organization_provider_access(w.id,'manage') then coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name) order by p.full_name)
 from public.organization_memberships m join public.profiles p on p.id=m.profile_id where m.organization_id=w.provider_organization_id and m.status='active'
 and public.organization_has_permission(m.organization_id,'work_assigned',m.profile_id)),'[]') else '[]' end,
 'report',case when provider then (select jsonb_build_object('id',s.id,'diagnosis',s.cause,'repair',s.correction,'notes',s.comments) from public.service_reports s where s.id=state.report_id)
 else state.published_report end,
 'review_note',case when provider then state.review_note else null end,
 'labour_hours',case when provider then w.labour_hours else null end,
 'parts',case when provider then coalesce((select jsonb_agg(to_jsonb(p)) from public.parts p where p.work_order_id=w.id),'[]') else null end,
 'invoice',case when (provider and public.organization_provider_access(w.id,'billing')) or public.organization_customer_access(w.id,true)
 then (select to_jsonb(i) from public.invoices i where i.work_order_id=w.id and i.status<>'void' and (provider or i.status in ('sent','paid')) limit 1) else null end);
end $$;
create function public.organization_work_orders() returns setof jsonb language sql stable security definer set search_path='' as $$
 select public.organization_work_order_context(w.id)->'work_order' from public.work_orders w
 where w.provider_organization_id is not null and (public.organization_provider_access(w.id) or public.organization_customer_access(w.id))
 order by w.updated_at desc,w.id
$$;
create function public.request_organization_work(p_operation uuid,p_relationship uuid,p_asset uuid,p_title text,p_note text default '') returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.organization_relationships; receipt public.closeout_operations; payload jsonb;
begin
 select * into r from public.organization_relationships where id=p_relationship for share;
 if r.id is null or r.status<>'active' or r.client_organization_id is distinct from public.active_organization_id()
 or not public.organization_has_permission(r.client_organization_id,'issues') or not public.organization_asset_permission(p_asset,'member')
 or not exists(select 1 from public.organization_service_settings where organization_id=r.provider_organization_id and provider_enabled)
 then raise exception 'Service relationship is not available'; end if;
 if length(btrim(p_title)) not between 3 and 160 or length(btrim(p_note))>4000 then raise exception 'Enter a work title and request details'; end if;
 payload:=jsonb_build_object('relationship_id',p_relationship,'asset_id',p_asset,'title',btrim(p_title),'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
 if receipt.actor_id<>auth.uid() or receipt.kind<>'organization_request' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
 return receipt.result; end if;
 insert into public.work_orders(id,organization_relationship_id,provider_organization_id,customer_organization_id,asset_id,client_id,created_by,job_type,title,description,status)
 values(p_operation,r.id,r.provider_organization_id,r.client_organization_id,p_asset,(select client_id from public.assets where id=p_asset),auth.uid(),'repair',btrim(p_title),btrim(p_note),'draft');
 insert into public.organization_work_report_state(work_order_id) values(p_operation);
 insert into public.service_requests(id,client_id,asset_id,request_type,urgency,title,description,status,generated_work_order_id,handled_by,handled_at,submitted_by,evidence_pending)
 values(p_operation,(select client_id from public.assets where id=p_asset),p_asset,'other_issue','normal',btrim(p_title),
 coalesce(nullif(btrim(p_note),''),btrim(p_title)),'resolved',p_operation,auth.uid(),now(),auth.uid(),false);
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'organization_request',payload,p_operation);
 return p_operation;
end $$;

create function public.change_organization_work(p_work_order uuid,p_revision integer,p_operation uuid,p_action text,p_data jsonb default '{}') returns void
language plpgsql security definer set search_path='' as $$
declare w public.work_orders; state public.organization_work_report_state; receipt public.closeout_operations; payload jsonb; manager boolean; report uuid; hours numeric; meter numeric;
begin
 select * into w from public.work_orders where id=p_work_order for update;
 if w.id is null or not public.organization_provider_access(w.id,'work') then raise exception 'Organization work access denied'; end if;
 select * into state from public.organization_work_report_state where work_order_id=w.id for update;
 payload:=jsonb_build_object('work_order',w.id,'action',p_action,'data',p_data);
 perform pg_advisory_xact_lock(hashtextextended(p_operation::text,0));
 select * into receipt from public.closeout_operations where id=p_operation;
 if found then
 if receipt.actor_id<>auth.uid() or receipt.kind<>'organization_work' or receipt.payload<>payload then raise exception 'Retry input differs'; end if;
 return; end if;
 if state.revision is distinct from p_revision then raise exception 'Work order changed; refresh'; end if;
 manager:=public.organization_provider_access(w.id,'manage');
 if p_action='assign' then
 if not manager or w.status not in ('draft','assigned','in_progress') then raise exception 'Assignment is not allowed'; end if;
 if not public.organization_has_permission(w.provider_organization_id,'work_assigned',(p_data->>'assigned_to')::uuid) then raise exception 'Choose a provider teammate'; end if;
 update public.work_orders set assigned_to=(p_data->>'assigned_to')::uuid,status='assigned' where id=w.id;
 insert into public.work_order_assignments(work_order_id,profile_id,role) values(w.id,(p_data->>'assigned_to')::uuid,'tech') on conflict(work_order_id,profile_id) do nothing;
 -- Previous labour stays attributable, but old assignment grants no ongoing
 -- write access after reassignment. Preserve only the currently chosen row.
 delete from public.work_order_assignments where work_order_id=w.id and profile_id<>(p_data->>'assigned_to')::uuid and hours_logged is null and started_at is null;
 elsif p_action='start' then
 if w.status<>'assigned' then raise exception 'Assign this work order first'; end if;
 meter:=nullif(p_data->>'meter_value','')::numeric;
 if meter is not null and not(meter>=0 and meter<1000000000) then raise exception 'Enter a valid meter reading'; end if;
 update public.work_orders set status='in_progress',started_at=coalesce(started_at,now()),hours_at_start=meter where id=w.id;
 if meter is not null then perform public.record_component_meter(gen_random_uuid(),w.engine_id,w.asset_id,meter,w.meter_unit,now(),'Provider work start'); end if;
 elsif p_action in ('save_report','submit') then
 if w.status<>'in_progress' then raise exception 'Start work before writing the report'; end if;
 if length(coalesce(p_data->>'diagnosis',''))>8000 or length(coalesce(p_data->>'repair',''))>16000 or length(coalesce(p_data->>'notes',''))>4000 then raise exception 'Report text is too long'; end if;
 if p_action='submit' and (length(btrim(coalesce(p_data->>'diagnosis','')))<3 or length(btrim(coalesce(p_data->>'repair','')))<3)
 then raise exception 'Describe the diagnosis and repair'; end if;
 hours:=coalesce(nullif(p_data->>'labour_hours','')::numeric,0);
 if hours<0 or hours>=10000 or hours='NaN'::numeric then raise exception 'Enter valid labour hours'; end if;
 report:=coalesce(state.report_id,gen_random_uuid());
 insert into public.service_reports(id,work_order_id,cause,correction,comments,submitted_by,evidence_pending)
 values(report,w.id,p_data->>'diagnosis',p_data->>'repair',p_data->>'notes',auth.uid(),false)
 on conflict(id) do update set cause=excluded.cause,correction=excluded.correction,comments=excluded.comments,updated_at=now();
 update public.organization_work_report_state set report_id=report,review_note=null where work_order_id=w.id;
 meter:=nullif(p_data->>'meter_value','')::numeric;
 if meter is not null and not(meter>=coalesce(w.hours_at_start,0) and meter<1000000000) then raise exception 'Completion reading cannot precede the start'; end if;
 if meter is not null then perform public.record_component_meter(gen_random_uuid(),w.engine_id,w.asset_id,meter,w.meter_unit,now(),'Provider work completion'); end if;
 update public.work_orders set labour_hours=hours,hours_at_end=meter,status=case when p_action='submit' then 'pending_review' else status end where id=w.id;
 elsif p_action='add_part' then
 if w.status<>'in_progress' then raise exception 'Parts can change only during work'; end if;
 if length(btrim(coalesce(p_data->>'description','')))<2 or not((p_data->>'quantity')::numeric>0 and (p_data->>'quantity')::numeric<100000)
 or not((p_data->>'unit_cost')::numeric>=0 and (p_data->>'unit_cost')::numeric<1000000) then raise exception 'Enter a part, quantity and internal cost'; end if;
 insert into public.parts(id,work_order_id,description,quantity,unit_cost,markup_pct,logged_by)
 values(p_operation,w.id,btrim(p_data->>'description'),(p_data->>'quantity')::numeric,(p_data->>'unit_cost')::numeric,0,auth.uid());
 elsif p_action='return' then
 if not manager or w.status<>'pending_review' or length(btrim(coalesce(p_data->>'note','')))<3 then raise exception 'Return requires a manager and reason'; end if;
 update public.work_orders set status='in_progress' where id=w.id;
 update public.organization_work_report_state set review_note=btrim(p_data->>'note') where work_order_id=w.id;
 elsif p_action='approve' then
 if not manager or w.status<>'pending_review' then raise exception 'A manager must approve submitted work'; end if;
 update public.organization_work_report_state set published_report=(select jsonb_build_object('id',s.id,'diagnosis',s.cause,'repair',s.correction,
 'notes',s.comments,'approved_at',now(),'approved_by_name',(select full_name from public.profiles where id=auth.uid())) from public.service_reports s where s.id=state.report_id),
 approved_at=now(),approved_by=auth.uid() where work_order_id=w.id;
 update public.work_orders set status='closed',completed_at=now() where id=w.id;
 else raise exception 'Unknown work action'; end if;
 update public.organization_work_report_state set revision=revision+1 where work_order_id=w.id;
 insert into public.closeout_operations(id,actor_id,kind,payload,result) values(p_operation,auth.uid(),'organization_work',payload,w.id);
end $$;

-- Direct rows never leak private provider fields to the customer. The shared
-- Work Orders repository uses the sanitized context RPC for customer rows.
create function public.legacy_provider_client_allowed(p_client uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.get_my_role() not in ('owner','employee') or exists(select 1 from public.legacy_provider_tenants t where t.client_id=p_client)
$$;
drop policy modern_membership_read_boundary on public.work_orders;
create policy modern_membership_read_boundary on public.work_orders as restrictive for select to authenticated
 using(case when provider_organization_id is not null then public.organization_provider_access(id)
 else public.get_my_role()<>'member' or public.organization_asset_permission(asset_id,'member') end);
create policy organization_provider_work_read on public.work_orders for select to authenticated using(public.organization_provider_access(id));
create policy organization_work_mutations on public.work_orders as restrictive for insert to authenticated with check(provider_organization_id is null and public.legacy_provider_client_allowed(client_id));
create policy organization_work_updates on public.work_orders as restrictive for update to authenticated using(provider_organization_id is null) with check(provider_organization_id is null);
create policy organization_work_deletes on public.work_orders as restrictive for delete to authenticated using(provider_organization_id is null);
create policy organization_reports_read_boundary on public.service_reports as restrictive for select to authenticated
 using(not public.is_organization_provider_work(work_order_id) or public.organization_provider_access(work_order_id));
create policy organization_parts_read_boundary on public.parts as restrictive for select to authenticated
 using(not public.is_organization_provider_work(work_order_id) or public.organization_provider_access(work_order_id));
create policy organization_assignments_read_boundary on public.work_order_assignments as restrictive for select to authenticated
 using(not public.is_organization_provider_work(work_order_id) or public.organization_provider_access(work_order_id));
create policy organization_invoice_read_boundary on public.invoices as restrictive for select to authenticated
 using(not public.is_organization_provider_work(work_order_id) or public.organization_provider_access(work_order_id,'billing') or
 (public.organization_customer_access(work_order_id,true) and status in ('sent','paid')));
-- All organization mutations use the same scoped, transactional adapter. Old
-- permissive owner/employee policies cannot bypass a relationship boundary.
do $$ declare tab text; begin
 foreach tab in array array['service_reports','parts','work_order_assignments','invoices'] loop
 execute format('create policy organization_write_boundary on public.%I as restrictive for insert to authenticated with check(not public.is_organization_provider_work(work_order_id))',tab);
 execute format('create policy organization_update_boundary on public.%I as restrictive for update to authenticated using(not public.is_organization_provider_work(work_order_id)) with check(not public.is_organization_provider_work(work_order_id))',tab);
 execute format('create policy organization_delete_boundary on public.%I as restrictive for delete to authenticated using(not public.is_organization_provider_work(work_order_id))',tab);
 end loop;
end $$;

-- Reuse invoice snapshots/tax calculation/immutability. The modern adapter
-- requires both organization billing capability and explicit personal permission.
create function public.organization_invoice_action(p_work_order uuid,p_action text,p_data jsonb default '{}') returns uuid
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
 insert into public.invoices(id,work_order_id,client_id,invoice_number,labour_hours,billable_rate_usd,labour_total_usd,parts_total_usd,consumables_total_usd,exchange_rate,iva_pct,export_snapshot)
 values(result,w.id,w.client_id,'INV-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(result::text,'-',''),1,12)),coalesce(w.labour_hours,0),rate,
 round(coalesce(w.labour_hours,0)*rate,2),part_total,0,coalesce((p_data->>'exchange_rate')::numeric,1),coalesce((p_data->>'tax_percent')::numeric,0),
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

-- Existing definer APIs must not retain their global legacy owner bypass for
-- newly isolated organization orders. Preserve old bodies behind scoped gates.
do $$ declare sig regprocedure; body text; replacement text; begin
 foreach sig in array array['public.save_provider_work_order(uuid,jsonb,uuid[],uuid,uuid,timestamptz)'::regprocedure,
 'public.generate_provider_invoice(uuid,numeric)'::regprocedure] loop
 body:=pg_get_functiondef(sig);
 if sig='public.generate_provider_invoice(uuid,numeric)'::regprocedure then
 replacement:=replace(body,$old$begin
 if public.get_my_role()$old$,$new$begin
 if public.is_organization_provider_work(p_work_order) then raise exception 'Use organization billing'; end if;
 if public.get_my_role()$new$);
 else
 replacement:=replace(body,$old$begin
 if public.get_my_role()$old$,$new$begin
 if p_work_order is not null and public.is_organization_provider_work(p_work_order) then raise exception 'Use organization work administration'; end if;
 if p_work_order is null and not exists(select 1 from public.legacy_provider_tenants t where t.client_id=(p_data->>'client_id')::uuid)
 then raise exception 'Use an authorized organization relationship'; end if;
 if public.get_my_role()$new$);
 end if;
 if replacement=body then raise exception 'Legacy provider gate adaptation did not match %',sig; end if;
 execute replacement;
 end loop;
end $$;
create or replace function public.provider_report_author(p_work_order uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not public.is_organization_provider_work(p_work_order) and exists(select 1 from public.work_orders w where w.id=p_work_order and not w.managed_maintenance and
 (public.get_my_role()='owner' or (public.get_my_role()='employee' and (w.assigned_to=auth.uid() or exists(select 1 from public.work_order_assignments a where a.work_order_id=w.id and a.profile_id=auth.uid())))))
$$;
create or replace function public.can_read_provider_report(p_work_order uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select case when public.is_organization_provider_work(p_work_order) then public.organization_provider_access(p_work_order)
 or (public.organization_customer_access(p_work_order) and exists(select 1 from public.organization_work_report_state where work_order_id=p_work_order and approved_at is not null))
 else exists(select 1 from public.work_orders w join public.profiles p on p.id=auth.uid() where w.id=p_work_order and not w.managed_maintenance
 and (p.role in ('owner','employee') or (p.role in ('client','client_admin','client_mechanic') and w.status in ('closed','invoiced') and public.maintenance_can_view_asset(w.asset_id)))) end
$$;
create function public.legacy_provider_asset_allowed(p_asset uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.get_my_role() not in ('owner','employee') or exists(select 1 from public.assets a join public.legacy_provider_tenants t on t.client_id=a.client_id where a.id=p_asset)
$$;
create policy legacy_provider_tenant_boundary on public.assets as restrictive for select to authenticated using(public.legacy_provider_asset_allowed(id));
create policy legacy_provider_tenant_update_boundary on public.assets as restrictive for update to authenticated using(public.legacy_provider_asset_allowed(id));
create policy legacy_provider_tenant_delete_boundary on public.assets as restrictive for delete to authenticated using(public.legacy_provider_asset_allowed(id));
create policy legacy_provider_tenant_insert_boundary on public.assets as restrictive for insert to authenticated with check(public.legacy_provider_client_allowed(client_id));

create function public.organization_provider_meter_access(p_asset uuid,p_engine uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.work_orders w where w.provider_organization_id is not null and w.asset_id=p_asset
 and w.engine_id is not distinct from p_engine and w.status='in_progress' and public.organization_provider_access(w.id,'work'))
$$;
do $$ declare body text; updated text; sig regprocedure; begin
 select p.oid::regprocedure into sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='record_component_meter';
 if sig is not null then
 body:=pg_get_functiondef(sig);
 updated:=replace(body,$old$if auth.uid() is null or not public.maintenance_can_view_asset(p_asset) then raise exception 'Asset access required'; end if;$old$,
 $new$if auth.uid() is null or not (public.maintenance_can_view_asset(p_asset) or public.organization_provider_meter_access(p_asset,p_engine)) then raise exception 'Asset access required'; end if;$new$);
 if updated=body then raise exception 'Organization meter permission adaptation did not match'; end if;
 execute updated;
 end if;
end $$;

revoke all on function public.initialize_organization_service_settings() from public,anon,authenticated;
do $$ declare f record; begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
 and p.proname in ('organization_provider_access','organization_customer_access','is_organization_provider_work','organization_service_configuration','configure_organization_services',
 'propose_organization_customer','organization_service_request_context','organization_work_order_context','organization_work_orders','request_organization_work','change_organization_work','organization_invoice_action','legacy_provider_asset_allowed','legacy_provider_client_allowed','organization_provider_meter_access') loop
 execute format('revoke all on function %s from public,anon',f.sig);execute format('grant execute on function %s to authenticated',f.sig);
 end loop;
end $$;
