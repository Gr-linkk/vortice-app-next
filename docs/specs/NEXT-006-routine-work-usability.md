# NEXT-006 — Make routine work obvious

Status: September 13 implementation and computer acceptance complete; Build 37
packaging/delivery in progress. Physical phone acceptance remains separate.

## Outcome

A first-time user can pick equipment, report a problem or choose maintenance,
open the resulting work order, do the work, record what happened and finish.
Customer billing follows only when applicable. Users should not need to learn
the app's internal document or database model to complete that path.

## Accepted scope

- Use "Work order" consistently through navigation, cards, creation and opening
  actions. Garrett explicitly rejected "Service order" on September 13; remove
  that job name throughout the ordinary workflow. Explain equipment ownership
  or customer context only where it affects the decision. Preserve the separate
  permissions and billing rules.
- Keep the job's checklist, findings, photos, parts and labour accessible in job
  context. Prefer fixing existing links, grouping and labels over adding screens.
- Give each stage a clear next action and result. Explain completion requirements,
  saved versus submitted state, review and return-for-correction in plain language.
- Preserve the Field Notes design, expanded list groups and established shortcuts.
  Use contextual help only when it resolves a demonstrated misunderstanding.
- Retain the NEXT-004 audit and its suggestions as evidence; evaluate relevant
  suggestions against the actual workflow instead of adding every prompt.

## First priority: company purpose and work focus

Accepted September 13 direction is recorded in decision
`../decisions/0018-company-purpose-and-work-orders.md`.

- New-owner onboarding asks Fleet owner, Service provider, or Both when creating
  the company. These are company activities under the same Company Owner role.
- All three retain full own-equipment fleet functions. Service provider and Both
  also support external customer work; neither requires a second fleet account.
- Invited team members inherit company setup and their granted working roles.
- Work orders remain one shared experience. Make own-equipment and customer
  work easy to prioritize without changing accounts or permissions.

Implemented interaction: one Work orders filter with **Our equipment**,
**Customer work**, and **All work**. Fleet owner initially sees Our equipment;
Service provider initially sees Customer work; Both initially sees All work.
Remember subsequent view choices per user/company. A fleet owner's work on its
own equipment remains under Our equipment even when an outside provider does
the work. Garrett authorized this proposed interaction for implementation.
Keep status and assignment filters usable alongside the work-context filter.

The previous onboarding collected name/company or an invitation without a
purpose. It now presents all three choices, saves company creation and purpose
atomically, and safely replays the same operation after a lost response. Company
services exposes the same choice and preserves its separate billing setting.
Work lists, planning, creation and opening actions use Work order consistently;
cards identify Our equipment or Customer work.

Implementation slice: onboarding and membership repository/context, company
service settings, Work list/calendar and contextual job creation, plus affected
labels and server capability checks. Reuse the existing provider capability;
persist company purpose and define compatible defaults for existing companies
without guessing from legacy roles. Validate saved settings and retries so a
failed setup cannot appear complete. New-company setup requires a connection;
keep existing job drafts and cached view preferences scoped to user/company.

Acceptance must start from fresh onboarding for each choice, save/reopen the
result, then exercise an own-equipment job for every choice and customer work
for Service provider and Both. Check invitation roles, existing-account access,
company isolation, billing permissions and recovery after interrupted setup.
Walk creation from equipment and customer context, filter switching and return
to the job at phone size and large text. Full fleet capability must remain
reachable from the service-provider choice. Record app/rendered evidence
separately from physical-phone acceptance.

## Execution and acceptance

1. Trace normal entries from equipment, a fault/request and scheduled maintenance
   into the work order. Note the actor, labels, destinations and state transitions.
2. Walk one internal job and one customer job through checklist/evidence, parts
   and labour as applicable, submission, correction/review and completion.
   Check that invoicing appears only in its authorized customer workflow.
3. Record concrete confusion and small fixes before/after. Inspect adjacent
   entry points so a naming correction persists through the complete route.
4. Verify real rendered screens and interactions at phone size and large text:
   readable selected filters, consistent names, accessible related records,
   understandable blocked/completion states and a clear next action.
5. Exercise relevant saved/offline and return-to-job behavior. Preserve drafts,
   account isolation, review requirements and invoice integrity. Run focused
   regression checks and the guarded release checks appropriate to actual changes.
6. Before build delivery, record which paths were exercised, rendered evidence,
   remaining limitations and separate physical phone acceptance. Automated test
   totals alone cannot close the usability requirement.

## September 13 implementation and computer evidence

The company-purpose migration is deployed only to Vortice Next. It adds nullable
purpose for compatibility, atomic/idempotent company creation, owner-only
purpose changes, and checked follow-up customer work on equipment already shared
through an active relationship. Customer context never lists an unrelated fleet.
The three choices share the existing Company Owner role and own-equipment tools.
Existing billing flags and records are preserved. The demo fleet owner selected
own-equipment purpose and the demo service owner selected customer-work purpose
through the actual Company services screen; neither loses fleet tools.

Normal entries exercised in the connected native Flutter test host:

- Fresh company onboarding for Fleet, Service and Both; reopen each company;
  equipment detail -> New work order -> assign self -> start/pause labour ->
  create report -> submit -> approve/complete. All three can do their own work.
- Invitation acceptance for a mechanic inherits company purpose and retains
  mechanic permissions. Five existing demo company roles still open their own
  company scope and available tools.
- Customer shares equipment through the existing request/relationship path;
  provider Work orders -> Customer work -> Create work -> select customer
  equipment -> create -> reopen. Service and Both each assign, execute, submit
  and approve/share a report; the customer can read the shared report without
  provider-private notes. Fixture setup uses checked RPCs; subsequent work
  creation and completion use rendered controls.
- Switch Our equipment/Customer work/All work and reopen; preferences remain
  scoped to the current person and company. Customer-owned jobs stay under Our
  equipment for the customer even when an outside provider performs them.
- Equipment categories, cross-category search, equipment-specific/general
  checklist groups, company switcher, Work status and customer-equipment
  dropdowns. Rendered checks include 390px and 320px with 200% text; the company
  choices also pass English and Spanish large-text widget checks.

Small UI fixes: standard wrapping dropdowns replace inconsistent raw selectors
in company switching, service requests, checklist preparation, required photos
and Work status. Equipment/assignee choices sort naturally. Work-order opening
actions and own/customer context agree across lists and planning. Long selected
equipment names wrap. Field Notes colours, grouped lists and navigation remain.

Garrett added the calendar follow-up during implementation. Month selection now
keeps the calendar visible and displays that day's agenda underneath. Selected
dates have a strong highlight, today has an outline, and badges show job counts;
cells align evenly when text or badges increase their height. Week view groups
work by day. Agenda cards show full title, equipment, assignee, state and booked
time; tapping a card opens the existing authorized job route, with rescheduling
available as a secondary action. Untimed customer dates are labelled No time
booked, and overnight work appears on both affected dates. Status filtering
preserves the calendar mode and selected date. The unscheduled-work shortcut
remains available so undated work is not silently lost.

Calendar acceptance uses two scheduled jobs on an isolated temporary company
asset because the existing demo fleet had no open dated work. Creation and
scheduling use checked repository commands; calendar date selection, opening,
return, week/month switching and large-text inspection use rendered controls.
Both connected stages pass in `outputs/next006-e2e-FlSNrB4G/`; screenshots were
visually inspected with real fonts at 390px and 320px/200% text. The 36 affected
planning/calendar tests pass in `outputs/next006-calendar-tests.log`, including
English/Spanish, overnight work and retaining the selected date after detail.

Verification evidence (ignored local output paths):

- Final guarded verification: clean analysis and **738 Flutter tests pass** in
  `outputs/next006-final-verify.log`, including the calendar follow-up. The
  Windows helper completed with exit code 0. The earlier 735-test run precedes
  the three added calendar regressions.
- **47 local SQL suites and 47 hosted rollback suites pass**, including purpose,
  replay, role boundaries, customer equipment visibility and revoked access:
  `outputs/next006-sql-final.log`, `outputs/next006-hosted.log`.
- Populated Work hub performance contract passes for 340 assets/1,500 jobs:
  `outputs/next006-performance.log`.
- Connected workflow receipts: `outputs/next006-e2e-latest.txt`,
  `outputs/next006-completion-latest.txt`, `outputs/next006-demo-latest.txt` and
  `outputs/next006-focus-ui-latest.txt` point to logs, stage receipts and rendered
  screenshots. Initial fresh-onboarding screenshots are in
  `outputs/next006-e2e-59kAnaUS/screenshots/audit010/`; later runs reopen the same
  isolated fixtures to verify saved setup.
- The list/grouping pass has four completed stages; modern membership has five;
  the whole-app audit visits **114 routes** with no error UI, framework errors,
  stuck loading or hidden provider failures. Evidence:
  `outputs/next006-ui-qRhVbODq/`.

The existing grouping test assumed exactly five demo procedures; it now checks
the actual saved equipment-specific set, preserving a sixth existing procedure.
The connected scroll helper now handles variable-height lazy lists after text
scale changes and holds the actual scroll state while finding a control.
Screenshot capture settles floating-label animations before saving an image.
These test corrections preserve hit-test and error assertions.

Limits: connected tests use a native Flutter test host and temporary account
storage, not the Android installation. Existing unit/SQL suites cover draft,
offline, permission and invoice contracts; this release still needs installation
and normal use on the physical phone. First-time customer equipment sharing
continues through the existing customer connection/request path. Follow-up
creation does not grant general access to that customer's fleet. Existing
NEXT-002 email/SMS setup and physical acceptance are still open.

## Boundaries

The September 13 company-purpose onboarding/capability refinement is selected.
No other new product features, major navigation redesign, account reset, record
deletion, schema consolidation or billing-policy change is selected here.
Existing internal/provider data boundaries remain intact. NEXT-002 retains its
external setup and physical acceptance; this item does not silently close them.
The standing requirement in AGENTS.md continues after this round is complete.
