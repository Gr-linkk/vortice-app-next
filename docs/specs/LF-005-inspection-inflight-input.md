# LF-005 inspection input received during save

This repair extends the inspection editor on receipt base
`dc9d7f4d78f2046eb9a69cb3921bb481dcaa95b0`. It changes only the editor's
acknowledgement of local input. The queue, native document authority, submission
hash fence, and office-agent connection behavior are unchanged.

## Reproduced defect

The frozen independent probe in `task-3/integrated-b84070f` has SHA-256
`9807aa5db599b0ffcbeccf1e7da19abec1d582f1d1665dad8f2674f45cb8f7aa`.
It invokes the rendered Submit callback while the native queue is held, then
sends platform text input before the busy frame paints. The field is still
enabled. Previously the completed save cleared all dirty fields and refilled the
controllers, discarding that later input. The baseline failure is retained in
`outputs/inspection-inflight-input/before-repair.log`; the frozen original is
untouched.

## Completed-operation acknowledgement

Every local field edit receives an identity. Save captures the raw edits,
identities, and merge base synchronously, before awaiting the queue. Completion
clears only identities that are still current. A later edit remains visible and
unsaved even if its value equals the captured value. Meter parsing operates on
the captured raw input, so normalizing a comma decimal cannot acknowledge a
different raw edit.

Later edits can extend the editor's own durable write without creating a false
self-conflict. This advances their merge base only when the original edit base,
queued pre-write document, and painted document have the same native hash. Any
unseen preceding remote write retains the original merge base and the normal
conflict behavior. The editor preserves remaining dirty fields during decode,
reload, and photo follow-up.

Submit can finish the exact captured version while later edits remain unsaved.
Its message explicitly identifies those newer unsaved changes. Save returns
false while any newer input remains, so back navigation and the initial photo
save cannot discard it. Submission still requires the existing displayed-native-
bytes hash fence; unseen versions require review and a new explicit click.

## Regression evidence

`inspection_inflight_input_test.dart` uses real platform input with the previous
enabled frame and a held native queue. Its twelve cases cover Save and Submit
for notes, raw comma meter input, numeric answers, and text answers; equal-value
new edit identities; durable-write/decode failure and retry; queued remote
conflicts; and navigation with a later unsaved edit. The copied frozen probe adds
one independent reproduction case. Existing coherence and queued-hash tests are
also retained.

The initial navigation test failure was an initial native-loading spinner
timeout before the back/save action. Its log is retained as
`outputs/inspection-inflight-input/focused-before-navigation-harness-fix.log`.
The harness now waits for native decode and route animation explicitly.
Final focused results are in `outputs/inspection-inflight-input/focused-final.log`.
All fixtures are isolated and synthetic; no live app, device, network service,
connection grant, or frozen packaging checkout is changed.
