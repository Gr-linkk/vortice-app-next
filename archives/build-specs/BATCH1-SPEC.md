# Batch 1 — Foundation + Quick Fixes

## Context
You are working on a Flutter app at `/home/garrett/.openclaw/workspace/vortice-app`. It uses Supabase, Riverpod, Freezed, GoRouter, and l10n (EN + ES). The app manages marine vessel maintenance for a company called Vórtice Mechanical.

Read existing code before changing it. Follow existing patterns. Do NOT break imports or existing functionality.

After making changes to Freezed models, run: `dart run build_runner build --delete-conflicting-outputs`

## Task List

### 1. Fix default billable rate: $80 → $60

**Files to change:**
- `lib/core/invoice_service.dart` line 65: change `80.0` to `60.0`
- `lib/features/invoices/invoice_detail_screen.dart` line 63: change `'80.00'` to `'60.00'`
- Search for any other references to 80.0 as a billable rate default and change to 60.0

### 2. Add `billable_rate` field to Profile model

Vórtice techs (employees) each have their own billable rate. Add to `lib/models/profile.dart`:
- `@JsonKey(name: 'billable_rate') double? billableRate,`

Run build_runner after.

### 3. Update invoice generation to support multi-tech billing

Currently `invoice_service.dart` reads `workOrder.labourHours` and `workOrder.billableRate`. 

The work_orders table has a single `assigned_to` field. We need to support multiple techs on one WO. 

**Database change needed — write SQL to a file `supabase-migrations/batch1.sql`:**

```sql
-- Multi-tech assignment table
CREATE TABLE IF NOT EXISTS work_order_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES profiles(id),
  role TEXT NOT NULL DEFAULT 'tech', -- 'tech' or 'client_mechanic'
  hours_logged DOUBLE PRECISION,
  billable_rate DOUBLE PRECISION,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(work_order_id, profile_id)
);

-- Enable RLS
ALTER TABLE work_order_assignments ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Owner sees all assignments" ON work_order_assignments
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'owner')
  );

CREATE POLICY "Employee sees all assignments" ON work_order_assignments
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'employee')
  );

CREATE POLICY "Tech sees own assignments" ON work_order_assignments
  FOR SELECT USING (profile_id = auth.uid());

-- Add billable_rate to profiles for per-tech rates
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS billable_rate DOUBLE PRECISION;

-- Client orgs table (needed for Planning+ tier)
CREATE TABLE IF NOT EXISTS client_orgs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  owner_profile_id UUID NOT NULL REFERENCES profiles(id),
  subscription_tier INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE client_orgs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Owner manages all orgs" ON client_orgs
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'owner')
  );

-- Add org_id to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS org_id UUID REFERENCES client_orgs(id);

-- Meeting requests table
CREATE TABLE IF NOT EXISTS meeting_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES profiles(id),
  interest TEXT, -- 'routine_maintenance', 'repair', 'fleet_management', 'telemetry', 'other'
  vessel_count TEXT, -- '1', '2-5', '5+'
  contact_method TEXT, -- 'whatsapp', 'email', 'phone'
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'contacted', 'closed'
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE meeting_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Owner sees all meeting requests" ON meeting_requests
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'owner')
  );

CREATE POLICY "Client creates own meeting requests" ON meeting_requests
  FOR INSERT WITH CHECK (profile_id = auth.uid());

CREATE POLICY "Client sees own meeting requests" ON meeting_requests
  FOR SELECT USING (profile_id = auth.uid());
```

**Write this SQL to `supabase-migrations/batch1.sql`** — do NOT try to execute it.

### 4. Create WorkOrderAssignment model

Create `lib/models/work_order_assignment.dart`:
- Freezed model matching the table above
- Fields: id, workOrderId, profileId, role, hoursLogged, billableRate, startedAt, completedAt, createdAt

Run build_runner after.

### 5. Update InvoiceService for multi-tech billing

In `lib/core/invoice_service.dart`, update `calculateFromWorkOrder()`:

- Fetch assignments from `work_order_assignments` where `work_order_id = workOrderId`
- For each assignment where `role = 'tech'` (NOT 'client_mechanic'):
  - Use assignment's `hours_logged` and `billable_rate` (fallback to tech's profile `billable_rate`, then $60 default)
  - Sum all: total labour hours and total labour cost
- Keep backward compatibility: if no assignments exist, fall back to current behavior (workOrder.labourHours × workOrder.billableRate ?? 60.0)
- Parts calculation stays the same

### 6. Self-serve signup (no org code path)

**Modify `lib/features/auth/register_screen.dart`:**
- Add a boolean toggle/tab at the top: "I have an org code" vs "New client signup"
- When "New client signup" is selected:
  - Hide the org code field
  - Show optional fields: phone, vessel name, vessel type (dropdown), marina/location
- When "I have an org code" is selected:
  - Show current form (org code required)

**Modify `lib/features/auth/auth_provider.dart`:**
- Add a `signUpFreeClient()` method:
  - No org code validation
  - Creates user with role = 'client', subscription_tier = 0
  - Stores optional vessel/phone info in user metadata

### 7. Fix dashboard widgets to be clickable (#9)

In `lib/features/dashboard/owner_dashboard.dart`:
- Find "Total Assets" and "Open Orders" cards/widgets
- Wrap each in an InkWell or GestureDetector
- "Total Assets" navigates to asset list screen
- "Open Orders" navigates to work order list screen
- Apply the same pattern to any other non-clickable stat cards

### 8. Remove post-trip toggle (#18)

Find the post-trip/pre-departure toggle in operator screens. Search for "post.trip", "post_trip", "postTrip", "Pre-Departure", "Post-Trip" across the codebase.
- Remove the toggle
- Default to pre-departure only
- Clean up any dead code related to post-trip

### 9. Dead code cleanup in tier_gate.dart

In `lib/features/subscription/tier_gate.dart`:
- Remove `showInvoicing()` function (Free tier always sees invoices, no gate needed)
- Check all exports are actually imported somewhere — remove unused ones
- Keep: `effectiveTier()`, `tierProvider`, `hasTier()`, `showPlanning()`, `showTelemetry()`

### 10. Invoice UX improvements (#12)

In `lib/features/invoices/invoice_detail_screen.dart`:
- Move "Mark Paid" button from overflow menu to a prominent button at the bottom
- Move "Export PDF" and "Export Excel" to visible icon buttons in the AppBar (not in overflow)
- If invoice status is 'sent' or 'paid', disable editing (lock the form fields)

### 11. Update UserRole enum for new roles

In `lib/models/profile.dart`, add new roles to the enum:
```dart
enum UserRole {
  @JsonValue('owner') owner,
  @JsonValue('employee') employee,
  @JsonValue('client') client,
  @JsonValue('operator') operator,
  @JsonValue('client_admin') clientAdmin,
  @JsonValue('client_mechanic') clientMechanic,
  @JsonValue('client_operator') clientOperator,
}
```

Run build_runner after.

### 12. Run build_runner at the end

After all model changes:
```bash
cd /home/garrett/.openclaw/workspace/vortice-app && dart run build_runner build --delete-conflicting-outputs
```

Fix any compilation errors that come up.

## Important Notes
- Do NOT run `flutter build` — just make sure `dart run build_runner` succeeds
- Do NOT modify test files
- Do NOT add new dependencies to pubspec.yaml without documenting why
- Keep all l10n strings in English — we'll add Spanish later
- Write the SQL migration file but do NOT execute it against Supabase
