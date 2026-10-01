# LF-002 — Current inspection work and exact review

Garrett authorized sustained local-first development on September 30. This
bounded increment continues the core company/equipment/checklist/inspection/
office-review/history/recovery/setup workflow. No production cutover, installation,
live import, public release, network-security change, inventory, billing,
multi-company sharing or automatic failover is authorized.

## Isolation and priorities

Base: receipt `b6d1c8d86950439be33921a2c4b6cf1638e71d95`, whose application source
is verified `45380ae6b093a400e8a5f589b19359fe822bfc28`. Parent's independent audit
passed against that immutable target. Worktree: `task-8/maintenance-progress`;
branch: `codex/maintenance-progress-slice`. The earlier maintenance checkout,
receipt, binaries, rollback and running physical workspaces stay untouched.

1. Current work versus immutable versions: fix job cards that still say approved
   after an offline saved edit, or prepared after recording an unsubmitted draft.
2. Focused office review and correction: expose undecided versions near work,
   preserve decided history, and open a returned job's correct current draft.
3. Next bounded candidates: recover interrupted raw editor drafts and author
   future checklist revisions without altering frozen jobs. Their concrete
   storage/publication semantics and acceptance will be inspected before edits.

## Architecture and read-only adapter contract

Add typed progress projections and a bulk snapshot reader outside widgets. Reuse
existing draft validation and evidence integrity checks; do not persist derived
workflow state. Do not edit `LabStore`, sync, approval, native code or backup
schema for this increment. The authoritative command/decision guards remain in
the reviewed runtime. Widget code renders projections and routes pinned job or
submission IDs; it does not invent approval policy.

Capture catalog context, every job's exact byte snapshot, submissions and receipts
under the existing serial queue. Decode those captured bytes, not an implicitly
selected document. Check evidence with `complete`, never `status` or partial-file
publication. A token derived from data relevant to the projection fences late
asynchronous results; selection alone does not invalidate another job's status.
The reader must not mutate documents, settings, events, history or evidence.

Represent draft phase (prepared/incomplete/ready/conflicted/unavailable), required
step progress, conflicts, local photo completeness and existing submission
problem. Separately represent exact-current-document submission records and
immutable historical decisions. Different bytes after edit/revert do not inherit
an earlier decision even if visible values match. Multiple device chains are not
globally ordered by revision or phone clock; ambiguous current records remain
explicit rather than selecting an invented latest authority.

Undecided old versions stay in office review so the coordinator can return them;
they are not silently discarded when a newer draft exists. Received command does
not mean complete photo or approvable current work. The existing exact review
guard remains decisive. Local receipt knowledge is historical, not fresh proof
that a restored office retains a newer decision; existing recovery warnings stay
visible.

## Acceptance and ownership

Runtime/projection worker owns new typed projection/reader modules and focused
unit tests. Workflow UI worker owns workspace/inspection/review integration and
new composed view widgets. Independent test worker owns new race/restart/history
regressions. Render worker owns a new ordinary workflow fixture at 412×915 and
1x/2x text. Workers use separate branches/worktrees; coordinator owns contracts,
integration, scope/version metadata, full gates and receipt.

Prove prepared/partial/complete drafts, approved and returned edit/revert,
queued restart, newer draft alongside older undecided review, two-job selection
and correct routing, optional/NA/no-meter/action rules, missing/conflicting
documents, complete versus partial/corrupt photos, late stale reads and unchanged
raw storage after repeated reads. Unchanged submission reports the existing
command/decision accurately; changed work extends its existing device/job chain.
Render normal entry → approved version → edit/save/back → draft + preserved
approval, and return → correct intended job → resubmit → pending review/history.

Run the full maintenance gate, isolation/domain guards, real rendered checks and
internal builds. Preserve source-versus-packaging receipt commits. Parent audits
each stable revision independently. No phone commands occur while Garrett uses
his phone; reconnecting USB later is not permission to install/reset or evidence
of network acceptance.

## Actual open gates and choices

Combined LF-001 source `45380ae` subsequently received independent PASS: both P2
findings closed, 78 focused checks, eight rendered cases and four capture-disabled
repeats passed; source/receipt trees, package hashes, identity and signer matched.
The independent gates must remain passing in this descendant. Physical gallery transfer,
exact approval, fresh-computer restore/reconfirmation and unassisted setup remain
unverified. Startup-failure recovery navigation and older-backup missing-decision
reconciliation need separately designed bounded flows; no phone receipt promotion
is permitted. Existing-company import, multi-coordinator failover, engine-cache
ownership and production identity compromise/rotation remain deferred choices.

## Desktop CLI coordination

Garrett subsequently chose a desktop CLI for external agents in the future
local-first edition, preserving hosted MCP as rollback/reference. A separate
research task owns the isolated CLI contract and adapter. LF-002 owns only the
progress modules, composed work UI and their tests; it adds no CLI or credentials.

Use the existing serial runtime command boundary, rather than exposing SQLite,
mutable catalog JSON, native documents or private recovery files. Read adapters
can reuse captured frozen work context and this increment's typed progress. Agent
reads must be scoped to the granted company/jobs and must not expose private
identity or backup material. Published-checklist provenance is available; this
slice does not yet provide a general manual repository or hosted MCP parity.

`LabStore` currently distinguishes office versus mechanic. It does not implement
scoped external-agent credentials. An explicit permission-checked service must
precede agent calls; possession of the office filesystem or a mechanic token is
not a new agent grant. Office publication, enrollment/revocation and immutable
approval/return authority stay separate. Consequential proposals need human
review. Use synthetic actors and credentials until a real grant is approved.

Existing submission and decision replay preserve exact frozen identity. Ordinary
`update` is a draft edit, not a general idempotent CLI operation: reapplying an
edit can create different Automerge bytes. The CLI owner must design frozen
operation-ID/payload/result semantics before treating that method as retry safe.
New durable command storage must reconcile the strict recovery schema; it cannot
be appended silently to the reviewed database. Local state, verified whole-job
transfer and immutable approval are distinct outputs. Progress is not evidence
of a fresh successful transfer; use the existing verified-send proof for synced
status. Unsaved human-editor checkpoints remain local UI recovery, outside an
agent's implicit mutation authority.

## LF-002 builder receipt

Verified build source is `bf6960abde5ecde48925119134257999f9801143`, on
`codex/maintenance-progress-slice`. Its maintenance application subtree is
`48ecbc68eb2f51ec9b7afa7caff73bdb908cd5ef`; the portable maintenance-rules subtree
is `1aa19a197d55cd335b8f04e340911bc0297fd632`. The following receipt commit changes
only this specification. Source was clean and frozen before both builds and
packaging. Version is `0.2.2+3`; office port remains `47841`.

The typed read-only projection and composed workspace now distinguish current
prepared, incomplete and complete drafts from immutable submitted decisions.
Office pending review retains older undecided versions, with decided history
separate. Returned-version navigation opens that submission's explicit job even
when another job is selected. The reviewed failed-submit fix refreshes progress
after a durable draft edit, including submission rejection, so changed incomplete
work cannot retain an earlier current approval. Runtime command, approval, sync,
native persistence and backup authority remain unchanged.

The ordinary rendered path starts by creating a company, two equipment records,
a checklist and two inspections through their normal controls. It records and
submits version A, approves the exact version on the office, then edits and saves
the phone draft while the real loopback office is unavailable. The card shows
current draft progress while preserving the earlier approval and frozen context.
An actual returned successor routes back to the intended inspection with its
reason while the other job is selected; a changed submission then appears in
pending review beside the decided history. Optional/NA/no-meter/action behavior,
queued restart, unchanged-command reuse, partial-photo publication, pending
native reads and stale-current approval guards are also exercised. Fresh
synthetic SQLite stores, pinned loopback TLS and a real decoded gallery PNG drive
these states; successful transport or decisions are not fabricated.

The final guarded helper passes locked offline dependencies, clean whole-package
analysis, the standalone pure-Dart progress boundary, **four Rust tests** and
**205 Flutter checks**, including all retained maintenance regressions and **ten
raster cases** at 412×915 and 1x/2x text. Four repository-boundary checks, the
portable domain guard and service/migration isolation guard pass. All six new
progress, prior setup and prior recovery raster cases also pass with capture
disabled at this frozen source. The retained hosted gates are historical evidence
from the preserved baseline; they were not rerun for this leaf-only increment.

There are **136 fresh PNG captures**, 68 per text scale, with dimensions and
checksums in `outputs/lf002/Screenshot-Manifest.json`. The first combined run had
a filename collision between two preparation frames; its 134 files and log are
preserved under `evidence-before-capture-rename/`. The new progress fixture uses a
distinct `progress-office-prepared` name, and the full gate was rerun into an
empty capture directory. Critical large-text draft/history/correction frames and
the complete review footers were visually inspected. Fonts and photo pixels are
real, ordinary actions are reachable, and no overflow was reported. The partial
photo, pending read and stale-current frames show disabled approval with a
reachable return action.

Linux and Android internal debug builds pass. Android Build Tools 36.0.0 confirms
`org.vortice.next.maintenance_local`, version name `0.2.2`, code `3`, and the
existing certificate SHA-256
`9b46bb98db0519dbb53c5e17086cc8b16459157275561dcc68174a6cec463b81`. Flutter,
Rust and SQLite Android runtime libraries are arm64; the JNI dependency also
packages `armeabi-v7a` and `x86_64` copies, so those ABIs appear in APK metadata.
Other-ABI execution is unverified. All seven packaged native libraries match
their declared ELF architectures. All **18 regular Linux archive files** match
the built bundle, including Rust, SQLite and Flutter libraries; the executable
uses `$ORIGIN/lib`, and the runtime asset manifest names `libsqlite3.so`.

| Local deliverable | SHA-256 |
| --- | --- |
| `outputs/lf002/Vortice-Local-Maintenance-0.2.2-internal.apk` | `10828be50e740cfb1b579b9781d510c4942c5be6e763d4b028cccfe4002c82ed` |
| `outputs/lf002/Vortice-Local-Maintenance-0.2.2-linux-x64.tar.gz` | `320ce85eeb4d121dfc878353cf79490a9f124cf9be3fdf040d97715e1bd55c78` |

`Milestone-Receipt.json`, `SHA256SUMS`, screenshot/Linux/native-dependency
manifests, full gate, capture-disabled, build, identity, signature and package
logs accompany the ignored deliverables in `outputs/lf002/`. The preserved
`b6d1c8d` checkout remains clean at its exact revision, and both earlier `0.2.1`
binary hashes were rechecked unchanged. No key was generated, device installed,
active app launched, network configuration changed, live data imported or source
pushed. Internal architecture review closes its demonstrated finding; the
parent's independent milestone review remains pending. Physical gallery transfer,
exact approval, fresh-computer restore/reconfirmation and unassisted operator
setup remain the open acceptance gates recorded above.
