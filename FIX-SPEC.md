# Vórtice App — Full Model/Schema Alignment Fix Spec

## Context
A full audit of the Flutter app revealed that many Dart models, providers, and Drift tables don't match the actual Supabase schema (`projects/vortice-schema.sql`). This spec covers EVERY fix needed.

## Ground Rules
- The Supabase schema (`projects/vortice-schema.sql`) is the **source of truth** — do NOT change it
- Fix the Dart side to match the DB, not the other way around
- After changing models, update the corresponding providers and screens that reference changed fields
- Do NOT run `build_runner` — we'll do that separately
- Preserve all existing functionality and UI behavior
- Keep the dark navy theme and all l10n references intact

---

## FIX 1: `lib/models/service_report.dart` — Complete rewrite

Current model has: `description`, `hoursWorked`, `signatureUrl`, `clientSignatureUrl`, `technicianId`

Supabase `service_reports` table has:
```sql
id uuid PK
work_order_id uuid FK NOT NULL UNIQUE
complaint text
cause text
correction text
collateral text
comments text
tech_signature_url text
signed_at timestamptz
created_at timestamptz
updated_at timestamptz
```

**Fix:** Replace model fields to match:
```dart
@freezed
class ServiceReport with _$ServiceReport {
  const factory ServiceReport({
    required String id,
    @JsonKey(name: 'work_order_id') required String workOrderId,
    String? complaint,
    String? cause,
    String? correction,
    String? collateral,
    String? comments,
    @JsonKey(name: 'tech_signature_url') String? techSignatureUrl,
    @JsonKey(name: 'signed_at') DateTime? signedAt,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _ServiceReport;

  factory ServiceReport.fromJson(Map<String, dynamic> json) => _$ServiceReportFromJson(json);
}
```

Also update `ServiceReportsTable` in `lib/db/database.dart` to match (remove `technicianId`, `description`, `hoursWorked`, `clientSignatureUrl`; add `complaint`, `cause`, `correction`, `collateral`, `comments`, `techSignatureUrl`, `signedAt`).

---

## FIX 2: `lib/models/invoice.dart` — Complete rewrite

Current model has: `amount`, `taxAmount`, `orgId`, `createdBy`, and statuses `overdue`/`cancelled`

Supabase `invoices` table has:
```sql
id uuid PK
work_order_id uuid FK NOT NULL UNIQUE
client_id uuid FK NOT NULL
invoice_number text NOT NULL UNIQUE
status text NOT NULL DEFAULT 'draft' CHECK (status in ('draft','sent','paid','void'))
labour_hours numeric(6,2)
billable_rate_usd numeric(8,2)
labour_total_usd numeric(10,2)
parts_total_usd numeric(10,2)
consumables_total_usd numeric(10,2)
subtotal_usd numeric(10,2)
iva_pct numeric(5,2) DEFAULT 16.00
iva_total_usd numeric(10,2)
total_usd numeric(10,2)
exchange_rate numeric(10,4)
total_mxn numeric(12,2)
notes text
pdf_url text
xlsx_url text
sent_at timestamptz
paid_at timestamptz
created_at timestamptz
updated_at timestamptz
```

**Fix:** Rewrite the model completely:
```dart
enum InvoiceStatus {
  @JsonValue('draft') draft,
  @JsonValue('sent') sent,
  @JsonValue('paid') paid,
  @JsonValue('void') voided; // 'void' is a Dart keyword, use 'voided' with @JsonValue('void')

  String get dbValue => switch (this) {
    InvoiceStatus.voided => 'void',
    _ => name,
  };
}

@freezed
class Invoice with _$Invoice {
  const factory Invoice({
    required String id,
    @JsonKey(name: 'work_order_id') required String workOrderId,
    @JsonKey(name: 'client_id') required String clientId,
    @JsonKey(name: 'invoice_number') required String invoiceNumber,
    @JsonKey(defaultValue: InvoiceStatus.draft) required InvoiceStatus status,
    @JsonKey(name: 'labour_hours') double? labourHours,
    @JsonKey(name: 'billable_rate_usd') double? billableRateUsd,
    @JsonKey(name: 'labour_total_usd') double? labourTotalUsd,
    @JsonKey(name: 'parts_total_usd') double? partsTotalUsd,
    @JsonKey(name: 'consumables_total_usd') double? consumablesTotalUsd,
    @JsonKey(name: 'subtotal_usd') double? subtotalUsd,
    @JsonKey(name: 'iva_pct') @Default(16.0) double ivaPct,
    @JsonKey(name: 'iva_total_usd') double? ivaTotalUsd,
    @JsonKey(name: 'total_usd') double? totalUsd,
    @JsonKey(name: 'exchange_rate') double? exchangeRate,
    @JsonKey(name: 'total_mxn') double? totalMxn,
    String? notes,
    @JsonKey(name: 'pdf_url') String? pdfUrl,
    @JsonKey(name: 'xlsx_url') String? xlsxUrl,
    @JsonKey(name: 'sent_at') DateTime? sentAt,
    @JsonKey(name: 'paid_at') DateTime? paidAt,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Invoice;

  factory Invoice.fromJson(Map<String, dynamic> json) => _$InvoiceFromJson(json);
}
```

Update `InvoicesTable` in Drift, `invoice_provider.dart`, and `invoice_screen.dart` to use new fields (e.g., `totalUsd` instead of `amount`, `ivaTotalUsd` instead of `taxAmount`, statuses `voided` instead of `cancelled`/`overdue`).

---

## FIX 3: `lib/models/part.dart` — Field name fixes

Current: `name`, `addedBy`, `unitCost` nullable, no `markupPct`
Supabase: `description`, `logged_by`, `unit_cost NOT NULL`, `markup_pct DEFAULT 15.00`

**Fix:**
```dart
@freezed
class Part with _$Part {
  const factory Part({
    required String id,
    @JsonKey(name: 'work_order_id') required String workOrderId,
    required String description,
    @JsonKey(name: 'part_number') String? partNumber,
    String? supplier,
    @JsonKey(defaultValue: 1) required double quantity, // numeric(8,2) in DB
    @JsonKey(name: 'unit_cost') required double unitCost,
    @JsonKey(name: 'markup_pct') @Default(15.0) double markupPct,
    String? notes,
    @JsonKey(name: 'logged_by') String? loggedBy,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Part;

  factory Part.fromJson(Map<String, dynamic> json) => _$PartFromJson(json);
}
```

Remove `catalogId` (not in DB). Update `parts_provider.dart` (change `name` → `description`, `added_by` → `logged_by`, make `unit_cost` required). Update `parts_log_screen.dart` (change `part.name` → `part.description`).

---

## FIX 4: `lib/models/checklist_item.dart` — Field name fixes

Current: `question`, `itemType`, `isRequired`, `sortOrder`, `notes`
Supabase: `description_en`, `description_es`, `category`, `requires_photo`, `sort_order`

**Fix:**
```dart
@freezed
class ChecklistItem with _$ChecklistItem {
  const factory ChecklistItem({
    required String id,
    @JsonKey(name: 'template_id') required String templateId,
    @JsonKey(name: 'description_en') required String descriptionEn,
    @JsonKey(name: 'description_es') String? descriptionEs,
    String? category,
    @JsonKey(name: 'requires_photo') @Default(false) bool requiresPhoto,
    @JsonKey(name: 'sort_order') @Default(0) int sortOrder,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _ChecklistItem;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => _$ChecklistItemFromJson(json);
}
```

Remove the `ChecklistItemType` enum entirely (DB has no item_type column). Update `checklist_screen.dart` and `operator_checklist_screen.dart`:
- Replace `item.question` with `item.descriptionEn` (and use `descriptionEs` when locale is 'es')
- Remove the switch on `item.itemType` — all checklist items are pass/fail with optional photo (use `item.requiresPhoto` to show photo button)
- Remove `item.isRequired` references

---

## FIX 5: `lib/models/checklist_response.dart` — Field fixes

Current: `response`, `respondedBy`
Supabase: `completed` (boolean), `completed_by`, `completed_at`, `notes`, `photo_url`

**Fix:**
```dart
@freezed
class ChecklistResponse with _$ChecklistResponse {
  const factory ChecklistResponse({
    required String id,
    @JsonKey(name: 'work_order_id') required String workOrderId,
    @JsonKey(name: 'checklist_item_id') required String checklistItemId,
    @Default(false) bool completed,
    String? notes,
    @JsonKey(name: 'photo_url') String? photoUrl,
    @JsonKey(name: 'completed_by') String? completedBy,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _ChecklistResponse;

  factory ChecklistResponse.fromJson(Map<String, dynamic> json) =>
      _$ChecklistResponseFromJson(json);
}
```

Update `checklist_provider.dart`:
- `submitResponse()` — change `response` → `completed` (true/false), `responded_by` → `completed_by`, add `completed_at`
- `submitBatch()` — same changes, send `completed: true` instead of response strings
- `onConflict` — remove it (no unique constraint on work_order_id + checklist_item_id)

Update checklist screens to use `completed` (boolean) instead of `response` (string 'pass'/'fail').

---

## FIX 6: `lib/models/checklist_template.dart` — Add missing fields

Current: has `isOperatorChecklist`, `orgId` (neither in DB)
Supabase: has `checklist_type`, `interval_hours`, `interval_label`, `version`, `is_active`, `source_doc_id`, `created_by`

**Fix:**
```dart
@freezed
class ChecklistTemplate with _$ChecklistTemplate {
  const factory ChecklistTemplate({
    required String id,
    @JsonKey(name: 'asset_type_id') String? assetTypeId,
    @JsonKey(name: 'checklist_type') @Default('pm') String checklistType,
    @JsonKey(name: 'interval_hours') int? intervalHours,
    @JsonKey(name: 'interval_label') String? intervalLabel,
    required String name,
    String? description,
    @Default(1) int version,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
    @JsonKey(name: 'source_doc_id') String? sourceDocId,
    @JsonKey(name: 'created_by') String? createdBy,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _ChecklistTemplate;

  factory ChecklistTemplate.fromJson(Map<String, dynamic> json) =>
      _$ChecklistTemplateFromJson(json);
}
```

Update `operator_checklist_screen.dart`: replace `t.isOperatorChecklist` with `t.checklistType == 'operator_daily'`.

---

## FIX 7: `lib/models/profile.dart` — Fix to match DB

Current: has `orgId`, `avatarUrl` (neither in DB)
Supabase: has `org_code_used`, `preferred_language`

**Fix:**
```dart
@freezed
class Profile with _$Profile {
  const factory Profile({
    required String id,
    required String email,
    @JsonKey(name: 'full_name') required String fullName,
    @JsonKey(defaultValue: UserRole.employee) required UserRole role,
    String? phone,
    @JsonKey(name: 'preferred_language') @Default('en') String preferredLanguage,
    @JsonKey(name: 'org_code_used') String? orgCodeUsed,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);
}
```

Update references: `profile?.orgId` → remove (not used critically anywhere except operator screens sending `org_id` in inserts — those need to be removed too since the tables don't have org_id).

---

## FIX 8: `lib/features/work_orders/work_order_provider.dart` — Drift cache status bug

Line ~30: `status: Value(wo.status.name)` → `status: Value(wo.status.dbValue)`

---

## FIX 9: `lib/db/database.dart` — Drift tables alignment

### AssetsTable
- Remove `orgId` and `status` columns (not in Supabase)
- Keep `manufacturer` (maps from `make` in the provider — it's the local column name for Drift)

### ServiceReportsTable  
- Remove: `technicianId`, `description`, `hoursWorked`, `clientSignatureUrl`
- Add: `complaint`, `cause`, `correction`, `collateral`, `comments`, `techSignatureUrl`, `signedAt`

### InvoicesTable
- Remove: `orgId`, `amount`, `taxAmount`, `createdBy`
- Add: `labourHours`, `billableRateUsd`, `labourTotalUsd`, `partsTotalUsd`, `consumablesTotalUsd`, `subtotalUsd`, `ivaPct`, `ivaTotalUsd`, `totalUsd`, `exchangeRate`, `totalMxn`, `pdfUrl`, `xlsxUrl`, `sentAt`
- Keep: `workOrderId`, `clientId`, `invoiceNumber`, `status`, `notes`, `paidAt`, `dueDate` → actually remove `dueDate` (not in Supabase)

### PartsTable
- Rename `name` → `description`
- Rename `addedBy` → `loggedBy`
- Add `markupPct` (real, nullable)
- Change `quantity` from integer to real (DB uses numeric(8,2))
- Remove `catalogId` (not in DB)
- Add `updatedAt`

### ChecklistTemplatesTable
- Remove: `orgId`, `isOperatorChecklist`
- Add: `checklistType`, `intervalHours`, `intervalLabel`, `version`, `isActive`, `sourceDocId`, `createdBy`

### ChecklistItemsTable
- Remove: `question`, `itemType`, `isRequired`
- Add: `descriptionEn`, `descriptionEs`, `category`, `requiresPhoto`

### ChecklistResponsesTable
- Remove: `response`, `respondedBy`
- Add: `completed` (boolean), `completedBy`, `completedAt`

### ProfilesTable
- Remove: `orgId`, `avatarUrl`
- Add: `preferredLanguage`, `orgCodeUsed`

### Bump `schemaVersion` to 3 and add a `MigrationStrategy` that does `destructive fallback` (this is a dev app, no production data to preserve):
```dart
@override
MigrationStrategy get migration => MigrationStrategy(
  onUpgrade: (m, from, to) async {
    // Dev-only: drop and recreate all tables
    for (final table in allTables) {
      await m.deleteTable(table.actualTableName);
    }
    await m.createAll();
  },
);
```

---

## FIX 10: `lib/features/parts/parts_provider.dart` — Field name fixes

Change in `addPart()`:
- `'name'` → `'description'`
- `'added_by'` → `'logged_by'`
- Add `'markup_pct': 15.0` (default)
- `'unit_cost'` must be required (not nullable)

---

## FIX 11: `lib/features/parts/parts_log_screen.dart` — Update field references

- `part.name` → `part.description`
- `part.addedBy` → `part.loggedBy`
- `_nameCtrl` → `_descCtrl` (or just rename the label)

---

## FIX 12: `lib/features/invoices/invoice_provider.dart` — Fix status values

- `markAsPaid`: `'status': InvoiceStatus.paid.name` → `'status': 'paid'` (same but explicit)
- `updateStatus`: use `.dbValue` pattern (important for `voided` → `'void'`)
- Remove `orgId` and `createdBy` from any insert maps

---

## FIX 13: `lib/features/invoices/invoice_screen.dart` — Update for new model

- Replace `invoice.amount + invoice.taxAmount` with `invoice.totalUsd ?? 0`
- Replace `InvoiceStatus.overdue` → remove (doesn't exist)
- Replace `InvoiceStatus.cancelled` → `InvoiceStatus.voided`
- Update grouping logic to use `draft`/`sent`/`paid`/`voided`

---

## FIX 14: `lib/features/service_reports/service_report_provider.dart` — Already correct

The `createReport()` method already sends the correct 5-C field names. Just need to verify it matches after model change (it should, since the method params already use complaint/cause/correction/collateral/comments).

But add `'technician_id'` — wait, the DB table has no `technician_id`. The report is linked to the work order which has `assigned_to`. So this is fine as-is. Just remove any reference to `technicianId` in the insert map if present.

---

## FIX 15: `lib/features/operator/maintenance_flag_screen.dart` — Multiple field fixes

Supabase `maintenance_requests` table:
```sql
id uuid PK
asset_id uuid FK NOT NULL
flagged_by uuid FK NOT NULL  -- NOT client_id
description text NOT NULL
photo_url text
severity text DEFAULT 'normal' CHECK (severity in ('normal', 'urgent'))  -- NOT priority (low/medium/high)
status text NOT NULL DEFAULT 'open' CHECK (status in ('open','acknowledged','converted','dismissed'))
converted_to_work_order_id uuid FK
client_notified_at timestamptz
owner_notified_at timestamptz
created_at timestamptz
updated_at timestamptz
```

**Fixes needed:**
- `'client_id': profile?.id` → `'flagged_by': profile?.id`
- Remove `'org_id': profile?.orgId` entirely (no org_id column)
- `'priority': _priority` → `'severity': _severity` and change the values from `low/medium/high` to `normal/urgent` (only 2 options, not 3)
- Update the UI: remove the 3-button priority picker, replace with 2-button severity picker (Normal / Urgent)
- Remove the `_priority` state variable, replace with `_severity = 'normal'`

---

## FIX 16: `lib/features/operator/operator_checklist_screen.dart` — Multiple fixes

Supabase `operator_checklist_runs` table:
```sql
id uuid PK
asset_id uuid FK NOT NULL
engine_id uuid FK
template_id uuid FK NOT NULL
operator_id uuid FK NOT NULL
run_type text NOT NULL CHECK (run_type in ('pre_departure', 'post_trip'))
trip_hours numeric(6,1)
fuel_added numeric(8,2)
notes text
completed_at timestamptz
created_at timestamptz
```

Supabase `operator_checklist_responses` table:
```sql
id uuid PK
run_id uuid FK NOT NULL
checklist_item_id uuid FK NOT NULL
result text NOT NULL CHECK (result in ('good', 'needs_attention', 'not_applicable'))
notes text
photo_url text
created_at timestamptz
```

**Fixes needed:**
- Remove `'org_id': profile?.orgId` from the runs insert
- Remove `'started_at'` from insert (not a column)
- Add `'run_type': 'pre_departure'` (required, add a selector in UI for pre_departure vs post_trip)
- In the responses insert: change `'response': e.value` → `'result': e.value`
- Remove `'responded_by': profile?.id` from responses (not a column)
- Update the toggle UI to use 3 states: Good (✓) / Needs Attention (⚠) / N/A (—) instead of Pass/Fail
- Change response values from 'pass'/'fail' to 'good'/'needs_attention'/'not_applicable'

---

## FIX 17: `lib/features/auth/auth_provider.dart` — Registration fix

Supabase `org_codes` table:
```sql
id uuid PK
code text NOT NULL UNIQUE
intended_role text CHECK (intended_role in ('employee', 'client', 'operator'))
single_use boolean DEFAULT true
max_uses int DEFAULT 1
use_count int DEFAULT 0
expires_at timestamptz
created_by uuid
notes text
created_at timestamptz
```

There is NO `org_id` column. The current code does:
```dart
final org = await supabase.from(tOrgCodes).select('org_id').eq('code', orgCode).maybeSingle();
```
This will fail because `org_id` doesn't exist.

**Fix:**
```dart
final org = await supabase
    .from(AppConstants.tOrgCodes)
    .select('id, code, intended_role, single_use, max_uses, use_count, expires_at')
    .eq('code', orgCode.toUpperCase())
    .maybeSingle();

if (org == null) throw Exception('invalidOrgCode');

// Check expiry
final expiresAt = org['expires_at'] as String?;
if (expiresAt != null && DateTime.parse(expiresAt).isBefore(DateTime.now())) {
  throw Exception('orgCodeExpired');
}

// Check usage
final singleUse = org['single_use'] as bool? ?? true;
final maxUses = org['max_uses'] as int? ?? 1;
final useCount = org['use_count'] as int? ?? 0;
if (singleUse && useCount >= maxUses) {
  throw Exception('orgCodeUsed');
}

await supabase.auth.signUp(
  email: email,
  password: password,
  data: {
    'full_name': fullName,
    'org_code_used': orgCode.toUpperCase(),
  },
);

// Increment use count
await supabase
    .from(AppConstants.tOrgCodes)
    .update({'use_count': useCount + 1})
    .eq('id', org['id']);
```

Also remove `'org_id': org['org_id']` from the `data` map in signUp.

---

## FIX 18: `_AddPartSheet` — Remove dead `WidgetRef ref` constructor param

---

## FIX 19: `lib/features/assets/asset_provider.dart` — Remove Drift columns that don't exist

The `upsert` in `assetsProvider` maps `manufacturer: Value(asset.make)` — after fixing AssetsTable to remove `manufacturer`, this needs to map to the correct column name. Actually, keep `manufacturer` as the Drift column name that stores the `make` value, OR rename the Drift column to `make` to match. Cleaner to rename to `make`.

---

## IMPORTANT: Read the rest of the Supabase schema

Before implementing, read `projects/vortice-schema.sql` from line 251 onward to check:
- `maintenance_requests` full column list
- `operator_checklist_runs` full column list  
- `operator_checklist_responses` full column list
- `service_reminders` column list
- `hour_logs` column list
- Any other tables

This is critical for fixes 15, 16, and 17.

---

## Files to modify (complete list):
1. `lib/models/service_report.dart`
2. `lib/models/invoice.dart`
3. `lib/models/part.dart`
4. `lib/models/checklist_item.dart`
5. `lib/models/checklist_response.dart`
6. `lib/models/checklist_template.dart`
7. `lib/models/profile.dart`
8. `lib/db/database.dart`
9. `lib/features/work_orders/work_order_provider.dart`
10. `lib/features/parts/parts_provider.dart`
11. `lib/features/parts/parts_log_screen.dart`
12. `lib/features/invoices/invoice_provider.dart`
13. `lib/features/invoices/invoice_screen.dart`
14. `lib/features/service_reports/service_report_provider.dart`
15. `lib/features/service_reports/service_report_screen.dart`
16. `lib/features/checklists/checklist_provider.dart`
17. `lib/features/checklists/checklist_screen.dart`
18. `lib/features/operator/operator_checklist_screen.dart`
19. `lib/features/operator/maintenance_flag_screen.dart`
20. `lib/features/auth/auth_provider.dart`
21. `lib/features/assets/asset_provider.dart`
22. `lib/features/dashboard/owner_dashboard.dart` (if invoice references changed)
23. `lib/core/app_shell.dart` (if profile.orgId referenced)

Do NOT touch: `lib/main.dart`, `lib/app.dart`, `lib/core/constants.dart`, `lib/core/router.dart`, `lib/core/theme.dart`, `lib/core/supabase_client.dart`, `lib/models/asset.dart`, `lib/models/asset_engine.dart`, `lib/models/work_order.dart`, `lib/features/auth/login_screen.dart`, `lib/features/auth/register_screen.dart`, `lib/features/assets/add_asset_screen.dart`, `lib/features/assets/asset_list_screen.dart`, `lib/features/assets/asset_detail_screen.dart`, `lib/features/dashboard/employee_dashboard.dart`, `lib/features/dashboard/client_dashboard.dart`, `lib/features/dashboard/operator_dashboard.dart`, `lib/features/work_orders/create_work_order_screen.dart`, `lib/features/work_orders/work_order_list_screen.dart`, `lib/features/work_orders/work_order_detail_screen.dart`, `lib/features/service_reports/signature_pad_widget.dart`

Wait — actually some of those "don't touch" files DO need changes:
- `lib/features/auth/register_screen.dart` — if org_codes query changes
- `lib/features/dashboard/operator_dashboard.dart` — references profile?.orgId? No, it doesn't.
- `lib/features/work_orders/work_order_detail_screen.dart` — references checklist route, might need status display fix

Re-check each "don't touch" file for references to changed model fields before finalizing.
