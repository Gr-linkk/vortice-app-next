# Vortice V2 Branch Spec

Date: 2026-05-28
Branch: `v2-route-access-foundation`
Status: active branch-local V2 authority

## Purpose

This file is the branch-local starting point for Vortice V2 work.

V2 is a new parallel app line on `v2-route-access-foundation`. The old `main`
app is preserved as reference/stable history. Do not plan V2 work as a feature
branch that must merge back into the old app shape.

## Source Of Truth On This Branch

Use these in order:

1. `docs/VORTICE-V2-BRANCH-SPEC.md` for current V2 branch direction and build order.
2. `docs/v2-spec-packet/README.md` and the split `docs/v2-spec-packet/*.md` files for the latest V2 product/workflow/data/screen/build packet copied from the approved Nextcloud drop lane.
3. `docs/VORTICE-WORKFLOW-SPECS-2026-05-21.md` for the earlier detailed workflow map and foundation coding packet history.
4. Older focused docs under `docs/` as supporting references only.

The split V2 packet from Nextcloud has been copied into `docs/v2-spec-packet/`
so the app branch carries the inspectable source material with the code.

## Settled V2 Direction

- Asset Detail is the workflow hub, but named modules own workflow mutations.
- Client onboarding is invite-only. No public self-registration.
- Client behavior uses a per-client capability switchboard, not tier dashboards.
- Baseline client portal access is always on: fleet, history, service requests,
  service reports, invoices, and documents.
- Internal Vortice work orders are staff workflow. Client mechanics use client-side
  checklists/history and do not see internal work orders.
- Submitted checklist history is immutable asset history in V2 launch scope.
- Service reports are client-facing records linked to work orders, not the work
  order itself.
- Day-one offline scope includes work orders, checklist flows, and service-report
  pending sync behavior.
- Telemetry is asset-first; engine/J1939 data is a stream under an asset.
- No-data-loss beats cleanup.

## Current Foundation Slice

The first slice is `V2 Foundation + Role/Capability/Fleet Scope`.

Definition of done for this slice:

- One central route/access policy exists and is tested.
- Client-side roles cannot direct-route into internal Vortice work orders.
- Client fleet scope uses the shared org-owner model, not broad per-screen queries.
- Capability switchboard rules match route behavior and screen behavior.
- Legacy tier/dashboard behavior is compatibility UI, not product authority.
- Migration needs are listed separately from app feature code.

Current implementation files for this slice:

- `lib/core/route_access_policy.dart`
- `lib/core/router.dart`
- `lib/features/dashboard/client_mechanic_dashboard.dart`
- `test/core/route_access_policy_test.dart`

## Next Build Order

1. Commit the current foundation slice with the branch-local specs.
2. Keep screenshot/XML debug artifacts out of git unless explicitly needed as evidence.
3. Continue with the next vertical V2 slice only after this checkpoint is clean.
4. Prefer small app slices with focused tests over broad widget rewrites.

## Migration And Backend Rule

Do not hand-edit production Supabase state for V2 experiments. Schema/RLS changes
belong in migrations and should be validated against a V2-matched Supabase branch
before production cutover.
