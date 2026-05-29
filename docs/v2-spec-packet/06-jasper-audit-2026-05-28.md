# Jasper Audit - 2026-05-28

## Overall Take

This is a strong V2 spec packet. It captures the right product direction: asset-first, invite-only, mobile field use first, capability switchboard instead of tiers, internal work orders separated from client-facing records, and explicit offline/sync honesty.

The spec is good enough to stop broad rediscovery. It is not yet fully ready for broad coding across all modules. The next useful move is to close the shape-changing decisions, then start with the foundation slice.

## What Looks Solid

- Rewrite/salvage direction is right: keep schema/domain truth, do not preserve the messy current workflow shape.
- Work-order lifecycle cleanup is strong: `draft -> ready -> in_progress -> on_hold -> completed -> closed`, with assignment, sync, review, billing, and client visibility separated.
- Offline field-work principle is correct: local work must show as waiting/pending until server acceptance.
- Client-facing product boundary is much cleaner: clients see service records/history/reports/invoices, not internal Vortice WOs.
- Capability switchboard is the right replacement for tier dashboards.
- Service report rebuild direction is sane: work-order-scoped, phone-first, step flow, durable draft/pending sync.
- Saved checklist history as immutable asset history is a good foundation.
- Supabase + Drift + Riverpod + GoRouter as default stack is a reasonable boring path unless a real blocker appears.

## Gaps / Holes To Close Before Casper Codes Too Broadly

1. Role and permission edges are still the biggest blocker.
   The spec settles `owner` and `employee`, but still has many `TBD`s around `client`, `client_admin`, `client_mechanic`, `operator/client_operator`, employee fleet visibility, client team management, invoice visibility, telemetry alert acknowledgement, and whether `operator` and `client_operator` collapse.

2. The first coded slice is not explicitly approved yet.
   The build plan recommends `V2 Foundation + Role/Capability/Fleet Scope`, and I agree. Casper should not jump into service reports or UI cleanup first unless you intentionally override that.

3. Offline scope still has open edges.
   Work orders/checklists/reports are mostly settled. Service requests, parts logging, invoice offline behavior, audit-history requirements, and longest no-service duration are still open. Those choices affect the sync engine shape.

4. Notifications / Action / Monitor is underspecified.
   Operator Action/Monitor creates a client-side notification, but recipients, lifecycle, visibility, and whether it replaces old maintenance flags are still open. That is a future bug farm if coded loosely.

5. Template versioning needs a decision.
   The spec says used templates should likely be versioned/archived before edits, but the actual behavior is not settled. This matters for checklist history integrity.

6. Asset ownership changes need audit rules before production.
   Moving `asset.client_id` changes historical visibility. The spec flags it, but needs a concrete audit/reassignment policy before this becomes a real admin action.

7. Client-facing language is not closed.
   The spec has good recommendations, but exact labels for request/job/report states still need a final pass, especially with English/Spanish shipping from day one.

8. Data model additions are listed but not prioritized.
   Likely required early: audit log, asset correction request, assignment model, device pairing history, document/export records, notification source table, template versioning/archive. Casper should turn these into migration candidates, not scatter them into feature code.

9. Launch promise is broad.
   "All workflows together" is the target, but the spec should keep enforcing staged acceptance. Otherwise Casper may try to build everything shallowly. Foundation first, then field WOs/offline, then checklists/history, then reports is the safer path.

10. Current dirty repo state needs protection.
   The canonical repo has untracked spec/screenshots/artifacts and a newly untracked workflow spec. Casper should inspect status and avoid cleanup/revert unless explicitly told.

## Recommended Instruction To Casper

Use the V2 spec packet as product truth, but do not start broad feature work yet.

First pass should be a foundation/scout pass:

- read all six spec files
- inspect current role enum, route guards, capability gate, client org asset access, and existing tier/client work-order routes
- produce a coding packet for `V2 Foundation + Role/Capability/Fleet Scope`
- identify migrations needed for role/capability/fleet scope only
- do not rebuild service reports yet
- do not delete old screens yet
- do not touch production Supabase
- preserve the current repo state and avoid reverting unrelated dirty files

Definition of done for Casper's next step:

- clear route/guard model
- client/internal WO boundary enforced in plan
- capability switchboard behavior mapped
- direct-route blocking tests proposed
- migration needs listed
- unresolved product decisions called out before implementation

## Jasper Recommendation

I would approve the spec direction, but I would not green-light broad coding yet. Green-light a bounded foundation slice only.

Casper's best next job is to make role/capability/fleet scope boring and testable. Once that is solid, service reports and offline work orders have a much better chance of not turning back into the current app's tangled mess.
