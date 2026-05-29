# Vortice V2 Build Plan, Salvage, And Acceptance

Date: 2026-05-24
Status: detailed planning draft for Garrett review

## Garrett Question Inbox

1. **Build location:** Garrett chose rewrite/salvage: do not preserve the current messy implementation shape, but do preserve progress. Should that rewrite live in a new repo, a new app folder inside the current repo, or a fresh branch/package layout?

   Garrett answer: Use the existing Vortice app repo as canonical. Create a V2 Git branch for the rewrite/salvage work, and pair it with a Supabase branch for database/RLS/migration work. Do not start a new app repo unless the Flutter app itself is being abandoned.

2. **First coded slice:** What should be the first coded V2 slice after spec approval: auth/client access, asset hub, work orders, checklists, or service reports?

   Garrett answer:

3. **Default stack:** Should we keep Supabase/Drift/Riverpod/GoRouter as the default stack unless a blocker appears?

   Garrett answer: Yes. Keep Supabase as the primary backend path and branch Supabase alongside the Git V2 branch. Drift/Riverpod/GoRouter remain the default app stack unless a real blocker appears.

4. **Phone acceptance gate:** Is phone testing on Garrett's Android device the required acceptance gate for every field workflow slice?

   Garrett answer:

5. **Pilot seed data:** Do we need a real seeded pilot dataset before coding, or should seed data be built as part of the first slice?

   Garrett answer:

6. **Old screen cleanup:** Should old app screens be deleted aggressively during V2, or kept behind compatibility routes until replacement is proven?

   Garrett answer:

7. **Launch shape:** Should V2 launch as one all-at-once app replacement, or a staged internal beta where staff workflows land before client workflows?

   Garrett answer:

8. **Most dangerous feature to lose:** Which existing feature is most dangerous to lose during rewrite: service records, checklist history, invoices, telemetry, or client access?

   Garrett answer:

## Resolved From Garrett Notes

- V2 is a rewrite/salvage effort. The goal is to stop inheriting the current app mess while avoiding loss of product/schema/domain progress.
- V2 build location is settled: use the existing Vortice app repo, create a V2 Git branch, and pair that with a Supabase branch. New repos are reserved for separate integration/tooling work, not the Flutter/Supabase app.
- Supabase remains the backend path for V2. Schema/RLS changes should be branch-and-migration driven, tested away from production, then promoted only after review.
- First launch target is mobile field use. Phone testing on Garrett's Android device should be treated as the default acceptance gate for field workflow slices unless Garrett says otherwise.
- Staff role split, client-admin default, and bilingual English/Spanish launch are settled product constraints for the build plan.
- First non-dredge pilot target is a general client/worksite. V2 should validate the general service workflow, not only Paradise Marina dredge telemetry.
- V2 launch promise is the full workflow set currently defined: portal/history, WOs, reports, checklists, invoices, telemetry, and supporting documents/records. That makes build sequencing important; it does not mean every workflow must be equally deep in the first coded slice.
- V2 launch has no public marketing/demo/request screens. Authenticated invite-only access is the app boundary.
- French should not be a branch. Keep localization in one codebase with resource files and translation completeness checks.
- Current V1/V1.5 app docs and code are approved reference material for V2. Preserve the workflows already built where they express clean domain truth, but strip away noisy screens, route sprawl, tier/dashboard leftovers, and smeared provider logic.

## Current App Salvage Assessment

### Salvage Rule From Garrett

V2 should incorporate as many already-built Vortice workflows as possible, but without inheriting the noise.

Practical rule:

- Treat current docs, migrations, models, repositories, workflow seams, and tests as evidence.
- Treat current screens, dashboards, route exposure, role leakage, and overgrown providers as suspect until re-proven.
- Preserve workflow intent and data shape before preserving UI shape.
- Prefer explicit V2 modules over patching old widgets into being the service writer, mechanic, and filing cabinet again.

This means the old app is not trash. It is a parts shelf. Pull the good parts, label them properly, and do not bolt the bent frame back onto V2.

### Current App Workflow Evidence Checked

Useful code/doc sources inspected for salvage:

- `docs/VORTICE-WORKFLOW-SPECS-2026-05-21.md`
- `docs/WORKFLOW-ARCHITECTURE-NOTES-2026-05-08.md`
- `lib/db/database.dart`
- `lib/features/assets/client_team_asset_access.dart`
- `lib/features/clients/client_capability_gate.dart`
- `lib/features/checklists/checklist_submission_orchestrator.dart`
- `lib/features/checklists/saved_checklist_history_writer.dart`
- `lib/features/work_orders/work_order_repository.dart`
- `lib/features/service_reports/service_report_repository.dart`
- `lib/features/service_reports/service_report_workflow.dart`
- `lib/features/invoices/invoice_provider.dart`
- `lib/features/telemetry/telemetry_repository.dart`
- `lib/l10n/app_localizations*.dart`

### Salvage With Confidence

- Product decisions in docs: capability switchboard, asset-first telemetry, saved checklist history, client org access.
- Domain models as reference: assets, work orders, service reports, saved checklists, telemetry, invoices, parts.
- Supabase migrations that represent accepted product direction.
- Client org asset visibility model.
- Saved checklist snapshot concept.
- Asset-first telemetry model and pairing direction.
- Drift offline queue concepts: `sync_operations` and `local_attachments`.
- Settled work-order vocabulary: main status `draft -> ready -> in_progress -> on_hold -> completed -> closed`, with assignment/review/billing/sync/client visibility as separate tracks.
- Existing localization shape for English/Spanish, as proof that one-codebase language support is already the right path.
- Named workflow seams: checklist submission orchestration, saved checklist history writer, PM completion, client fleet access, capability gate, service-report local-first repository.

### Salvage Carefully

- Work-order screens/providers: useful behavior exists, but must be wrapped by the settled V2 transition/offline policy instead of preserving direct status writes.
- Asset Detail: good hub concept, but risk of too many provider-specific responsibilities.
- Checklist submission screen: useful domain flow, but needs stronger submission seams.
- Service request flow: MVP exists, but status language/lifecycle is thin.
- Invoice generation/export: useful, but needs lifecycle audit.
- Parts/PM kits: useful concept, needs actual-used versus planned-kit separation.
- Telemetry screens: useful asset-first seams, but MVP values depend on hardware evidence.
- Role routing: useful inventory, needs stronger guards and route cleanup.
- Drift local tables: useful foundation, but V2 needs a deliberate sync engine and visible conflict behavior, not scattered local fallbacks.
- Service-report local-first save/sync: good direction, but authoring and route entry need rebuilding around the workflow.

### Treat As Reference Only / Likely Replace

- Service report authoring screen that failed on device.
- Tier-specific client dashboards.
- Client internal work-order routes.
- Meeting/demo request screen. Garrett confirmed no public marketing/demo request screens for V2 launch.
- Any screen where hidden nav is relied on as authorization.
- Any broad provider that can leak cross-client assets/history.
- Any current UI that mixes multiple jobs into one screen instead of routing to named workflow modules.
- Any generated/localization string coverage that leaves real screens hard-coded in English for launch-critical flows.

## Recommended V2 Build Strategy

Decision direction: rewrite the app shape while salvaging domain truth.

Reason: the current repo contains valuable schema, migrations, domain model, and tested decisions, but the workflow implementation is too smeared across screens to treat as the V2 foundation. V2 should preserve product truth while rebuilding workflows as explicit modules.

### Phase 0: Spec Closure

Goals:

- Garrett answers top question blocks.
- Define localization architecture for English/Spanish launch and future French without code branching.
- Resolve role model.
- Resolve V2 implementation strategy.
- Resolve offline scope.
- Resolve work-order and service-request statuses.
- Produce first coding packet.

Exit criteria:

- No P0 workflow has a shape-changing open question.
- First build slice is selected.
- Backend/local/offline direction is chosen.

### Phase 1: Foundation And Guards

Build:

- app shell/navigation policy
- route guards
- role/capability guard helpers
- client/org/fleet scope read model
- capability switchboard read model
- sync status display foundation
- seed/pilot data

Acceptance:

- each role lands in correct experience
- direct route access blocked correctly
- client org users see only their fleet
- disabled capabilities block new workflow entry
- no tier dashboard behavior drives product access

### Phase 2: Asset Hub

Build:

- asset list/search
- asset detail hub by role
- asset facts read-only/edit/admin split
- client correction request placeholder or full workflow
- history cards
- telemetry/checklist/service sections as stubs or live cards

Acceptance:

- owner sees full asset operations
- client sees baseline portal asset view
- client mechanic sees checklist/history surface, no internal WOs
- operator sees operations-only asset view
- no mutations happen directly from hub except explicit asset admin edits

### Phase 3: Work Orders And Field Offline

Build:

- internal WO list/detail/create
- status transition policy
- assignment policy
- local/offline WO queue for approved actions
- sync state on list/detail
- conflict/retry handling

Acceptance:

- staff can create/use WOs in target field conditions
- offline-safe actions survive app restart
- pending sync is visible
- clients cannot see internal WOs
- status transitions enforce required data

### Phase 4: Checklists And Saved History

Build:

- internal WO checklist flow
- client maintenance checklist flow
- operator operations checklist flow
- saved_checklists history list/detail
- Monitor/Action validation
- offline checklist submit/sync

Acceptance:

- every checklist submission creates saved immutable history
- operations and maintenance tabs obey role rules
- client checklist does not satisfy PM or create WO
- operator Action/Monitor creates client-side notification only
- offline submissions survive restart and sync later

### Phase 5: PM Planning

Build:

- service intervals
- due reminders
- generate PM WO
- PM checklist completion
- manual completion hours
- interval satisfaction after authoritative sync

Acceptance:

- staff PM can satisfy intervals
- client/operator checklists cannot satisfy PM
- telemetry/manual hours do not silently override staff-entered PM completion hours
- due state and reminder state stay separate from completion

### Phase 6: Service Reports

Build:

- work-order-scoped new report flow
- 5C draft persistence
- signature step
- photo step
- review/submit
- durable pending-sync report
- client/staff report list/detail
- PDF later once flow is stable

Acceptance:

- opens reliably on Garrett's phone from real WO
- no blank/stuck/freeze screen
- draft survives restart
- signature required before submit
- photos optional and retryable
- offline submit creates pending report
- client sees synced final reports only unless otherwise approved

### Phase 7: Invoices, Parts, And Documents

Build:

- parts actual-used logging
- PM kit prefill
- invoice generation from eligible WO
- invoice edit/send/paid/void states
- PDF/XLSX storage/regeneration
- client invoice/document views

Acceptance:

- completed WOs are invoice-eligible; review state can block sending
- sent invoices remain editable if that decision holds
- generated files are stored and regeneratable
- parts estimate vs actual used is clear
- client can view allowed invoices/docs

### Phase 8: Telemetry And Device Pairing

Build:

- owner device pair/replace/unpair
- pairing history
- asset telemetry latest/history
- alert list/detail
- client acknowledge
- staff resolve
- gateway health owner view

Acceptance:

- telemetry is asset-first
- one active device per asset
- unpair/replace preserves history
- no fake production telemetry
- exact values reflect real hardware/gateway evidence

## Definition Of Done For Any Slice

For each future coding slice:

- Product decision references are linked.
- Roles and capabilities are explicit.
- Data ownership is explicit.
- Offline behavior is explicit.
- Route guard and backend/data scope are considered.
- Empty/loading/error/offline states exist.
- Mobile field path is tested.
- Direct route access is tested where relevant.
- Existing user data is not destroyed.
- Known limitations are documented in the slice handoff.

## Testing Gates

Recommended gates:

- Unit tests for workflow policy and status transitions.
- Repository tests for scope and sync queue behavior.
- Widget tests for critical forms where practical.
- Route guard tests.
- Supabase/RLS review before live apply.
- Android phone smoke test for field workflows.
- Manual offline test: airplane mode, submit, restart app, reconnect, sync.
- Export test for generated PDFs/XLSX once implemented.

## Branch And Migration Strategy

Settled direction: branch both the app repo and Supabase.

- Git: keep the existing Vortice app repo canonical. `main` stays stable/reference; V2 work starts from a dedicated branch such as `v2/workflow-foundation`.
- Supabase: create/use a Supabase branch matched to the V2 Git branch. Schema, RLS, seed data, and migration experiments happen there first.
- Migrations are the contract between the Git branch and Supabase branch. Every schema/RLS change should be represented as a reviewable migration, not a hand-edited production drift.
- Keep old stable surfaces while new workflow slices land behind new routes/flags.
- Cut over one workflow at a time after phone testing.
- Remove old screens only after replacement passes acceptance.
- Prefer additive migrations first. Avoid destructive live Supabase migrations until backup, branch validation, and review are complete.
- New repos are only for separate tooling/integration projects, such as telemetry gateway software, migration utilities, or docs packets. The Flutter/Supabase app stays in one repo.

## Highest-Risk Decisions Before Coding

1. Client-visible language and service request lifecycle.
2. Offline scope for service requests, parts, invoices.
3. Exact reopen policy after authoritative WO close.
4. Template versioning/archive behavior.
5. Client team management permissions.
6. Device pairing history schema.
7. Export/document MVP scope.
8. First pilot dataset and acceptance device.

## First Coding Packet Candidate

Do not execute until Garrett approves coding.

Recommended first slice:

```text
V2 Foundation + Role/Capability/Fleet Scope
```

Why:

- Every workflow depends on correct user scope.
- Current app has route contradictions.
- Capability switchboard and client org access are settled enough to formalize.
- It reduces risk before building forms.

Likely included:

- role enum cleanup decision
- route guard model
- client org fleet read model
- capability guard model
- dashboard shell cleanup
- direct route blocking tests

Explicitly out of scope:

- service report rebuild
- telemetry values
- invoice generation
- PM interval behavior
- new visual redesign beyond navigation policy

Alternative first slice:

```text
Service Report V2 Authoring
```

Why:

- It is a known broken field workflow.
- It has a contained rebuild plan.

Risk:

- If route/role/offline foundations remain weak, report work may repeat the current pattern of patching a screen before the workflow is stable.

Recommendation: foundation first, service report second.
