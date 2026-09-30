# 0022 — Office authority for the bounded local inspection slice

- Status: Accepted within Garrett's LF-001 implementation authorization
- Date: 2026-09-30
- Backlog: LF-001
- Extends 0012, 0016, 0018 and 0020; no production cutover

Garrett selected local-first maintenance and explicitly preserved the existing
hosted app for rollback. Implement one single-company inspection workflow with
one office coordinator and one enrolled mechanic device. The office OS account
protects coordinator authority in this experimental scope; it is not a complete
multi-person production identity system.

The office creates equipment, publishes company-authored procedures and prepares
work. Preparation freezes equipment context and a complete versioned procedure
snapshot with explicit provenance. A missing external publication cache cannot
invalidate a frozen snapshot: original identifiers and pinned definitions remain
evidence, as clarified by the reviewed soft-provenance decision in the retained
verification branch. This slice does not redefine engine-cache ownership or
global foreign-key policy.

Automerge contains only editable inspection answers, readings, notes and photo
references. Job and snapshot identity markers are pinned. Office catalog and
membership authority are separate. Never infer zero from an unknown reading or
convert units silently. A valid flagged inspection result remains an honest
finding; approving the inspection record does not verify a repair, clear a fault,
change availability, advance a maintenance recurrence or create billing.

Submissions freeze context, document version, values and evidence hashes under
durable IDs. The coordinator approves or returns that exact version. Decisions
and earlier submissions remain immutable when work changes or is resubmitted.
Complete verified evidence is required for approval; a photo reference alone is
not proof that bytes arrived. Replay may acknowledge the same command but cannot
replace its content. Enrollment, revocation and decision authority remain at the
office and are checked when queued work actually executes.

One office authority may run for this identity. Disagreement is explicit manual
resolution; there is no leaderless approval, automatic phone promotion or silent
coordinator failover. Same-identity restoration requires a trusted complete
backup and separately retained fingerprint, with the old office stopped.
Previously revoked phones stay revoked and other phones must be reconfirmed
before later queued work can send. Unsynced data on a permanently lost device
cannot be recovered from the office. Private backup identity is not a public
phone bundle.

Existing-company import, identity compromise/rotation, multi-coordinator
failover, engine-cache ownership, provider/customer replication, inventory and
billing remain separately scoped choices. Use local creation and synthetic
fixtures here. No migration adapter may destroy, relabel or dual-write hosted
data. Production distribution and access changes require separate authorization.
