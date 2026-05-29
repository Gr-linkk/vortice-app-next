# Vortice V2 Product, Roles, And Principles

Date: 2026-05-24
Status: detailed planning draft for Garrett review

## Garrett Question Inbox

1. **Staff role permissions:** Garrett clarified that `service_manager` is not a role. Which permissions belong to the current app roles from the dev login/profile enum?

   Garrett answer: Use the current app dev login/profile enum as the role source of truth. There is no `service_manager` role. Vórtice Owner/Admin is the current `owner` role and can handle everything, including edits to checklist templates and other admin-controlled setup. Vórtice Tech/Mechanic maps to the existing staff `employee` role for now and should not edit checklist templates or admin setup. Billing/office is a permission lane, not a confirmed role: users with that permission can build, send, and export invoices to customers inside the app.

2. **Client view-only role:** If all primary client users are client admins, do we still need a limited read-only client/contact role for invoice/report visibility?

   Garrett answer:

3. **Operator role model:** Should `operator` and `client_operator` collapse into one role model scoped by org/client membership, or remain separate labels?

   Garrett answer:

4. **Client mechanic history:** Can client mechanics see operations checklist history, or should they only see maintenance history? Current direction says they can see both.

   Garrett answer:

5. **Staff fleet visibility:** Should Vortice employees see all client fleets by default, or only assigned work/assets unless Vórtice Owner/Admin grants broader access?

   Garrett answer:

6. **Capability visibility:** Should capability switches be visible read-only to clients, or hidden unless a disabled feature is attempted?

   Garrett answer:

7. **Pricing language:** Should V2 expose pricing/package names anywhere in-app, or keep the app purely capability/workflow based?

   Garrett answer:

8. **Client-facing terms:** What client-facing language should replace internal words like `resolved`, `pending_review`, and `work order`?

   Garrett answer:

## Resolved From Garrett Notes

- V2 should be a rewrite/salvage pass: preserve hard-won product and schema progress, but do not keep the messy current workflow implementation as the shape to build around.
- First production target is mobile field use. Tablet/desktop office workflows can follow, but phone UX is the first acceptance path.
- Current app roles are the source of truth for V2 role names until Garrett explicitly approves a schema change. `service_manager` is not a role. Billing/office is a permission lane, not a confirmed role.
- Primary client-side users should have client-admin powers by default. A weaker view-only client/contact role is only needed if Garrett confirms that use case.
- V2 must ship English and Spanish support in the first build, not English-only with localization later.
- First V2 pilot target besides Paradise Marina dredge is a general client/worksite. Do not overfit V2 around the dredge telemetry pilot.
- Minimum V2 launch promise is the full workflow set defined so far: client portal/history, work orders, service reports, checklists, invoices, telemetry, and the supporting records around them.
- V2 has no public marketing/demo request screens for launch. Access is invite-only and authenticated.
- Do not create a separate French app branch. Keep one codebase and add French through localization files/keys when needed.
- Vórtice Owner/Admin is the top Vórtice control role and can edit everything, including checklist templates and admin setup.
- Mechanic/tech users perform field work but do not get checklist-template or broad admin-edit powers.
- Billing/office permission should remain narrow: build invoices, send invoices to customers inside the app, and export invoices.
- Dev login contains two client admin personas on purpose so V2 can test cross-client separation and the full app function set without confusing them for two product roles.

## Product Definition

Vortice V2 is an asset-centered maintenance operations app for Vortice staff and their clients.

It coordinates:

- client fleet records
- service request intake
- internal Vortice work orders
- preventive maintenance planning
- maintenance and operations checklists
- saved asset history
- service reports
- invoices
- documents/media
- telemetry and alerts
- client team access

The app should feel like a field-service tool first. It must support people doing real work around machines, often with poor connectivity, dirty context, and incomplete information.

## What V2 Is Not

- Not a public self-serve marketplace.
- Not a public lead/demo capture site.
- Not generic SaaS tier scaffolding.
- Not a customer-facing clone of Vortice internal work orders.
- Not a telemetry dashboard bolted beside maintenance records.
- Not a document vault detached from assets and work.
- Not a system where a checklist silently changes PM state unless the workflow explicitly says so.
- Not a system where offline forms appear to work but lose records, photos, or signatures.
- Not separate language forks or branches. Localization belongs in shared app architecture.

## Core Product Principles

1. Asset-first: the asset is the anchor for service history, checklists, telemetry, reports, documents, invoices, and requests.
2. Workflow-owned mutations: screens can route and summarize, but named workflows own writes.
3. Client portal baseline: every client can see their fleet, records, invoices, documents, and submit service requests.
4. Capability switchboard: optional client workflows are enabled per client through explicit capabilities.
5. Internal/client separation: Vortice work orders are internal. Client-facing history is records, status, reports, requests, invoices, and enabled client workflows.
6. Immutable history: completed checklists and finalized service records preserve what happened at the time.
7. Offline honesty: every workflow is either offline-capable with visible sync state or clearly online-only.
8. No-data-loss: if sync, upload, or export fails, the parent record and local evidence remain recoverable.
9. Hardware humility: telemetry values and alert logic should follow real gateway evidence, not assumptions before field data.
10. Capability is not security: app gates, route guards, backend RLS, and data scope must agree.

## User And Organization Model

### Vortice Organization

The Vortice organization contains internal staff users.

Current app staff roles:

- `owner`: full Vórtice admin role. Current dev login label: `Vórtice Owner/Admin`. Can handle everything, including clients, assets, staff, capabilities, orgs, work orders, reports, invoices, telemetry pairing, checklist templates, and admin setup.
- `employee`: Vortice staff user. Current dev login label: `Vórtice Tech/Mechanic`. Performs field work, checklists, service reports, parts/labor notes, and assigned service records. Does not edit checklist templates or broad admin setup by default.

Use the dev-login persona wording as the planning vocabulary:

- `Vórtice Owner/Admin`: current `owner` role. Owns admin/office-side control: clients, assets, assignments, review, billing prep, overrides, and final close.
- `Vórtice Tech/Mechanic`: current internal field-work persona. Handles assigned WO execution: start, hold, resume, evidence, labor/parts, service reports, and completion.
- `Client 1 Admin` / `Client 2 Admin`: customer admin test personas. They can use client-safe request, fleet, team, and enabled workflow surfaces, but do not drive internal WO status.
- `Client Mechanic`: customer-side mechanic persona for enabled client PM/checklist/parts workflows; not the internal Vortice WO owner.
- `Operator/Captain`: operations checklist persona; can flag issues or create client-side signals, not mutate internal WOs.

Decision: preserve the current app role model unless a later schema decision changes it. `service_manager`, `office`, `billing`, `mechanic`, and `technician` are not current `profiles.role` values. Do not use separate office/coordination labels as primary V2 spec actor names unless a matching dev persona is added.

### Client Identity

A client is the customer account/profile that owns the fleet relationship.

Current source-of-truth model to preserve:

```text
assets.client_id = client owner/profile id
client_orgs.owner_profile_id = client owner/profile id
profiles.org_id = client_orgs.id
```

Client fleet visibility flows from the client owner profile through the client org.

### Client Team Roles

- `client`: limited customer contact/viewer, only if Garrett confirms that role is needed. Sees fleet, history, service requests, reports, invoices, documents, and enabled capabilities according to permissions.
- `client_admin`: default primary client role. Manages client team users within the client org, sees fleet and enabled workflows, can submit service requests.
- `client_mechanic`: performs client-side maintenance/checklist workflows. Does not see Vortice internal work orders.
- `operator` / `client_operator`: performs operations/pre-op/daily checklists and sees operations history only.

Current product direction:

- Primary client users are client admins by default.
- Client users can add employees/team members.
- Client users cannot add assets.
- Client users cannot directly edit asset facts.
- Clients can request asset corrections.
- Client mechanics do not see internal Vortice work orders.
- Operators do not see maintenance tabs or service reports.

## Role Matrix

This matrix uses current app role values from `Profile.UserRole` and the dev login switchboard. Extra job labels such as service manager, office, billing, mechanic, and technician are permission lanes or UI labels until the schema explicitly adds them.

| Area | owner | employee | client | client_admin | client_mechanic | operator/client_operator |
| --- | --- | --- | --- | --- | --- | --- |
| Dev login persona | Vórtice Owner/Admin | Vórtice Tech/Mechanic | none/current viewer TBD | Client 1 Admin / Client 2 Admin | Client Mechanic | Operator/Captain |
| Login/invite access | Yes | Yes | Yes/TBD | Yes | Yes | Yes |
| Create client profile | Yes | No/TBD | No | No | No | No |
| Create client org/invite code | Yes | No/TBD | No | Team invites TBD | No | No |
| Manage capability switchboard | Yes | No | No | View-only/TBD | No | No |
| Create/edit checklist templates | Yes | No | No | No | No | No |
| Create asset | Yes | No/TBD | No | No | No | No |
| Edit asset facts | Yes | Field-note/TBD | Request only | Request only | Request only | No/TBD |
| Delete asset | Yes only | No | No | No | No | No |
| View assigned/client fleet | All | Assigned/all TBD | Own fleet | Org fleet | Org fleet | Operations assets/fleet TBD |
| Submit service request | Vórtice Owner/Admin can create internal WO instead | Vórtice Owner/Admin can create internal WO instead | Yes | Yes | No for MVP | No for MVP |
| Triage service request | Yes | Permission lane/TBD | No | No | No | No |
| See internal work orders | Yes | Assigned/all TBD | No | No | No | No |
| Create/update work orders | Yes | Assigned work updates only/TBD | No | No | No | No |
| Run internal WO checklist | Yes | Yes | No | No | No | No |
| Run client maintenance checklist | Vórtice Owner/Admin can run any | Vórtice Tech/Mechanic can run assigned | TBD | Yes if enabled | Yes if enabled | No |
| Run operations checklist | Yes | Yes/TBD | View/TBD | Yes if enabled | Yes if enabled/TBD | Yes if enabled |
| View maintenance history | Yes | Yes | Yes | Yes | Yes | No |
| View operations history | Yes | Yes | Yes | Yes | Yes | Yes |
| Author service reports | Yes | Yes | No | No | No | No |
| View service reports | Yes | Yes | Own fleet | Org fleet | Org fleet | No |
| Build/send/export invoices | Yes | Billing permission only | No | No | No | No |
| View invoices | Yes | Billing or staff-context TBD | Own | Org | No/TBD | No |
| Pair telemetry device | Yes | No/TBD | No | No | No | No |
| View telemetry | Yes | Yes/TBD | If enabled | If enabled | If enabled | If enabled/TBD |
| Acknowledge telemetry alert | Yes | Yes/TBD | Yes/TBD | Yes/TBD | Yes/TBD | View/TBD |

## Capability Switchboard

Capability switches are per client, controlled by Vórtice Owner/Admin. They are the app's workflow entitlement model: Vortice turns optional workflows on or off for each customer according to the services that customer is paying for or has been granted. They are not user roles, and they are not the old subscription-tier UI.

Current app source of truth to preserve:

- Schema table: `public.client_capabilities`
- Model: `ClientCapability` / `ClientCapabilitySwitchboard`
- Owner UI label: `Service Switchboard`
- Gate widgets/providers: `ClientCapabilityGate`, `clientCapabilitiesProvider`, `clientCapabilityGateProvider`

Initial capability keys:

- `operational_checklists`
- `pm_checklists`
- `pm_parts_lists`
- `maintenance_planning`
- `telemetry`

Always-on client portal access:

- assets/fleet list
- asset facts visible to permitted client users
- service request submission and history
- service reports
- invoices
- documents/generated files
- saved checklist/service history where role permits

Switch behavior:

- Missing capability rows default disabled.
- Switches control paid/granted optional workflow entry, not baseline portal access and not history deletion.
- Turning a switch off hides normal navigation/actions and blocks direct route access.
- Historical records remain visible read-only where role/data policy allows.
- Disabling a capability does not unpair telemetry devices, delete checklists, remove users, or rewrite records.
- The switchboard also controls whether client-side workflow users should be invited/created for those workflows: `pm_checklists` enables client mechanic workflow invites; `operational_checklists` enables operator workflow invites.

## Product Language Rules

Internal words can exist in data, but user-facing labels should match the user's mental model.

Recommended language:

- Internal `service_request.status = new`: client sees `Sent` or `Received`.
- Internal `service_request.status = resolved`: client sees `Being handled`, not `Resolved`, unless the mechanical issue is actually complete.
- Internal review state `pending_review`: staff sees `Ready for invoice` or `Ready for review`; this is not a main WO status.
- Internal `work order`: client generally sees `Service job`, `Service record`, or nothing; clients should not browse internal WOs.
- Internal `saved_checklists`: users see `Checklist history` or `Inspection record`.
- Internal telemetry `acknowledged`: client sees `Seen` or `Acknowledged`.

## Product Risks To Resolve

- Current app has client work-order routes that contradict client-facing product direction.
- Current role model has both `operator` and `client_operator`; decide whether this is real distinction or legacy.
- Current tier dashboards can fight the capability switchboard.
- Client org/team management must not drift into asset creation or asset reassignment.
- Staff visibility scope is not fully settled: all-client staff access versus assigned-only access.
- Capability switchboard UX location is not final.
