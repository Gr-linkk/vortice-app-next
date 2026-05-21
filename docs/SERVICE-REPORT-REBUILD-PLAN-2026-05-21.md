# Service Report Rebuild Plan

Date: 2026-05-21
Status: Planning checkpoint after on-device authoring screen failure

## Why rebuild

The current service report authoring screen is no longer a trustworthy surface. Multiple attempts improved individual symptoms, but on-device testing still shows the service report screen sticking, freezing, or disappearing when the authoring UI enters view. At this point, continuing to patch the same screen risks hiding the real workflow problems under more widget-level workarounds.

The next pass should treat the existing implementation as reference material, not the foundation for the new screen.

## Preserve

- Service report domain model and database fields unless the rebuild spec finds a concrete mismatch.
- Existing work-order relationship direction: one work order can have many service reports.
- Role policy:
  - `owner` and `employee` can author service reports.
  - `client`, `client_admin`, and `client_mechanic` can view allowed reports.
  - `operator` and `client_operator` do not see service reports.
- Existing migrations that remove one-report-per-work-order assumptions and block operator visibility.
- Existing list/detail route intent where it is already boring and testable.
- Offline draft/retry concepts from the current spec, but only after the basic form is stable.

## Rebuild principles

- Build the authoring workflow from small screens and owned state, not one oversized page.
- Make the phone layout the primary target, then scale up.
- Keep workflow rules outside widgets where possible.
- Do not bury required actions at the bottom of a long form.
- Prefer explicit states over hidden empty widgets: loading, no work order, draft load failed, save failed, submit failed.
- Ship the boring workflow first: create draft, edit fields, save locally, submit.

## Proposed workflow

1. Entry point
   - Staff work-order action opens `NewServiceReportFlow` directly with a required `workOrderId`.
   - Existing report list remains a history/list surface, not the first stop for authoring.

2. Draft initialization
   - Load the target work order directly.
   - Create or resume one local draft for that work order.
   - If draft initialization fails, show a blocking error with retry.

3. Main 5C form
   - First stable screen contains only:
     - complaint
     - cause
     - correction
     - collateral
     - comments
   - Save draft automatically on field changes with debounce or explicit save.
   - Bottom actions stay fixed and simple: `Save draft`, `Next`.

4. Signature
   - Separate step/screen or modal after the 5C form is stable.
   - Save signature into the local draft before submit.
   - Show a clear captured/not-captured state.

5. Photos
   - Separate step/screen after signature.
   - Photo upload/offline retry should not block proving the base 5C flow.

6. Review and submit
   - Dedicated review screen shows required fields, signature state, and attachment count.
   - Submit validates required fields and produces one explicit state:
     - synced
     - pending sync
     - failed with retry

## First implementation slice

Build a replacement authoring flow behind a new route and leave the existing screen available only as a reference until the replacement passes phone testing.

Minimum slice:
- new route: `/service-reports/new-v2?workOrderId=...`
- work-order detail debug/staff action can point at v2 during testing
- 5C form only
- local draft save
- visible error/empty states
- no photos
- no signature pad
- no PDF/export work

Accepted direction:
- This slice is intentionally only the 5C form plus local draft persistence.
- Signature, photos, PDF/export, and full offline queue UX are explicitly out of scope until the 5C flow is proven stable on Garrett's phone.
- Work Order Detail should route staff directly to v2 authoring. The report list remains history, not the authoring entry point.

Definition of done for slice one:
- opens reliably from a real in-progress work order on Garrett's phone
- no red screen
- no blank/stuck screen when the form enters view
- required 5C fields can be filled without the keyboard trapping the screen
- leaving and reopening preserves draft text
- targeted tests cover route entry and draft persistence

## Cutover plan

1. Build v2 authoring route in parallel.
2. Verify v2 on phone with a real work order.
3. Move the normal `Add Service Report` action to v2.
4. Keep old screen behind no primary navigation for one checkpoint commit.
5. Delete old authoring screen once v2 supports signature, photos, and submit.

## Open questions for the full spec

- Should a work order allow more than one active local draft at once, or only one active draft plus many submitted reports?
- Are signature and photos required for every service report, or only supported?
- Should staff be able to submit a pending-sync report while offline, or only save a draft offline and submit online?
- What exact report statuses should clients see: only synced/final, or pending/internal drafts hidden entirely?
