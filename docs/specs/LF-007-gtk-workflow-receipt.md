# LF-007 — Rendered GTK workflow and refresh repair

October 1 follow-up on isolated `codex/linux-gtk-acceptance`, based on the
published LF-007 checkpoint `ca8eefb`. Production build source is
`16818a996de9782900fc8c9ea7ed8c96beebba37`, internal version `0.2.8+9`.
Test-only descendant `58b4cbaf5c3c4ed9ab602465dec61a8713efc599` adds a bounded
native-readiness wait to the recovery journey helper. Its production `lib/`
source tree, pubspec/lock, native sources and CLI inputs match the compiled
revision. Later
documentation commits do not change those inputs. The earlier
[0.2.7 receipt](LF-007-portability-receipt.md) remains a separate frozen result.

This records the original GTK milestone. Later execution against the current
CLI archive and the new Android candidate is recorded in the
[0.2.8 artifact supplement](LF-007-028-artifact-gates.md); the original local
receipts and binaries remain frozen.

## User-visible repair

The Home page periodically verifies saved work. Previously each verification
briefly removed progress/history rows, contracting the scroll extent. A
controlled native Flutter regression reproduced a scroll offset change from
1641 to 873 while the read was pending. That probe passed its Backup target
rectangle assertion before failing the scroll assertion; it proves scroll
contraction, not that the Backup target itself moved in that baseline.

Home now preserves the last saved presentation while verification is pending,
shows `Updating work status…`, and blocks pointer and keyboard actions on cached
inspection rows and the office progress/history section. Phone submitted-history
links can still open immutable review details. A completed read shows
`Saved work status`;
a failed read clears the cached presentation. Backup and setup remain available
during verification. The strict snapshot is still invalidated immediately, so
inspection submission, whole-job status, document tokens, authority and error
fences retain their existing semantics. The display cache grants no command
permission. General restoration of previously focused links after refresh has
not been established; those links intentionally cannot be activated while the
read is pending.

The launcher also returns a bounded JSON failure on stdout, with empty stderr,
when `--check-runtime --json` cannot execute its missing/nonexecutable checker.
Human output and invalid-argument precedence retain their existing behavior.

## Actual packaged GTK journey

The final combined archive was extracted into a path containing spaces. All
26 regular files were compared to archive bytes and modes before acceptance.
The actual packaged GTK executable, Flutter engine, Rust and SQLite ran with
source, host HOME, session/display sockets, JVM, GPU/input/USB devices and real
workspace data unavailable. Clean HOME/XDG and synthetic office storage were
used in a private mount/process/network namespace. Existing GTK 3 Broadway and
headless Chromium provided the display. Only child loopback was enabled; no host
network or desktop setting changed. Existing compatible host system libraries
were mounted read-only. No runtime installation or download occurred.

Normal rendered controls and the native file chooser completed:

1. Create a synthetic company and equipment, publish a real one-step checklist,
   preview/copy it with source attribution, save/reopen the draft, and publish
   an independent v1 checklist.
2. Prepare an inspection from that publication. Record Pass, meter **0 hours**,
   notes and a gallery image; cancel a replacement without losing the image.
   Save, submit, review the exact submitted version and approve it.
3. Scroll Home across periodic verification and open Backup with a normal
   pointer click. Create a verified backup containing one submission, one
   decision and one complete photo. A second attempt at that existing backup
   destination displays an error and leaves all five backup files unchanged.
4. Restart at an empty launcher. A wrong saved fingerprint prevents restore.
   A matching fingerprint permits checking, but an occupied destination fails
   with the existing-data-retained message. Editing the destination invalidates
   the checked summary and disables restore until it is checked again.
5. Restore into an absent destination, then restart the original empty launcher.
   It follows the saved restored-workspace pointer. The restored inspection
   retains zero, notes and photo; exact-version history retains the approval and
   reviewer. The office's displayed public fingerprint matches the original.

Before deletion, the coordinator verified that the backup photo matched the
gallery fixture byte-for-byte, SHA-256
`0cc929bb73a7d7dcc0833b86b6c801389daaa42f6a2e5e90489af7747ae04e6c`.
Restored GTK screens display the same fixture. Photo equality and five-file
backup preservation are contemporaneous coordinator checks attested in the
receipt; independent reviewers verify the retained public receipt/captures
after deletion of the private backup.
The empty Agent suggestions screen also rendered. Agent proposal acceptance is
covered by separate native/CLI journeys, not claimed as an actual GTK action.

This was assisted execution at 1440×1000, scale 1, using the stock Flutter Linux
software renderer. Forty-three screenshots, fourteen input/reply batches, two
isolated display/application restarts, extraction hashes, native identities and
namespace checks are bound in local `outputs/gtk/Actual-GTK-028-Workflow-Receipt.json`,
SHA-256 `6edc0ea142010cad0970fb5cecc13af3dc6464b82789b97e5c9937056a7aa0ca`.
Screenshot labels describe intended actions; the receipt explicitly identifies
partially populated forms and a still-open inspection image that do not prove
their labels. Acceptance uses the confirmed final images. All namespace
processes stopped, tmpfs workspaces disappeared, and the private synthetic
backup was deleted after its public summary/photo-integrity checks. No key,
grant, workspace database or recovery bundle is published.

## Exact new artifacts and native identities

| Archive | Bytes | SHA-256 |
| --- | ---: | --- |
| `0.2.8-LF007-16818a9-linux-x64.tar.gz` | 49,403,956 | `53ea128004e031844d03aa0422322607689720a65245de72bc5f1f01ef3b0282` |
| `0.2.8-LF007-16818a9-CLI-linux-x64.tar.gz` | 49,416,956 | `6ba5e0e176278d91243dbe58a58841c2ecea5131651693c420a7c1418a011f73` |

Both are internal debug artifacts. The combined archive preserves every app
byte/mode and adds the seven unchanged reviewed CLI/help inputs plus metadata
binding the actual app digest and production revision. CLI source `c64c6c3`
remains an ancestor. Packaging determinism does not imply native-build
reproducibility. No new Android 0.2.8 artifact or device installation is claimed.

| Actual packaged ELF | SHA-256 | GNU Build ID |
| --- | --- | --- |
| `lib/libfile_selector_linux_plugin.so` | `10c23302a479b5f44471b0d7776ac8ff7ac5c1eb500558ac14a86d0fcdfd3cc8` | `5d6dae4a316581ca1849f882665bdd93c19a9d8c` |
| `lib/libflutter_linux_gtk.so` | `01553f48fb1f9413ea70c184b4f81db9e92fb792f7bf6aeaf77652e071acaf6d` | `25f1b480fdfc45848d105f29c492c5ec908b93d4` |
| `lib/librust_lib_sync_lab.so` | `582b0b00d645d9683512d4426729c633985302322232e3413fca4e7fe015d412` | `1d76e8b506aeac40765fdd6b03414d8a6a15f4d7` |
| `lib/libsqlite3.so` | `2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5` | `8d00df9c57e6b97adef2df4ab31e492a6bcbd106` |
| `maintenance_local` | `73537802d5421bdcb7a2a4dbcb75878ba5cd38b6cd80a8c3d33cb2708c995e8c` | `825fa4015f4603c8799148a7dd0dc8177a3be4fe` |
| `vortice-runtime-check` | `2f2dc16bfb860a0646fd6de29938450b35e243b86a2d1426bebf6597542573ce` | `916cd7804619355fed3dba523dd6a1b0459bf58a` |

Fresh offline application/native outputs were built with independent copied
caches, locked Cargo and unchanged dependency locks/native source. JNI/JVM are
absent and native search paths remain bundle-relative. All 143 previously frozen
artifact files retained their hashes. The exact manifests, source/toolchain and
independent artifact audit are local in `task-8/linux-028-build/outputs/0.2.8-linux/`.
`Build-Handoff.json` SHA-256:
`b1abb80e5c8e356920d09aa84c4d6672916fc8ef11dd01acc04ed00111724ad9`.
`Independent-Artifact-Audit.json` SHA-256:
`d966252389137cdff1bb91c8d1d45917bf2f84dc21562ae8b21d5f276dc73f87`.

## Verification and remaining gates

The final full suite on clean test revision `58b4cba` passed **481 Flutter tests,
zero failures and zero skips**, in 339.69 seconds. Whole-package analysis is
clean; all **298 Node tests** pass without failures/skips, and the pure Dart
progress-boundary check passes. Production source objects match the compiled
`16818a9` inputs before and after execution. Full-suite native tests use the
retained Rust/SQLite test binaries (`8aabe84b…` / `2219febf…`) from the unchanged
native source; actual packaged GTK and prerequisite checks use the new native
identities listed above. The two sets of binary identities are not conflated.

Thirty checker regressions, nineteen packager cases and twenty-one source-hidden
packaged checks pass. The earlier
0.2.7 CLI 98-check execution remains bound to its own archive; it is not relabeled
as execution against 0.2.8.

Native Flutter checks cover the Home refresh layout/command fence and four
ordinary proposal/recovery/reopen journeys at phone size and true 1×/2× text.
Separate status-line renders verify readable pending status/history and normal
Backup pointer activation at both scales. These are Flutter test-runtime renders;
the actual GTK evidence above is a separate scale-1 desktop gate.

The full run produced 280 rendered captures, plus ten targeted status captures;
all are 412×915. True 1×/2× recovery/progress cases are distinguished from the
existing proposal cases' recorded scales. Logs, source bindings and render hashes
are local in `task-8/stable-progress-refresh/outputs/028-source-gate/`. Initial
failed executions remain separate: two legacy tests initially lacked their
hard-coded ignored native binary, and two new journey taps ran during the
intentional pending-input fence. The final run seeds the exact retained native
test binary and the nine-line test-only wait uses bounded native settling,
preserves exception checks, and still requires one reachable target before
normal input. No production fence was weakened or failing assertion skipped.

Independent source/helper/render, artifact/provenance and publication-safety
reviews report no P1/P2 findings. The final retained review binds the GTK public
captures and contemporaneous integrity attestations, rather than retaining
private recovery data.

Actual default GPU rendering, a genuinely fresh computer, older glibc/distro/ABI
coverage, minimum Node-version execution, physical phone/recovery and unassisted
setup remain open. The supported host still supplies compatible GTK 3 and
C/C++ system libraries; current ELF requirements reach GLIBC 2.34 and GLIBCXX
3.4.30. No OS support matrix is inferred from this one-host simulation.

Hosted/Supabase rollback, earlier reviewed source and binaries, current phone
and office sessions, production signing and real persistent access are untouched.
Only tested source/docs/tests on a named repository branch may be pushed; no
default-branch merge, deployment, public release, live migration or cutover is
part of this follow-up.
