# LF-005 — Answer acknowledgement repair receipt

**Parent acceptance blocked:** subsequent independent review reproduced prepaint
N/A and optional-clear status races in `9c88f39`. Its existing evidence below
remains historical and does not clear those failures. The complete ownership
repair is scoped in [LF-005 displayed-answer state](LF-005-displayed-answer-state.md);
0.2.5 and 0.2.6 binaries remain unchanged and blocked.

Verified source milestone on `codex/inspection-answer-ack-repair`. Production
fix is `9a15ac6758923d3fe14808bc2fcff08f8dfb9e57`; final source/test integration
is `9c88f39f156baf2dab41b44c631d7a7aa51750df`, based on frozen `55fb96b`.
The later documentation commit does not change tested application bytes.

The repair preserves Needs action/35 while a durable Save waits for decoding
and repaint. Genuine platform input of 25 retains Needs action, and the next
explicit Save persists Action/25. A retained presentation overlay also preserves
Action/35 through decoding failure and a benign rebuild before any newer edit.
Existing finding classification, raw numeric parsing, units, dirty identities,
CRDT base and exact painted-document submission fences remain intact.

## Exact source identities

| Item | Identity |
| --- | --- |
| Final application tree | `26179d351c93d1cdac8b9fd33e90735eec50bc58` |
| Editor SHA-256 | `8e13983ff9e33290a0ff7749b92682077f3d4a3cf670cab3c332927ed13352a3` |
| New regression file SHA-256 | `0ea35fa3b4dc5b7280f699371e43c41998634b9de6060d92af79fab302264c74` |
| Immutable parent probe SHA-256 | `1717489da811dc323fccdfbd725f31b6c0b02337478761ec54ab84cdc5ddfd58` |
| Unchanged Rust source tree | `9ef2144f90b34557b3695bc2ece806bc37f68ec0` |
| Unchanged local agent-service tree | `d4209817f7dd16272b07644d7641a820047581e5` |

Production changes only `inspection_page.dart`. Independent test commits
`be78b684`, `3349a0a5`, `936a9334`, `fb18f45b` are selectively ported as
`bb5309f`, `1334d9a`, `0d03534`, `9c88f39`. They change only the new regression
file; render follow-ups preserve its original assertions. The test owner's
final application tree exactly matches integration despite different commit order.

## Verification results and correction

- Every existing **426** application test passed across the full run and a
  corrected native rerun: **422** successes in the full `9a15ac6` run, then
  **4** bootstrap/bridge cases after restoring their expected pinned-library
  cache path. The original full-run log retains its two setup failures before
  test loading. This is not a claim of one clean 426-case invocation.
- **13** added classification cases passed: twelve in the combined corrected
  run, and the added overlay-only failure/rebuild case in its targeted final run.
  Independent baseline evidence has five passing controls and seven failing
  classification cases for the original twelve; the added case separately fails
  the baseline before any late typing and passes the repair.
- **6** byte-identical immutable diagnostic cases passed: four LF004 human-review
  cases, the original in-flight probe, and the new answer-acknowledgement probe.
  Original external probe files were not edited.
- Whole local-app analysis is clean at final `9c88f39`; boundary checks **4/4**
  and portable progress/checklist/exact-history verification pass.
- Rust **4/4**, Node **298**, Python **35**, normal host **112 assertions / 14
  actual CLI calls**, and extracted CLI **98 assertions / 18 calls** are retained
  gates bound to identical native, rules, service, CLI and script objects. They
  were not newly rerun for this editor-only change. Parent separately reported
  scoped independent PASS on CLI `c64c6c3`.

All late-input events use genuine focused, registered, enabled platform clients.
The post-install/prepaint case observes completion of the real enabled Save
callback. Controls cover N/A, explicit unanswered state, unknown/zero, numeric
bounds, invalid input, raw comma values/psi, repeated events, failure/retry,
immutable submission and concurrent conflict fencing.

Phone widget captures at 412×915 with 1×/2× text show readable raw readings,
units, range guidance and result controls. Additional 1× captures show retained
Action/35 after failure and Action/25 after retry. These are synthetic widget
fixtures with bundled fonts; production theme is unchanged. They do not establish
physical or unassisted acceptance.

## Durable local evidence

Evidence lives in owned, ignored output directories:

- `task-8/answer-ack-full-gate/outputs/`: full log, corrected 22-case run
  (four native + twelve new + six immutable), final overlay-only case, analysis,
  boundary/portable receipts and immutable-probe bindings.
- `task-8/answer-ack-regressions/outputs/answer-ack/`: independent baseline/fix
  logs, `CHECKPOINT.md`, `OVERLAY-ONLY-FOLLOWUP.md`, render and evidence manifests.
- `task-8/inspection-answer-ack-repair/outputs/answer-ack-repair/`: coordinator
  gate/source bindings and independent source/test/hygiene review.

Key log SHA-256 values:

| Log | SHA-256 |
| --- | --- |
| Full run, retained setup failures | `ca8d39d94b7233146cde461a19c1c34bc48f41f5bb267bd3bc001fb834a48513` |
| Corrected native/regression/immutable 22 | `645804bb20c50ddf66e7c2fef8426bbc474d7319ee58cfcd00c2ea4b06504d12` |
| Final overlay-only case | `86b8e919780f770ab608da41ec1bfe4a28850fa34128a74344ec3222b12b284b` |
| Final whole-app analysis | `71aead9b57efa9f166bddb25d8290c7afa02c35699575199bfdcbd2b05c4f67b` |
| Independent original-twelve baseline | `233d852b7cc0da622313eb899164483f1225230b9a2f2e9f9378fadddb903a2e` |
| Independent added-case baseline | `1f2cb790a674d7cf10a1d9f398d44c6f76df69fa8b69c7b4bcabd70d0faa434c` |

Tests use the pinned Linux x86-64 native library SHA-256
`1b03d11510bc0146fe63f69e41346a64e315b20cf457df94273e21b9e394fe68`,
ELF Build ID `86d1a03dc24b3da5efa61f7178c1001a6f8ec493`. Offline toolchain:
Flutter 3.44.0, Dart 3.12.0; SQLite hook pin
`2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5`.

## Acceptance and preservation

Independent read-only source/test review passes the exact fix and test ports.
Parent independent acceptance of the replacement fix remains open. Frozen
`55fb96b` 0.2.5 APK/Linux artifacts remain unchanged and blocked; no new binary
is built or installed from this fix. Rebuild a distinct next candidate after
parent review clears. Earlier 0.2.4 artifacts and hosted rollback remain intact.

Named-branch publication is limited to source, tests and documentation. No
default-branch merge, deployment, device operation, real credential/grant change,
live-data migration or production cutover occurred. Updated-device, ordinary
office launch, unassisted setup/recovery and fresh-computer acceptance remain
separate gates.
