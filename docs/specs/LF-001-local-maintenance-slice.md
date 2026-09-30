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

Stable candidate `e6956ae8d3274142cc09fa23c6ced05eda4bac00` was inspected read-only
after the parent relayed it. Its independent review is still pending. The planned
selective port is address refresh/invitation invalidation and safe connection
guidance, followed by status updates adapted to **all job documents**. Its
single-document `PhoneSync.visibleMessage` comparison cannot be copied unchanged
into this multi-job runtime. Preparation/workspace/inspection screens must be
merged selectively, retaining real catalogs, frozen context and interrupted-photo
job binding. Port the relevant tests with maintenance identities and TCP 47841;
exclude lab backlog/demo claims and the already-adopted subprocess harness fix.
No part of that candidate is accepted or ported by this milestone.

## Verification receipt

Five independent GPT-6.1 Sol Ultra workstreams handled native persistence/sync,
portable domain rules, workflow UI, adversarial tests and rendered acceptance.
Workers used separate branches/checkouts with file ownership; the coordinator
integrated commits and ran the retained gates. A separate Fast switch was not
exposed by these worker tools. Disposable tooling caches are in task-8. No active
office/phone workspace or physical network settings are modified.

Implemented: office-created company/equipment/procedures/prepared inspections;
frozen checklist context/provenance; null versus zero and pinned meter units;
job-scoped offline CRDT answers, notes and gallery evidence; immutable idempotent
submission chains; exact-version approval/return/history; referenced-only public
photo replication; coherent private backups and reconfirmed recovery. Surviving
phones can resend their own submissions after an older backup, but missing newer
office decisions cause an explicit incomplete-history failure. Phone receipts
never recreate office authority.

Final audit tightened two isolation boundaries: normal UI/CLI restoration requires
maintenance-local-office/v2 before staging, and normal startup checks existing
app/role ownership read-only before chmod/schema/identity writes. Legacy lab APIs
remain fixture compatibility only. Foreign directories and legacy backups are
not silently adopted or converted. Restored ownership markers are written within
the fenced stage transaction before publication.

Retained gates pass: 879 Flutter tests through the official verification script,
clean analysis and portable-Dart guard; 52 SQL contracts plus archive restore/RLS,
populated coordination/report upgrades and Work hub performance; five headless
Chromium checks; 15 repository script tests and two web-preparation checks.
The native four Rust tests pass. The initial combined maintenance regression
passed 103 tests, including the 12 domain cases and 30 independently authored
workflow/network probes. Real-v2 SIGKILL/publication recovery subsequently passed
all 10 interruption cases through the strict normal CLI. Both ordinary workflow
render cases passed at 412×915 with 1x/2x text and actual decoded photo pixels.
Final integrated totals, restore renders and artifact hashes follow below.

Local evidence is in `outputs/lf001/`; generated binaries and screenshots are
ignored deliverables rather than source-control payloads. Original rollback and
source checkouts remain clean at Build45 `9a3b5d3`, reviewed retained `eb2d0d4`,
cleanup `102f630` and active lab `f6608e10`. No merge, push, deployment, public
release, new signing key or live-data import occurred.

Physical gates remain distinct: user-reported lab hotspot pairing, offline note
save/reopen and delivery on reconnect do not establish this new real workflow's
gallery-photo delivery, exact approval or fresh-computer restore. The S24 camera
is broken; gallery images are the accepted path. No physical app installation or
credentials/access change occurs during these synthetic automated tests.
