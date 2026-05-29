# Jasper Second-Pass Review - 2026-05-28

## Sync Caveat

The local Nextcloud folder shows no spec files modified after `06-jasper-audit-2026-05-28.md` was saved at 09:57 PDT. If Casper made changes after that, they may not have synced to this machine yet. This review is against the spec packet currently visible on disk.

## Verdict

The spec is meaningfully better than the first pass. Casper/Jasper's audit points are now more directly represented in the packet: role language is cleaner, offline behavior is much less vague, pending-sync visibility is explicit, and the recommended first coding slice still points at the correct foundation work instead of jumping into service reports.

I would approve this as the V2 product/spec direction. I still would not approve broad feature coding. The next move should be a bounded scout/coding packet for `V2 Foundation + Role/Capability/Fleet Scope`.

## Improvements Since The Audit

- Current app role names are now treated as source of truth: `owner`, `employee`, `client`, `client_admin`, `client_mechanic`, `operator`, with `client_operator` treated as legacy/uncertain.
- `service_manager` is removed as a fake role. Billing/office is a permission lane, not a new schema role.
- Client-admin default is captured.
- English and Spanish first-build requirement is captured.
- Offline rules are stronger: local completion is not server completion, pending sync is visible, and clients do not see unsynced internal work.
- WO close blocking is explicit: required checklists/reports/photos/signatures must sync before authoritative close.
- Service requests are cleaner: client request -> Vortice acknowledgement/review -> draft WO prefill, not automatic live WO creation.
- Invoice lifecycle is separated from WO lifecycle.
- Service report/client visibility language is safer.
- Build location and stack are now clear: existing Vortice repo, V2 Git branch, Supabase branch, Supabase/Drift/Riverpod/GoRouter unless a real blocker appears.

## Remaining Blockers Before Implementation

1. The first coded slice is still not explicitly answered in the question inbox. The recommendation says foundation first, but Garrett approval should be recorded before Casper codes.
2. Role matrix still has shape-changing `TBD`s around employee fleet visibility, client team invite/remove/role permissions, `operator` vs `client_operator`, invoice visibility, telemetry alert acknowledgement, and client mechanic history.
3. Offline scope still has unresolved launch choices for service requests, invoice read/edit/generate, parts logging, audit history, and longest no-service duration.
4. Action/Monitor notifications remain underspecified: who receives them, whether client mechanics can create them, whether they replace old maintenance flags, and whether they are in-app only.
5. Template versioning is still only a tentative direction. Used checklist templates should be locked/versioned before edits, but that needs explicit approval before schema/history work.
6. Asset reassignment and asset fact corrections need a concrete audit/correction workflow before production admin tools.
7. The first coding packet is not complete enough yet. It lists likely includes/out-of-scope, but still needs likely files/modules, migration candidates, exact tests, and definition of done.

## Recommended Casper Instruction

Do not broaden into service reports, telemetry, invoices, or visual cleanup yet.

Next Casper pass should produce the actual coding packet for:

```text
V2 Foundation + Role/Capability/Fleet Scope
```

That packet should include:

- current code inventory: role enum, profile model, router guards, client org access, capability gate, dashboard routes
- route/guard policy for every current role
- direct-route blocking expectations
- client/internal work-order boundary
- capability switchboard behavior
- RLS/query-scope implications
- migration candidates, if any
- tests/checks before implementation
- unresolved Garrett decisions that could change implementation shape

## Jasper Recommendation

Green-light the direction. Do not green-light broad coding.

Green-light one bounded foundation scout/coding-packet pass. Once that packet is clean, then Casper can start implementation on the role/capability/fleet foundation.
