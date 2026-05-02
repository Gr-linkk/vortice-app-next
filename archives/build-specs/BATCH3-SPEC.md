# Batch 3 — Planning Tier + Org System + Operator Fixes

## Context
Flutter app at `/home/garrett/.openclaw/workspace/vortice-app`. Uses Supabase, Riverpod, Freezed, GoRouter, l10n (EN + ES).

**CRITICAL:** Dart/Flutter is NOT installed on this machine. Do NOT run `dart run build_runner` or `flutter build`. Just write correct code.

Read existing code before changing anything. Follow existing patterns exactly.

## Task List

### 1. Create ClientOrg model

Create `lib/models/client_org.dart` — Freezed model:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_org.freezed.dart';
part 'client_org.g.dart';

@freezed
class ClientOrg with _$ClientOrg {
  const factory ClientOrg({
    required String id,
    required String name,
    @JsonKey(name: 'owner_profile_id') required String ownerProfileId,
    @JsonKey(name: 'subscription_tier') @Default(0) int subscriptionTier,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _ClientOrg;

  factory ClientOrg.fromJson(Map<String, dynamic> json) =>
      _$ClientOrgFromJson(json);
}
```

### 2. Create ClientOrg provider

Create `lib/features/orgs/org_provider.dart`:
- `clientOrgsProvider` — FutureProvider that fetches all from `client_orgs` table (owner sees all)
- `orgByIdProvider` — FutureProvider.family<ClientOrg?, String>
- `orgMembersProvider` — FutureProvider.family<List<Profile>, String> that fetches profiles where `org_id = orgId`
- `OrgController` — StateNotifier with:
  - `createOrg(String name, String ownerProfileId)` — insert into client_orgs, set owner's org_id
  - `addMember(String orgId, String profileId)` — update profile's org_id
  - `removeMember(String profileId)` — set profile's org_id to null
  - `deleteOrg(String orgId)` — delete org + null out all members' org_id

Follow the pattern in `lib/features/invoices/invoice_provider.dart`.

### 3. Create Client Admin Panel screen

Create `lib/features/orgs/org_admin_screen.dart`:

This is the screen a `client_admin` sees to manage their organization.

**AppBar:** Org name as title

**Tabs or sections:**

**Team tab:**
- List of org members (name, role badge: mechanic/operator, email)
- Each member has a "Remove" button (with confirmation dialog)
- "Invite Team Member" FAB or button at bottom
- Tapping "Invite" shows a bottom sheet:
  - Role picker: Mechanic or Operator
  - Name field
  - Email field
  - "Send Invite" button
  - On submit: generate a single-use org code scoped to this org + role, show the code in a dialog for the admin to share (we'll add email sending later)

**Fleet tab:**
- List of org's assets (same as asset list but filtered to org's client_id)
- Read-only — no add/edit (owner creates assets)

**Work Orders tab:**
- List of WOs for org's assets
- Tap to view detail

**Invoices tab:**
- List of invoices for this org
- Tap to view detail

Use `DefaultTabController` with `TabBar` + `TabBarView`. Follow existing screen patterns.

### 4. Create Client Mechanic Dashboard

Create `lib/features/dashboard/client_mechanic_dashboard.dart`:

What a `client_mechanic` sees when they log in.

**Layout (scrollable column):**

1. **Assigned Work** (top, prominent):
   - Header: "My Assigned Work"
   - List of WOs assigned to this mechanic (via work_order_assignments where profile_id = current user)
   - Each card: asset name, WO title, status chip, scheduled date
   - Tap → WO detail screen
   - Empty state: "No work assigned yet."

2. **Checklists** section:
   - Header: "Checklists"
   - Active checklists for assigned WOs
   - Tap → checklist screen

3. **Parts Lists** section:
   - Header: "Parts Lists"
   - Parts lists for fleet assets (read-only)
   - Shows parts catalog entries scoped to org's assets

**Cannot see:** Invoices, other orgs, asset creation, WO creation

### 5. Create Client Operator Dashboard

Create `lib/features/dashboard/client_operator_dashboard.dart`:

What a `client_operator` sees.

**Layout (scrollable column):**

1. **Pre-Departure Checklists** (top):
   - Header: "Pre-Departure Checklists"
   - List of assigned assets with a "Start Checklist" button each
   - Tap → opens pre-departure checklist for that asset
   - Empty state: "No assets assigned."

2. **Flag an Issue** button:
   - Prominent button to flag an issue on any assigned asset
   - Opens the existing flag issue screen

3. **Recent Checks** section:
   - History of completed pre-departure checklists
   - Date, asset name, pass/fail status

### 6. Update dashboard routing for new roles

Modify `lib/features/dashboard/client_dashboard_free.dart` (where `ClientDashboardRouter` lives):

Update the router to handle all client-type roles:
- `UserRole.client` with tier 0 → `ClientDashboardFree`
- `UserRole.client` with tier 1 → `ClientDashboardManaged`
- `UserRole.client` with tier >= 2 → `ClientDashboardManaged` (for now)
- `UserRole.clientAdmin` → `OrgAdminScreen` (the admin panel from task 3)
- `UserRole.clientMechanic` → `ClientMechanicDashboard`
- `UserRole.clientOperator` → `ClientOperatorDashboard`

Also update `lib/core/app_shell.dart` — the bottom navigation bar should show different items based on role:
- `client_admin`: Dashboard, Fleet, Work Orders, Invoices, Settings
- `client_mechanic`: Dashboard, Work Orders, Checklists, Settings
- `client_operator`: Dashboard, Checklists, Settings

Read the existing app_shell.dart carefully to understand current nav structure before modifying.

### 7. Invite flow — extend org codes for org scoping

Modify the existing org code system to support org-scoped invites.

Check the org_codes table structure. We need to add `org_id` to org codes so that when someone registers with an org-scoped code, they automatically get linked to that org.

**Write SQL to `supabase-migrations/batch3.sql`:**
```sql
-- Add org_id to org_codes for org-scoped invites
ALTER TABLE org_codes ADD COLUMN IF NOT EXISTS org_id UUID REFERENCES client_orgs(id);

-- When a client_admin creates an invite code, it's scoped to their org
-- The register flow will set the new user's org_id based on the code's org_id
```

**Modify `lib/features/auth/auth_provider.dart`:**
In the `signUp()` method, after validating the org code:
- If the org code has an `org_id`, set the new user's `org_id` to that value
- The `intended_role` on the org code determines the user's role

### 8. Owner dashboard — organize by client/org

Modify `lib/features/dashboard/owner_dashboard.dart`:

Currently shows flat lists. Reorganize:

**Layout:**
1. **KPI row** (keep existing clickable cards: Total Assets, Open Orders, etc.)

2. **Clients section** — replace flat WO list with client-organized view:
   - Header: "Clients"
   - Each client card shows:
     - Client name + tier badge (Free/Managed/Planning/Telemetry)
     - Vessel count
     - Open WO count
     - Latest activity date
   - Tap → navigates to client detail
   - Sorted by most recent activity

3. **Alerts section** (placeholder for telemetry):
   - Header: "Alerts"
   - Empty state for now: "No active alerts"
   - Will be populated when telemetry is live

### 9. Fix operator scoping (#8, #16)

The operator currently sees all clients' assets. Fix this:

In operator-related screens (search for operator screens in `lib/features/operator/`):
- Filter assets to only those assigned to the operator
- For now, use `work_order_assignments` where `profile_id = current user` to determine which assets the operator is associated with
- If no assignment table link exists for operators, filter by the operator's `org_id` (if they belong to a client org)

### 10. Owner can create service reports (#6)

Find the service report creation screen. Currently it checks for `UserRole.employee` (tech only).

Change the guard to allow both `employee` AND `owner`:
```dart
if (profile.role == UserRole.employee || profile.role == UserRole.owner)
```

Search for all places where service report creation is role-gated and update them.

### 11. Verify tech cannot edit WOs (#11)

Check `lib/features/work_orders/work_order_detail_screen.dart`:
- The edit button/sheet should only be visible for `UserRole.owner`
- If tech can currently see the edit button, add a role check
- Tech should only be able to: view WO, start work, complete work, log hours, add parts, fill checklist

### 12. Service intervals config screen (#19)

Create `lib/features/service_intervals/service_interval_screen.dart`:

Owner screen to configure which maintenance intervals apply to which asset.

**Layout:**
- AppBar: "Service Intervals"  
- Asset picker dropdown at top (select an asset)
- When asset selected, show list of configured intervals:
  - Each row: interval hours (250, 500, 1000, etc.), checklist template name, last completed date
  - Swipe to delete
- FAB to add new interval:
  - Bottom sheet with:
    - Hours field (e.g., 250)
    - Checklist template dropdown (from existing templates)
    - Save button

**Provider:** Create `lib/features/service_intervals/service_interval_provider.dart`:
- Fetch from `asset_service_intervals` table filtered by asset_id
- CRUD operations

**Model:** Check if `lib/models/asset_service_interval.dart` already exists. If so, use it. If not, create a Freezed model matching the `asset_service_intervals` table.

### 13. Add routes for new screens

In `lib/core/router.dart`, add routes:
- `/org/admin` → `OrgAdminScreen`
- `/service-intervals` → `ServiceIntervalScreen`

## Important Notes
- Do NOT run `dart run build_runner` or `flutter build`
- Do NOT add dependencies to pubspec.yaml
- Follow existing code patterns exactly
- Use `AppColors` and existing theme
- Check for existing implementations before writing new code
- When modifying screens, read the entire file first to understand the current structure
