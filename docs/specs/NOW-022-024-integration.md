# NOW-022/023/024: Combined feature integration

Garrett requested merging the two completed feature worktrees into the parts
workstream, resolving conflicts and testing the combined application with
parallel reviewers and end-to-end tests. The independent Next repository and
backend remain the only targets.

## Integrated scope

- NOW-022: PM kits, job requirements, stock, reservations, purchasing and returns.
- NOW-023: configurable hours/calendar recurrence and explicit included services.
- NOW-024: equipment cost, downtime and possible repeat-fault reporting/export.

The merges preserve both feature histories: recurrence `6a79548` through merge
`63dc6a2`, and reporting `1af8ce1` through merge `6597476`, on
`codex/parts-readiness`. Both shared document sections and Planning changes are
retained. Build 26 contains only the parts feature; the combined artifact is
Build 27, version `1.14.0+27`.

## Review and correction

Independent recurrence/parts review found that reopening completed work checked
only the primary plan and could overlap an open included service. Reopen now
checks the job's frozen primary/included coverage in every direction, serialized
with creation under the asset lock. Regression cases cover larger/smaller jobs,
two larger jobs sharing an included plan, later plan edits, legitimate reopen,
replay and reapproval without advancing recurrence twice.

Independent reporting review traced frozen approval costs, provider invoice
exclusion, live export authorization and company scope. No additional reporting
application defect was confirmed. Its SQL test was made portable beyond psql and
its provider assertion scoped to fixture IDs so existing hosted fleets are valid.

Only the selected larger service's full PM kit is snapshotted; included smaller
kits are not implicitly summed. Included checklist work is still required.

## Verification

- Clean analysis and all 611 Flutter tests pass, with zero skips.
- All 24 local PostgreSQL contracts pass across the combined migration chain.
- The extra `parts_recurrence_reporting.sql` drives real APIs for included
  services, frozen kits, issue/return, approval/replay/reapproval and report costs.
  It proves USD 40 initial net parts then USD 20 on reapproval, one report record,
  recurrence targets 7750/8000 advancing once and company/role denials.
- Connected native test passes all 10 stages, including the actual recurrence
  editor, kit/stock/purchasing/use/return forms, Spanish dark 200% text, approval,
  7000-to-7250 hour and calendar advancement, report USD 11 cost, drill-down and
  other-company exclusion. Evidence: `outputs/parts022-A3d2qHhR/`.
- Exact connected fixtures removed with unrelated counts preserved; receipt:
  `outputs/parts022-A3d2qHhR/cleanup-20260908T014524Z-be8f73de.json`.
- Native recurrence and reporting screenshots were visually inspected.

The recurrence and reporting migrations are active on isolated Next. All 24 hosted
contracts pass, including the combined workflow. The whole-app route audit and
Build 27 delivery are pending.
Physical Android installation and interaction remain separate acceptance.
