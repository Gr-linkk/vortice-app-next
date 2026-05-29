# Vortice Workflow Specs

Date: 2026-05-21
Status: planning draft for Garrett review

## How To Use This Doc

This is the review map before the next fixing pass. Each workflow has:

- Intent: what the app should mean to the user.
- Current implementation: files/routes/tables that appear to own it now.
- Happy path: the boring flow that should work first.
- Rules: product constraints we should not accidentally break.
- Conflicts/risks: places the current app can contradict itself.
- Garrett notes: empty space for field/product notes.

Garrett notes can go directly under any workflow, or in the summary sections at the bottom.

## Garrett Review Board

Use this section as the fastest note-taking spot. The detailed workflow sections below repeat the same questions with context.

### Resolved from Garrett notes

| Area | Decision now captured in the spec |
| --- | --- |
| Client mechanics | Client mechanics do not see internal Vortice work orders. They use client-side checklists/history only. |
| Work order lifecycle | Main WO status is `draft -> ready -> in_progress -> on_hold -> completed -> closed`. Assignment, review, billing, sync, and client visibility are separate tracks. |
| Service reports | Service reports need true pending-sync submit behavior, not draft-only offline support. |
| PM hours | PM completion hours are manually entered by Vórtice Owner/Admin or Vórtice Tech/Mechanic. Telemetry/checklist/WO hours can inform context but do not silently win. |
| Asset lifecycle | Hard delete is allowed, but must use an explicit destructive warning that all asset data/history will be lost. |
| Operator exceptions | An Action/Monitor result creates a client-side notification only. The client can then decide whether to make a service request. |
| Dashboard model | Tier dashboards are retired. Dashboards get revamped after workflow stabilization around capability-driven behavior. |
| Invoices | Completed WOs are invoice-eligible. Sent invoices can still be edited. |
| Client request history | Leave the existing service-request behavior as-is for now. |
| Documents/media | Store generated files and keep the ability to regenerate them from source records. |
| Onboarding | Public/self registration is out. Onboarding should be invite-code driven. |
| Client orgs and invite codes | Only Vortice owner users create client orgs and invite codes. |
| Client/user management | Clients can add employees/team members, but they cannot add assets. Asset creation is owner-only. |
| Client asset edits | Clients cannot directly edit asset facts. They can request corrections. |
| Staff checklist history visibility | Clients should see Vortice staff maintenance checklist history by default. |
| PM kits | PM kits belong to clients with maintenance planning enabled in the capability switchboard and should prefill work-order parts. |
| PM procedure hyperlinks | Hyperlinks from PM checks/checklists to procedures are not first-MVP scope. Vortice needs clean, stable source documents before linking checklist items to procedure docs; until then, PM checklists should rely on checklist text, materials/parts, notes, and optional attachments/references. |
| Telemetry MVP | No final telemetry value list until the first real hardware/gateway test. Do not hard-code assumptions before the gateway is plugged in. |
| Telemetry alerts | Clients can acknowledge an alert for their asset, then create a service request if they want Vortice involved. |
| Fuel advisory forecasting | Vortice provides advisory fuel forecasting as a telemetry/planning feature: burn-rate trends and reorder guidance help clients estimate how much fuel to order and when, but do not automatically purchase fuel or satisfy PM intervals. |
| Meeting/demo request | Garrett does not recognize this screen; treat it as suspect legacy/demo scaffolding and do not build on it until reviewed. |
| Checklist template lifecycle | Tentative direction is archive/version used templates instead of silently changing historical meaning. Garrett's answer was uncertain, so confirm before implementation. |
| WO actor terms | Use the dev-login persona wording for workflow rules: `Vórtice Owner/Admin`, `Vórtice Tech/Mechanic`, `Client Admin`, `Client Mechanic`, and `Operator/Captain`. |
| Reports after close/invoice | Closed or invoiced work orders can still accept new service reports if info was missed. |
| Service report signatures | Signature is required every time. |
| Service report photos | Photos are optional evidence. |
| Offline day-one scope | Service-report pending sync, all checklist flows, and work-order workflows must be offline-capable for day one. |



## Coding Packet: V2 Foundation + Role/Capability/Fleet Scope

Status: ready for Garrett approval before implementation. This is the first bounded foundation slice; service-report rebuild, broad dashboard rebuild, production Supabase changes, and deleting old screens are out of scope.

### Goal

Make the app's first V2 foundation rules explicit in code before any broad workflow rebuild:

```text
authenticated role
-> allowed route family
-> fleet/client scope
-> optional capability gate
-> screen/provider uses the same policy
```

### Settled decisions this slice relies on

- Client users, including client mechanics, do not see internal Vortice work orders in v1.
- Baseline client portal access remains always-on: fleet, service requests, service reports/history, invoices, documents/history.
- Optional client workflows are gated by `client_capabilities`: `operational_checklists`, `pm_checklists`, `pm_parts_lists`, `maintenance_planning`, and `telemetry`.
- Client team fleet scope inherits through `profiles.org_id -> client_orgs.id -> client_orgs.owner_profile_id -> assets.client_id`.
- Capability switches must not delete users, records, or history.
- Tier dashboards are legacy scaffolding and must not drive product access.
- Work-order status cleanup is target shape `draft -> ready -> in_progress -> on_hold -> completed -> closed`; assignment, review, billing, sync, and client visibility are separate tracks.

### Current code facts found

- `lib/core/router.dart` authenticates users but does not centrally authorize direct route access by role/capability.
- Client routes still expose internal WO surfaces: `/client/work-orders`, `/client/work-orders/:id`, and `/client/checklists/:workOrderId`.
- `ClientCapabilityGate` exists and is useful, but it is screen-level and inconsistent for direct-route policy.
- `visibleAssetsProvider`, `currentClientFleetAssetsProvider`, and `currentClientFleetOwnerIdProvider` are the right fleet-scope seams.
- `client_capabilities` exists, but the RLS policy only lets the owning client profile read its own switches; org team roles need confirmed policy support.
- `WorkOrderStatus` still contains old statuses `assigned`, `pending_review`, and `invoiced`; code uses `assigned` when assigning work.
- Client mechanic dashboard still presents "assigned work" backed by work orders, which conflicts with the new client-side/non-internal-WO rule.

### Implementation slice

1. Add a central app route/access policy module for route families and direct-route blocking.
2. Apply that policy from `router.dart` redirect logic before route builders run.
3. Block or redirect client-side direct routes to internal work orders/checklists.
4. Keep client-facing history/report/invoice/service-request routes accessible through fleet scope.
5. Replace client mechanic dashboard "assigned work" with client-side checklist/history language, or mark it hidden until the PM checklist capability flow is implemented.
6. Keep capability gates for optional workflow bodies, but ensure direct route policy agrees with them.
7. Add focused tests for role route access, client WO blocking, operator/client-operator isolation, and capability-gated route behavior.

### Likely files/modules

- `lib/core/router.dart`
- new or existing policy seam near `lib/core/` or `lib/features/auth/`
- `lib/features/clients/client_capability_gate.dart`
- `lib/features/clients/client_context_provider.dart`
- `lib/features/assets/client_team_asset_access.dart`
- `lib/features/assets/asset_workflow_policy.dart`
- `lib/features/dashboard/client_mechanic_dashboard.dart`
- `lib/features/dashboard/client_operator_dashboard.dart`
- `lib/features/work_orders/work_order_provider.dart` for follow-up status cleanup, not necessarily first patch
- `test/core/` and targeted `test/features/...` route/policy tests
- migration candidates under `supabase/migrations/`, but do not apply production Supabase changes in this slice

### Data/schema migration candidates

- Work-order status migration from `assigned/pending_review/invoiced` into operational status plus separate assignment/review/billing fields.
- Client-org readable `client_capabilities` policy so `client_admin`, `client_mechanic`, `operator`, and `client_operator` can evaluate switches for their inherited fleet.
- Audit log table for asset reassignment, role/capability changes, WO status transitions, reopen/close actions, and invoice/report document events.
- Asset correction requests table for client-requested fact changes.
- Checklist template version/archive model before mutable templates become real history.
- Notification source/lifecycle table for Action/Monitor, telemetry alerts, reminders, service requests, and old maintenance flags.
- Document/export records table for stored/generated files.

### Out of scope for this slice

- Service-report authoring rebuild beyond preserving existing owner/employee route behavior.
- Production Supabase writes or live policy changes.
- Deleting legacy tier dashboard files.
- Full WO status migration.
- Offline queue implementation.
- Invoice/report export rebuild.
- PM procedure-document hyperlinks.

### Tests/checks proposed

- Unit-test route policy: owner/employee can reach internal WO routes; client/client_admin/client_mechanic/operator/client_operator cannot.
- Unit-test client baseline routes remain allowed: assets, service requests, service reports, invoices, checklist history where role-appropriate.
- Unit-test optional capability route decisions for PM checklists, operational checklists, maintenance planning, PM parts, and telemetry.
- Widget/router test direct navigation to blocked client WO paths redirects to a safe client route.
- Existing policy tests: `test/features/assets/asset_workflow_policy_test.dart`.
- Existing shell/navigation tests: `test/core/app_shell_back_navigation_test.dart`.

### Open product decisions before implementation

- Confirm client mechanics should have zero internal WO visibility, including assigned/shared WO checklist work. Current code and one RLS migration still allow assigned client mechanics to see WO-backed work.
- Decide where blocked direct routes land: `/client/dashboard`, `/client/service-reports`, or a small not-available screen.
- Confirm `client_admin` invoice visibility: all company invoices through org fleet, or owner profile only.
- Confirm telemetry alert split: clients acknowledge; Vortice staff resolve/clear.
- Confirm whether `operator` should be treated only as client-side operations scope in the current app, despite the older role name.

### Definition of done

- One central route/access policy exists and is tested.
- Client-side roles cannot direct-route into internal Vortice work orders.
- Client fleet scope uses the shared org-owner model, not per-screen broad queries.
- Capability switchboard rules match route behavior and screen behavior.
- Legacy tier surfaces are isolated as compatibility UI, not product authority.
- Migration needs are listed separately from feature code.
- Remaining product decisions are explicitly named before broader implementation begins.

## Source Material Checked

- `CONTEXT.md`
- `projects/vortice-app/STATUS.md`
- `docs/WORKFLOW-ARCHITECTURE-NOTES-2026-05-08.md`
- `docs/SCHEMA-WORKFLOW-AUDIT-2026-05-08.md`
- `docs/CLIENT-ORG-ACCESS-MODEL-2026-05-08.md`
- `docs/CHECKLIST-WORKFLOW-SPEC-2026-05-07.md`
- `docs/SERVICE-REPORT-FLOW-SPEC-2026-05-12.md`
- `docs/SERVICE-REPORT-REBUILD-PLAN-2026-05-21.md`
- `docs/DEVELOPER-REVIEW-PREP-PLAN-2026-05-13.md`
- Current routes in `lib/core/router.dart`
- Current feature modules under `lib/features/`
- Screen inventory from `lib/features/**`
- Current models/DAOs under `lib/models` and `lib/db`

## Global Product Rules

 1. Asset Detail is the user-facing hub for an asset's maintenance life.
 2. Asset Detail should compose summaries/actions; it should not directly write workflow tables.
 3. Named workflow modules own business mutations.
 4. Client capability switches gate optional client-side workflows only.
 5. Baseline client portal access, asset visibility, invoices, documents/history, and service-request intake remain always-on.
 6. Client users, including client mechanics, do not see internal Vortice work orders in v1.
 7. Operators and client operators see operations work only.
 8. Work-order workflows are now day-one offline scope; local state, sync visibility, and conflict handling need explicit design.
 9. Submitted checklist history is immutable in v1.
10. Service reports are client-facing records linked to work orders; they are not the internal work order.
11. Service reports require true pending-sync submit behavior for field use.
12. PM completion hours are manually entered by Vórtice Owner/Admin or Vórtice Tech/Mechanic; telemetry/checklist/WO hours are context only unless explicitly selected.
13. Hard asset delete is allowed only behind an explicit destructive warning that all asset data/history will be lost.
14. Tier dashboards are retired; client dashboard behavior should become capability-driven after workflow stabilization.
15. Generated files should be stored and regeneratable from source records.
16. No-data-loss beats cleanup.
17. Work-order main status is operational only: `draft -> ready -> in_progress -> on_hold -> completed -> closed`.
18. Assignment, review, billing, sync, and client visibility are separate tracks.
19. WO transitions use dev-login persona terms. `Vórtice Owner/Admin` controls admin/office-side WO actions; `Vórtice Tech/Mechanic` controls assigned field execution; client personas do not drive internal WO status.
20. Service-report signatures are required every time; report photos are optional.

## Role Matrix

| Role            | Core access                                                                                                                                                           |
|-----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `owner`           | Full Vortice staff admin. Manages clients, assets, org codes, capabilities, work orders, service requests, reports, invoices, intervals, reminders, parts, telemetry. |
| `employee`        | Staff service workflow. Handles service requests, work orders, checklists, service reports, parts, and assigned service work.                                         |
| `client`          | Customer owner profile. Sees assigned fleet, service requests, reports, invoices, documents/history. Optional workflows depend on capability switches.                |
| `client_admin`    | Customer team admin. Inherits fleet through `profiles.org_id -> client_orgs.owner_profile_id -> assets.client_id`. Can use enabled client workflows.                    |
| `client_mechanic` | Client-side mechanic. Inherits fleet. Can use enabled PM/checklist/parts workflows. Does not see internal Vortice work orders.                                        |
| `operator`        | Operations-only role. Sees allowed operations assets and operations checklist history.                                                                                |
| `client_operator` | Client team operator. Same operations-only intent as operator, scoped through client org.                                                                             |

## Workflow Inventory

| \#  | Workflow                                         | Primary owner now                                 | Status                            |
|----|--------------------------------------------------|---------------------------------------------------|-----------------------------------|
| 1  | Auth and role routing                            | `auth_provider`, `router.dart`                        | Exists, needs route audit         |
| 2  | Client access and fleet scope                    | `client_team_asset_access`, `client_context_provider` | Canonical model exists            |
| 3  | Client org and org code invites                  | `org_provider`, `org_code_provider`                   | Exists, needs policy polish       |
| 4  | Client capability switchboard                    | `client_capability_provider`, gates                 | Exists, needs consistency audit   |
| 5  | Asset creation/edit/delete                       | `asset_provider`, asset screens                     | Exists, owner-heavy               |
| 6  | Asset hub/detail                                 | `AssetDetailScreen`, `AssetWorkflowPolicy`            | Exists, needs read-model depth    |
| 7  | Engine records and hour logs                     | `engine_provider`, `hour_log_provider`                | Exists                            |
| 8  | Service request intake                           | `service_request_provider`                          | Exists, MVP statuses              |
| 9  | Vórtice Owner/Admin service request triage to WO               | request list + WO draft                           | Exists                            |
| 10 | Work orders                                      | `work_order_provider`, repository/screens           | Exists, needs transition spec     |
| 11 | Vórtice PM interval -> WO -> checklist -> reminder | interval/checklist/PM modules                     | Exists, hours gap                 |
| 12 | Client/admin/mechanic non-WO checklists          | `ChecklistScreen` route, missing seam               | Partially exists                  |
| 13 | Operator checklist and operations history        | operator + checklist orchestrator                 | Exists                            |
| 14 | Saved checklist history                          | saved checklist modules/history screen            | Exists, needs viewer polish       |
| 15 | Service reports                                  | report modules/screens                            | Rebuild in progress               |
| 16 | Invoicing                                        | invoice provider/service/screens                  | Exists, needs audit               |
| 17 | Parts and PM kits                                | parts providers/screens                           | Exists, needs workflow linkage    |
| 18 | Telemetry display and alerts                     | telemetry providers/screens                       | Exists                            |
| 19 | Device pairing/gateway link                      | `DevicePairingScreen`, `devices`                      | Exists but needs clearer workflow |
| 20 | Dashboards                                       | dashboard screens                                 | Exists, needs continuity pass     |
| 21 | Notifications and reminders                      | notification/reminder modules                     | Exists, needs route/status audit  |
| 22 | Maintenance flags                                | operator/client flag screens/providers            | Exists, weak lifecycle            |
| 23 | Meeting/demo request                             | meeting provider/screen                           | Exists, intake-only               |
| 24 | Documents/exports/PDFs                           | invoice/report export services                    | Partial                           |
| 25 | Client/profile management                        | `ClientScreen`, profile/client providers            | Exists, owner-heavy               |
| 26 | Checklist template and assignment setup          | checklist providers/assignment model              | Partially exposed                 |
| 27 | Subscription/tier scaffolding                    | tier gates/dashboard variants                     | Legacy risk                       |
| 28 | Offline/local sync and cache                     | Drift DAOs, repositories, sync status             | Partial/uneven                    |
| 29 | Media attachments and storage                    | request/report photos, signatures, snapshots      | Partial                           |
| 30 | Asset type and template binding                  | asset type/checklist filters                      | Exists, needs admin story         |
| 31 | Localization/app shell/navigation                | l10n, `AppShell`, router                            | Exists, needs policy audit        |

---

## Workflow 1: Auth And Role Routing

### Intent

A signed-in user lands in the correct role experience and cannot reach workflow surfaces outside their role.

### Current implementation

- `lib/features/auth/auth_provider.dart`
- `lib/features/auth/login_screen.dart`
- `lib/features/auth/register_screen.dart`
- `lib/core/router.dart`
- role dashboard redirects

### Happy path

```text
user logs in
-> profile loads
-> role is resolved
-> router sends user to role dashboard
-> role-specific nav/routes expose allowed workflows
```

### Rules

- Auth routing is not workflow authorization by itself.
- Direct routes must still enforce role/capability/data scope.
- Registration with org code must set both role and org membership.
- Client mechanics do not get internal work-order routes in v1.
- Public/self registration is disabled for product onboarding; users enter through invite codes.

### Conflicts/risks

- Client routes include work-order and checklist paths that may be stronger than the intended MVP client visibility.
- A route being hidden from nav is not enough if direct URL access still works.


### Garrett notes

-

## Workflow 2: Client Access And Fleet Scope

### Intent

A client owns vessels/equipment. A client org is that client's team. Org members inherit visibility to the client owner's fleet.

### Current source of truth

```text
profiles.org_id
-> client_orgs.id
-> client_orgs.owner_profile_id
-> assets.client_id
```

### Current implementation

- `lib/features/assets/client_team_asset_access.dart`
- `lib/features/clients/client_context_provider.dart`
- `visibleAssetsProvider`
- `currentClientFleetAssetsProvider`

### Happy path

1. Vortice owner creates or confirms a client profile.
2. Owner creates/assigns assets with `assets.client_id = client profile id`.
3. Client/admin has or creates a client org.
4. Org codes invite admin/mechanic/operator users into that org.
5. Client team members inherit visibility to the owner profile's fleet.

### Rules

- Do not add per-screen fallback queries that show all assets to client-side users.
- Capability switches do not remove historical fleet visibility.
- V1 does not use per-user asset assignment.

### Conflicts/risks

- Any broad provider used on a client screen can leak stale/local/all-asset data if not scoped.
- Vórtice Tech/Mechanic visibility is still workflow-specific and should not be assumed identical to owner.


### Garrett notes

-

## Workflow 3: Client Org And Org Code Invites

### Intent

Client teams are managed through orgs and invite codes, not loose role changes.

### Current implementation

- `lib/features/orgs/org_provider.dart`
- `lib/features/orgs/org_admin_screen.dart`
- `lib/features/org_codes/org_code_provider.dart`
- `lib/features/org_codes/org_code_screen.dart`
- `client_orgs`, `org_codes`, `profiles.org_id`

### Happy path

```text
owner creates org
-> owner creates org code with intended role
-> user registers with code
-> profile.role and profile.org_id are set
-> user sees inherited fleet and enabled workflows
```

### Rules

- Org code should set both role and org membership.
- Only Vortice owner users create client orgs and invite codes.
- Disabling a capability must not delete existing users.
- Removing an org member should remove inherited fleet access.

### Conflicts/risks

- `deleteOrg` clears `profiles.org_id` then deletes the org; confirm no orphaned invite/code behavior.
- Client-created orgs are out for v1; owner-created orgs are the rule.


### Garrett notes

-

## Workflow 4: Client Capability Switchboard

### Intent

Capabilities enable optional client-side workflows without changing baseline portal access.

### Current implementation

- `public.client_capabilities`
- `lib/features/clients/client_capability_provider.dart`
- `ClientCapabilityGate`
- capability keys: `operational_checklists`, `pm_checklists`, `pm_parts_lists`, `maintenance_planning`, `telemetry`

### Happy path

```text
owner opens client/admin area
-> toggles a capability for client profile
-> client routes/cards for that capability appear
-> direct access is blocked when disabled
```

### Rules

- Missing capability rows default disabled.
- Always-on: portal access, assigned fleet, invoices, documents/history, service requests.
- Capability off hides/blocks workflow surfaces, but does not delete history/users.

### Conflicts/risks

- Some screens may gate nav but not deep routes.
- Some role policies may show cards before capability gates block the target screen.


### Garrett notes

-

## Workflow 5: Asset Creation, Editing, And Deletion

### Intent

Assets are the canonical vessel/equipment records that all maintenance history attaches to.

### Current implementation

- `AssetListScreen`
- `AddAssetScreen`
- `EditAssetScreen`
- `AssetController`
- `assets`

### Happy path

```text
owner creates asset
-> assigns client profile
-> fills name/type/make/model/serial/location/notes
-> asset appears in owner and assigned client fleet
-> owner edits as facts change
```

### Rules

- Asset creation is owner-only in v1.
- Owner-created assets should still belong to a client fleet when applicable.
- Hard delete is allowed, but only after an explicit destructive warning that all data/history for the asset will be lost.
- Asset local cache must not expose stale assets across users.
- Clients cannot directly edit asset facts; they can request corrections.

### Conflicts/risks

- `deleteAsset` exists; the remaining work is making the destructive warning and permission boundary impossible to miss.
- Editing client ownership can move a full history record between clients if not audited.


### Garrett notes

-

## Workflow 6: Asset Hub / Asset Detail

### Intent

Asset Detail is the hub for asset facts, maintenance plan, service requests, work history, reports, telemetry, engines, and documents.

### Current implementation

- `AssetDetailScreen`
- `AssetWorkflowPolicy`
- `AssetWorkflowSummary`
- routes to checklist history, service intervals, service reports, telemetry, engines

### Happy path

1. User opens asset from their dashboard/list.
2. Asset Detail loads asset facts and role policy.
3. It renders only cards/actions the role can use.
4. Summary cards point into named workflow screens.
5. Mutations happen inside the target workflow module, not Asset Detail.

### Rules

- Asset Detail can show summaries and route to workflow screens.
- Asset Detail must not directly create service reports, close WOs, satisfy intervals, or write checklist history.
- Operators see operations surfaces only.
- Client-facing cards must not leak internal WO details.

### Conflicts/risks

- Asset Detail still knows too much about individual providers/routes.
- Adding more cards without read-model seams will make it fragile.


### Garrett notes

-

## Workflow 7: Engine Records And Hour Logs

### Intent

Engines/components under an asset track current hours and support PM/telemetry context.

### Current implementation

- `EngineScreen`
- `EngineController`
- `HourLogScreen`
- `HourLogController`
- `asset_engines`, `hour_logs`

### Happy path

```text
owner opens asset engines
-> adds/edits engine record
-> logs manual hours
-> engine.current_hours updates
-> PM summaries and history can use latest known hours
```

### Rules

- Manual hour logs are a source of truth for engine current hours.
- Telemetry hours and manual hours need precedence rules.
- Engine records are child records of assets.

### Conflicts/risks

- PM completion currently uses WO hours, engine telemetry, and engine current hours, but not saved checklist header hours.
- Asset-first telemetry can conflict with engine-first PM fallback if `engine_id` is missing.


### Garrett notes

-

## Workflow 8: Client Service Request Intake

### Intent

Service requests are the baseline customer intake workflow. They are not work orders.

### Current implementation

- `ServiceRequestFormScreen`
- `ServiceRequestController`
- `clientServiceRequestsProvider`
- `service_requests`
- optional photo upload to service request photo bucket

### Happy path

```text
client/client_admin opens request form
-> selects request type and asset/other asset
-> enters description/contact/hours/photos
-> service_requests status = new
-> client sees "Sent" or simple confirmation
```

### Rules

- Always-on for `client` and `client_admin`.
- A request can reference a known asset or describe another asset.
- Photo upload failure should not lose the request.
- Leave the current request behavior as-is for now; do not broaden this workflow during the next fixing pass.

### Conflicts/risks

- Client request list/history can remain thin for MVP unless later feedback says it is confusing.
- `resolved` maps to "Being handled" for clients, which is product-language awkward.


### Garrett notes

-

## Workflow 9: Vórtice Owner/Admin Service Request Triage To Work Order

### Intent

Vórtice Owner/Admin turns customer requests into internal work orders or decline them.

### Current implementation

- `StaffServiceRequestListScreen`
- `MaintenanceWorkOrderDraft`
- `CreateWorkOrderScreen`
- `ServiceRequestController.markGeneratedWorkOrder`

### Happy path

```text
service_requests status = new
-> Vórtice Owner/Admin inbox
-> Vórtice Owner/Admin Generate Work Order
-> CreateWorkOrderScreen receives draft + serviceRequestId
-> work_orders row created
-> service_requests.generated_work_order_id set
-> service_requests.status = resolved
```

### Rules

- Backing out of WO creation leaves request unchanged.
- Saving the generated WO marks the request handled.
- Clients do not see internal WO schedules/status from this bridge.

### Conflicts/risks

- `resolved` means handled, not necessarily complete.
- A declined request needs a clear client-facing reason policy.


### Garrett notes

-

## Workflow 10: Work Orders

### Intent

Work orders are internal Vortice service jobs. They coordinate assignment, status, checklists, labor, parts, service reports, and invoicing.

### Current implementation

- `WorkOrderListScreen`
- `WorkOrderDetailScreen`
- `CreateWorkOrderScreen`
- `WorkOrderRepository`
- `WorkOrderController`
- `work_orders`, `work_order_assignments`

### Happy path

1. Vórtice Owner/Admin creates WO manually, from a service request, or from PM planning.
2. WO stores asset, client, optional engine, optional checklist template, job type, assignment, and status.
3. Vórtice Tech/Mechanic works through detail actions.
4. Checklist completion can save maintenance history and satisfy PM for Vórtice PM work.
5. Service reports can be created from the WO.
6. Invoice can be generated when ready.
7. WO can be closed/reopened by Vórtice Owner/Admin or server policy.

### Rules

- Work-order create/edit/status/complete behavior must be designed as offline-capable day-one scope.
- `work_orders.asset_id` and `work_orders.client_id` must remain coherent.
- `work_orders.checklist_template_id` is optional but important for PM/checklist-backed work.
- Vórtice-created WOs may be tied to service requests by `service_requests.generated_work_order_id`.
- Main WO status is operational only: `draft -> ready -> in_progress -> on_hold -> completed -> closed`.
- Assignment, review, billing, sync, and client visibility are separate tracks, not main statuses.
- Use the dev-login persona wording when describing WO actors. Avoid introducing separate labels unless a matching dev persona exists.
- `Vórtice Owner/Admin` can create, ready, assign, review, prepare billing, override, and close WOs according to permission policy.
- `Vórtice Tech/Mechanic` can start, hold, resume, add field evidence, create service reports, and mark assigned WOs completed.
- Authoritative `closed` requires `Vórtice Owner/Admin` or server policy after required evidence has synced and review rules pass.
- Completed work orders are invoice-eligible through billing state, not an `invoiced` main status.
- Client mechanics do not see internal work orders.

### Conflicts/risks

- Client work-order routes exist and need to be blocked/removed for client-side roles.
- Reopen policy after authoritative server close still needs an exact approval/review trail.
- Reopen/close behavior can conflict with invoicing and follow-up reporting.


### Garrett notes

-

## Workflow 11: Vórtice PM Interval To Work Order To Checklist History

### Intent

Vórtice Owner/Admin or Vórtice Tech/Mechanic PM completion can satisfy maintenance intervals. Client-side checklist submissions cannot satisfy intervals in v1.

### Current implementation

- `ServiceIntervalScreen`
- `serviceIntervalSummariesProvider`
- `MaintenanceWorkOrderDraft.preventativeMaintenance`
- `MaintenanceChecklistSubmission`
- `SavedChecklistHistoryWriter`
- `PreventativeMaintenanceCompletion`
- `asset_service_intervals`, `service_reminders`, `work_orders`, `checklist_responses`, `saved_checklists`

### Happy path

```text
asset_service_interval defines PM schedule/template
-> due summary/reminder appears
-> Vórtice Owner/Admin creates PM work order
-> work_order stores checklist_template_id and job_type
-> Vórtice Tech/Mechanic completes checklist
-> checklist_responses saved
-> saved_checklists row filed as maintenance
-> PreventativeMaintenanceCompletion advances reminder
-> work_order closes
```

### Rules

- Vórtice PM checklist completion may satisfy intervals.
- PM completion hours are manually entered by Vórtice Owner/Admin or Vórtice Tech/Mechanic.
- Order matters: save responses, file history, then satisfy PM/close WO.
- Hyperlinks from PM checklist items to procedures are later-phase scope, not first MVP, until source procedure documents are curated and stable.
- Offline/pending checklist response state must not pretend PM is satisfied.

### Conflicts/risks

- Telemetry, checklist-entered hours, and WO hours can provide context, but they should not silently override the manually entered PM completion hours.
- Asset-first telemetry and engine-first interval logic still need a deliberate display/precedence model.


### Garrett notes

-

## Workflow 12: Client/Admin/Mechanic Non-WO Checklists

### Intent

Client-side admin/mechanic users can submit asset-associated checklists without creating Vortice WOs. These become asset history only in v1.

### Current implementation

- Route: `/client/assets/:id/checklists/new`
- `ChecklistScreen(clientHistoryOnly: true)`
- capability gate: `pm_checklists`
- schema support through `saved_checklists` with optional `work_order_id`
- missing dedicated `ClientChecklistSubmission` seam

### Happy path

```text
client admin/mechanic opens asset
-> enabled capability allows checklist workflow
-> user selects asset-associated template
-> fills checklist header/items
-> app writes saved_checklists row
-> Asset Checklist History shows submitted record
```

### Rules

- Do not route through staff PM completion.
- Hyperlinks from checklist items to procedures are later-phase scope, not first MVP, until source procedure documents are curated and stable.
- Do not update `service_reminders`.
- Do not close or create work orders.
- Do not notify Vortice automatically in v1.
- Assignments can nudge; they are not permissions.
- Client mechanics use this non-WO checklist/history path, not internal Vortice work orders.

### Conflicts/risks

- Reusing `ChecklistScreen` without a clear submission seam can accidentally inherit staff PM behavior.
- Source type needs to be explicit enough for history/audit.


### Garrett notes

-

## Workflow 13: Operator Checklist And Operations History

### Intent

Operators perform operations/pre-op/daily checks. Their history is operations history, not maintenance history.

### Current implementation

- `OperatorChecklistScreen`
- `_OperatorChecklistCapabilityGate`
- `OperationsChecklistSubmission`
- `operator_checklist_runs`
- `operator_checklist_responses`
- `saved_checklists`
- `SavedChecklistHistoryWriter.recordOperationsRunHistory`

### Happy path

```text
operator/client_operator opens checklist
-> operational_checklists capability is enabled for asset client
-> user selects asset/template
-> fills checklist
-> operator run/responses saved
-> saved_checklists row filed as operations
-> operations history visible under asset
```

### Rules

- Operators/client operators see operations history only.
- Operators do not see Maintenance tab.
- Operations checklist exceptions can surface later, but v1 history is immutable.
- Action/Monitor items create a client-side notification only; the client can decide whether to create a service request.

### Conflicts/risks

- Legacy operator run tables still exist alongside canonical saved history.
- Capability gate depends on resolving asset client; no asset means policy is less clear.


### Garrett notes

-

## Workflow 14: Saved Checklist History

### Intent

Every submitted checklist becomes a durable saved copy under the asset.

### Current implementation

- `SavedChecklistHistoryWriter`
- `SavedChecklistsRepository`
- `savedChecklistsProvider`
- `AssetChecklistHistoryScreen`
- `saved_checklists`

### Canonical model

`saved_checklists` stores asset/client/template ids, template name, `checklist_type`, `source_type`, submitter role/user, submitted timestamp, optional current hours/notes, optional `work_order_id`, optional `assignment_id`, and immutable `snapshot`.

### Rules

- No edit/delete/amendment flow in v1.
- Maintenance and operations tabs stay distinct.
- Operators only see operations.
- Clients do not see internal WO details through checklist history.
- Clients see Vortice staff maintenance checklist history by default.

### Conflicts/risks

- Detail/photo/filtering polish is still thin.
- `assignment_id` has no strong workflow meaning yet.


### Garrett notes

-

## Workflow 15: Service Reports

### Intent

Service reports are Vortice-authored client-facing service records linked to work orders. They are not the internal work order.

### Current implementation

- `ServiceReportWorkflow`
- `ServiceReportRepository`
- `ServiceReportListScreen`
- `ServiceReportDetailScreen`
- `ServiceReportAuthoringScreenV2`
- `service_reports`, `service_report_photos`

### Relationship

```text
work_orders.id
-> service_reports.work_order_id
```

A work order can have many service reports. A service report belongs to exactly one work order.

### Happy path

1. Vórtice Tech/Mechanic opens Work Order Detail.
2. Vórtice Tech/Mechanic chooses Add Service Report.
3. V2 authoring opens with required `workOrderId`.
4. Vórtice Tech/Mechanic fills 5C fields.
5. Draft saves locally.
6. Submit creates either a synced report or a durable pending-sync report linked by `work_order_id`.
7. Staff/client viewers can see it in scoped report lists/detail.

### Role rules

- Create: `owner`, `employee`
- View: `owner`, `employee`, `client`, `client_admin`, `client_mechanic`
- No access: `operator`, `client_operator`

### Rules

- Work-order-scoped authoring must require `workOrderId`.
- Do not create orphan reports from global/asset list actions.
- Vórtice Owner/Admin or Vórtice Tech/Mechanic can add service reports even after WO close/invoice.
- Detail fetch should use report id directly.
- Offline submit must create a durable pending-sync report, not just a local draft.
- Signatures are required every time.
- Photos are optional evidence.
- PDF/export return after phone-stable 5C flow.

### Conflicts/risks

- Old authoring screen is not trustworthy and should be reference-only until removed.
- Client route `/client/service-reports/new` redirects away; correct, but direct access should stay impossible.
- Pending-sync retry/error states are not fully final.


### Garrett notes

-

## Workflow 16: Invoicing

### Intent

Invoices are client-facing billing records generated from completed/internal work. They should tie back to a work order and tell the same story as service reports and client history.

### Current implementation

- `InvoiceScreen`
- `InvoiceDetailScreen`
- `InvoiceController`
- `InvoiceService`
- `InvoicePdfService`
- `InvoiceExcelService`
- `invoices`

### Current happy path

```text
owner opens invoices
-> selects pending_review/completed work order without invoice
-> generates invoice
-> invoice detail opens
-> owner adjusts line items/status if needed
-> mark sent/paid/voided as appropriate
-> client can view allowed invoice
```

### Rules

- Owner generates invoices.
- Client viewers can see their invoices through client list/detail.
- Invoice preserves customer identity, totals, taxes/currency, line items, and work-order source.
- Closed/invoiced WOs should still allow follow-up service reports.
- Completed work orders are invoice-eligible.
- `pending_review` means ready for invoice.
- Sent invoices can still be edited.

### Conflicts/risks

- Invoice list provider is broad; rely on RLS only after audit.
- Parts/labor/service-report linkage needs confirmation.
- Generated invoice status transitions and send behavior are not fully mapped.


### Garrett notes

-

## Workflow 17: Parts And PM Kits

### Intent

Parts support maintenance planning, PM kits, work-order costing, and eventual invoice line accuracy.

### Current implementation

- `PartsLogScreen`
- `PartsController`
- `PmKitsScreen`
- `PmPartsSetupScreen`
- `pm_parts_provider`
- `parts`, PM kit/requirement tables

### Happy path

```text
Vórtice Tech/Mechanic logs parts against WO
-> parts include quantity/cost/markup/supplier/notes
-> invoice generation can include parts total
```

PM kit path:

```text
Vórtice Owner/Admin configures PM parts list for checklist/template
-> maintenance planning capability exposes the kit where enabled
-> kit can prefill work-order parts
-> actual WO parts can still be adjusted before invoicing
-> client mechanic access depends on pm_parts_lists capability
```

Recommended inventory path:

```text
Vórtice Owner/Admin defines required parts/materials at the asset level
-> asset-level requirements can include part numbers, quantities, intervals, suppliers, and notes
-> site/fleet recommended inventory rolls up from the assets assigned to that client/location
-> maintenance planning compares upcoming PMs against required parts/materials
-> client dashboard can show parts to stage, recommended stock, and missing parts data
```

### Rules

- `pm_parts_lists` gates optional client-side PM parts access.
- PM kits apply to clients with planning enabled in the capability switchboard.
- Recommended inventory is an optional advisory workflow tied to `pm_parts_lists` / maintenance planning.
- Asset-level requirements are the source record; fleet/site recommended inventory is a roll-up view.
- Recommended inventory exists to shorten downtime by helping clients stage parts/materials before PMs or known high-hour work.
- PM kits should prefill WO parts, not become immutable actual-used parts.
- Parts do not decide whether PM is satisfied.
- Recommended inventory does not prove physical stock is available unless stock tracking is explicitly enabled and maintained.
- Vortice does not automatically purchase parts from recommended inventory.
- Invoice costing should reconcile with parts/labor through a clear flow.

### Conflicts/risks

- Work-order parts log and PM kit requirements may drift.
- Invoice generated totals may not clearly distinguish actual parts used versus kit estimate.
- Recommended inventory can look like a stock guarantee if the UI does not distinguish advisory requirements from counted inventory.


### Garrett notes

-

## Workflow 18: Telemetry Display And Alerts

### Intent

Telemetry is asset-first. It supports visibility, alerts, history, fuel advisory forecasting, and eventually maintenance planning.

### Current implementation

- `TelemetryRepository`
- `VesselTelemetryScreen`
- `TelemetryHistoryScreen`
- `latestTelemetryForAssetProvider`
- `telemetryHistoryForAssetProvider`
- `telemetry_readings`, `telemetry_alerts`

### Happy path

```text
paired device/gateway uploads readings
-> readings are pinned to asset
-> asset detail/dashboard shows latest status
-> user opens telemetry/history
-> fuel and operating-hour trends can feed advisory planning views
-> app estimates burn rate and upcoming fuel need when enough fuel/hour data exists
-> clients can acknowledge alerts for their assets
-> client can create a service request if they want Vortice involved
-> Vórtice Owner/Admin / Vórtice Tech/Mechanic resolution rules remain to be confirmed
```

### Rules

- `asset_id` is the canonical owner.
- `engine_id` is optional/future detail.
- Do not insert fake/test telemetry into production app tables.
- Asset Detail can display telemetry but must not own ingestion/polling.
- Do not finalize the telemetry MVP value list until the first real gateway/hardware test.
- Clients can acknowledge alerts for their assets and choose whether to create a service request.
- Vortice provides fuel advisory forecasting, not automatic purchasing.
- Fuel forecasting belongs to telemetry/planning, not PM interval satisfaction.
- First fuel-forecasting version should be simple: manual/imported fuel entries, operating hours, average burn rate, and 7/14/30-day advisory need.
- Fuel trends can create warnings/recommendations, but operating hours remain the driver for scheduled PM intervals.
- Recommended output should answer the client question: approximately how much fuel to order and by what date.

### Conflicts/risks

- PM completion still has engine-first fallback behavior.
- Gateway health data is separate from app-facing readings.
- Fuel forecasting can look more authoritative than the data supports if current tank/supply levels, outliers, workload, or seasonal usage are missing.
- Mixing fuel forecasting directly into PM due logic would make both models muddy.


### Garrett notes

- Paradise's real problem is fuel ordering uncertainty. Spec direction: keep fuel as advisory forecasting in telemetry/planning, separate from PM interval logic.

## Workflow 19: Device Pairing / Gateway Link

### Intent

A physical gateway/device links to an asset without manual database work.

### Current implementation

- `DevicePairingScreen`
- `devices`
- pairing-code direction in telemetry docs/supporting project

### Happy path

```text
Vórtice Owner/Admin opens asset/device pairing
-> app displays or accepts pairing code
-> gateway claims code
-> devices row links device to asset
-> telemetry readings flow to that asset
```

### Rules

- Gateway health/GPS is separate from engine telemetry readings/alerts.
- Pairing belongs to asset first.
- Field gateway deployment details live in the dredge telemetry project unless scoped into app work.

### Conflicts/risks

- App/device pairing workflow is not yet as specified as telemetry display.
- Pairing codes need expiry/ownership/security rules.


### Garrett notes

-

## Workflow 20: Dashboards

### Intent

Dashboards route users into the same underlying workflows; they should not create alternate truths.

### Current implementation

- `OwnerDashboard`
- `EmployeeDashboard`
- `ClientDashboardRouter`
- `ClientDashboardFree/Managed/Telemetry`
- `ClientMechanicDashboard`
- `OperatorDashboard`
- `ClientOperatorDashboard`

### Rules

- Counts/status cards must match underlying list providers.
- "Needs attention" cards route to filtered useful lists/details, not generic hallways.
- Client dashboards show service requests, service reports, invoices, fleet, and enabled optional workflows.
- Operators only see operations work.
- Dashboard actions should not duplicate or contradict Asset Detail and Work Order Detail actions.

### Conflicts/risks

- Existing tier-specific dashboards are legacy scaffolding and should not drive future product behavior.
- Dashboard cards may use broad providers while detail/list screens use scoped providers.


### Garrett notes

-

## Workflow 21: Notifications And Reminders

### Intent

Notifications and reminders surface work that needs attention without becoming hidden workflow owners.

### Current implementation

- `notification_provider`
- `NotificationsScreen`
- `reminder_provider`
- `ReminderScreen`
- `service_reminders`
- service interval modules

### Rules

- Reminders support PM planning and due-state.
- PM satisfaction happens through `PreventativeMaintenanceCompletion`, not directly from reminder UI.
- Notifications should route to existing workflow screens.

### Conflicts/risks

- Reminder acknowledgement versus PM completion needs clean separation.
- Notification route targets can go stale when routes change.


### Garrett notes

-

## Workflow 22: Maintenance Flags And Client Notifications

### Intent

Operators/client users can surface issues found during operations without creating internal WOs directly. For Action/Monitor checklist results, the v1 behavior is a client-side notification; the client can then choose whether to create a service request.

### Current implementation

- `MaintenanceFlagScreen`
- `MaintenanceFlagsScreen`
- `operator_runs_provider`
- maintenance request/flag tables in current provider path

### Happy path

```text
operator notices issue
-> submits checklist with Action/Monitor result or explicit issue note
-> client-side notification is created
-> client/admin decides whether to create a service request
```

### Rules

- Flags are not work orders.
- Flags should not satisfy/check off PM.
- Operators should not see maintenance-history internals as part of flagging.
- Action/Monitor does not automatically create a service request or Vortice work order in v1.

### Conflicts/risks

- Lifecycle/status rules are weak.
- Existing maintenance-flag screens/tables may represent an older workflow and should be reconciled with the notification-first decision.
- Relationship to service requests is user-driven, not automatic.


### Garrett notes

-

## Workflow 23: Meeting / Demo Request

### Intent

Prospective or low-tier clients can ask for a meeting/demo without entering service workflow.

### Current implementation

- `MeetingRequestScreen`
- `MeetingRequestController`
- `meeting_requests`
- route `/meeting-request`

### Happy path

```text
authenticated user opens meeting request
-> enters interest/vessel count/contact method/notes
-> meeting_requests row status = pending
-> Vórtice Owner/Admin follows up outside app or future admin screen
```

### Rules

- Meeting request is not a service request.
- It should not create WOs, reminders, invoices, or fleet actions.
- Garrett does not recognize this screen; treat it as suspect legacy/demo scaffolding until reviewed.

### Conflicts/risks

- Vórtice Owner/Admin handling workflow for meeting requests is not defined.
- Route visibility by role/tier needs review.
- Keeping an unknown screen in live navigation risks distracting users from real service/request workflows.


### Garrett notes

-

## Workflow 24: Documents, PDFs, Exports

### Intent

Client-facing records should be exportable/shareable without changing the source workflow records.

### Current implementation

- `InvoicePdfService`
- `InvoiceExcelService`
- service report PDF/export concepts
- invoice/service report detail screens

### Happy path

```text
Vórtice Owner/Admin opens finalized record
-> app stores the generated PDF/Excel file
-> exported file can also be regenerated from current synced source record
-> client can view/share/download allowed records
```

### Rules

- Exports are representations, not source-of-truth records.
- Generated files should be stored for retrieval/audit and remain regeneratable from source records.
- Export generation should not mutate workflow state except explicit "sent" actions.
- Clients only export records they can read.

### Conflicts/risks

- Service report PDF/export is delayed behind stable authoring.
- Invoice PDF/Excel needs confirmation against invoice lifecycle.


### Garrett notes

-

## Workflow 25: Client/Profile Management

### Intent

Vórtice Owner/Admin can create/manage customer profiles, assign fleet records, and configure the customer's available workflows without mixing customer identity with team membership.

### Current implementation

- `ClientScreen`
- `client_provider`
- `client_context_provider`
- profile/client models
- `assets.client_id`
- `client_orgs.owner_profile_id`
- capability switchboard controls inside owner client area

### Happy path

```text
owner creates or selects client profile
-> owner assigns assets to that client profile
-> owner configures optional capabilities
-> owner creates org/team invite codes
-> client admins manage their own employee/team membership within the owner-created org
-> client team inherits fleet through org owner profile
```

### Rules

- Client profile is customer identity and asset owner.
- Client org is team membership, not the asset owner itself.
- Vortice owner users create client profiles, assets, orgs, and invite codes.
- Client users can add employees/team members, but not assets.
- Capability switches attach to the client/customer workflow, not individual users.
- Asset assignment changes affect all client history visibility and need audit-level care.

### Conflicts/risks

- Owner-created assets can accidentally belong to the wrong profile if client assignment is loose.
- Client profile management, org management, and capability management currently overlap in product meaning.
- Vórtice Tech/Mechanic-level client management permissions are not clearly specified.
- Client team-member management must not drift into asset creation or asset reassignment.


### Garrett notes

-

## Workflow 26: Checklist Template And Assignment Setup

### Intent

Checklist templates define repeatable maintenance/operations work. Assignments should nudge people toward work; they should not become hidden permissions.

### Current implementation

- `checklist_provider`
- `checklist_repository`
- `checklist_assignment_provider`
- `asset_checklist_template_filter`
- `checklist_templates`, `checklist_items`, `checklist_assignments`
- PM parts setup route: `/owner/checklists/:templateId/parts`

### Happy path

```text
Vórtice Owner/Admin creates or imports checklist template
-> template is marked maintenance or operations
-> template is optionally bound to asset type/service-hour interval
-> assignment points a user/role toward a checklist
-> submit flow files immutable saved history
```

### Rules

- Template setup is separate from checklist submission.
- Maintenance templates and operations templates must remain distinct.
- Assignments should not grant asset access by themselves.
- Work-order checklist snapshots preserve what was assigned at the time of work.
- Tentative direction: once a template has been used, changes should create a version/archive path rather than silently changing the old meaning.

### Conflicts/risks

- There is no obvious full admin workflow for creating/editing checklist templates from the current route inventory.
- Assignment semantics are weak and need implementation care before they are treated as tasks, reminders, permissions, or due-work records.
- Template edits can change future submissions while old saved history must remain immutable.


### Garrett notes

-

## Workflow 27: Retired Subscription/Tier Scaffolding

### Intent

Remove or collapse old tier scaffolding so it does not contradict the newer client capability switchboard or hide baseline history.

### Current implementation

- `subscription_tier` model
- `TierGate`
- `UpgradePrompt`
- `ClientDashboardFree`
- `ClientDashboardManaged`
- `ClientDashboardTelemetry`
- `ClientDashboardRouter`

### Target path

```text
client profile has baseline portal access
-> capability switchboard controls optional workflows
-> one client dashboard renders baseline plus enabled capabilities
-> baseline portal/history/request access stays visible
```

### Rules

- Capability switchboard is the current workflow-control model.
- Baseline portal access, fleet, invoices, history, and service requests are not optional capability toggles.
- The old tiers system is no longer a product control model.
- Commercial packaging should not be used as a security boundary.

### Conflicts/risks

- Tier-specific dashboards will drift from capability switchboard behavior if kept as active surfaces.
- Old "free/managed/telemetry" concepts are legacy scaffolding unless explicitly reintroduced as marketing/package labels later.
- A tier gate can hide a surface while direct routes remain accessible unless route/backend policy agrees.


### Garrett notes

-

## Workflow 28: Offline/Local Sync And Cache

### Intent

Field workflows should either be explicitly offline-safe or fail fast. Half-offline workflows are where data loss happens.

### Current implementation

- Drift database under `lib/db`
- DAOs for assets, checklists, invoices, parts, service reports, work orders
- `sync_status`
- repository/provider-level Supabase calls
- local draft behavior in service reports

### Happy path

```text
screen opens with cached data where supported
-> user performs a workflow that is explicitly offline-capable
-> local record/draft is durable
-> sync status is visible and retryable
-> once online, remote source catches up without duplicates
```

### Rules

- Work-order workflows are day-one offline scope and need durable local state plus visible sync/retry status.
- Service reports need true pending-sync submit support, with durable local record/media state and visible retry/error handling.
- All checklist flows are day-one offline scope.
- Checklist PM completion must not satisfy PM intervals until the authoritative submission succeeds.
- No workflow should silently discard photos/signatures/notes after app restart.

### Conflicts/risks

- DAOs exist for several domains, but offline guarantees differ by workflow.
- Users may assume all field forms are offline-safe once one form is.
- Retry semantics for service reports/media are not final.


### Garrett notes

-

## Workflow 29: Media Attachments, Photos, And Signatures

### Intent

Photos, signatures, and saved snapshots support field evidence without becoming fragile one-off uploads.

### Current implementation

- service request photo upload path
- `service_report_photos`
- `SignaturePadWidget`
- saved checklist snapshots with photo URLs when already uploaded
- Supabase storage buckets/policies implied by request/report flows

### Happy path

```text
user attaches/captures media inside a workflow
-> media is stored locally or uploaded without losing the parent record
-> parent record references uploaded media
-> failed media upload is visible and retryable
-> viewers only see media for records they can read
```

### Rules

- Photo upload failure must not lose the parent service request/report/checklist.
- Signatures are required on every service report and are part of service-report draft state before submit.
- Photos are optional evidence in MVP.
- Media access policy must match the parent workflow's role/data scope.
- Exports should render media from stable source references, not transient local paths.

### Conflicts/risks

- Service request photos and service report photos may not share a reusable media workflow.
- Saved checklist photo history depends on photos already being uploaded.
- Offline media retry is harder than text drafts and needs explicit states.


### Garrett notes

-

## Workflow 30: Asset Type And Template Binding

### Intent

Asset types connect vessels/equipment to relevant checklist templates, service intervals, icons, and future parts kits.

### Current implementation

- `asset_type_provider`
- `asset_type` model
- `asset_checklist_template_filter`
- service-hour template sorting/fallback
- asset icons/theme helpers

### Happy path

```text
owner defines/selects asset type
-> asset is assigned that type
-> maintenance/operations templates filter by type
-> service intervals and PM kits use the same type/template assumptions
-> generic templates remain fallback when no specific template exists
```

### Rules

- Asset-type-specific templates beat generic templates.
- Generic fallback is useful, but should be visible enough that staff know why it appeared.
- Changing an asset type can change future checklist options but not historical saved checklists.

### Conflicts/risks

- Asset type admin lifecycle is not clearly exposed.
- Template/type binding can become invisible product logic if only buried in providers.
- PM parts and interval setup can drift from checklist type binding.


### Garrett notes

-

## Workflow 31: Localization, App Shell, And Navigation Policy

### Intent

Navigation should reflect role/workflow policy consistently, and labels should be stable enough for field users.

### Current implementation

- `AppShell`
- `router.dart`
- `app_en.arb`, `app_es.arb`
- generated localization files
- role dashboard routing

### Happy path

```text
authenticated user resolves role
-> shell/nav exposes only appropriate workflow entry points
-> direct route access is also blocked or redirected consistently
-> labels match shop/client language
-> localized text does not drift from workflow meaning
```

### Rules

- Hidden nav is not authorization.
- Role dashboard routing is a convenience, not a security model.
- Client-facing labels should not expose internal statuses like "resolved" when the work is only "being handled."

### Conflicts/risks

- Router has direct client work-order/checklist routes that may exceed product intent.
- App shell navigation can lag behind route/provider policy.
- Localization files can preserve outdated product language after workflow changes.


### Garrett notes

-

---

## Highest-Risk Conflicts

 1. Service reports accidentally created without `work_order_id`.
 2. Client/checklist PM submissions satisfying internal service intervals.
 3. Operators seeing maintenance, invoice, or service-report data.
 4. Client-side screens falling back to all assets.
 5. Dashboards using broad providers that RLS hides inconsistently.
 6. Invoice generation treating closed/invoiced WOs as no longer reportable.
 7. Asset Detail gaining mutation logic instead of routing into workflow modules.
 8. Hard asset delete losing history without a sufficiently explicit destructive warning.
 9. Legacy tier dashboard routes contradicting the newer capability switchboard.
10. Telemetry hours, manual hours, and checklist-entered hours being displayed without clear context.
11. Offline/local cache behavior implying safety before WO/checklist/report sync states are durable and visible.
12. Media upload failure losing photos/signatures or leaving source records half complete.
13. Checklist template edits changing future behavior without preserving old template meaning; tentative direction is version/archive after use.
14. Client/profile/org/capability screens mixing customer identity, team management, and workflow switches.
15. Direct routes bypassing role/capability intent because route visibility and backend policy are separate.



## Recommended Build Order

 1. Finish phone verification of service report v2 5C authoring.
 2. Add/confirm tests around work-order-scoped service report route and `work_order_id`.
 3. Add pending-sync service report submit states and retry/error visibility.
 4. Run invoicing workflow confirmation around completed-WO eligibility and sent-invoice edits.
 5. Add `ClientChecklistSubmission` for non-WO client/admin/mechanic checklist submissions.
 6. Refine PM completion to require explicit manual completion hours.
 7. Deepen asset summary read models before adding more Asset Detail cards.
 8. Add destructive hard-delete warning and permission guard before broad asset cleanup.
 9. Audit client direct routes and capability gates.
10. Retire/collapse tier dashboard scaffolding after core workflows are stable.
11. Separate checklist template setup/versioning from checklist run submission.
12. Clean repo debug artifacts and stale service report authoring code before outside review.

## Garrett Notes - General

-