# NOW-006: Continue the remaining feature areas

Garrett requested a fresh project task for the remaining 20 areas from the
September 5 assessment, after the initial two-feature delivery and the UX pass.
The numbered inventory below preserves the original 22-item numbering. It is
an intake list, not approval to implement all items simultaneously or deploy
hosted changes without the applicable authorization.

## Starting point

- Original item 2, fault-to-repair lifecycle, and item 3, asset readiness and
  downtime, have their initial implementation under NOW-003. Both hosted
  migrations were explicitly approved and deployed to Vortice Next on
  2026-09-06 UTC. Both hosted contract suites and six persona HTTP fleet checks
  passed; see NOW-003's activation record. Device workflow review remains open.
- The accepted implementation scope is in `NOW-003-faults-and-availability.md`
  and `../decisions/0004-faults-and-availability.md`. The original assessment
  described larger feature areas: source integration/photos/duplicate linking
  and planned-versus-unplanned downtime are not all delivered by this slice.
- Related foundations exist for items 1, 4 and 16. The latest shared dashboards
  improve navigation and presentation; they do not complete item 16's broader
  operational metrics. Recheck code before choosing each remaining slice.
- Preserve the shared dashboard/navigation design, Sign out at the top right
  and in More, English/Spanish support, and large-text behavior.

## Recommended next conversation

First resolve the recorded deployment/device follow-ups. Then compare the gaps
in company-owned internal maintenance (1), mechanic execution (4), and reliable
maintenance completion (5). Recommend one small end-to-end slice with observable
acceptance criteria and role/server checks. Let Garrett choose the next feature
before implementation; this new task is the place to continue that discussion.

## Remaining 20 areas

The descriptions below are the original assessment scope, not verified current
absence. Some components already exist and should be extended rather than rebuilt.

1. **Company-owned maintenance workspace — extend existing access.** Company owners/admins can manage their assets and plans, create and assign internal work orders, and allow their mechanics to report and close work. Separate internal costs from customer billing. Keep company data scoped on the server as well as in the UI. Acceptance example: Company A's manager assigns a repair to A's mechanic, who completes it; Company B cannot read or change any related record or attachment.

4. **Complete mechanic job workflow — extend staff execution to company teams.** A useful My Work list; priority, due date, instructions, start/pause labour entries, parts used, diagnosis, repair notes, evidence, blocked reasons and supervisor review. Support reopening and follow-up work. Do not require an invoice to complete an internal repair. Acceptance example: a mechanic records two separate labour sessions, replaces a seal and submits a report; a reviewer can approve or return it with a reason.

5. **Trustworthy maintenance completion — connect and harden existing PM.** Link work directly to the relevant maintenance plan/component. Advance the next service only after the required completion conditions succeed. Make partial saves visible and retryable without creating duplicates. Client-performed maintenance must update the same due-state rules as provider-performed work. Acceptance example: completing a generator service advances that generator's service, leaves the propulsion engine unchanged, and survives retry after an interrupted connection.

6. **Delivered notifications and escalation — finish existing stubs.** Assignment, urgent fault, approaching/overdue service, blocked work and review-needed notifications with deep links and delivery/retry records. Add user preferences, actionable recipients and escalation for unacknowledged critical items. Acceptance example: an urgent defect reaches the responsible manager while the app is closed, and acknowledgment stops repeated escalation.

7. **Field offline workflow — complete existing foundations.** Download assigned work, asset context and procedures; persist drafts, photos, readings and labour; show pending/failed/synced state and safe retries. Define conflicts, duplicate prevention and account-scoped local data. Acceptance example: an operator or mechanic finishes work without reception, restarts the app, reconnects and obtains exactly one complete submission including evidence.

8. **Flexible maintenance plans — extend hour intervals.** Calendar dates, operating hours, distance/cycles where relevant, and “whichever comes first”; component-specific meters; recurring inspections; last-service baseline; planned shutdown windows; recorded postponements. Acceptance example: “every 250 hours or six months” becomes due at the earlier threshold.

9. **Fleet planning board — new beyond scheduled date.** Week/month calendar plus an unscheduled queue; assignee capacity, estimated duration, priority, due dates, availability windows, conflicts and parts readiness. Acceptance example: a planner sees that two jobs overlap for one mechanic and reschedules one before committing the week.

10. **Reliable meter history — extend hour logging.** Separate meters for each engine/component, capture time/source, corrections with reasons, meter replacement/reset handling and stale-reading warnings. Derive forecasts only when usage data supports them. Acceptance example: an older uploaded reading cannot silently replace a newer accepted meter value.

11. **Customer checklist/procedure builder — new authoring over existing templates.** Create, copy and version procedures; pass/fail/not-applicable responses, numeric limits, required evidence and critical failures; publish to asset types or selected components. Preserve the version used on completed work. Acceptance example: a changed procedure affects future jobs while last month's signed checklist remains unchanged.

12. **Parts stock and purchasing — connect the existing catalog/inventory foundation.** Stock by location; receive, issue, return and count transactions; minimum levels; job reservations; supplier lead times; purchase requests/orders and delivery status. Acceptance example: planning a service reveals one missing filter, reserves the available parts and tracks the filter through receipt and issue.

13. **Asset setup, documents and identification — extend registration.** CSV import with preview and duplicate checks; photo and identification label; QR scanning; manuals, diagrams, certificates and warranties attached to assets/components; initial meter/service data and bulk plan assignment. Acceptance example: an owner imports 50 machines and the mechanic scans a label to open the correct machine and manual.

14. **One asset history — connect existing records.** A chronological view of usage, inspections, issues, work, service reports, parts, costs, moves and documents. Filter and export a service record. Acceptance example: a mechanic investigating a recurring leak can find the prior repair and installed part without searching several screens.

15. **Job discussion and handover — new.** Comments tied to a job/issue, mentions, attachments, handover notes and a clear event trail. Distinguish internal notes from customer-visible updates. Acceptance example: the next shift sees the diagnosis, isolation status and outstanding work without relying on a separate message thread.

16. **Owner's fleet dashboard — extend current counts and lists.** Show unavailable assets, urgent unresolved faults, overdue service, upcoming demand and work waiting on people/parts/approval. Every indicator opens the underlying records. Acceptance example: the owner can identify today's three decisions without opening each asset.

17. **Cost, downtime and reliability reporting — new analytics over completed records.** Labour, parts and outside-service costs by asset/site/period; planned versus actual; downtime duration; repeat faults; scheduled maintenance completion. Later add repair-versus-replace comparisons and cost per operating hour when inputs are reliable. Define denominators and exclude missing data rather than presenting misleading precision.

18. **Budgets, estimates and approvals — extend invoicing into authorization.** Estimate labour/materials, record company approval thresholds, approve changes, attach external quotes and track external work. Keep approval status separate from execution and payment status. Acceptance example: a mechanic requests an expensive component, a manager approves the revised estimate and both versions remain visible.

19. **Asset custody, sites and lifecycle — new over location text.** Responsible team/person, site transfers, location history, loan/assignment, commissioning, retirement and disposal; optional GPS/map view where hardware supports it. Acceptance example: the owner can identify a machine's current site, responsible team and last transfer. GPS coordinates already in telemetry schema do not replace custody records.

20. **Inspection assurance and expiry tracking — extend history.** Inspection schedules, certificate expiry, reviewer sign-off, required evidence, exportable audit trail and correction history. Add permits/qualification checks only where the customer's work requires them. Acceptance example: the planner sees an expiring inspection and can show which procedure and evidence supported the renewal.

21. **Platform operations and company administration — extend org controls.** Guided company setup, workspace switching if needed, membership suspension/transfer, subscription lifecycle, company export and controlled support access with activity records. Existing global owner access is not by itself a separate platform support model. Acceptance example: a support action records who accessed which company and why.

22. **Condition-based maintenance and integrations — later expansion.** Turn validated telemetry alerts into reviewable issues with deduplication, acknowledgment and linked repairs; expose sensor freshness and faults. Add accounting, supplier, telematics or import/export integrations based on real customer demand. Start with transparent thresholds and trends before considering predictive models.

## Session checkpoint

Build `1.2.2+7` includes the two initial features, working internal dev login,
the broad UX pass, and dashboard standardization. Verification: guardrails,
code generation, clean analysis, 328 passing tests and 204 existing skips.
Android package/signature/configuration and the ARM64 Flutter runtime were
verified. Phone delivery and hosted migration status must be checked in the
handoff packet; an APK alone does not activate undeployed backend functions.

Detailed local evidence is in the original checkout's ignored `outputs/`,
especially `NOW-003-build-notes.md` and `NOW-005-dashboard-build-notes.md`.
Do not copy local credentials, dev-login secrets, private attachments, or build
artifacts into a new worktree or commit them. Repository and service isolation
in AGENTS.md remains mandatory.
