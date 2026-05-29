# Jasper Coding Packet Audit - 2026-05-28

Checked: 2026-05-28 12:44 PDT

Source reviewed:

- `02-workflow-specs.md`
- Vortice app repo route/policy/work-order/client mechanic surfaces

## Verdict

The sync gap is fixed. The Drops copy now contains Casper's `Coding Packet: V2 Foundation + Role/Capability/Fleet Scope` section and matches the timestamp/size Garrett reported.

This is the right next packet. Casper did not wander into service reports, invoices, telemetry, visual cleanup, or broad feature coding. The packet is grounded in real repo facts:

- `router.dart` authenticates but does not centrally authorize role/capability route access.
- Client routes still expose `/client/work-orders`, `/client/work-orders/:id`, and `/client/checklists/:workOrderId`.
- `ClientCapabilityGate` exists but is a widget/screen gate, not a direct-route policy.
- `client_capabilities` RLS only clearly covers owner and owning client profile reads; inherited org-team capability reads need policy work.
- `WorkOrderStatus` still includes `assigned`, `pending_review`, and `invoiced`.
- `client_mechanic_dashboard.dart` still shows assigned work orders and links to client WO routes.

## Approval Call

Approve Casper to proceed to a bounded foundation implementation packet/patch only if the implementation is limited to:

1. central route/access policy,
2. router redirect enforcement,
3. client-side direct-route blocking for internal WOs/checklists,
4. capability gate alignment,
5. focused route/policy tests,
6. no production Supabase changes.

Do not approve broad V2 coding yet.

Do not approve service-report rebuild, invoice lifecycle rebuild, telemetry rebuild, offline queue implementation, or full WO status migration from this packet.

## Small Product Holds

Before Casper writes the patch, Garrett should confirm these assumptions or let Casper code them as explicit temporary defaults:

1. Client mechanics have zero internal WO visibility, including assigned/shared WO checklist work. They use client-side checklist/history flows instead.
2. Blocked client direct routes should land on `/client/dashboard` for now, not on internal/service-report screens.
3. `operator` is treated as client-side operations scope in the current app, despite the older role name.
4. Client admin invoice visibility is company/org-fleet scoped, not owner-profile-only, unless Garrett says otherwise.

My recommended defaults:

- yes, zero client mechanic internal WO visibility;
- redirect blocked client routes to `/client/dashboard`;
- treat operator as client-side operations;
- client admins see org/company invoices that are client-safe and synced.

## Implementation Guardrails

The first patch should be boring and narrow:

- create one testable route/access policy module;
- call it from `GoRouter.redirect`;
- keep existing screen gates but make them subordinate to route policy;
- remove or hide client mechanic assigned-WO cards/routes from the client experience;
- add tests for owner/employee allowed, client/client_admin/client_mechanic/operator/client_operator blocked from internal WO routes;
- list Supabase/RLS migrations but do not apply production changes.

The code should not delete legacy screens yet. Isolate them behind policy first, then clean them up after the boundary holds.

## Forwardable Casper Note

Jasper audit of synced packet: approved direction, bounded implementation only. The packet now has the exact foundation slice I asked for and its repo facts check out. Before coding, assume or confirm: client mechanics get zero internal WO visibility, blocked client direct routes redirect to `/client/dashboard`, operator is client-side ops scope, and client admin invoices are org/company scoped. First patch should be central route policy + router enforcement + capability alignment + focused tests only. No service reports, invoices, telemetry, offline queue, full WO migration, production Supabase writes, or legacy deletion yet.
