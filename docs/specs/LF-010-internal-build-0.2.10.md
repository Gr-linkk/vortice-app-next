# Vortice LF010 internal build 0.2.10+11

Office corrective planning is implemented and has passed source and bounded
functional/data-preservation review. Distinct Android, Linux and Linux+CLI
internal artifacts passed their affected gates. Actual extracted Linux UI
created and edited a linked draft, reopened it, then backed up, restored and
reopened the same office with the saved revision and original report retained.
Physical installation, fresh-computer and unassisted acceptance remain open.

- Build source: `b2eed9eb5c2fba6a39ded390af7c73bce8cb0ded`.
- Application tree: `7c07e9523dbc1bcef835663e47f336a153323ece`.
- Tested functional source: `209970a885f9d874ae3753605d958068512f4443`;
  original reviewed receipt: `194a2f801e49318a35396ed1c3f9624b6fb7b2be`.
- Published functional source branch: `codex/local-corrective-planning`,
  verified `95cb1397176b17627d7fe9911036353ade0d35e8`; its subsequent changes are
  documentation only. Default and prior milestone branches are unchanged.
- Matching build branch: `codex/local-corrective-internal-build`.
- Metadata-only application delta: pubspec `0.2.9+10` to `0.2.10+11` and exactly
  two About labels. No behavioral, native, permission, schema or CLI change.
- Application ID: `org.vortice.next.maintenance_local`; debug internal edition.
- Existing Android certificate SHA-256:
  `9b46bb98db0519dbb53c5e17086cc8b16459157275561dcc68174a6cec463b81`.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Vortice-Local-Maintenance-0.2.10-internal.apk | 91,524,445 | `adbc7ab31a10dd3e3eddbfd098945ee79870b0ce30b0faec1ee731f7809a7abc` |
| 0.2.10-LF010-b2eed9e-linux-x64.tar.gz | 49,537,503 | `cd7896bbed48ce4e525f95837b65951143aa6afd27342e95056eb1949458b235` |
| 0.2.10-LF010-b2eed9e-CLI-linux-x64.tar.gz | 49,550,797 | `1b0b62a6721f4b599d34443ed45bf058d2dbd06a9b2a495f7afdfb832fd0db36` |

## Gate attribution

The functional source passed the full 620/620 Flutter suite, clean analysis,
298 Node, 53 Python, four Rust, separation and portable progress gates.
Independent static/code/evidence review passed; parent scoped functional and
preservation review separately passed 89 fresh focused cases, clean changed
analysis and 30 generated renders with seven critical screens inspected.

The metadata build passed clean analysis and 106/106 affected tests using the
new packaged Linux Rust/SQLite, zero errors/skips and a successful terminal.
Fifteen current-reader backup cases ran from an ignored harness copy adapting
only the explicit native SHA expectation and resolving an unchanged helper
import. Tracked tests and assertions remain unchanged. The frozen older-reader
proof is excluded from this new-native run and retained with its original pin;
it passed in the source gate. Original and adapted hashes/diff are evidence.

Android owner verification passed 165 static/native/signature checks.
Coordinator inspection independently read the actual APK manifest/signature,
kernel and seven ELF payloads and verified 22 LOAD segments and native ZIP
payloads meet 16 KiB alignment. Linux passed 21 source-hidden native checks,
98 extracted CLI checks over 18 calls, and one actual extracted CLI/service/human
review integration test. Coordinator separately checked both archives, exact
application/CLI file bytes and modes, and all six Linux ELF identities.
These are distinct gates, not one summed test count or physical acceptance.

Actual GTK used the extracted stock candidate in an isolated namespace with
source and host sessions hidden, a 1x software renderer and synthetic tmpfs
storage. The ordinary path was company/equipment/fault → corrective draft →
planning description edit → launcher reopen → normal verified backup → original
app stopped → fresh empty-office restore with a separately saved public
fingerprint → restored linked draft → final launcher reopen. It retained draft
revision 2, full description, original Urgent fault/time and office fingerprint.
There were 28 successful command replies, 47 screenshots and three restarts.
The draft images before restore and after final reopen match byte for byte.
Two separate read-only evidence inspections passed; no second runtime execution
is implied. Three harmless pointer/rapid-input attempts and renderer/DBus
warnings remain evidence. The private runtime closed and tmpfs was destroyed;
no database, private keys or recovery bundle was exported.

## Actual native identities

| Actual packaged payload | SHA-256 | GNU build ID |
| --- | --- | --- |
| Android / lib/arm64-v8a/libVkLayer_khronos_validation.so | `ae445f7e74d402e3a367adb230b1edd9841899fcb3310166e5cc96a09ad37a3f` | `03eeab8e1148ffdccb650351ab9ef9045e0d4e08` |
| Android / lib/arm64-v8a/libdartjni.so | `5bf4c91b83d3d6b640cffdcd5b2a88ae0eb6d0efd980ecc8e1ddfaad2200c0a7` | `df4344397409f7d18cd2844bf6fe2eb6e68054eb` |
| Android / lib/arm64-v8a/libflutter.so | `5e5a911af31499698997fbd21422b5b7ad35fda89f849ba2cbb4719b4d4e7c95` | `ca67bb4921815d788d830725cb12f34f480ed34e` |
| Android / lib/arm64-v8a/librust_lib_sync_lab.so | `b888699674c8f0a7d2e8af49da8818c94d21a5eeb4919a7227c8fc7f697447ca` | **Absent in actual packaged ELF** |
| Android / lib/arm64-v8a/libsqlite3.so | `6d817e14c6d9ec422a2e7649017bca03d94880e10bc3ce451c2a5318de015294` | **Absent in actual packaged ELF** |
| Android / lib/armeabi-v7a/libdartjni.so | `8e4669a6a20c0764804e7491845e0a8fd0a8a3e9bb699c2978322a417b29922f` | `f9b1f8a96d61a1a43c2b003f877575309a6d7a28` |
| Android / lib/x86_64/libdartjni.so | `14d3d169cea716e37c8d3553e47129d0f1392cfc95f7726146fda719c90a0d2b` | `c76e147649e426beb5c70e71312cd0246a586365` |
| Linux / lib/libfile_selector_linux_plugin.so | `45d34464146d44a8ad2d6d0f7af20e194ff3d4d8ea5359c9a6ff75f6f4e13fa0` | `4e81b5ee4bb50fc9fddb1cc9cc03f89c7f02abb7` |
| Linux / lib/libflutter_linux_gtk.so | `01553f48fb1f9413ea70c184b4f81db9e92fb792f7bf6aeaf77652e071acaf6d` | `25f1b480fdfc45848d105f29c492c5ec908b93d4` |
| Linux / lib/librust_lib_sync_lab.so | `44b455390e8810d763b2ba50130fb6792f01416fbea6677588be1b5673e02ba3` | `4343893c26bd7277eb7ee22b33acc3c98d6dd6eb` |
| Linux / lib/libsqlite3.so | `2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5` | `8d00df9c57e6b97adef2df4ab31e492a6bcbd106` |
| Linux / maintenance_local | `6fd10383b28f647838a6ee8060659f8c3b405f390cf03631f93feba60145accb` | `8b69ece57dcee100af4cbe595ba52e8d9add2102` |
| Linux / vortice-runtime-check | `9cf64fd6ecb2bfe7380fe0b8deb691c0e4d86679822ee18b9e2a3b67b27ddd17` | `14e9c96f486f9c780bb7eccfc632ee2dd16d195d` |

Android Rust and SQLite also have no SONAME. ARM64 is the primary Android
runtime; the extra JNI ABIs do not establish full alternate-ABI support.
Android kernel SHA-256:
`85f1e0990d91cd2d6a9ee727b7528d09d23e189bd63074955990b79585fa73ad`.
Linux kernel SHA-256:
`14a003645bb24cb0b97c4be3996b78e0a8a47499801a49f8be06966f2ebfc7e1`.
Linux aggregate native symbol requirements are GLIBC 2.34, GLIBCXX 3.4.30 and
CXXABI 1.3.9 plus host GTK dependencies. Node 26.8.2 was exercised; Node is not
bundled and minimum-version execution was not proven on a fresh computer.

## Build corrections and preservation

The first Android attempt requested a shared Kotlin daemon control path and
was stopped. No retained shared entries were found afterward, but without a
before snapshot transient control-file creation cannot be excluded. Its logs
and partial attempt remain retained. The corrected fresh run used in-process
Kotlin compilation, private metadata and no daemon/control-path arguments.
Existing signer bytes/modes/mtime and 92,945 prior Android/Linux artifact files
were preserved. Cargokit omits `--locked`; offline resolution and unchanged
tracked locks were verified. Root's first final-analysis invocation stopped
before analysis on a denied telemetry write; the corrected suppressed-analytics
run passed without changing source. Extracted CLI preparation corrected a
copied old native-ID pin before fixture launch; the initial evidence remains.

Hosted rollback, retained fixes, default branch, prior LF009 source/build
receipts and artifacts, phone and live workspace remain intact. LF008 stays
held and excluded. No installation, real grants, live update/migration,
deployment, default merge, public binary release or binary push occurred.

## Upgrade and remaining scope

The first saved planning request selects office schema 3. Older local editions
cannot open that workspace, and no local workspace downgrade is supported.
**Before any real update or migration, give a clear explicit notice and preserve
an independently verified pre-upgrade backup.** Hosted Supabase rollback is a
separate fallback and neither downgrades this workspace nor contains new local
work. Current verification uses synthetic internal candidates only.

Repair execution/submission/approval, fault verification/resolution,
availability, inventory/billing, maintenance advancement, multiworker and remote
relay remain outside LF010. The read-only next-contract map identifies report
completion policy, worker/assignment authority, scope/link coverage, native
ownership/cache and office/phone format choices; it does not authorize execution
implementation. Full application conversion is ongoing.

Durable local evidence is in `outputs/0.2.10-internal/`, including
`LF010-0.2.10-Internal-Artifact-Receipt.json`, separate immutable owner receipts,
coordinator artifact inspections, native gate evidence, GTK screenshots and
`receipt-copies/Corrective-Execution-Contract-Map.md`. The binaries remain in
`android-lf010-build/outputs/0.2.10-android/` and
`linux-lf010-build/outputs/0.2.10-linux/`. Receipt-only revisions after `b2eed9e`
retain its application tree and are bound separately in the machine receipt.
