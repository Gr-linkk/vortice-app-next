# LF-005 — Complete displayed-answer ownership

Parent review blocked `9c88f39` and frozen 0.2.6 candidate `a902373` on
three genuine enabled-platform cases: an unpainted N/A selection or optional
clear followed by Save, decoded installation, then typing before repaint.
The old callback lost N/A or revived the earlier Action classification.
All existing 0.2.5/0.2.6 artifacts remain unchanged and blocked.

## Invariant and implementation

Each configured answer has one immutable full nullable presentation and a
monotonic local event identity. Selection, typing, optional clear and human full-answer conflict choices replace
that full value synchronously, including raw text. Acknowledgement can remove
only matching dirty persistence identities. It never removes presentation.
An explicit null answer is an owned cleared value, distinct from no owner.

| Transition | Presentation and persistence rule |
| --- | --- |
| Local event | Replace the full answer, advance its identity, mark dirty, synchronize raw controller text only when different. |
| Durable acknowledgement | Remove matching captured dirty identities; retain the full current presentation. |
| Decoded installation | Stage complete candidates only for keys clean at installation; capture each local identity and the form generation. |
| Replacement frame | Render/promote a candidate only if its captured identity is unchanged and the key remains clean; otherwise preserve newer local ownership. |
| New command | Invalidate pending frame handoff before writing; restore one coherent painted field/document pair plus local overlays. |
| Failure or rebuild | Keep the owned full answer and coherent painted snapshot; subsequent successful reads can stage a new snapshot. |

Callbacks read current owned answer state rather than captured classification
or an unpainted decoded candidate. N/A, explicit clear, Action, Pass, unknown,
zero, bounds and raw units retain existing domain semantics. A result-only
selection preserves the owned raw text when a remote candidate has changed a
controller before paint. Dirty-at-install candidates cannot become eligible
merely because acknowledgement clears dirty membership.

The frame publishes document bytes and fields together. Save uses that painted
pair. Existing queue serialization, captured-edit identities, original CRDT
base, known self-write base extension, incoming generations, conflict checks,
unseen-version rejection and exact-document submission hashes remain enforced.
A staged incoming frame cannot overwrite the command's durable-write base.
A human full-answer conflict choice takes local ownership before capture,
including N/A or null. Its exact dirty identity is acknowledged only after the
chosen write; a later local input remains dirty and extends that chosen answer.
Remote decoded data still takes ownership only through the guarded frame.

## Verification and delivery boundary

The coordinator owns the editor. An independent read-only state-machine review
and counterexample review own invariant analysis. A separate worker owns a
black-box table-driven boundary matrix, baseline evidence and immutable parent
probes. Full native source gates run after source/test freeze with the exact
native pin and explicit environment; every interrupted/setup attempt stays in
local evidence and is not a pass.

Exercise queued/acknowledged/staged/prepaint/failure/rebuild boundaries, N/A and
optional clear, repeated platform input, raw pressure/units, remote result and
raw changes, dirty-time stage plus Save, early validation failure, and immutable
submission/conflict fences. Parent probe files remain byte-identical.

This is a source-only repair on `codex/inspection-answer-state-invariant`, based
on `ac2e158` (documentation-only superset of `9c88f39`). No new distribution
version, build, installation, grant, database schema, engine, protocol, signer,
network, hosted cutover or live-data migration is introduced. Return immutable
source and unchanged-probe results for parent audit before another candidate.
