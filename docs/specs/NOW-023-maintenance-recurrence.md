# NOW-023: Flexible maintenance recurrence

## Outcome

Extend existing component maintenance plans with configurable hours, calendar
months, completion-based recurrence, fixed milestones and explicit transitions.
Garrett approved implementation after describing a dredge serviced at 6,700 h
and deliberately moved onto 7,000 / 7,250 / 7,500 / 7,750 h milestones. These
numbers are examples only; each asset/component has its own settings.

Accepted semantics: `../decisions/0015-maintenance-recurrence.md`.

## Customer workflow

Open Assets & plans, select the asset, and add or edit a maintenance plan.
Choose Operating hours, Calendar, or Hours or calendar. Select From actual
completion or Fixed milestones / transition. Supply the baseline or first
targets and inspect the four-occurrence preview. Existing adjustments require
a reason. Optional Included services selects other plans on the same component.

Example: the 250 h plan starts at 7,000 h and the 500 h plan starts at 7,500 h.
The 500 h plan explicitly includes the 250 h plan. A 250 h service completed at
7,020 h leaves 7,250 h due. Completing the 500 h service at 7,500 h advances the
250 h target to 7,750 and the 500 h target to 8,000, after validating the included
checklist tasks. The generator's plan remains unchanged.

Moving a calendar booking only moves the appointment. Saving a plan does not
book future work automatically. Date-based completion uses the approval date;
backdating historical completion is not introduced by this slice.

## Implementation and integration

- Branch: `codex/maintenance-recurrence`, based on `52fe552`.
- Isolated worktree: `work/maintenance-recurrence` within the Next clone.
- New migration: `20260907220000_maintenance_recurrence.sql`.
- Existing `save_maintenance_setup`, job creation/approval, plan context,
  planning and fleet attention remain the access-checked entry points.
- Reviewed agent proposals retain their explicit review flow and record the
  proposal reference as the adjustment reason. Agent recurrence authoring is
  not added; the native plan editor owns the new settings.
- No dependencies added. No original-app code, services or credentials used.
- The concurrent NOW-022 parts branch is not included. Integrate both backlog
  entries and both Planning changes when synchronizing the workstreams; preserve
  the parts controls and the recurrence-aware plan description. Both migrations
  are additive and have distinct timestamps. Re-run combined checks after sync.
  The jobs response preserves the parts stream's optional stock requirement ID
  through a schema-compatible JSON lookup. Included service checklists are merged;
  PM kit quantities still come from the selected job's kit. Ensure that larger
  service kit describes its full requirements when checking the combined workflow;
  smaller kits are not implicitly summed and potentially counted twice.

## Verification

The recurrence contract exercises configurable intervals, transition, early/late
completion, month-end/leap-year arithmetic, calendar-only and combined due states,
manager/mechanic/company boundaries, replay and stale revisions, change reasons,
coverage validation, open-job conflicts, included checklist enforcement, atomic
multi-plan advancement, other-component preservation and immutable coverage.

Native tests exercise the real editor's target preview, changed save payload,
uncertain-response retry identity, return navigation and Spanish 320 px / 200%
text layout. Rendered evidence: `outputs/recurrence-renders/`.

Final verification: guarded `scripts/verify.cmd` equivalent through
`scripts/verify.ps1` passed repository guards, code generation, clean analysis
of lib/test/tool, and all 589 Flutter tests with zero skips. All 21 isolated
PostgreSQL suites pass after the final jobs-response compatibility update.
The six focused native/model recurrence checks pass; screenshots were inspected.
Direct review followed setup, preview, approval, coverage, replay, access and
the concurrent parts response contract. No independent reviewer was used.

## Delivery boundary

Implementation and local contracts are separate from hosted activation and
physical phone acceptance. No hosted migration or phone installation is part
of this isolated workstream. The user requested a separate stream to synchronize
with the parts feature before a combined delivery.
