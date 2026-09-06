# 0005: Explicit managed maintenance completion

Status: Accepted
Date: 2026-09-06
Scope: NOW-006, original assessment items 1, 4 and 5 selected by Garrett.

Company and provider teams share a managed job workflow. Existing assets,
components, work orders, reports, parts and history remain the underlying
records. Managed jobs use checked transactional operations; legacy direct
writes cannot mutate them or produce invoices for internal work.

A service job identifies one asset, one component and one plan. Creation
snapshots its checklist and initial meter. Approval requires completed checklist
answers, required stored evidence, diagnosis and repair notes, stopped labour,
and a valid completion meter. One transaction records the immutable approval
snapshot, closes the job, and advances only that plan and its reminder. Internal
costs derive from recorded labour sessions and parts, independent of billing.

Every mutation has an operation ID and exact request payload. Identical retries
have one effect; different payloads under the same ID and stale revisions fail.
Reopening preserves earlier approval snapshots and does not apply the same
service twice. A subsequent service uses a new job, optionally linked as a
follow-up. Approval does not resolve a fault or return an asset to service.

Standalone checklist submissions preserve inspection history and reported
meters. They no longer infer service completion from a template or interval
label. Existing unbound intervals must be explicitly bound to a component
before scheduling through the new workflow; the migration does not guess or
backfill historic completions.

Company fleet scope follows CONTEXT.md. Company execution requires
`pm_checklists`; plan changes and scheduling require `maintenance_planning`.
Assigned mechanics execute; managers approve. History remains readable after
capability disablement. A separate private storage bucket scopes evidence to
the job and forbids replacement or deletion through authenticated clients.

Connectivity is required to persist work. Saved report drafts and stable retries
cover interrupted requests within the current form; durable offline queues,
notifications, inventory movements and calendar scheduling remain later items.
