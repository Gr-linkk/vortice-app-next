# LF-010 tested milestone receipt

Office coordinators can create an explicitly typed corrective draft with a
title and optional planning description, edit and reopen it, and associate one
or several reported faults on the same equipment. Each fault has one durable
association. The ordinary Home and fault-detail paths expose creation, linking,
current association and immutable original reporting history. Planning does
not start repair work or resolve a fault.

## Review target

- Branch: `codex/local-corrective-planning`.
- Checkout: `/home/garrett/Documents/Codex/2026-09-30/task-8/local-corrective-planning`.
- Reviewed LF009 base: `fc086136e1cf9cbfc4ab90c844d2cff62e2d2ea9`.
- Tested source: `209970a885f9d874ae3753605d958068512f4443`.
- Application tree: `db815554adb992e6df4e79a517d8d88408b46229`.
- This receipt is a subsequent documentation-only commit. Its binding is in
  `outputs/corrective-planning/Final-Source-and-Receipt-Binding.json`.

The [contract](LF-010-corrective-planning.md) records accepted semantics and
ownership. Model, persistence, UI and recovery owners worked in separate
checkouts; the coordinator selectively integrated their stable commits and
owned the existing navigation and startup guard. All implementation workers
have completed this increment.

## Durable behavior

Frozen UUID commands and immutable receipts/events support exact replay and
interruption recovery. Expected revision and hash fence edits and added links.
Batch links are atomic; reassignment, duplicate new-operation links and
cross-equipment targets refuse without altering history. Current drafts derive
from their receipts rather than a second mutable state copy.

The first successful planning freeze atomically selects office schema 3;
browsing does not upgrade a workspace. Backup manifest 3 preserves pending
intent, drafts and associations alongside existing inspection, fault, identity
and evidence data. Old schema/manifest 2 and legacy absence controls remain
usable. Seven SQL tables, inspection catalog/documents and phone bundles remain
unchanged. Existing scoped agent reads do not expose corrective drafts.

## Completed verification

| Gate | Result and source attribution |
| --- | --- |
| Full Flutter regression | 620/620, zero errors/skips, exit 0 and successful terminal result; exact tested source in a fresh isolated verification checkout |
| Analysis | No issues; exact tested source |
| Python and application separation | 53/53 and separation PASS; exact tested source |
| Node CLI/distribution | 298/298 at `8f24bf6`; actual CLI input tree byte-identical to tested source |
| Rust unit tests | 4/4 at `8f24bf6`; actual Rust and builder input trees byte-identical to tested source |
| Pure Dart work-progress gate | PASS at `3431523`; actual input graph bound to tested source |
| Compatibility before implementation | 4/4 on unchanged base `fc086136`: older reader refusal and intact old-format controls |
| Rendered workflow | 30 native widget screenshots at phone size and 1x/2x text, including ordinary Home/fault entry and restart |

The 89 added tests comprise 26 model, 19 store, 16 recovery, 14 UI, 11 startup,
two ordinary-entry and one existing-agent-read tests. The agent-read test
compares 56 successful responses across seven snapshots before/after planning.
The full regression also executes the startup guard and frozen old-reader
compatibility checks.

Independent integrated review passed within its **static code/integration and
evidence-inspection scope**, with no remaining material finding. Its one
startup finding was fixed in `51ae4bf`: legacy schema 0/1 must reject corrective
metadata/events just as schema 2 does. The reviewer did not independently run
the final 620-test suite. Parent functional/publication review is still required.

The first full attempt failed on missing private native/SDK fixture paths:
615/616 cases passed, with three setup errors and no successful terminal result.
Those logs remain evidence. All required fixtures were prepared before the
single corrected full run in a new isolated checkout; no product or test source
was changed to turn that failure green. The earlier startup owner's store file
differs from final by formatting and two optional trailing commas; the final
620-test run verifies the actual final guard.

## Exact runtime evidence

The final 620-test run used these private synthetic-test libraries:

| Library | SHA-256 | GNU build ID |
| --- | --- | --- |
| Rust | `582b0b00d645d9683512d4426729c633985302322232e3413fca4e7fe015d412` | `1d76e8b506aeac40765fdd6b03414d8a6a15f4d7` |
| SQLite | `2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5` | `8d00df9c57e6b97adef2df4ab31e492a6bcbd106` |

The store owner's 19 tests and positive agent-read test used reviewed 0.2.9
Linux Rust SHA-256
`8fdcb0f3f7a9e007a901a5d6d4cbe12542cde91ea04be7cd7791f8d959821e6b`,
GNU build ID `bca74ca037aa0e32dddcc868a5ea9932051e225f`.

Local durable evidence is under `outputs/corrective-planning/`, including
`LF010-Milestone-Receipt.json`, `Final-Full-Flutter-620-Receipt.json`,
`Final-Full-Flutter-Execution.json`, `Final-Full-Flutter.log`, fixture isolation
receipts, original failed-run logs, owner receipts and screenshots.
The successful full-run log SHA-256 is
`dffe24196041c130faa73b554c08542875fc4bc37df985dab96f76171b556f81`;
the independent integrated-review receipt SHA-256 is
`b8646ce29d94bde1a4a7a51e008d2ac92c55a5bb5a54b8bce2dcd222eb953c24`.
Disposable outputs, credentials and synthetic runtime workspaces are untracked.

## Remaining acceptance and preservation

LF010 has not been pushed or packaged. Source still inherits 0.2.9 metadata;
the reviewed 0.2.9 binaries contain LF009, not LF010. After parent acceptance,
a matching internal edition build needs its own identity, hash and packaging
receipt before physical, fresh-computer recovery and unassisted acceptance.
Rendered widget checks do not establish those physical gates.

Hosted Supabase rollback, retained fixes, default branch, LF009 checkpoints and
binaries, the phone and live workspace remain intact. No real grants or live
data migration occurred. LF008 remains excluded. Corrective execution,
repair approval/verification, fault resolution, equipment availability,
inventory/billing, maintenance advancement, multiworker and remote relay need
separate scope. There is no unresolved product decision blocking this tested
planning increment; full application conversion remains ongoing.

## Subsequent parent acceptance — October 1

After this receipt was sealed at `194a2f8`, parent scoped functional and
data-preservation review passed 89 fresh focused tests, clean changed-file
analysis, and 30 generated renders with seven critical screens inspected.
Create/edit/reopen, multiple same-equipment faults, one association, immutable
history, retry and recovery passed. The unchanged LF009 reader refused schema
3 while preserving file bytes; old-format controls passed. Tested source
`209970a` and receipt `194a2f8` have the same application tree. The original
pre-publication receipt and its evidence remain retained unchanged in history.

Named source publication is authorized after remote/delivery checks. Distinct
0.2.10 internal candidates are being verified separately; packaging does not
establish physical acceptance. Before any real update or migration, explicitly
explain older-edition refusal after the first planning freeze and preserve a
verified pre-upgrade backup. There is no workspace downgrade. Hosted Supabase
rollback remains a separate fallback and does not contain new local work.
