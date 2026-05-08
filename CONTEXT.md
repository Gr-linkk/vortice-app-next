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
