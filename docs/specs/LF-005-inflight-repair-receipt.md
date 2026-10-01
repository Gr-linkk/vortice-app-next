# LF-005 editor repair receipt

Input received before the busy frame paints now stays visible and unsaved when
an earlier save completes. The editor acknowledges only captured edit identities,
retains later notes/readings/answers, and prevents navigation or photo selection
from discarding them. Captured submissions remain immutable; their messages
identify any newer unsaved edits. Genuine queued remote conflicts and the existing
painted-document submission hash fence remain intact.

Production repair: `234865f37d2735c86506650a93f94f3e790114ca`.
Final code/test freeze: `e46cc9e50cff64e3b6ae0a321e8fdec7b7714fd9`, on
`codex/inspection-inflight-input`, base receipt `dc9d7f4`. The two follow-up
commits import independent tests and correct their terminal-state waits. They
leave the repaired editor unchanged at SHA-256
`6a1d4c430473f33e09a028e7a275a78911c6a457fec78503cdc5e4170557f243`.
This receipt is a separate documentation change.

## Verification

- The full Flutter suite passed 408/408 on frozen `234865f`, including native
  process recovery, ordinary workflow, office/agent commands and 1×/2× renders.
- The imported independent suite passed 18/18 again on final `e46cc9e`.
  Its corrected baseline counter-check demonstrates 17 failures on the old
  editor; the SQL rollback retention control passes on both versions.
- Independent read-only review passed 19/19: the exact unchanged parent probe,
  six additional baseline failures, and 12 retained coherence/hash/conflict
  controls. No concrete P1/P2 finding remained in the scoped repair.
- The four unchanged LF004 proposal/editor probes passed. Two additional phone
  renders of the submitted-with-unsaved banner passed and were visually checked.
  The independent suite produced 13 inspected synthetic 412×915 captures at 1×/2×.
- Whole-app analysis, four application separation checks, the portable Dart
  checklist/progress/exact-history gate and whitespace checks passed.

Coverage includes notes, raw comma meters, numeric/text answers, checklist
pointer actions, initially clean/new fields, post-write decoding, SQL and decode
failure/retry, back navigation and gallery-picker interleavings. Later edits can
extend the editor's own durable write without false self-conflicts; truly unseen
queued remote writes retain their original merge base and explicit conflict.

## Evidence and boundaries

Local evidence lives in `outputs/inspection-inflight-input/`, including
`CHECKPOINT.md`, `full-suite.log`, `combined-independent-tests.log`, the LF004
probe log and rendered banner captures. Independent reviewer log SHA-256:
`9847751724ddcd39229d910c8a8e6151c6bfd72592f87eff659681f5efc0fea9`.
Full-suite log SHA-256:
`98b0d726869d7c4a463a85c94fa9bd1acd009f266d517c80892eacfdddf2e60d`.

The parent probe remains untouched at SHA-256
`9807aa5db599b0ffcbeccf1e7da19abec1d582f1d1665dad8f2674f45cb8f7aa`.
The committed reproduction copy differs only by Dart formatting; its assertions
and interleaving are unchanged. Its SHA-256 is
`2feae25dee39233343eb46a5d831d1da858e8daca0b2099535631e4f866622dc`.
The LF004 copied probe is byte-identical to its original at
`1478fe01c02b965a57077472384416b3fbda4b3b390d83f1c86b9ca86cb9823c`.

Only editor code, dedicated tests and documentation changed. Store/service/API,
native engine, portable rules, grant authority and hosted rollback remain
unchanged. Fixtures are synthetic and isolated. No new app build, installation,
live phone operation, network configuration, credential provisioning, default
branch merge or deployment occurred. Existing 0.2.4 artifacts still contain the
older editor; this source repair must be incorporated into a separately verified
build before physical acceptance. Source publication is limited to this named
branch. Physical and unassisted setup/recovery gates remain open.
