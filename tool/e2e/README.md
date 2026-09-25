# Connected workflow audit

These tests render real Flutter screens with hosted Next authentication and
persistence. They are outside `test/`: ordinary verification must not create
hosted records or need development passwords. Saved journeys can create test
push notifications for registered development devices; run them only with that
authorization. They do not prove physical Android or inbox delivery.

## Select one run directory

Run from the verified independent repository root with the configured Flutter
runtime. Reference the existing Next config; do not copy credentials. It must
contain the exact Next URL, anon key and `DEV_LOGIN_PASSWORDS` JSON map. Set fonts
to the Flutter SDK's `bin/cache/artifacts/material_fonts` directory.

```sh
export VORTICE_E2E_CONFIG=/absolute/path/to/config/vortice-next.local.json
export VORTICE_FLUTTER_FONTS=/absolute/path/to/flutter/bin/cache/artifacts/material_fonts
mkdir -p outputs/e2e
export VORTICE_E2E_OUTPUT="$(mktemp -d outputs/e2e/run-XXXXXXXX)"
```

Every connected test writes its manifests, step reports and screenshots into
`VORTICE_E2E_OUTPUT`. Existing filenames are retained. Without the variable,
tests retain the legacy `outputs/` location, but cleanup never implicitly scans
that historical directory. Use a fresh directory for every attempt.

## Rendered route and accessibility audit

```sh
VORTICE_AUDIT_APPEARANCE=light flutter test tool/e2e/full_app_audit_test.dart --dart-define-from-file="$VORTICE_E2E_CONFIG" --reporter expanded
VORTICE_AUDIT_APPEARANCE=dark flutter test tool/e2e/full_app_audit_test.dart --dart-define-from-file="$VORTICE_E2E_CONFIG" --reporter expanded
VORTICE_AUDIT_APPEARANCE=dark VORTICE_AUDIT_LOCALE=es VORTICE_AUDIT_TEXT_SCALE=2 flutter test tool/e2e/full_app_audit_test.dart --dart-define-from-file="$VORTICE_E2E_CONFIG" --reporter expanded
```

Appearance supports light/dark/system; locale supports en/es/fr (default en); text
scale must be positive (default1). Preferences are disposable. Results record
and assert the actual rendered locale and text scale, fail on provider/framework
errors including overflows, inspect English/Spanish error labels and check for
unfinished loaders. Screenshots and `routes.json` live under
`$VORTICE_E2E_OUTPUT/route-audit/<appearance>/<locale>-<scale>x/`.

The route inventory opens top-level/new-item screens and the first visible asset
for six roles. Recorded redirects need review; route entry is not completion of
a saved workflow or proof of every role-denial rule.

## Save, reopen, execute and deny access

Run sequentially. These use existing owner, technician, company manager,
company mechanic, operator and second-company development accounts with uniquely
marked synthetic assets.

```sh
for test in saved_workflows operations_workflows custody_workflows field_reliability direct_workflows planning_workflows internal_work_orders checklist_builder_workflows; do
  flutter test "tool/e2e/${test}_test.dart" --dart-define-from-file="$VORTICE_E2E_CONFIG" --reporter expanded || break
done
```

Inspect final exit status and step reports. Some steps continue after a failure
to collect independent findings; a completed step can still contain a failed
check in `issues`. A file only passes when its exit code is zero and issues are
empty. The tap helper waits for transient overlays but retains hit-test checks.

The journeys cover provider billing, maintenance/fault review, explicit fault
verification, custody/renewals, schedule conflicts, internal work, checklist
publication/versioning and cross-company data/evidence denial. Fixture setup and
some persistence assertions use API calls; these are connected test-host journeys.
Custody substitutes the photo picker with `fixtures/evidence.png` and verifies
actual uploaded bytes. Field reliability uses account-owned SQLite files,
closes/reopens them, and simulates lost connectivity/acknowledgements around the
production sender. It does not kill a physical Android process.

`recovery_contract.py` separately tests recovery with a disposable auth account
and no email. It does not prove app deep-link handling or inbox delivery.

## Exact cleanup

`fleet_import_calendar_test.dart` exercises Assets import through column mapping,
server preview, atomic save, service-baseline persistence and calendar creation /
booking / rescheduling. It uses the prepared modern fleet and service-owner demos
and writes exact `NEXT-007-fixture-*.json` cleanup manifests.
`fleet_import_xlsx_test.dart` reads real XLSX bytes with a test-selected file path,
then checks worksheet/header selection and existing-fleet duplicate rejection.
It never confirms a write. Both use the configuration and run-directory setup
above; system-picker interaction on a physical Android device remains separate.

After a failed file, inspect its evidence and clean up **before retrying**: a
synthetic labour timer can otherwise affect the next run. Keep the authenticated
Supabase CLI on PATH, inspect the selected run's manifests, then execute:

```sh
python3 tool/e2e/cleanup_fixtures.py --manifest-dir "$VORTICE_E2E_OUTPUT"
```

The environment variable is also accepted when `--manifest-dir` is omitted.
There is no implicit historical-directory fallback. Legacy manifests still work
when deliberately selected with `--manifest-dir outputs`; inspect which manifests
that directory contains first. `--receipt /path/to/new-receipt.json` selects a
receipt path; existing receipts are refused. By default each cleanup gets a
unique timestamped receipt in the run directory. A started receipt preserves the
before snapshot if cleanup fails; only `status: complete` proves the final checks.

For an isolated worktree whose direct network connection is unavailable,
`--connection-root /absolute/path/to/another-next-checkout` reuses its existing
Supabase CLI linkage. Both roots must have the sole independent origin and exact
Next project reference. Only CLI SQL queries use that connection root; manifests,
SQL and receipts remain in the selected run. No connection credentials are copied.

Cleanup validates exact UUID/name pairs, rejects outside-template references
including NULL-asset records, deletes only exact evidence paths and dependent
fixture records, restores the invoice immutability trigger within its transaction,
and compares unrelated counts. The Storage service key stays in process memory.
On failure retain manifests/receipt/SQL and investigate; do not delete broad
prefixes. Offline cleanup-option checks:

```sh
python3 tool/e2e/cleanup_options_test.py
```

Physical camera/permission prompts, mobile process-kill recovery and actual push
receipt/taps remain separate device acceptance. This harness does not measure
production-scale load capacity.

## First-time usability captures (NEXT-004)

`nontechnical_audit_test.dart` captures the five prepared modern demo roles,
using real primary navigation and read-only deep-page inspection. It also opens
an operator checklist without submitting it. The retained NEXT-003 demo work
record supplies completed customer/provider report context. It is an explicit
connected snapshot, not part of the normal unit suite or a new-user study.
Set `VORTICE_AUDIT_WIDTH` (default 390) and `VORTICE_AUDIT_TEXT_SCALE` (default 1)
to repeat at desktop width or enlarged text. Keep a fresh output directory for
every run; `usability-pages.json` pairs captured text with actual routes.

The direct-repair and parts-readiness journeys normally execute as
`client_mechanic@vortice.dev`. If that shared test actor already has unrelated
running work, `VORTICE_E2E_EXECUTOR=paradise@vortice.dev` explicitly selects the
configured test manager as the assigned executor. This changes the acceptance
claim: it checks a manager executing assigned work, not mechanic-role execution.
The default mechanic-specific parts permission assertion remains active in the
normal mode; the alternate mode checks its manager control instead. Preserve
pre-existing timers and verify recipient device scope before connected writes.

## Isolated mechanic and Canadian invoice acceptance (NEXT-011)

Existing demo timers belong to their saved work; do not pause or delete them to
make a test pass. `python3 tool/e2e/fixtures/prepare_isolated_executor.py` creates
one separate internal mechanic in the existing test company, refuses replacement
of its local config, and sends no email. Its password is stored only in ignored
private files. It is not added to the app's demo picker. Set
`VORTICE_E2E_EXECUTOR_CONFIG` to the absolute path of
`config/e2e-executor.local.json` to substitute that mechanic in connected tests.
The test reports identify the isolated actor; the role remains mechanic.

Run connected mutation tests **serially**, including fixture cleanup. Cleanup
checks unrelated record counts and should fail if another test changes them.
The current Supabase CLI may wrap query rows in an object; cleanup accepts both
that format and the prior row-array response, and rejects unknown shapes.

`native_cad_workflow_test.dart` creates uniquely marked work in the prepared
modern demo service company, executes and approves it, completes an explicit
synthetic issuer/tax profile, saves/revises/issues a CAD invoice, checks customer
and mechanic visibility, and exports the saved customer snapshot in French. It
refuses to overwrite an existing issuer profile. No real customer charge or tax
determination is made. After each attempt, run:

```sh
python3 tool/e2e/cleanup_native_cad.py "$VORTICE_E2E_OUTPUT/NEXT-011-native-cad.json"
```

The dedicated cleanup verifies the exact job title/company and synthetic issuer,
removes only that job/invoice/profile, preserves its existing equipment, restores
the invoice guard within its transaction, and records a verification receipt.
