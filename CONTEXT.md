# Vórtice Context

## Client access language

- **Client profile**: the customer account/profile. `assets.client_id` points here.
- **Client org**: the customer's team/workspace. `client_orgs.owner_profile_id` points to the owning client profile.
- **Client team**: people who work for a client through `profiles.org_id` membership in a client org.
- **Org code**: an invite into a client org. It should set both the invited role and org membership.
- **Assigned asset**: a vessel/equipment record assigned to a client profile through `assets.client_id`.

## Current access rule

A client team member sees the fleet owned by their client org's owner profile:

`profiles.org_id -> client_orgs.id -> client_orgs.owner_profile_id -> assets.client_id`

Vórtice owner users see all client fleets and can assign/reassign assets to client profiles. Owner-created assets still belong to a client fleet; they should not silently belong to the owner profile.

Client and client-admin users see only their assigned fleet. Client mechanics and operators inherit the same whole-fleet visibility through their client org; v1 does not use per-user asset assignment.

## Switchboard rule

The client capability switchboard controls optional client-side workflows. Baseline portal access, asset visibility, invoices, documents/history, and service-request intake are always-on. Client-side mechanic/operator workflow access requires the relevant capability switch for that client fleet.

The switchboard also controls creation/invitation of client-side workflow users: `pm_checklists` enables client mechanic invites, and `operational_checklists` enables operator invites. Turning a capability off must not delete, orphan, or reassign existing accounts; it only blocks new invites for that role and hides/blocks the gated workflow surfaces until the capability is enabled again.
