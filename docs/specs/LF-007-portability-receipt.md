# LF-007 — Linux portability milestone receipt

Built source `0744da8602deb1e665fb12636ba4d9d682b11669` on isolated
`codex/linux-portable-runtime`, based on reviewed `b09c02b`. Application tree:
`1efd7e712d8e91d0a5e6303d0c9a05297e7d8cce`. Internal app version remains
`0.2.7+8`; these desktop archives are separately identified by LF-007 and source
revision. Original candidate archives are unchanged.

## Result and normal use

The new Linux distribution omits unused Android-origin JNI and has no Java/JVM
payload or dependency. File-selector now resolves its sibling Flutter library
through `$ORIGIN`; the application uses `$ORIGIN/lib`. Every packaged native
search path is relative. Generated plugin files, Android, dependency locks,
Dart/domain/editor, office authority, recovery and service/CLI source are intact.

From the extracted bundle, run `./vortice-maintenance --check-runtime --json`
to check prerequisites without opening a display or workspace. Run
`./vortice-maintenance` for the ordinary desktop application; the launcher checks
native prerequisites before forwarding the application arguments. The checker
needs no Java, Node or Python. The separate `bin/vortice-agent` continues to
require an existing Node 22 or newer and explicit private connection settings.

A compatible x86_64 Linux system still supplies GTK 3, graphics/display and C/C++
runtime libraries. Actual packaged ELF requirements reach `GLIBC_2.34` and
`GLIBCXX_3.4.30`; these symbol requirements are not a tested operating-system
support matrix. No operating-system runtime is redistributed or installed.

## Exact frozen artifacts

| Archive | Bytes | SHA-256 |
| --- | ---: | --- |
| `0.2.7-LF007-0744da8-linux-x64.tar.gz` | 49,396,413 | `1073e1f760a0d7020a841449c093466188af4461d9d4c7f5b9357a8e1e4bc372` |
| `0.2.7-LF007-0744da8-CLI-linux-x64.tar.gz` | 49,409,592 | `bc2f55e04ebbb4cdc2141a2a96e125a075b840bb0417c8b9d5f75b95b37f5900` |

The app archive has 18 regular files, seven directories and six ELF binaries.
The combined archive preserves every app byte/mode and adds seven reviewed
CLI/help files plus metadata. CLI source `c64c6c3` and receipt `59b7ac5` are actual
ancestors, and all seven inputs match their reviewed Git bytes. Combined metadata
binds application source `0744da8` and CLI source `c64c6c3`. The unchanged bounded
packager verifies the app digest, is deterministic, and refuses overwrite.
Deterministic archive metadata is distinct from reproducibility of a separate
native build.

## Actual native identities

| File | SHA-256 | GNU Build ID |
| --- | --- | --- |
| `lib/libfile_selector_linux_plugin.so` | `031b5d77427ca64927435a0253da2ca8682ab5c58f6f0d2903564e3d069b61d6` | `2fec41794d3ed9b479642170f45193b3f6bdb0d1` |
| `lib/libflutter_linux_gtk.so` | `01553f48fb1f9413ea70c184b4f81db9e92fb792f7bf6aeaf77652e071acaf6d` | `25f1b480fdfc45848d105f29c492c5ec908b93d4` |
| `lib/librust_lib_sync_lab.so` | `8aabe84b5fa863169a7b82d2686a2f26076e8b369ca2bc3727bd094a29fcf594` | `27792aca9e85951d7a7d8e8a1893a0b2af50463e` |
| `lib/libsqlite3.so` | `2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5` | `8d00df9c57e6b97adef2df4ab31e492a6bcbd106` |
| `maintenance_local` | `4a0b44587359d16af3dd7e1db895f8378740353ff2bb29b079b9f84e3fc12389` | `1671ee422e8bb463cd78c63c2b70f4272bd7fc17` |
| `vortice-runtime-check` | `22bf021788cdc861741a5ec467f16620d400d3635aa7013319d99067233bff8d` | `883d4d7fac9c0f7ecc61878bdfd6ca808817968f` |

## Executed checks and limits

A fresh guarded offline build passed from clean frozen source, with independent
copied dependency caches and fresh application/native outputs. Cargo was locked
and offline, bootstrap/locks/wrappers/toolchains are bound, JNI target/payload
is absent, and all six ELF dependencies/search paths/identities were verified.
The normal host native prerequisite check passed. All 100 pre-existing 0.2.7
artifact files retained their bytes.

The checker/launcher worker passed 26 headless regressions for
spaces/symlinks, missing/corrupt/wrong-architecture
libraries, SQLite failures, argument preservation and bounded noisy/crashing/
hanging native code, and separately passed actual packaged ABI validation.
Frozen packaging tests passed 19 cases; native architecture
separation passed four. The unchanged Dart application retains its earlier full
474-case and rendered-source gates; no new full Flutter-suite execution is
claimed for this Linux build configuration change.

Independent relocation execution passed 18 recorded entries, including its
isolation/environment checks and failure controls. The extracted package lives
at a path containing spaces. Source/home/cache paths and all Java are hidden;
HOME/XDG are clean, display/session sockets absent, and the child-only network
namespace is empty. Separate processes load each library, preventing a previously
loaded Flutter SONAME from concealing a broken plugin search path. The old
archive reproduces its independent-plugin/JVM failures. The new runner loader,
plugin loads, actual SQLite query and packaged checker/launcher pass with normal
and minimally mapped host libraries. Missing GTK and withheld Rust fail through
the intended prerequisite messages. System libraries are test mounts, not copied
into the distribution or modified on the host.

An optional existing `flutter_tester` test runtime, mounted beside the actual
packaged libraries without source paths or preloads, executed the exact packaged
Dart kernel through Rust initialization, Linux path provider and SQLite schema/
settings creation in temporary tmpfs storage. No company, office key/certificate
or grant files were created. The process was intentionally terminated after
12 seconds. This establishes test-runtime bootstrap, not actual GTK embedding
parity, rendered desktop workflow, device or fresh-computer acceptance.

Actual extracted CLI acceptance passed 98 checks across 18 subprocess calls on
Node 26.8.2. It verified scoped reads, pending notes proposals, one lost reply
with explicit identical retry, zero automatic retries, operation conflict and
unchanged inspection hash/history. The new packaged Rust and SQLite libraries
were verified in the fixture's process maps. Temporary fixtures and extraction
were removed. Execution on the minimum Node version is not claimed.

Independent source/provenance review confirms the locked Android path-provider
JNI chain, platform-specific registration and upstream optional CMake behavior.
No Java redistribution is introduced. Existing BSD/JNI and complete license
notices stay intact. The inherited inventory incompletely maps AOSP native JNI
components; the reviewer found no proven binary-license violation. This Linux
omission does not retroactively establish Android license completeness.

Actual GTK desktop rendering/workflows, genuinely fresh-computer recovery,
older-runtime portability and unassisted setup remain open. No phone/ADB/live
UI/office-session action, real credential/grant, network setting, system install,
production merge/deploy, live migration or hosted rollback retirement occurred.
Earlier blocked 0.2.5/0.2.6 binaries and the approved 0.2.7 candidate are preserved.

Build, exact manifests and CLI receipts are local in
`task-8/office-build-artifacts/linux-portable-runtime/`. Independent isolation
and kernel evidence is in `linux-portability-review/`; dependency/license trace
is in `linux-runtime-provenance-review/`. The retained scope is
[LF-007](LF-007-linux-portability.md).

Final independent artifact/source/bootstrap review: PASS, report SHA-256
`41d3626d2bba4eae488b64b2c8fa2f66ec3f22ec025c69399254685ee56298ad`.
Namespace execution report SHA-256:
`7c54142336ddf79b006d4241fd2d0e8c9bfad9d53773746584fd4852e0d53d79`.
Exact packaged-kernel bootstrap report SHA-256:
`b73e577056897d1f5b97eb95c4d88bd34d87a69b1e487ddbf2ee25e00dd12197`.
CLI acceptance receipt SHA-256:
`fee365afb92f0aa9eb8628e90592d3ee92bce62fca0634f364102396617851a4`.
