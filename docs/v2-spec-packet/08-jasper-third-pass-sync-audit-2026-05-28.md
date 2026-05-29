# Jasper Third-Pass Sync Audit - 2026-05-28

## Sync Verdict

As of 11:23 PDT, the local Nextcloud V2 spec packet still does not show any newly synced Casper changes after Jasper's second-pass review.

Latest visible files in the packet:

- `07-jasper-second-pass-2026-05-28.md` - 10:28:58 PDT
- folder modified time - 10:29:04 PDT
- `02-workflow-specs.md` - 09:55:49 PDT
- `06-jasper-audit-2026-05-28.md` - 09:57:25 PDT

No new file, updated spec file, coding packet, or Casper output is visible in:

- `Vortice App V2 Spec 2026-05-24/`
- adjacent `Jasper Drops/Vortice/` files
- the local canonical app repo docs

## Third-Pass Audit

The prior second-pass review still stands.

The visible spec is good enough to approve as product/spec direction, but not good enough to approve broad coding. The correct next move is still one bounded scout/coding-packet pass:

```text
V2 Foundation + Role/Capability/Fleet Scope
```

## What Is Still Strong

- Current app role names are treated as source of truth.
- `service_manager` is gone as a fake role.
- Billing/office remains a permission lane, not a new role.
- Client-admin default is captured.
- English and Spanish first-build requirement is captured.
- Offline behavior is much safer and clearer.
- Local complete is not server close.
- Clients do not see unsynced internal work.
- Internal WOs are separated from client-facing records.
- Service requests prefill draft WOs only after Vortice review.
- Invoice lifecycle is separated from WO lifecycle.
- Capability switchboard remains the right access model.

## Still Blocking Implementation

1. First coded slice still needs explicit Garrett approval recorded. Recommendation: approve foundation first.
2. Role/access matrix still has shape-changing TBDs: employee fleet visibility, client team management, `operator` vs `client_operator`, invoice visibility, telemetry alert acknowledgement, and client mechanic history.
3. Offline launch scope still needs closure for service requests, invoices, parts logging, audit history, and longest no-service duration.
4. Action/Monitor notifications still need recipients, lifecycle, visibility, and relationship to older maintenance flags.
5. Checklist template versioning/archive behavior still needs an explicit decision before history/schema work.
6. Asset reassignment and client asset-fact corrections need audit/correction workflow rules.
7. The first coding packet still needs code inventory, likely files/modules, migration candidates, RLS/query-scope implications, direct-route tests, and definition of done.

## Recommended Casper Instruction

Do not start broad implementation yet.

Produce the actual coding packet for:

```text
V2 Foundation + Role/Capability/Fleet Scope
```

Include:

- code inventory for role enum, profile model, router guards, client org access, capability gate, and dashboard routes
- route/guard policy for each current role
- internal/client WO boundary
- capability switchboard behavior
- RLS/query-scope implications
- migration candidates
- direct-route blocking tests
- exact checks to run
- definition of done
- unresolved Garrett decisions that could change implementation shape

If Casper already produced that somewhere else, it has not synced into this visible V2 spec packet yet.
