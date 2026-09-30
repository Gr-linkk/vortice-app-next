# Dependency notice evidence

`dart-licenses.json` and `rust-licenses.json` describe the installed locked
packages. `licenses/` retains their exact notice text. The generator copies
these into the APK/Linux assets as `THIRD_PARTY_NOTICES.txt`; the app's About
screen exposes them through Flutter's license page. This does not select a
license for Vortice or authorize publication.

Some published Rust archives omit their repository license. `upstream/` stores
those notices with pinned public source URLs and SHA-256 values in `sources.json`.
The Automerge 0.12.0 archive's recorded VCS commit was unavailable from GitHub;
its notice is taken from the official `rust/automerge-0.12.0` release tag at
`1755d0dbd9a467cb849cf08a5c86e207835f5533`. Other fallback notices use the crate's
recorded source commit. The r-efi AUTHORS document includes its copyright and
license grants. Nested notices and case-insensitive filenames are included.
When the Rust lock contains two versions of a package, separate versioned notice
files prevent one version's copyright/license text from replacing the other's.
The generator verifies every final notice hash before producing the bundle.

Regenerate after dependency changes, with the pinned packages already fetched:

```bash
CARGO_HOME="$HOME/.local/share/vortice-sync-lab-toolchain/cargo" \
  python3 experiments/sync_lab/tool/inventory-dependencies.py
```

The inventory includes target-specific and build dependencies from the lock;
not all are linked into Android/Linux. No Syncfusion or ML Kit is included.
Flutter/GTK/OpenSSL runtime prerequisites are listed in the lab README.
