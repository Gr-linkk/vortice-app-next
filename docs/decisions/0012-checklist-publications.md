# 0012: Company checklist authorship and immutable execution

Accepted 2026-09-07 for NOW-015.

The owner publishes shared starter checklists. Client managers author private
company procedures or copy a visible starter. Copies retain source/version
attribution and evolve independently. Existing company access and maintenance
capabilities govern authorship, selection, execution and evidence access.

Draft saves use optimistic revisions and stable request identities. Publishing
creates a new immutable template and immutable steps; a later publication retires
the previous version for new work. Existing work keeps its pinned version and
snapshot. Archive prevents new starts without removing historical instructions,
answers or evidence. Concurrent edits must reload instead of overwriting work.

PM and pre-operation checklists share step definitions: check results, numeric
readings with limits/units, text, guidance, critical flags and required photos.
Preview uses the execution controls. Server validation enforces the same rules.
Authored steps are never removed by legacy signature-word filtering.

PM procedures feed provider work orders and internal component plans/jobs.
New planned jobs resolve the current publication; existing jobs retain their
snapshot. Required unresolved answers block completion. Internal service approval
alone advances the linked component interval under the existing maintenance rules.

Pre-operation assignment completion, run/history creation and flagged-answer
fault creation form one idempotent transaction. A retry creates no duplicate run
or fault. Critical findings mark the linked fault urgent. Operators can resume
the version they started, including after publication of a replacement. Offline
execution remains pending until the server accepts it.

Faults connect to corrective work and explicit manager verification; neither a
checklist submission nor repair completion implicitly returns equipment to
service. Original answers remain unchanged. Private photos follow the company
and work access rules, including reads through signed URLs.

Arbitrary scripts, conditional forms, document/AI import and automatic compliance
or safety certification are outside this slice. Physical camera permissions,
device installation and real-world offline/device behavior require separate
device evidence from automated connected tests.
