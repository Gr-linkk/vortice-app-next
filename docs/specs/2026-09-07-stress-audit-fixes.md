# Stress audit corrections

Follow-up maintenance for NOW-016 and NOW-017, based on the September 7 full-app
audit. Work is isolated on `codex/stress-audit-fixes`, based on Build 21 commit
`8a93122`, to preserve the separate UI task.

## Scope

- Keep organization codes and role badges readable at 200% text scaling.
- Restore contrast for the organization-code add icon and label its tooltip.
- Keep telemetry date selection usable with enlarged Spanish text.
- Localize the existing provider work-order creation form and PM-parts preview.
- Fail connected route audits on provider errors and verify the actual locale
  and text scale applied to every screen.
- Retain the connected journey corrections for scroll settling, current Planning
  controls and expanded internal-work details.
- Isolate each connected run's manifests and require an explicit cleanup scope,
  preserving receipts and checking references outside the synthetic fixtures.
- Compare every original provider-report field during schema upgrades while
  allowing deliberately added columns.
- Retain three real SQLite queue stress regressions in the normal suite:
  concurrent flushes, rejected-subject isolation and account switching.

The historical walkthrough scoreboard and constant declarations do not establish
behavioral coverage. Their skip explanation is corrected; removing the obsolete
declarations is a separate pending approval after automatic review rejected
deletion. They must not be counted as verified product acceptance.

## Validation

- Guarded `scripts/verify.cmd` passed: clean analysis and **528 Flutter tests**,
  with the **204 historical declaration checks still explicitly skipped**.
  Log: `work/verify-final.log`. PowerShell wraps build-hook stderr as
  `NativeCommandError`; the helper completed successfully with exit code 0.
- Six native UI regression cases pass in English/Spanish at 320 logical pixels
  and 200% text. They reproduce the original overflows, translation gap and
  invisible add icon before the fixes; final checks exercise date selection,
  assignment/submission callbacks and template-load errors. Ten rendered
  viewports were inspected. Evidence: `outputs/audit-ui/REPORT.md`.
- Three retained real SQLite queue stress cases pass, including 300 operations
  with 25 concurrent flush callers and 200-operation rejection/account-switch
  scenarios. These use simulated transport, not hosted performance testing.
- All **18 SQL contract suites** pass against **25 migrations**. Both populated
  upgrade scenarios pass. The report-preservation probe accepts new columns and
  rejects changed text/timestamps, missing rows and changed null values. Evidence:
  `outputs/db-audit-fixes.md`.
- Three offline cleanup-option tests pass. Independent review of the UI and
  E2E cleanup/audit changes found no actionable regression in the inspected scope:
  `outputs/stress-audit-review.md`.

- All eight tracked connected journey files passed, comprising **48 workflow
  steps plus 7 custody checks**, with zero recorded issues. This covers provider
  invoicing, operations, custody, field recovery, fault execution, planning,
  internal work and checklist publication on the current fixes worktree.
- Exact cleanup completed: **8 synthetic assets, 3 checklist procedures and 26
  evidence objects removed**; scoped asset/work/request/media sets are empty and
  all **11 unrelated-count categories** match their before snapshots. Receipt:
  `work/e2e-audit-fixes/mutations-20260907T181845Z/cleanup.json`.

- The tracked full-app route audit passed **130 role/route entries** in dark
  appearance, Spanish and 200% text. Every entry records actual locale `es` and
  scale `2.0`; error labels, framework errors, provider failures and unfinished
  loaders are all zero. Evidence:
  `work/e2e-audit-fixes/routes/route-audit/dark/es-2.0x/routes.json`.

Detailed logs and renders are in ignored `outputs/` and `work/` in this worktree.

## Acceptance boundary

Connected tests use the authorized Vortice Next project and exact synthetic
fixtures. They may trigger the test alerts already authorized by Garrett;
server delivery does not prove phone receipt. Cleanup must leave the checked
unrelated counts unchanged.

This maintenance does not establish physical camera/permission, OS process
termination, closed-app push display/tap, keyboard/share or installation
acceptance. The earlier 36.91% local line-coverage measurement describes the
earlier audit snapshot; it is not a current coverage result or a promise of
complete execution coverage.
