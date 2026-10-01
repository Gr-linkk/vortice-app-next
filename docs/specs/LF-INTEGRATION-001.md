# Reviewed local workflow integration

Garrett authorized tested source commits and named-branch pushes to the existing
`Gr-linkk/vortice-app-next` repository on October 1. Its existing public visibility
is unchanged. This source integration is experimental: no default-branch merge,
force push, deployment, app release, live-data migration or rollback removal.

## Isolated base and selective transfer

Branch `codex/local-maintenance-integrated-20261001`, checkout
`task-8/local-maintenance-integrated`, starts at LF-002 docs receipt
`eafd35bf0c8ad8b388e252ea2bab59c3722902c6`. Its frozen application source is
`bf6960abde5ecde48925119134257999f9801143`; LF-001 reviewed source `45380ae`
and receipt `b6d1c8d` remain preserved in their own checkout.

- Service: selectively copied only new service modules, unique tests, guarded
  synthetic launcher and contract from `c02d63222811bf3cb82c7b4cb2dda1e019b2a17e`.
  Production service code is `50de2259b3486efbe239c661008ba7abe710d9b5`; the
  followup is a strict SIGKILL helper correction. Already-identical LF-002 pure
  progress modules were retained. No lab history or runtime/DB/sync changes.
- Client: `tools/local-agent-cli/` and its contract copied from
  `7171f395cc2e668e22edb188eaf26a12f2d6b192` in the separate CLI-owned checkout.
- LF-003: its new domain/store/UI/test modules, preparation navigation hook and
  scope copied from `3903d8dc4f257ca5b9a9133bf3551f8ac4cd454b`; both backlog
  entries and existing architecture/service documentation are retained.

The source checkpoints, binary receipts and original running workspaces are
unchanged. Disposable tests, builds, screenshots, synthetic workspaces, keys
and recovery bundles must remain outside tracked publication.

The combined internal build is `0.2.3+4` under the unchanged dedicated
`org.vortice.next.maintenance_local` identity and existing internal signer.
It receives separate local artifacts; earlier validated binaries are retained.

## Combined behavior and boundaries

The office creates equipment and immutable checklists, prepares frozen jobs,
reviews exact submissions and retains history. The phone captures readings,
notes and hashed gallery evidence offline with durable frozen submission
commands. LF-002 projects current draft/readiness separately from historical
decisions. LF-003 saves attributed editable copies privately and publishes new
independent v1 procedures; it never replaces issued snapshots or introduces
family retirement. The publication hash and prepared job snapshot hash have
different meanings and remain distinct.

The CLI uses Linux private Unix JSON Lines protocol1 with explicit validated
workspace/company/service-device scope, default-deny command and record filters,
UTC expiry/revocation and final authorization before durable publication/replay.
Reads are scoped coherent snapshots. Procedures are only publications referenced
by accessible jobs. Neither private office drafts nor unused publications become
agent-visible. Reads report local knowledge and explicitly unverified current
sync. Only write is an exact-version pinned pending `inspection.notes` proposal;
no direct document mutation, submit, approve, publish, grant or billing command.
Real grant provisioning, normal-app service launch and human proposal application
are not implemented acceptance claims.

Office library settings remain in existing complete office backups and outside
phone public bundles. Agent proposal sidecars remain excluded from the existing
strict backup and replication. Do not promote same-directory proposals into
restored-office authority or broaden permission from the office flag.

## Verification and publication gates

Source-only receipts establish component evidence: LF-002 205 Flutter/4 Rust and
136 phone-size 1x/2x PNGs; service 56 native/SQLite/Unix/recovery tests and 21 actual
CLI checks; client 155 Node tests; LF-003 197 Flutter/4 Rust/3 boundaries and
42 renders. These component counts remain provenance; combined counts below
come from the actual combined revision.

Run combined analysis, native/Flutter/Node and repository boundaries, genuine
CLI subprocess/Unix acceptance, distinct library/service privacy and recovery
companions, and normal 1x/2x workflow renders. Independent combined-source and
publication audits must close before the named branch is pushed. Verify exact
origin/current branch/remote refs at action time and verify remote SHA afterward.
Existing CI runs on main pushes or pull requests targeting main; a named-branch
push alone does not establish CI success. Retain local gate evidence explicitly.

`scripts/local-maintenance.sh verify` now supplies the built native library to
all local tests, runs Node CLI contracts, and invokes the guarded synthetic
`cli-smoke` action. `cli-smoke` creates only a new private temporary workspace,
waits a bounded 30 seconds for its Unix endpoint, runs the actual CLI driver,
then stops its own runner and removes its own fixture. It cannot launch against
an existing workspace or provision a real grant. Restricted sandboxes need the
scoped Unix-socket test approval; ordinary development does not change network
configuration. Seven independently authored combined-boundary companions are
retained with the main suite.

## Completed combined milestone

Frozen tested application/CLI/helper source:
`7e9918c966cbdeed5894cd05f00aaefbf62d8d0d`. The corrected whole verifier exits 0:
295 Flutter tests (including seven independent combined-boundary companions),
4 Rust, 155 Node tests with zero skips, and 21 actual CLI/native/Unix checks.
Whole local analysis, portable progress/domain, service isolation and four
repository boundary checks pass. Twelve ordinary render cases produce 178 unique
412x915 PNGs, 89 per text scale, with no name collisions and critical 2x layouts
inspected. Fresh Linux and Android debug builds pass at this exact source.

Independent combined review is clear. Its readiness race is retained as evidence:
the old helper fails with a one-second pause between ready-file writing and
private permissions; the fixed helper passes the same 21 actual CLI checks and
cleans up its own runner. Initial symlink-environment rejection and interrupted
preliminary shell execution are preserved separately and are not final gates.
No product module or reviewed authority rule was changed to hide those failures.

Local ignored `outputs/integration/` holds the build/gate, screenshot, package,
native dependency, independent review and remote verification manifests. These
deliverables are not tracked or pushed. Artifact identity:

| Artifact | SHA-256 |
| --- | --- |
| `Vortice-Local-Maintenance-0.2.3-internal.apk` | `ed887911ab3cd6cffa300b755d5aa877314bd56f50e98f6395962d9b4f0bad26` |
| `Vortice-Local-Maintenance-0.2.3-linux-x64.tar.gz` | `4d3a9767bb50f273bad4dd0d2f6c5b86ad91b9da608662aeb3c3472f0d34bb92` |

The APK is `org.vortice.next.maintenance_local`, `0.2.3+4`, existing certificate
SHA-256 `9b46bb98db0519dbb53c5e17086cc8b16459157275561dcc68174a6cec463b81`.
The application runtime is arm64; additional vendor JNI ABI copies do not prove
other-ABI execution. All 17 regular Linux archive files match the built bundle;
its runtime asset manifest and `$ORIGIN/lib` are verified. The prior optional
build-path manifest is absent from the fresh bundle and is not required runtime
evidence. Earlier validated 0.2.2 artifacts were rehashed and remain unchanged.

The tested source was atomically pushed to
`codex/local-maintenance-integrated-20261001` on the verified existing repository.
Remote source SHA and three separately named snapshot refs were confirmed:
`codex/rollback-build45-9a3b5d3`,
`codex/reviewed-local-maintenance-45380ae`, and
`codex/reviewed-maintenance-progress-bf6960a`. Default main remains
`f6c54e80c2f4e097c7d028c37e7348427517b26d`; repository visibility was unchanged.
GitHub run lookup returns no branch runs, matching the existing workflow's
main/PR trigger rules. Local gate success is recorded independently of remote CI.
This receipt update changes documentation only; it does not rebuild artifacts.

## Physical owner handoff

The separate physical owner controls all ADB/UI work. Compare the actual installed
package/version/certificate before any separately authorized installation. The
new APK can coexist with the lab source's `com.example.vortice_app_next`; same-ID
maintenance 0.2.1/0.2.2 uses this same certificate, but installed compatibility
must be read from the device rather than inferred from source.

After the necessary device/install/enrollment permission, use only a fresh
synthetic company/workspace: create equipment and a checklist, copy/edit/reopen
and independently publish it, prepare two jobs, pair through current-address
manual paste and explicit office confirmation, then save readings/notes/gallery
photo offline and reopen. Submit offline, reconnect foreground and verify the
whole photo hash, exact return/edited successor/approval and history, including
returning job A while job B is selected. Restore a private same-identity backup
to a fresh synthetic office computer and verify old-phone reconfirmation and
revocation fencing. Unassisted setup/hotspot refresh is a separate physical gate.
No camera capture is required for the broken-camera S24; use gallery evidence.

Current sync is foreground/resumed four-second polling plus manual actions;
there is no Android background sender or exponential backoff. Pinned TLS accepts
private IPv4/loopback, not an internet relay. Office mediation remains the topology;
phone-to-phone and near-live multiworker acceptance are future scope.

## Next bounded increment

Preserve this milestone while closing the physical gates through their owner.
The safe next core recovery increment is a private, job/base-hash pinned editor
checkpoint that preserves raw unsaved input across restart and offers explicit
resume/compare/discard. It must not silently apply, submit, approve or merge an
outdated draft, or change the existing strict backup/sync format. The earlier
LF-002 local design provides acceptance cases; use a new isolated branch with
separate storage, UI and adversarial-test ownership.

Real CLI use still requires explicit scoped grant provisioning and a human
proposal-review/application path. Keep agents separate from office/mechanic
authority; do not create real grants while the user is asleep or silently decide
who may replace a mechanic's inspection notes. Current proposals remain pending.

## Open acceptance

Physical S24 gallery transfer, exact office approval, fresh-computer restore and
phone reconfirmation, and unassisted setup remain open. The physical owner has
exclusive ADB/UI ownership. No coordinator device installation/reset or network
change is part of this integration. Multiworker shared checklists and remote
cellular relay are future targets, not this delivered single-office workflow.

Manual office failover, live-company import strategy, engine-cache ownership,
compromised-key/person recovery and reconciliation of decisions missing from an
older backup retain their earlier unresolved policy boundaries.
