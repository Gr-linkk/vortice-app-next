# Vortice App V2 Spec Packet

Date: 2026-05-24
Status: discovery-based planning draft for Garrett review
Owner: Garrett / Vortice
Prepared by: Jasper

## Garrett Question Inbox

Answer here in rough notes. Jasper should fold answers into the matching spec files and rotate the next questions.

 1. **Rewrite shape:** Should V2 be a rewrite from scratch, a staged rebuild inside the current Flutter app, or a hybrid where workflows are rebuilt one module at a time?

    Garrett answer:re write i have the goal of trying not to loose too much progress but ditch the mess made
 2. **First production target:** Is the first production target still mobile-first field use, or should tablet/desktop office workflows be equal priority from day one?

    Garrett answer:mobile to start
 3. **Staff roles:** What exact roles should V2 preserve from the current app dev login and profile enum?

    Garrett answer: Use the current app dev login/profile enum as the role source of truth. There is no service_manager role. Current role values are owner, employee, client, client_admin, client_mechanic, operator, with client_operator as a legacy alias. The dev login personas are Vórtice Owner/Admin, Vórtice Tech/Mechanic, Client 1 Admin, Client 2 Admin, Client Mechanic, and Operator/Captain. The two client admins are intentional test clients for exercising cross-client app behavior.
 4. **Client admin model:** For client-side users, should `client` and `client_admin` remain separate roles, or should every client owner be a client admin?

    Garrett answer:all should be a client admin
 5. **Localization:** Should V2 keep Spanish localization in the first build, or design the system for localization but ship English first?

    Garrett answer:we need to ship both first
 6. **Pilot client:** What is the first real pilot client/worksite for V2 besides the Paradise Marina dredge telemetry context?

    Garrett answer: First V2 pilot target besides Paradise Marina dredge is a general client/worksite, not another specially scoped dredge telemetry pilot.
 7. **Launch promise:** What is the minimum V2 launch promise: client portal/history, work orders, service reports, checklists, invoices, telemetry, or all of them together?

    Garrett answer: All of them together. V2 launch should cover the full workflow set defined so far, not a narrow portal-only or work-order-only slice.
 8. **Public screens:** Should V2 include public marketing/demo request screens at all, or is it invite-only authenticated app only?

    Garrett answer: No public marketing/demo request screens. V2 is invite-only authenticated app access.
 9. **Client exports:** Do clients need to export/download their own records from day one, or is view-only enough until staff sends PDFs?

    Garrett answer:
10. **Hardest field workflow:** What is the hardest field workflow you want V2 to survive: no service, bad signal, wet phone, long checklist, multiple techs, or client handoff?

    Garrett answer:

## Packet Files

Read in this order:

1. `01-product-roles-and-principles.md`
2. `02-workflow-specs.md`
3. `03-data-offline-sync-and-security.md`
4. `04-information-architecture-and-screens.md`
5. `05-build-plan-salvage-and-acceptance.md`

## Scope

This packet is for the Vortice App V2 product and implementation spec. It is not an app-code change and does not authorize coding. The goal is to make the workflows specific enough that a future coding pass can build V2 without rediscovering product rules in chat history.

## Source Material Inspected

- Current app repo: `/mnt/c/Users/gr_link/src/vortice-app-main`
- Current workflow spec: `/mnt/c/Users/gr_link/src/vortice-app-main/docs/VORTICE-WORKFLOW-SPECS-2026-05-21.md`
- Service report rebuild plan: `/mnt/c/Users/gr_link/src/vortice-app-main/docs/SERVICE-REPORT-REBUILD-PLAN-2026-05-21.md`
- Checklist workflow spec: `/mnt/c/Users/gr_link/src/vortice-app-main/docs/CHECKLIST-WORKFLOW-SPEC-2026-05-07.md`
- Service report flow spec/notes: `/mnt/c/Users/gr_link/src/vortice-app-main/docs/SERVICE-REPORT-FLOW-SPEC-2026-05-12.md`, `/mnt/c/Users/gr_link/src/vortice-app-main/docs/SERVICE-REPORT-FLOW-NOTES-2026-05-12.md`
- Client org access model: `/mnt/c/Users/gr_link/src/vortice-app-main/docs/CLIENT-ORG-ACCESS-MODEL-2026-05-08.md`
- Schema/workflow audit: `/mnt/c/Users/gr_link/src/vortice-app-main/docs/SCHEMA-WORKFLOW-AUDIT-2026-05-08.md`
- Workflow architecture notes: `/mnt/c/Users/gr_link/src/vortice-app-main/docs/WORKFLOW-ARCHITECTURE-NOTES-2026-05-08.md`
- Developer review prep plan: `/mnt/c/Users/gr_link/src/vortice-app-main/docs/DEVELOPER-REVIEW-PREP-PLAN-2026-05-13.md`
- Product decision: `/home/gr_link/.openclaw/workspace/projects/vortice-app/PRODUCT-DECISION-2026-05-07-client-capability-switchboard.md`
- Telemetry ADR: `/home/gr_link/.openclaw/workspace/projects/vortice-app/ADR-2026-05-07-asset-first-telemetry.md`
- Current code shape: routes, feature folders, models, Drift tables, repositories, Supabase migrations.

## V2 Product Thesis

Vortice is a service operations app for mechanical service relationships around vessels, dredges, heavy equipment, and client fleets. It is not generic SaaS tierware. The app should make field work, service records, client visibility, maintenance planning, and telemetry belong to the same asset-centered maintenance story.

The current app has useful domain pieces, but the workflows are close rather than fully developed. V2 should treat the current app as reference material and salvageable domain knowledge, not as the unquestioned product shape.

## Non-Negotiable Direction

- Asset Detail is the main workflow hub.
- Client onboarding is invite-only; no open public registration.
- Client app behavior is controlled by a per-client capability switchboard, not rigid tier routing.
- Baseline client portal access is always on: fleet visibility, history/records, service requests, invoices/documents.
- Internal Vortice work orders are not client work orders.
- Client mechanics use client-side checklists/history; they do not see internal Vortice work orders.
- Every submitted checklist becomes immutable saved asset history.
- Service reports are client-facing records linked to work orders; they are not the internal work order.
- Field work must have explicit offline behavior. Half-offline workflows are not acceptable.
- Telemetry is asset-first. Engine/J1939 data is one stream under an asset.
- Generated files are stored and regeneratable from source records.
- No-data-loss beats cleanup.
- Localization should use one shared codebase with locale files/keys, not a separate French branch or fork. English and Spanish ship first; French can be added as another locale when required.

## Current-Code Facts To Preserve Or Fix

- Current routes include client work-order routes even though product direction says clients should not see internal WOs.
- Current tier dashboards still exist and are legacy risk.
- Current code has overloaded work-order statuses: `draft`, `assigned`, `in_progress`, `on_hold`, `pending_review`, `invoiced`, `closed`.
- V2 launch simplifies main WO status to `draft -> ready -> in_progress -> on_hold -> completed -> closed`; assignment, review, billing, sync, and client visibility are separate fields.
- WO transition permissions use the dev-login persona wording: `Vórtice Owner/Admin` for admin/office-side control and `Vórtice Tech/Mechanic` for assigned field execution. Client personas do not mutate internal WO status.
- Current Drift local tables exist for work orders, checklists, service reports, invoices, parts, sync operations, and local attachments, but offline guarantees are uneven by workflow.
- Service report authoring became unstable on device and should be rebuilt from small steps.
- Saved checklist history and client org visibility are strong concepts worth carrying into V2.
- Telemetry has already moved toward asset-first in docs, app seams, and migrations.

## Spec Maintenance Rule

When Garrett answers a question:

1. Convert the answer into a settled/tentative/conflict/question note.
2. Update the matching workflow or data rule.
3. Remove or rewrite the answered question.
4. Add the next highest-impact question at the top of the relevant file.
5. Do not code from this packet until a build packet is explicitly produced and approved.