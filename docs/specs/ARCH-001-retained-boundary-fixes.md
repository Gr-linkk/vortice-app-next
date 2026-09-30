# ARCH-001 — Retained boundary fixes

September 30, 2026. Authorized isolated implementation from retained
`102f630d1fc3489f85234e00532e8c73511e294f` on
`codex/retained-boundary-fixes`. Independent review is pending. No merge,
push, deployment, live database access, historical backfill, production cutover,
network configuration or physical phone testing is part of this change.
The retained architecture checkout, production checkout and separate Sync Lab
`f6608e10` are preserved.

The audit's `Remediation-Handoff.md` and `Extension-Findings.md` reproduced
one SQL privacy assertion and three Flutter assertions. The original probes
are copied unchanged into `test/audit/`; their fixtures use synthetic data.
These findings establish API boundary defects, not affected real customer data.

## Repairs

### Automatic stock release and ledger privacy

New migration `20260930120000_parts_release_scope_privacy.sql` replaces the
automatic release trigger and the private implementation beneath the existing
currency wrapper. Deployed migrations are unchanged.

The trigger derives expected stock ownership from the actual work order:
modern provider organization owner, managed client, or legacy NULL. Each
positive reservation must reference inventory in that scope. The event uses
the validated inventory's actual scope. Requirements stay locked; quantities
release once, advance the requirement revision and leave physical stock
unchanged. Requirement locks use ID order. Invalid stock ownership raises
`23514`, rolling back the status change and any earlier releases in that
statement. The trigger does not depend on the current actor's access helper;
the existing creator fallback for actor attribution remains.

The ledger now requires stock-backed events to join existing inventory in the
requested scope, using `IS NOT DISTINCT FROM` to preserve legacy NULL
semantics. The entire mismatched event is omitted, including payload. Legitimate
stockless events and the currency wrapper remain. The private implementation
and trigger remain unavailable for direct authenticated invocation.

Historical events are not relabeled. The read guard hides mismatched
stock-backed history before any separately approved repair; it does not restore
that history to the correct owner's ledger. Malformed existing positive
reservations now prevent finishing atomically. Investigating or repairing such
real records needs its own authorized work; these tests do not establish that
any exist.

`parts_release_scope_privacy.sql` proves ordinary modern-provider submit and
exact replay; owner history once; unrelated legacy/customer/company privacy;
historical mismatches in both directions; unchanged on-hand stock; authless
creator attribution; and legacy/managed-client compatibility. A valid release
followed by a malformed reservation rolls back all quantities, revisions,
events and work status. Supported `pending_review`, `closed` and `invoiced`
statuses are covered. Retained work status constraints reject `cancelled`;
that rejection is covered, then the existing dormant cancellation trigger
branch is exercised under a rollback-only fixture constraint. Product statuses
are unchanged.

### Cache reads after an account or permission change

`AccountJsonCache.readThrough` synchronously checks current account and captured
epoch after final awaited persistence, immediately before returning data. The
same guard covers awaited `save()`, used by the profile read before returning
its membership projection. Account identity is checked again after preference
loading and before fetching.

A successful read that discovers removed access or changed membership accepts
exactly its own epoch increment. It cannot absorb a separate permission
invalidation while clearing caches. Connection fallback must still match the
original read epoch, even if another read repopulates newer cache data.
Permission denial never becomes fallback; fresh-read policy, cache age,
account-scoped keys, drafts and outbox are preserved.

Seventeen added tests use deterministic preference/transport barriers and
cover final save, derived writes/removals, concurrent self-invalidation,
preference loading, offline fallback and valid refreshes. Six fail against the
unchanged base; all pass after repair. Call tracing includes profile membership
projection, readiness refresh and the repository callers of `readThrough`.
This is API completion coverage, not a claim of rendered cross-account
disclosure or hosted authorization bypass.

### Unsupported future SQLite schemas

Both database constructors and the account provider share the migration guard.
The first `onUpgrade` action rejects `from > to`; Drift does not complete its
version update after failure. No reset, drop, import or supported migration
work runs on that path.

Tests reopen populated schemas 9 and 999 through both constructors, attempt
reads and first-query writes, then retry writes on each rejected connection.
Version, complete logical schema, future-only marker, current rows, frozen
commands, evidence and report references remain unchanged. This is logical
preservation, not byte-for-byte file invariance: SQLite opening may affect
journal metadata. Synthetic populated versions 3–6 cover every supported
migration threshold; the unchanged audit companion covers version 7. Each
supported fixture upgrades and reopens with its existing values preserved.
Existing supported migration transaction boundaries are unchanged; this work
does not claim power-loss or failed-upgrade recovery acceptance.

## Local verification

The installed locked Flutter package graph and 45 generated Dart parts were
reused with the application package URI pointed at this isolated worktree.
No dependency upgrade or tool regeneration was needed. SDK cache locks and
private PostgreSQL sockets required sandbox access; all checks remained local.

| Check | Result |
| --- | --- |
| Unchanged cache/account/future-schema audit assertions | 3 pass |
| Unchanged frozen command and populated version-7 companion | 2 pass |
| Added cache regressions plus existing cache suite | 22 pass |
| Added future/reconstructed supported schema suite | 6 pass |
| Full retained Flutter suite | 879 pass |
| Analysis of `lib`, `test`, `tool` | No issues |
| Portable domain contracts and project guardrails | Pass |
| Operations-tool unit checks | 12 pass |
| Full SQL contracts plus isolated archive restore | 52 pass; restore pass |
| Existing populated Work hub scope/performance gate | Pass |

Detailed SQL logs and the final revision receipt are recorded under ignored
`outputs/retained-boundary-fixes/`. The repaired chain has
67 migrations, including exactly one new migration. Disposable PostgreSQL 17.11
uses private Unix sockets with TCP disabled. No hosted Supabase is used.

Reusable verification commands (from this checkout):

```sh
flutter test --no-pub test/audit/retained_boundary_probe_test.dart \
  test/audit/retained_command_upgrade_probe_test.dart
flutter test --no-pub test/core/account_storage_test.dart \
  test/core/cache_read_completion_test.dart test/db/schema_upgrade_test.dart
flutter analyze --no-pub lib test tool
flutter test --no-pub
dart tool/project_guardrails.dart --base-ref 102f630
dart tool/verify_domain.dart
```

Select `VORTICE_TEST_DATABASE_BACKEND=local` and the installed `VORTICE_PG_BIN`
as documented in `DEVELOPMENT-WORKFLOW.md`, then run:

```sh
bash scripts/test-database.sh --restore-drill
bash scripts/test-database.sh test/audit/sql/provider_release_privacy_probe.sql \
  test/audit/sql/customer_private_probe.sql
bash scripts/check-work-hub-performance.sh
```

The original two-session stock conservation/replay helper is reused from the
audit handoff in an isolated local runner pointed at an immutable archive of
the repair commit. The original probe source hashes are in the final receipt.
Fixture clusters, SQLite stores, SDK caches and generated access material are
disposable test inputs, not delivery artifacts.

## Bounded next work

Independent review should rerun the unchanged failing assertions and passing
companions against the stable repair revision, then assess any review findings.
It should pay particular attention to malformed reservation rejection and the
intentionally hidden historical event behavior.

Further regression preparation can exercise the ordinary profile/work-order
rendered flow with deterministic final-cache-write invalidation, extending API
evidence to actual screen behavior. This is a test candidate, not a demonstrated
new UI disclosure. Before future runtime integration, carry these exact retry,
privacy, stock conservation and populated upgrade acceptance scenarios into
the selected complete workflow. The current Sync Lab does not yet implement
retained customer/company authorization or inventory; that known integration
gap must not be treated as a newly discovered lab defect. No transfer, cutover
or historical repair is performed here.
