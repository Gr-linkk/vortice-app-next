# ARCH-001 — Implement the architecture audit

Authorized September 29, 2026. Status: pre-integration cleanup implemented and
verified. Full runtime migration and public release remain open.

## Purpose and source

Garrett asked for the original DHH-style architecture/code audit to be fixed
alongside the large local-first change. The scope includes the retained
application as well as independent Sync Lab review. The desired result is a useful complete
free/open maintenance tool with understandable code and simple licensing.
Income is optional. The work must preserve the existing mechanical/domain
guarantees and reduce the places a maintainer has to change one behavior.

The original audit was prepared against Build 40 (`78b9c62`), with seven numbered
findings and a reproduced provider retry defect. The local artifact is
`/home/garrett/Documents/ChatGPT/Vortice app/outputs/architecture-audit-2026-09-28/Vortice-Architecture-and-Product-Audit.md`.
This document carries its actionable scope into tracked project knowledge;
the ignored local report is background evidence, not the live backlog.

## Baselines and ownership

- Retained application: independent repository `Gr-linkk/vortice-app-next`,
  Build 45 `9a3b5d3`, delivered from `codex/canada-play-readiness` in
  `/home/garrett/projects/vortice-app-next`. The cleanup branch is
  `codex/architecture-cleanup` in its own worktree. Preserve French, native CAD,
  web/offline support, historical records and existing deployment safeguards.
- Isolated experiment: `codex/local-first-lab`, from the Build 40-derived
  planning commit `b75b711`; native integration milestone `3745d37`, offline
  persistence `0ae4bd7`, sync/approval milestone `ff41931`.
  The task “Review big change idea” owns lab implementation/device testing.
  The architecture task owns retained-app remediation and independent review.
- Preserved return point: `pre-local-first-build-40`, with the existing
  `codex/cad-currency` checkout intact. Build 45 is also preserved in its own
  existing checkout. Nothing here resets either branch or migrates real data.
- An integration base beyond the isolated experiment is not yet selected.
  Do not merge/copy the lab or the newer product implementation automatically.
  Neither a working prototype nor a review finding authorizes a production cutover.

Both inspected clones have only the independent repository as origin. The old
original repository is outside this work. Backend deployment remains separately
guarded under AGENTS.md; this scope has not performed one.

### Backlog identifier reconciliation

| Reference | Meaning in its owning branch | Integration treatment |
| --- | --- | --- |
| Build 45 `NEXT-011` | Canadian billing/company money | Retain this delivered history and source links. |
| Lab `NEXT-011` | Local-first research and isolated Sync Lab | Refer to it as lab NEXT-011 in cross-branch discussion. |
| Build 45 `NEXT-012`–`NEXT-014` | Play preparation, French, companion web | Preserve; these are not unused identifiers. |
| `ARCH-001` | This architecture remediation | Distinct shared reference for cleanup and migration checks. |

At integration, select an unused identifier for the lab in the destination
backlog, update all incoming local links, and record the historical alias.
Do not silently combine unrelated NEXT-011 specifications or erase completed
billing work to make a merge appear clean.

## Disposition of the seven audit findings

Garrett clarified that cleanup should stop where the big change would make it
throwaway work. The implementation task confirmed that hosted identity,
SQL/RLS and cloud delivery are replacement targets. That changes the earlier
sequence: a readable current SQL wrapper chain is no longer the next milestone.
[Decision 0020](../decisions/0020-maintenance-domain-and-runtime-boundaries.md)
and [the architecture guide](../ARCHITECTURE.md) record the resulting boundary.

| Finding | Work done here | Deliberately remaining |
| --- | --- | --- |
| 1. Unsafe/duplicated retry handling | Shared rejection policy; exact retries across provider actions/reports, parts, import and shared RPC. Report command freezes nested input. | Existing internal queue remains; lab maintains its own durable exact-retry contract. Neither transport should invent new command IDs on ambiguous outcomes. |
| 2. SQL wrapper/function-text patches | Preserved history and established 51-contract/restore baseline. | **Deferred:** cosmetic consolidation of hosted SQL is throwaway under the selected target. Fix concrete defects as needed; port business acceptance scenarios when the local workflow is selected. |
| 3. Parallel work execution | Internal and provider paths now use portable checklist/report completeness rules with one source of truth. | **Deferred:** merging the entire hosted work engines. The next local workflow must use these requirements while keeping inspection, publication and financial policy explicit. No fourth workflow engine. |
| 4. Membership translated into legacy roles | Portable capability policy; legacy route projection isolated in a named hosted adapter, with access fixtures. | **Deferred:** rewriting hosted identity/RLS/routes. Retire the adapter with the hosted runtime. Device enrollment is not person membership; multi-worker authority is outside the lab. |
| 5. Screens own persistence/commands | Provider report draft/retry state moved into a work-specific controller; immutable typed command; plain-Dart domain checks added to guarded verification. Checklist rules no longer require importing a widget. | Large existing screens are not all rewritten. Extract boundaries when their actual workflow migrates; do not add a universal repository/controller framework. |
| 6. Private deployment/licensing friction | Syncfusion signature pad/core removed with no new package. In-app ink preserves PNG callback, clear/save and error recovery. Runtime license inventory regenerated. | Lab owns independently running local runtime/build/recovery gates. Inherited code/asset rights, project license and public packaging remain open; dependency removal does not settle them. |
| 7. Breadth outruns repeated use | Selected one complete equipment/work/evidence/review/history/recovery path as the next integration scope; preserved deferred product features. | Real maintenance use and a second independent crew are not established by synthetic tests. No speculative billing, inventory, plugin or AI expansion. |

This resolves the sensible cleanup scope before integration, not every historical
architectural issue. Deferred items have a named replacement boundary; they are
not silently closed. No merge, dual-write bridge or production cutover follows
automatically from a passing lab.

## Milestone A — Shared write-outcome policy

The Build 40 provider/report defect remains present in Build 45. Both clear a
saved pending operation on every `PostgrestException`. That dependency exception
also represents gateway failures. Parts used a five-character-code heuristic,
while maintenance used a separate known-code list and other forms depended on
that maintenance-specific helper.

Create `core/rpc_failure.dart` as the single classifier. A known database
rejection allows the user to correct/revise input; an uncertain response retains
the exact saved operation. Invalid data/constraints/access and known domain or
serialization/deadlock errors are rejections. Gateway errors, unknown codes,
and explicitly unknown SQL completion (`08007`, `40003`) are uncertain.
PostgreSQL describes these codes in its
[error-code reference](https://www.postgresql.org/docs/current/errcodes-appendix.html).

Move existing maintenance callers to that core policy, and apply it to provider
actions/reports, parts, fleet import and the shared retryable RPC helper. Keep
queue availability and online-only approval/scheduling rules intact. Preserve
existing account keys, payload shape, backend RPCs and operation identifiers.
This does not introduce a second queue or a generic command framework.

Tests must exercise actual uncertain/rejected saves and storage/reopen behavior,
not just compare a source list of error codes. Reuse the ordinary rendered
provider workflow at phone size/large text for affected UI acceptance. Record
automated, rendered and physical checks separately.

The implemented slice also keeps an earlier unconfirmed report command when a
later retry fails its local evidence preflight: that later failure cannot prove
the earlier request rolled back. The editor no longer labels that situation as
definitely unsubmitted. Provider action persistence checks successful local
storage and the current account before sending. A successful action dismisses
its old error toast so it cannot cover the next action after recovery.

### Rendered workflow evidence

The actual provider Work order panel was rendered at 412 x 915 logical pixels,
with 1x and 2x text. The path was Pause my labour -> uncertain response -> Retry
action -> Continue service report -> Save to server -> uncertain response ->
Retry request -> return to the work order. Tests click the rendered controls;
the screenshots were visually inspected. This is a fixture-backed Flutter
rendering check, not a hosted/network or physical-phone acceptance claim.

Observed and fixed: a stale failure toast survived a successful retry and could
intercept Save to server on the next screen. Recovery now clears that toast;
an assertion verifies dismissal after a successful corrected action. Pending
actions and reports remain frozen with an accessible retry control. The report
fixture intentionally contains an out-of-range answer: Save to server stores a
draft; it does not bypass Submit for review completeness requirements.

Snapshots: ignored `outputs/architecture-cleanup/rendered/`. The action captures
show persistent retry controls after the temporary failure toast expires.
Report captures show disabled editing and the active Retry request at both
text sizes. Fresh physical acceptance remains open; this task has not displaced
the lab task's use of the S24 or installed another build.

## Milestone B — Portable rules and small runtime adapters

`lib/domain/` contains checklist value rules, report readiness, company
capabilities and immutable report commands. The rules compile and run under
plain Dart. `tool/verify_domain.dart` exercises linked photos, backwards/invalid
meters, out-of-range results, unresolved failures, command immutability and
capability boundaries; it also rejects domain imports from plugins/UI/adapters.
The guarded verifier runs it. Existing internal/provider and checklist-builder,
operator, history and submission paths call the same rule source.

`ProviderReportDraft` owns load/save, original operation/revision, confirmed
rejection, uncertain retries, flush/clear ordering and account checks. The report
widget keeps input, presentation and navigation. Failed local writes cannot send
an unpreserved command; later writes can recover. A damaged saved command stays
blocked and retained instead of being overwritten with older server data.
The editor explains the retained draft, offers Reopen saved draft, and stops
the loading indicator after a failure; saving stays disabled until it can read
the preserved data. A damaged command may still need separate recovery.

`hostedProfile` contains the old member-to-route translation. It does not change
server permissions or migrate accounts. Membership capabilities remain separate
from route roles. Tests preserve old profiles and ensure owner-shaped routes do
not manufacture owner capabilities for a modern operator.

## Milestone C — Signature dependency removed

The isolated signature pad now uses Flutter drawing primitives and exports an
opaque black-on-white PNG. Normalized strokes survive resizing; clearing removes
prior ink, export is independent of the light/dark theme, and a failed save
retains the drawing for retry. Save/clear are disabled during export. The sheet
scrolls and the title/actions wrap for large text. Existing callback/upload
contracts and old saved image bytes are unchanged.

No replacement dependency was added. Syncfusion's signature pad and core are
absent from `pubspec.yaml`, the lockfile and the resolved runtime graph. The
regenerated inventory contains 154 reachable packages with available license
text and no flags from the inventory script. That is not a native binary SBOM,
a license classification, or clearance of inherited/asset rights.

### Rendered signature acceptance

The ordinary Service report action bar opens Technician Signature, then draw ->
clear -> draw -> save -> return to report. Checks run at 412 x 915, normal English
light theme and 2x French dark theme. Exported PNGs are decoded to verify visible
ink, opaque white background and removal of the cleared stroke. A failed save
keeps ink and supports retry. Screenshots are in
`outputs/architecture-cleanup/rendered/signature-*.png`.
These are actual Flutter widget renders with fixture report persistence; no
new build was installed on the phone used by the lab task. All three signature
PNG/clear/retry cases also pass in headless Chromium via `flutter test --platform
chrome`; browser tests use the harness fonts, while inspected native snapshots
use the bundled Roboto/Material fonts. The first browser attempt stalled in the
native-font preload helper; browser checks now skip that screenshot-only setup.

## Next work that depends on the experiment

1. Review the final lab evidence and its unpassed gates (including actual LAN,
   as distinct from USB-forwarded transport). A two-device synthetic job is not
   the full maintenance application.
2. Select a destination base preserving Build 45, reconcile NEXT-011 identifiers,
   and scope one complete real equipment/work workflow against the portable
   rules and retained acceptance scenarios.
3. Define one write authority, import of IDs/history/evidence, rollback, and
   retirement of the old workflow. Do not merge two independently accepting
   authorities or delete existing billing/inventory/customer responsibilities.
4. Establish actual ordinary use, independent setup/restore and rights/notice
   readiness before calling the complete product ready for open-source release.

## Evidence and current limits

- Scope/baseline reconciliation: confirmed with the implementation task on
  September 29. Separate cleanup worktree created from Build 45.
- Milestone A: implemented. `pwsh -NoProfile -File scripts/verify.ps1` passes:
  clean analysis and all 841 Flutter tests, including 19 added regressions.
  Six targeted provider/widget tests cover the rendered phone/text-size paths
  above, exact retries after reopen/account changes, and confirmed rejection.
  Logs and the verification receipt are in ignored `outputs/architecture-cleanup/`.
- Fresh retained-backend baseline: 51 SQL contracts and an isolated archive
  restore drill pass through `scripts/test-database.sh --restore-drill`, using
  its explicit local PostgreSQL backend and a fresh Unix-socket-only cluster.
  The earlier audit's Docker-access limitation no longer blocks these checks.
  No hosted backend was used. This establishes a baseline, not SQL consolidation.
- Milestones B/C: full guarded verification passes with clean analysis, plain-Dart
  domain contracts and all 851 Flutter tests (10 added in this round). Targeted
  checks cover seven provider retry/reopen paths, three controller failure cases,
  three hosted-profile access cases and three signature save/render cases.
  Hosted SQL/Auth/delivery redesign is deliberately deferred under Garrett's
  latest instruction. No database behavior was changed in this round.
- No SQL/membership/work-engine replacement or public installation/license
  clearance is claimed. The remaining migration scope is above.
- Separate lab review LF-AUDIT-001: partial-photo/final-flush recovery repaired;
  independent nine-case probe passes against evidence store SHA256
  `e2d5b8951a78e3567dfb85cf840c5ef008a351e52f545ea4bec8c989f1dadee2`.
  This closes only that lab defect. Pairing/authority/full recovery remain separate.
- No production data, deployment, published license, repository visibility,
  phone installation or prior delivered build is changed by this scope so far.
