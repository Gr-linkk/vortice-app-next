# LF-003 — Independent saved checklist copies

## Authorized outcome and boundaries

Garrett requested another substantial retained-workflow port in parallel with
the current local CLI/service milestone. This slice lives on
`codex/local-procedure-library`, in a separately owned Git worktree/store, from
reviewed local maintenance `45380ae6b093a400e8a5f589b19359fe822bfc28`.
The retained reference is reviewed `eb2d0d4b5d9f582f4dce45d099fe1d15824c75bf`;
the relational checklist reference is `17542426e942e2d8cb5642ec1ff23a85a0c51c4a`.
No active coordinator, CLI, retained, or experimental-lab files are changed.

The accepted independent-copy, optimistic-save, immutable-publication and
source-attribution rules come from
[decision 0012](../decisions/0012-checklist-publications.md). The single-office,
frozen-inspection and recovery limits remain those of
[decision 0022](../decisions/0022-local-inspection-authority.md).

This is an independent-copy workflow. Each copied draft can publish once as a
fresh independent v1 checklist. It has no procedure-family versions, retirement,
archive, current-version resolution or automatic rewrite of issued work. Only
the existing local check, number and text definitions are supported. Richer
retained guidance/photo/critical rules are not imported or silently discarded.
Inventory, billing, live import, remote workers, extra office authority and
multiworker policies remain outside this authorization.

## Precise parity and selected gap

| Workflow | Reviewed local maintenance and current LF-002 | Retained workflow | This slice |
|---|---|---|---|
| Equipment | Create equipment with serial and explicit meter unit | Richer equipment management/history | No equipment policy change |
| Procedures | Publish immutable v1 definitions; inspect frozen job content | Library preview, attributed copies, durable optimistic drafts, family publication/retirement | Preview existing publications; durable independent copies; one new v1 per copy |
| Inspection preparation | Choose equipment/publication; freeze full snapshots | Current publication selection and broader planning | Reuse existing prepareWork authority and exact chosen publication |
| Work planning | Immediate prepared inspection; LF-002 progress/review already underway | Calendar, assignment, recurrence, due/blocked state | No planning policy change |
| History | Exact submissions/review; LF-002 current/history navigation | Search/filter equipment history and richer event types | Preserve all existing versions and receipts |

The selected missing workflow is reusable saved checklist preparation. Broader
equipment and scheduling changes require policies or touch the active progress
milestone. True family publication would require changing catalog selection and
service authority; it is deliberately not claimed by this bounded copy port.

## Code and persistence contract

New pure domain code in `lib/procedure_library.dart` checks source publication
hashes, creates independent draft/step identities and preserves exact source
ID/version/hash/title attribution. Unfinished drafts may have empty titles,
labels or step lists; publication still uses the existing stricter template
validator. Missing readings/limits, zero, units, required and allow-NA semantics
remain explicit. There is no unit conversion or inferred zero.

`lib/procedure_library_store.dart` extends the existing LabStore without changing
its schema, core implementation or catalog shape. One office-only
`procedureLibrary` settings entry stores versioned drafts and durable command
receipts. Commands serialize on the existing queue, check office authority when
they execute, compare revisions atomically, and commit draft/receipt/catalog/event
changes in one SQLite transaction. Exact retries return the original result;
reusing an operation ID with changed arguments is rejected. Finalized drafts
cannot be edited or republished under another command.

The existing generic complete office backup includes this settings entry.
The public phone bundle remains the strict existing catalog plus inspection
documents, with no draft/receipt settings. The CLI's existing read-catalog shape
therefore stays unchanged. Compatibility is checked through the exact public
bundle/catalog shape and existing strict phone import; a separate live CLI smoke
remains with the CLI/service owner. Older readers can retain office-only draft
settings in a complete backup, but cannot edit copies or interpret their receipts.
A matching LF-003 version is required to resume/edit saved copies. Unsupported
or inconsistent library state
fails closed at the library boundary rather than being reset.

New library, editor and publication pages own the UI. The sole existing UI edit
adds an office-only Checklist library link in checklist/work preparation. The
ordinary route is preparation → library → preview → make a copy → save → reopen
→ publish → choose equipment → prepare inspection. Publication shows independent
v1 and source attribution; it does not claim to update the source procedure.

## Parallel ownership

Six independent workers cover domain, persistence, new UI, adversarial
domain/store tests, rendered workflow tests, and read-only review. Root owns the
narrow preparation entry, backlog/specification, final verification and commit.
Workers use GPT-6.1 Sol Ultra; the available tool has no separate Fast selector.
No worker owns existing sync, service, CLI, backup, core-store or progress files.

## Acceptance and integration gates

The focused domain/store gate passes 25 tests (8 pure domain and 17 SQLite/store),
including simultaneous saves and same-command concurrency; stale editors;
argument capture while queued; exact/changed/cross-command replay after later
saves, publication and restart; office checks at queue execution; malformed and
rehashed history; transaction rollback; deep returned-data immutability; unchanged
source/job/document bytes; absent/null/empty/zero units and limits; phone denial
and strict catalog import; and complete same-identity backup/restore with original
snapshot and command results, excluding changes made after the backup.

Final guarded `scripts/local-maintenance.sh verify --reporter expanded` passes:
enforced-lockfile offline dependency resolution, clean analysis, 4 native
Automerge tests/native build, and all 197 Flutter tests. The separate identity
guard and 3 Python boundary assertions also pass. These gates ran in this owned
checkout with copied offline tools/cache; the Flutter runner and existing
synthetic fixtures used loopback only. No dependency, signer, application-ID,
SQLite schema, public catalog or native protocol change was needed.

The ordinary rendered route is preparation → Checklist library → preview →
copy → save → return/reopen → publish → select equipment → prepare. Both
412 × 915 at 1× and 2× text also exercise invalid limits without losing input,
unfinished-publication gating, actual stale saves with confirmed reload, and a
concurrently published draft reloading read-only. Title-only saves preserve
the exact missing/null/empty/zero step shape. Visual review found and fixed raw
reference crowding, clipped selected equipment identity and long optional bound
labels: source title/version stays visible; full reference expands on request;
the selected equipment name wraps; and bounds use concise optional labels.

The final focused rendered suite passes both workflows and emits 42 stable PNGs.
Source-summary/full-reference expansion and selected-equipment geometry are
asserted. Root inspected the revised 2× preview, selected equipment, numeric
limits and prepared-completion images. PNGs and verification logs remain ignored
local evidence under `outputs/lf003/`.

Independent read-only source review: **PASS**, with no blocking security/runtime
finding. The reviewer checked original publication hash/new independent step IDs,
office checks inside the queue, transaction-local state/revision reads, complete
receipt reconstruction and exact replay before stale checks, atomic
draft/receipt/catalog/event commits, finalized guards, frozen snapshots, captured
UI retry arguments, reload after stale/finalized edits, exact missing-value
preservation and the final attribution/equipment displays. The parent's separate
integration audit remains a coordinator gate.

Integration can preserve existing LF-002/service work by adding the isolated
modules/tests, applying the small `preparation_page.dart` navigation hook and
retaining both backlog/spec entries. No existing core store, sync, backup,
inspection/progress, service or CLI file is in this diff. Rerun the same local
gate and the service/CLI owners' compatibility tests on the actual chosen
combined destination. Keep the pre-integration commit and complete same-identity
backup as rollback checkpoints before any separately authorized real-data use.

This local source milestone will be offered to the main coordinator for explicit
integration and independent audit. It is not a merge, push, deployment, APK or
phone-installation receipt. No physical device or real-world offline acceptance
is inferred from synthetic tests. Existing CLI/service acceptance and release
decisions remain with their owners.
