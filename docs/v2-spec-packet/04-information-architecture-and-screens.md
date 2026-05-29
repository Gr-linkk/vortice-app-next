# Vortice V2 Information Architecture And Screens

Date: 2026-05-24
Status: detailed planning draft for Garrett review

## Garrett Question Inbox

1. **Vórtice Owner/Admin first screen:** What should be the first screen for Vórtice Owner/Admin: operational dashboard, client list, work queue, or asset search?

   Garrett answer:

2. **Mechanic/employee first screen:** What should be the first screen for a mechanic/employee: assigned work, today's schedule, or asset search?

   Garrett answer:

3. **Client admin first screen:** What should be the first screen for client admin: fleet overview, service requests, or needs-attention dashboard?

   Garrett answer:

4. **Operator first screen:** What should be the first screen for operator/captain: select asset, resume last asset, or today's checklist?

   Garrett answer:

5. **Asset Detail layout:** Should Asset Detail use tabs, sections, or role-specific cards?

   Garrett answer:

6. **Global search:** Should V2 include a global search across assets, clients, serials, reports, invoices, and work orders?

   Garrett answer:

7. **Document placement:** Should reports/invoices/documents live under each asset first, or also have global lists?

   Garrett answer:

8. **Vórtice Owner/Admin setup screens:** Should the mobile app include Vórtice Owner/Admin setup screens, or should setup be desktop/tablet-first later?

   Garrett answer:

## Resolved From Garrett Notes

- Phone/mobile field use is the first production target. Tablet and desktop office workflows are secondary until the core field paths survive on mobile.
- English and Spanish must both ship in the first build. UI text, status labels, PDFs/exports, and client-facing workflow language need localization-ready keys from the start.
- No public marketing/demo request screens for V2 launch. Users enter through authenticated invite-only access.
- French should be handled as another locale in the same app, not as a separate branch. Use shared localization keys, ARB/resource files, and CI checks for missing strings.

## Navigation Principles

- Users start from their work, not from marketing.
- Invite/auth screens are the public edge; marketing/demo capture stays outside V2 app scope.
- Asset Detail is the shared hub.
- Dashboards summarize and route; they do not own workflow state.
- Disabled capability surfaces are hidden in normal nav and blocked on direct access.
- Client-facing navigation avoids internal Vortice terms.
- Field forms keep primary actions visible and avoid long fragile screens.
- Phone layout is primary for field workflows and is the first acceptance target.

## Top-Level App Areas

Recommended global areas:

- Dashboard / Work Queue
- Assets / Fleet
- Service Requests
- Work Orders (staff only)
- Checklists / History
- Service Reports
- Invoices
- Parts / PM Kits
- Clients / Orgs / Capabilities (Vórtice Owner/Admin)
- Telemetry
- Notifications / Reminders
- Settings / Account
- Auth / Invite Acceptance

## Owner/Admin Experience

### Primary Jobs

- See operational workload.
- Manage clients and capabilities.
- Create/manage assets.
- Triage service requests.
- Create/assign/manage WOs.
- Review ready-for-invoice work.
- Generate/send invoices.
- Manage telemetry pairing.
- Manage checklist templates and PM setup.

### Suggested Home Dashboard

Cards/lists:

- New service requests.
- WOs needing assignment.
- In-progress/on-hold WOs.
- Ready for invoice/review (from review/billing state, not main WO status).
- Failed/pending sync items.
- Telemetry alerts.
- PM due soon.
- Recent service reports.

Actions:

- New asset.
- New work order.
- New client/org invite.
- Open client.
- Open asset search.

## Employee/Mechanic Experience

### Primary Jobs

- See assigned work.
- Start/hold/resume/complete work.
- Run required checklist.
- Add notes, labor, parts.
- Create service report.
- See relevant asset history.

### Suggested Home

- Assigned WOs.
- In-progress WOs.
- Due checklists.
- Recently viewed assets.
- Pending sync queue warning.

### Work Order Detail

Must show:

- asset and client context
- status and assignment
- job type/title/description
- scheduled/start/completed data
- checklist action/status
- parts/labor section
- service report section
- internal notes
- sync state
- allowed status actions

## Client / Client Admin Experience

### Primary Jobs

- View fleet.
- See service records/history.
- Submit service request.
- View invoices/documents.
- Use enabled planning/checklist/telemetry workflows.
- Manage team members if approved.

### Suggested Home

Baseline cards:

- Fleet/assets.
- Request Vortice service.
- Recent service reports.
- Invoices/documents.
- Open service requests.

Capability cards:

- Maintenance planning.
- PM/checklists.
- Operational checklists.
- PM parts lists.
- Telemetry.

### Client-Facing Labels

- `Service Requests` for asking Vortice for help.
- `Service Records` or `Reports` for completed reports.
- `Checklist History` for saved checklists.
- Avoid exposing `Work Orders`.

## Client Mechanic Experience

### Primary Jobs

- See client fleet.
- Run enabled maintenance checklists.
- View maintenance and operations history if allowed.
- View PM parts/planning if enabled.
- View telemetry if enabled.
- Surface issues to client/admin, not directly to Vortice WO.

### Must Not Show

- Internal Vortice WOs.
- Internal Vortice notes.
- Invoice generation/editing.
- Asset creation/edit/delete.
- Telemetry pairing controls.

## Operator / Captain Experience

### Primary Jobs

- Pick/resume asset.
- Run operational checklist.
- Record Monitor/Action issues with note/photo.
- See operations history.
- See telemetry if enabled and allowed.

### Must Not Show

- Maintenance checklist tab.
- Internal work orders.
- Service reports.
- Invoices.
- Client admin setup.

## Asset Detail Screen

### Shared Sections

- Header: asset name, type, client, location/status.
- Facts: make/model/year/serial/PIN, notes.
- Current attention: open service requests, alerts, due PM, open staff work where role allows.
- History: checklist history, service reports, documents.
- Actions: role/capability-specific.

### Owner/Admin Asset Detail

Sections:

- Asset facts and edit/delete/archive actions.
- Client ownership.
- Work orders.
- Service requests.
- PM plan/service intervals.
- Checklist history.
- Service reports.
- Invoices/documents.
- Engines/components/hour logs.
- Telemetry device pairing/status.
- Telemetry latest/history.
- Audit/history.

### Client Asset Detail

Sections:

- Asset facts read-only.
- Request service.
- Service history/reports.
- Checklist history.
- Invoices/documents.
- Enabled maintenance planning/checklists/telemetry.
- Asset correction request action.

### Operator Asset Detail

Sections:

- Asset identity.
- Start/resume operations checklist.
- Operations history.
- Telemetry status if enabled.

## Key Screens

### Auth / Invite

- Login.
- Register/accept invite.
- Invite code validation.
- Account/profile settings.

### Client/Admin Setup

- Client list.
- Client detail.
- Capability switchboard.
- Client org/team.
- Invite code management.
- Client team member management.

### Assets

- Asset list/search.
- Asset detail.
- Add asset.
- Edit asset.
- Delete/archive confirmation.
- Asset correction requests.
- Asset type management.
- Engine/component management.
- Hour log.

### Service Requests

- Client request form.
- Client request list/detail.
- Staff request inbox.
- Staff request detail/triage.
- Generate WO from request.
- Decline/request more info.

### Work Orders

- Staff work-order list with filters.
- Create work order.
- Work order detail.
- Assign techs.
- Status transition dialogs.
- Checklist entry.
- Parts/labor.
- Service report action.
- Invoice action.
- Reopen/close.

### Checklists

- Staff WO checklist.
- Client maintenance checklist.
- Operator operations checklist.
- Checklist template picker scoped by asset/type/capability.
- Checklist history list.
- Checklist history detail.
- Template admin/versioning.

### Service Reports

- Report list.
- Report detail.
- New report flow:
  1. Work-order context load.
  2. 5C form.
  3. Signature.
  4. Photos.
  5. Review.
  6. Submit/sync state.
- Report PDF/export later after stable authoring.

### Invoices

- Invoice list.
- Generate from eligible WO.
- Invoice detail/edit.
- PDF/XLSX export.
- Sent/paid/voided actions.
- Client invoice list/detail.

### Telemetry

- Asset telemetry summary.
- Latest readings.
- History/trends.
- Alerts.
- Alert acknowledge/resolve.
- Device pair/replace/unpair owner screen.
- Gateway health/status owner screen.

### Notifications / Reminders

- Notifications list.
- PM reminders/due soon.
- Sync problem list.
- Action/Monitor issue notifications.

## Current Routes That Need V2 Attention

Current app has useful route inventory, but V2 should review:

- Client work-order routes should be removed/blocked if clients do not see internal WOs:
  - `/client/work-orders`
  - `/client/work-orders/:id`
  - `/client/checklists/:workOrderId`
- Tier dashboard routes/classes should be retired or collapsed.
- `/meeting-request` should be dropped unless product need is confirmed.
- Service report authoring should be work-order-scoped and not global/orphan.
- Telemetry should prefer asset routes over engine-rooted routes.

## Screen Acceptance Rules

- Every primary screen must have loading, empty, error, offline, and permission-denied states.
- Every mutating screen must show save/sync outcome.
- Every destructive action must have explicit confirmation and consequence.
- Every role-sensitive route must be guarded at route and data levels.
- Every list count/card must match source list behavior.
- Every disabled-capability route must show clear unavailable state or redirect safely.
