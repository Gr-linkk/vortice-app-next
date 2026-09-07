# 0010: Existing maintenance plans drive forward scheduling

Status: Accepted
Date: 2026-09-06
Scope: NOW-013, Garrett's request for substantial forward-facing planning.

Maintenance planning becomes a prominent entry point. The inherited service
interval records and newer component-linked plans are the same source of
maintenance intent. Do not create a second recurrence catalog. Existing work
orders remain the execution records; bookings add timing and estimated duration.

Keep deadlines separate from booked start times. Store booking instants in UTC,
display local times, and use half-open intervals so back-to-back jobs do not
conflict. Flag overlaps for the same asset or assignee; accepting one requires
an explicit reason. Weekly booked hours are estimates, not contractual capacity.

Managers plan online with existing company/capability checks, revision guards
and replay identity. Mechanics see only work they can already read and execute.
An offline report does not become an offline scheduling authority. Completion,
service baseline advancement, fault verification and availability rules from
decisions 0005, 0008 and 0009 remain in force. Legacy billed provider jobs retain
their original execution routes and are accessible from All work.
