# LF-001 — Real local-first equipment inspection slice

Authorized September 30, 2026. Experimental implementation; no hosted cutover.

## Chosen base and isolation

Checkout: `/home/garrett/Documents/Codex/2026-09-30/task-8/local-maintenance`.
Branch: `codex/local-maintenance-slice`. Base:
`eb2d0d4b5d9f582f4dce45d099fe1d15824c75bf`, descendant of retained Build 45
`9a3b5d3` through `0e1e6ab` and `102f630`. The retained baseline, active lab,
cleanup checkout and setup UX builder remain untouched. Origin is only the
independent `Gr-linkk/vortice-app-next` repository. No push or remote query.

Branch evidence was inspected in task-7's Integration-Plan before implementation.
Lab `f6608e10e1d5460a7657f6c5cf6e204123d48e24` shares the older Build 40 ancestor,
so it is not merged. Only its standalone native package is staged under
`experiments/maintenance_local`, preserving pinned Rust/bridge/dependency licenses
and original adversarial tests. Its old backlog/project authority and synthetic
acceptance claims are excluded. Domain behavior is extended here using the
retained pure-Dart checklist rules. The package uses application ID
`org.vortice.next.maintenance_local`, data folder `maintenance-local-v1`, Linux
override `VORTICE_MAINTENANCE_DATA`, and office port 47841. The active lab's
identity, data and port are separate.

## Phases and selected workflow

1. Inspect source/rules and stage the isolated native runtime.
2. Add office-created equipment, published procedure definitions and immutable
   prepared inspection context. Keep catalog authority outside editable CRDTs.
3. Build ordinary office/phone paths: setup, preparation, offline check/numeric/
   written answers, readings with units, notes, saved photo, durable submission,
   exact-version review/return/approval, history and coherent recovery.
4. Run complete retained/native regression, independent authority/replay/photo/
   restart/restore probes, rendered phone-size 1x/2x checks and internal builds.

The first workflow is an equipment inspection record. Flags are visible findings;
approval does not mark repairs complete or change asset availability. The normal
empty office asks for a company, then equipment, then a published procedure and
prepared work. No fixed demo generator is the real workflow. Synthetic seed
helpers remain only for original runtime regression fixtures.

## Boundaries and specific decisions

- **Coordinator disagreement/failover:** safe default is one office authority.
  No automatic promotion. Stop the old office before same-identity restore;
  reconfirm phones after restoring an older backup. Multi-coordinator arbitration
  and compromised identity rotation need a separate design and approval.
- **Existing-company import:** local creation only. Frozen retained provenance
  is an input to a future reviewed importer, not permission to read live data.
- **Engine cache ownership:** no changes to retained engine relations or global
  FK enforcement. Inspection equipment context is frozen independently of a
  hosted engine cache; telemetry/generator integrations are outside this slice.
- **Identity/recovery:** office OS account plus pinned local TLS and explicit
  enrollment; trusted private backup plus saved fingerprint. This is an
  experimental authority model, not broad production person/account recovery.
- **Publication/access:** single company and mechanic only. No customers,
  provider-private replication, live credential changes, invoice/inventory
  expansion, release-guard bypass or new signing key.

The setup UX builder owns the separate address-refresh/plain-language-error/
dialog-resume follow-up from the lab. Only a stable parent-relayed commit may be
reviewed and ported later; its active files are not edited here.

## Verification receipt

Implementation/test results and exact milestone commits will be appended after
integration. Initial native build and four Rust tests pass on cached toolchains.
Tooling is copied into task-8 writable cache locations; the original SDK, active
office/phone workspace and physical network settings are not modified.

Physical gates remain distinct: user-reported lab hotspot pairing, offline note
save/reopen and delivery on reconnect do not establish this new real workflow's
gallery-photo delivery, exact approval or fresh-computer restore. The S24 camera
is broken; gallery images are the accepted path. No physical app installation or
credentials/access change occurs during these synthetic automated tests.
