# Vortice V2 Data, Offline Sync, And Security Spec

Date: 2026-05-24
Status: detailed planning draft for Garrett review

## Garrett Question Inbox

1. **Offline service requests:** Should service requests be offline-capable in V2 launch, or can they remain online-only while field work is offline-first?

   Garrett answer:

2. **Invoice offline scope:** Should invoices be offline-readable only, or editable/generatable offline too?

   Garrett answer:

3. **Parts logging offline:** Should parts logging work offline on day one?

   Garrett answer:

4. **Sync wording:** What sync state labels should field users see: `saved on this device`, `waiting to sync`, `sync failed`, `synced`, or simpler wording?

   Garrett answer: anything completed offline should be shown as pending/waiting until the phone has signal and upload succeeds. Checklists, work-order updates, service reports, and any other offline-capable records must make it clear they are ready to upload, not silently finished on the server.

5. **Close-WO blocking:** Should closing a WO be blocked when required checklist/report/media sync is pending?

   Garrett answer: yes. Vórtice Tech/Mechanic can mark the work locally as complete/waiting to sync, but the server-side work order must not become truly closed while required checklist, service report, photo, signature, or other required child evidence is still pending sync. Close is authoritative only after required child records and media are accepted by the server.

6. **Pending-sync visibility:** Should client users ever see pending-sync records created on internal Vórtice devices, or only after server sync succeeds?

   Garrett answer: unsynced pending work is visible only to the device/user that created it. Once upload succeeds, Vortice staff can see the record normally. Clients only see the record after the server accepts it and it reaches a client-safe state.

7. **Photo/signature upload:** Should photos/signatures be compressed before upload? If yes, do originals need to be preserved locally?

   Garrett answer: upload optimized photos/signatures for normal reports/history. Preserve the original full-size local file only until the upload is verified, then allow cleanup unless a specific legal/audit requirement later says originals must be retained.

8. **Audit history:** Do we need audit history for asset client assignment changes and asset fact edits in V2 launch?

   Garrett answer:

9. **Backend choice:** Should V2 use Supabase as the primary backend again, or is backend choice part of the rewrite decision?

   Garrett answer: V2 uses Supabase as the primary backend path. Supabase should be branched alongside the V2 Git branch so schema, RLS, migration, and seed-data work can be validated before production promotion.

10. **Longest no-service session:** What is the longest expected no-service field session: minutes, hours, full day, multi-day?

    Garrett answer:

## Data Ownership Principles

- Asset is the main domain anchor.
- Client profile owns the fleet relationship.
- Client org owns team membership.
- Work orders are internal Vortice records.
- Service reports, invoices, checklist history, and documents are client-visible records when role policy allows.
- Telemetry readings belong to the asset at the time recorded.
- Generated files are derived from source records, not source records themselves.

## Core Entity Map

| Entity | Purpose | Owner/scope | Notes |
| --- | --- | --- | --- |
| Profile/User | Authenticated person and role | user id | Role + org membership drives access |
| Client profile | Customer identity | profile id | Assets point to this id |
| Client org | Customer team | org id + owner_profile_id | Team users inherit fleet access |
| Org code/invite | Invite-only onboarding | client org + target role | Must set role and org |
| Asset | Vessel/equipment/unit | client profile | Main hub for history/work/telemetry |
| Asset type | Category/template binding | Vortice-managed/settings | Controls checklist/template defaults |
| Asset engine/component | Engine or monitored component under asset | asset | Supports hours/PM/telemetry context |
| Hour log | Manual hour record | engine/component/asset | Need precedence rules with telemetry |
| Capability | Enabled client workflow | client profile | Missing row defaults disabled |
| Service request | Client asks Vortice for service | client + optional asset | Not a work order |
| Work order | Internal Vortice job | client + asset | Not client-visible in MVP |
| Work-order assignment | Vórtice Tech/Mechanic assignment | WO + profile | Current model supports one main assignee plus assignment table direction |
| Checklist template | Repeatable checklist definition | Vortice/settings | Maintenance or operations |
| Checklist item | Template item | template | Pass/Monitor/Action/N/A response model |
| Checklist response | In-progress/WO response | WO/template/item | May be local/offline |
| Saved checklist | Immutable submitted history | asset + client | Canonical history record |
| Service interval | PM schedule | asset/engine/template | Vórtice PM can satisfy |
| Service reminder | Due/upcoming work | interval/asset | Reminder is not completion |
| Service report | Client-facing report | WO | Requires signature |
| Report photo | Evidence attachment | report | Optional |
| Part/log | Actual part used or parts catalog item | WO/client | Kit estimate vs actual used must be clear |
| PM kit/parts requirement | Planned parts for PM | template/asset type/client | Prefills, does not prove usage |
| Invoice | Client-facing bill | WO + client | Editable after sent per current decision |
| Document/export | Stored generated or uploaded file | parent record | Regeneratable where generated |
| Telemetry device | Gateway/device | asset pairing | Known device; no mystery creation |
| Device pairing history | Which device belonged to which asset when | asset/device | Needed for replace/unpair/history |
| Telemetry reading | Sensor snapshot | asset + device | Engine optional |
| Telemetry alert | Alert/DTC/threshold event | asset + device | Client ack, Vórtice Owner/Admin or Vórtice Tech/Mechanic resolve TBD |
| Notification | Attention item | user/client/asset/workflow | Routes to source workflow |
| Sync operation | Local pending mutation | device/user/entity | Durable queue |
| Local attachment | Local file awaiting upload | parent entity | Photos/signatures |

## Current Local Data Facts From Code

The current app already has a useful local/offline skeleton. V2 should salvage the data shape, but replace scattered fallback behavior with an explicit sync workflow users can see and recover from.

Current Drift tables include:

- `profiles`
- `assets`
- `asset_engines`
- `work_orders`
- `checklist_templates`
- `checklist_items`
- `checklist_responses`
- `service_reports`
- `parts`
- `invoices`
- `sync_operations`
- `local_attachments`

Useful current local fields:

- Work orders include asset/client/engine, assigned user, checklist template/version, job type, status, scheduled/start/completed dates, hours, labor/rates, internal notes, hold reason.
- Service reports include work order id, 5C fields, signature URL, signed date, sync status, last sync/error.
- Checklist responses include work order id, item id, complete flag, notes, photo URL, response status, completed by/at, sync status/error.
- Sync operations already model entity type, local/remote ids, operation type, payload JSON, dependency, status, attempts, retry time, errors.
- Local attachments already model owner entity, purpose, local path, mime type, hash, remote bucket/path/url, status, errors.
- Service report repository already proves the local-first pending-sync pattern is viable; V2 should generalize the pattern rather than hiding it inside one feature.
- Checklist response sync fields exist and should feed saved-history/offline rules, not become a silent partial-submit trap.
- Current work-order status mutations still need a V2 transition service/policy; direct server updates cannot enforce close blocking, dependency sync, or conflict review consistently.
- Current service-request-to-work-order prefill behavior is useful evidence for V2, but acknowledgement/review should be modeled explicitly before conversion.

## Offline Scope

Garrett decision: V2 must handle field work offline. Any workflow approved for offline use saves locally first, then remains in a visible pending state until the phone receives signal and uploads successfully. The app must distinguish between "done locally and ready to upload" and "synced/authoritative on the server" so field users are not lied to and office/client users are not shown half-synced records.

Pending-sync visibility rule: unsynced local work is device/user-local. It can be shown to the creator as waiting to sync, but it must not be shown to clients, and should not be treated as staff-visible server truth until the server accepts it. After successful sync, Vortice staff can see it according to normal workflow permissions; clients see it only when it is in a client-safe state.

Work-order close blocking rule: Vórtice Tech/Mechanic may complete required work locally and leave the work order in `completed` with local `waiting to sync`/pending-close sync state, but server-side `closed` is blocked until required checklist responses, service reports, photos, signatures, and other required child records have synced successfully. If sync fails or a dependency is missing, the work order stays open/pending review with a clear blocker instead of appearing closed without its evidence.

### Day-One Offline-Capable Workflows

Current direction says day-one offline scope includes:

- work-order workflows
- service-report pending-sync submit
- all checklist flows

Settled V2 launch offline scope:

- Read cached assigned internal WOs.
- Create local draft WOs and update internal WO field notes/details.
- Add labor/time and parts-used entries locally.
- Start, hold, resume, and complete locally as waiting-to-sync according to final transition rules.
- Run internal WO checklist as Vórtice Tech/Mechanic.
- Run client maintenance checklist.
- Run operator operations checklist.
- Save immutable checklist history locally pending sync.
- Create service report draft.
- Submit service report into durable pending-sync state.
- Capture service-report signature locally.
- Attach photos locally with retry.

### Online-Only Unless Approved

Online-only at launch unless explicitly reopened:

- creating client profiles/orgs/invite codes
- capability switchboard changes
- asset creation/edit/delete
- invoice generation/sending
- Vórtice Tech/Mechanic assignment and reassignment
- admin WO edits
- client-visible status changes
- authoritative server-side WO close
- reopening WOs that are already server-closed
- telemetry device pairing
- service request submission, if Garrett accepts online-only
- template creation/edit/versioning

## Work Order Lifecycle Model

Settled V2 launch rule: the main work-order status answers only where the job is operationally. It does not carry assignment, sync, review, billing, or client visibility.

Main status ladder:

- `draft`: created but not ready for field work.
- `ready`: assigned or available to start.
- `in_progress`: field work active.
- `on_hold`: paused with required reason.
- `completed`: Vórtice Tech/Mechanic says work is done; required evidence may still be pending sync or review.
- `closed`: Vórtice Owner/Admin or server policy accepts the WO as final.

Separate state fields:

- `sync_state`: local, syncing, synced, failed, conflict, blocked dependency.
- `review_state`: not required, pending review, changes needed, accepted.
- `billing_state`: not billable, pending invoice, invoiced, paid/settled.
- `client_visibility`: internal only, client visible, client notified.

Do not use `assigned`, `pending_review`, or `invoiced` as main V2 launch WO statuses. Assignment belongs to assignment data. Review belongs to `review_state`. Invoice progress belongs to invoice/billing records.

## Sync State Model

Recommended internal statuses:

- `local_draft`: saved only on device, not submitted.
- `pending_sync`: user submitted; queued for server.
- `syncing`: retry in progress.
- `synced`: authoritative server state caught up.
- `sync_failed`: last attempt failed; retry available.
- `conflict`: server rejected because state changed or permissions/data mismatch.
- `blocked_dependency`: waiting on parent record or attachment.

Recommended user labels:

- `Draft saved on this device`
- `Waiting to sync`
- `Syncing`
- `Synced`
- `Sync failed - retry`
- `Needs review`

Visibility rules:

- Creator/device: can see local drafts, pending sync, sync failed, and synced states.
- Vórtice internal users: sees records after server acceptance, plus any explicit server-side sync/review state.
- Client users: see synced client-safe records only; no unsynced local internal drafts or pending records.
- Server conflict/rejection creates a internal review item, not a client-visible partial record.

## Offline Rules By Workflow

### Work Orders

Settled launch policy: offline work orders support the field-critical path only.

- View cached assigned/open WOs offline.
- Create local draft WOs when needed for field work.
- Edit field-safe fields offline: notes, details, start/hold/resume, local `completed`/waiting-to-sync, labor hours, parts used, checklist answers, report links, photos, and signatures.
- Do not support offline Vórtice Tech/Mechanic assignment or reassignment for launch.
- Do not support offline client/asset reassignment.
- Block invoice generation offline.
- Show pending states in list/detail.
- Allow local `completed`/waiting-to-sync, but block authoritative server-side `closed` while required checklist/report/media/signature sync is pending.
- Allow local reopen only when the WO is not already server-closed; server-closed reopen queues for staff/server review.

Conflict examples:

- Two users change same WO status offline.
- One user closes WO while another adds checklist/report.
- Staff edits WO assignment while field device is offline.

Recommended conflict policy:

- Append-only evidence (checklists, reports, parts notes) should sync as new child records where possible.
- Destructive/overwriting fields need server version checks.
- Closing/reopening should require latest known server state or create a pending transition requiring review.
- A pending `completed -> closed` transition cannot resolve to `closed` until required child evidence is accepted by the server.

### Checklists

Rules:

- Checklist submission must be durable after user taps submit.
- Offline checklist submission means ready to upload, not server-complete.
- Checklist list/detail screens must show pending upload status until sync succeeds.
- Monitor/Action requires note or photo.
- Saved history must preserve template snapshot, item order, labels, responses, notes, photos, submitter, role, timestamp, asset, source context.
- Offline staff PM checklist must not satisfy PM interval until authoritative sync succeeds.
- Offline client/operator checklist can create pending saved history and pending client notification where applicable.

### Service Reports

Rules:

- Draft survives app restart.
- Submit offline creates pending-sync report, not merely draft.
- Signature required before submit.
- Photos optional; report text/signature can sync before photos only if UI shows media still pending.
- Client visibility waits for successful server sync and client-safe state; unsynced local internal reports are creator/device-local only.
- A work order can accept reports after close/invoice.

### Media

Rules:

- Parent record is never lost because a photo upload failed.
- Attachment queue tracks local path, owner entity, purpose, hash, remote path/status/error.
- If parent entity has local id, attachment depends on parent sync before upload.
- Generated PDFs should not depend on local-only media paths.

### Service Requests

If offline-capable:

- Save local request with asset/description/photos.
- Submit to server when online.
- Client sees waiting-to-send state.
- Vórtice internal users do not see request until synced.

If online-only:

- Disable submit offline with clear message.
- Preserve typed draft locally if possible.

## Security And Access Policy

### Required Layers

- Route guard: prevents obvious wrong-role routes.
- Screen guard: checks role/capability/data scope before rendering actions.
- Repository query scope: fetches only relevant records.
- Backend RLS: prevents cross-client/org leakage.
- Storage policy: matches parent record visibility.
- Export policy: only exports records user can read.

### Role-Specific Security Rules

- Vórtice Owner/Admin can manage all Vortice records.
- Vórtice Tech/Mechanic can manage assigned field workflows within approved scope.
- Client/client_admin can see their own/org fleet and records.
- Client mechanic sees client fleet maintenance/checklist/telemetry where enabled, not internal WOs.
- Operator sees operations assets/checklists/history only.
- Client users do not pair telemetry devices.
- Client users do not create/edit/delete assets.
- Public/self registration is out.

## RLS / Backend Rules To Preserve

- `client_capabilities`: owner manages; clients read own capabilities; missing rows disabled.
- `assets`: client/team visibility through `client_orgs.owner_profile_id`; internal Vórtice access per policy.
- `service_requests`: client/client_admin submit/read own/org; Vórtice Owner/Admin manages.
- `saved_checklists`: internal Vórtice users read/submit; client/org members read/submit based on asset scope and checklist type; operators only operations.
- `telemetry_readings` and `telemetry_alerts`: asset-owned; engine optional.
- `devices`: owners pair/manage; clients read permitted asset device where appropriate.
- `service_reports`: Vórtice Owner/Admin or Vórtice Tech/Mechanic create; clients view scoped reports; operators blocked.

## Audit Requirements

Strongly recommended audit events:

- asset created/edited/deleted
- asset client assignment changed
- client capability toggled
- invite code created/disabled/used
- client team member added/removed/role changed
- work order status transition
- work order reopened
- service request declined/converted
- service report submitted/edited/regenerated
- invoice generated/sent/edited/voided/paid
- telemetry device paired/replaced/unpaired
- checklist template version created/archived

## Data Model Gaps To Resolve

- Multiple Vórtice Tech/Mechanic assignments per WO versus single `assigned_to`.
- Clear source table for client-side notifications from Action/Monitor.
- Device pairing history table or status-history fields.
- Template versioning/archive semantics.
- Asset correction request table/workflow.
- Service request richer statuses.
- PM interval engine/asset/component scope.
- Parts catalog versus actual parts used versus PM kit estimate.
- Export/document table for stored generated files.
- Audit log.
