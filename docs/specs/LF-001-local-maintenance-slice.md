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
The final integrated `scripts/local-maintenance.sh verify --reporter expanded`
passes locked offline dependency resolution, clean package-wide analysis, four
Rust tests/native build and **111 Flutter tests**. This includes all adopted
runtime regressions, independent workflow/network probes, four strict
startup/restore boundary cases (including actual CLI rejection), ten real-v2
interruption/publication cases, and four ordinary/recovery render cases at 1x/2x.
The strict rejection tests first caught SQLite read-only opens creating WAL/SHM
sidecars; the final ownership-file guard performs no SQLite open on a foreign
folder. The unchanged-byte/file/permission assertions now pass.

Both internal debug builds succeed at `0.2.0+1`. APK metadata confirms application
ID `org.vortice.next.maintenance_local`, label **Vortice Local Maintenance**, and
debuggable mode. Signature verification confirms the existing internal debug
certificate SHA-256 `9b46bb98db0519dbb53c5e17086cc8b16459157275561dcc68174a6cec463b81`;
no new key was generated. Runtime source was frozen at `db6ecbf`; subsequent
`8188e4e`/`96ee764` add tests/integration fixtures only. Final full verification
ran at `96ee76480782f22e2aa5952a0bd0c3f3ae36bcca`.

| Local deliverable | SHA-256 |
| --- | --- |
| `outputs/lf001/Vortice-Local-Maintenance-0.2.0-internal.apk` | `0701d65a0236b5f30c0e64a8724a418ff1125c08993cbeb755e2df2dbad46d5f` |
| `outputs/lf001/Vortice-Local-Maintenance-0.2.0-linux-x64.tar.gz` | `2e32bca44563f19cb922bafe6e1f2085d470ae679942360990768ad5e5278371` |

The packaged Linux archive was compared with every current bundle regular file.
`outputs/lf001/SHA256SUMS`, build/package/signature logs and 50 inspected ordinary/
recovery PNG captures accompany the artifacts. Gallery selection uses the
plugin's synthetic test seam; captures show actual Flutter widget rendering,
Roboto/Material icons and decoded photo pixels. A native desktop integration
session was not launched: there is no disposable Xvfb display here, and the
active physical workspace was preserved. This is a tested internal reviewable
milestone, not proof of device installation or production readiness.

Meaningful integrated commits: `99f780e` isolated runtime foundation; `c3a6fe0`
portable real domain; `084b212` real workflow UI; `16ccb72` shared rules/startup
guard; `008d1c6` real native catalog/job persistence; `003d339` independent probes;
`3cb1a36` older-backup history; `7d0f578` ordinary renders; `60c998c` strict restore;
`b78d1ea`/`db6ecbf` ownership guards; `8188e4e` rejection tests; `96ee764` real
recovery renders. Final review should use the branch tip and these artifacts.

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

## Setup follow-up and independent review remediation

The preceding receipt describes preserved `7192166`, including its original
`0.2.0+1` files. It is not replaced by this follow-up. The parent subsequently
relayed independent PASS for setup source `e6956ae8d3274142cc09fa23c6ced05eda4bac00`
(34 focused checks and two renders). The selective maintenance port uses explicit
file ownership across isolated runtime, Devices, workspace/inspection UI and
independent test workers. Its version is `0.2.1+2`; new evidence goes only to
`outputs/lf001-setup/`.

Evidence correction: the earlier ignored receipt's `applicationTree` field was
stale. The actual immutable `experiments/maintenance_local` subtree at both
`7192166` and verified source `96ee764` is
`87710f4f85ae2e1771a3017746a7a1efb505da17`. The original receipt and binary files
remain preserved byte-for-byte; the new receipt records this correction
separately. Their recorded binary checksums are unchanged and were independently
confirmed by the reviewer.

Independent review of `7192166` is **blocked** on reproduced P2 findings
LF001-AUDIT-001/002: fresh command identities could duplicate an already submitted
document version, and wire `_state` metadata could poison a stored command hash.
Both require deliberately altered requests from an enrolled synthetic phone;
they do not bypass office decision authority. The follow-up must reject them
before persistence, preserve exact retries and actually edited resubmission, and
enforce version uniqueness in imported/recovered history. No store backfill or
live repair is authorized. The audit's recovery-render wait also needed an
absent-finder guard; both cases now pass without screenshot output enabled.

The adapter and reviewer boundaries are documented in
`LF-001-API-BOUNDARIES.md`. Stable follow-up source, full applicable gate results,
separate packaging receipt and independent clearance remain required before
calling this revision ready for the next physical acceptance step.

### Follow-up builder receipt

Verified source is `45380ae6b093a400e8a5f589b19359fe822bfc28`; its maintenance
subtree is `adb8720d6f762da816ae22dfd4c75d0700bd6485`. Later receipt documentation
commits change no application source. `9a4b493` fixes both ingestion findings;
`b07759d` adds ten independently authored TLS/import/private-recovery companions.
Those tests reject both poisons atomically, retain exact-ID retries after later
successors, and allow changed-byte histories even when visible values match.
The original audit reproduction files remain unchanged in the reviewer's frozen
checkout. A fresh internal source review found no P1/P2 in these two fixes;
external combined re-review remains **pending**, and the original `7192166`
review remains blocked until the reviewer clears it.

The reviewed setup port is integrated through `b8d4c76`, `125e7b3` and `45380ae`.
Whole-job confirmation uses the final office bundle's document map. Selecting a
different job retains confirmation; new drafts, queued commands, absent/new job
documents and partial photo/history results cannot inherit it. Safe connection
guidance has independent response tracking: starting a retry retains help, a
fresh actual response clears only associated transport help, and application or
persisted photo-recovery failures remain visible. Invitation dialog/scanning and
enrollment fence automatic sync for the whole manual action; existing in-flight
sync disables connection update. Address refresh invalidates stale invitations,
rechecks the selected address before creation and preserves explicit office code
confirmation and revocation. `SETUP.md` explains manual transfer and hotspot
reconnection without changing network settings.

Fresh full `scripts/local-maintenance.sh verify --reporter expanded` passes
locked offline dependencies, clean whole-package analysis, **four Rust tests**,
native build and **170 Flutter tests**. This includes every original maintenance
regression, ten real-v2 controlled interruption/publication cases, three focused
ingestion checks, ten independent ingestion companions, twelve setup/network
race probes, and eight ordinary/setup/recovery raster cases at 412×915, 1x/2x text.
Three repository isolation tests, service guard and portable domain guard pass.
Both setup renders and both recovery renders also pass without screenshot output.
The earlier retained 879 Flutter / 52 SQL / five browser / repository gates are
preserved prior evidence; the follow-up changes only the experimental app and its
own documentation, so those hosted gates were not rerun for this follow-up.

There are **94 fresh PNG captures** in `outputs/lf001-setup/screenshots/`, with
dimensions and checksums in `Screenshot-Manifest.json`. Actual gallery pixels,
notes, queue/verified states, private copy instructions, code confirmation,
revocation, exact review and restored approval were checked at normal/large text.
Large-text notes instructions now wrap completely. Real loopback TLS and fresh
synthetic catalog/equipment/job fixtures drive verified-status renders; no
fabricated success message or live physical workspace is used.

Linux and Android arm64 debug builds pass at `0.2.1+2`. APK metadata confirms
the separate maintenance identity and existing certificate SHA-256
`9b46bb98db0519dbb53c5e17086cc8b16459157275561dcc68174a6cec463b81`.
All 17 regular Linux archive files match the built bundle. Packaged SQLite,
Rust and Flutter native libraries are present; Linux uses `$ORIGIN/lib` and its
normal relative native-assets manifest. No key was created, device installed or
active application launched.

| Follow-up local deliverable | SHA-256 |
| --- | --- |
| `outputs/lf001-setup/Vortice-Local-Maintenance-0.2.1-internal.apk` | `dece29145fc66d2e0d039b310477c3542bae1da122e92e9bf58b1779f8db7a1d` |
| `outputs/lf001-setup/Vortice-Local-Maintenance-0.2.1-linux-x64.tar.gz` | `982039b67d279ee86905c92f09022d4b0bdf971bd374f0b68d3e0f3982aaa955` |

`Milestone-Receipt.json`, `SHA256SUMS`, native dependency and Linux file manifests,
full gate/build/signature logs and worker evidence accompany those ignored
deliverables. The original `outputs/lf001/` receipt, checksum file and both
`0.2.0+1` binaries were checked against their previous hashes and remain identical.
Build45, retained, cleanup and both source lab checkouts remain clean at their
previous revisions. The next step is independent combined audit, followed by
separately authorized physical gallery/approval/restore and unassisted setup
acceptance. Existing-company import, multi-coordinator failover, engine-cache
ownership and broader identity recovery remain the specific deferred decisions
already recorded above.
