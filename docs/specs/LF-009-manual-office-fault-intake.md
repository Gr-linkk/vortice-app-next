# LF-009 — Manual office fault intake

Garrett authorized this bounded follow-up on the accepted local maintenance
source `98deb62cb3b790f3cc7f7197f9407209033877fd`. The isolated branch is
`codex/local-fault-intake`. The broader LF-008 candidate remains provisional and
is not an implementation dependency or an acceptance result for this slice.
Hosted source, reviewed packages, running phone/office sessions and credentials
remain outside the changes here.

## Ordinary workflow

From the real company office Home, open **Reported faults**, choose existing
equipment and enter a description and **Normal** or **Urgent** severity. A
saved inspection submission, individual step or saved note can optionally
provide exact source attribution. Drafts are not source choices. The office
explicitly records the report; this does not create corrective work.

Every record shows **Reported — corrective work not planned**. The saved-source
observation is captured as pending, approved or returned when the command is
frozen. A subsequent inspection decision does not rewrite that observation.
Source detail is read-only. It retains the exact saved document/snapshot/item
and decision hashes; original readings, units, unknown values and zero values
keep their established meaning. An inspection approval does not verify a fault
or change equipment availability.

## Persistence and authority

`ManualFaultIntakeStore` composes the existing office `LabStore` queue and
transaction without changing native documents, sync, SQL tables or SQL schema
version. The typed `manualFaultIntakeV1` setting contains at most one durable
pending frozen command and immutable receipts. A successful record atomically
consumes that pending command and writes one matching
`manual_fault_reported_v1` event. UUID identity binds company, office device,
equipment, description, severity and optional exact source. The identical retry
returns the original receipt; changed fields under that identity are refused.
There is no automatic deduplication of distinct manual reports.

The form locks before persisting intent. An uncertain failure offers exact
resume, including after closing and reopening the page/app. Editable input is
restored only after reads establish that no durable intent exists. Detaching
JSON getters prevents callers from altering frozen commands or receipts.
Only an office with a real company may read or report faults. No new access
grant, agent command, device enrollment or phone replication is introduced.

The ledger validator checks exact shapes and versions, hashes, company/device
identity, same-equipment saved sources, receipt binding and a one-to-one
receipt/event set. UTC timestamps remain recorded facts; clocks on separate
devices are not assumed synchronized. Existing backup checks retain their
native document, immutable inspection-chain and photo-integrity authority.

## Recovery compatibility

The existing coherent office backup includes the whole SQLite database. This
slice adds semantic validation to its existing inspection boundary; it adds
neither a new backup format nor a SQL migration. Unsupported ledger versions
and corrupt or inconsistent records are refused before writes, with files
retained. Pending intent is included and can be resumed after restore.

Compatibility must execute the actual unchanged accepted `98deb62`
`OfficeBackup.create`, `inspect`, `restore` and reopen against a synthetic new
ledger, not infer preservation from a SQL copy. Compare ledger/settings/events,
catalog, native documents, submissions and immutable inspection receipts before
and after. Then run the new semantic validator and new backup implementation on
the old-restored result. The older app preserving unknown settings/events does
not imply it understands or validates fault semantics. Same-identity restore
continues to fence phones for reconfirmation and retains revocation.

## Integration and acceptance

Independent ownership: new portable ledger models and composed store; new intake
and read-only detail UI; narrow backup validation and actual older-reader proof;
independent frozen-source review. The coordinator owns the normal office entry,
combined source and complete regression gates. Private SDK/pub/hook caches and
temporary synthetic workspaces isolate parallel test runs. Tests use the
accepted 0.2.8 native library, SHA-256
`582b0b00d645d9683512d4426729c633985302322232e3413fca4e7fe015d412`,
GNU Build ID `1d76e8b506aeac40765fdd6b03414d8a6a15f4d7`; native source is unchanged.

Required evidence: valid manual intake and optional sources; exact retry and
conflicting identity refusal; pre/post-commit lost reply and restart/resume;
pending observations after later decisions; office/company/equipment authority;
atomic rollback; strict damaged/unknown-version recovery; actual older-reader
preservation; ordinary Home → intake → detail → Home rendered at 1x and 2x text;
full applicable app, rules, CLI and separation regression gates; independent
review of the final frozen source. Counts and final source IDs belong in the
milestone receipt after execution, not in planned acceptance claims.

## Deferred decisions

Corrective-work coverage/linking, verification/reopening, equipment availability,
automatic checklist failures, recurrence, multiworker/remote sync and production
data import remain separate scope. Physical and unassisted acceptance, a new
binary distribution or device installation are not established by source tests.
No app metadata bump, new signer, release-guard exception, hosted cutover or
live-data migration is part of this intake milestone.
