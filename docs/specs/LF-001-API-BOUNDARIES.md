# LF-001 runtime boundaries for independent review

This summary is self-contained for review of preserved milestone
`7192166cd2411a92cba7bc180b6d3aeff0d3593d` and its reviewed setup follow-up.
Combined verified source: `45380ae6b093a400e8a5f589b19359fe822bfc28` (setup port
plus both submission fixes); full builder gate passes 170 Flutter/four Rust
tests. External combined audit remains pending. Receipt documentation is a
separate later commit and does not alter that source.
Checkout: `task-8/local-maintenance`, branch `codex/local-maintenance-slice`.
The hosted rollback and active lab are separate and untouched. This is an
experimental single-company office-coordinator/mechanic workflow. It grants no
customer access, live import, deployment, installation or network changes.

## Domain and document differences from the lab

Normal setup uses `LabStore.createCompany`, `addEquipment`, `publishChecklist`
and `prepareWork`. The office owns the append-only catalog, publications,
equipment and prepared context. `createWorkspace` and single-document lab paths
remain compatibility fixtures; the ordinary empty UI creates real company work.

Prepared work freezes equipment, meter unit, full checklist, publication/version,
explicit provenance and snapshot hash. Missing external publication cache rows
do not invalidate this evidence. Engine-cache ownership/global FK policy is
unchanged and unresolved outside this slice. Approval records an inspection;
it does not close repairs, change availability or advance recurring maintenance.

Each job has its own Automerge document. `_jobId` and `_snapshotHash` are pinned
identity markers. Editable answers are atomic `answer:<item-id>` maps containing
`result` and string `value`, plus nullable meter, pinned unit, notes and photo
hash. Unknown is never coerced to zero. Conflicts, units, numeric bounds and
required answers are checked before submission. Catalog and membership authority
are not editable CRDT fields.

`fields`, `update`, `attach` and `submit` accept optional `jobId`; real callers pin
the selected job. `documentFor(jobId)` accesses a specific document. The legacy
`document` getter selects only the active job and is insufficient for whole-phone
status. Gallery recovery retains the originating job ID, including after restart.

## Network and immutable history

| Boundary | Real maintenance contract |
| --- | --- |
| Company bundle | `format: maintenance-local-company`, `version: 1`, `catalog`, `officeDevice`, `documents: {jobId: base64Bytes}`, submissions, receipts, referenced blobs, saved time |
| Sync request | Explicit `jobId`; sessions keyed by authenticated device and job; fields revalidated against that job before persistence |
| Submission | Frozen document bytes/hash, values, equipment ID, snapshot hash, real context/revision, submission sequence and predecessor ID; local SQL `_state` is excluded |
| Receipt | Office-authoritative exact-version approve/return decision; immutable alongside its frozen submission |
| Evidence | Separate hashed bytes; only referenced evidence is replicated to enrolled phones; private backup retains all complete evidence |

The phone imports catalog authority only through its authenticated pinned office
endpoint. Existing company/equipment/template/job context cannot be silently
replaced or removed. Same-ID retries have one effect; relabelled or changed
payloads, stale heads, mismatched contexts and cross-job identity markers reject.
One `(device, jobId, documentHash)` version retains one submission identity:
changing only its envelope ID, sequence or predecessor cannot reopen review.
Changed document bytes may extend the chain. Full-history validation enforces the
same version uniqueness during public import and private backup validation.
Wire/local `_state` metadata rejects before persistence. Submission validation
defaults to rejecting this metadata; only the display/getter approval check opts
into `allowLocalState`, because SQL row state is held separately from the command.
Complete hash-verified photo bytes are required for approval. Revocation is
rechecked after body delivery, when queued operations execute and across async
photo publication. `/pair` still requires invitation and explicit office code
confirmation; address refresh does not authorize a phone.

Pinned TLS, the office's explicit enrollment/revocation authority and all wire
payloads remain unchanged by the setup port. Normal app identity is the separate
experimental `org.vortice.next.maintenance_local`, office port 47841, default
directory `maintenance-local-v1`; the lab uses another identity/data/port.

## Recovery and startup isolation

Normal UI and CLI require `OfficeBackupFormat.maintenance`, exact
`maintenance-local-office`/version 2. Compatibility fixture APIs accept legacy
lab format only when the maintenance requirement is omitted. Backup inspection
couples manifest, strict SQLite schema, catalog/documents/history, complete
evidence and certificate/key identity. A lab manifest cannot simply be relabelled.

Restore requires an absent destination and optionally the separately retained
fingerprint (required by normal UI/CLI). It verifies staged copies, fences retained
phones for reconfirmation, retains revocations, discards invitations, checks
authority again and publishes without overwriting an existing folder. Strict
restore writes app/office DB markers and a private flushed
`maintenance-local-owner.json` before publication. Normal startup, restored-page
opening and saved launcher-pointer reopening use `maintenanceOnly: true`.
Existing directory ownership is read before any SQLite open, chmod, schema or
identity write; even read-only SQLite opens can otherwise create WAL/SHM files.

After an older backup, a surviving phone may replay its own exact submissions
before queued successors. Its saved receipt cannot reconstruct a newer missing
office decision. Discrepancy fails before `lastCompleteSync` is written and retains
the phone's evidence/history. Reconciliation is a separately scoped choice. Stop
the old office before same-identity restore; there is no automatic failover,
phone promotion or compromised-identity rotation.

## Reviewed setup port and status adapter

Source: reviewed `e6956ae8d3274142cc09fa23c6ced05eda4bac00` in
`task-2/vortice-sync-lab-setup-ux`. Parent relayed independent PASS: 34 focused
checks and two renders, no P1/P2 findings. Only justified setup files/tests are
ported; no lab fork/history/backlog merge.

The port adds injected local-address discovery, refresh on resume/periodically/
before invitation creation, stale invitation invalidation, safe error guidance,
explicit copy/paste instructions and response-aware UI status. It never copies
raw transport diagnostics, URLs or tokens into guidance. Application, photo and
recovery failures retain their own presentation. A newer actual connection
response may clear its associated transport banner; starting a retry alone does
not clear it. Manual confirmation and revoked/auth-failure states remain visible.
Manual invitation entry/scanning and enrollment fence the automatic timer for the
whole action; a running sync disables connection updates to prevent stale action
completion from replacing newer help or confirmation.

`PhoneSync.visibleMessage`, `lastGuidance` and `connectionResponses` are
presentation APIs. Verified-send status is derived from the **final office bundle's
whole job-ID/document-hash map**, not the selected job or current phone snapshot.
Changing selection alone is harmless; editing any job, queuing a submission or
receiving a partial/incomplete result cannot inherit a previous verified status.
The proof is in-memory, so reopening starts conservatively until another complete
exchange. These fields never grant access or synthesize receipts.

Physical acceptance remains open: S24 gallery evidence delivery, exact office
approval and fresh-computer restore/reconfirmation. Rendered and loopback tests
do not establish those device outcomes. No active physical workspace is taken over.
