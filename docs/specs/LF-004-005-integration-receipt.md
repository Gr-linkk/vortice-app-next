# LF-004/LF-005 — Reviewed local office and agent workflow

October 1, 2026. Tested source: `b84070f635498034bdf1807ec776489578218370`.
Branch: `codex/office-agent-connections`, based on preserved receipt
`ed79c4faaa014c0bfb6f514256ed2cea8f44472e`. This is a source and internal debug
build milestone. It does not establish production conversion or physical
acceptance of this version.

## Resulting workflow

The existing local company, equipment, immutable checklist, offline inspection,
gallery evidence, submission, exact office approval/history and recovery slice
now includes normal Linux office agent connection controls and human review.
The office explicitly enables connections, selects fixed equipment/job scope,
issues a named credential with finite expiry, and can revoke or disable access.
Fresh workspaces start disabled. Phones have no management route.

The actual external-agent Node CLI calls the shared permission-checked local
service through its private Unix socket. Reads stay within the saved record
selection. Its sole write saves a suggested replacement for inspection notes;
it does not edit the inspection directly. The office opens **Agent suggestions**,
reviews current and suggested notes against exact document versions, then
explicitly applies or rejects them. Submission and inspection approval remain
separate human actions.

The CLI currently runs from its source checkout with Node 22 or later. The
desktop debug archive contains the app and does not install a CLI launcher.

Application and its authoritative review receipt are atomic. Accepted/rejected
history preserves the original suggestion even after later edits. Coherent
office backups retain these decision receipts, while unreviewed proposal and
access sidecars remain excluded. Restoring the same public office identity
does not restore agent capabilities or enabled intent.

Protocol v1 create/retry responses remain immutable creation evidence, including
their original pending flags. The office review/history screen supplies current
human decisions. CLI procedure reads remain grant-scoped inspection snapshots;
private checklist drafts and the complete office library are not exposed.

## Audit corrections and architectural boundaries

INT-AUDIT-001 is corrected: every proposal replay confirms directory durability
and current authorization before acknowledging its original immutable result.
Post-publication failures retain the proposal and report an uncertain outcome.

INT-AUDIT-002 is corrected: clean inspection fields refresh coherently; dirty
intent retains its visible merge base. A changed document requires review before
submission, and the store checks the displayed hash inside its queue. Visible
form state advances after painting, so input before that frame cannot silently
accept an unseen merge. Exact retries and historical decisions remain intact.

Unix endpoint checks use actual UTF-8 bytes for both private bind and public
paths. Existing unsafe files/endpoints are refused and preserved. Grant state
has a single writer lease, strict private filesystem validation, digest-only
credentials, explicit record sets and maximum seven-day expiry. Disable, revoke,
expiry and restoration preserve the existing command/whole-job status fences.

The office OS account remains experimental coordinator authority under decision
0022. Hosted MFA/MCP and Supabase remain rollback boundaries. There is no new
database schema, native engine, phone sync protocol, approval authority, remote
relay, multi-worker policy or live-data import.

## Verification at the exact source

- `scripts/local-maintenance.sh verify --reporter expanded`: clean analysis,
  portable work projection, 4 Rust tests, 395 Flutter tests and 166 Node tests;
  zero failures or skips.
- Actual synthetic service/CLI acceptance: 21 fixture checks, plus 112 normal
  host acceptance assertions across 14 Node CLI subprocess calls. The host
  fixture retained one pending proposal and removed its temporary workspace.
- Four local-maintenance separation and twelve offline operations-tool Python
  tests passed, plus portable work/command/membership contracts.
- Independent final-source review: 75 focused native/widget/subprocess cases
  passed, both P2 closures recommended, no concrete remaining P1/P2 found.
  Original audit evidence was preserved; positive editor acceptance replaces
  obsolete expectations that a clean form should remain stale.
- Full gate produced 253 fresh 412×915 PNGs: 245 workflow/navigation/connection/
  review images and 8 editor coherence images. All 178 previous render names
  remain present. Affected flows cover 1× and 2× text, with additional 1.8× review
  coverage. Generation and visual inspection are separate receipts.

The readiness-file repair is confined to a subprocess test helper: it now
publishes complete flushed JSON atomically before the parent observes existence.
It does not change proposal storage or manufacture a successful crash test.

## Build identity and preserved artifacts

Application tree: `0b5a1d3f192a76cdd85a53f650bc062545b4fdf4`.
Portable rules tree: `1aa19a197d55cd335b8f04e340911bc0297fd632`.
Rust source tree: `9ef2144f90b34557b3695bc2ece806bc37f68ec0`.

Both isolated debug builds passed at the exact source with tracked code clean.
Version is **0.2.4+5**; application ID is
`org.vortice.next.maintenance_local`. The existing internal signer remains
`9b46bb98db0519dbb53c5e17086cc8b16459157275561dcc68174a6cec463b81`.
No key was generated and no installation occurred.

| Preserved internal artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Android arm64 APK | 91,379,737 | `74d8448f71fcaa10525590726a676e7a42c7f881b484215ab129b09b224700bb` |
| Linux x64 archive | 49,667,914 | `c6800522920a4fbee90f80e73b977ecada1fa9c1278bc8a59660665592d66b64` |

Linux packaging verified 17 regular files and its `$ORIGIN/lib` dependencies.
Android identity, signature and packaged native assets were checked. Extra vendor
JNI ABI copies do not establish execution on another application ABI.
The previous 0.2.3 APK/archive were rehashed unchanged; earlier milestones and
the hosted Build 45 rollback remain intact.

Local supporting receipts are under `outputs/lf005/`,
`outputs/connections/Threat-Review.md`, and the separate
`task-8/office-build-artifacts/0.2.4-b84070f/` directory. Outputs, binaries,
private fixtures, recovery archives and credentials are excluded from Git.

## Remaining acceptance and next step

A separate physical receipt passed the exact older **0.2.1** APK through USB:
gallery evidence, offline readings/notes across restart, durable reconnect
delivery, exact office API approval, disconnected receipt persistence and
duplicate-sync checks. Desktop preparation/approval used APIs because the
desktop was locked. That receipt does not verify 0.2.4, LAN, camera, desktop
click-through, fresh-computer recovery or unassisted setup.

Next: independently audit this immutable combined source and receipts, then
exercise the new version's ordinary office controls and phone/recovery journeys
with specifically authorized device actions. Preserve desktop lock/privacy.
Real grant provisioning remains an explicit human action. Named source-branch
publication is authorized; default-branch merge, deployment, release, hosted
retirement and live company migration remain outside this milestone.

Library archival of the preserved 0.2.1 APK/receipt was retried with the current
required upload helper; it reported unavailable upload preparation. Neither
file was saved and no new Library ID was created. Their verified local archival
copies remain available. Existing main-only GitHub CI does not run for this
named-branch push; local verification is not represented as a hosted CI pass.
