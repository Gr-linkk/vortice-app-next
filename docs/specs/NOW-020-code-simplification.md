# NOW-020 — Code simplification

## Scope

Requested September 7: simplify the code without losing functionality, verify,
build, push and deliver an APK to S24 Downloads. Base: Build 24, `920a709`;
branch: `codex/code-simplification`.

## Changes

- Reuse one asset-to-SQLite mapping across asset lists, client fleet lists and
  work-order asset-name caching. Account guards and cache fallback rules stay
  at their existing call sites.
- Reuse the identical loading, error and empty states on the three client
  dashboards. Preserve all text, colors, spacing and role-specific actions.
- Reuse the identical error/retry panel for clients, engines, hour logs,
  organization codes and reminders. Each screen retains its provider retry.
- Reuse invoice download-directory creation and file writing for PDF and Excel.
  Generation, frozen invoice snapshots, filenames, sharing and opening remain.
- Delete the unreachable retired meeting-request screen/provider/model; preserve
  the existing redirect for stale meeting links. Delete unreferenced subscription
  prompts/gates and unused asset-type, assignment, imported-document and catalog
  models. Active capability checks, model replacements and database tables stay.

## Review coverage and boundaries

Scanned every handwritten Dart file for duplicate blocks and followed the full
import/export/part graph from `main.dart`. Checked deletion candidates against
app, test and tool references. Identical moved blocks were compared before edits.
Similar parts editors and checklist headers have distinct defaults, validation,
labels and layouts; merging them would require more configuration and carries
unnecessary behavior risk. Keep those differences explicit. Keep test-used policy
helpers, generated code for active models, and deployed migration history.

This pass does not claim every possible simplification has been exhausted or
that automated verification proves physical-device acceptance.

## Verification and delivery

- Guarded `scripts/verify.cmd` passes: clean analysis, 583 Flutter tests, zero
  skips. All 571 existing tests remain; ten new checks exercise failed-load retry
  on the five affected screens in English/Spanish, and two verify PDF/Excel file
  names, bytes, replacement and Downloads/document-directory fallback. Log:
  `work/simplify-verify.log`.
- Direct review found no actionable regression in the changed paths. Exact
  duplicate removal plus nine unused source files removes 729 net production
  Dart lines. The only dependency metadata change makes the already-installed
  path-provider platform interface a direct test dependency; no version upgrades.
- Backend/service code and deployed migrations are unchanged; no service
  deployment or database mutation is required for this refactor.
- Build 25 (`1.12.2+25`) is built from `e4c5560`. Inspection verifies the existing
  Next application ID and signing certificate, ARM64, Next backend/Firebase,
  notification service and recovery link, and all 19 bundled artwork files.
  Reports: `outputs/build25-build-verified.json`, `outputs/build25-signature.txt`.
- Delivered to S24 (`SM-S928W`) Downloads on September 7 as
  `INSTALL-Vortice-Next-Build-25.apk` (129,211,021 bytes). Both local and phone
  SHA-256 are `84b73dfe73bf3c148273bbafd0047019a3c6cbed8970e0854ef3989443b0d723`.
  Receipt: `outputs/build25-phone-delivery.json`. The APK was copied, not
  installed; physical-device acceptance remains separate.
- Implementation and delivery documentation are pushed to the independent Next
  repository on `codex/code-simplification`.

## Connected E2E follow-up — September 7

Garrett requested connected end-to-end regression checks after delivery. All
eight journey files pass against hosted Next: 48 saved-workflow steps plus seven
custody/inspection checks. This covers asset/component saves, requests, provider
reporting and invoice issue/void/correction/payment, maintenance and faults,
handover/history, private evidence, offline SQLite restart/retry/account isolation,
planning/conflicts, internal orders and checklist publication/versioning.

The route audit passes 130 entries across six roles in each configuration:
English/light/100% text and Spanish/dark/200% text. All 260 entries have zero
error labels, framework/provider failures or unfinished loaders, and all requested
destinations were reached. Representative invoice, fault and dashboard screenshots
were inspected, including the large-text dark dashboard.

One initial direct-workflow assertion ran after server persistence but before the
save sheet closed. The failure screenshot showed the still-open sheet; the fault
was already resolved in hosted persistence. The test now waits a bounded time for
sheet dismissal and reveals the lazy list row before asserting the next action.
All six original steps pass on retry, and the resolved screenshot shows the
availability action. Focused Dart analysis passes. Application code and Build 25
are unchanged; no replacement APK is needed.

Both attempts were cleaned separately before proceeding. Complete receipts verify
removal of nine synthetic assets, three procedures and 26 evidence objects, with
all 11 unrelated-count categories preserved. No app regression was found in this
coverage. Physical APK installation, camera/permission dialogs, OS process kills,
native file sharing/downloading and actual notification receipt/taps remain
separate device checks.

Evidence: `outputs/build25-e2e-report.md`, `outputs/build25-e2e-summary.json` and
the full logs/screenshots/manifests under `outputs/e2e/build25-sktdg36v` and
`outputs/e2e/build25-z5hj5zbd`.
