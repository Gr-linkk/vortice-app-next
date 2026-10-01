# LF-INTEGRATION-002 — Repaired app and extracted CLI

Authorized October 1 integration of two source milestones in a new isolated
candidate: `codex/local-maintenance-repaired-025` at
`task-8/local-maintenance-repaired`. Base is CLI receipt
`59b7ac50a63a5394f92923d8728ca640a90e864a`. Editor commits from
`234865f` through receipt `ab59470` are selectively ported; no unrelated lab
branch or hosted baseline is merged.

## Result and bounded changes

The editor preserves platform input received while an earlier Save/Submit
waits, with explicit unsaved state, exact captured-edit acknowledgement and
existing conflict/submission fences. The Linux package includes its relocatable
permission-checked agent CLI. Its code locations are checked before handing a
credential to package modules. Human approval, scope, finite grants, revocation,
immutable proposal creation envelopes and office review receipts remain as
reviewed. Default agent access stays disabled.

New changes beyond those two milestones are internal `0.2.5+6` metadata, matching
About labels, and inclusion of distribution tests in the guarded verify action.
Protocol/client version remains 1/0.1.0. No new database, engine, API, credential,
permission, signing key or hosted service is introduced.

The existing 0.2.4 artifacts contain the earlier editor. Preserve them unchanged
and never describe that packaging as repaired. Build a new Android debug APK and
Linux debug distribution from the frozen combined revision, using the existing
reviewed signer and offline toolchains. Record source/metadata/native IDs and
hashes before any separately coordinated physical acceptance.

## Verification ownership and order

1. Coordinator inspects ancestry/diffs, ports source and freezes the candidate.
2. Isolated gate worker runs the complete native Flutter suite, analysis,
   portable rules/progress/history, application separation checks, Rust tests,
   unchanged LF004/parent probes and 1×/2× rendered checks. Coordinator runs
   all affected Node/Python checks and normal synthetic command smoke gates.
3. Separate Android and Linux workers build from that exact frozen source in
   independent caches. No live app or desktop UI is launched. Existing signer
   material is read only and verified before/after; no key is created.
4. Coordinator adds the exact frozen CLI runtime to the new digest-pinned Linux
   app archive. A fresh guarded synthetic service exercises the extracted
   executable, including reads, accepted lost reply, exact retry and conflict.
5. Independent read-only review verifies source/artifact hygiene, signatures,
   metadata, native IDs and original preservation. Publish only tested source,
   docs and tests to this named branch; keep artifacts/fixtures in ignored outputs.

Parent independently audits exact editor `e46cc9e` and CLI `c64c6c3`. Those source
milestones remain unchanged. The earlier security worker's final content turn
was stopped by a platform flag; it was not an exec approval rejection. Its
interrupted review is not recorded as a pass. Subsequent checks are limited to
ordinary defensive source review and benign synthetic regression fixtures;
no denied action or credential-capture probe is retried through another route.

No default-branch merge, deployment, installation, network change, real grant
provisioning or live-data migration is authorized by this build increment.
Physical updated-app acceptance follows separate coordination after independent
audit. Unassisted setup/recovery, multiworker and internet relay remain outside
these gates.
