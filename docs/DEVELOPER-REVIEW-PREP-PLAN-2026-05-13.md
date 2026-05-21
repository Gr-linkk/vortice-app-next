# Developer Review Prep Plan

Date: 2026-05-13
Status: Working checklist before final outside/proper developer review

## Purpose

Prepare Vórtice for a serious developer review by finishing the known workflow seams first, then removing obvious vibecoding shrapnel so the reviewer spends time on real architecture and product risks instead of avoidable mess.

## Guiding order

Do not start final review while major user flows are known-broken. Finish/review the core flows, then polish, then cleanup, then package the app for review.

## Phase 0 — Stabilize current checkpoint

- [ ] Confirm service report form build is installed/tested on Garrett's phone.
- [ ] If phone unavailable, keep status explicit: built locally, install pending USB reconnect.
- [ ] Review current dirty git state before new work.
- [ ] Create a safe checkpoint branch/commit when Garrett approves.
- [ ] Preserve current service-report work and docs before touching invoicing/dashboard.
- [ ] Record known gaps rather than hiding them.

## Phase 1 — Invoicing workflow confirmation

Goal: confirm the invoicing flow still works end-to-end and matches the real shop workflow.

Review path:
- [ ] Start from a work order that is ready to invoice.
- [ ] Create/generate invoice.
- [ ] Confirm labor, parts, service report linkage, taxes, totals, and customer identity.
- [ ] Preview invoice.
- [ ] Send/mark sent.
- [ ] Mark paid/closed.
- [ ] Confirm work-order status transitions still make sense.
- [ ] Confirm closed/invoiced work orders can still accept follow-up service reports when needed.
- [ ] Confirm client-facing invoice visibility is correct.
- [ ] Confirm offline/poor-network behavior is not silently destructive.

Outputs:
- [ ] Invoicing workflow spec or notes file.
- [ ] Fix list with severity.
- [ ] Targeted tests for policy/status transitions where practical.

## Phase 2 — Dashboard continuity

Goal: dashboards should tell the same story as work orders, service reports, invoices, assets, and client access.

Review areas:
- [ ] Owner dashboard.
- [ ] Employee dashboard.
- [ ] Client dashboard.
- [ ] Client admin/mechanic dashboard behavior, if distinct.
- [ ] Operator/client-operator visibility restrictions.
- [ ] Counts/status cards match underlying lists.
- [ ] “Needs attention” cards route to useful filtered lists, not hallways.
- [ ] Recent work orders/service reports/invoices are consistent across dashboards.
- [ ] Empty states explain what to do next.
- [ ] Dashboard actions do not duplicate or contradict detail-screen actions.

Outputs:
- [ ] Dashboard continuity notes/spec.
- [ ] List of dashboard cards/actions to keep, rename, remove, or re-route.

## Phase 3 — Cross-flow consistency pass

Goal: catch issues between flows, not just inside one screen.

Checks:
- [ ] Asset → work order → service report → invoice → client history tells one coherent story.
- [ ] Work order detail cards open the right scoped lists/forms.
- [ ] Service report and invoice records remain visible after work order closure/invoicing.
- [ ] Role-based visibility is consistent across dashboard, list, detail, and deep-link routes.
- [ ] Back button behavior is predictable from leaf screens.
- [ ] Add/create actions are direct and scoped; avoid generic “hallway” screens.

## Phase 4 — Small UX polish pass

Goal: remove obvious friction before developer review.

Targets:
- [ ] Button appearance and placement.
- [ ] Duplicate buttons/actions.
- [ ] Labels and titles.
- [ ] Empty/loading/error states.
- [ ] Overflow on long vessel/work-order/customer names.
- [ ] Janky scroll areas.
- [ ] Bottom nav vs page action conflicts.
- [ ] Route dead ends and blank screens.
- [ ] Snackbar/toast wording.
- [ ] Confirm destructive actions have confirmation.

## Phase 5 — Vibecoding shrapnel cleanup

Goal: remove avoidable mess so review focuses on durable issues.

Cleanup:
- [ ] Delete temporary screenshots/debug artifacts from repo root unless intentionally kept elsewhere.
- [ ] Remove debug labels, marker strings, and temporary logging.
- [ ] Remove unused imports/dead code.
- [ ] Remove or document half-finished screens/routes.
- [ ] Consolidate duplicate workflow policy logic.
- [ ] Ensure docs/specs match the actual implemented behavior.
- [ ] Ensure migrations and generated DB code are coherent.
- [ ] Ensure no secrets/auth/runtime state were accidentally added.

## Phase 6 — Code structure / architecture prep

Goal: make the code easier for a developer to review and improve.

Review for deepening opportunities:
- [ ] Workflow policy seams: service reports, work orders, invoices, dashboards.
- [ ] Repository/provider seams: avoid UI screens knowing too much persistence detail.
- [ ] Route construction: avoid hand-built route strings scattered everywhere.
- [ ] Role/access policy: one clear rulebook per workflow.
- [ ] Offline draft/sync state: make local vs synced vs failed explicit.
- [ ] List/detail fetch behavior: avoid broad list loads when detail-by-id is needed.
- [ ] Shared card/action patterns: avoid each screen inventing its own workflow UI.

Outputs:
- [ ] Architecture notes for reviewer.
- [ ] Candidate refactors ranked by risk/value.
- [ ] Tests around important seams before large refactors where practical.

## Phase 7 — Final developer review packet

Goal: hand a real developer a clean, honest review bundle.

Packet contents:
- [ ] App purpose and current product shape.
- [ ] Current workflow specs.
- [ ] Known gaps and non-goals.
- [ ] Architecture notes and likely risk areas.
- [ ] Database/migration notes.
- [ ] Test/build instructions.
- [ ] Recent test/build status.
- [ ] Screenshots or short videos for critical flows if useful.
- [ ] “Review these first” list.

## Extra items to add before review

- [ ] Confirm seed/demo data supports reviewing all important flows without Garrett hand-building records every time.
- [ ] Add a lightweight manual QA script for the reviewer and for Garrett.
- [ ] Decide what counts as MVP-ready vs later polish.
- [ ] Capture role matrix in one place: owner, employee, client, client_admin, client_mechanic, operator, client_operator.
- [ ] Confirm production vs debug build/versionCode expectations so phone installs do not keep hitting downgrade confusion.
- [ ] Decide whether to keep or archive old screenshots and one-off debug artifacts outside the repo.

## Recommended next action

Start with Phase 0, then Phase 1 invoicing workflow confirmation.
