# Vórtice session report — 2026-05-08

## Session goal

Deepen the workflow architecture before turning Asset Detail into a real hub, then clean up the half-baked client org / org-code access model that affected asset visibility.

## Final state

- Branch: `main`
- Remote: pushed to `origin/main`
- Latest commit: `9fb27d8 fix: consolidate client org asset access`
- Working tree at audit time: clean
- Live Supabase project touched: `REDACTED_SUPABASE_PROJECT`
- Debug APK built: `build/app/outputs/flutter-apk/app-debug.apk`
- Phone install: blocked because no ADB device was attached and remembered wireless debugging ports refused/timed out.

## Verification

- `flutter analyze` — no issues found
- `flutter test` — all tests passed
- `flutter build apk --debug` — succeeded
- Supabase migrations applied with minimal calls; one verification confirmed `public.handle_new_user` exists as a security definer function.

## What changed

### 1. Workflow seams were deepened

Added clear workflow modules so screens stop acting as the mechanic, service writer, and filing cabinet at the same time.

- `SavedChecklistHistoryWriter` — immutable asset history writer
- `MaintenanceChecklistSubmission` — staff maintenance checklist submission flow
- `OperationsChecklistSubmission` — operator checklist submission flow
- `ClientChecklistSubmission` — client-side asset checklist submission, history-only
- `PreventativeMaintenanceCompletion` — PM closeout/reminder/work-order completion flow
- `AssetWorkflowPolicy` — asset-detail role/action rules, kept separate from capability gates

Important commits:

- `3467382 refactor: deepen checklist history and PM completion workflows`
- `73c5969 refactor: centralize asset workflow role policy`

### 2. Analyzer debt was cleared

Cleaned warning/info noise before feature work.

Important commits:

- `7e0cacb chore: clear analyzer warnings`
- `4411dde chore: replace deprecated form field values`
- `6e658e1 chore: replace deprecated opacity helpers`
- `66e0c82 chore: add analyzer-suggested const constructors`
- `3a77cc2 chore: clear remaining analyzer infos`

### 3. Schema/workflow audit was written

Added `docs/SCHEMA-WORKFLOW-AUDIT-2026-05-08.md`.

Main conclusion: Asset Detail hub v1 was not blocked by a schema migration. Existing schema was good enough if the workflow seams stayed clear.

Commit:

- `7ea541b docs: audit schema fit for workflow hub`

### 4. Asset Detail became a read-only workflow hub

Asset Detail now summarizes:

- latest maintenance checklist
- latest operations checklist
- due/overdue PM count
- new service request count where the role can see it

Then heading was simplified from “Workflow Summary” to “Summary”.

Important commits:

- `027111f feat: add asset workflow summary hub`
- `7d16415 chore: simplify asset summary heading`

### 5. Half-baked Parts Inventory was removed

Removed the old inventory/readiness surface because it was not the real workflow.

Kept:

- PM parts lists
- PM kit setup/list screens
- work-order parts log

Removed:

- parts inventory provider/screen/model
- owner dashboard Parts Inventory card
- inventory-backed PM readiness provider/badges

Commit:

- `c2b47b7 chore: remove parts inventory workflow`

### 6. Client-side Asset Detail checklist submission was added

Client maintenance roles can start a checklist from Asset Detail. These submissions write immutable `saved_checklists` history only.

They intentionally do **not**:

- satisfy PM intervals
- close work orders
- write service-request responses
- notify Vórtice automatically

Commit:

- `7f2656d feat: add client asset checklist submission`

### 7. Asset checklist picker was made machine-specific

Asset Detail checklist picker now filters templates by the asset’s `asset_type_id`, instead of showing global/general templates.

Added Ellicott 460SL dredge pre-op checklist seed linked to `Cutter Suction Dredge`.

Commit:

- `40c1aec fix: filter asset checklist templates by machine`

Migration:

- `20260508143000_seed_dredge_preop_checklist.sql`

Live verification showed the seeded checklist had 49 items.

### 8. Stale cross-account asset cache was fixed

A successful empty remote asset result is now authoritative. The app no longer falls back to stale local cached assets from a previous login.

Commit:

- `8a9730c fix: avoid stale asset cache across logins`

### 9. Asset visibility RLS was tightened

Owner can see/manage all assets. Client sees assets assigned to their profile through `assets.client_id`.

Removed broad legacy visibility such as global operator/org-member access.

Important commits:

- `a99421b fix: add owner-client asset visibility policies`
- `7a8f782 fix: tighten asset visibility to owner and assigned client`

Migrations:

- `20260508150000_asset_owner_client_visibility.sql`
- `20260508151000_tighten_asset_visibility_policies.sql`

### 10. Client staff asset visibility was added through org membership

Client operators/mechanics now inherit vessel visibility from the client org they belong to:

```text
profiles.org_id
  -> client_orgs.id
  -> client_orgs.owner_profile_id
  -> assets.client_id
```

Current demo data was repaired:

- created client orgs for existing client/client-admin profiles
- assigned demo field-team accounts to the org that owns `Ellicott 460SL`

Commit:

- `b680db7 fix: let client staff see their org assets`

Migration:

- `20260508152000_client_org_staff_asset_visibility.sql`

Verification after RLS:

- Vórtice owner sees all 5 assets
- Client 1 sees `Big Cheese`
- Client 2 sees `Ellicott 460SL`
- client mechanic/operator/test operator see `Ellicott 460SL`

### 11. Org-code / client-org cleanup was completed

Garrett flagged that the visibility issue smelled like half-baked org id/key plumbing. Confirmed.

Added:

- `CONTEXT.md`
- `docs/CLIENT-ORG-ACCESS-MODEL-2026-05-08.md`
- `lib/features/assets/client_team_asset_access.dart`

Centralized client-team fleet lookup and removed duplicated org-owner asset queries from operator/dashboard providers.

Removed the dangerous legacy fallback where an operator with no org/WO assignment could fall back to all assets.

Hardened signup:

- app passes invite `role` + `org_id`
- server-side `handle_new_user()` now uses org codes to set `role`, `org_id`, and `org_code_used`

Commit:

- `9fb27d8 fix: consolidate client org asset access`

Migration:

- `20260508153000_harden_org_code_signup_profiles.sql`

## Supabase migrations added this session

- `20260508143000_seed_dredge_preop_checklist.sql`
- `20260508150000_asset_owner_client_visibility.sql`
- `20260508151000_tighten_asset_visibility_policies.sql`
- `20260508152000_client_org_staff_asset_visibility.sql`
- `20260508153000_harden_org_code_signup_profiles.sql`

## Important decisions

- Asset Detail is a hub/composer, not the workflow mutator.
- `saved_checklists` is the canonical immutable asset history.
- Client-side non-WO checklist submissions are history-only in v1.
- Capability gates stay separate from `AssetWorkflowPolicy`.
- No schema migration just because code seams were renamed.
- Parts Inventory was clutter; PM parts lists and work-order parts logs remain the real workflow.
- Client staff visibility is org-wide fleet visibility for now, not per-asset staff assignment.
- Org codes are invites into a client org and must set both role and org membership.
- No provider should fall back to all assets for client-side staff with no org.

## Known loose ends / next session

1. Reconnect phone ADB and install the already-built debug APK.
   - Current APK: `C:\Users\gr_link\src\vortice-app-main\build\app\outputs\flutter-apk\app-debug.apk`
   - Wireless debugging ports are ephemeral; remembered ports refused/timed out.
2. Smoke-test on phone:
   - owner sees all vessels
   - Client 1 sees only `Big Cheese`
   - Client 2 / Paradise sees `Ellicott 460SL`
   - client operator/mechanic see only their org fleet
   - Asset Detail checklist picker shows dredge-specific checklist
3. Audit work-order/service-report RLS before exposing more client-side work/report surfaces.
4. Decide later whether client staff need per-asset assignment, or whether org-wide fleet visibility remains enough.
5. Consider a small UI cleanup pass for org/member removal: removing a member clears org membership but does not normalize their role.

## Session commits audited

```text
9fb27d8 fix: consolidate client org asset access
b680db7 fix: let client staff see their org assets
7a8f782 fix: tighten asset visibility to owner and assigned client
a99421b fix: add owner-client asset visibility policies
8a9730c fix: avoid stale asset cache across logins
40c1aec fix: filter asset checklist templates by machine
7f2656d feat: add client asset checklist submission
7d16415 chore: simplify asset summary heading
c2b47b7 chore: remove parts inventory workflow
027111f feat: add asset workflow summary hub
7ea541b docs: audit schema fit for workflow hub
3a77cc2 chore: clear remaining analyzer infos
66e0c82 chore: add analyzer-suggested const constructors
6e658e1 chore: replace deprecated opacity helpers
4411dde chore: replace deprecated form field values
7e0cacb chore: clear analyzer warnings
73c5969 refactor: centralize asset workflow role policy
3467382 refactor: deepen checklist history and PM completion workflows
```
