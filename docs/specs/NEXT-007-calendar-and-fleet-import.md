# NEXT-007: Calendar workspace and reviewed fleet import

Approved September 13, 2026. Base a47996a; branch codex/calendar-fleet-import.
Garrett requested implementation, end-to-end tests and free commits/pushes.
The approved proposal uses the existing Field Notes appearance and Work orders
navigation. This scope includes necessary additive Next database activation.

## Calendar

- Default normal Work orders entry to Month, with today selected. Explicit
  action shortcuts may select a work filter while retaining calendar context.
- Month navigation, Today and a compact view choice precede the month. Search,
  company work focus and lifecycle filters open on demand in one sheet.
- Select a date to view its agenda below; cards open existing authorized work.
  Preserve the selected date on return. Keep large text and narrow layouts usable.
- Create work for the selected day, then confirm time/assignee in the existing
  checked scheduler. Appointment date is not the completion deadline.
- Unscheduled work opens in context and can be booked for the selected day.
  Keep overlap warnings, stale-write checks, permissions and retry identity.
- Do not hide completed calendar records merely because the old initial filter
  was Open; make explicit filtering visible. Existing offline work remains readable.

## Import

Managers enter from Assets. Read files locally: XLSX (select sheet and header
row), CSV (comma/semicolon/tab delimiter), TSV, or pasted spreadsheet/text rows.
Column mapping handles different exported headings. Unsupported binary XLS,
PDF/photos and unstructured documents explain how to export a supported table;
no automatic OCR or external upload. Reject formulas rather than evaluating them.

Preview all mapped rows and their errors before a confirmed import. Users can
correct mappings or exclude rows; unknown equipment types need a deliberate
mapping. Preserve serial numbers as text, explicit meter units, date format,
component identity and service baselines. Repeated equipment rows can describe
multiple components; conflicting repeated equipment details are errors.

New equipment import does not overwrite existing equipment. Detect same-fleet
serial/name collisions and repeated file rows; server checks are authoritative.
Import a bounded batch atomically, with exact-payload replay identity and a saved
receipt. Failure or uncertain response must not imply success. Recheck active
company and management rights; never grant access to outside customer fleets.

Support equipment/component opening readings and optional recurring service
baselines. Service baselines initialize plans; they are not signed completion
records or bookings. Reuse existing checklist/plan authoring and selected bulk
plan setup, with explicit component/unit compatibility.

## Export/integration research

Official documentation checked September 13:
- MaintainX exports asset lists to CSV, with configurable hierarchy depth:
  https://help.getmaintainx.com/view-and-export-asset-data
- Fleetio provides CSV export/import and mapped columns; spreadsheet exports
  provide a practical migration boundary:
  https://help.fleetio.com/en_US/importexport-data

Generic column mapping supports exported tables without claiming a certified
connector or importing every source-system field. Live accounting/telematics
connections need a selected provider and credentials and are not this import.

## Acceptance

Parser tests: XLSX sheet/header selection, quoted delimiters/newlines, UTF BOMs,
formula rejection, text serials, dates/units, row/size limits and duplicate groups.
Database: own-company access, denied other-company/worker/anonymous writes,
atomic rollback, same/different replay, duplicate detection and correct baseline.
Rendered connected flow: Assets -> import -> map -> preview -> confirm ->
equipment/component/plan -> work creation -> selected-day booking -> agenda ->
open/return/reschedule. Test cancellation, rejected inputs, filtered/empty days,
English/Spanish and phone/large-text layouts. Remove only exact test fixtures.
Run guarded verification, local/hosted SQL as applicable and internal Android
build. APK delivery is not physical-phone acceptance.

## Results

Implemented for 1.18.0+38 on `codex/calendar-fleet-import`.

- Month is the default Work orders view. Selecting a day retains the calendar
  and shows its agenda. Search, company work focus and filters open in one
  sheet. List, Day, Week, Needs attention and Service plans remain available.
- Add work here carries the day into the checked scheduler; unscheduled work
  opens below the month. Own-equipment bookings default to 08:00 and 60 minutes
  for review, without creating a deadline. Customer work retains the existing
  date-only service model and creates its service date atomically for that day;
  it does not invent a timed appointment or resource booking.
- Assets exposes the local XLSX/CSV/TSV/TXT/paste import. Sheet/header selection,
  editable column/type mappings, explicit units and dates, grouped components,
  duplicate/exclusion review and published-checklist selection are implemented.
  See `docs/guides/import-equipment.md` for the user workflow and bounds.
- Atomic import and dated customer creation migrations were activated only on
  Next (`hkjpojobdbbtjkhaudki`). SQL rechecks management rights, company scope,
  duplicate identity, plan/checklist compatibility and exact retry payloads.
- Direct review covered route entry, active-company changes, parser bounds,
  multirow grouping, preview/commit/retry, native layout and backend permissions.
  Fixes included confirmed-rejection recovery, waiting for the profile at route
  entry, service-feature checks, exact checklist attachment and readable column
  labels at large text. This was direct review, not independent agent review.

Connected native Flutter acceptance:

- `outputs/next007-e2e-dh7gIzTj`: 4 completed steps, no issues. Assets → import
  pasted export → preview with no writes → commit → equipment/component/plan
  persistence → Month day selection → Add work here → booked day → detail/return
  → reschedule; duplicate preview rejection and other-company denial.
- `outputs/next007-xlsx-XNiZbjkn`: 2 completed steps, no issues. Picker cancellation,
  real XLSX bytes, worksheet/header selection and duplicate review. The automated
  picker returns the fixture file path; Android's system picker still needs
  physical-device acceptance.
- `outputs/next007-native-captures`: English/Spanish at 320 px and 200% text,
  including import mapping/review/rejection/retry and month/day agenda. Captures
  were visually inspected with the actual font and icon assets.
- Both mutating connected attempts have complete cleanup receipts. Each removed
  only its exact marked equipment, dependent work and import receipt. Unrelated
  asset/invoice counts were preserved.
- The full 48-file local PostgreSQL contract suite passed. The import contract
  additionally passed with a published checklist attached to its service plan.
  Parser and UI tests cover quoted CSV, UTF BOMs, Excel dates/formulas, unknown
  types/units, contradictory identities, exclusions and save recovery.

Final guarded `scripts/verify.cmd` run reports no analyzer issues, **748 tests
passed**, and `Project verification passed`
(`outputs/next007-verification-final.log`). The guarded Android build succeeded
(`outputs/next007-android-build.log`). Both Windows log captures include
PowerShell's NativeCommandError formatting for native stderr warnings; the
underlying verification/build completion and the actual artifact were checked.

Internal debug APK:
`outputs/builds/vortice-next-android-debug-20260913-171542.apk`
(209,928,174 bytes), version 1.18.0 / code 38.
SHA-256: `39c4fe5652cbf5aecc167d2f86a41fa068e891e43eabbf15b542c32389a2a266`.

These tests exercise rendered Flutter screens and real Next persistence; physical
Android installation, system-picker behaviour and phone acceptance are not claimed.
