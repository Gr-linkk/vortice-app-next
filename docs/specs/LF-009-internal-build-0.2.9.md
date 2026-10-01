# Vortice LF009 internal build 0.2.9+10

Bounded manual office fault intake is implemented and reviewed. The internal Android, Linux and Linux+CLI artifacts passed their affected gates. Actual extracted Linux UI created company/equipment and an urgent fault, then reopened the same saved record. Physical installation, fresh-computer and unassisted acceptance remain open.

- Build source: `f0c8e61c0a9c570001a758351fb70d88b6b05765` on `codex/local-fault-internal-build`.
- Reviewed functional code: `36f3a4d453b83466054163724fcbd5defc2704dd`; published source receipt: `23ea34de81395b0d059375117be9f887c506dfe8`.
- Metadata-only delta: pubspec version and two About version literals. No behavioral, permission, schema, native or CLI changes.
- Application ID: `org.vortice.next.maintenance_local`; debug internal edition.
- Existing Android certificate SHA-256: `9b46bb98db0519dbb53c5e17086cc8b16459157275561dcc68174a6cec463b81`.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Vortice-Local-Maintenance-0.2.9-internal.apk | 91,437,321 | `c77dbb0a8f5f474f3456e308ee1e30568458968d69794ae37583b072fd74cedf` |
| 0.2.9-LF009-f0c8e61-linux-x64.tar.gz | 49,464,739 | `7a75f31a0041c4b3ae4944a35ffe0074f5f0c6aaebd69cd5f7e5766301f11d86` |
| 0.2.9-LF009-f0c8e61-CLI-linux-x64.tar.gz | 49,478,129 | `6a7f5276c411e2d90a54c76588cebc7f0d668b02476f839e2585344b6070e199` |


The original functional source passed 531 Flutter tests. This metadata build passed 49 affected tests using fresh packaged Linux Rust/SQLite, clean analysis, 21 source-hidden runtime checks, 98 extracted CLI checks over 18 calls, and one actual extracted CLI human-review integration test. Android owner verification passed 158 artifact checks. Separate Android and Linux reviewers passed their read-only artifact/evidence inspections. Parent ordinary LF009 functional/data-preservation review passed 50 focused tests plus one legacy restore/resume check and inspected six screens. These counts describe distinct gates, not a single combined test count.

The frozen original old-reader compatibility helper pins accepted 0.2.8 Rust. That one proof was intentionally excluded from the fresh 0.2.9 runtime 49-test run; its original successful source run and separate parent proof remain preserved. Its pin was not changed to make the new runtime pass.

Actual extracted GTK used an isolated namespace and 1x software renderer. The normal UI path was About → create company → add equipment → Reported faults → select equipment → enter description → choose Urgent → record → read detail → reopen → read retained record. It retained the same report time, severity and description. Eleven command receipts and 17 screenshots retain initial missed focus/coordinate attempts as well as final evidence. Runtime exited cleanly; synthetic database and keys existed only in namespace tmpfs and were not exported.

| Actual packaged native payload | SHA-256 | GNU Build ID |
|---|---|---|
| Android / lib/arm64-v8a/libVkLayer_khronos_validation.so | `ae445f7e74d402e3a367adb230b1edd9841899fcb3310166e5cc96a09ad37a3f` | `03eeab8e1148ffdccb650351ab9ef9045e0d4e08` |
| Android / lib/arm64-v8a/libdartjni.so | `888dba6c3ea71e2d0cf817d25f6498ad323eab5b1dc82813062140f4e3d559a5` | `cd551a4b6bfcbfbfd804f94553b82694eb8dbf51` |
| Android / lib/arm64-v8a/libflutter.so | `5e5a911af31499698997fbd21422b5b7ad35fda89f849ba2cbb4719b4d4e7c95` | `ca67bb4921815d788d830725cb12f34f480ed34e` |
| Android / lib/arm64-v8a/librust_lib_sync_lab.so | `63b365852a9c25654d682afdde9d3bcf9f0cb6f739d66a076e8dd22f2ce16912` | **Absent in actual packaged ELF** |
| Android / lib/arm64-v8a/libsqlite3.so | `6d817e14c6d9ec422a2e7649017bca03d94880e10bc3ce451c2a5318de015294` | **Absent in actual packaged ELF** |
| Android / lib/armeabi-v7a/libdartjni.so | `04159316f4ffb6f60cdd2be1036114ab3bb660622c30cb53738edc96e68bc8a0` | `e21d4ea213c23e7d328797b225589bd5869661c5` |
| Android / lib/x86_64/libdartjni.so | `d55fb69620166fb35b7886ac56a03fec5e069ea9d2c014dee86c3873774c44dd` | `479245497bd147ac72f9f67a13077bdb7dedd778` |
| Linux / lib/libfile_selector_linux_plugin.so | `570b47c62f3269acb3c47bb1b283352f070b844ffd327c084b17bdf3e5c70076` | `ca863a3df405923fdb598792ccfac766b863e9e8` |
| Linux / lib/libflutter_linux_gtk.so | `01553f48fb1f9413ea70c184b4f81db9e92fb792f7bf6aeaf77652e071acaf6d` | `25f1b480fdfc45848d105f29c492c5ec908b93d4` |
| Linux / lib/librust_lib_sync_lab.so | `8fdcb0f3f7a9e007a901a5d6d4cbe12542cde91ea04be7cd7791f8d959821e6b` | `bca74ca037aa0e32dddcc868a5ea9932051e225f` |
| Linux / lib/libsqlite3.so | `2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5` | `8d00df9c57e6b97adef2df4ab31e492a6bcbd106` |
| Linux / maintenance_local | `5e350030837468c5bab32a045114ccf8629884850d35c8e8d38817f2c252da14` | `cac2d08e115d7ac62da3d1c914ed07c3568aa499` |
| Linux / vortice-runtime-check | `cf14665b509bf9d3541e0889e67e00835ee9733d32daaa929a9a97af5ffaf3bd` | `84a3a44909510c769f7a9963a1d4981a98ab0152` |


Android Rust and SQLite also have no SONAME. All 22 Android LOAD segments and all seven stored native ZIP payloads meet 16 KiB alignment. ARM64 is the primary runtime; additional JNI payloads do not establish complete alternative-ABI support. Kernel SHA-256 is `97b789d02807c1df162727c3bdb47d2cf76c2ffaff48003552c93c01e470fd7c`.

Prior 0.2.7/0.2.8 artifacts and the existing signer remained unchanged. Installed 0.2.7, live office, phone, network settings, company data and real grants were untouched. Supabase rollback remains intact. LF008 stays held and excluded. Corrective-work planning semantics are unimplemented.

Remaining limits: same-host Linux proof does not establish fresh-computer/older-distribution acceptance; required native symbol maxima are GLIBC 2.34 and GLIBCXX 3.4.30. Node 26.8.2 was tested and Node is not bundled. Android Cargokit omits --locked; offline resolution and unchanged tracked lock/source were verified. No physical/GPU/unassisted use or production/public release is claimed.

The source milestone is already retained separately in Library as `libfile_6c0f52a269508191be5644b4396bd501`; this build receipt is a new distinct item. Full local machine-readable receipt: `outputs/0.2.9-internal/LF009-0.2.9-Internal-Artifact-Receipt.json`. Artifact ownership and raw native notes are bound in the Android/Linux handoffs.
