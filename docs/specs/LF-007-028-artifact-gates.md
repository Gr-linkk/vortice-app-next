# LF-007 current 0.2.8 artifact gates

October 1 supplement to the [GTK workflow receipt](LF-007-gtk-workflow-receipt.md).
The reviewed and published source stays at
`98deb62cb3b790f3cc7f7197f9407209033877fd` on
`codex/linux-gtk-acceptance`. Linux was compiled from production revision
`16818a996de9782900fc8c9ea7ed8c96beebba37`; the full source gate ran on test-only
descendant `58b4cbaf5c3c4ed9ab602465dec61a8713efc599`. The production, native,
dependency-lock and CLI inputs match the documentation-only descendant used for
Android. This supplement changes no application or build inputs.

## Extracted CLI execution

Fresh execution against the actual current combined Linux archive passed
**98 checks across 18 CLI subprocess calls**, using Node **26.8.2** and a
private synthetic Unix-socket service. Scoped reads/pagination, pending notes
proposals, one deliberately lost reply, explicit exact retry, conflicting
idempotency reuse and unchanged inspection hash/history passed. No automatic
proposal retry occurred. The actual packaged Rust library was loaded from the
extraction; the fixture's loaded SQLite bytes matched the packaged library.

`CLI-028-Acceptance-Receipt.json` SHA-256:
`62c9176d44096d002b6404f29bf5d4b3b73facaa062d34fa8989ee83dea2e7c9`.
The independent CLI audit passed, SHA-256:
`39312ae0d7918440c3b602fd947e1cd57e1df5b2b210cc412b5a93659e23f3f3`.
The fixture exited successfully and its temporary workspace, extraction and
private homes were removed. Both current archives and all 143 prior original
files were rechecked unchanged.

Two refused attempts are retained separately: the transport rejected an overly
long socket path before client execution, and the managed executor refused a
private Unix-socket bind. A bounded approved rerun used a short private path,
the same unchanged driver and the same permission checks. No network or host
security setting changed. This current execution supplements the separately
preserved 0.2.7 result; that older result is not relabeled.

## Android build and packaging

The new internal debug APK is **0.2.8+9**, application ID
`org.vortice.next.maintenance_local`, label **Vortice Local Maintenance**,
minimum SDK 24 and target/compile SDK 36. It was freshly built from clean
`98deb62` using the guarded offline build and complete owned Flutter, Android
SDK and Rustup copies. The recorded build ran 235 Gradle tasks: 234 executed,
one up-to-date and none restored from the task-output cache.

The existing signer was reused without alteration. Its certificate SHA-256 is
`9b46bb98db0519dbb53c5e17086cc8b16459157275561dcc68174a6cec463b81`.
No new key or release-guard exception was introduced. All 100 files in the
approved 0.2.7 artifact directory remain unchanged.

All seven actual packaged ELF files, their upstream/raw/stripped provenance,
GNU Build IDs or their explicit absence, 22 LOAD segments and 16 KiB APK payload
alignment passed independent native inspection (294 checks). Rust and SQLite
have no GNU Build ID in the actual Android payload; Linux identities are not
substituted. The primary runtime targets ARM64; extra third-party JNI libraries
do not establish complete application support for other ABIs.

| APK native payload | GNU Build ID |
| --- | --- |
| `arm64-v8a/libVkLayer_khronos_validation.so` | `03eeab8e1148ffdccb650351ab9ef9045e0d4e08` |
| `arm64-v8a/libdartjni.so` | `97504dd964eefb7bba58b578ac4b7f68c999f4f8` |
| `arm64-v8a/libflutter.so` | `ca67bb4921815d788d830725cb12f34f480ed34e` |
| `arm64-v8a/librust_lib_sync_lab.so` | Absent |
| `arm64-v8a/libsqlite3.so` | Absent |
| `armeabi-v7a/libdartjni.so` | `50824d992aa48eecd7db60c585574bb04893a848` |
| `x86_64/libdartjni.so` | `1184c7ff56d11f7272da295de624789d51cd0b6f` |

The build receipt records complete native SHA-256 values, compiler/toolchain
identities, recipes and source/provenance bindings. Android Cargokit invokes
Cargo with offline resolution; the tracked Cargo lock remained byte-identical
before and after the clean build. Its invocation does not include `--locked`,
so explicit Cargo locked-mode execution is not claimed.

An interrupted first attempt used shared SDK paths and refreshed **five
generated metadata files**: four Flutter Gradle lock/probe/output files and
Android SDK `.knownPackages`. The attempt was stopped. Those metadata files were
not reverted. The corrected fresh build used complete private toolchains and
private Java/Android user homes; the five shared paths remained unchanged after
the stop. Thirteen compiler/snapshot/JAR/API inputs were verified unchanged.
This is recorded in `Shared-SDK-Isolation-Correction.json`; it is not described
as complete shared-toolchain immutability.

The final independent artifact audit passed **403/403 checks** (109 main and
294 native), with no P1/P2 findings or build/packaging blockers.
`Independent-Artifact-Audit.json` SHA-256:
`d0f53e69f96bff27b23544666dbb715744de39fa80ca01d80bba65dbedc55b6d`.
`Android-Build-Receipt.json` SHA-256:
`320ebdb1a84ccf8838b4172264e43865e64c47eeaeccf04c47bc6d88cbe0f96e`.
The initial prebuild disposition remains separate from the final verified
internal-candidate disposition, which keeps physical acceptance open.

## Current deliverables

| Internal artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `0.2.8-LF007-16818a9-linux-x64.tar.gz` | 49,403,956 | `53ea128004e031844d03aa0422322607689720a65245de72bc5f1f01ef3b0282` |
| `0.2.8-LF007-16818a9-CLI-linux-x64.tar.gz` | 49,416,956 | `6ba5e0e176278d91243dbe58a58841c2ecea5131651693c420a7c1418a011f73` |
| `Vortice-Local-Maintenance-0.2.8-internal.apk` | 91,376,093 | `98742ef342ee861f8c678574ba892a0712c34f941f302899438bf4c9f82e09fe` |

The prior GTK milestone remains bound to its original immutable receipt. The
coordinator's additive `Current-028-Artifact-Gates.json` binds that milestone,
the new CLI receipt, Android build and independent audit, all actual native
identities, source equivalence and current artifact bytes. These ignored local
deliverables contain no private workspace, grant, recovery bundle or signing key.

## Remaining acceptance

The existing 481 Flutter/298 Node full gate, 290 recorded renders and assisted
packaged GTK workflow remain the source and UI evidence. This supplement adds
current packaged CLI execution and Android build/packaging evidence. It does
not establish an Android installation or physical phone acceptance.

Physical gallery/submission/approval/recovery and unassisted setup remain open,
along with a genuinely fresh computer, default GPU rendering, older runtime/
distro/ABI coverage, minimum supported Node execution and general keyboard
focus restoration. The same-host GTK run used the software renderer.

Hosted/Supabase rollback, earlier reviewed source and approved binaries remain
preserved. No device, live office, network, persistent real access, production
deployment, cutover, default-branch merge or public release was changed.
