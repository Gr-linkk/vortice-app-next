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
The other 12 areas remain intake in `docs/specs/NOW-006-feature-continuation.md`.
Preserve the current visual language; naming and production identity remain
separate decisions. Hosted activation and device review are tracked separately
from the internal build.

Detailed client-access terminology and rules live in `CONTEXT.md`.

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

- Start each change from current `main` on a short-lived branch.
- Give each task one backlog ID and one clear outcome.
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
