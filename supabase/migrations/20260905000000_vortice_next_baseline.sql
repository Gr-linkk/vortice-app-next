-- Vortice Next current-schema baseline
-- Generated from read-only metadata from the original mock-data project.
-- The earlier incremental migrations are preserved in supabase/migrations_legacy.

set check_function_bodies = off;
create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;

-- Tables
create table public."parts" (
  "id" uuid default uuid_generate_v4() not null,
  "work_order_id" uuid not null,
  "description" text not null,
  "part_number" text,
  "supplier" text,
  "quantity" numeric(8,2) default 1 not null,
  "unit_cost" numeric(10,2) not null,
  "markup_pct" numeric(5,2) default 15.00,
  "logged_by" uuid,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now()
);
create table public."invoices" (
  "id" uuid default uuid_generate_v4() not null,
  "work_order_id" uuid not null,
  "client_id" uuid not null,
  "invoice_number" text not null,
  "status" text default 'draft'::text not null,
  "labour_hours" numeric(6,2),
  "billable_rate_usd" numeric(8,2),
  "labour_total_usd" numeric(10,2),
  "parts_total_usd" numeric(10,2),
  "consumables_total_usd" numeric(10,2),
  "subtotal_usd" numeric(10,2),
  "iva_pct" numeric(5,2) default 16.00,
  "iva_total_usd" numeric(10,2),
  "total_usd" numeric(10,2),
  "exchange_rate" numeric(10,4),
  "total_mxn" numeric(12,2),
  "notes" text,
  "pdf_url" text,
  "xlsx_url" text,
  "sent_at" timestamp with time zone,
  "paid_at" timestamp with time zone,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now()
);
create table public."asset_types" (
  "id" uuid default uuid_generate_v4() not null,
  "category" text not null,
  "name" text not null,
  "tracking_unit" text default 'engine_hours'::text not null,
  "created_at" timestamp with time zone default now()
);
create table public."imported_docs" (
  "id" uuid default uuid_generate_v4() not null,
  "asset_type_id" uuid,
  "uploaded_by" uuid,
  "file_name" text not null,
  "file_url" text not null,
  "status" text default 'uploaded'::text not null,
  "extracted_items" jsonb,
  "notes" text,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now()
);
create table public."checklist_items" (
  "id" uuid default uuid_generate_v4() not null,
  "template_id" uuid not null,
  "sort_order" integer default 0 not null,
  "description_en" text not null,
  "description_es" text,
  "category" text,
  "requires_photo" boolean default false,
  "created_at" timestamp with time zone default now()
);
create table public."asset_engines" (
  "id" uuid default uuid_generate_v4() not null,
  "asset_id" uuid not null,
  "label" text not null,
  "kind" text default 'engine'::text not null,
  "make" text,
  "model" text,
  "serial_number" text,
  "current_hours" numeric(10,1) default 0,
  "telemetry_channel" text,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now()
);
create table public."asset_service_intervals" (
  "id" uuid default uuid_generate_v4() not null,
  "asset_id" uuid not null,
  "interval_hours" integer not null,
  "interval_label" text,
  "checklist_template_id" uuid,
  "is_active" boolean default true,
  "notes" text,
  "created_at" timestamp with time zone default now()
);
create table public."work_orders" (
  "id" uuid default uuid_generate_v4() not null,
  "asset_id" uuid not null,
  "engine_id" uuid,
  "client_id" uuid not null,
  "assigned_to" uuid,
  "created_by" uuid not null,
  "checklist_template_id" uuid,
  "checklist_template_version" integer,
  "job_type" text not null,
  "status" text default 'draft'::text not null,
  "title" text not null,
  "description" text,
  "scheduled_date" date,
  "started_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "hours_at_start" numeric(10,1),
  "hours_at_end" numeric(10,1),
  "labour_hours" numeric(6,2),
  "billable_rate" numeric(8,2) default 80.00,
  "wage_rate" numeric(8,2) default 60.00,
  "notes_internal" text,
  "on_hold_reason" text,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now()
);
create table public."operator_checklist_runs" (
  "id" uuid default uuid_generate_v4() not null,
  "asset_id" uuid not null,
  "engine_id" uuid,
  "template_id" uuid not null,
  "operator_id" uuid not null,
  "run_type" text not null,
  "trip_hours" numeric(6,1),
  "fuel_added" numeric(8,2),
  "notes" text,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now()
);
create table public."checklist_templates" (
  "id" uuid default uuid_generate_v4() not null,
  "asset_type_id" uuid,
  "checklist_type" text default 'pm'::text not null,
  "interval_hours" integer,
  "interval_label" text,
  "name" text not null,
  "description" text,
  "version" integer default 1 not null,
  "is_active" boolean default true,
  "source_doc_id" uuid,
  "created_by" uuid,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now(),
  "category" text default 'general'::text not null
);
create table public."service_reminders" (
  "id" uuid default uuid_generate_v4() not null,
  "asset_id" uuid not null,
  "engine_id" uuid not null,
  "interval_hours" integer not null,
  "due_at_hours" numeric(10,1) not null,
  "threshold_50hr_sent" boolean default false,
  "threshold_10hr_sent" boolean default false,
  "threshold_due_sent" boolean default false,
  "acknowledged" boolean default false,
  "created_at" timestamp with time zone default now(),
  "template_id" uuid,
  "notes" text,
  "service_interval_id" uuid
);
create table public."assets" (
  "id" uuid default uuid_generate_v4() not null,
  "client_id" uuid not null,
  "asset_type_id" uuid not null,
  "name" text not null,
  "make" text,
  "model" text,
  "year" integer,
  "serial_number" text,
  "location" text,
  "notes" text,
  "telemetry_enabled" boolean default false,
  "telemetry_source" text,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now()
);
create table public."service_reports" (
  "id" uuid default uuid_generate_v4() not null,
  "work_order_id" uuid not null,
  "complaint" text,
  "cause" text,
  "correction" text,
  "collateral" text,
  "comments" text,
  "tech_signature_url" text,
  "signed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now()
);
create table public."service_report_photos" (
  "id" uuid default uuid_generate_v4() not null,
  "service_report_id" uuid not null,
  "photo_url" text not null,
  "caption" text,
  "sort_order" integer default 0,
  "uploaded_by" uuid,
  "created_at" timestamp with time zone default now()
);
create table public."org_codes" (
  "id" uuid default uuid_generate_v4() not null,
  "code" text not null,
  "intended_role" text,
  "single_use" boolean default true,
  "max_uses" integer default 1,
  "use_count" integer default 0,
  "expires_at" timestamp with time zone,
  "created_by" uuid,
  "notes" text,
  "created_at" timestamp with time zone default now(),
  "org_id" uuid
);
create table public."profiles" (
  "id" uuid not null,
  "role" text not null,
  "full_name" text not null,
  "email" text not null,
  "phone" text,
  "preferred_language" text default 'en'::text,
  "org_code_used" text,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now(),
  "subscription_tier" integer default 0 not null,
  "billable_rate" double precision,
  "org_id" uuid
);
create table public."hour_logs" (
  "id" uuid default uuid_generate_v4() not null,
  "asset_id" uuid not null,
  "engine_id" uuid,
  "work_order_id" uuid,
  "hours" numeric(10,1) not null,
  "logged_by" uuid not null,
  "logged_at" timestamp with time zone default now(),
  "notes" text
);
create table public."parts_catalog" (
  "id" uuid default uuid_generate_v4() not null,
  "description" text not null,
  "part_number" text,
  "supplier" text,
  "last_unit_cost" numeric(10,2),
  "use_count" integer default 1,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now()
);
create table public."parts_inventory" (
  "id" uuid default uuid_generate_v4() not null,
  "description" text not null,
  "part_number" text,
  "qty_on_hand" numeric(8,2) default 0 not null,
  "min_stock_level" numeric(8,2) default 0,
  "location" text,
  "supplier" text,
  "last_unit_cost" numeric(10,2) default 0,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now()
);
create table public."maintenance_requests" (
  "id" uuid default uuid_generate_v4() not null,
  "asset_id" uuid not null,
  "flagged_by" uuid not null,
  "description" text not null,
  "photo_url" text,
  "severity" text default 'normal'::text,
  "status" text default 'open'::text not null,
  "converted_to_work_order_id" uuid,
  "client_notified_at" timestamp with time zone,
  "owner_notified_at" timestamp with time zone,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now(),
  "client_id" uuid
);
create table public."notifications" (
  "id" uuid default gen_random_uuid() not null,
  "user_id" uuid,
  "title" text,
  "body" text,
  "type" text,
  "reference_id" uuid,
  "read" boolean default false,
  "created_at" timestamp with time zone default now()
);
create table public."pm_parts_requirements" (
  "id" uuid default uuid_generate_v4() not null,
  "template_id" uuid not null,
  "description" text not null,
  "part_number" text,
  "qty" numeric(8,2) default 1 not null,
  "unit" text,
  "notes" text,
  "created_at" timestamp with time zone default now()
);
create table public."work_order_assignments" (
  "id" uuid default gen_random_uuid() not null,
  "work_order_id" uuid not null,
  "profile_id" uuid not null,
  "role" text default 'tech'::text not null,
  "hours_logged" double precision,
  "billable_rate" double precision,
  "started_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now()
);
create table public."telemetry_alerts" (
  "id" uuid default uuid_generate_v4() not null,
  "engine_id" uuid,
  "alert_type" text not null,
  "spn" integer,
  "fmi" integer,
  "parameter" text,
  "value" numeric(10,2),
  "threshold" numeric(10,2),
  "comparison" text,
  "message" text,
  "severity" text default 'warning'::text,
  "acknowledged" boolean default false,
  "acknowledged_by" uuid,
  "acknowledged_at" timestamp with time zone,
  "resolved" boolean default false,
  "resolved_at" timestamp with time zone,
  "source" text,
  "device_id" text,
  "raw_data" jsonb,
  "created_at" timestamp with time zone default now(),
  "alert_source" text default 'system'::text,
  "asset_id" uuid not null
);
create table public."meeting_requests" (
  "id" uuid default gen_random_uuid() not null,
  "profile_id" uuid not null,
  "interest" text,
  "vessel_count" text,
  "contact_method" text,
  "notes" text,
  "status" text default 'pending'::text not null,
  "created_at" timestamp with time zone default now()
);
create table public."checklist_assignments" (
  "id" uuid default gen_random_uuid() not null,
  "template_id" uuid not null,
  "asset_id" uuid,
  "assigned_to" uuid not null,
  "assigned_by" uuid not null,
  "org_id" uuid not null,
  "status" text default 'pending'::text not null,
  "due_date" date,
  "completed_at" timestamp with time zone,
  "notes" text,
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now()
);
create table public."checklist_responses" (
  "id" uuid default uuid_generate_v4() not null,
  "work_order_id" uuid not null,
  "checklist_item_id" uuid not null,
  "completed" boolean default false,
  "notes" text,
  "photo_url" text,
  "completed_by" uuid,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now(),
  "response_status" text
);
create table public."operator_checklist_responses" (
  "id" uuid default uuid_generate_v4() not null,
  "run_id" uuid not null,
  "checklist_item_id" uuid not null,
  "result" text not null,
  "notes" text,
  "photo_url" text,
  "created_at" timestamp with time zone default now(),
  "response_status" text
);
create table public."devices" (
  "id" uuid default gen_random_uuid() not null,
  "pairing_code" text not null,
  "asset_id" uuid,
  "linked_at" timestamp with time zone,
  "linked_by" uuid,
  "last_seen" timestamp with time zone,
  "created_at" timestamp with time zone default now(),
  "device_id" text
);
create table public."telemetry_readings" (
  "id" uuid default uuid_generate_v4() not null,
  "engine_id" uuid,
  "ts" timestamp with time zone default now() not null,
  "rpm" numeric(8,2),
  "coolant_temp" numeric(6,2),
  "oil_pressure" numeric(6,2),
  "battery_v" numeric(5,2),
  "boost_psi" numeric(6,2),
  "throttle_pct" numeric(5,2),
  "fuel_rate" numeric(8,3),
  "torque_pct" numeric(5,2),
  "engine_hours" numeric(10,1),
  "intake_temp" numeric(6,2),
  "exhaust_temp" numeric(6,2),
  "oil_temp" numeric(6,2),
  "fuel_pressure" numeric(6,2),
  "transmission_temp" numeric(6,2),
  "transmission_pressure" numeric(6,2),
  "raw_data" jsonb,
  "source" text,
  "device_id" text,
  "created_at" timestamp with time zone default now(),
  "asset_id" uuid not null
);
create table public."client_capabilities" (
  "id" uuid default gen_random_uuid() not null,
  "client_id" uuid not null,
  "capability_key" text not null,
  "enabled" boolean default false not null,
  "updated_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
create table public."client_orgs" (
  "id" uuid default gen_random_uuid() not null,
  "name" text not null,
  "owner_profile_id" uuid not null,
  "subscription_tier" integer default 0 not null,
  "created_at" timestamp with time zone default now()
);
create table public."saved_checklists" (
  "id" uuid default gen_random_uuid() not null,
  "asset_id" uuid not null,
  "client_id" uuid not null,
  "template_id" uuid,
  "template_name" text not null,
  "checklist_type" text not null,
  "source_type" text not null,
  "submitted_by" uuid,
  "submitted_by_role" text,
  "submitted_at" timestamp with time zone default timezone('utc'::text, now()) not null,
  "current_hours" numeric,
  "general_notes" text,
  "work_order_id" uuid,
  "assignment_id" uuid,
  "snapshot" jsonb not null,
  "created_at" timestamp with time zone default timezone('utc'::text, now()) not null,
  "updated_at" timestamp with time zone default timezone('utc'::text, now()) not null
);
create table public."service_requests" (
  "id" uuid default gen_random_uuid() not null,
  "client_id" uuid not null,
  "asset_id" uuid,
  "title" text not null,
  "description" text not null,
  "urgency" text default 'normal'::text not null,
  "status" text default 'new'::text not null,
  "source_maintenance_request_id" uuid,
  "generated_work_order_id" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "handled_at" timestamp with time zone,
  "handled_by" uuid,
  "other_asset_name" text,
  "contact_phone_or_whatsapp" text default ''::text not null,
  "photo_urls" text[] default '{}'::text[] not null,
  "request_type" text default 'other_issue'::text not null,
  "engine_hours" numeric
);
create table public."telemetry_gateway_health" (
  "id" uuid default gen_random_uuid() not null,
  "device_id" text not null,
  "pairing_code" text,
  "asset_id" uuid,
  "ts" timestamp with time zone default now() not null,
  "cpu_temp" text,
  "throttled" text,
  "can_status" text,
  "modem_status" jsonb,
  "raw_data" jsonb,
  "created_at" timestamp with time zone default now() not null,
  "gps_fix" boolean,
  "gps_lat" double precision,
  "gps_lon" double precision,
  "gps_altitude_m" double precision,
  "engine_rpm" numeric(8,2),
  "engine_torque_pct" numeric(5,2),
  "coolant_temp_c" numeric(6,2),
  "battery_voltage_v" numeric(5,2),
  "fuel_rate_lph" numeric(8,3),
  "engine_hours" numeric(10,1),
  "active_fault_count" integer,
  "dm1_faults" jsonb
);

-- Table and column comments
comment on table public."telemetry_alerts" is 'Diagnostic trouble codes (DTCs) and threshold-based alerts from telemetry';
comment on column public."telemetry_alerts"."engine_id" is 'Optional engine/J1939 stream pointer. Alerts remain asset-owned when null.';
comment on column public."telemetry_alerts"."spn" is 'J1939 Suspect Parameter Number for diagnostic codes';
comment on column public."telemetry_alerts"."fmi" is 'J1939 Failure Mode Identifier for diagnostic codes';
comment on column public."telemetry_alerts"."asset_id" is 'Canonical alert owner. Required even when engine_id is null.';
comment on table public."telemetry_readings" is 'Periodic engine telemetry snapshots from J1939/NMEA/Modbus sources';
comment on column public."telemetry_readings"."engine_id" is 'Optional engine/J1939 stream pointer. Telemetry remains asset-owned when null.';
comment on column public."telemetry_readings"."asset_id" is 'Canonical telemetry owner. Required even when engine_id is null.';
comment on table public."client_capabilities" is 'Per-client service capability switches. Missing rows default to disabled in the app.';
comment on column public."client_capabilities"."client_id" is 'Client profile id. Mirrors current assets.client_id = profiles.id app model.';
comment on column public."client_capabilities"."capability_key" is 'Switch key for optional workflows only; always-on portal capabilities are not stored here.';
comment on table public."saved_checklists" is 'Immutable submitted checklist history for assets across maintenance and operations workflows.';
comment on table public."service_requests" is 'Always-on client/admin requests for Vórtice service. Staff triage these before creating work orders.';
comment on column public."service_requests"."urgency" is 'Visual treatment only for MVP; no notification or escalation behavior.';
comment on column public."service_requests"."status" is 'Client labels: new=Sent, resolved=Being handled, declined=Declined.';
comment on column public."service_requests"."generated_work_order_id" is 'Reserved for later explicit staff-generated work orders; not automatic.';
comment on column public."service_requests"."other_asset_name" is 'Client-entered asset label when the requested machine is not in their asset list.';
comment on column public."service_requests"."contact_phone_or_whatsapp" is 'Best callback number or WhatsApp contact supplied with the request.';
comment on column public."service_requests"."photo_urls" is 'Public photo URLs attached to the service request intake packet.';
comment on column public."service_requests"."request_type" is 'Simple client-selected intake bucket: breakdown, service_maintenance, safety_concern, or other_issue.';
comment on column public."service_requests"."engine_hours" is 'Client-supplied current engine/machine hours at service request intake; used to prefill generated work orders.';
comment on column public."telemetry_gateway_health"."gps_fix" is 'Whether SIM7600 GNSS had a location fix for this gateway health sample.';
comment on column public."telemetry_gateway_health"."gps_lat" is 'Gateway GPS latitude in decimal degrees from SIM7600 GNSS.';
comment on column public."telemetry_gateway_health"."gps_lon" is 'Gateway GPS longitude in decimal degrees from SIM7600 GNSS.';
comment on column public."telemetry_gateway_health"."gps_altitude_m" is 'Gateway GPS altitude in metres from SIM7600 GNSS, when available.';
comment on column public."telemetry_gateway_health"."engine_rpm" is 'Prototype decoded J1939 engine speed from gateway health snapshots. Not app-facing telemetry_readings.';
comment on column public."telemetry_gateway_health"."engine_torque_pct" is 'Prototype decoded J1939 actual engine torque percent from gateway health snapshots.';
comment on column public."telemetry_gateway_health"."coolant_temp_c" is 'Prototype decoded J1939 engine coolant temperature in Celsius.';
comment on column public."telemetry_gateway_health"."battery_voltage_v" is 'Prototype decoded J1939 battery/electrical potential in volts.';
comment on column public."telemetry_gateway_health"."fuel_rate_lph" is 'Prototype decoded J1939 fuel rate in litres per hour.';
comment on column public."telemetry_gateway_health"."engine_hours" is 'Prototype decoded J1939 total engine hours.';
comment on column public."telemetry_gateway_health"."active_fault_count" is 'Count of active DM1 faults decoded in this gateway health snapshot.';
comment on column public."telemetry_gateway_health"."dm1_faults" is 'Decoded DM1 faults as JSON objects containing SPN, FMI, occurrence count, source address, and raw bytes.';

-- Primary, unique, and check constraints
alter table only public."parts" add constraint "parts_pkey" PRIMARY KEY (id);
alter table only public."invoices" add constraint "invoices_invoice_number_key" UNIQUE (invoice_number);
alter table only public."invoices" add constraint "invoices_pkey" PRIMARY KEY (id);
alter table only public."invoices" add constraint "invoices_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'sent'::text, 'paid'::text, 'void'::text])));
alter table only public."invoices" add constraint "invoices_work_order_id_key" UNIQUE (work_order_id);
alter table only public."asset_types" add constraint "asset_types_pkey" PRIMARY KEY (id);
alter table only public."imported_docs" add constraint "imported_docs_pkey" PRIMARY KEY (id);
alter table only public."imported_docs" add constraint "imported_docs_status_check" CHECK ((status = ANY (ARRAY['uploaded'::text, 'processing'::text, 'draft'::text, 'approved'::text])));
alter table only public."checklist_items" add constraint "checklist_items_pkey" PRIMARY KEY (id);
alter table only public."asset_engines" add constraint "asset_engines_kind_check" CHECK ((kind = ANY (ARRAY['engine'::text, 'generator'::text, 'other'::text])));
alter table only public."asset_engines" add constraint "asset_engines_pkey" PRIMARY KEY (id);
alter table only public."asset_service_intervals" add constraint "asset_service_intervals_pkey" PRIMARY KEY (id);
alter table only public."work_orders" add constraint "work_orders_job_type_check" CHECK ((job_type = ANY (ARRAY['preventative'::text, 'repair'::text])));
alter table only public."work_orders" add constraint "work_orders_pkey" PRIMARY KEY (id);
alter table only public."work_orders" add constraint "work_orders_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'assigned'::text, 'in_progress'::text, 'on_hold'::text, 'pending_review'::text, 'invoiced'::text, 'closed'::text])));
alter table only public."operator_checklist_runs" add constraint "operator_checklist_runs_pkey" PRIMARY KEY (id);
alter table only public."operator_checklist_runs" add constraint "operator_checklist_runs_run_type_check" CHECK ((run_type = ANY (ARRAY['pre_departure'::text, 'post_trip'::text])));
alter table only public."checklist_templates" add constraint "checklist_templates_checklist_type_check" CHECK ((checklist_type = ANY (ARRAY['pm'::text, 'operator_daily'::text])));
alter table only public."checklist_templates" add constraint "checklist_templates_pkey" PRIMARY KEY (id);
alter table only public."service_reminders" add constraint "service_reminders_pkey" PRIMARY KEY (id);
alter table only public."assets" add constraint "assets_pkey" PRIMARY KEY (id);
alter table only public."service_reports" add constraint "service_reports_pkey" PRIMARY KEY (id);
alter table only public."service_reports" add constraint "service_reports_work_order_id_key" UNIQUE (work_order_id);
alter table only public."service_report_photos" add constraint "service_report_photos_pkey" PRIMARY KEY (id);
alter table only public."org_codes" add constraint "org_codes_code_key" UNIQUE (code);
alter table only public."org_codes" add constraint "org_codes_intended_role_check" CHECK ((intended_role = ANY (ARRAY['employee'::text, 'client'::text, 'operator'::text])));
alter table only public."org_codes" add constraint "org_codes_pkey" PRIMARY KEY (id);
alter table only public."profiles" add constraint "profiles_pkey" PRIMARY KEY (id);
alter table only public."profiles" add constraint "profiles_preferred_language_check" CHECK ((preferred_language = ANY (ARRAY['en'::text, 'es'::text])));
alter table only public."profiles" add constraint "profiles_role_check" CHECK ((role = ANY (ARRAY['owner'::text, 'employee'::text, 'client'::text, 'operator'::text, 'client_admin'::text, 'client_mechanic'::text, 'client_operator'::text])));
alter table only public."hour_logs" add constraint "hour_logs_pkey" PRIMARY KEY (id);
alter table only public."parts_catalog" add constraint "parts_catalog_pkey" PRIMARY KEY (id);
alter table only public."parts_inventory" add constraint "parts_inventory_pkey" PRIMARY KEY (id);
alter table only public."maintenance_requests" add constraint "maintenance_requests_pkey" PRIMARY KEY (id);
alter table only public."maintenance_requests" add constraint "maintenance_requests_severity_check" CHECK ((severity = ANY (ARRAY['normal'::text, 'urgent'::text])));
alter table only public."maintenance_requests" add constraint "maintenance_requests_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'converted'::text, 'dismissed'::text])));
alter table only public."notifications" add constraint "notifications_pkey" PRIMARY KEY (id);
alter table only public."pm_parts_requirements" add constraint "pm_parts_requirements_pkey" PRIMARY KEY (id);
alter table only public."work_order_assignments" add constraint "work_order_assignments_pkey" PRIMARY KEY (id);
alter table only public."work_order_assignments" add constraint "work_order_assignments_work_order_id_profile_id_key" UNIQUE (work_order_id, profile_id);
alter table only public."telemetry_alerts" add constraint "telemetry_alerts_alert_type_check" CHECK ((alert_type = ANY (ARRAY['dtc'::text, 'threshold'::text, 'warning'::text, 'critical'::text, 'info'::text])));
alter table only public."telemetry_alerts" add constraint "telemetry_alerts_comparison_check" CHECK ((comparison = ANY (ARRAY['gt'::text, 'lt'::text, 'gte'::text, 'lte'::text, 'eq'::text])));
alter table only public."telemetry_alerts" add constraint "telemetry_alerts_pkey" PRIMARY KEY (id);
alter table only public."telemetry_alerts" add constraint "telemetry_alerts_severity_check" CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'critical'::text])));
alter table only public."meeting_requests" add constraint "meeting_requests_pkey" PRIMARY KEY (id);
alter table only public."checklist_assignments" add constraint "checklist_assignments_pkey" PRIMARY KEY (id);
alter table only public."checklist_assignments" add constraint "checklist_assignments_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text])));
alter table only public."checklist_responses" add constraint "checklist_responses_pkey" PRIMARY KEY (id);
alter table only public."checklist_responses" add constraint "checklist_responses_response_status_check" CHECK ((response_status = ANY (ARRAY[NULL::text, 'pass'::text, 'alert'::text, 'action'::text])));
alter table only public."operator_checklist_responses" add constraint "operator_checklist_responses_pkey" PRIMARY KEY (id);
alter table only public."operator_checklist_responses" add constraint "operator_checklist_responses_response_status_check" CHECK ((response_status = ANY (ARRAY[NULL::text, 'pass'::text, 'alert'::text, 'action'::text])));
alter table only public."operator_checklist_responses" add constraint "operator_checklist_responses_result_check" CHECK ((result = ANY (ARRAY['good'::text, 'needs_attention'::text, 'not_applicable'::text])));
alter table only public."devices" add constraint "devices_pairing_code_key" UNIQUE (pairing_code);
alter table only public."devices" add constraint "devices_pkey" PRIMARY KEY (id);
alter table only public."telemetry_readings" add constraint "telemetry_readings_pkey" PRIMARY KEY (id);
alter table only public."client_capabilities" add constraint "client_capabilities_capability_key_check" CHECK ((capability_key = ANY (ARRAY['operational_checklists'::text, 'pm_checklists'::text, 'pm_parts_lists'::text, 'maintenance_planning'::text, 'telemetry'::text])));
alter table only public."client_capabilities" add constraint "client_capabilities_client_id_capability_key_key" UNIQUE (client_id, capability_key);
alter table only public."client_capabilities" add constraint "client_capabilities_pkey" PRIMARY KEY (id);
alter table only public."client_orgs" add constraint "client_orgs_pkey" PRIMARY KEY (id);
alter table only public."saved_checklists" add constraint "saved_checklists_checklist_type_check" CHECK ((checklist_type = ANY (ARRAY['maintenance'::text, 'operations'::text])));
alter table only public."saved_checklists" add constraint "saved_checklists_pkey" PRIMARY KEY (id);
alter table only public."service_requests" add constraint "service_requests_description_check" CHECK ((length(TRIM(BOTH FROM description)) > 0));
alter table only public."service_requests" add constraint "service_requests_handled_status_check" CHECK ((((status = 'new'::text) AND (handled_at IS NULL) AND (handled_by IS NULL)) OR (status = ANY (ARRAY['resolved'::text, 'declined'::text]))));
alter table only public."service_requests" add constraint "service_requests_pkey" PRIMARY KEY (id);
alter table only public."service_requests" add constraint "service_requests_request_type_check" CHECK ((request_type = ANY (ARRAY['breakdown'::text, 'service_maintenance'::text, 'safety_concern'::text, 'other_issue'::text])));
alter table only public."service_requests" add constraint "service_requests_status_check" CHECK ((status = ANY (ARRAY['new'::text, 'resolved'::text, 'declined'::text])));
alter table only public."service_requests" add constraint "service_requests_title_check" CHECK ((length(TRIM(BOTH FROM title)) > 0));
alter table only public."service_requests" add constraint "service_requests_urgency_check" CHECK ((urgency = ANY (ARRAY['normal'::text, 'urgent'::text])));
alter table only public."telemetry_gateway_health" add constraint "telemetry_gateway_health_pkey" PRIMARY KEY (id);

-- Foreign keys
alter table only public."parts" add constraint "parts_logged_by_fkey" FOREIGN KEY (logged_by) REFERENCES profiles(id);
alter table only public."parts" add constraint "parts_work_order_id_fkey" FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table only public."invoices" add constraint "invoices_client_id_fkey" FOREIGN KEY (client_id) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table only public."invoices" add constraint "invoices_work_order_id_fkey" FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table only public."imported_docs" add constraint "imported_docs_asset_type_id_fkey" FOREIGN KEY (asset_type_id) REFERENCES asset_types(id);
alter table only public."imported_docs" add constraint "imported_docs_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES profiles(id);
alter table only public."checklist_items" add constraint "checklist_items_template_id_fkey" FOREIGN KEY (template_id) REFERENCES checklist_templates(id) ON DELETE CASCADE;
alter table only public."asset_engines" add constraint "asset_engines_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table only public."asset_service_intervals" add constraint "asset_service_intervals_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table only public."asset_service_intervals" add constraint "asset_service_intervals_checklist_template_id_fkey" FOREIGN KEY (checklist_template_id) REFERENCES checklist_templates(id);
alter table only public."work_orders" add constraint "work_orders_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE RESTRICT;
alter table only public."work_orders" add constraint "work_orders_assigned_to_fkey" FOREIGN KEY (assigned_to) REFERENCES profiles(id);
alter table only public."work_orders" add constraint "work_orders_checklist_template_id_fkey" FOREIGN KEY (checklist_template_id) REFERENCES checklist_templates(id);
alter table only public."work_orders" add constraint "work_orders_client_id_fkey" FOREIGN KEY (client_id) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table only public."work_orders" add constraint "work_orders_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table only public."work_orders" add constraint "work_orders_engine_id_fkey" FOREIGN KEY (engine_id) REFERENCES asset_engines(id);
alter table only public."operator_checklist_runs" add constraint "operator_checklist_runs_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table only public."operator_checklist_runs" add constraint "operator_checklist_runs_engine_id_fkey" FOREIGN KEY (engine_id) REFERENCES asset_engines(id);
alter table only public."operator_checklist_runs" add constraint "operator_checklist_runs_operator_id_fkey" FOREIGN KEY (operator_id) REFERENCES profiles(id);
alter table only public."operator_checklist_runs" add constraint "operator_checklist_runs_template_id_fkey" FOREIGN KEY (template_id) REFERENCES checklist_templates(id);
alter table only public."checklist_templates" add constraint "checklist_templates_asset_type_id_fkey" FOREIGN KEY (asset_type_id) REFERENCES asset_types(id);
alter table only public."checklist_templates" add constraint "checklist_templates_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table only public."checklist_templates" add constraint "checklist_templates_source_doc_id_fkey" FOREIGN KEY (source_doc_id) REFERENCES imported_docs(id);
alter table only public."service_reminders" add constraint "service_reminders_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table only public."service_reminders" add constraint "service_reminders_engine_id_fkey" FOREIGN KEY (engine_id) REFERENCES asset_engines(id);
alter table only public."service_reminders" add constraint "service_reminders_service_interval_id_fkey" FOREIGN KEY (service_interval_id) REFERENCES asset_service_intervals(id) ON DELETE CASCADE;
alter table only public."service_reminders" add constraint "service_reminders_template_id_fkey" FOREIGN KEY (template_id) REFERENCES checklist_templates(id);
alter table only public."assets" add constraint "assets_asset_type_id_fkey" FOREIGN KEY (asset_type_id) REFERENCES asset_types(id);
alter table only public."assets" add constraint "assets_client_id_fkey" FOREIGN KEY (client_id) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table only public."service_reports" add constraint "service_reports_work_order_id_fkey" FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table only public."service_report_photos" add constraint "service_report_photos_service_report_id_fkey" FOREIGN KEY (service_report_id) REFERENCES service_reports(id) ON DELETE CASCADE;
alter table only public."service_report_photos" add constraint "service_report_photos_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES profiles(id);
alter table only public."org_codes" add constraint "org_codes_org_id_fkey" FOREIGN KEY (org_id) REFERENCES client_orgs(id) ON DELETE CASCADE;
alter table only public."profiles" add constraint "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table only public."profiles" add constraint "profiles_org_id_fkey" FOREIGN KEY (org_id) REFERENCES client_orgs(id);
alter table only public."hour_logs" add constraint "hour_logs_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table only public."hour_logs" add constraint "hour_logs_engine_id_fkey" FOREIGN KEY (engine_id) REFERENCES asset_engines(id);
alter table only public."hour_logs" add constraint "hour_logs_logged_by_fkey" FOREIGN KEY (logged_by) REFERENCES profiles(id);
alter table only public."hour_logs" add constraint "hour_logs_work_order_id_fkey" FOREIGN KEY (work_order_id) REFERENCES work_orders(id);
alter table only public."maintenance_requests" add constraint "maintenance_requests_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table only public."maintenance_requests" add constraint "maintenance_requests_client_id_fkey" FOREIGN KEY (client_id) REFERENCES profiles(id);
alter table only public."maintenance_requests" add constraint "maintenance_requests_converted_to_work_order_id_fkey" FOREIGN KEY (converted_to_work_order_id) REFERENCES work_orders(id);
alter table only public."maintenance_requests" add constraint "maintenance_requests_flagged_by_fkey" FOREIGN KEY (flagged_by) REFERENCES profiles(id);
alter table only public."notifications" add constraint "notifications_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table only public."pm_parts_requirements" add constraint "pm_parts_requirements_template_id_fkey" FOREIGN KEY (template_id) REFERENCES checklist_templates(id) ON DELETE CASCADE;
alter table only public."work_order_assignments" add constraint "work_order_assignments_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES profiles(id);
alter table only public."work_order_assignments" add constraint "work_order_assignments_work_order_id_fkey" FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table only public."telemetry_alerts" add constraint "telemetry_alerts_acknowledged_by_fkey" FOREIGN KEY (acknowledged_by) REFERENCES profiles(id);
alter table only public."telemetry_alerts" add constraint "telemetry_alerts_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table only public."telemetry_alerts" add constraint "telemetry_alerts_engine_id_fkey" FOREIGN KEY (engine_id) REFERENCES asset_engines(id) ON DELETE SET NULL;
alter table only public."meeting_requests" add constraint "meeting_requests_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES profiles(id);
alter table only public."checklist_assignments" add constraint "checklist_assignments_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id);
alter table only public."checklist_assignments" add constraint "checklist_assignments_assigned_by_fkey" FOREIGN KEY (assigned_by) REFERENCES profiles(id);
alter table only public."checklist_assignments" add constraint "checklist_assignments_assigned_to_fkey" FOREIGN KEY (assigned_to) REFERENCES profiles(id);
alter table only public."checklist_assignments" add constraint "checklist_assignments_org_id_fkey" FOREIGN KEY (org_id) REFERENCES client_orgs(id);
alter table only public."checklist_assignments" add constraint "checklist_assignments_template_id_fkey" FOREIGN KEY (template_id) REFERENCES checklist_templates(id);
alter table only public."checklist_responses" add constraint "checklist_responses_checklist_item_id_fkey" FOREIGN KEY (checklist_item_id) REFERENCES checklist_items(id);
alter table only public."checklist_responses" add constraint "checklist_responses_completed_by_fkey" FOREIGN KEY (completed_by) REFERENCES profiles(id);
alter table only public."checklist_responses" add constraint "checklist_responses_work_order_id_fkey" FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table only public."operator_checklist_responses" add constraint "operator_checklist_responses_checklist_item_id_fkey" FOREIGN KEY (checklist_item_id) REFERENCES checklist_items(id);
alter table only public."operator_checklist_responses" add constraint "operator_checklist_responses_run_id_fkey" FOREIGN KEY (run_id) REFERENCES operator_checklist_runs(id) ON DELETE CASCADE;
alter table only public."devices" add constraint "devices_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE SET NULL;
alter table only public."devices" add constraint "devices_linked_by_fkey" FOREIGN KEY (linked_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table only public."telemetry_readings" add constraint "telemetry_readings_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table only public."telemetry_readings" add constraint "telemetry_readings_engine_id_fkey" FOREIGN KEY (engine_id) REFERENCES asset_engines(id) ON DELETE SET NULL;
alter table only public."client_capabilities" add constraint "client_capabilities_client_id_fkey" FOREIGN KEY (client_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table only public."client_capabilities" add constraint "client_capabilities_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table only public."client_orgs" add constraint "client_orgs_owner_profile_id_fkey" FOREIGN KEY (owner_profile_id) REFERENCES profiles(id);
alter table only public."saved_checklists" add constraint "saved_checklists_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table only public."saved_checklists" add constraint "saved_checklists_client_id_fkey" FOREIGN KEY (client_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table only public."saved_checklists" add constraint "saved_checklists_submitted_by_fkey" FOREIGN KEY (submitted_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table only public."saved_checklists" add constraint "saved_checklists_template_id_fkey" FOREIGN KEY (template_id) REFERENCES checklist_templates(id) ON DELETE SET NULL;
alter table only public."saved_checklists" add constraint "saved_checklists_work_order_id_fkey" FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE SET NULL;
alter table only public."service_requests" add constraint "service_requests_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE SET NULL;
alter table only public."service_requests" add constraint "service_requests_client_id_fkey" FOREIGN KEY (client_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table only public."service_requests" add constraint "service_requests_generated_work_order_id_fkey" FOREIGN KEY (generated_work_order_id) REFERENCES work_orders(id) ON DELETE SET NULL;
alter table only public."service_requests" add constraint "service_requests_handled_by_fkey" FOREIGN KEY (handled_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table only public."service_requests" add constraint "service_requests_source_maintenance_request_id_fkey" FOREIGN KEY (source_maintenance_request_id) REFERENCES maintenance_requests(id) ON DELETE SET NULL;
alter table only public."telemetry_gateway_health" add constraint "telemetry_gateway_health_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE SET NULL;

-- Indexes not owned by constraints
CREATE INDEX idx_service_reminders_service_interval_id ON public.service_reminders USING btree (service_interval_id);
CREATE INDEX service_reports_work_order_id_idx ON public.service_reports USING btree (work_order_id);
CREATE INDEX service_report_photos_service_report_id_idx ON public.service_report_photos USING btree (service_report_id);
CREATE INDEX idx_org_codes_org_id ON public.org_codes USING btree (org_id);
CREATE INDEX idx_profiles_org_id ON public.profiles USING btree (org_id);
CREATE INDEX notifications_user_unread ON public.notifications USING btree (user_id, read, created_at DESC);
CREATE INDEX idx_telemetry_alerts_acknowledged ON public.telemetry_alerts USING btree (acknowledged);
CREATE INDEX idx_telemetry_alerts_asset ON public.telemetry_alerts USING btree (asset_id, created_at DESC);
CREATE INDEX idx_telemetry_alerts_asset_created ON public.telemetry_alerts USING btree (asset_id, created_at DESC);
CREATE INDEX idx_telemetry_alerts_asset_unacked ON public.telemetry_alerts USING btree (asset_id, acknowledged, created_at DESC) WHERE (NOT acknowledged);
CREATE INDEX idx_telemetry_alerts_device ON public.telemetry_alerts USING btree (device_id, created_at DESC) WHERE (device_id IS NOT NULL);
CREATE INDEX idx_telemetry_alerts_engine ON public.telemetry_alerts USING btree (engine_id, created_at DESC);
CREATE INDEX idx_telemetry_alerts_engine_id ON public.telemetry_alerts USING btree (engine_id);
CREATE INDEX idx_telemetry_alerts_unacked ON public.telemetry_alerts USING btree (engine_id, acknowledged, created_at DESC) WHERE (NOT acknowledged);
CREATE INDEX telemetry_alerts_engine_id ON public.telemetry_alerts USING btree (engine_id, created_at DESC);
CREATE INDEX devices_asset_id_idx ON public.devices USING btree (asset_id);
CREATE UNIQUE INDEX devices_device_id_idx ON public.devices USING btree (device_id) WHERE (device_id IS NOT NULL);
CREATE INDEX devices_pairing_code_idx ON public.devices USING btree (pairing_code);
CREATE INDEX idx_telemetry_readings_asset_ts ON public.telemetry_readings USING btree (asset_id, ts DESC);
CREATE INDEX idx_telemetry_readings_device_ts ON public.telemetry_readings USING btree (device_id, ts DESC) WHERE (device_id IS NOT NULL);
CREATE INDEX idx_telemetry_readings_engine_ts ON public.telemetry_readings USING btree (engine_id, ts DESC);
CREATE INDEX idx_telemetry_readings_ts ON public.telemetry_readings USING btree (ts DESC);
CREATE INDEX telemetry_readings_engine_ts ON public.telemetry_readings USING btree (engine_id, ts DESC);
CREATE INDEX client_capabilities_client_id_idx ON public.client_capabilities USING btree (client_id);
CREATE INDEX saved_checklists_asset_id_submitted_at_idx ON public.saved_checklists USING btree (asset_id, submitted_at DESC);
CREATE INDEX saved_checklists_checklist_type_idx ON public.saved_checklists USING btree (checklist_type);
CREATE INDEX saved_checklists_client_id_submitted_at_idx ON public.saved_checklists USING btree (client_id, submitted_at DESC);
CREATE INDEX saved_checklists_source_type_idx ON public.saved_checklists USING btree (source_type);
CREATE INDEX saved_checklists_work_order_id_idx ON public.saved_checklists USING btree (work_order_id) WHERE (work_order_id IS NOT NULL);
CREATE INDEX service_requests_asset_id_idx ON public.service_requests USING btree (asset_id) WHERE (asset_id IS NOT NULL);
CREATE INDEX service_requests_client_created_idx ON public.service_requests USING btree (client_id, created_at DESC);
CREATE INDEX service_requests_status_created_idx ON public.service_requests USING btree (status, created_at DESC);
CREATE INDEX idx_telemetry_gateway_health_asset_ts ON public.telemetry_gateway_health USING btree (asset_id, ts DESC);
CREATE INDEX idx_telemetry_gateway_health_device_ts ON public.telemetry_gateway_health USING btree (device_id, ts DESC);

-- Public functions
CREATE OR REPLACE FUNCTION public.get_my_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  select role from profiles where id = auth.uid()
$function$;
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_code text;
  v_org_id uuid;
  v_intended_role text;
  v_role text;
  v_subscription_tier integer;
begin
  v_org_code := upper(nullif(new.raw_user_meta_data->>'org_code_used', ''));

  if v_org_code is not null then
    select oc.org_id, oc.intended_role
      into v_org_id, v_intended_role
    from public.org_codes oc
    where oc.code = v_org_code
    limit 1;
  end if;

  v_role := coalesce(
    v_intended_role,
    nullif(new.raw_user_meta_data->>'role', ''),
    'client'
  );

  v_subscription_tier := coalesce(
    nullif(new.raw_user_meta_data->>'subscription_tier', '')::integer,
    0
  );

  insert into public.profiles (
    id,
    email,
    full_name,
    role,
    org_id,
    org_code_used,
    preferred_language,
    subscription_tier,
    created_at,
    updated_at
  )
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), new.email, ''),
    v_role,
    coalesce(v_org_id, nullif(new.raw_user_meta_data->>'org_id', '')::uuid),
    v_org_code,
    coalesce(nullif(new.raw_user_meta_data->>'preferred_language', ''), 'en'),
    v_subscription_tier,
    now(),
    now()
  )
  on conflict (id) do update set
    email = excluded.email,
    full_name = excluded.full_name,
    role = excluded.role,
    org_id = excluded.org_id,
    org_code_used = excluded.org_code_used,
    preferred_language = excluded.preferred_language,
    subscription_tier = excluded.subscription_tier,
    updated_at = now();

  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION public.set_client_capabilities_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION public.set_service_requests_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION public.update_engine_hours_from_telemetry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  -- Only update engine hours when this reading is tied to a known engine.
  if new.engine_id is not null and new.engine_hours is not null then
    update public.asset_engines
    set
      current_hours = new.engine_hours,
      updated_at = now()
    where id = new.engine_id
      and (current_hours is null or current_hours < new.engine_hours);
  end if;

  return new;
end;
$function$;

-- Privileges
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on all tables in schema public to postgres, anon, authenticated, service_role;
grant all on all sequences in schema public to postgres, anon, authenticated, service_role;
grant execute on all functions in schema public to postgres, anon, authenticated, service_role;

-- Row-level security and public policies
alter table public."parts" enable row level security;
create policy "Employee manages assigned WO parts"
on public."parts"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM work_orders
  WHERE ((work_orders.id = parts.work_order_id) AND (work_orders.assigned_to = auth.uid())))));
create policy "Owner and employee delete parts"
on public."parts"
as permissive
for delete
to authenticated
using ((get_my_role() = ANY (ARRAY['owner'::text, 'employee'::text])));
create policy "Owner and employee insert parts"
on public."parts"
as permissive
for insert
to authenticated
with check ((get_my_role() = ANY (ARRAY['owner'::text, 'employee'::text])));
create policy "Owner full access"
on public."parts"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."invoices" enable row level security;
create policy "Client reads own"
on public."invoices"
as permissive
for select
to public
using (((client_id = auth.uid()) AND (status = ANY (ARRAY['sent'::text, 'paid'::text]))));
create policy "Org admin sees org invoices"
on public."invoices"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM (profiles p
     JOIN client_orgs co ON ((co.owner_profile_id = invoices.client_id)))
  WHERE ((p.id = auth.uid()) AND (p.org_id = co.id) AND (p.role = 'client_admin'::text)))));
create policy "Owner full access"
on public."invoices"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."asset_types" enable row level security;
create policy "All authenticated read"
on public."asset_types"
as permissive
for select
to public
using ((auth.uid() IS NOT NULL));
create policy "Owner full access"
on public."asset_types"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."imported_docs" enable row level security;
create policy "Owner full access"
on public."imported_docs"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."checklist_items" enable row level security;
create policy "Client admin reads checklist items"
on public."checklist_items"
as permissive
for select
to public
using ((get_my_role() = 'client_admin'::text));
create policy "Client mechanic reads checklist items"
on public."checklist_items"
as permissive
for select
to public
using ((get_my_role() = 'client_mechanic'::text));
create policy "Employee read"
on public."checklist_items"
as permissive
for select
to public
using ((get_my_role() = ANY (ARRAY['owner'::text, 'employee'::text])));
create policy "Operator read daily items"
on public."checklist_items"
as permissive
for select
to public
using (((get_my_role() = 'operator'::text) AND (EXISTS ( SELECT 1
   FROM checklist_templates
  WHERE ((checklist_templates.id = checklist_items.template_id) AND (checklist_templates.checklist_type = 'operator_daily'::text))))));
create policy "Owner full access"
on public."checklist_items"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."asset_engines" enable row level security;
create policy "Client sees own"
on public."asset_engines"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM assets
  WHERE ((assets.id = asset_engines.asset_id) AND (assets.client_id = auth.uid())))));
create policy "Employee sees assigned"
on public."asset_engines"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM work_orders
  WHERE ((work_orders.asset_id = asset_engines.asset_id) AND (work_orders.assigned_to = auth.uid())))));
create policy "Operator sees all"
on public."asset_engines"
as permissive
for select
to public
using ((get_my_role() = 'operator'::text));
create policy "Org members see org engines"
on public."asset_engines"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM ((assets a
     JOIN client_orgs co ON ((co.owner_profile_id = a.client_id)))
     JOIN profiles p ON ((p.org_id = co.id)))
  WHERE ((a.id = asset_engines.asset_id) AND (p.id = auth.uid()) AND (p.role = ANY (ARRAY['client_admin'::text, 'client_mechanic'::text, 'client_operator'::text]))))));
create policy "Owner full access"
on public."asset_engines"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."asset_service_intervals" enable row level security;
create policy "Employee reads"
on public."asset_service_intervals"
as permissive
for select
to public
using ((get_my_role() = ANY (ARRAY['owner'::text, 'employee'::text])));
create policy "Owner full access"
on public."asset_service_intervals"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."work_orders" enable row level security;
create policy "Assigned profiles can view assigned work orders"
on public."work_orders"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM work_order_assignments woa
  WHERE ((woa.work_order_id = work_orders.id) AND (woa.profile_id = auth.uid())))));
create policy "Employee sees all"
on public."work_orders"
as permissive
for select
to authenticated
using ((get_my_role() = 'employee'::text));
create policy "Employee updates assigned"
on public."work_orders"
as permissive
for update
to public
using ((assigned_to = auth.uid()));
create policy "Owner full access"
on public."work_orders"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."operator_checklist_runs" enable row level security;
create policy "Client reads own asset runs"
on public."operator_checklist_runs"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM assets
  WHERE ((assets.id = operator_checklist_runs.asset_id) AND (assets.client_id = auth.uid())))));
create policy "Operator manages own runs"
on public."operator_checklist_runs"
as permissive
for all
to public
using ((operator_id = auth.uid()));
create policy "Org admin sees org checklist runs"
on public."operator_checklist_runs"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM ((assets a
     JOIN client_orgs co ON ((co.owner_profile_id = a.client_id)))
     JOIN profiles p ON ((p.org_id = co.id)))
  WHERE ((a.id = operator_checklist_runs.asset_id) AND (p.id = auth.uid()) AND (p.role = 'client_admin'::text)))));
create policy "Owner full access"
on public."operator_checklist_runs"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."checklist_templates" enable row level security;
create policy "Client admin reads templates"
on public."checklist_templates"
as permissive
for select
to public
using ((get_my_role() = 'client_admin'::text));
create policy "Client mechanic reads PM templates"
on public."checklist_templates"
as permissive
for select
to public
using (((get_my_role() = 'client_mechanic'::text) AND (checklist_type = 'pm'::text)));
create policy "Employee read"
on public."checklist_templates"
as permissive
for select
to public
using ((get_my_role() = ANY (ARRAY['owner'::text, 'employee'::text])));
create policy "Operator read daily"
on public."checklist_templates"
as permissive
for select
to public
using (((checklist_type = 'operator_daily'::text) AND (get_my_role() = 'operator'::text)));
create policy "Owner full access"
on public."checklist_templates"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."service_reminders" enable row level security;
create policy "Client reads own"
on public."service_reminders"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM assets
  WHERE ((assets.id = service_reminders.asset_id) AND (assets.client_id = auth.uid())))));
create policy "Owner full access"
on public."service_reminders"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."assets" enable row level security;
create policy "Client org staff read org assets"
on public."assets"
as permissive
for select
to authenticated
using ((EXISTS ( SELECT 1
   FROM (profiles p
     JOIN client_orgs co ON ((co.id = p.org_id)))
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['client_admin'::text, 'client_mechanic'::text, 'client_operator'::text, 'operator'::text])) AND (co.owner_profile_id = assets.client_id)))));
create policy "Clients can read assigned assets"
on public."assets"
as permissive
for select
to authenticated
using ((client_id = auth.uid()));
create policy "Owners can delete assets"
on public."assets"
as permissive
for delete
to authenticated
using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'owner'::text)))));
create policy "Owners can insert assets"
on public."assets"
as permissive
for insert
to authenticated
with check ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'owner'::text)))));
create policy "Owners can read all assets"
on public."assets"
as permissive
for select
to authenticated
using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'owner'::text)))));
create policy "Owners can update assets"
on public."assets"
as permissive
for update
to authenticated
using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'owner'::text)))))
with check ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'owner'::text)))));
create policy "Service role full access assets"
on public."assets"
as permissive
for all
to service_role
using (true)
with check (true);
alter table public."service_reports" enable row level security;
create policy "Client reads closed"
on public."service_reports"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM work_orders
  WHERE ((work_orders.id = service_reports.work_order_id) AND (work_orders.client_id = auth.uid()) AND (work_orders.status = ANY (ARRAY['invoiced'::text, 'closed'::text]))))));
create policy "Clients read own asset service reports"
on public."service_reports"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM (work_orders wo
     JOIN assets a ON ((a.id = wo.asset_id)))
  WHERE ((wo.id = service_reports.work_order_id) AND (a.client_id = auth.uid())))));
create policy "Employee inserts service reports"
on public."service_reports"
as permissive
for insert
to public
with check ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['owner'::text, 'employee'::text]))))));
create policy "Employee manages own"
on public."service_reports"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM work_orders
  WHERE ((work_orders.id = service_reports.work_order_id) AND (work_orders.assigned_to = auth.uid())))));
create policy "Employee updates service reports"
on public."service_reports"
as permissive
for update
to public
using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['owner'::text, 'employee'::text]))))));
create policy "Org members read associated service reports"
on public."service_reports"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM (((work_orders wo
     JOIN assets a ON ((a.id = wo.asset_id)))
     JOIN client_orgs co ON ((co.owner_profile_id = a.client_id)))
     JOIN profiles p ON ((p.org_id = co.id)))
  WHERE ((wo.id = service_reports.work_order_id) AND (p.id = auth.uid()) AND (p.role = ANY (ARRAY['client_admin'::text, 'client_mechanic'::text, 'operator'::text, 'client_operator'::text]))))));
create policy "Owner full access"
on public."service_reports"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
create policy "Service role full access service reports"
on public."service_reports"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
create policy "Staff manage service reports"
on public."service_reports"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'employee'::text]))))))
with check ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'employee'::text]))))));
create policy "Staff read service reports"
on public."service_reports"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'employee'::text]))))));
alter table public."service_report_photos" enable row level security;
create policy "Client reads closed"
on public."service_report_photos"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM (service_reports sr
     JOIN work_orders wo ON ((wo.id = sr.work_order_id)))
  WHERE ((sr.id = service_report_photos.service_report_id) AND (wo.client_id = auth.uid()) AND (wo.status = ANY (ARRAY['invoiced'::text, 'closed'::text]))))));
create policy "Clients read own asset service report photos"
on public."service_report_photos"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM ((service_reports sr
     JOIN work_orders wo ON ((wo.id = sr.work_order_id)))
     JOIN assets a ON ((a.id = wo.asset_id)))
  WHERE ((sr.id = service_report_photos.service_report_id) AND (a.client_id = auth.uid())))));
create policy "Employee manages own"
on public."service_report_photos"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM (service_reports sr
     JOIN work_orders wo ON ((wo.id = sr.work_order_id)))
  WHERE ((sr.id = service_report_photos.service_report_id) AND (wo.assigned_to = auth.uid())))));
create policy "Org members read associated service report photos"
on public."service_report_photos"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM ((((service_reports sr
     JOIN work_orders wo ON ((wo.id = sr.work_order_id)))
     JOIN assets a ON ((a.id = wo.asset_id)))
     JOIN client_orgs co ON ((co.owner_profile_id = a.client_id)))
     JOIN profiles p ON ((p.org_id = co.id)))
  WHERE ((sr.id = service_report_photos.service_report_id) AND (p.id = auth.uid()) AND (p.role = ANY (ARRAY['client_admin'::text, 'client_mechanic'::text, 'operator'::text, 'client_operator'::text]))))));
create policy "Owner full access"
on public."service_report_photos"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
create policy "Service role full access service report photos"
on public."service_report_photos"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
create policy "Staff manage service report photos"
on public."service_report_photos"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'employee'::text]))))))
with check ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'employee'::text]))))));
create policy "Staff read service report photos"
on public."service_report_photos"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'employee'::text]))))));
alter table public."org_codes" enable row level security;
create policy "Owner full access"
on public."org_codes"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."profiles" enable row level security;
create policy "Owner full access"
on public."profiles"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
create policy "Self read"
on public."profiles"
as permissive
for select
to public
using ((auth.uid() = id));
alter table public."hour_logs" enable row level security;
create policy "Employee logs hours"
on public."hour_logs"
as permissive
for insert
to public
with check ((get_my_role() = 'employee'::text));
create policy "Employee reads own logs"
on public."hour_logs"
as permissive
for select
to public
using ((logged_by = auth.uid()));
create policy "Owner full access"
on public."hour_logs"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."parts_catalog" enable row level security;
create policy "Employee insert"
on public."parts_catalog"
as permissive
for insert
to public
with check ((get_my_role() = 'employee'::text));
create policy "Employee read"
on public."parts_catalog"
as permissive
for select
to public
using ((get_my_role() = ANY (ARRAY['owner'::text, 'employee'::text])));
create policy "Employee update"
on public."parts_catalog"
as permissive
for update
to public
using ((get_my_role() = 'employee'::text));
create policy "Owner full access"
on public."parts_catalog"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."parts_inventory" enable row level security;
create policy "Employee insert"
on public."parts_inventory"
as permissive
for insert
to public
with check ((get_my_role() = 'employee'::text));
create policy "Employee read"
on public."parts_inventory"
as permissive
for select
to public
using ((get_my_role() = ANY (ARRAY['owner'::text, 'employee'::text])));
create policy "Employee update"
on public."parts_inventory"
as permissive
for update
to public
using ((get_my_role() = 'employee'::text));
create policy "Owner full access"
on public."parts_inventory"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."maintenance_requests" enable row level security;
create policy "Client reads own asset requests"
on public."maintenance_requests"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM assets
  WHERE ((assets.id = maintenance_requests.asset_id) AND (assets.client_id = auth.uid())))));
create policy "Operator manages own"
on public."maintenance_requests"
as permissive
for all
to public
using ((flagged_by = auth.uid()));
create policy "Org members see org asset flags"
on public."maintenance_requests"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM ((assets a
     JOIN client_orgs co ON ((co.owner_profile_id = a.client_id)))
     JOIN profiles p ON ((p.org_id = co.id)))
  WHERE ((a.id = maintenance_requests.asset_id) AND (p.id = auth.uid()) AND (p.role = ANY (ARRAY['client_admin'::text, 'client_mechanic'::text, 'client_operator'::text]))))));
create policy "Owner full access"
on public."maintenance_requests"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."notifications" enable row level security;
create policy "Authenticated users can insert notifications"
on public."notifications"
as permissive
for insert
to authenticated
with check (true);
create policy "Users can mark own notifications read"
on public."notifications"
as permissive
for update
to authenticated
using ((user_id = auth.uid()));
create policy "Users see own notifications"
on public."notifications"
as permissive
for select
to authenticated
using ((user_id = auth.uid()));
alter table public."pm_parts_requirements" enable row level security;
create policy "Client reads PM parts"
on public."pm_parts_requirements"
as permissive
for select
to public
using ((get_my_role() = ANY (ARRAY['client'::text, 'client_admin'::text, 'client_mechanic'::text, 'client_operator'::text])));
create policy "Employee read"
on public."pm_parts_requirements"
as permissive
for select
to public
using ((get_my_role() = ANY (ARRAY['owner'::text, 'employee'::text])));
create policy "Owner full access"
on public."pm_parts_requirements"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."work_order_assignments" enable row level security;
create policy "Employee sees all assignments"
on public."work_order_assignments"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'employee'::text)))));
create policy "Owner sees all assignments"
on public."work_order_assignments"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'owner'::text)))));
create policy "Tech sees own assignments"
on public."work_order_assignments"
as permissive
for select
to public
using ((profile_id = auth.uid()));
alter table public."telemetry_alerts" enable row level security;
create policy "Client reads own asset telemetry alerts"
on public."telemetry_alerts"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM assets a
  WHERE ((a.id = telemetry_alerts.asset_id) AND (a.client_id = auth.uid())))));
create policy "Device can insert alerts"
on public."telemetry_alerts"
as permissive
for insert
to public
with check (true);
create policy "Employee reads assigned asset telemetry alerts"
on public."telemetry_alerts"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM work_orders wo
  WHERE ((wo.asset_id = telemetry_alerts.asset_id) AND (wo.assigned_to = auth.uid())))));
create policy "Org members read org asset telemetry alerts"
on public."telemetry_alerts"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM ((assets a
     JOIN client_orgs co ON ((co.owner_profile_id = a.client_id)))
     JOIN profiles p ON ((p.org_id = co.id)))
  WHERE ((a.id = telemetry_alerts.asset_id) AND (p.id = auth.uid()) AND (p.role = ANY (ARRAY['client_admin'::text, 'client_mechanic'::text, 'client_operator'::text, 'operator'::text]))))));
create policy "Owner full access telemetry alerts"
on public."telemetry_alerts"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text))
with check ((get_my_role() = 'owner'::text));
create policy "Service role full access telemetry alerts"
on public."telemetry_alerts"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
alter table public."meeting_requests" enable row level security;
create policy "Client creates own meeting requests"
on public."meeting_requests"
as permissive
for insert
to public
with check ((profile_id = auth.uid()));
create policy "Client sees own meeting requests"
on public."meeting_requests"
as permissive
for select
to public
using ((profile_id = auth.uid()));
create policy "Owner sees all meeting requests"
on public."meeting_requests"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'owner'::text)))));
alter table public."checklist_assignments" enable row level security;
create policy "Assignee sees own assignments"
on public."checklist_assignments"
as permissive
for select
to public
using ((assigned_to = auth.uid()));
create policy "Assignee updates own assignments"
on public."checklist_assignments"
as permissive
for update
to public
using ((assigned_to = auth.uid()));
create policy "Client admin manages org assignments"
on public."checklist_assignments"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.org_id = checklist_assignments.org_id) AND (p.role = 'client_admin'::text)))));
create policy "Owner full access"
on public."checklist_assignments"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."checklist_responses" enable row level security;
create policy "Assigned profiles can insert WO checklist responses"
on public."checklist_responses"
as permissive
for insert
to public
with check (((completed_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM work_order_assignments woa
  WHERE ((woa.work_order_id = checklist_responses.work_order_id) AND (woa.profile_id = auth.uid()))))));
create policy "Assigned profiles can update WO checklist responses"
on public."checklist_responses"
as permissive
for update
to public
using ((EXISTS ( SELECT 1
   FROM work_order_assignments woa
  WHERE ((woa.work_order_id = checklist_responses.work_order_id) AND (woa.profile_id = auth.uid())))))
with check (((completed_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM work_order_assignments woa
  WHERE ((woa.work_order_id = checklist_responses.work_order_id) AND (woa.profile_id = auth.uid()))))));
create policy "Assigned profiles can view WO checklist responses"
on public."checklist_responses"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM work_order_assignments woa
  WHERE ((woa.work_order_id = checklist_responses.work_order_id) AND (woa.profile_id = auth.uid())))));
create policy "Client admin reads org responses"
on public."checklist_responses"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM (((work_orders wo
     JOIN profiles p ON ((p.id = wo.assigned_to)))
     JOIN client_orgs co ON ((co.id = p.org_id)))
     JOIN profiles admin ON ((admin.id = auth.uid())))
  WHERE ((wo.id = checklist_responses.work_order_id) AND (admin.org_id = co.id) AND (admin.role = 'client_admin'::text)))));
create policy "Client mechanic manages own responses"
on public."checklist_responses"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM work_orders
  WHERE ((work_orders.id = checklist_responses.work_order_id) AND (work_orders.assigned_to = auth.uid())))));
create policy "Employee manages own WO responses"
on public."checklist_responses"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM work_orders
  WHERE ((work_orders.id = checklist_responses.work_order_id) AND (work_orders.assigned_to = auth.uid())))));
create policy "Owner full access"
on public."checklist_responses"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."operator_checklist_responses" enable row level security;
create policy "Operator manages own"
on public."operator_checklist_responses"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM operator_checklist_runs
  WHERE ((operator_checklist_runs.id = operator_checklist_responses.run_id) AND (operator_checklist_runs.operator_id = auth.uid())))));
create policy "Owner full access"
on public."operator_checklist_responses"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text));
alter table public."devices" enable row level security;
create policy "Clients can read their asset device"
on public."devices"
as permissive
for select
to public
using ((asset_id IN ( SELECT assets.id
   FROM assets
  WHERE (assets.client_id = auth.uid()))));
create policy "Owners can read devices"
on public."devices"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'owner'::text)))));
create policy "Owners can update devices"
on public."devices"
as permissive
for update
to public
using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'owner'::text)))));
create policy "Service role full access"
on public."devices"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text));
alter table public."telemetry_readings" enable row level security;
create policy "Client reads own asset telemetry readings"
on public."telemetry_readings"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM assets a
  WHERE ((a.id = telemetry_readings.asset_id) AND (a.client_id = auth.uid())))));
create policy "Device can insert telemetry"
on public."telemetry_readings"
as permissive
for insert
to public
with check (true);
create policy "Employee reads assigned asset telemetry readings"
on public."telemetry_readings"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM work_orders wo
  WHERE ((wo.asset_id = telemetry_readings.asset_id) AND (wo.assigned_to = auth.uid())))));
create policy "Org members read org asset telemetry readings"
on public."telemetry_readings"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM ((assets a
     JOIN client_orgs co ON ((co.owner_profile_id = a.client_id)))
     JOIN profiles p ON ((p.org_id = co.id)))
  WHERE ((a.id = telemetry_readings.asset_id) AND (p.id = auth.uid()) AND (p.role = ANY (ARRAY['client_admin'::text, 'client_mechanic'::text, 'client_operator'::text, 'operator'::text]))))));
create policy "Owner full access telemetry readings"
on public."telemetry_readings"
as permissive
for all
to public
using ((get_my_role() = 'owner'::text))
with check ((get_my_role() = 'owner'::text));
create policy "Service role full access telemetry readings"
on public."telemetry_readings"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
alter table public."client_capabilities" enable row level security;
create policy "Clients can read own capabilities"
on public."client_capabilities"
as permissive
for select
to public
using ((client_id = auth.uid()));
create policy "Owners can manage client capabilities"
on public."client_capabilities"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'owner'::text)))))
with check ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'owner'::text)))));
create policy "Owners can read client capabilities"
on public."client_capabilities"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'owner'::text)))));
create policy "Service role full access to client capabilities"
on public."client_capabilities"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
alter table public."client_orgs" enable row level security;
create policy "Client org members read own org"
on public."client_orgs"
as permissive
for select
to authenticated
using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.org_id = client_orgs.id)))));
create policy "Client org owners read own org"
on public."client_orgs"
as permissive
for select
to authenticated
using ((owner_profile_id = auth.uid()));
create policy "Owner manages all orgs"
on public."client_orgs"
as permissive
for all
to public
using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'owner'::text)))));
alter table public."saved_checklists" enable row level security;
create policy "Clients read own asset saved checklists"
on public."saved_checklists"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM assets a
  WHERE ((a.id = saved_checklists.asset_id) AND (a.client_id = auth.uid())))));
create policy "Clients submit own asset saved checklists"
on public."saved_checklists"
as permissive
for insert
to public
with check (((client_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM assets a
  WHERE ((a.id = saved_checklists.asset_id) AND (a.client_id = auth.uid()))))));
create policy "Org members read associated saved checklists"
on public."saved_checklists"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM ((assets a
     JOIN client_orgs co ON ((co.owner_profile_id = a.client_id)))
     JOIN profiles p ON ((p.org_id = co.id)))
  WHERE ((a.id = saved_checklists.asset_id) AND (p.id = auth.uid()) AND ((p.role = ANY (ARRAY['client_admin'::text, 'client_mechanic'::text])) OR ((p.role = ANY (ARRAY['operator'::text, 'client_operator'::text])) AND (saved_checklists.checklist_type = 'operations'::text)))))));
create policy "Org members submit associated saved checklists"
on public."saved_checklists"
as permissive
for insert
to public
with check ((EXISTS ( SELECT 1
   FROM ((assets a
     JOIN client_orgs co ON ((co.owner_profile_id = a.client_id)))
     JOIN profiles p ON ((p.org_id = co.id)))
  WHERE ((a.id = saved_checklists.asset_id) AND (p.id = auth.uid()) AND (a.client_id = saved_checklists.client_id) AND ((p.role = ANY (ARRAY['client_admin'::text, 'client_mechanic'::text])) OR ((p.role = ANY (ARRAY['operator'::text, 'client_operator'::text])) AND (saved_checklists.checklist_type = 'operations'::text)))))));
create policy "Service role full access saved checklists"
on public."saved_checklists"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
create policy "Staff read saved checklists"
on public."saved_checklists"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'employee'::text]))))));
create policy "Staff submit saved checklists"
on public."saved_checklists"
as permissive
for insert
to public
with check ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'employee'::text]))))));
alter table public."service_requests" enable row level security;
create policy "Client admins can read org service requests"
on public."service_requests"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM (client_orgs co
     JOIN profiles p ON ((p.org_id = co.id)))
  WHERE ((p.id = auth.uid()) AND (p.role = 'client_admin'::text) AND (co.owner_profile_id = service_requests.client_id)))));
create policy "Client admins can submit org service requests"
on public."service_requests"
as permissive
for insert
to public
with check (((status = 'new'::text) AND (generated_work_order_id IS NULL) AND (handled_at IS NULL) AND (handled_by IS NULL) AND (EXISTS ( SELECT 1
   FROM (client_orgs co
     JOIN profiles p ON ((p.org_id = co.id)))
  WHERE ((p.id = auth.uid()) AND (p.role = 'client_admin'::text) AND (co.owner_profile_id = service_requests.client_id)))) AND ((asset_id IS NULL) OR (EXISTS ( SELECT 1
   FROM assets a
  WHERE ((a.id = service_requests.asset_id) AND (a.client_id = service_requests.client_id)))))));
create policy "Clients can read own service requests"
on public."service_requests"
as permissive
for select
to public
using ((client_id = auth.uid()));
create policy "Clients can submit own service requests"
on public."service_requests"
as permissive
for insert
to public
with check (((client_id = auth.uid()) AND (status = 'new'::text) AND (generated_work_order_id IS NULL) AND (handled_at IS NULL) AND (handled_by IS NULL) AND ((asset_id IS NULL) OR (EXISTS ( SELECT 1
   FROM assets a
  WHERE ((a.id = service_requests.asset_id) AND (a.client_id = auth.uid())))))));
create policy "Service role full access service requests"
on public."service_requests"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
create policy "Staff can manage service requests"
on public."service_requests"
as permissive
for all
to public
using ((get_my_role() = ANY (ARRAY['owner'::text, 'employee'::text])))
with check ((get_my_role() = ANY (ARRAY['owner'::text, 'employee'::text])));
create policy "Staff can read service requests"
on public."service_requests"
as permissive
for select
to public
using ((get_my_role() = ANY (ARRAY['owner'::text, 'employee'::text])));
alter table public."telemetry_gateway_health" enable row level security;
create policy "Clients read own asset gateway health"
on public."telemetry_gateway_health"
as permissive
for select
to public
using ((asset_id IN ( SELECT assets.id
   FROM assets
  WHERE (assets.client_id = auth.uid()))));
create policy "Owners read gateway health"
on public."telemetry_gateway_health"
as permissive
for select
to public
using ((get_my_role() = 'owner'::text));
create policy "Service role full access to gateway health"
on public."telemetry_gateway_health"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

-- Application triggers
CREATE TRIGGER trg_update_engine_hours AFTER INSERT ON public.telemetry_readings FOR EACH ROW EXECUTE FUNCTION update_engine_hours_from_telemetry();
CREATE TRIGGER trg_client_capabilities_updated_at BEFORE UPDATE ON public.client_capabilities FOR EACH ROW EXECUTE FUNCTION set_client_capabilities_updated_at();
CREATE TRIGGER trg_service_requests_updated_at BEFORE UPDATE ON public.service_requests FOR EACH ROW EXECUTE FUNCTION set_service_requests_updated_at();
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Storage buckets
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('service-report-photos', 'service-report-photos', false, null, null) on conflict (id) do update set name = excluded.name, public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('service-request-photos', 'service-request-photos', true, 10485760, array['image/jpeg', 'image/png', 'image/webp']::text[]) on conflict (id) do update set name = excluded.name, public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('signatures', 'signatures', false, null, null) on conflict (id) do update set name = excluded.name, public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Application storage policies
create policy "Authenticated read report photos"
on storage.objects
as permissive
for select
to authenticated
using ((bucket_id = 'service-report-photos'::text));
create policy "Authenticated read signatures"
on storage.objects
as permissive
for select
to authenticated
using ((bucket_id = 'signatures'::text));
create policy "Authenticated update signatures"
on storage.objects
as permissive
for update
to authenticated
using ((bucket_id = 'signatures'::text));
create policy "Authenticated upload report photos"
on storage.objects
as permissive
for insert
to authenticated
with check ((bucket_id = 'service-report-photos'::text));
create policy "Authenticated upload signatures"
on storage.objects
as permissive
for insert
to authenticated
with check ((bucket_id = 'signatures'::text));
create policy "Authenticated users can upload service request photos"
on storage.objects
as permissive
for insert
to authenticated
with check (((bucket_id = 'service-request-photos'::text) AND (auth.uid() IS NOT NULL)));
create policy "Public can view service request photos"
on storage.objects
as permissive
for select
to public
using ((bucket_id = 'service-request-photos'::text));

reset check_function_bodies;
