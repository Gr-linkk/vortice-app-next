# LF-005 — Internal 0.2.7 candidate receipt

Built source: `228091abde5c3e7fc6874ed03238f49bf34c50f8` on
`codex/local-maintenance-candidate-027`, based directly on `87e52e9`.
Application tree: `1244d58634925031c4ddbf0f8049d61a9494b97e`.
Source and artifact checks pass. Physical updated-app, unassisted setup and
fresh-computer acceptance remain open. This is an internal candidate, not a
production release. Earlier blocked 0.2.5/0.2.6 packages remain separate.

## Exact source difference and accepted repair

Compared with `87e52e9`, the build commit changes only two files and three lines:

- `experiments/maintenance_local/pubspec.yaml`: `0.2.5+6` → `0.2.7+8`.
- `experiments/maintenance_local/lib/ui/workspace_page.dart`: both office and
  phone About labels change `0.2.5` → `0.2.7`.

The repair source `5f9a1100b01706e4c9c2463e3b2b3992d0c2617b` is unchanged and an
actual ancestor. Parent independent review confirmed 45 fresh passing cases:
nine unchanged probes, the 35-case matrix and a same-value submission fence.
This confirmation is attributed to the parent's review handoff; no separately
saved parent-report hash was supplied. The complete local source gate remains
474 passing native cases, clean analysis, four boundaries and portable checks.
See [the source receipt](LF-005-displayed-answer-state-receipt.md).

Reviewed CLI commits `c64c6c3d8270bd8ef70819a81bcb2701c960a33c` and
`59b7ac50a63a5394f92923d8728ca640a90e864a` are actual ancestors, not inferred from
matching filenames. All seven packaged runtime/help inputs are byte-identical.
The editor, domain, permissions, backup, service, native source, dependency
locks, hosted application and Supabase rollback objects are unchanged.

## Frozen packages

| Package | Bytes | SHA-256 |
| --- | ---: | --- |
| Android internal APK | 91,387,697 | `670be6aa8f0c1804dde41b24b595c577d43a79ea163eb074377573b779ef86ff` |
| Linux app-only archive | 49,393,928 | `ce2cc0c0f9c2497d5519067d0aebc8f110ed25053dbf375c400d415d98b993de` |
| Linux app + extracted CLI archive | 49,406,076 | `65f73bb4ad7533be1c98cceaa7c77f96368a74930e862dd29ad24caa76d6362a` |

Android identity is `org.vortice.next.maintenance_local`, debug, version `0.2.7`,
code `8`. Sole existing certificate SHA-256:
`9b46bb98db0519dbb53c5e17086cc8b16459157275561dcc68174a6cec463b81`.
No signer was created or changed. ARM64 is the primary Android runtime; extra
JNI libraries for ARMv7/x64 do not establish complete runtime support there.

Linux has 17 app files/seven directories/six ELFs. The combined archive preserves
all app bytes and modes and adds exactly seven CLI/help files plus bundle
metadata. Packaging is deterministic and refuses overwrite. Node is not bundled;
the launcher requires an already installed supported Node 22 or newer.

## Executed artifact verification

Both guarded offline builds started with fresh application/native output
directories, with independent copied dependency caches. Tracked source and locks
remain unchanged. Generated Cargokit path relocation/bootstrap, locked offline
Cargo invocation, recipes and toolchains are hash-bound. The initial Android
sandbox local-socket refusal is preserved; the same approved offline build
completed on the host without policy or network-setting changes.

New candidate synthetic service acceptance passes 112 assertions/14 actual CLI
calls for normal office hosting, 21 checks/one call for the legacy client and
98 assertions/18 calls for the extracted CLI. The final run proves the actual
packaged Rust and SQLite libraries are loaded. It covers scoped reads, proposals,
lost-reply explicit retry, idempotency conflict and unchanged inspection/history.
No automatic retry, real workspace or real grant is used. Temporary fixtures
and extraction are removed; failed setup attempts remain separately recorded.

Independent review passes 936 source/artifact/evidence binding checks, including
package contents, all native identities, actual signature and CLI/source inputs.
All 109 files in the earlier 0.2.5/0.2.6 artifact directories retain their hashes.
Review SHA-256: `d639a4e38c7d193d9c11745c594a8a30abd0445298c6f4aa42e209a5a24d668b`.
Composite review SHA-256:
`a413dd4c74d9ec3c191e06fe535fade70cb23deb594aca2ef7af74e43edda036`.

## Exact packaged native identities

GNU Build IDs marked `ABSENT` are absent in the packaged ELF; a Linux or raw
unstripped ID is not substituted. SHA-256 remains the file identity.

| Platform/file | SHA-256 | GNU Build ID |
| --- | --- | --- |
| Linux `maintenance_local` | `55abd575547854e9cd945873ab8981b5555868e691523e7041a2cf9a5fcfe129` | `81ac7d259a23d0db309cbfe873cbdb296b7887c2` |
| Linux `lib/libdartjni.so` | `b081dfca486af45c324047d74c1701270d3eaca44593357af5d4d6b6d2228668` | `17c0fd920395a567457138b2b09dfdfb9dc19ced` |
| Linux `lib/libfile_selector_linux_plugin.so` | `456c9cf58579333e02b2d4ab648aee298216a5761cabc1190afdd6de60264128` | `8afba01e90d7f0d2470d55b3d9b7c5ffdd880819` |
| Linux `lib/libflutter_linux_gtk.so` | `01553f48fb1f9413ea70c184b4f81db9e92fb792f7bf6aeaf77652e071acaf6d` | `25f1b480fdfc45848d105f29c492c5ec908b93d4` |
| Linux `lib/librust_lib_sync_lab.so` | `de8c39cdd1729b391dcf00820af09852653932d64b497d96795575557d1adbb7` | `c1aba474c221d8df080c8f236b3c0f7e8ada68e8` |
| Linux `lib/libsqlite3.so` | `2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5` | `8d00df9c57e6b97adef2df4ab31e492a6bcbd106` |
| Android ARM64 `libVkLayer_khronos_validation.so` | `ae445f7e74d402e3a367adb230b1edd9841899fcb3310166e5cc96a09ad37a3f` | `03eeab8e1148ffdccb650351ab9ef9045e0d4e08` |
| Android ARM64 `libdartjni.so` | `1a691298dba7146ee0603fc82aa024bb20fc4766c5bcd5433574bd1beb8e628d` | `6bc5cda8d752a19376cf58c0f1a082ef259f5bc2` |
| Android ARM64 `libflutter.so` | `5e5a911af31499698997fbd21422b5b7ad35fda89f849ba2cbb4719b4d4e7c95` | `ca67bb4921815d788d830725cb12f34f480ed34e` |
| Android ARM64 `librust_lib_sync_lab.so` | `89e9254e0e42db8e6c80753b1cb5a6075846544605c1051bf028ab4898ef25bc` | `ABSENT` |
| Android ARM64 `libsqlite3.so` | `6d817e14c6d9ec422a2e7649017bca03d94880e10bc3ce451c2a5318de015294` | `ABSENT` |
| Android ARMv7 `libdartjni.so` | `ac98b73158027bd2832eca0c61b08aa81a41c2b0f665a67a3d9ef27592eaceb0` | `bafbb51069eecac5c53f3ca4004a1f31da1be71f` |
| Android x64 `libdartjni.so` | `4c4494bac9db11f4efc98be09ee3d79cbcb1d6ad38bfc52fa9cfa9b2879a9588` | `035784d2b5c9e1beed561dfcf8b104c3746d465d` |

## Recovery and physical handoff

Fresh-folder synthetic recovery passes 72 assertions and four actual owner CLI
cases using the packaged Rust/SQLite libraries, with mappings verified in four
processes. Verify and restore succeed; a wrong office fingerprint and an existing
destination are refused. Restore/reopen preserves the same office identity,
company/equipment/checklist, notes, photo bytes and two immutable submitted
versions with return/approval history. Retries remain idempotent. Phones remain
fenced until explicit synthetic owner confirmation. No CLI grant is issued;
private sidecars stay excluded and restored agent access starts empty/disabled.
All temporary workspaces, backup contents, keys and tokens are cleaned up.
The first harness output-parser failure is preserved separately.
Recovery verification SHA-256:
`efb2d9d0e052d35500d64c7429b07d27fdd1daadeee08e0528adbe4b1d6ebed3`.
Existing product recovery creates a verified private **unencrypted** folder; no
encryption feature or new recovery/permission semantics is introduced here.

The physical owner first verifies the installed approved 0.2.1 package, signer,
sample records and pairing. Save unfinished UI input, capture a consistent
quiescent private-file hash inventory, update the same package in place and
compare private bytes before first launch. Then check original notes/reading/
gallery evidence/history offline, Save/reopen and existing-pairing reconnect.
Use the actual office human for exact-version review and unchanged retry.
No uninstall, data clear, reset, new grant, re-enrollment, competing office process
or network/firewall workaround is part of the recipe. Stop an access change for
parent coordination. The detailed passive recipe is in local
`outputs/027/Physical-Update-Recipe.md`; no phone command has been executed.

The source's same-value CRDT-base no-op policy remains unchanged and documented.
Linux dependency checks establish this build host only: absolute plugin RUNPATH
and an unbundled JVM remain. Earlier source render review explicitly records
missing MaterialIcons, faint navigation-transition captures and 2x scroll/ellipsis
limits; it does not establish physical acceptance. Synthetic fresh-folder recovery is not fresh-computer
portability; USB is not LAN/hotspot or unassisted setup acceptance. No production
merge/deployment, live migration, hosted retirement or real credential change
occurred. Private recovery folders, keys and fixtures are excluded from packages
and source publication.

Local artifacts/recipes/manifests are in `task-8/office-build-artifacts/0.2.7-228091a/`;
CLI evidence is in `cli-027-acceptance/outputs/`, independent audit in
`candidate-027-review/`, and recovery evidence in `recovery-027-acceptance/`.
