# NEXT-008: Checklist and date during work-order creation

Requested September 13, 2026, following the customer creation screenshot.
Branch: codex/work-order-creation-details, continuing Build 38.

## Outcome

Customer work creation opens a full native page. Choose equipment, attach a
compatible published PM checklist, review/change the scheduled date, and enter
the title and instructions before one Create work order action. Start with the
selected calendar day; allow clearing it to leave the job unscheduled. Returning
to the calendar follows the saved date. Equipment changes clear the checklist
selection so an incompatible procedure cannot be carried across equipment.

## Rules and scope

- Existing provider/customer authorization and shared-equipment rules apply.
- Offer shared starters and the provider company's compatible published library;
  never expose another company's private checklists through a service connection.
- Creation, date, checklist version, procedure snapshot and parts-kit capture
  commit in one server transaction. Rejection leaves no partial work order.
- Preserve old RPC overloads for installed versions. New retries match the exact
  submitted checklist/date payload; an uncertain response freezes the form for
  retry. New creation requires a connection and does not claim offline delivery.
- Keep Field Notes styling and English/Spanish labels. No new checklist authoring,
  arbitrary job fields, timed customer-resource scheduling or changed completion
  rules are part of this slice. Own-equipment creation retains its existing
  checklist field and checked scheduling workflow.

## Acceptance

Exercise calendar -> creation -> equipment/checklist -> date picker -> change ->
save, and checklist removal, equipment change, clearing the date, empty library,
rejected save and uncertain retry. Inspect rendered phone and 200% text layouts.
SQL contracts cover compatibility, private/retired templates, role isolation,
atomic snapshot/kit capture and exact-payload replay. Physical Android acceptance
and build delivery are reported separately.

## Verification results

- WSL project guardrails and full analysis passed. The full Flutter suite passed
  **779 tests**. The six new creation widget tests passed again after the final
  date-picker accessibility fix and shorter date-field label.
- All **48 local PostgreSQL contracts** passed. The expanded customer creation
  contract also passed against hosted Next inside a rolled-back transaction.
- The additive migration `20260914090000_customer_creation_checklist.sql` is
  activated on Next only. Both older creation overloads remain available.
- Connected journey `outputs/next008-connected-2`: normal Month entry -> Add work
  here -> customer equipment -> published checklist -> date changed from September
  20 to September 23 -> create -> saved day's agenda -> open work with pinned
  checklist/version and steps. One completed step, no recorded issues.
- The first connected attempt stopped before save because the test targeted an
  off-screen duplicate day cell. The test now selects the hit-testable day.
  Both attempts have cleanup receipts: the first created nothing; the second
  removed its exact synthetic work order, preserving 216 unrelated work orders,
  all 35 assets and all 32 invoices. Existing library entries were not edited.
- Rendered screenshots in `outputs/next008-ui` and the connected run were visually
  inspected. Standard phone light/dark layouts and English/Spanish at 320 px and
  200% text were checked. Enlarged calendar cells clipped two-digit days, so that
  case now uses native date entry while retaining the user's text size.
- Direct code review covered RPC compatibility, company/checklist boundaries,
  rollback and retry identity, calendar return and UI changes. No independent
  agent review was performed. Tests emit the existing deliberate multi-database
  harness warning at sign-out; it does not indicate test failure.
- Added `scripts/build-android.sh` as a guarded WSL/Linux build companion so the
  requested WSL-only CLI workflow checks repository, Supabase and Firebase
  identity and actual backend build configuration before producing an APK.

Build target: internal Android `1.18.1+39`. Physical installation and acceptance
are separate from the automated native journey and artifact delivery.
