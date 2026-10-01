# LF-005 — Complete displayed-answer repair receipt

Source verification is complete for `5f9a1100b01706e4c9c2463e3b2b3992d0c2617b`
on `codex/inspection-answer-state-invariant`, based on `ac2e158`.
Parent independent acceptance remains pending. The previously frozen 0.2.5 and
0.2.6 binaries remain blocked and byte-identical; this repair has no new binary.
The inherited application metadata is still `0.2.5+6`.

## Result and implementation

The parent found that selecting N/A or clearing an optional answer immediately
before Save, then typing through the enabled platform text client after decoded
installation but before repaint, lost N/A or revived an older Action result.
The editor now owns each complete nullable answer and its local event identity
independently of dirty persistence. Acknowledgement removes only matching dirty
identities. Decoded replacements take ownership through a guarded frame;
explicit local selections and human full-answer conflict choices take ownership
synchronously. Cancellation restores coherent painted fields and document bytes.
Original CRDT bases, queued capture/write/capture, unseen-version rejection and
exact-document submission fences remain enforced. Full rules are recorded in
[the displayed-answer specification](LF-005-displayed-answer-state.md).

Production commits are `ef1b3264b9e71fc121022bf14ee5b09ed84b9dd6` and
`8870d654b13a6eaec29bb4cb0fb608f9d5810565`. The separately owned final matrix
`71308633d8d08b73035b4c94665c43cfc9cd4080` was ported without changing its bytes.
Only the editor, its new matrix, backlog and LF-005 documentation differ from
the base. Hosted application, service/CLI, permissions, recovery, database,
native engine, platform projects and dependency locks are unchanged.

## Executed gates

- One complete native Flutter invocation: **474/474**, no failures or skips.
- Four unchanged parent probe files: **9/9**, including all three new prepaint
  selection/clear cases; their original bytes are preserved.
- New black-box matrix: **35/35** on the repair; the identical matrix on `ac2e158`
  gives 21 passes and **14 semantic failures**, with no setup/timeout failures.
- Whole local-app analysis: clean; offline dependency resolution enforces the
  lockfile; four application-boundary checks and portable progress/checklist/
  exact-history verification pass.

The matrix covers queued writes, acknowledgements, decoded installation,
prepaint input, rebuild/failure recovery, nullable clears, N/A, unknown/zero,
bounds, raw units, repeated inputs, remote result/raw changes, coherent rollback,
human complete-answer conflict choices and immutable submission. Inputs use
genuine enabled, focused, registered platform text clients and real pointer
controls. Independent state-machine, counterexample, source and matrix-evidence
reviews found no blocking issue.

Rendered review: **58/58 inspected**, with no blocking visible field/action
overlap. The complete source run captured 272 fresh PNGs; the independent review
selects 58 ordinary-workflow screens at
normal and large text, including inspection, preparation, checklist library,
office progress/review, agent connections/proposals and recovery. The N/A/clear
prepaint cases have widget/platform assertions; no dedicated PNG is claimed.
Some 2x context falls below the viewport or uses ellipsis. The normal-navigation
fixture lacks MaterialIcons and has faint route-transition captures. These are
explicit evidence limits; rendered review is not physical or unassisted acceptance.

Unchanged-object gates retain their earlier execution evidence: Rust 4, Node
298, Python 35, normal office-host acceptance 112 assertions/14 actual CLI calls,
legacy CLI 21 checks/1 actual call, and extracted-package CLI 98 assertions/18
actual calls. A separate 154-check publication review verifies source objects,
the service import closure, runtime CLI inputs and evidence hashes. These are
retained gates, not new invocations or acceptance of an old blocked package.

## Exact source and native test binding

| Binding | Value |
| --- | --- |
| Full frozen source tree | `86832eb52d82499ed06039c2a27a24516a5e9639` |
| Local application tree | `197ddb0cf902c4b14aec40f4980385b9504fde24` |
| Editor SHA-256 | `cc95f23790b7ac3ba0c5d2642e451c377f1e88a10abcb15d2da91f47b174aa37` |
| Matrix SHA-256 | `2d25dfa54fb6dbc2c370f6d800886ce5d628c7e97138724adc4d93cfeedb3e19` |
| New unchanged parent probe SHA-256 | `bb2aa9dd01d2317cce725b42aac1db61ce49a8749b0e5e8b149ec7fc8f8d15fd` |
| Rust test library SHA-256 | `1b03d11510bc0146fe63f69e41346a64e315b20cf457df94273e21b9e394fe68` |
| Rust ELF Build ID | `86d1a03dc24b3da5efa61f7178c1001a6f8ec493` |
| SQLite test library SHA-256 | `2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5` |
| SQLite ELF Build ID | `8d00df9c57e6b97adef2df4ab31e492a6bcbd106` |

Local evidence is under `task-8/answer-state-invariant-full-gate/outputs/`,
`answer-state-matrix/outputs/answer-state/`, `answer-state-invariant-review/`,
`answer-matrix-review/`, `answer-state-render-review/` and
`answer-state-publication-review/`. Important evidence SHA-256 values:

| Evidence | SHA-256 |
| --- | --- |
| Complete native log | `da63617506a7d9ac2b6d095e1eeb30a640971cf7351e34b065968c8738684f88` |
| Unchanged earlier six-probe log | `a66ff0689a13865223064a67f707cd1e14fab6d7dd45655a4e4c3d95198e48f5` |
| Unchanged new three-probe log | `529afd3f9d5f96867afb7f71a1483f967197643583c68d30774ad9303613c577` |
| Combined gate status | `9280f47da78f440f42321f9342767e10f8a8ae6564cb3fe8d541d2aff50b1eed` |
| Final source/native binding | `a14ecd9e2b5025c5f3e8c543d1977656b86a665674a7bd7e205f6da194812d2f` |
| Complete capture manifest | `d736a21d1d73af29e6418cf95669296e6c4e55571a751d22b1cdcec746daaf2b` |
| Matrix pass log | `91d0cc1c61aa79a10f504f3096fd0b167ee2463ad9c8e10b2091572d2f7545ea` |
| Matching baseline matrix log | `7d1dfeea530048014e3cfb3f2c98da8d7f9a2ecfc20f3c2e8625f945bf1ed355` |
| Independent matrix review | `978e6081cba2b8e808083c266fa141882b40b415bba2b5619f6f364edafeef5c` |
| Independent 58-screen rendered review | `1fce8dc2cd0f427cc74de4d273b5c5addf1f1adc7f63024470d504a60f6d2d35` |
| Publication object/evidence binding | `d51dbc999b217f8aafecec8ce7d97bac759d8fbc282dde6e7ab6249b5b64b73e` |

## Remaining boundaries

The engine still treats a put equal to its original CRDT base as a no-op.
Re-selecting that same value does not force a concurrent branch; a later coherent
paint may adopt incoming persisted data. This separate persistence-intent policy
is unchanged and needs its own engine-policy review. The matrix verifies the
combined pending-load path; it does not claim an isolated mutation proof of every
internal guard. Source review checks those guards directly.

Parent acceptance must clear this immutable source before another distribution
candidate. Physical updated-app acceptance, unassisted network setup and coherent
fresh-computer recovery remain open. No device operation, real grant provisioning,
network change, live-data migration, merge, deployment or hosted retirement was
performed for this repair. Publishing tested source to its named branch does not
close these acceptance gates.
