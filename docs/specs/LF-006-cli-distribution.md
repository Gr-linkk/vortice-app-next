# LF-006 — Usable Linux agent CLI distribution

Authorized October 1 follow-up. Isolated `codex/local-cli-distribution` at
`task-8/local-cli-distribution`, base receipt
`dc9d7f4d78f2046eb9a69cb3921bb481dcaa95b0`. Audited application source
`b84070f635498034bdf1807ec776489578218370` and its 0.2.4 artifacts remain frozen.

## Scope and runtime decision

Add a relocatable executable `bin/vortice-agent` and copied source client to a
separate Linux distribution. Reuse the existing reviewed 0.2.4 Linux archive
without changing its original bytes. No application, service, wire, grant,
approval, database, native-engine or hosted source changes are needed.

Use an already installed Node 22 or newer from the caller's PATH. No Node binary,
npm dependency, installer, download, system-wide integration or new license is
added. The launcher checks the runtime before loading client code, removes Node
module/instrumentation overrides, preserves argument quoting and emits safe JSON
errors for missing/unsupported runtime. Tests record the actual installed runtime;
minimum-version simulation is separate from execution on that version.

## Explicit connection discovery

`bin/vortice-agent work list --connection /absolute/private/connection.json`
reads the exact token-free JSON copied from **Agent connections**:

```json
{"protocol_version":1,"socket_path":"/private/current.sock","scope":{"workspace_id":"WORKSPACE_ID","company_id":"COMPANY_ID","device_id":"DEVICE_ID"},"token_environment":"VORTICE_LOCAL_AGENT_TOKEN"}
```

The file must be a bounded regular non-symlink file, owned by the current UID,
mode 0600, with one link, in its canonical current-UID parent of mode 0700.
No credentials, extra fields, database paths or directory scans are accepted.
Reject duplicate/mixed explicit scope/socket arguments with `--connection`.
The original explicit flags remain supported and use the unchanged client.
Tokens still come exclusively from `VORTICE_LOCAL_AGENT_TOKEN` supplied by the
agent host; the launcher never creates, persists, discovers or requests a grant.

The existing transport independently validates the private endpoint before
transmitting a token. Reopened office endpoints require newly copied settings.
No existing-file chmod, deletion, repair, automatic service startup or fallback
to another endpoint is allowed. Access stays disabled until the office's explicit
human enable/grant actions.

Before dispatching a requested command, use the shared client to read current
`capabilities` under the exact scope. A malformed/version-mismatched response or
missing command/proposal type prevents the requested dispatch. Authorization is
still checked by the service on every call. No automatic proposal retry is added;
lost replies keep stable operation identity and the existing unknown outcome.

## Distribution layout and ownership

Archive root `vortice-local-maintenance/` keeps every original app file unchanged.
Add `bin/vortice-agent`, `agent-cli/{cli,client,contract,transport}.mjs`,
`agent-cli/distribution/{entry.mjs,bundle.json}`, and `AGENT-CLI.md`.
The package metadata binds format `vortice-linux-cli-v1`, client/protocol version,
CLI source revision, original app source/archive digest and explicit file hashes.
It is corruption evidence, not a signing key or a new trust authority.

The caller trusts the package bootstrap and installed runtime. Before executing
the packaged entry with a credential, a token-empty builtin runtime probe checks
code ownership and directory protection. Package directories and files must be
owned by the caller or root and protected from group/other writes. Canonical
ancestors have the same trusted owners; sticky shared ancestors such as `/tmp`
are accepted. Entry repeats the directory checks before client imports. Writable
code locations are refused rather than repaired. Same-UID changes remain within
the office operating-account authority; unsigned hashes are not a signature.

Coordinator owns launcher, entry adapter, this spec, user help/backlog and
integration. Packaging owner owns new `scripts/package-local-linux-cli.py` and
`scripts/test_package_local_linux_cli.py`. Test owner owns new
`tools/local-agent-cli/distribution/test/` and extracted-package E2E only.
Independent security/license reviewer is read-only. All work uses separate
worker checkouts. Existing CLI/service/application files are reserved unchanged.

## Acceptance phases

1. Commit this boundary and runtime/discovery contract before substantive edits.
2. Implement disjoint launcher/adapter and deterministic bounded packaging with
   an explicit original-app digest. Refuse overwrite and unsafe tar paths,
   links, unsupported members, duplicates and unintended source files.
3. Execute the launcher from a moved extracted package containing spaces and
   Unicode, without source-checkout paths or dependency resolution. Test runtime
   refusal, fixed safe errors, malformed/private settings, changed endpoint,
   version/capability mismatch, missing packaging inputs and command quoting.
4. Against a guarded fresh synthetic fixture, exercise actual packaged CLI reads,
   pending proposal, lost-response retry and conflict. Preserve inspection history,
   default-disabled access and no real workspace/grant creation.
5. Run all affected Node/packaging gates, independent security/license review and
   source-publication hygiene. Commit/push only the named source branch; retain
   distribution archives and receipts locally. No installation/deployment/release.

If a new runtime redistribution license, real credential or security permission
is required, pause only that dependent action and report the exact requirement.
