# 0004 — Fault workflow and explicit asset availability

- Status: Accepted
- Date: 2026-09-05
- Backlog: NOW-003 (completes selection/specification items NOW-002 and NEXT-002)
- Supersedes: N/A

## Context

Garrett authorized autonomous selection and implementation of two features,
with an internal APK delivered to his phone. Existing maintenance flags lacked
repair ownership, verified closure and a durable record of operating state.

## Decision

Implement the journey in `../specs/NOW-003-faults-and-availability.md`:
report, assign, repair, review and resolve faults; independently record asset
availability, reasons and downtime. Preserve the company fleet scope and role
model. Company mechanics work directly on assigned faults. Provider work orders
can link to faults without implicitly closing them or returning assets to service.

Use checked transactional RPCs with revision checks and idempotent operation IDs.
History is actor-attributed and read-only to application clients. Unassessed
availability is explicit. Urgent unresolved faults block marking Available.

Signup roles and organization membership must derive from validated invitations
or server-managed metadata. Caller-editable role metadata is not authoritative.

## Consequences

New writes require connectivity; failures retain input for retry. Offline queues,
company internal invoicing, push notifications and production signing are outside
this slice. The additive backend migration and signup correction must be deployed
to the independent Next backend before the APK's new workflows are usable.
Hosted deployment is pending explicit approval; this decision records product and
implementation scope, not deployment approval.
