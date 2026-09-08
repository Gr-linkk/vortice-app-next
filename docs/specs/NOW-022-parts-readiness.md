# NOW-022: PM kits through parts readiness and use

Garrett approved the complete parts-readiness journey, commit, push and an
internal APK delivered to S24 Downloads. Build on the existing Field Notes UI,
PM kit requirements, work orders and parts costs. Original inventory area 12.
Durable semantics: `../decisions/0015-parts-readiness.md`.

## Contract

- New checklist-linked work snapshots its PM requirements. Existing jobs may
  explicitly import the current kit once. Standard-kit edits never rewrite jobs.
- Managers edit a job's required quantities and add requirements independently.
- The Checklist library opens the existing PM kit editor for company managers;
  shared kits remain owner-managed. Copies and new publications inherit the kit.
- Stock belongs to the provider or a client company, with named locations,
  minimum levels, unit cost and an immutable transaction history.
- Managers link requirements to stock, reserve available quantities, request
  shortages, record ordering and receive partial deliveries. Reservations cannot
  oversubscribe stock; a receipt does not silently reserve the delivery.
- Assigned workers issue reserved stock into existing job parts/costs, return
  unused issued quantities and release reservations. Internal costs remain
  separate from provider invoices. Closed/billed work cannot change stock use.
- Receipts update weighted average stock cost. Issues record the selected stock
  item and cost; returns reverse its recorded job cost. Review/closure releases
  remaining reservations, and outstanding deliveries remain receivable.
- Changes are atomic and replay-safe, with checked revisions and server-side
  roles/company boundaries. A failed or uncertain save keeps its replay ID for
  retry; stock transactions require a connection and never claim offline success.
- Existing stock rows are retained as provider stock. Existing jobs, parts and
  invoices are retained. This slice does not place orders with external suppliers.

## Acceptance

Two filters required, one on hand: snapshot kit, link location stock, reserve one,
request/order/receive another, reserve it, issue two and return one. Verify stock,
reserved counts, net costs and audit trail after every transition. Verify kit
edits do not alter the job; retries do not duplicate receipts or usage; another
company cannot read or change records; two jobs cannot reserve the same stock.
Render and exercise native work-order and stock screens, including Spanish,
large text, empty/error states. Run Flutter and SQL checks, deploy only to Next,
inspect APK identity and compare source/phone SHA-256. Device installation and
physical interaction are separate from delivery.

## Verification and activation

Both additive migrations are active only on Vortice Next:
`20260907210000_parts_readiness.sql` and `20260907213000_pm_kit_continuity.sql`.
The first full Flutter run passed 592 tests after correcting a displayed-version
mismatch and test-only HTTP-response/scroll fixtures. Focused SQL follow-up
checks company-kit privacy and publication continuity as well as the stock flow.

The final connected run passes all eight stages in
`outputs/parts022-ygfLiFoL/NOW-010-parts022.json`: manager PM-kit editing, job
snapshot/opening count, reservation/shortage request, order/receipt, Spanish dark
screens and forms at 200% text, mechanic use/return, approval/history and another
company's denial. Native screenshots are under that run's `screenshots/audit010`.
Two filters (one at USD 10 and one received at USD 12) issue at weighted USD 11
each; returning one restores stock and leaves USD 11 of internal parts cost.

The first connected attempt completed the six business stages but its final
isolation login used an unconfigured test email. Its exact fixture was removed;
the corrected run above passes with the configured second-company account.
Physical Android installation/interaction is not established by these tests.

Final verification passes clean analysis and 593 Flutter tests with zero skips
(`outputs/NOW-022-verify.log`). All 21 hosted SQL suites pass with both migrations
active. The successful run's exact asset, procedure, job and stock fixture were
removed with unrelated counts preserved; receipt:
`outputs/parts022-ygfLiFoL/cleanup-20260908T010034Z-6f01a0a1.json`.
The initial cleanup request timed out; remaining fixture IDs were checked before
retrying. Its unfinished receipt is retained alongside the completed receipt.

## Build 26 delivery

Implementation commit: `02f72e835e4b195b9cc0ebbe245d42fcc5c80958`, pushed to
`codex/parts-readiness`. The guarded internal Android build passes, with version
`1.13.0+26`, ARM64 and package `com.example.vortice_app_next`. Inspection verifies
the Next backend/Firebase, signing certificate, notification service, recovery
link, parts workflow and equipment assets. The build reports a future Kotlin
plugin compatibility warning for share_plus/shared_preferences_android; it does
not prevent this build.

Canonical APK: `outputs/builds/INSTALL-Vortice-Next-Build-26.apk` (129,263,817 bytes).
SHA-256: `5fd52cb179d524bf609cda1ba5b25fb580feb6807f73a45e988530e885f474bc`.
Inspection: `outputs/build26-build-verified.json`.

Delivered to the Samsung S24 (SM-S928W) at
`/storage/emulated/0/Download/INSTALL-Vortice-Next-Build-26.apk` on
2026-09-08 at 01:10 UTC (September 7 local evening). Remote SHA-256 matches.
Receipt: `outputs/build26-phone-delivery.json`. Not installed; physical Android
acceptance remains: open a work order's Parts readiness, import/edit requirements,
reserve/request/receive stock, then record use/return with an assigned mechanic.
