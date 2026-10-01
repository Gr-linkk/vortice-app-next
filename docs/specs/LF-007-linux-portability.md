# LF-007 — Linux desktop runtime portability

Authorized October 1 follow-up on isolated `codex/linux-portable-runtime`, based
on the reviewed 0.2.7 source/documentation head `b09c02b`. The original Android
and Linux candidate archives remain immutable. The physical owner separately
owns the phone and active office session; this increment never opens them.

## Supported runtime and smallest change

Build a distinct Linux x86_64 internal debug distribution with the existing
Flutter, Rust and SQLite dependencies. Keep the application version `0.2.7+8`
and identify the desktop artifact by its LF-007 source revision. No Android,
Dart domain/editor, authority, credentials, dependency lock or hosted changes
are needed.

The locked `path_provider_android` implementation brings JNI into Flutter's
transitive FFI plugin list. The generated Dart registrant invokes it only on
Android; Linux uses `PathProviderLinux`. Upstream JNI already supports building
without an available JVM. Disable optional JNI discovery in this Linux CMake
project, start with a fresh build directory, explicitly clear the discovery
flag, and fail if an unexpected JNI target is nevertheless created. Keep the
generated plugin files and locked packages intact. Do not bundle Java or add a
Java runtime prerequisite. Existing license notices stay in the distribution.

Use `$ORIGIN` for the installed file-selector plugin's sibling dependencies.
Flutter installs that plugin with `install(FILES)`, which does not perform the
usual target RUNPATH rewrite; explicitly build it with its installation RUNPATH.
The application retains `$ORIGIN/lib`. Record every actual packaged ELF's
dependencies, search paths, hashes, GNU Build ID or absence, and symbol versions.

The distribution supplies its application libraries, not an entire Linux
operating system. A compatible x86_64 Linux/glibc system with GTK 3, standard
graphics/display and C/C++ runtime libraries remains required. The CLI continues
to require an already installed Node 22 or newer. No runtime download, system
installation, new licensing acceptance or global environment change occurs.

## Normal launch and prerequisite check

The bundle-root `vortice-maintenance` launcher checks its actual sibling native
libraries before starting `maintenance_local`. `--check-runtime [--json]` checks
only prerequisites and never opens a display or workspace. The standalone
`vortice-runtime-check [--json]` derives its bundle location from its executable;
it uses no source paths, Java, Node, Python or user-data directory.

The checker loads Flutter, file-selector, Rust and SQLite, verifies required
native symbols and executes a SQLite query in memory. The supplied SQLite asset
uses system math symbols without its own `DT_NEEDED` entry; explicitly load
`libm.so.6` first rather than changing the third-party binary. Use the actual
asset's `sqlite3_open_v2`/`sqlite3_close_v2` exports. Fixed errors explain missing
or incompatible prerequisites without dumping loader paths, environment or
credentials. A successful check is native prerequisite evidence, not GUI or
workflow acceptance.

## Ownership and acceptance

Coordinator owns Linux CMake, source integration, fresh offline build, packaging
and this specification/backlog. A separate worker owns the native checker,
launcher and meaningful synthetic regression tests. Independent provenance and
portability reviewers own read-only evidence in separate output directories.

1. Establish the exact locked JNI dependency chain and lazy/platform-specific
   initialization, with upstream optional-build and license evidence.
2. Verify checker/launcher behavior, argument preservation, spaces/symlinks,
   actual SQLite symbols, corrupt/missing libraries and safe JSON failures.
3. Build from frozen clean source with fresh native/application outputs, copied
   independent dependency caches, unchanged locks and locked offline Cargo.
4. Extract to a path containing spaces. In a process mount namespace expose only
   the extracted bundle and compatible system dependencies; hide all source/home
   paths and the host JVM, use clean HOME/XDG and no display/session sockets. Test each
   plugin independently, the normal launcher check and actual in-memory SQLite.
5. Exercise missing required system libraries. Reproduce old absolute-plugin
   and JVM failures under the same isolation, preserving the old archives.
6. Verify exact inventories, ELF identities/search paths, license/provenance,
   CLI packaging/Node truthfulness and source-publication hygiene independently.

The namespace test is a one-host simulation. It cannot establish installation,
GUI rendering, older-glibc compatibility or recovery on a genuinely fresh
computer. Those gates remain separate; no running office, physical device,
network/security setting or persistent access is changed.
