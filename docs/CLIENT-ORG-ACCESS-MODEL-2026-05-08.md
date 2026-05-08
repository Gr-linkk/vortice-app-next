# Client org access model — 2026-05-08

Plain-English rule: **a client owns vessels; a client org is that client's team; org codes invite people onto that team.**

## Terms

- **Client profile**: the customer account/profile. This is the billing/customer identity.
- **Client org**: the customer's team/workspace. It groups the customer and their operators/mechanics.
- **Org code**: an invite into one client org. It should set both role and org membership.
- **Assigned asset**: an asset whose `assets.client_id` points at the owning client profile.
- **Client staff**: client-side operator/mechanic/admin profiles whose `profiles.org_id` points at a client org.

## Source of truth

```text
assets.client_id
  -> profiles.id for the owning client profile

client_orgs.owner_profile_id
  -> profiles.id for the owning client profile

profiles.org_id
  -> client_orgs.id for the team/workspace the user belongs to

org_codes.org_id
  -> client_orgs.id for the team/workspace an invite joins
```

The inherited fleet path is:

```text
staff profile
  -> profiles.org_id
  -> client_orgs.id
  -> client_orgs.owner_profile_id
  -> assets.client_id
```

## Role visibility

| Role | Asset visibility |
| --- | --- |
| Vórtice owner | All assets |
| Vórtice employee | Internal/service view; depends on workflow assignment/RLS |
| Client / client admin owner profile | Assets where `assets.client_id = profile.id` |
| Client admin org member | Assets owned by their org's owner profile |
| Client mechanic | Assets owned by their org's owner profile; work-order actions still depend on assignment |
| Client operator | Assets owned by their org's owner profile; operations history/checklists only |
| User without org/client ownership | No inherited fleet visibility |

## Workflow rules

1. A client/admin creates or already has a client org.
2. Client/admin creates an org code for a mechanic/operator.
3. Registration with that org code must create/update the profile with:
   - `role = org_codes.intended_role`
   - `org_id = org_codes.org_id`
   - `org_code_used = org_codes.code`
4. Staff asset pickers use one client-team asset module, not per-screen hand-rolled queries.
5. No provider should fall back to all assets for a client-side staff user with no org.

## What is intentionally not solved yet

- Per-asset staff assignment/reassignment. Today, client-side staff visibility is org-wide fleet visibility.
- Fine-grained work-order/service-report visibility. That should be audited before broad client-side access.
- Schema renames. Current names are a little awkward but usable; avoid migration churn until needed.
