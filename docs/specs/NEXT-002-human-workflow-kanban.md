# NEXT-002 — Human-centered workflow consolidation Kanban

Status: Build 29 scope delivered; NEXT-003 follow-ups delivered in Build 33.
Implementation requirements below are retained as
the accepted specification; the status groups here own remaining work.

## Current board

- **Native S24 demo paths verified:** provider creation/assignment, checklist,
  report/photo recovery, return/correction, approval, customer visibility and
  issued invoice; modern account switching with collapsed older accounts.
  See `NEXT-003-workflow-follow-through.md` for the exact Build 32/33 evidence.
- **Further phone checks:** remaining role, recurrence, source-page, parts,
  catalog, notification and access-revocation cases in the matrix below.
  .18 also passed five connected demo-role checks.
- **Deferred setup:** .01 email/SMS providers, at Garrett's request.
- **Needs external verification:** .20 personal agent host connection;
  .23 live API quality, latency and usage measurements. The managed agent is an
  exploration, not a delivered production chat feature.
- **Completed follow-up:** all five improvements in
  `NEXT-003-workflow-follow-through.md`, represented in `BACKLOG.md`.
- **Computer acceptance and usability:** `NEXT-004-usability-audit.md` records
  the connected fault/repair and PM-parts journeys, five modern account switches,
  recurring-work/membership contracts and visual checks at normal, desktop and
  enlarged text sizes. Small display and lifecycle defects were corrected;
  larger usability changes remain suggestions. These checks do not close the
  separate phone acceptance items above.

Native-phone evidence is recorded separately from unit tests and APK delivery;
the demo journey does not imply Garrett accepted every role or workflow.

Accepted organization membership and role semantics:
`../decisions/0016-organization-membership-access.md`.

Garrett assembled this board while testing the app on September 10-11, 2026.
On September 12 he authorized reconciliation, autonomous implementation,
review, commits, pushes and necessary Next Supabase migrations. NEXT-002 is
now active in `BACKLOG.md`; bounded slices and actual evidence are below.
Account/data clearing and production identity/signing remain separate decisions.

## Execution and dependencies

Batch 1 delivery: `NEXT-002-workflow-batch-1.md` records its original checks.
Whole-board scope is below. Implementation does not replace physical acceptance.

| Card | Implemented scope | Remaining acceptance |
| --- | --- | --- |
| .01 | Email/phone code entry, recovery and organization routing; truthful unavailable state in this build | Garrett deferred email/SMS provider setup and real delivery; see `NEXT-002-code-sign-in-setup.md` |
| .02 | Common work hub, calendar views, search, matching filters and preserved booking context | Native cached Work and Completed discovery passed; calendar/other-role checks remain |
| .03 | Asset/fault/plan/request/inspection source context and frozen work procedures | Native provider/asset/frozen checklist journey passed; other source entries remain |
| .04 | Automatic cycle generation, no automatic booking/assignment, checked once-only advancement | Hourly scheduler verified active; physical phone journey |
| .05 | Explicit operator asset/draft choice and frozen attached checklist progress | Native provider checklist/evidence passed; operator asset/draft journey remains |
| .06 | Exact manual page links, adjustable state sequence and offline source-page cache | Physical offline source-page acceptance |
| .07 | Common service-report language, retained returned work and approved publication boundary | Native return/correction/publication and pre/post-approval customer views passed |
| .08 | Work-contained progress, missing requirements, evidence, report and labour | Native provider timer/checklist/report/photo journey passed; other role cases remain |
| .09 | Linked fault-to-work, explicit repair verification and availability decision | Physical phone acceptance |
| .10 | Relationship-scoped request acceptance, linked work, approved report and invoice | Native linked demo job through approved report and issued zero-dollar invoice passed; other relationship cases remain |
| .11 | Shared lifecycle labels; actual bookings distinguished from assignment/due dates | Physical phone acceptance |
| .12 | Home exceptions use domain filters and matching result counts; Mine preserved | Physical phone acceptance |
| .13 | Canonical asset context, current work, meters, custody, inspections and immutable history | Physical phone acceptance |
| .14 | Needed/reserved/ordered/received/used/returned parts in the work context | Physical parts workflow acceptance |
| .15 | Original hours/km/mi in work, reports and history; distance display preference | Native 62000 km preserved through approved report; other units/preferences remain |
| .16 | Six selected land types, stable catalog IDs, bundled drawings and searchable Add/Edit | Physical catalog acceptance |
| .17 | Automatic foreground offline readiness, cached work/source pages, truthful queue states and online action gates | Native Wi-Fi/data-off force-stop, cached Work, unsent photo preview and reconnect/submit passed; source pages and other field paths remain |
| .18 | Additive membership/permissions, invitations, revocation, company relationships and scoped provider work | Five live demo role checks passed; physical acceptance remains |
| .19 | Checklist issue details, fault handoff and contextual discussions with company boundaries | Physical evidence/notification acceptance |
| .20 | Guided scoped MCP setup, real backend grant check, reviewed proposals and narrow audited tools | A real user-selected agent host connection |
| .21 | Internal account switcher and five verified modern demo identities alongside existing accounts | Build 33 installed; native fleet/service-owner switching and collapsed older accounts passed; other role journeys follow their cards |
| .22 | Company announcements, unread state, attachments and notifications | Physical delivery/tap acceptance |
| .23 | Managed-agent architecture and executed budget/dispatcher spike | Live API quality/latency/usage measurements need an API credential; see `NEXT-002-managed-agent-exploration.md` |

- On September 12 Garrett requested execution of the whole board and APK
  delivery to S24 Downloads. Build 29 is delivered and checksum-verified;
  `NEXT-002-whole-board-delivery.md` records verification and remaining acceptance.
- .18 organization membership precedes .01 owner onboarding. Legacy `owner`
  grants provider/platform authority, not the new Company Owner role. Migrate
  membership, invitations, routes and backend access together; do not implement
  new semantics by relabeling or widening existing roles.
- .03/.05/.07 source and completion links precede .04 recurring generation;
  .04's inspection-work bridge precedes removal of the renewal UI under .13.
  Keep renewal available until its replacement preserves certificate history
  and atomically approves the linked work.
- .15 flexible meters precedes kilometre/mile-based automatic recurrence.
- .07 report naming can converge while internal snapshots and provider reports
  retain separate privacy/billing rules. Every report belongs to one order;
  this does not require every order to have a report or limit it to one report.
- .21 physical phone acceptance remains distinct from automated/rendered tests.

Build 27 integration supersedes earlier pending-deployment statements for
NOW-023/024. Recurring generation changes decision 0015's no-auto-create boundary
only when .04 is implemented; appointment selection, checked approval,
included-service exclusion and once-only advancement remain. The older
unselected inventory remains historical reference rather than active priority.

This board takes priority over the older unselected feature inventory retained
under NOW-006. That inventory remains reference material. Do not add or select
more feature expansion until Garrett revisits it after the existing workflows
on this board have been addressed.

## Product rules

- Work orders are where planned and corrective work happens.
- A checklist attached to a work order defines the required steps.
- A service report attached to a work order records what was found and done.
- Faults, service requests, inspections and maintenance plans create or link to
  work orders instead of becoming competing work systems.
- Shared screens serve client and provider teams; permissions control their
  data and available actions.
- A client/customer is a relationship between organizations, not a person's
  permanent profile type. People receive roles within their organization.
- Each state exposes one obvious next action. Secondary choices remain
  available without competing with it.
- A normal pre-operation check may stand alone when it passes. A failed result
  creates a linked fault and corrective-work path.

## P1 — Core workflows

### NEXT-002.01 — Simple email or phone onboarding

Let a person choose email or phone, receive and enter a verification code, and
land in the correct app context.

- A new unaffiliated person creates a company workspace and becomes its Company
  Owner with full access to that organization.
- An invited person joins the inviting company with the roles and capabilities
  chosen on the invitation.
- Existing users return to their last active organization. The data model should
  allow future membership in more than one organization without duplicating the
  person's identity.
- After verification, collect only the minimum missing identity/company details
  and open the useful dashboard instead of presenting a second registration
  maze.
- Cover expired codes, resend timing, contact correction, invite redemption and
  recovery. Verify real email and SMS delivery separately from automated checks.

The default self-signup receives Company Owner access because that person is
creating the company. Invited employees do not all receive owner access; the
inviter selects the least access needed for their work.

### NEXT-002.02 — One Work Orders hub

Make Planning the common place to view, create, assign, schedule and reschedule
work orders. Provide List plus Day, Week and useful Month calendar views. Show
actual scheduled work in Month, keep unscheduled work visible, distinguish due
dates from booked times, and preserve selected date and filters after opening a
record. Include Mine, Open, Unassigned, Unscheduled, Needs review and Completed
filters plus asset, component, worker, status and work-type search. Remove
competing Planning, Work Orders and Service Work Orders discovery paths while
retaining role and billing rules.

Bring work-related Fleet decisions into this hub as saved filters or summary
chips: Work overdue, Awaiting review, Waiting for parts, Waiting for people and
Other blocked work. Selecting a count opens the matching filtered work orders;
it must not open another competing work list. Counts and results use the same
role scope and status definitions.

### NEXT-002.03 — Context-aware work-order creation

Creating work from an asset, fault, inspection, maintenance plan or service
request carries forward the known asset/component, description, work type,
priority, due date, source relationship, checklist, procedure, evidence and
parts requirements. Do not make the user reselect or retype existing context.

### NEXT-002.04 — Automatically generate recurring work

Maintenance schedules and inspection requirements generate one work order per
cycle with the correct asset, component, due date, procedure, checklist and
evidence requirements. Generation does not choose an appointment or worker;
managers schedule and assign through the Work Orders hub. Remove the parallel
Submit renewal journey. Approval advances the maintenance or inspection target
once, and retries, returned work or reopened work cannot advance it twice. Due
reminders open the work or plan, with acknowledgment as a secondary notification
action. Preserve the current certificate while replacement work awaits review.

### NEXT-002.05 — Attached checklist lifecycle

Select or generate the checklist with the work order, freeze its published
version, show progress on the order, and preserve answers, readings, notes,
signatures and photos. Failed steps can create a fault or follow-up work order.
Completing an unrelated standalone checklist must not appear to complete
scheduled maintenance.

For operator checklist entry:

- The generic Home **Start checklist** action first shows every active asset the
  operator is authorized to use, with search when the list is long.
- After the operator selects an asset, show only published pre-operation
  checklists that match it. Continue directly when there is one clear match;
  let the operator choose when several apply.
- Tapping an assigned checklist may continue directly because its asset and
  checklist are already explicit. Starting from an asset card may preselect
  that asset.
- If an unfinished local draft exists, show **Resume [asset] checklist** and
  **Start another checklist** instead of silently reopening the saved asset.
  Starting another checklist must preserve or deliberately discard the draft;
  it must not overwrite it accidentally.
- A checklist run always displays the selected asset prominently before any
  answers are recorded, preventing results from being saved against the wrong
  equipment.

Acceptance: from the operator Home shown with multiple fleet assets, generic
Start checklist opens asset selection rather than the Ellicott 460SL. Selecting
another asset exposes its matching checklist. An actual unfinished Ellicott
draft is offered explicitly and remains recoverable after choosing Start
another checklist.

### NEXT-002.06 — Manual-linked, state-based checklists

Allow a checklist author to attach the exact manual and page or section to a
step. During execution, `View procedure — Manual p. 42` opens the referenced
page without losing progress. Cache assigned source pages for offline work,
freeze the reference with the published checklist/work-order snapshot, and
preserve manual permissions.

Offer an adjustable sequence based on equipment state: walk-around, machine
stopped, before starting, start-up, running checks, shutdown, isolated/locked
out, maintenance, controlled restart and post-maintenance verification.
Pre-operation checks normally progress from stopped checks to start-up and
running checks. PMs perform required running diagnostics before shutdown,
isolate for service, and perform defined verification after restart. The
approved equipment procedure controls the actual sequence.

### NEXT-002.07 — Work-order and service-report lifecycle

Keep both concepts. The work order defines what should happen, who owns it,
when it is due/booked, and its parts/procedures. Its attached service report
records findings, performed work, checklist results, measurements, photos,
labour, parts and completion notes. Every service report belongs to one work
order. Use Create, Continue, Submit for review, Review and View service report
actions according to state. Returned work opens at the reviewer's comment with
previous input intact. Approved provider reports can support customer
publication and invoicing. Remove Work report and Maintenance report as
separate user-facing concepts while retaining historical records.

### NEXT-002.08 — Complete work inside the work order

Use `Start work → Record work → Complete checklist/service report → Submit for
review → Review work`. Keep the labour timer visible, show missing requirements
beside their fields, and keep parts, evidence, checklist progress and the
service report together. Approved completion remains discoverable in the
work-order history.

### NEXT-002.09 — Connect faults through repair and availability

Use `Create work order → Open work order → Verify repair → Review availability`.
Replace Plan repair with Create/Open work order and keep Link existing work
order secondary. Work-order approval does not automatically resolve the fault
or return the asset to service. Repair verification and the availability
decision remain explicit and traceable.

### NEXT-002.10 — Connect service requests through completion

Accepting a request creates or links a work order and exposes an Open work
order action. Staff and customers use understandable, consistent progress
language. Customers see useful progress and published deliverables without
private staff details. Provider work continues contextually to its service
report and invoice.

### NEXT-002.11 — One status language and one next action

Use a coherent lifecycle across Home, Assets, Notifications, Calendar,
Requests and Work Orders: Unassigned, Scheduled, In progress, Blocked, Awaiting
review, Returned and Completed. Each state has one primary action. Put secondary
actions in a labeled menu. Notifications use the same language and open the
correct record for every permitted role.

## P2 — Supporting workflows and product coverage

### NEXT-002.12 — Home shows each person's next real task

Managers see urgent exceptions, assignment and review; mechanics see running
and assigned work; operators see due and unfinished checks; customers see fleet
status, request progress, reports and invoices. `View all my work` preserves
the Mine filter. Empty states explain the person's available next step.

Retire Fleet decisions as a standalone workflow and navigation destination,
while preserving its useful attention query and counts. Place each signal with
the subject a person can act on:

- Plan setup needed opens the affected assets' maintenance setup in the Asset
  workspace.
- Availability unknown and Unavailable assets open the corresponding Assets
  status filters.
- Urgent faults opens the urgent Faults filter.
- Service overdue and approaching-service signals open the affected asset,
  maintenance requirement or generated work order as appropriate.
- Work overdue, Awaiting review, Waiting for parts, Waiting for people and
  Other blocked work open the corresponding Work Orders hub filters.

Manager Home may show the top three urgent exceptions, each linking to its
prefiltered destination, with View all opening the same scoped result. Operator
Home shows only contextual safety, availability and inspection information for
the selected or assigned asset; operators do not receive a fleet-wide decision
dashboard.

Acceptance: every former Fleet decisions tile reaches an actionable, filtered
domain screen; Home and destination counts agree for the same role; returning
from a record preserves the filter; and no standalone Fleet decisions entry is
needed to find or resolve the exception.

### NEXT-002.13 — One understandable asset workspace

Keep asset identity, condition, location/responsibility, readings, current and
upcoming work, components, maintenance setup, inspections, parts/plans, past
work, reports and documents in one understandable asset context. Consolidate
the overlapping Assets, Assets & plans, Asset maintenance and
Work/components/plans paths. Direct links open the source record without making
the user reselect the asset.

Put inspection status and history in this asset context rather than keeping a
standalone Fleet inspections destination. The asset summary shows the current
inspection/certificate state, next due date and any active inspection work
order. **Schedule/Open inspection work** is the primary action when attention is
needed. Completed, replaced, rejected and expired inspection versions appear in
Asset history under an Inspections filter, with their evidence, procedure,
review decision and actor preserved. Do not flatten or discard the immutable
inspection versions already required by decision 0007.

Managers find fleet-wide inspection attention through Assets filters such as
Inspection due soon, Inspection overdue and Missing inspection setup. Those
results open the affected asset or linked work order. This preserves fleet
oversight without making Fleet inspections another place users must visit and
interpret.

Acceptance: from an asset, a permitted user can understand its current
inspection state, open the work needed to change it, and review every prior
inspection in chronological history. From an Assets inspection filter, a
manager reaches that same asset and work without encountering a separate
inspection register workflow.

### NEXT-002.14 — Parts inside the work-order journey

One work-order context shows Needed, Available/reserved, Missing/ordered,
Received and Used/returned parts. Planners prepare/reserve/request parts;
mechanics record actual use. Prevent duplicate inventory usage while preserving
company/provider stock and cost boundaries.

### NEXT-002.15 — Flexible asset meters

Support hours, kilometres and miles throughout Assets, Work Orders,
Checklists, Service Reports, Planning and History. Allow rules such as every
10,000 km or 12 months, whichever occurs first. Record meters at work start and
completion, retain original values/units in history, support sensible
organization/asset display preferences, and prevent accidental unit changes or
incorrect conversions. Leave room for cycle meters without adding them now.

Acceptance example: a truck at 62,000 km with service every 10,000 km or 12
months receives a kilometre-based generated work order and service report, and
approval calculates the next target correctly.

### NEXT-002.16 — Broader land-equipment catalog and artwork

Consider Compact/Mini Excavator, Compact Track Loader, Agricultural Tractor,
Compact Utility Tractor, Lawn Tractor, Zero-Turn Mower, Motor Scraper,
Articulated Dump Truck, Asphalt Paver, Trencher, Soil Compactor, Boom Lift,
Scissor Lift, Street Sweeper, Vacuum Truck, Air Compressor, Light Tower and
UTV/Utility Vehicle. Add deliberately rather than creating every subtype.

Each selected type receives a stable catalog identity, sensible category,
appropriate default meter, searchable Add/Edit selection, offline bundled
artwork, light/dark support, a generic custom-equipment fallback, and a distinct
technical line drawing matching the existing Field Notes style.

### NEXT-002.17 — Truthful saving, syncing and administration

Clearly distinguish Saved locally, Waiting to upload, Submitted, Received,
Returned and Approved. Reopen rejected work at the field requiring correction,
provide actionable recovery for permission/version conflicts, and make
notification links work for every permitted role. Rename Send Invite to Create
invite code while it only creates a code, and provide Copy/Share. Keep Team
focused on membership/invitations instead of duplicating Fleet, Checklists and
Invoices.

Make offline readiness automatic during ordinary use. After sign-in and while
the app is connected in the foreground, quietly refresh the signed-in person's
profile, organization/capabilities, visible assets, assigned and open work,
asset context, published checklists and recoverable drafts. Opening or refreshing
a record updates its offline copy. A person should not need to predict losing
coverage or remember to press Prepare for offline work.

Replace the preparation task with a small, understandable sync state such as
**Ready offline · updated 12 min ago**, **3 changes waiting to upload** or
**Needs attention**. Keep **Refresh offline data** as a secondary action for a
person who wants reassurance before a long trip. When the connection disappears,
open cached screens without a blocking error and keep supported field actions
locally. Label and disable connection-only actions such as assignment, approval,
invoicing and organization changes with a direct explanation. Automatically
retry queued work while the app is open and connected; do not claim Android
background delivery that the app cannot guarantee.

Acceptance: after normal connected use, enable airplane mode, force-close and
reopen the app without first using a preparation control. The signed-in person
can open their cached Home, assigned work, asset and checklist, record supported
work and evidence, restart again without losing it, then reconnect and observe
one successful upload. Also verify expired cache, expired authentication,
account switching, revoked access, partial refresh and a rejected queued change;
none may expose another account's data or describe a local save as server
acceptance.

### NEXT-002.18 — Organization roles and permission-based actions

Replace the growing set of account/profile types with organization membership
and a small set of understandable working roles:

- **Company Owner:** full organization access, company settings, subscription,
  team administration and permission delegation.
- **Supervisor/Manager:** assets, planning, assignment, review and approval;
  team administration and billing can be granted separately.
- **Mechanic/Technician:** assigned work, checklists, service reports, labour,
  parts and job discussions.
- **Operator:** pre-operation/running checks, readings, issue reporting,
  handovers and relevant discussions. This role does not receive fleet-wide
  custody, certificate, renewal or inspection-register administration.

A person may hold more than one working role, such as Supervisor + Mechanic.
Employee is membership in a company rather than a useful permission role. Job
titles can be displayed without creating new authorization roles for every
trade or supervisory title.

Client/customer is an organization-to-organization relationship. A company can
maintain its own equipment, provide service to other companies, or do both.
Service requests, customer-visible reports and invoices cross that authorized
relationship. Owning assets or being an outside-service customer does not make
each person a separate Client profile type.

Invoicing is an organization capability plus an explicit Finance/Billing
permission, normally held by the Company Owner or a permitted supervisor. It is
not the definition of a client or supervisor. Platform administration remains
separate from customer-company roles.

Company Owners and Supervisors with inspection-management permission use
inspection filters in Assets for fleet-wide oversight, then manage the selected
asset or its linked work order. A mechanic receives relevant inspection work
and evidence through an assigned work order. An operator sees only the current,
expired or unsafe inspection status needed for the selected asset, surfaced on
the asset or before starting its checklist. Fleet inspections is not a separate
destination in More for any role.

Use the same core work-order, checklist and service-report experiences across
organizations. Permissions determine who may view, create, assign, perform,
review, approve, publish, invoice and manage the team. Preserve company
isolation, explicitly shared records, private evidence, internal costs,
provider billing, capability gates, revocation and audit history.

For the current isolated Next environment, prefer a clean account reset over
translating ambiguous legacy profile roles when implementation begins, provided
an inventory confirms the affected identities are test/demo accounts. Most of
the heavy-use population is disposable. Preserve the Ellicott 460SL and its
useful connected maintenance/checklist record before clearing or reseeding the
rest. Do not delete profile rows in place while retained work orders, reports,
faults, checklist runs, invoices or audit events still reference them. Use one
controlled transition:

1. Inventory Next authentication users, profiles, organizations, memberships,
   invites and the exact records connected to the Ellicott 460SL.
2. Create a small exact-ID preservation manifest/export for the dredge graph,
   including its identity, components, source notes, three imported manual
   pages, published PM/pre-operation checklists, service plans, linked work,
   completed checklist results and relevant asset history/evidence. Include
   referenced storage objects. Do not create a broad backup of disposable demo
   population solely for this transition.
3. Retain the existing warnings that its meter/baseline examples are synthetic
   and that the saved C15 JRE manual does not match the MCW10441 engine serial.
   Preserving a record must not turn sample data into a claimed observation or
   manufacturer-approved interval.
4. Remove or recreate the remaining synthetic/demo population and old test
   accounts using exact scope rather than broad pattern deletion.
5. Create clean organization fixtures with Company Owner, Supervisor/Manager,
   Mechanic/Technician and Operator members.
6. Include at least two organizations with an authorized customer/service
   relationship so shared work, reports and invoicing remain testable.
7. Remap or restore the preserved dredge graph into the intended new company
   without breaking its checklist versions, source links, history or authorship.
8. Revoke old sessions and invites, then verify onboarding, role changes,
   dredge checklist execution, company isolation, cross-company sharing and
   billing permissions.

This is a transition preference, not authorization to clear accounts or data.

### NEXT-002.19 — Contextual discussions and issue handoffs

When an operator marks a pre-operation item Needs action, let them add or
dictate a message, attach evidence, state urgency and record whether the asset
appears safe to operate. Link the discussion to the exact checklist run/item,
notify the responsible manager, and create a fault without retyping the issue.
Carry the same discussion into the linked work order so the operator, manager
and mechanic can follow the outcome.

Expose the same record-linked Discussion section where useful on checklists,
faults, work orders, inspections, service requests, service reports and assets.
Each message retains its subject link, timestamp, author, participants and
company boundary. Preserve the conversation in asset/work history.

### NEXT-002.20 — Personal agent API/MCP completion

Finish the advanced route for customers who already use Codex, OpenClaw or a
compatible agent. Provide guided setup and connection testing around
fleet/company-scoped, expiring and revocable grants, narrow audited tools,
manual/source access and clear revocation. Consequential proposals require
human review. Completion, approval, publication, invoicing and permission
changes remain human-only.

### NEXT-002.21 — Human phone acceptance and retesting

Garrett also requested an account switcher for easy profile testing on
September 12. The internal Next build exposes configured test accounts from
Login and More, with safe account changes and account-owned saved work. This
testing aid uses real current permissions; it must not simulate Company Owner
or multi-role membership before .18 exists. New configured test accounts remain
discoverable as the profile model evolves.

After implementation, exercise realistic phone journeys: manager creation,
scheduling, return and approval; mechanic checklist/report completion;
operator pre-operation failure; and customer request through work, report and
invoice. Cover offline interruption/recovery, account switching, large text,
long names, empty/populated states and calendar density. Back returns to the
same asset, filter, date or list position. Report automated evidence separately
from physical phone acceptance.

## P3 — Accepted messaging and agent exploration scope

### NEXT-002.22 — Organization messaging

Provide an organization announcement channel controlled by appropriate
managers, with unread state, notifications, timestamps, attachments,
participants and strict company boundaries. Reuse the record-discussion
foundation. Full direct messaging is outside this initial card.

### NEXT-002.23 — Managed in-app Vortice Agent

Explore an embedded Ask Vortice experience for people who will not configure
their own agent. Reuse the same scoped tools, permissions, audit and manual
sources as personal API/MCP access. Initial abilities may search and summarize,
answer manual questions with sources, and draft work orders, checklists, plans
and service reports. Consequential writes receive a human preview; completion,
approval, invoicing, publication and permissions remain human-only.

Keep provider credentials on the server. Meter use per organization, enforce
daily/monthly budgets and rate limits, support an admin disable control, and
record cost by model/conversation/tool call. Run a representative cost spike
before choosing an included allowance, overage or credit-pack price. ChatGPT
workspace subscriptions and embedded API billing are treated separately.

## Implementation choices and remaining decisions

- Recurrence defaults to 30 days of calendar lead (adjustable 0–365); meter work
  generates when its recorded target is reached. Decision 0017 records this.
- External inspection findings enter the linked work/report evidence and review
  path; the current approved certificate is retained until replacement approval.
- Company creation asks only for the missing person name and company name.
- Work completion records the report required by its execution path; standalone
  passing pre-operation checks remain independent of scheduled maintenance.
- First catalog expansion: Compact/Mini Excavator, Compact Track Loader,
  Agricultural Tractor, Zero-Turn Mower, Boom Lift and Scissor Lift.
- Pricing, allowance and retention choices for a future managed agent.

## Preserve while simplifying

- The Field Notes visual language, native controls and large touch targets.
- Tenant, company, role and capability boundaries.
- Checked approval, explicit fault verification and availability decisions.
- Immutable work history and versioned checklist publication.
- Offline drafts, evidence queues and stable retry/replay protection.
- Provider invoice states, frozen exports and real-delivery separation.
- Equipment-report source drill-down and explicit missing-data treatment.
