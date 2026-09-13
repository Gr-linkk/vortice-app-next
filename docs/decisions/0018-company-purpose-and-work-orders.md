# 0018: Company purpose and one work-order vocabulary

- Status: Accepted
- Date: 2026-09-13
- Backlog: NEXT-006
- Extends: 0016-organization-membership-access.md
- Clarifies: 0011-company-internal-work-orders.md

## Context

Garrett rejected the "Service order" name and clarified that service company
owners should have the full fleet-owner experience, with the additional ability
to perform work for outside customers. Separate demo profiles and internal versus
service-order labels make these look like unrelated products.

## Decision

When a new owner creates a company during onboarding, ask whether they are a
fleet owner, a service provider, or both. This describes the company's activity;
Company Owner remains the same working role in all three cases. Invited people
join their company's existing setup with their assigned roles and permissions.

All three choices retain the full ability to manage the company's own equipment
and maintenance. Service provider and Both additionally enable work for outside
customers. Service provider must not lose fleet functions or require a second
account to maintain its own equipment. Both describes intended use of both
activities; it does not create a third permission tier.

Use "Work order" for every job across lists, creation, details, planning and
opening actions. Retire "Service order" from user-facing work-order naming.
Show whose equipment or customer the job concerns where that helps the user.
Existing service requests, work evidence/reports and invoices keep their distinct
purposes; this decision does not remove customer work or billing.

Work visibility prioritizes own-equipment work or customer work without
switching accounts or changing access. The September 13 implementation request
accepts the proposed Our equipment, Customer work and All work filters. Fleet,
Service and Both initially use own, customer and all respectively; subsequent
choices are remembered per user and company. Ownership determines the group:
an outside provider working on our equipment still appears under Our equipment.

The onboarding prompt is "What will your company use the app for?", with
"Maintaining our own equipment", "Working on customers' equipment", and "Both".
Company services allows the owner to change this choice later. Existing
companies remain unchosen until an owner selects a purpose; their capabilities
and billing settings are preserved.

## Consequences

NEXT-006 begins with onboarding, company purpose and consistent work-order
context, before continuing the previously selected routine-work cleanup.
The existing organization and provider-capability model is the starting point.
Company choice does not grant access to unrelated customer equipment, platform
administration, or billing permission to every team member. Preserve authorized
company relationships, separate costs/invoices, checked completion and history.

Existing accounts, assets and jobs must remain usable. Do not infer a company's
purpose from an old profile label or reset test accounts as part of this work.
Implementation must establish compatible saved settings, server enforcement,
retry behavior and account-scoped view preferences. Implementation and rendered
acceptance evidence are recorded in NEXT-006; physical acceptance is separate.
