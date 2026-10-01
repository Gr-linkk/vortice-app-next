# LF-010 — Office corrective-work planning

Status: isolated implementation candidate; full combined verification and parent
publication review remain pending. Compatibility was proven before new code.
Base: reviewed LF009 plus metadata receipt `fc086136e1cf9cbfc4ab90c844d2cff62e2d2ea9`.
Coordinator branch: `codex/local-corrective-planning`.

## Accepted meaning

[Decision 0009](../decisions/0009-fault-work-order-workflow.md) allows a
manager to create or link same-equipment open work, several faults sharing one
order, one durable association per active fault, atomic mutations and stable
retries. [Decision 0011](../decisions/0011-company-internal-work-orders.md)
separates repair from inspection and allows revisioned unstarted scope edits.
Garrett's delegated instruction explicitly selects office planning locally.
The office coordinator remains the authority; no phone/agent write authority
is added. This edition retains the accepted inspection workflow separately.

A **corrective work draft** has explicit `kind: corrective`, `state: draft`,
existing company/equipment identity, frozen equipment context, title and
optional planning description, preserving the retained work-order field.
An empty description means it has not been supplied, not a diagnosis.
Diagnosis instructions belong in that description;
there is no completed diagnosis or repair report. Standalone unplanned repair
drafts may have zero faults. One or several reported same-equipment faults can
be linked atomically when creating a draft, or to an eligible existing draft.
Only this explicitly typed open draft is eligible; inspection jobs are not.

Every fault has at most one durable association. A new operation cannot
reassign it, remove its association, or create a redundant same-target link.
An exact retry of the original command still returns its original receipt.
Title/description edits and added associations increment the draft revision;
equipment context, identity and prior associations remain immutable.
Both expected revision and expected draft hash fence stale mutations.

Planning never starts work, assigns it, submits/approves a repair, verifies or
resolves a fault, changes equipment availability, or advances maintenance.
There is no corrective execution document/checklist in this increment.
Priority, assignment, booking, labour, parts, multiworker and remote relay are
not added. LF008 provisional source and restricted probes remain excluded.

## Storage and compatibility contract

Corrective drafts live in office-private setting `correctivePlanningV1`:
`{version: 1, pending: [zero or one frozen command], receipts: [...]}`.
Typed immutable receipts derive the current drafts and associations; there is
no second mutable copy of links or job state. Each accepted operation has one
`corrective_planning_recorded_v1` event, canonically equal to its receipt.
The validator checks exact shapes, supported versions, bounded lengths/counts,
hashes, command identity, revision chains, company/device/equipment authority,
immutable fault-record references and global link uniqueness.

Commands are `create`, `edit`, and `link`. UUID identity binds the entire frozen
intent. Create carries a deterministic draft ID and frozen equipment snapshot;
create/link carry a batch of `CorrectiveFaultReference(faultId,faultRecordHash)`.
Edit/link bind expected revision and hash. Timestamps are UTC evidence, while
receipt order/revision determines sequence; wall-clock monotonicity is not
assumed. An accepted receipt and its event are immutable across later edits.

The first successfully frozen planning command atomically writes its pending
intent **and** advances `PRAGMA user_version` from 2 to 3. Reading or merely
opening planning UI never upgrades a workspace. Existing seven SQL tables are
unchanged. Schema 3 is office-only and requires a real company plus valid typed
planning state; future/unsupported versions fail closed with files retained.
The unchanged prior LabStore refuses versions above 2. Synthetic fixtures must
prove this before implementation. There is no live migration or downgrade.

New backup creation uses Local Maintenance manifest version 3 exactly when its
database is schema 3. The new reader accepts intact old manifest/schema 2 and
validates new manifest/schema 3 coherently. Mismatches, unsupported types,
invalid associations/events/receipts and corrupt pending commands refuse
restoration before destination publication. Old backup readers must reject
version 3; older restore must never silently produce an inspection-only view.
Same-office identity, phone reconfirmation/revocation, existing inspection
documents/submissions/approvals/evidence and LF009 records remain preserved.

The inspection catalog and phone bundle remain their existing version 1.
Corrective drafts are not inserted into `catalog.jobs`, native documents,
phone bundles, agent read snapshots, proposals, grants or CLI history. New
planning events must not expand those readers' record-scoped visibility.

## Agreed public boundary

Pure `corrective_planning.dart` owns `CorrectiveWorkDraft`,
`CorrectiveFaultReference`, `FrozenCorrectivePlanningCommand`,
`CorrectivePlanningReceipt`, `CorrectivePlanningState`, and typed failure.
`validateCorrectivePlanning(settings, events, catalog, deviceId,
manualFaultHistory, databaseVersion)` receives the already validated
`ManualFaultIntakeState` and enforces coherent workspace format.
It derives pending commands, receipts, drafts and `draftForFault` associations.
Factories `createDraft`, `editDraft`, `linkFaults` validate frozen intent.
These signatures were frozen before adapter/UI coding.

`CorrectivePlanningStore(LabStore)` composes the existing serial queue and
transaction. Public commands are `freezeCreate(equipmentId,title,description,
faultIds,commandId)`, `freezeEdit(draftId,expectedRevision,expectedDraftHash,
title,description,commandId)`, `freezeLink(draftId,expectedRevision,
expectedDraftHash,faultIds,commandId)`, and `apply(frozenCommand)`.
Reads are `listDrafts`, `draftForFault`, `pendingCommands`, `receiptFor` and
draft detail. Exact receipt replay is resolved before current revision/link
checks; conflicting same-UUID payloads reject without writes. Each mutation
rechecks authority and coherent state inside `BEGIN IMMEDIATE`, reserves the
bounded receipt capacity before saving intent, and rolls back atomically.

## Ownership and phases

- Coordinator: LabStore early schema/role guard, ordinary Home/fault navigation,
  scope/backlog/architecture documentation, selective integration and full gate.
- Model owner: new pure model and its model tests, isolated model checkout.
- Store owner: new adapter and persistence tests, isolated store checkout.
- UI owner: new planning list/detail/editor pages and phone/large-text renders;
  coordinator owns existing pages' narrow entry hooks.
- Recovery owner: synthetic unchanged-reader proof first, then OfficeBackup
  compatibility/validation hunks and new recovery tests.
- Independent reviewer: accepted semantic/interface review followed by frozen
  implementation/evidence review; no live runtime or LF008 probes.

First freeze the contract and prove ordinary old-reader refusal with synthetic
controls. Then implement disjoint model/adapter/UI/recovery pieces. Integrate
from stable commits and walk the ordinary rendered workflow. Run full applicable
gates and independent review before parent publication readiness. Existing
reviewed source/artifacts, default branch, hosted rollback and phone stay intact.

## Testable acceptance

Create standalone and multi-fault drafts; edit/reopen the planning description;
link additional same-equipment reported faults to an eligible saved draft.
Show exact original fault history and one durable association after restart.
Persist/resume frozen intent across interruption; exact UUID replay produces
one receipt/event, while conflicting, stale, already-linked, cross-equipment,
inspection-target and unauthorized mutations leave state unchanged.

Backup/restore preserves drafts, links, receipts, pending intent and existing
inspection/fault/identity data; a restored pending command resumes exactly once.
Verify unsupported schema/type/manifest rejection and unchanged old schema-2
controls. Assert no corrective records escape inspection bundles or existing
scoped agent readers. Render normal entry/create/detail/edit/link/retry/error
states at phone size and 1x/2x text. Physical/unassisted acceptance remains a
separate gate; no phone installation or live workspace action is authorized here.

## Ordinary rendered workflow

Home offers **Corrective planning** beside **Reported faults**. Merely browsing
does not upgrade a workspace. A saved fault's **Plan corrective work** action
opens its equipment/fault context, then **Create corrective draft** saves a
title and optional planning description. The saved detail identifies corrective
work, its draft revision, linked immutable reports and the next planning actions.
After returning, the fault shows its current corrective association separately
from the historical “corrective work not planned” fact recorded at reporting.
**Open corrective draft** reopens the same association after an app restart.

This normal Home/fault path passed actual native widget execution at 412×915
with 1x and 2x text. It retained inspection catalog/document hashes and the
original fault ledger; ten screenshots cover entry, editing, saved detail,
current/historical fault state and reopened detail. Separate UI-owner native
tests cover standalone/multiple faults, existing-draft selection, edits, stale
revision recovery and saved-request/lost-reply resume. These are rendered
synthetic checks, not physical-device or unassisted acceptance.
