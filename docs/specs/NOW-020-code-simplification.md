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
- Build 25 (`1.12.2+25`) packaging, APK inspection and S24 delivery are in progress.
