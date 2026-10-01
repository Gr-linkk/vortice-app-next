# LF-005 — Answer state after save acknowledgement

Independent review of the earlier input-retention repair found a second race.
An enabled, focused field still showed Needs action and reading 35 after Save
had acknowledged its edit but before decoded replacement and repaint. Ordinary
platform input changed the reading to 25. The callback fell back to older stored
Pass state, and the next explicit Save persisted Pass/25. The retained input
value alone did not preserve the inspected finding.

Work is isolated on `codex/inspection-answer-ack-repair`, based on combined
`55fb96b738464b8c4b43ca8ff44c7c1d574cd4e5`. The frozen 0.2.5 candidate and
binaries remain unchanged and blocked. The existing 0.2.4 binaries, extracted
CLI milestone, hosted rollback, signer and reviewed references also remain
unchanged. No candidate installation or acceptance follows from a source fix.

## Result and boundaries

Production repair `9a15ac6758923d3fe14808bc2fcff08f8dfb9e57` changes only the
inspection editor. Matching durable acknowledgement retains the complete
answer as presentation state until a coherent decoded form installs. This
survives asynchronous decoding, decoding failure and intervening rebuilds.
Each rendered field also captures an immutable full answer for its callback.
Newer dirty edits win, including explicit unanswered and not-applicable values;
then retained acknowledgement state wins, then the rendered callback snapshot.

Presentation state never enters a persistence patch or submission. Existing
raw-value parsing, units, unknown-versus-zero behavior, edit identities, native
document bytes, CRDT merge base, read/form generations and painted-version
submission fencing remain unchanged. The repair adds no schema, service, CLI,
grant, permission, procedure or authority behavior.

## Verification and acceptance

Keep the parent's frozen reproduction byte-identical:
`review_after_ack_answer_probe_test.dart`, SHA-256
`1717489da811dc323fccdfbd725f31b6c0b02337478761ec54ab84cdc5ddfd58`.
It uses the actual enabled focused platform input client before a replacement
frame, then verifies Action/25 persists through the next explicit Save.

Independent companion regressions cover classification across acknowledgement,
replacement paint, multiple input events, failure/rebuild/retry, optional and
not-applicable intent, unknown and numeric input. Retain all earlier late-input,
human-proposal, conflict and exact-version submission probes. Run the complete
application suite, analysis, boundary and portable gates against the frozen
production repair, and bind unchanged native/CLI gates to their identical source
objects. Render the affected workflow at phone size and 1×/2× text.

The [durable receipt](LF-005-answer-acknowledgement-receipt.md) records exact test
revisions, baseline failures and passing controls, source hashes, logs, rendered
evidence and review limits.
Parent independent review remains a separate acceptance gate. Rebuild the next
candidate only after that review clears; do not relabel frozen `55fb96b` binaries.
No live-data migration, real grants, default-branch update, deployment, device
command or physical acceptance occurs in this repair.
