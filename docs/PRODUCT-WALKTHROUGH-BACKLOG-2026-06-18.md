# Product Walkthrough Backlog - 2026-06-18

Purpose: summarize the June 2026 app walkthrough into product requirements, defects, missing flows, and acceptance checks for contributor review.

Scope: `vortice-app-main` product review notes intended for planning, triage, and GitHub issue creation.

Use this document as the review backlog for prioritizing fixes, implementation slices, and issue creation.

## Dev Login / Persona Switchboard

The walkthrough assumes the development login helper is available in the installed build. On the login screen, tap the small hardhat icon to open the dev persona switchboard. That switchboard lists the saved test personas used during the walkthrough and provides quick-login access to each role.

Keep this visible for anyone reproducing the notes on a phone: use the hardhat persona switchboard to jump between owner/admin, client, client mechanic, client operator, and other test personas before validating the matching backlog items. If a role-specific issue is unclear, reproduce it through the same switchboard login path first so the persona, permissions, and assigned assets match the walkthrough context.

## Walkthrough Starting Order

Start with the owner/admin path because it touches the most product surface area and exposes the core object relationships.

1. Owner/admin login and dashboard
2. Owner/admin asset list and asset detail
3. Asset detail hub: work orders, service reports, invoices, checklist history, maintenance plan, photos/documents, client visibility
4. Work order creation and work order detail
5. Service report creation from a work order, including 5C fields, draft/save/submit, signatures/photos/PDF if visible
6. Invoice creation from service/work order history
7. Client login/portal: visible assets, reports, requests, history, invoices
8. Operator/technician path: assigned work, checklists, offline/pending sync behavior
9. Settings/admin/client org/team access
10. Polish pass: confusing labels, dead buttons, empty states, permissions, navigation, slow or awkward flows

## Backlog Items

### A002 - Work order parts/materials should support PM kits and manual line items

Persona: owner/admin/service manager

Flow/screen: create work order -> parts/materials expected

Type: missing

Priority guess: core workflow

Story: As a service manager, I expect parts/materials on a work order to support both manual entry and selectable maintenance kits so a 250-hour PM can be planned with the right filters, oil quantity, and consumables before the job starts.

Acceptance checks:
- When creating a preventative-maintenance work order, the user can freestyle parts/materials notes or add explicit parts line items.
- When an asset has a maintenance interval kit, the user can select that kit from the work order parts/materials step.
- When a kit is selected, the expected parts/materials list is prefilled with item names, quantities, and any available cost fields.
- When the work order is created from a maintenance plan, the matching interval kit carries into the work order.

### A003 - Work order checklist attachment replacement loses earlier photo

Persona: technician/operator

Flow/screen: work order detail -> checklist -> issue photo attachment

Type: broken

Priority guess: core workflow

Story: As a technician, I expect checklist issue attachments to preserve every photo I add so evidence from gallery and camera is not lost during checklist completion.

Acceptance checks:
- Given a checklist item that requires issue documentation, when the user selects a photo from the gallery and then adds a camera photo, both attachments remain visible.
- Given an existing issue attachment, when the user adds another attachment, the new attachment appends instead of replacing the previous one.
- When the checklist is submitted, all retained attachments remain associated with the correct checklist item.

### A004 - Service report section 4 wording should be contingent damage

Persona: technician/service manager

Flow/screen: service report -> 5C/section 4 damage wording

Type: unclear

Priority guess: client-facing

Story: As a technician writing a service report, I expect section 4 to use the shop's preferred language, "contingent damage," so reports avoid the less precise "secondary damage" wording.

Acceptance checks:
- Service report section 4 label uses "Contingent damage" instead of "Secondary damage."
- Any helper text or generated report/PDF wording uses "contingent damage caused by" language if that phrasing still applies.
- Existing saved reports are reviewed for display/export wording impact before migration.

### A005 - Service report should be mandatory for every work order

Persona: owner/admin/service manager

Flow/screen: work order lifecycle -> service report submission/completion

Type: missing

Priority guess: core workflow

Story: As a service manager, I expect every work order to require a service report before it can be fully completed so job history, findings, photos, and signatures are captured consistently.

Acceptance checks:
- A work order cannot move to the final completed/closed state unless a service report exists and has been submitted.
- If a user tries to complete a work order without a service report, the app explains what is missing and routes them to create/finish the report.
- Submitted service reports remain linked from the work order detail and history.

### A006 - Confirm work order status transitions after checklist/report submission

Persona: owner/admin/service manager

Flow/screen: work order detail -> checklist submit -> service report submit -> status

Type: decision

Priority guess: core workflow

Story: As a service manager, I expect work order status changes to follow a clear lifecycle so submitting a checklist or report does not put the order in an unexpected state.

Acceptance checks:
- The intended status lifecycle is documented for draft/assigned/in progress/completed/closed.
- Submitting a checklist changes status only according to that lifecycle.
- Submitting a service report returns the user to the expected work order screen and updates status according to that lifecycle.
- Manual "mark completed" behavior is consistent with the mandatory service report requirement.

### A007 - Invoice generation needs itemized parts, not only a parts total

Persona: owner/admin/service manager

Flow/screen: invoice generation from completed work order -> parts total

Type: missing

Priority guess: core workflow

Story: As a service manager, I expect invoices to support itemized parts lines so customers can see which parts were used instead of only a generic marked-up parts total.

Acceptance checks:
- When generating an invoice from a completed work order, parts can be entered or imported as individual line items.
- Each part line supports at least description/name, quantity, unit cost or sell price, and markup/tax behavior as applicable.
- The invoice export/share output shows the itemized parts list clearly.
- A summary parts total is still calculated from the itemized list.

### A008 - Validate invoice currency conversion for labor rate and exports

Persona: owner/admin/service manager

Flow/screen: invoice generation -> currency/rate conversion -> export

Type: broken

Priority guess: core workflow

Story: As a service manager billing in multiple currencies, I expect labor rate and totals to convert predictably so USD/MXN invoices are mathematically correct before sharing or exporting.

Acceptance checks:
- Given a source currency, target currency, exchange rate, labor hours, and billable rate, the app calculates labor subtotal and invoice total using the documented formula.
- When switching between USD and MXN, the billable rate label/value makes clear whether the input is pre-conversion or post-conversion.
- Exported/shared invoice files match the in-app calculated totals.
- Add a regression test or fixture for at least one USD-to-MXN example using a known exchange rate.

### A009 - Dashboard UI and legacy navigation need cleanup

Persona: owner/admin

Flow/screen: owner dashboard -> clients/list/work codes/navigation

Type: polish

Priority guess: later polish

Story: As an owner/admin, I expect dashboards and navigation labels to match the current workflow so old concepts do not clutter or confuse the product.

Acceptance checks:
- Owner/admin dashboard UI is reviewed for layout, labels, and useful summary information.
- Client/list/work-code dashboard/navigation entries are audited for current product relevance.
- Any legacy "work codes" surface is either removed, renamed, or documented as still required.
- Dashboard cleanup work is split into implementation cards once the intended information architecture is confirmed.

### A010 - Maintenance plan intervals and parts kits are strong but need validation pass

Persona: owner/admin/service manager

Flow/screen: asset detail -> maintenance plan -> interval parts -> generate work order

Type: decision

Priority guess: core workflow

Story: As a service manager, I expect maintenance plan intervals, parts lists, and generated work orders to be validated end to end so the strong existing flow can be trusted for real PM scheduling.

Acceptance checks:
- Maintenance intervals can be created/edited with schedule data and interval-specific parts.
- The "view parts" and interval parts UI correctly persists added parts.
- "Generate work order" from a maintenance plan pre-fills title, asset, PM type/interval, checklist template if available, and expected parts/materials.
- Any calculation or schedule logic is checked against the intended maintenance model before marking ready.

### A011 - Owner/admin needs checklist builder for work order templates

Persona: owner/admin/service manager

Flow/screen: admin/settings or maintenance plan -> checklist templates

Type: missing

Priority guess: demo blocker

Story: As an owner/admin, I expect to build and manage the checklist templates used on work orders so the app can match each company's real PM and repair procedures.

Acceptance checks:
- Owner/admin can create a checklist template with ordered checklist items.
- Checklist items support required/pass-fail/NA behavior and issue documentation requirements where applicable.
- Templates can be attached to maintenance intervals and selected during work order creation.
- Existing work orders preserve the checklist version they were created with if the template changes later.

### A012 - Checklist templates must be editable inside the app

Persona: owner/admin/service manager

Flow/screen: checklist templates -> create/edit/manage checklist

Type: missing

Priority guess: demo blocker

Story: As an owner/admin, I expect checklists to be editable inside the app so each company can maintain its real inspection, PM, and repair procedures without developer intervention.

Acceptance checks:
- Owner/admin can find a checklist-management screen from the app navigation or relevant settings/admin surface.
- Existing checklist templates can be opened, edited, reordered, saved, and reused.
- Checklist edits do not unexpectedly rewrite historical completed checklist records.
- The app makes it clear which templates are active and where they are used.

### A013 - Client invite email fails with 503 function error

Persona: owner/admin

Flow/screen: clients -> invite client -> send invite

Type: broken

Priority guess: demo blocker

Story: As an owner/admin, I expect client invites to send reliably so clients can be brought into the app and connected to their assets, reports, invoices, and shared workflows.

Acceptance checks:
- Given a client name, email, and phone number, when the owner/admin sends an invite, the invite request succeeds without a 503 function error.
- If the invite backend fails, the UI shows a useful error and does not imply the invite was sent.
- The invite creates or links the correct client/contact record needed for client-facing access.
- Add logging or an operator-visible diagnostic path for failed invite function calls.

### A014 - Client invite should use a branded/professional email template

Persona: owner/admin/client contact

Flow/screen: clients -> invite client -> invite email

Type: polish

Priority guess: client-facing

Story: As a client contact receiving an invite, I expect a professional Vortice email instead of a generic Supabase invite so the onboarding experience feels trustworthy and product-owned.

Acceptance checks:
- Invite emails use a Vortice-branded subject, sender identity, and body copy.
- The email explains why the client is being invited and what action they should take.
- The invite link/code still maps to the correct Supabase/auth flow behind the scenes.
- The template is checked in English first, with localization/translations handled deliberately if needed later.

### A015 - Client workflow switchboard needs end-to-end wiring audit

Persona: owner/admin/service manager

Flow/screen: client dashboard/switchboard -> workflow toggles

Type: decision

Priority guess: core workflow

Story: As an owner/admin, I expect workflow toggles on the client switchboard to map to real app behavior so enabling or disabling a workflow actually changes the correct client-visible capability.

Acceptance checks:
- Every switchboard toggle has a named workflow/capability and documented expected effect.
- For each toggle, verify whether it persists, updates backend permissions/settings, and changes the relevant UI or workflow.
- Unknown or partially wired toggles are marked as not ready or hidden until their behavior is implemented.
- Notification behavior after saving/enabling a toggle is documented and made understandable in the UI.

### A016 - PM parts list should be shareable with the client when appropriate

Persona: owner/admin/service manager/client contact

Flow/screen: maintenance plan/work order -> PM parts list -> client visibility

Type: missing

Priority guess: client-facing

Story: As a service manager, I expect PM parts lists to be shareable with clients when appropriate so the customer can see expected materials or kit requirements tied to their maintenance work.

Acceptance checks:
- PM parts lists used on maintenance plans or work orders can be marked client-visible or internal-only.
- Client-facing views show shared PM parts in a readable format without exposing internal-only cost/markup fields unless explicitly intended.
- Work order and maintenance plan flows preserve the link between the interval kit and any client-visible parts list.
- The app defines where shared PM parts appear for the client: portal, report, invoice, or work-order summary.

### A017 - Client workflow switchboard needs explicit save/apply behavior

Persona: owner/admin/service manager

Flow/screen: client dashboard/switchboard -> workflow toggles

Type: broken

Priority guess: core workflow

Story: As an owner/admin, I expect workflow toggles to require an explicit save/apply action so an accidental tap does not immediately disable a whole section of a client's app experience.

Acceptance checks:
- Toggling a workflow changes local pending state first and does not apply destructive/permission-changing behavior until Save/Apply is tapped.
- A Save button is available at the bottom of the switchboard, with clear disabled/enabled state based on unsaved changes.
- Cancel/revert behavior is available or navigating away warns about unsaved changes.
- High-impact toggles either confirm before applying or clearly show what will change for the client.

### A018 - Bottom navigation should be standardized across app personas

Persona: client mechanic/technician, owner/admin, other role views

Flow/screen: bottom navigation / dial across persona dashboards

Type: UX polish

Priority guess: contributor-ready polish

Story: As a user who moves between app roles, I expect the bottom navigation pattern to feel consistent across personas so I do not have to relearn basic navigation in each role.

Acceptance checks:
- Compare bottom navigation in owner/admin, client mechanic, client, and operator views and document intentional differences.
- Shared destinations use consistent iconography, ordering, spacing, labels, and selected-state treatment where practical.
- Persona-specific destinations remain different only where the role genuinely needs different actions.
- The implementation uses shared navigation components/styles instead of role screens drifting independently.

### A019 - Parts log purpose and role ownership needs product decision

Persona: client mechanic/technician, owner/admin/service manager

Flow/screen: mechanic dashboard -> parts log

Type: product decision

Priority guess: needs decision before build

Story: As the product owner, I need the parts log's purpose and ownership defined so contributors know whether to keep, remove, or redesign it.

Acceptance checks:
- Decide whether the parts log is required for the technician workflow, owner invoice workflow, inventory workflow, or none of the above.
- Define whether parts logged by a technician are internal-only, owner-reviewable, client-visible, invoice-ready, or inventory-impacting.
- Document where logged parts should appear after submission: work order detail, owner invoice builder, service report, inventory/parts history, or a separate parts log screen.
- If the feature is not needed, remove or hide it from the mechanic UI rather than leaving an unclear destination.

### A020 - Online checklist submission incorrectly lands in pending sync

Persona: client mechanic/technician

Flow/screen: mechanic work order -> checklist submit

Type: broken

Priority guess: core workflow

Story: As a technician with connectivity, I expect checklist submission to save immediately instead of going into pending sync when the device is online.

Acceptance checks:
- Reproduce checklist submission while connected to Wi-Fi and confirm whether the app reports pending sync.
- Verify online/offline detection, Supabase write path, sync queue state, and error handling for checklist submissions.
- Connected successful submissions show a saved/submitted state, not pending sync.
- Offline submissions may queue, but the UI clearly distinguishes intentional offline queueing from failed online saves.

### A021 - Technician hours must attach to owner-visible work order and invoice flow

Persona: client mechanic/technician, owner/admin/service manager

Flow/screen: mechanic work order -> log hours -> owner work order/invoice

Type: workflow validation

Priority guess: core workflow

Story: As an owner/admin, I expect technician hours logged against a work order to appear on the same owner-visible work order and be available for invoicing.

Acceptance checks:
- Technician can log hours against an assigned work order.
- Logged hours are associated with the correct work order ID, technician/user, date, and notes if applicable.
- Owner/admin work-order detail shows the logged hours in a useful review format.
- Invoice generation can pull approved billable hours from the work order without manual re-entry.
- Non-billable/internal time handling is defined if needed.

### A022 - Parts logged by technician must flow to owner review and invoicing

Persona: client mechanic/technician, owner/admin/service manager

Flow/screen: mechanic parts log -> owner work order/invoice

Type: workflow validation

Priority guess: core workflow

Story: As an owner/admin, I expect parts logged by a technician to be reviewable and invoiceable from the linked work order.

Acceptance checks:
- Parts log entries require a clear work-order link when they are intended to support billing.
- Owner/admin can see technician-logged parts on the linked work order.
- Owner/admin can edit, approve, remove, or convert logged parts into invoice line items.
- The app defines whether technician-entered costs are estimated, actual cost, sale price, or owner-only metadata.
- Client-facing invoice/report output uses owner-approved values, not raw technician input unless explicitly approved.

### A023 - Parts log linked-work-order dropdown overflows by hundreds of pixels

Persona: client mechanic/technician

Flow/screen: mechanic parts log -> link to work order dropdown

Type: broken UI

Priority guess: contributor-ready bug

Story: As a technician logging parts, I expect the linked-work-order dropdown to fit on screen without layout overflow.

Acceptance checks:
- Reproduce the dropdown overflow on the mechanic parts log screen.
- Long work-order labels wrap, truncate, or constrain correctly within the menu width.
- Dropdown/list height and width respect mobile viewport constraints.
- No Flutter overflow warning remains when selecting a linked work order.

### A024 - Technician parts price should not be mandatory and owner must be able to price/edit parts

Persona: client mechanic/technician, owner/admin/service manager

Flow/screen: mechanic parts log -> unit cost / owner invoice editing

Type: workflow/permissions

Priority guess: core workflow

Story: As a technician, I should be able to log parts used without being forced to enter pricing, and as an owner/admin I should control final part pricing before invoicing.

Acceptance checks:
- Technician parts logging allows quantity/description/work-order link without mandatory unit cost unless the business rule explicitly requires it.
- If technicians may enter cost, label clarifies whether it is unit cost, estimated cost, sale price, or internal note.
- Owner/admin can edit logged parts and pricing before the item reaches an invoice.
- Invoice output uses owner-approved pricing.

### A025 - Parts log submit fails against missing notes column/schema mismatch

Persona: client mechanic/technician

Flow/screen: mechanic parts log -> submit logged part

Type: broken

Priority guess: core workflow

Story: As a technician, I expect a parts log entry to submit successfully without a backend schema error.

Acceptance checks:
- Reproduce the parts log submission failure after filling required fields.
- Identify the exact table/write path and expected schema for parts log entries.
- Align client payload fields with the database schema or add the intended missing column through a reviewed migration.
- Error handling shows a useful message if submission fails.
- Add regression coverage or a smoke check for parts log creation.

### A026 - Client dashboard scheduled maintenance/recent service cards need real wiring and UI pass

Persona: client contact/client operator

Flow/screen: client dashboard -> scheduled maintenance / recent service summary

Type: broken/unclear

Priority guess: client-facing

Story: As a client, I expect scheduled-maintenance and recent-service dashboard cards to reflect real asset history so the dashboard is trustworthy instead of looking like placeholder content.

Acceptance checks:
- Client dashboard cards pull from the same asset/work-order/service-report/checklist data used elsewhere in the app.
- If service was performed in the last 30 days, the recent-service card reflects that instead of showing no recent service.
- Scheduled-maintenance copy, spacing, and card layout are reviewed for client readability.
- Empty states are accurate and explain whether there is no data, no client-visible data, or a wiring problem.

### A027 - Client request-service flow is strong and should be preserved while validating owner handoff

Persona: client contact, owner/admin/service manager

Flow/screen: client dashboard -> request service -> owner service requests -> create work order

Type: workflow validation

Priority guess: client-facing

Story: As a client, I expect request-service submission with hours, notes, and pictures to become an owner-reviewable service request that can be accepted into a work order without retyping the useful details.

Acceptance checks:
- Client can submit a service request with service type, current hours, notes/contact details, and photos.
- Owner/admin sees the service request with the submitted notes/contact/photo context intact.
- Owner/admin can accept the request and create a work order from it.
- After work-order creation, the request leaves the pending/request queue and the new work order appears in the correct owner/client views.
- Preserve the current clean handoff UX where it is already working.

### A028 - Client should get acknowledgment when service request is accepted

Persona: client contact

Flow/screen: client service request -> owner acceptance -> client notification/status

Type: missing

Priority guess: client-facing

Story: As a client, I expect to be notified when my service request has been acknowledged or accepted so I know the shop has seen it and started handling it.

Acceptance checks:
- When owner/admin accepts a client service request, the client receives an in-app notification, email, or visible status update according to the chosen notification model.
- The client request detail/history shows an acknowledged/accepted state with date/time.
- The accepted request links to the resulting work order if that is intended to be client-visible.
- Notification wording is client-friendly and does not expose internal-only workflow state.

### A029 - Client service reports view should show completed services for the client's assets

Persona: client contact

Flow/screen: client portal -> service reports

Type: broken/missing

Priority guess: client-facing

Story: As a client, I expect to view service reports for work performed on my assets so I have a usable maintenance and repair record.

Acceptance checks:
- Client service reports list shows reports attached to the client's visible assets and work orders.
- Reports generated from the current walkthrough/test service appear once submitted and marked client-visible.
- Service report list items show readable asset, date, service type, and status metadata.
- Empty states distinguish no reports from reports hidden by permissions.

### A030 - Client visible assets should be scoped to that client's assets only

Persona: client contact

Flow/screen: client portal -> assets / asset summary

Type: workflow validation

Priority guess: client-facing

Story: As a client, I expect the app to show only assets assigned to me or my organization so I do not see other customers' equipment.

Acceptance checks:
- Client asset lists are filtered by client/org assignment and permissions.
- Client cannot open assets that belong to another client through list, deep link, search, invoice, report, or dashboard shortcuts.
- Owner/admin can intentionally assign or remove client visibility for an asset.
- Test data with multiple clients confirms isolation.

### A031 - Client can run assigned checklists but must not edit checklist templates

Persona: client contact/client operator

Flow/screen: client asset -> start checklist / checklist execution

Type: permissions

Priority guess: client-facing

Story: As a client user, I expect to complete assigned checklists but not modify the checklist template itself so operational records are captured without letting clients alter company-controlled procedures.

Acceptance checks:
- Client/operator can start and submit checklists they are allowed to complete.
- Client/operator cannot edit checklist template structure, labels, required fields, or pass/fail rules.
- The UI separates completing a checklist from template editing/admin actions.
- Leaving and returning to an in-progress checklist preserves progress where intended.

### A032 - Asset summary maintenance history needs source clarity and accurate rollup

Persona: client contact, owner/admin/service manager

Flow/screen: client asset summary -> last maintenance / due-overdue / history rollup

Type: unclear/workflow validation

Priority guess: client-facing

Story: As a client, I expect asset summary maintenance facts to clearly explain what happened and where the data came from so last maintenance, due/overdue state, and checklist/report history are meaningful.

Acceptance checks:
- Last-maintenance date/interval reflects the authoritative submitted service report, completed work order, or completed maintenance checklist according to documented rules.
- Due/overdue indicators use the same maintenance-plan calculations as owner/admin views.
- The summary links to the underlying checklist, service report, or work order evidence.
- Labels clarify whether a record came from a maintenance checklist, operations checklist, service report, or manual entry.

### A033 - Client should view service reports but not create service reports

Persona: client contact/client operator

Flow/screen: client asset -> service reports

Type: permissions

Priority guess: client-facing

Story: As a client, I expect to read service reports attached to my assets, but not create official service reports, so the record remains controlled by the service provider.

Acceptance checks:
- Client role can view submitted client-visible service reports for assigned assets.
- Client role has no create/edit/submit service report action.
- Any report attachments/photos/signatures intended for client visibility are available from the read-only view.
- Attempting to access service-report creation routes as a client is blocked.

### A034 - Checklist history should show human names instead of raw user codes

Persona: client contact, owner/admin/service manager

Flow/screen: client asset -> checklist history -> checklist detail

Type: polish

Priority guess: client-facing polish

Story: As a client reviewing checklist history, I expect to see who completed a checklist by readable name instead of an internal user code.

Acceptance checks:
- Checklist history detail resolves user IDs/codes to display names where permission allows.
- If a user profile is missing, fallback text is readable and not a raw UUID/code unless necessary for support diagnostics.
- Owner/admin can still access diagnostic IDs somewhere appropriate if needed.
- The display is consistent across operations and maintenance checklist histories.

### A035 - Client checklist history should expose checklist notes and photos where allowed

Persona: client contact/client operator

Flow/screen: client asset -> checklist history -> checklist detail/photos

Type: missing/workflow validation

Priority guess: client-facing

Story: As a client, I expect checklist history to show pass/fail/action notes and attached photos so checklist records become useful documentation for the asset.

Acceptance checks:
- Checklist detail shows completed items, pass/fail/action states, and notes in a readable format.
- Photos attached to checklist items can be viewed by the client when those photos are client-visible.
- Operations checklist and maintenance checklist history both follow the same attachment visibility rules.
- Empty photo/note states are clear without looking broken.

### A036 - Preserve the operations-vs-maintenance checklist separation

Persona: client contact/client operator, owner/admin/service manager

Flow/screen: client asset -> checklist history -> operations and maintenance checklist categories

Type: preserve/validate

Priority guess: client-facing

Story: As a client, I expect operations checklists and maintenance checklists to be separated so pre-start/operator records are not mixed with maintenance history.

Acceptance checks:
- Checklist history clearly separates operations checklists from maintenance checklists.
- Operations checklist records are labeled as operator/pre-start style records.
- Maintenance checklist records are labeled as maintenance/service history records.
- Any filters or tabs preserve this distinction on mobile.

### A037 - Client service/maintenance hub layout is promising but needs validation and terminology cleanup

Persona: client contact

Flow/screen: client asset -> maintenance/service central

Type: polish/workflow validation

Priority guess: client-facing

Story: As a client, I expect the asset maintenance hub to show last known hours, remaining interval, parts, reports, invoices, and checklists in a polished, accurate summary.

Acceptance checks:
- The hub displays last known hours and interval remaining using authoritative asset/maintenance data.
- Parts recorded for the asset/interval are viewable where intended.
- Invoices, service reports, and checklists link to the correct scoped records.
- Labels use consistent client-facing terms: service, maintenance, checklist, report, invoice, and parts.
- Preserve the current useful layout while fixing wiring and confusing labels.

### A038 - Client invoices should be scoped and organized by client-visible assets/work orders

Persona: client contact

Flow/screen: client portal -> invoices

Type: workflow validation

Priority guess: client-facing

Story: As a client, I expect invoices to show only invoices for my assets/work orders and be organized enough that test-heavy or active accounts do not become confusing.

Acceptance checks:
- Client invoice list filters by client/org visibility and assigned assets/work orders.
- Invoice list rows show readable asset, work order/service reference, date, status, and amount.
- If many invoices exist for one test asset, the UI remains usable with search/filter/sort or grouping.
- Client cannot access invoices for other clients through list or deep link.

### A039 - Client team section needs product definition, not just info dump

Persona: client contact/client admin

Flow/screen: client portal -> my team

Type: product decision

Priority guess: core workflow/client-facing

Story: As a client admin, I expect the team area to tell me who has access and what they have done, not feel like an unfinished alternate app section.

Acceptance checks:
- Define the purpose of the client team section: invite users, manage operators, view checklist activity, assign asset access, or some combination.
- Team list shows invited/active users, role/status, contact info, and last activity where useful.
- Client admin can see checklist/activity history tied to team members if that is part of the product model.
- Remove or hide placeholder/info-dump surfaces until the section has a clear client workflow.

### A040 - Client invite-team-member flow needs account invite/code behavior defined and implemented

Persona: client contact/client admin, invited team member

Flow/screen: client portal -> my team -> invite team member

Type: missing/workflow validation

Priority guess: core workflow/client-facing

Story: As a client admin, I expect to invite a team member with a code/link so they can create an account and access the right client assets and checklists.

Acceptance checks:
- Invite team member flow collects the required contact information and role/access level.
- The app sends a branded invite email/link/code or otherwise clearly communicates the invite path.
- Invited users can create an account and land in the correct client/org context.
- Owner/admin and client admin permissions for team invitations are defined.
- Failed invite sends show useful errors and do not create confusing half-invited users.

### A041 - Client mechanic login cannot access the core checklist workflow

Persona: client mechanic

Flow/screen: mechanic login -> checklists

Type: blocker/workflow gap

Priority guess: core workflow

Story: As a client mechanic, I need to start, view, and complete assigned checklists so I can document maintenance work from my own login.

Acceptance checks:
- Client mechanic can see the checklists they are allowed to run for assigned client assets.
- Client mechanic can start a checklist from the correct asset/workflow context.
- Client mechanic can view checklist details before and after submission.
- Completed checklist submissions attach to the correct asset/client/work order context where applicable.
- Permission failures explain what access is missing instead of leaving the mechanic with no usable workflow.

### A042 - Client mechanic needs a strong notes workflow without full service-report authority

Persona: client mechanic

Flow/screen: mechanic login -> checklist/service notes

Type: missing/workflow design

Priority guess: core workflow

Story: As a client mechanic, I need a clear place to leave useful maintenance notes, close to a lightweight service report, without being given the full service-report creation workflow.

Acceptance checks:
- Client mechanic has an obvious notes entry point tied to the asset, checklist, work order, or maintenance event.
- Notes support enough detail to document work performed, observations, concerns, and follow-up needs.
- Notes are visible to the owner/admin in the appropriate review and service-history surfaces.
- Notes are visible to the client where the product allows client-facing maintenance documentation.
- The notes flow is distinct from full service-report creation if client mechanics should not create official service reports.

### A043 - Client mechanic parts logging may be wrong-scope and needs role decision

Persona: client mechanic, owner mechanic, owner/admin

Flow/screen: mechanic login -> parts list / parts used

Type: product decision/workflow validation

Priority guess: important

Story: As the product owner, we need to decide whether client mechanics should log used parts, while ensuring owner mechanics can log parts for invoicing.

Acceptance checks:
- Define whether client mechanics can log parts used, view parts lists only, or have no parts workflow.
- Owner mechanics can log parts used in a way that supports owner review and invoicing.
- If client mechanics can log parts, their entries are clearly marked as client-supplied/requested/reported and require owner review before invoicing.
- If client mechanics cannot log parts, the UI hides disabled/irrelevant parts controls instead of presenting broken actions.
- Parts terminology distinguishes parts list, parts used, invoiceable parts, and client-provided parts where needed.

### A044 - Client operator asset visibility must be tied to correct client/org membership

Persona: client operator, client admin, owner/admin

Flow/screen: client operator login -> checklists -> asset selector

Type: workflow validation/permissions

Priority guess: core workflow/client-facing

Story: As a client operator, I expect to see only the assets for the client/org I belong to so I cannot accidentally inspect or submit records against another customer's equipment.

Acceptance checks:
- Client operator asset visibility is derived from the correct client/org membership model.
- Asset selectors show only assets owned by or assigned to that client/org.
- Client operators cannot access other clients' assets through search, deep links, checklist routes, or stale cached records.
- Owner/admin can verify which client/org and assets an operator is attached to.
- Empty or unassigned states explain that no assets are assigned instead of implying the app is broken.

### A045 - Preserve working pre-op checklist header prefill for client operators

Persona: client operator

Flow/screen: client operator -> pre-op checklist -> checklist header

Type: preserve/validate

Priority guess: core workflow

Story: As a client operator, I expect the checklist header to prefill the correct asset/user/context data so pre-op submissions are fast and filed against the right equipment.

Acceptance checks:
- Pre-op checklist header pre-fills asset, client/org, operator, date/time, and any known machine context required by the template.
- The prefilled values match the selected asset and logged-in operator.
- Editable header fields remain clear where manual correction is allowed.
- Submitted checklist history retains the same header context shown during completion.

### A046 - Telemetry-backed hour fields should auto-fill last known hours with manual override

Persona: client operator, technician, owner/admin

Flow/screen: checklist/service/work-order hour entry across app

Type: missing/workflow design

Priority guess: core workflow/telemetry

Story: As a user entering machine hours, I expect telemetry-enabled assets to prefill last known hours while still allowing manual correction so records are faster without trapping bad telemetry values.

Acceptance checks:
- For telemetry-enabled assets, current-hours fields prefill from the authoritative last-known telemetry or asset-hour source.
- Users can manually change the prefilled value before submission.
- The UI makes clear whether the value came from telemetry/last known hours or manual entry.
- Manual overrides are stored with enough metadata to audit source/value/user/time if needed.
- This rule is reviewed for all app surfaces that ask for current hours, not only the client-operator pre-op checklist.

### A047 - Checklist action items with photos must notify or surface to responsible owner/admin

Persona: client operator, owner/admin, client admin

Flow/screen: client operator checklist -> action item/photo -> owner/admin review

Type: workflow validation/missing

Priority guess: core workflow/client-facing

Story: As an owner/admin, I need checklist action items and attached photos from operators to surface in the right review/notification flow so problems found during pre-op checks are not buried in history.

Acceptance checks:
- When a client operator marks a checklist item as action-required and attaches a photo, the saved record preserves the action state, note, and photo.
- The action item is visible to the responsible owner/admin or client admin according to the product permission model.
- The app defines whether action items create notifications, review queue entries, maintenance flags, service requests, or work-order prompts.
- Notifications/review entries link back to the asset and checklist detail.
- Failed notification/surfacing behavior does not block saving the checklist record unless explicitly designed.

### A048 - Client operator checklist submit fails online and needs offline-sync policy cleanup

Persona: client operator

Flow/screen: client operator -> pre-op checklist -> complete checklist

Type: broken/offline-sync

Priority guess: demo blocker/core workflow

Story: As a client operator, I expect checklist completion to submit or queue predictably so a completed pre-op check is not lost behind a misleading reconnect error.

Acceptance checks:
- When online, completing a client-operator checklist submits successfully and writes the expected saved checklist/history record.
- When offline, the app clearly saves the checklist to a pending-sync queue with visible status and retry behavior.
- The error message distinguishes offline/no connection, server validation failure, permission failure, and local queue failure.
- Pending checklist records survive app navigation/restart until synced or explicitly discarded.
- Offline checklist behavior is aligned across client operator, client mechanic, technician, and owner/maintenance checklist flows.

### A049 - Flag-for-maintenance flow should support photos and clear downstream routing

Persona: client operator, owner/admin, maintenance reviewer

Flow/screen: client operator -> flag for maintenance

Type: missing/workflow validation

Priority guess: core workflow

Story: As a client operator, I expect flag-for-maintenance to support issue description and photos so maintenance reviewers receive enough evidence to act.

Acceptance checks:
- Flag-for-maintenance accepts a clear issue description and one or more photos.
- Submitted flags confirm success and attach to the correct asset/client/operator context.
- Owner/admin or the responsible maintenance reviewer can see the flag in a defined queue, notification, asset history, or service-request/work-order path.
- The product defines whether a maintenance flag becomes a service request, maintenance action item, work-order draft, or simple note.
- Empty/photo upload failure states are handled without losing the typed issue description.
