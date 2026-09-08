# NOW-024: Equipment cost, downtime and repeat-fault reporting

Garrett approved this feature on September 7, 2026. QR labels are not selected.
Base: 52fe552 in the independent Next repository, isolated from NOW-022 parts
readiness and the maintenance-recurrence workstream.

## Outcome

Company managers and the provider owner open More > Equipment report, select
a month, quarter or custom period, compare machines by recorded cost, downtime
or possible repeat count, inspect the underlying records and export a CSV with summaries,
source rows and matching-fault groups. Preserve the approved Field Notes design.

## Calculation and access rules

- One read-only, server-authorized RPC returns a transaction-consistent report.
  Every asset must pass current maintenance management access; employees,
  mechanics and operators cannot query management costs. Invoice access also
  follows current customer invoice visibility. No anonymous access.
- USD is the existing recording currency. Internal labour and parts come from
  the latest approved completion snapshot per internal work order, dated by that
  approval. Multiple approvals of one job do not duplicate its cost. Unapproved
  work and mutable draft parts are excluded.
- Outside service uses sent/paid provider invoice totals including invoice tax,
  dated by sent_at. Draft and void invoices are excluded, even for the provider
  owner. Provider job labour/parts are not counted again. This is recorded
  maintenance expenditure, not a cash-flow report, accounting ledger or total
  cost of ownership. There is no new external-vendor bill entry workflow.
- Completed provider jobs without an issued invoice, unpriced/zero-price parts,
  positive labour with zero/missing rate, missing approval receipts, empty cost
  records and zero/incomplete invoice amounts are
  visible cost gaps. Zero does not establish that maintenance was free.
- Unavailability is time in out_of_service or under_maintenance, reconstructed
  from the explicit availability event timeline and clipped to the selected
  interval and query time. Restricted time is not downtime. Time before the
  first recorded state, or after conflicting same-time events until the next
  unambiguous state, is unknown, not assumed available. Fleet hours are sums
  of equipment-hours, not elapsed wall-clock hours. Do not infer downtime from
  work-order dates or fault creation.
- Matching fault descriptions ignore case and repeated whitespace, within each
  asset and the selected period. Dismissed faults are excluded. Show the matching
  records as possible repeats, not diagnosed root causes or inferred repairs.
  Repeat count is the number of reports beyond the first in each matching group;
  the equipment list flags this count before expansion and can sort by it.
- Dates use the viewer's local calendar, sent as explicit UTC instants with an
  exclusive end. Current periods stop at query time. Maximum interval: 366 days.
- Export re-queries with live authorization rather than exporting cached data.
  It includes date bounds, query time, currency, limitations, all summaries and
  source rows. CSV cells escape quotes and spreadsheet formula prefixes.
  Server errors/timeouts produce a retry state, never a partial-success export.
- No persistent report cache: a connection is required. Source workflows and
  their offline behavior stay unchanged. Re-query after reconnecting.

## Acceptance

1. A two-hour approved job at USD 50/hour with USD 40 in parts plus a USD 116
   sent provider invoice reports 100 labour + 40 parts + 116 outside = USD 256.
2. Draft, void, unapproved, other-company and duplicate approval records cannot
   inflate or leak into the result. Frozen approval evidence survives later edits.
3. Overlapping period boundaries, transitions between unavailable states, open
   intervals and unknown history produce correct hours without double counting.
4. Matching faults on different machines do not form one repeat group.
5. English/Spanish, narrow screens and enlarged text render without overflow;
   period selection, sorting, expansion, drill-down, retries and export work.

## Delivery status

Implemented locally on `codex/equipment-reporting` from 52fe552.
Guarded verification passes: repository/migration guards, clean Flutter analysis
and 595 Flutter tests, with no skips. The 12 focused report tests cover
sorting, period selection, source navigation, export failure, company switching
during export, management access, loading/empty/retry states and native rendering.
The isolated PostgreSQL contract suite passes scoped cost reconciliation,
immutable receipt selection, incomplete costs, invoice exclusion, date boundaries,
open/ambiguous downtime, description matching, seven seeded user profiles and
anonymous access denial.

Native English/light and Spanish/dark renders at 390x844 and 100%/200% text were
generated and visually inspected. Evidence: `outputs/report-renders/` and
`outputs/report-verification.log`. Render fixtures are synthetic; no phone or
hosted-data interaction is implied. Direct review traced the changed API, source
permissions, navigation, calculations and CSV export; this was not an independent
agent review.

No hosted migration, branch integration, APK packaging, phone transfer or
physical-device acceptance occurred in this workstream. Activate only
`supabase/migrations/20260907230000_equipment_reporting.sql` on the guarded Next
backend as part of integration. The report requires that RPC and a connection.
Recheck it against the integrated parts and recurrence branches before packaging.
Keep the shared More route entries and both other backlog items when combining
the small `BACKLOG.md`, `PROJECT.md`, router and navigation additions.
