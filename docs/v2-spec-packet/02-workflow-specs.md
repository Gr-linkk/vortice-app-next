# Vortice V2 Workflow Specs

Date: 2026-05-24
Status: detailed planning draft for Garrett review

## Garrett Question Inbox

1. **Work-order status ladder:** Keep `draft -> assigned -> in_progress -> on_hold -> pending_review -> invoiced -> closed`, or simplify?

   Garrett answer: simplify the main work-order lifecycle to operational job state only: `draft -> ready -> in_progress -> on_hold -> completed -> closed`. Assignment, sync, review, billing, and client visibility are separate fields/tracks, not overloaded main statuses. `assigned`, `pending_review`, and `invoiced` are not V2 launch WO statuses.

2. **Offline work-order actions:** Which work-order actions must work offline on day one: create, edit, assign, start, hold, complete, reopen, add parts, add report?

   Garrett answer: use the field-critical offline set for V2 launch. Offline-capable WO work must save locally and remain pending until uploaded when the phone receives signal. Day one supports cached WO viewing, local draft WO creation, field notes/details, start/hold/resume, local complete as waiting-to-sync, checklist answers, photos, signatures, labor/time, parts used, and service reports. Offline tech assignment, admin edits, client-visible status changes, invoice generation, and authoritative server close are out of scope for launch. Reopen is local only when the WO is not already server-closed; otherwise it queues for staff/server review.

3. **Service request status:** Should a service request support `needs_more_info`, or only a simple launch lifecycle for now?

   Garrett answer: keep the client request workflow simple. A request is submitted, Vórtice Owner/Admin acknowledges/reviews it, then the request can prefill a draft work order. No fully automatic live work order is created without Vórtice Owner/Admin acknowledgement.

4. **Client mechanic action items:** Should client mechanics be able to submit Action/Monitor items that create client-side notifications, same as operators?

   Garrett answer:

5. **Action/Monitor notification recipients:** Should Action/Monitor notifications go to client admins only, all client admins + client owner, or all client-side fleet users?

   Garrett answer:

6. **PM-generated work orders:** Should PM-generated work orders be owner-only, or can employees generate them from due intervals?

   Garrett answer:

7. **Checklist template versioning:** Should used checklist templates become locked/versioned automatically, or can owner edit active templates in place?

   Garrett answer:

8. **Service report drafts:** For service reports, should there be one active draft per work order, or multiple drafts when multiple techs/report sections exist?

   Garrett answer:

9. **Client-visible report status:** What report statuses should clients see: only final synced reports, or also pending/internal draft indicators?

   Garrett answer: clients see synced client-safe records only. Unsynced local staff drafts or pending-sync reports remain visible only to the creator/device until the server accepts them; Vortice staff can then see them according to normal workflow permissions.

10. **Invoice lifecycle:** Should invoice generation automatically move a WO to `invoiced`, or should invoice and WO lifecycle stay separately controlled?

    Garrett answer: invoice and WO lifecycle stay separately controlled. Invoice state belongs in billing/invoice fields, not the main WO status ladder. Completed WOs are invoice-eligible; invoicing does not turn the WO into an `invoiced` status.

11. **PM procedure hyperlinks:** Are hyperlinks from PM checks/checklists to procedure documents first-MVP scope?

    Garrett answer: no. PM checklist/procedure hyperlinks are not first-MVP scope because the source procedure documents are not yet clean and stable enough. First MVP should rely on checklist text, required materials/parts, notes, and optional attachments/references. Procedure hyperlinks become later-phase work after document curation.

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

## Workflow Inventory

Current-app references below are evidence to salvage, not implementation commands. V2 should reuse the workflow truth and data relationships where they are clean, while rebuilding noisy screens/providers around explicit modules.


| # | Workflow | V2 priority | Current source/reference |
| --- | --- | --- | --- |
| 1 | Invite-only auth and role routing | P0 | `auth_provider`, `router.dart`, org-code migrations |
| 2 | Client profile, org, and fleet scope | P0 | client org access model, asset visibility migrations |
| 3 | Capability switchboard | P0 | `client_capabilities`, product decision doc |
| 4 | Asset creation/edit/delete | P0 | asset screens/providers |
| 5 | Asset hub/detail | P0 | `AssetDetailScreen`, `AssetWorkflowPolicy` |
| 6 | Service request intake | P0 | `service_requests`, service request screens |
| 7 | Vórtice Owner/Admin request triage to WO | P0 | request list + WO draft flow |
| 8 | Internal work orders | P0 | work-order screens/providers/repository |
| 9 | Vórtice PM interval to WO/checklist/history | P0 | service intervals, PM completion |
| 10 | Client maintenance checklists | P0/P1 | checklist history spec, client checklist route |
| 11 | Operator checklists and operations history | P0/P1 | operator checklist flow |
| 12 | Saved checklist history | P0 | `saved_checklists` |
| 13 | Service reports | P0 | service report rebuild plan |
| 14 | Parts and PM kits | P1 | parts/PM kit screens |
| 15 | Invoicing | P1 | invoice screens/services |
| 16 | Telemetry readings/alerts | P1 | asset-first telemetry ADR |
| 17 | Device pairing | P1 | devices table, device pairing screen |
| 18 | Notifications/reminders/flags | P1 | notifications/reminders/maintenance flags |
| 19 | Documents/media/exports | P1 | report/invoice PDFs, storage |
| 20 | Dashboards/navigation | P1 | dashboard screens/router |
| 21 | Template/asset-type setup | P1 | checklist templates, asset types |
| 22 | Meeting/demo request | Drop for V2 launch | suspect legacy screen; Garrett confirmed no public marketing/demo/request screens |

## Workflow 1: Invite-Only Auth And Role Routing

### Intent

Users enter Vortice through explicit invitation and land in the correct experience for their role and organization.

### Happy Path

```text
Vórtice Owner/Admin creates client org/invite code
-> user registers or accepts invite with code
-> profile.role and profile.org_id are set
-> app resolves role + org/client scope
-> user lands on role dashboard
-> route guards and backend policies enforce same scope
```

### Rules

- No open public self-registration.
- Invite code must set both role and org membership.
- Auth routing is not authorization.
- Hidden navigation is not enough; direct routes must also be blocked.
- Recovery for lost/mistyped codes must not let users self-assign a client or role.

### Acceptance Criteria

- A new user without invite context cannot create a usable account.
- A client org member cannot access another client's fleet by route guessing.
- A client mechanic cannot reach internal work-order routes.
- An operator cannot reach maintenance tabs, service reports, or invoices.

## Workflow 2: Client Profile, Org, And Fleet Scope

### Intent

The client profile owns the fleet relationship. The client org controls team membership. Team members inherit visibility to the client owner's fleet.

### Canonical Relationship

```text
profiles.id = client owner/profile id
assets.client_id -> profiles.id
client_orgs.owner_profile_id -> profiles.id
profiles.org_id -> client_orgs.id
```

### Happy Path

```text
owner creates/selects client profile
-> owner creates assets assigned to that client profile
-> owner creates client org for that profile
-> owner creates invite codes for client roles
-> invited users join org
-> users see fleet through org owner profile
```

### Rules

- Client profile is customer identity.
- Client org is team membership.
- Client users can manage team membership only where approved.
- Client users cannot create assets.
- Client users cannot directly edit asset facts.
- Asset assignment changes must be treated as high-risk because they move history visibility.

### Open Design Details

- Whether employees see all fleet assets or only assigned assets.
- Whether client admins can deactivate/remove team members and change roles.
- Whether client profile/org/capabilities live on one screen or separated admin screens.

## Workflow 3: Capability Switchboard

### Intent

Vortice staff enables optional workflows per client according to the services that customer is paying for or has been granted, without using rigid subscription tiers as app behavior.

This switchboard controls customer workflow entitlement. It does not create roles, replace org/team membership, or remove baseline portal access.

### Current App Evidence

- `public.client_capabilities`
- `ClientCapability` / `ClientCapabilitySwitchboard`
- Owner client screen section labeled `Service Switchboard`
- `ClientCapabilityGate`, `clientCapabilitiesProvider`, `clientCapabilityGateProvider`

### Capabilities

- `operational_checklists`
- `pm_checklists`
- `pm_parts_lists`
- `maintenance_planning`
- `telemetry`

### Always-On Client Portal

- fleet/assets
- asset history and allowed records
- service requests
- service reports
- invoices
- documents/generated files

### Happy Path

```text
owner opens client admin
-> owner reviews the services/workflows enabled for that customer
-> owner toggles capabilities in the Service Switchboard
-> client dashboard/routes update
-> direct access to disabled features is blocked
-> existing history remains visible read-only where allowed
```

### Rules

- Missing capability row means disabled.
- Capability off prevents new workflow use, not history access.
- Baseline portal access, fleet, service requests, service reports, invoices, documents, and allowed history are not paid-workflow toggles.
- `pm_checklists` enables client-side mechanic/checklist workflows and should control creation/invitation of client mechanic workflow users.
- `operational_checklists` enables operator/captain checklist workflows and should control creation/invitation of operator workflow users.
- Capabilities are not security boundaries by themselves.
- Route guards, screen guards, and RLS must agree.

## Workflow 4: Asset Creation, Editing, And Deletion

### Intent

Assets are the canonical units/vessels/equipment records all maintenance and telemetry attach to.

### Happy Path

```text
owner creates asset
-> selects client profile
-> selects asset type
-> enters name, make/model, serial/PIN, location, notes
-> asset appears in Vortice staff fleet and permitted client fleet
```

### Required MVP Fields

Recommended baseline:

- asset name
- client owner/profile
- asset type/category
- serial/PIN/HIN or explicit `unknown`
- location/site
- status: active/inactive/sold/retired TBD

### Rules

- Asset creation is owner-only unless Garrett approves employee asset creation.
- Clients request corrections rather than editing facts directly.
- Hard delete is allowed only behind explicit destructive warning.
- Delete warning must say all asset data/history can be lost.
- Prefer archive/inactive for real production records once history exists.

### Risks

- Moving `client_id` changes which client can see historical records.
- Current delete path exists; V2 must make destructive intent impossible to miss.

## Workflow 5: Asset Hub / Detail

### Intent

Asset Detail is the hub for asset facts, service history, work context, checklists, maintenance plan, telemetry, documents, and client actions.

### Role-Specific First Screen

Vórtice Owner/Admin:

- asset facts
- client/owner
- current work orders
- due PM/reminders
- service requests
- reports/history
- checklist history
- telemetry status/pairing
- documents

Employee:

- asset facts
- assigned/current work
- checklist/report actions
- history
- parts/labor context

Client/client admin:

- asset facts
- service request action
- service reports/history
- invoices/documents
- enabled checklist/maintenance planning/telemetry cards

Client mechanic:

- asset facts
- enabled maintenance checklist actions
- checklist history
- telemetry if enabled
- no internal work orders

Operator:

- operations checklist action
- operations history
- telemetry if enabled and permitted
- no maintenance/service report/invoice/internal WO surfaces

### Rules

- Asset Detail can summarize and route.
- Current `AssetWorkflowPolicy` is a useful salvage seam for centralizing role behavior, but V2 must expand it for split staff roles and direct-route guards.
- Asset Detail should not directly close WOs, satisfy PM, submit reports, or write checklist history.
- Role policy should be centralized and testable.
- Client-facing cards must not expose internal WO status/details.

## Workflow 6: Service Request Intake

### Intent

Clients ask Vortice for service through a baseline request workflow. A request is not a work order.

### Happy Path

```text
client/client_admin opens service request
-> selects asset or "other/not listed"
-> enters type/title/description/contact/hours/photos
-> submits request
-> request status = new
-> Vórtice Owner/Admin sees request inbox
-> Vórtice Owner/Admin acknowledges/reviews request
-> client sees sent/received/acknowledged state
```

### Rules

- Service requests are always-on for client/client_admin.
- Client mechanic/operator do not directly submit Vortice service requests in MVP unless Garrett changes this.
- Photo upload failure must not lose request.
- Request can be declined, acknowledged, or converted to a prefilled draft WO.
- Vórtice Owner/Admin acknowledgement/review is the human checkpoint before WO creation.
- No fully automatic live WO is created from a client request in V2.
- `resolved` in old schema means handled, not mechanically completed.

### Current App Salvage Notes

- Current service-request flow is close to the desired V2 shape: simple client intake, staff review, then assisted work-order generation.
- Preserve the existing prefill behavior where request details carry into a draft work order, but make staff acknowledgement/review an explicit lifecycle step.
- Do not expand this into a heavy client project-management workflow for launch; the value is that the client can report the issue cleanly and Vortice can turn it into internal work.
- Current status language is thinner than V2 needs. V2 should separate client-facing labels from internal lifecycle states so `acknowledged`, `converted`, `declined`, and `resolved/closed` do not get muddled.

### Recommended V2 Launch Status Model

Keep the launch service-request lifecycle simple. `needs_more_info` can be added later if real intake volume proves it is needed; it should not be part of the first status ladder unless Garrett explicitly reopens it.

Internal:

- `new`
- `acknowledged`
- `declined`
- `converted_to_work_order`
- `closed`

Client-facing:

- `Sent`
- `Received`
- `Acknowledged`
- `Declined`
- `In progress`
- `Completed`

## Workflow 7: Vórtice Request Triage To Work Order

### Intent

Vórtice Owner/Admin turns service requests into internal Vortice work orders or declines/returns them for more information.

### Happy Path

```text
Vórtice Owner/Admin opens request inbox
-> reviews asset, description, photos, contact info
-> Vórtice Owner/Admin acknowledges/reviews request
-> choose Generate Work Order
-> work-order draft is prefilled from request details
-> Vórtice Owner/Admin reviews and saves WO
-> request links to generated_work_order_id
-> client request status updates to client-safe label
```

### Rules

- Backing out of WO creation leaves request unchanged.
- Saving generated WO marks request handled/converted.
- WO generation is assisted prefill, not automatic live WO creation.
- Declining requires client-safe reason.
- Clients do not see the internal WO from this bridge.
- Vórtice Owner/Admin UI should preserve backlink between request and WO.

### Current App Salvage Notes

- Existing generated-WO flow is worth keeping as reference because it already matches Garrett's decision: acknowledgement/review first, then prefilled draft WO.
- V2 should harden the bridge with explicit backlinks in both directions: request -> generated WO and WO -> source request.
- The triage inbox should show whether a request is new, acknowledged/reviewed, converted, declined, or closed without exposing internal WO details to the client.

## Workflow 8: Internal Work Orders

### Intent

Work orders coordinate Vortice internal service work: assignment, status, checklist, labor, parts, reports, invoicing, and completion.

### Current Status Ladder

Current code has a useful but overloaded ladder: `draft`, `assigned`, `in_progress`, `on_hold`, `pending_review`, `invoiced`, `closed`. V2 keeps the operational spine and moves assignment, review, billing, sync, and client visibility into separate fields.

Settled V2 launch ladder:

- `draft`: created but not ready for field work.
- `ready`: assigned or available to start.
- `in_progress`: field work active.
- `on_hold`: paused with required reason.
- `completed`: Vórtice Tech/Mechanic says the work is done; evidence may still be syncing or awaiting review.
- `closed`: Vórtice Owner/Admin or server policy accepts it as final.

Separate tracks:

- `assigned_to`/assignment records: who owns or participates in the work.
- `sync_state`: local, syncing, synced, failed, conflict, blocked dependency.
- `review_state`: not required, pending review, changes needed, accepted.
- `billing_state`: not billable, pending invoice, invoiced, paid/settled.
- `client_visibility`: internal only, client visible, client notified.

Dropped as main statuses for V2 launch: `assigned`, `pending_review`, and `invoiced`.

### Happy Path

```text
Vórtice Owner/Admin creates WO manually, from service request, or from PM
-> selects client, asset, optional engine/component, job type
-> assigns Vórtice Tech/Mechanic user(s)
-> Vórtice Tech/Mechanic starts work
-> Vórtice Tech/Mechanic performs checklist/notes/parts/labor
-> service report(s) authored
-> Vórtice Tech/Mechanic marks WO completed
-> sync/review/billing tracks resolve separately
-> Vórtice Owner/Admin or server policy closes WO when accepted
```

### Rules

- Internal WOs are not visible to clients.
- Work-order `asset_id` and `client_id` must remain coherent.
- WO can have zero or many service reports.
- Closed WOs and WOs with invoiced billing state can still accept missed/additional service reports.
- Offline behavior must be explicit for every WO action.
- Assignment should support multiple Vórtice Tech/Mechanic users eventually, even if current model stores one primary `assigned_to`.
- Current direct server-side status updates are not enough for V2. Status transitions must go through a named workflow policy so offline state, required evidence, and close-blocking rules are enforced consistently.
- Vórtice Tech/Mechanic can mark work locally complete/waiting to sync, but authoritative server-side `closed` requires accepted checklist/report/photo/signature evidence where required.

### Current App Salvage Notes

- Current work-order code already has the right spine: create, assign, start/in-progress, checklist, complete, reopen, invoice/report hooks.
- Preserve the domain shape, but do not preserve overloaded statuses as the V2 API contract.
- Rebuild or wrap status mutation behind a transition service/policy. Today, work-order status can still be updated directly through Supabase paths, which bypasses the new V2 evidence/sync guardrails.
- Keep reports attached to work orders, but do not make reports the owner of work-order lifecycle. WO lifecycle owns internal work; reports are client-facing evidence/history.

### Settled Transition Rules

| From | To | Actor | Required data |
| --- | --- | --- | --- |
| draft | ready | `Vórtice Owner/Admin` | assignment or ready-for-field-work flag |
| ready | in_progress | `Vórtice Tech/Mechanic` | start timestamp |
| in_progress | on_hold | `Vórtice Tech/Mechanic` | hold reason |
| on_hold | in_progress | `Vórtice Tech/Mechanic` | resume timestamp optional |
| in_progress | completed | `Vórtice Tech/Mechanic` | completion details, required evidence policy |
| completed | closed | `Vórtice Owner/Admin` or server policy | accepted review and required evidence synced |
| completed | completed | `Vórtice Owner/Admin` | invoice state changes in billing track only |
| closed | in_progress | `Vórtice Owner/Admin` TBD | reopen reason; server-closed reopen requires staff/server review |

Actor rule: use dev-login persona labels in transition specs. `Vórtice Owner/Admin` handles admin, office, review, billing prep, and close authority. `Vórtice Tech/Mechanic` handles assigned field execution. Client personas never perform internal WO status transitions.

## Workflow 9: Vórtice PM Interval To WO / Checklist / History

### Intent

Vórtice Owner/Admin or Vórtice Tech/Mechanic PM work can satisfy maintenance intervals. Client-side checklist submissions do not satisfy PM intervals in MVP.

### Happy Path

```text
asset service interval defines schedule/template
-> due/reminder appears
-> Vórtice Owner/Admin generates PM work order
-> WO stores job_type = preventative/pm and checklist template
-> Vórtice Tech/Mechanic completes checklist
-> saved_checklists records immutable history
-> PM completion uses manually entered completion hours
-> reminder/interval advances
-> WO moves toward completed, then closed only after authoritative sync/review
```

### Rules

- Vórtice PM completion may satisfy intervals.
- PM completion hours are manually entered by Vórtice Owner/Admin or Vórtice Tech/Mechanic.
- Telemetry/checklist/WO hours can inform context but do not silently win.
- Hyperlinks from PM checklist items to procedures are later-phase scope, not first MVP, until source procedure documents are curated and stable.
- Order matters: save responses, file history, then satisfy PM/close WO.
- Offline pending checklist must not mark interval satisfied until authoritative sync succeeds.

### Open Detail

- Asset-hour versus engine-hour interval logic.
- Multiple engines/components under one asset.
- Whether Vórtice Tech/Mechanic can generate PM WOs, or only Vórtice Owner/Admin.

## Workflow 10: Client Maintenance Checklists

### Intent

Client admins/mechanics can run enabled asset-associated maintenance checklists without creating internal Vortice work orders.

### Happy Path

```text
client admin/mechanic opens asset
-> pm_checklists capability is enabled
-> app shows associated maintenance templates
-> user fills checklist header/items
-> Monitor/Action requires note or photo
-> submit writes saved_checklists as asset history
-> no Vortice WO is created
-> no PM interval is satisfied
```

### Rules

- Preserve the current app's clean separation between staff maintenance, client maintenance, and operator operations submission paths.
- This is asset history only in MVP.
- Hyperlinks from checklist items to procedures are later-phase scope, not first MVP, until source procedure documents are curated and stable.
- Do not update `service_reminders`.
- Do not notify Vortice automatically in MVP.
- Client mechanic uses this path instead of internal WOs.
- Assignments can nudge; they are not permissions.

### Current App Salvage Notes

- Current code already separates client-submitted maintenance checklists from internal Vortice work orders. Preserve that boundary.
- Client checklist submissions should write saved asset history only. They do not complete internal WOs, satisfy PM intervals, or create Vortice service work unless a separate service request is submitted.
- Existing checklist orchestration and saved-history writer tests are useful V2 reference points.

## Workflow 11: Operator Checklists And Operations History

### Intent

Operators/captains perform operations/pre-op/daily checks. These become operations history, not maintenance history.

### Happy Path

```text
operator opens operational checklist
-> selects assigned/permitted asset
-> fills Pass/Monitor/Action/N/A responses
-> Monitor/Action requires note or photo
-> submitted run writes saved_checklists with checklist_type = operations
-> Action/Monitor creates client-side notification
-> client/admin decides whether to create service request
```

### Rules

- Preserve operations history as its own saved-checklist category.
- Operators see operations history only.
- Operators do not see Maintenance tab.
- Operator exceptions do not automatically create Vortice service requests or WOs.
- Action/Monitor creates client-side notification only in current direction.

### Current App Salvage Notes

- Current operations checklist flow already points the right way: operator submissions become operations history, not maintenance completion.
- Preserve the distinct operations-history surface so operator records do not pollute maintenance history or internal WO state.

### Open Detail

- Whether operators choose all fleet assets or only assigned/current assets.
- Notification recipients.
- Whether older maintenance flag screens remain separate.

## Workflow 12: Saved Checklist History

### Intent

Every submitted checklist becomes a durable saved copy under the asset.

### Canonical Record

`saved_checklists` should store:

- id
- asset id
- client id/org scope
- template id
- template name
- template version
- checklist type: maintenance/operations
- source type: vortice/work_order/client/operator
- submitted by user/role
- submitted timestamp
- current hours
- general notes
- optional work_order_id
- optional assignment_id
- immutable snapshot JSON

### Rules

- No edit/delete/amendment in MVP.
- Historical saved records remain visible even if capability is later disabled.
- Maintenance and operations tabs stay distinct.
- Operators only see operations.
- Clients can see Vortice staff maintenance checklist history by default.
- Internal notes must not leak through snapshots.

### Current App Salvage Notes

- `SavedChecklistHistoryWriter` is a strong salvage seam. V2 should keep the idea of one immutable asset-history writer instead of scattering saved-history writes through screens.
- Checklist submission order matters: save responses/evidence, write saved history, then satisfy PM or advance WO state only after authoritative sync where required.
- Snapshot data must be client-safe before it becomes visible to client roles.

## Workflow 13: Service Reports

### Intent

Service reports are Vortice-authored client-facing records linked to work orders. They are not the internal work order.

### Relationship

```text
work_orders.id -> service_reports.work_order_id
```

One work order can have many service reports. One service report belongs to one work order.

### Happy Path

```text
staff opens Work Order Detail
-> Add Service Report
-> authoring flow opens with required workOrderId
-> staff fills 5C form: complaint, cause, correction, collateral, comments
-> signature captured
-> optional photos attached
-> review screen validates required fields
-> submit produces synced or durable pending-sync report
-> client can view final report where allowed
```

### Rebuild Direction

- Build from small screens/steps, not one oversized authoring page.
- Phone layout is primary.
- Required actions should not be buried at bottom of long form.
- First stable slice should prove 5C draft persistence before signature/photos/PDF.
- Old authoring screen is reference-only.

### Rules

- Create: owner, employee.
- View: owner, employee, client, client_admin, client_mechanic.
- No access: operator/client_operator.
- Work-order-scoped authoring requires `workOrderId`.
- No orphan global service report creation.
- Offline submit must create durable pending-sync report, not just local draft.
- Signature required every time.
- Photos optional.
- Clients see synced client-safe reports only; unsynced local staff drafts or pending-sync reports remain creator/device-local until server acceptance.
- Upload optimized photos/signatures for normal reports/history. Preserve full-size originals locally only until upload is verified, unless a later legal/audit requirement says otherwise.

### Current App Salvage Notes

- Current service report repository already proves the local-first/pending-sync pattern is viable. Generalize that pattern instead of leaving it hidden in one feature.
- Current service-report workflow correctly allows reports to attach to closed WOs and WOs with invoiced billing state. Preserve this because missed/additional reports are real-world cleanup, not a reason to reopen billing automatically.
- Current authoring UI remains reference-only. The V2 authoring surface should still be rebuilt around phone-first steps: 5C draft, signature, optional photos, review, submit/pending sync.

## Workflow 14: Parts And PM Kits

### Intent

Parts support work-order costing, PM planning, PM kits, and invoice accuracy.

### Happy Path

```text
Vórtice Tech/Mechanic logs parts against WO
-> parts include quantity, cost, markup, supplier, notes
-> invoice generation can include actual parts
```

PM kit:

```text
Vórtice Owner/Admin creates PM parts list tied to asset type/template/interval
-> PM-generated WO can prefill expected parts
-> tech adjusts actual parts used
-> invoice uses actual parts, not kit estimate unless confirmed
```

Recommended inventory:

```text
Vórtice Owner/Admin defines required parts/materials at the asset level
-> asset-level requirements can include part numbers, quantities, intervals, suppliers, and notes
-> site/fleet recommended inventory rolls up from the assets assigned to that client/location
-> maintenance planning compares upcoming PMs against required parts/materials
-> client dashboard can show parts to stage, recommended stock, and missing parts data
```

### Rules

- PM kits prefill work-order parts; they are not immutable actual-used records.
- `pm_parts_lists` gates optional client-side parts guidance.
- Recommended inventory is an optional advisory workflow tied to `pm_parts_lists` / maintenance planning.
- Asset-level requirements are the source record; fleet/site recommended inventory is a roll-up view.
- Recommended inventory exists to shorten downtime by helping clients stage parts/materials before PMs or known high-hour work.
- Parts do not decide whether PM is satisfied.
- Recommended inventory does not prove physical stock is available unless stock tracking is explicitly enabled and maintained.
- Vortice does not automatically purchase parts from recommended inventory.
- Client parts price visibility is TBD.

## Workflow 15: Invoicing

### Intent

Invoices are client-facing billing records generated from reviewed/completed internal work.

### Happy Path

```text
owner opens invoice area
-> selects completed WO without invoice
-> invoice draft is generated from labor/parts/rates
-> owner edits lines/taxes/notes
-> PDF/XLSX generated and stored
-> invoice marked sent/paid/voided as appropriate
-> client views invoice
```

### Rules

- Completed WOs are invoice-eligible. Review state can block sending, but it is not a main WO status.
- Sent invoices can still be edited.
- Invoice should preserve customer identity, source WO, totals, taxes, currency, line items, and export URLs.
- Export generation should not mutate workflow state except explicit sent actions.
- Closed WOs and WOs with invoiced billing state can still accept follow-up service reports.

### Open Detail

- Exact billing-state names and invoice send/paid transitions.
- PDF, Excel, or both for MVP.
- Whether client can download exports directly.

## Workflow 16: Telemetry Readings And Alerts

### Intent

Telemetry is asset-first. It supports live visibility, historical readings, alerts, fuel advisory forecasting, and eventually maintenance planning.

### Happy Path

```text
paired gateway uploads asset-pinned readings
-> asset detail shows telemetry status
-> user opens latest/history
-> fuel and operating-hour trends feed advisory planning when enough data exists
-> app estimates burn rate and upcoming fuel need
-> alerts appear for permitted users
-> client acknowledges alert
-> client can create service request if Vortice help is wanted
-> staff resolves/clears alert according to final policy
```

### Rules

- `asset_id` is the canonical telemetry owner.
- `engine_id` is optional/future detail.
- Gateway health is separate from engine readings.
- Do not insert fake/test telemetry into production app tables.
- Do not finalize telemetry MVP value list until real gateway field evidence.
- Historical readings stay attached to the asset they belonged to at recording time.
- Vortice provides fuel advisory forecasting, not automatic purchasing.
- Fuel forecasting belongs to telemetry/planning, not PM interval satisfaction.
- First fuel-forecasting version should be simple: manual/imported fuel entries, operating hours, average burn rate, and 7/14/30-day advisory need.
- Fuel trends can create warnings/recommendations, but operating hours remain the driver for scheduled PM intervals.
- Recommended output should answer the client question: approximately how much fuel to order and by what date.

### Paradise Fuel Planning Direction

Paradise's fuel problem is ordering uncertainty, not just chart visibility. The V2 direction is to use fuel added/used plus operating hours to show litres-per-hour, litres-per-day/week, normal/rising/abnormal trend, and an advisory reorder estimate. This should stay advisory until data quality is proven and should not automatically create purchases or mutate PM schedules.

### Open Detail

- What fuel inputs will Paradise provide first: fuel added, fuel used, tank/supply level, operating hours, or all of them?
- Should early fuel forecasting be per asset only, or also fleet/site-level for ordering?

## Workflow 17: Device Pairing

### Intent

A physical gateway links to an asset through a controlled Vórtice Owner/Admin pairing flow.

### Settled Direction

- Vórtice Owner/Admin only for MVP.
- Asset must exist before pairing.
- Device already has a setup/pairing code from device setup.
- App verifies known code; it does not create mystery devices.
- One active telemetry device per asset.
- Pair, Replace, Unpair actions are explicit.
- Replacing preserves old pairing history.
- Unpairing preserves history.
- No Move Device shortcut for MVP.

### Happy Path

```text
owner opens asset telemetry card
-> enters/scans device code
-> backend verifies code exists and is available
-> device is linked to asset
-> readings flow to that asset
```

## Workflow 18: Notifications, Reminders, And Flags

### Intent

Notifications and reminders surface attention, but do not own workflow state.

### Rules

- PM reminders support due-state; PM completion workflow satisfies intervals.
- Notifications route to existing workflow screens.
- Action/Monitor checklist results create client-side notifications in current direction.
- Maintenance flags are not work orders.
- Client chooses whether to create Vortice service request.

### Open Detail

- Which reminders are staff-only versus client-visible.
- Whether notifications are in-app only or later push/email/SMS.
- Whether old maintenance flag screens remain or collapse into notifications/service requests.

## Workflow 19: Documents, Media, And Exports

### Intent

Photos, signatures, PDFs, Excel files, and generated records support proof and sharing without replacing source records.

### Rules

- Parent records must survive media upload failures.
- Media upload retries must be visible.
- Signatures are required for service reports.
- Photos are optional evidence for service reports and requests.
- Generated files are stored and regeneratable.
- File access policy follows parent record access.
- Exports should render from stable source references, not transient local paths.

## Workflow 20: Dashboards And Navigation

### Intent

Dashboards route users into real workflows without creating alternate business logic.

### Rules

- Counts/cards must match underlying list providers.
- "Needs attention" cards route to filtered useful lists/details.
- Client dashboard is capability-driven, not tier-driven.
- Operators see operations work only.
- Dashboard actions must not duplicate or contradict Asset Detail/WO Detail actions.

### Current-Code Risk

Current app still has `ClientDashboardFree`, `ClientDashboardManaged`, and `ClientDashboardTelemetry`. V2 should replace this with one client dashboard that renders baseline portal + enabled capabilities.

## Workflow 21: Template And Asset-Type Setup

### Intent

Checklist templates and asset types define repeatable work without hiding permissions inside assignments.

### Rules

- Maintenance and operations templates remain distinct.
- Asset-type-specific templates beat generic templates.
- Generic fallback is useful but should be visibly labeled.
- Used templates should likely be versioned/archived before edits.
- Assignments nudge users toward work; they do not grant asset access.
- Changing asset type can affect future checklist options, not history.

## Workflow 22: Meeting / Demo Request

### Current Status

Removed from V2 launch scope. Garrett confirmed V2 should not include public marketing/demo request screens.

### Rule

V2 app access is invite-only and authenticated. Public lead capture, marketing, or demo-request workflows belong outside the V2 application unless Garrett later creates a separate marketing-site requirement.
