# LF-009 — Verified manual fault intake source milestone

October 1, 2026. Office staff can report a fault against existing company
equipment, choose normal/urgent severity, optionally attribute an exact saved
inspection version/item/note, and reopen the immutable report. Its status is
**Reported — corrective work not planned**. The ordinary path is office Home →
Reported faults → New report → record → fault detail → Home.

## Frozen source and review

- Accepted base: `98deb62cb3b790f3cc7f7197f9407209033877fd`.
- Tested code: `36f3a4d453b83466054163724fcbd5defc2704dd`.
- Application tree: `7e0371faa520e7e5e55a52f26db8e415da1824d8`.
- Isolated branch: `codex/local-fault-intake` in the independent
  `Gr-linkk/vortice-app-next` repository. Source-only named-branch publication is
  separately verified in the local remote-publication receipt.
- Independent bounded static review: closed with no remaining material finding.
  Checklist SHA-256:
  `5a61770729d491323756ed3cb9ab90647b5eecf080f51509f5d6e549d10ab59c`.

Four distinct owners covered ledger/store, intake UI, recovery/actual older
reader, and independent review. The coordinator integrated normal navigation
and combined gates. Backend `3d4cba`, recovery `b307917`, UI `d8d83d3`, and root
navigation through `ff03335` are the reviewed component checkpoints. Root UI
and regression blobs match the independently reviewed UI exactly.

Review found and closed two valid-source compatibility defects (long labels and
unsynchronized source timestamps). Ordinary tests also reproduced a previous
frame's navigation callback racing save completion: three of four cases failed
before the repair, all four passed afterward. Source/equipment actions now check
live saving state before navigating. Idle frozen/recorded source viewing remains
available. The earlier 527-case run is historical; final execution includes the
repair.

## Executed gates

| Gate | Result | Log SHA-256 |
| --- | --- | --- |
| Full Flutter app on final code | 531/531; zero errors/skips; successful terminal | `fe9de97b020a41ef456f44cb01f6301bfa4d51f3426fd906542915e9cb30c10c` |
| Final whole-app analysis | Clean | `4c6917bb8fbf77c4b0179d42ad379c465960468af1a3985cc0e33442c95adb0f` |
| Node CLI/transport/distribution | 298/298; zero failures/skips | `d5de4d21d9ca1c3e427f549bd91453a47582db96330c0a2f190664d0ce20dd8b` |
| Python boundary/runtime/packaging | 53/53; zero failures/errors/skips | `a801fc5e134e0b2061104158d95bac9e762d7be29b08a7451ddd18bf07d2af52` |
| Existing native Rust tests | 4/4; zero failures/ignored | `0dccd4945c4866ec8986aec4d574cfa7dd7ebca4220f7b08b523645a4679eef2` |
| Hosted/local launch separation | Pass | `c2f751f93fe42c017cf1f74fa927061f30701aac69a2a26ee2930a32767722c9` |

Node, Python, Rust, separation and pure Dart progress gates ran at `ff03335`.
Their recorded source inputs are byte-identical at final `36f3a4d`; the only
later source delta is the new fault page and its four ordinary UI regressions.
`Gate-Source-Binding.json` records the Git-object correspondence. Final Flutter
execution includes existing real CLI/service/human-review integration tests.

The 50 new cases comprise 20 model/store, 11 recovery, 17 UI and two ordinary
Home-entry cases. They cover durable frozen intent, pre/post-commit lost reply,
exact replay/conflicting identity, reopen/resume, atomic rollback, queued office
authority, exact pending/approved/returned source observation, unknown versus
zero readings, unchanged original inspection/photo data, and corrupt/future
ledger refusal. The seven SQL tables and database version 2 remain unchanged.

## Actual recovery and rendering

The helper ran the unchanged accepted `98deb62` `OfficeBackup.create`, `inspect`,
`restore` and reopen against a synthetic new ledger and pending request. Original
settings, events, catalog, native documents, submissions and inspection receipts
were retained, excluding the documented restoration metadata. The new validator
and backup reader then accepted the intact old-restored result.

- Actual old `office_backup.dart` SHA-256:
  `f53eead83de01138cde19b3a3d4cd9aae542585ba8b920cfa7cb0dedf4588023`.
- Before/backup/restored retained-state hash:
  `0a725b0d1103cb0a79c83d1734019398425a028f3fe4d143be5e01211ef8cba8`.
- Final proof SHA-256:
  `4f09aeb1d2b6036f171a9af077b67c3f70db30712c6ef443c1bb3b2f8a1cec85`.
- Two phones fenced for reconfirmation, one revocation retained, three invitations
  discarded by the existing same-office recovery rules.

The older reader preserves unknown settings/events; it does not understand or
validate new fault semantics. The matching new reader refuses damaged or
unsupported ledgers without changing retained files.

Actual native rendered ordinary paths passed at 412×915, 1x and 2x text. Final
captures include `home-fault-entry`, `home-fault-list`, `home-fault-detail`, exact
saved-source/photo provenance and durable retry screens. The coordinator visually
checked final 1x entry, 2x detail and 2x stored-photo source; the UI owner checked
the component captures. These are rendered checks, separate from physical use.

## Native identities and unchanged boundaries

Tests used the accepted 0.2.8 Linux x64 runtime, with hashes unchanged before and
after execution. This milestone contains no newly built or distributed app.

| Runtime library | Bytes | SHA-256 | Actual GNU Build ID |
| --- | ---: | --- | --- |
| `librust_lib_sync_lab.so` | 74224312 | `582b0b00d645d9683512d4426729c633985302322232e3413fca4e7fe015d412` | `1d76e8b506aeac40765fdd6b03414d8a6a15f4d7` |
| `libsqlite3.so` | 1801600 | `2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5` | `8d00df9c57e6b97adef2df4ab31e492a6bcbd106` |

The ignored bridge-test path holds a separate copy of the same accepted runtime;
Rust tests build in a separate ignored target. Native source/bindings, locks,
schema, sync, hosted source, CLI commands/grants, signing and app metadata are
unchanged. Only source/docs/tests are publication candidates; local outputs,
SDK caches, evidence images, private workspaces and backup files stay untracked.

## Open gates

Physical/unassisted fault intake and fresh-computer recovery acceptance remain
open, along with any separately scoped binary packaging/install. No phone action,
live credential/access change, company import, network change, production merge,
cutover or deployment occurred. Hosted rollback at Build 45 `9a3b5d3` and retained
fixes `eb2d0d4` were rechecked clean and unchanged.

LF008 remains provisional, with its independent security assessment uncompleted;
its source and restricted assessment are excluded. Corrective linking/execution,
verification, availability, recurrence, multiworker/remote sync and production
import remain separate product choices. Full local receipts, logs, proof and
render hashes are retained in ignored `outputs/manual-fault-intake/`.
