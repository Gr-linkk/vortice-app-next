# LF-006 distribution receipt

The agent CLI now runs from an extracted Linux package without a source checkout.
It uses an already installed compatible Node runtime and the existing permission
checked local service. It never enables access, starts the office app, creates a
grant or installs a runtime.

Code freeze: `c64c6c3d8270bd8ef70819a81bcb2701c960a33c` on
`codex/local-cli-distribution`, based on receipt `dc9d7f4`. This receipt is a
separate documentation change. The package contains the unchanged application
at `b84070f635498034bdf1807ec776489578218370` (internal debug 0.2.4+5).

## Implementation and verification

- Relocatable `bin/vortice-agent`, fixed JSON setup errors, private token-free
  connection settings and a capability check before requested dispatch.
- Preserved client protocol, scopes, permissions, operation UUIDs, unknown
  outcomes and human review. No direct database fallback or automatic write retry.
- Deterministic bounded packaging, digest-pinned input, exact runtime inventory
  and atomic publication without replacing an existing output.
- 298 Node tests passed: 166 retained client/transport tests and 132 extracted
  launcher cases. All 35 Python tests passed, including 19 packaging tests,
  four isolation checks and 12 operations-tool tests. Syntax and whitespace
  checks passed. The original app, service, rules and native source trees are
  unchanged, so these gates do not claim a new application regression run.
- Actual final-package acceptance passed 98 assertions across 18 packaged CLI
  subprocess calls against a fresh guarded synthetic native service. Reads,
  pagination, a pending notes proposal, a reply dropped after durable acceptance,
  explicit exact retry and conflicting reuse were checked. There were zero
  automatic proposal retries; the inspection hash and history stayed unchanged.
  Temporary fixture data was removed.
- Actual execution used Node `v26.8.2`. Node 22 minimum-version probes were
  simulations; execution on Node 22 was not performed. Help also ran from a moved
  extraction with spaces and Unicode and an unrelated working directory.

Implementation defects found during review were repaired before this freeze:
oversized settings now return `connection_invalid`, and the builder's runtime
input bound now matches the launcher's 512 KiB limit. Every runtime/help input
has exact-bound acceptance and just-over-bound refusal coverage. Code-location
checks now refuse directories writable by other accounts before a credential
reaches the package entry. Trusted sticky ancestors remain usable; special bits
are refused on package directories. Benign permission tests cover ordinary
relocations, refusals and token-empty startup probes.

## Artifact identity and retained application

Local artifact:
`outputs/lf006/Vortice-Local-Maintenance-0.2.4-LF006-c64c6c3-linux-x64.tar.gz`

- Bytes: `49,679,880`
- SHA-256: `02c6a46ff554bd8a0f1234b62ddfc17ace10c3055544d585840b8f64f1234914`
- Original Linux archive SHA-256:
  `c6800522920a4fbee90f80e73b977ecada1fa9c1278bc8a59660665592d66b64`
- All 17 original app files and seven original directory records retain their
  exact bytes, hashes and modes. Both third-party notices are preserved. Only
  seven runtime/help files, their metadata and three directories were added.
- Preserved Linux Rust library SHA-256:
  `adfc5bf8b7c83c7067dba28a0ca0b6f323361d93afc5c94242c72992123af7cc`;
  ELF build ID: `27e66d88e6f6d1291ca8c09f41c002f6d9459479`.
- Preserved SQLite library SHA-256:
  `2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5`;
  ELF build ID: `8d00df9c57e6b97adef2df4ab31e492a6bcbd106`.
- Synthetic service acceptance used the separately pinned test Rust library:
  `1b03d11510bc0146fe63f69e41346a64e315b20cf457df94273e21b9e394fe68`.

The original signed/debug APK and Linux archive were neither rebuilt nor
modified. No new signing key, runtime redistribution, npm dependency or project
license decision was introduced. The metadata detects corruption; it is not a
signature or access grant. The caller must trust the package bootstrap and
installed runtime; same-UID/root changes remain within that operating authority.

## Acceptance limits and evidence

A later independent audit reproduced an in-flight editor input-loss P2 in the
preserved `b84070f` app. Its repair and acceptance run in a separate checkout.
This CLI packaging receipt does not clear that application issue or establish
installation readiness. No new app build or device installation occurred here.

Real grant provisioning, physical acceptance of 0.2.4, unassisted setup and
fresh-computer recovery remain open. Multiworker checklists and internet relay
remain deferred. Hosted rollback, default branch and retained review refs remain
unchanged; publication is limited to the named source branch.

Local evidence under `outputs/lf006/`: `Final-Gate-Status.json`,
`Final-Packaged-Service-E2E-Status.json`, `Final-Content-Preservation.json`,
`Final-Package-Receipt.json`, Node/Python gate logs, `Security-License-Review.md`,
`Source-Hygiene-Review.md` and `Final-Source-Review.md`. The original security
review worker stopped after a platform content flag during final follow-up. Its
prior evidence is retained; a separate read-only review of the defensive source
checks does not claim that the interrupted turn completed. Archives, captures,
fixtures and credentials are excluded from Git. See [usage](../../tools/local-agent-cli/distribution/AGENT-CLI.md)
and [scope](LF-006-cli-distribution.md).
