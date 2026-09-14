# Project Operating Brief

## Identity

This repository is the independent continuation of the Vortice maintenance
application. Its working name is **Vortice Next** until the product is renamed.
It uses only the independent repository and Supabase project described in
`AGENTS.md` and `FORK_PROVENANCE.md`.

The product is an asset-first maintenance workspace for marine and heavy
equipment. Assets connect client access, engines and telemetry, service
requests, work orders, maintenance and operations checklists, service reports,
parts, and invoices.

## Current direction

NEXT-009 is the current production-readiness closeout. Finish the existing
workflows, release safeguards, access verification, recovery preparation and
customer operating material before expanding features. Its specification
consolidates remaining acceptance and Garrett's decisions. The company-purpose
model in decision 0018 and Field Notes design remain authoritative. Subscription
prices discussed on September 14 are hypotheses, not accepted product tiers.
Build 39 below is the current internal app delivery; housekeeping does not
constitute a production release.

NEXT-008 adds published-checklist attachment and an editable scheduled date to
the customer work-order creation page in internal Build 39 (`1.18.1+39`). The
calendar day is visible before saving and can be changed or cleared. Creation,
checklist snapshot and booking persist atomically. All 779 Flutter tests, 48
local SQL contracts and the connected native creation/reopen journey passed.
See `docs/specs/NEXT-008-work-order-creation.md` for delivery and acceptance.

NEXT-007 implements Month as the normal Work orders workspace and reviewed
XLSX/CSV/TSV/pasted-table fleet import in internal Build 38 (`1.18.0+38`). The
connected import, selected-day booking/rescheduling and company-boundary journeys
passed, as did 748 Flutter tests and all 48 database contracts. Scope, APK checksum
and acceptance evidence are in `docs/specs/NEXT-007-calendar-and-fleet-import.md`.
It extends NEXT-006 below; physical/external acceptance remains open.

NEXT-006 implements routine-work clarity through
company-purpose onboarding and one work-order experience, with small
changes to existing names, job context and next actions. Decision 0018 defines
Fleet owner, Service provider and Both: all retain own-equipment maintenance,
with customer work additionally enabled for service providers. "Service order"
is retired from the selected user-facing vocabulary. Its scope is in
`docs/specs/NEXT-006-routine-work-usability.md` and priority is in `BACKLOG.md`.
The usability completion requirement in `AGENTS.md` applies to every future
product change and build delivery. Apart from the selected onboarding/capability
refinement, new features and major redesigns are deferred
during this round. The calendar follow-up adds selected-day agendas, work counts,
grouped weeks and direct job opening. Build 37 is checksum-delivered to S24 and
Windows Downloads after clean analysis and 738 tests. Installation is pending.
Existing NEXT-002 external/physical acceptance
remains open.

NEXT-003's five follow-ups are complete and delivered as internal Build 33:
account selection, a complete native S24 demo job through invoicing, provider
offline evidence, shared execution rules and a populated Work hub performance
guard. See `BACKLOG.md` and
`docs/specs/NEXT-003-workflow-follow-through.md` for current status.

NEXT-002 records the implemented workflow-consolidation board; remaining
external acceptance is consolidated under NEXT-009. Work orders become the
common work hub while retaining the Field Notes design, checked completion,
company isolation, offline drafts and provider billing boundaries. See
`docs/specs/NEXT-002-human-workflow-kanban.md` for implemented scope and remaining acceptance.
Whole-board implementation and final verification are tracked in
`docs/specs/NEXT-002-whole-board-delivery.md`; the earlier Batch 1 receipt remains
historical evidence. Decision 0016 defines organization membership and decision
0017 defines generated cycles and original meter context. Existing legacy
identities are retained alongside the new organization permissions.

NOW-022, NOW-023 and NOW-024 are merged, verified and delivered as Build 27.
Integration evidence: `docs/specs/NOW-022-024-integration.md`.


Parts readiness extends the existing PM kits through job-specific requirements,
company/provider stock, reservations, purchasing records and actual use/returns.
See NOW-022. Standard-kit edits affect future jobs; inventory changes require
a confirmed connection and preserve replay identity for uncertain outcomes.

Maintenance plans support configurable hour and calendar recurrence, explicit
transition targets and optional included services on the same component. Fixed
milestones stay aligned after early/late completion; appointment moves remain
separate. See NOW-023 and decision 0015. Hosted activation is verified in Build 27.
Equipment reporting is selected under NOW-024: managers compare recorded costs,
explicit downtime and possible repeat faults, inspect sources and export the
same report. Calculation, coverage and access rules are in
`docs/specs/NOW-024-equipment-reporting.md`.

Owners and client managers author versioned PM and pre-operation procedures in
the Checklist library. Shared owner starters and private company copies connect
to maintenance plans/work orders and assigned operator checks. Failed pre-op
results create linked faults for corrective work and explicit verification.
See NOW-015 and decision 0012 for publication, access and execution rules.

Each client company manages its own internal work orders using the shared
work-order vocabulary and familiar owner workflow. Repairs are one type of work;
preventive maintenance, inspections and general work use the same lifecycle.
See NOW-014 and decision 0011. Provider billing remains separate.

Maintenance planning is a prominent forward-facing workflow. Existing service
intervals and component plans define upcoming maintenance; the schedule organizes
when and by whom it will be performed. NOW-013 connects these foundations to
work execution without replacing their completion rules or billing workflows.
See `docs/specs/NOW-013-maintenance-planning.md` and decision 0010.

The initial internal build implements fault-to-repair tracking and explicit
asset availability, followed by a broad UX pass and standardized dashboards.
Implementation and deployment limits are recorded in
`docs/specs/NOW-003-faults-and-availability.md` and
`docs/specs/NOW-005-ux-cohesion.md`.

Garrett selected items 1, 4 and 5 from the original assessment: company
maintenance, mechanic execution and component-specific service completion.
The connected implementation is specified in
`docs/specs/NOW-006-company-maintenance.md`; its completion rules are recorded
in `docs/decisions/0005-managed-maintenance-completion.md`.
The next selected areas are asset history, job/fault discussions and handovers,
and actionable fleet decisions (original items 14, 15 and 16). Their integrated
scope is `docs/specs/NOW-007-fleet-coordination.md`; privacy, event capture and
indicator rules are recorded in `docs/decisions/0006-fleet-coordination.md`.
Asset custody/site transfers and inspection renewals (original areas 19 and 20)
are selected under `docs/specs/NOW-009-custody-inspections.md`. Their recorded
states, versioning and access rules are in `docs/decisions/0007-custody-inspections.md`.
Area 12 is selected under NOW-022. The other 11 areas remain intake in
`docs/specs/NOW-006-feature-continuation.md`.

The direct fault-to-work-order workflow and adjacent simplification audit are
tracked in `docs/specs/NOW-012-direct-workflows.md`; repair ownership and explicit
fault verification are recorded in `docs/decisions/0009-fault-work-order-workflow.md`.
Garrett approved the Field Notes visual direction: warm ivory, deep teal,
fine technical equipment art and saved System/Light/Dark appearance. Home puts
current work before tools; Planning leads with the schedule. See NOW-017 and
decision 0013. Naming and production identity remain separate decisions. Hosted
activation and device review are tracked separately from the internal build.

Detailed client-access terminology and rules live in `CONTEXT.md`.

Scoped agent access is tracked in NOW-019 and decision 0014. Named, expiring
fleet grants expose maintenance context and optional work drafts through a
restricted API and local MCP adapter. Separate permissions cover private manual
pages, reviewed checklist/plan proposals and checked work assignment, scheduling
and scope edits. Plans combine manuals, current hours and task-specific service
history; users review and tweak them in the app. More manages scanning,
connections, owner MFA, revocation and activity. Hosted activation is separate.

Field reliability, private evidence, Android notification delivery and password
recovery are specified in `docs/specs/NOW-011-field-reliability.md`, with durable
ownership and delivery rules in `docs/decisions/0008-field-reliability.md`.

## Source authority

When documents disagree, use this order:

1. `AGENTS.md` for repository, service, safety, and agent rules.
2. `PROJECT.md` for product direction and document authority.
3. `BACKLOG.md` for active priority and scope.
4. Accepted records in `docs/decisions/` for durable decisions.
5. Current feature specifications linked from the backlog.
6. Dated plans, session reports, `NEXT.md`, and `archives/` as historical input.

Do not silently promote an item from historical material into the active
backlog. Record consequential changes as a decision and update superseded
documents with links rather than rewriting history.

## Working agreements

- Continue authorized work on its verified branch; start independent new work
  on a short-lived `codex/` branch from the agreed current base.
- Give substantive product/implementation tasks one backlog ID and a clear
  outcome. Incidental mechanical fixes may reference existing scope without a new item.
- Keep schema changes in new files under `supabase/migrations/`; never edit a
  migration that has been deployed.
- Run `scripts/verify.ps1` before opening a pull request.
- Keep UI authorization and Supabase RLS changes in the same review when they
  jointly define access.
- Store reusable knowledge in tracked docs, disposable work in `work/`, local
  deliverables in `outputs/`, and secrets only in ignored local configuration.

## Explicit non-goals

- Synchronizing changes back to the original repository or its services.
- Treating archived plans or mock personas as approved product requirements.
- Shipping a production mobile release before the final name, application IDs,
  signing material, and production service targets are deliberately selected.
- Combining telemetry collector/runtime work with app changes unless a backlog
  item explicitly includes both.

## Entry points

- Active work: `BACKLOG.md`
- Development workflow: `docs/DEVELOPMENT-WORKFLOW.md`
- Decisions: `docs/decisions/README.md`
- Releases: `docs/RELEASE-CHECKLIST.md`
- Supabase workflow: `supabase/README.md`
- Client access model: `CONTEXT.md`
