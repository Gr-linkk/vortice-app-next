# 0016: Organization membership and working roles

Accepted 2026-09-11 for NEXT-002 after Garrett approved the simplified
onboarding and organization-role direction.

Extended by [decision 0018](0018-company-purpose-and-work-orders.md) on
2026-09-13: company-purpose onboarding, shared fleet capabilities and one
work-order vocabulary. Working roles and invitation access below still apply.

A person's identity is separate from their organization membership. A new
unaffiliated person who creates a company becomes that organization's Company
Owner. People who arrive through an invitation join the inviting organization
with the roles and capabilities selected by an authorized inviter; they do not
receive owner access by default.

Use four understandable working roles: Company Owner, Supervisor/Manager,
Mechanic/Technician and Operator. A person may hold more than one working role.
Employee describes membership rather than authorization, and a person's job
title does not require another security role. Team administration, billing and
other consequential capabilities can be delegated explicitly instead of being
implied by every supervisory title.

Client/customer is a relationship between organizations rather than a permanent
person role. A company may maintain its own equipment, provide service to other
companies, or do both. Service requests, shared work, customer-visible service
reports and invoices follow an authorized relationship between the companies.
Finance/Billing is an explicit capability. Platform administration remains
separate from customer-company ownership.

The current `UserRole` values and client organization rules are transitional
implementation details. A future slice must migrate profiles, invitations,
memberships, routes and server authorization together. Preserve existing
company isolation and access throughout migration; enforce roles and
capabilities in the backend, retain audit history, and avoid silently granting
broader access to existing or invited users.
