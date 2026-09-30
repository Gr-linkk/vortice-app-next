# ARCH-001 — Implement the architecture audit

Authorized September 29, 2026. Status: in progress; not a completed architecture
rewrite or a public-release authorization.

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
  planning commit `b75b711`; native integration milestone `3745d37`.
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

## All audit findings and closure requirements

| Finding | Retained-app work | Lab/migration relationship | Closure evidence |
| --- | --- | --- | --- |
| 1. Unsafe/duplicated retry handling | Use one conservative write-outcome policy; keep identity/payload through uncertain responses; allow correction after confirmed rejection. | Apply the same invariant to peer commands and submissions; native sync alone does not repair hosted clients. | Provider action and report reopen/retry, parts and shared RPC regressions; account isolation; uncertain SQLSTATE/gateway cases. |
| 2. SQL wrappers and function-text patches | Derive the current command definitions from replayed history; consolidate one critical command through a new forward migration with characterization contracts. | Document which business commands remain and which a future migration replaces. | A current readable command and equivalent permissions, revision, approval and replay results. No closure from simply omitting SQL in a prototype. |
| 3. Parallel work execution models | Define a common work-execution contract for checklist/evidence/labour/review while keeping billing and customer publication explicit policies. Migrate one real path, then retire redundant handling. | The lab's one-job fixture is a candidate boundary, not yet a replacement for provider/internal execution. | Ordinary job journey through the shared boundary, unchanged IDs/history, distinct provider billing rules, removed duplicate behavior. |
| 4. Membership translated into legacy roles | Inventory legacy profiles/routes/policies; make membership/capabilities canonical and contain legacy translation at a documented adapter. | Device possession must not become company ownership; multi-user access remains outside the current lab. | Historical account/access fixtures, revocation and tenant isolation; a named adapter retirement criterion. |
| 5. Screens own command/persistence logic | Extract small domain/command controllers and parse important response boundaries into explicit types. Avoid generic framework scaffolding. | Keep local storage, evidence, transport and approval independent; do not create another large screen-owned engine. | A behavior can be changed in one place; widget tests exercise outcomes while lower-level tests own persistence/retry. |
| 6. Private deployment and licensing friction | Replace Syncfusion where retained app code ships; document required dependencies, assets and rights; provide a supported independent bootstrap/build/recovery path. | New deployment direction is company-operated local-first; the earlier audit's proposed hosted packaging path is superseded as the target. | Clean installation without Garrett's credentials, complete ordinary job, restore/export, dependency notices. A project license cannot clear inherited rights automatically. |
| 7. Product breadth outruns sustained use | Freeze speculative expansion; make equipment -> work -> evidence -> review -> history obvious and reliable. | The experiment proves one technical path, not complete maintenance usefulness. | Garrett uses actual equipment work, then a similar independent crew can repeat it without database/developer intervention. |

No full finding is closed solely by this matrix, a plan, a green unit suite, or a
smaller prototype. A deliberately deferred item stays visible with its reason.

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

## Subsequent implementation slices

1. Characterize the retained approval command, generate a current-schema view
   locally, then consolidate one wrapper chain. Preserve deployed migration files.
   A local database/contract-runner failure must be resolved before asserting
   backend equivalence; a textual SQL rewrite alone is insufficient.
2. Extract the shared execution/command boundary and typed payloads from one
   retained workflow. Keep provider financial/publication policy separate. Do not
   create a fourth parallel work-order engine or change every model at once.
3. Move membership/capabilities behind a canonical workspace context with legacy
   adapter fixtures. Coordinate client and server retirement; no privilege widening
   or account reset is acceptable as a shortcut.
4. Replace the isolated signature-pad dependency and verify touch, clear/save,
   generated image and accessibility. Track inherited rights/asset provenance
   separately; do not invent a blanket MIT grant over other people's work.
5. After the lab proves its accepted gates, choose an integration base and map the
   complete first maintenance workflow, its approvals, meter context, checklist
   snapshots and evidence into the new authority. Define import, rollback and
   retirement before enabling it for real company records.

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
- Other retained-app findings: open. No SQL/membership/work-engine replacement
  or public installation/license clearance is claimed.
- Separate lab review LF-AUDIT-001: partial-photo/final-flush recovery repaired;
  independent nine-case probe passes against evidence store SHA256
  `e2d5b8951a78e3567dfb85cf840c5ef008a351e52f545ea4bec8c989f1dadee2`.
  This closes only that lab defect. Pairing/authority/full recovery remain separate.
- No production data, deployment, published license, repository visibility,
  phone installation or prior delivered build is changed by this scope so far.
