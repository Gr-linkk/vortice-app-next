# Batch 2 — Free Tier Dashboard + Meeting Request + Invoice Overhaul

## Context
Flutter app at `/home/garrett/.openclaw/workspace/vortice-app`. Uses Supabase, Riverpod, Freezed, GoRouter, l10n (EN + ES). Read existing code patterns before changing anything.

**CRITICAL:** Dart/Flutter is NOT installed on this machine. Do NOT run `dart run build_runner` or `flutter build`. Just write correct code.

## Task List

### 1. Create MeetingRequest model

Create `lib/models/meeting_request.dart` — Freezed model:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'meeting_request.freezed.dart';
part 'meeting_request.g.dart';

@freezed
class MeetingRequest with _$MeetingRequest {
  const factory MeetingRequest({
    required String id,
    @JsonKey(name: 'profile_id') required String profileId,
    String? interest,
    @JsonKey(name: 'vessel_count') String? vesselCount,
    @JsonKey(name: 'contact_method') String? contactMethod,
    String? notes,
    @JsonKey(defaultValue: 'pending') required String status,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _MeetingRequest;

  factory MeetingRequest.fromJson(Map<String, dynamic> json) =>
      _$MeetingRequestFromJson(json);
}
```

### 2. Create MeetingRequest provider

Create `lib/features/meeting/meeting_provider.dart`:
- `meetingRequestsProvider` — FutureProvider that fetches from `meeting_requests` table
- `MeetingRequestController` — StateNotifier with:
  - `submitRequest({interest, vesselCount, contactMethod, notes})` — inserts into meeting_requests using current user's profile ID
  - After submit, invalidate the provider

Follow the pattern in `lib/features/invoices/invoice_provider.dart`.

### 3. Create Meeting Request Screen

Create `lib/features/meeting/meeting_request_screen.dart`:

A form screen for Free tier clients to request a consultation with Vórtice.

**Fields:**
- "What are you looking for?" — dropdown with options:
  - Routine Maintenance
  - Repair
  - Fleet Management
  - Telemetry & Monitoring
  - Other
- "How many vessels?" — dropdown: 1, 2-5, 5+
- "Preferred contact method" — dropdown: WhatsApp, Email, Phone
- "Anything else we should know?" — multiline text field (optional)
- Submit button: "Request Consultation"

**On submit:**
- Save to meeting_requests table
- Show success SnackBar: "Request sent! We'll be in touch within 24 hours."
- Pop back to dashboard

**Style:** Follow existing form patterns (see register_screen.dart for reference). Use AppColors and existing theme.

### 4. Create Free Tier Client Dashboard

Create `lib/features/dashboard/client_dashboard_free.dart`:

This is what a Free tier (T0) client sees after signing up.

**Layout (scrollable column):**

1. **Welcome Card** (top, prominent):
   - "Welcome to Vórtice" heading
   - "View your vessels and service history, or schedule a consultation to discuss maintenance plans."
   - Styled with a subtle brand color background

2. **My Vessels** section:
   - Header: "My Vessels"
   - If no assets: empty state card — "No vessels yet. Contact Vórtice to get started."
   - If assets exist: list of asset cards (name, type, icon) — tap navigates to asset detail
   - Read-only — no "Add" button (owner creates all assets)

3. **Service History** section:
   - Header: "Service History"  
   - If no completed WOs: "No service history yet."
   - If exists: list of completed WOs with date, title, asset name — tap to view

4. **Invoices** section:
   - Header: "Invoices"
   - If none: "No invoices yet."
   - If exists: list showing invoice number, amount, status (draft/sent/paid) — tap to detail

5. **Schedule Consultation** button (bottom, prominent):
   - Full-width ElevatedButton
   - Navigates to the meeting request screen
   - "Schedule a Consultation"

**Data fetching:** Use existing providers (assetsProvider, workOrdersProvider filtered by client, invoicesProvider). Filter to current user's client_id.

### 5. Create Managed Tier Client Dashboard

Create `lib/features/dashboard/client_dashboard_managed.dart`:

This is what a Managed tier (T1) client sees. Everything from Free plus upcoming work.

**Layout (scrollable column):**

1. **Upcoming Work** card (top, prominent):
   - Header: "Upcoming Work"
   - Shows WOs with status assigned/in_progress for client's assets
   - Each row: asset name, WO title, scheduled date, status chip
   - Empty state: "No upcoming work scheduled."

2. **Recent Activity** section:
   - Recently completed WOs (last 30 days)
   - Each row: date, WO title, asset name — tap to view service report

3. **My Vessels** section (same as Free)

4. **Invoices** section (same as Free)

5. **Service Reports** section:
   - Header: "Service Reports"
   - List of available service reports with PDF download button
   - Empty state if none

### 6. Wire client dashboard routing by tier

Modify the client dashboard routing so the correct dashboard shows based on tier:

Find where the client dashboard is rendered (likely in `lib/features/dashboard/` or `lib/core/app_shell.dart`).

- If `subscriptionTier == free` → show `ClientDashboardFree`
- If `subscriptionTier == managed` → show `ClientDashboardManaged`
- If `subscriptionTier >= planning` → show existing client dashboard (or `ClientDashboardManaged` for now)

Import the tier from the profile and use `effectiveTier()` from `tier_gate.dart`.

### 7. Add meeting request route

In `lib/core/router.dart`:
- Add route: `/meeting-request` → `MeetingRequestScreen`
- Import the screen

### 8. Invoice edit screen — make parts cost optional for tech

In `lib/models/part.dart`:
- Change `required double unitCost` to `@Default(0) double unitCost`

This lets techs log parts without knowing the cost. Owner fills it in on the invoice.

### 9. Invoice — global markup default with per-part override

In `lib/core/constants.dart` (or create a new config), add:
```dart
static const double defaultPartsMarkupPct = 15.0;
static const double defaultBillableRate = 60.0;
```

Update `lib/core/invoice_service.dart` to reference these constants instead of inline values.

### 10. Invoice — Send button becomes PDF share

In `lib/features/invoices/invoice_detail_screen.dart`:

Find the "Send Invoice" button. Currently it just flips status to 'sent'.

Change it to:
1. Generate the PDF using the existing `InvoicePdfService`
2. Open the system share sheet with the PDF file (use `share_plus` package if available, or `open_file`)
3. THEN flip the status to 'sent'

Check if `share_plus` is already in pubspec.yaml. If not, note it as a required dependency but do NOT add it — just leave a TODO comment.

### 11. Invoice — lock after sent/paid

In `lib/features/invoices/invoice_detail_screen.dart`:

If the invoice status is `sent` or `paid`:
- All text fields should be read-only (enabled: false)
- Hide the edit/save buttons
- Show only "Export PDF", "Export Excel", and (if sent) "Mark Paid"

Check if this is already implemented from Batch 1's task 10. If so, verify it works correctly and skip.

### 12. Add table name constants

In `lib/core/constants.dart`, add if not already present:
```dart
static const String tWorkOrderAssignments = 'work_order_assignments';
static const String tClientOrgs = 'client_orgs';
static const String tMeetingRequests = 'meeting_requests';
```

## Important Notes
- Do NOT run `dart run build_runner` or `flutter build` — Dart is not installed on this machine
- Do NOT modify test files
- Follow existing code patterns exactly (Riverpod, Freezed, GoRouter, l10n)
- Use `AppColors` and existing theme — no hardcoded colors
- Reference existing screens for layout patterns
- Write correct Freezed model code even though build_runner can't run here
