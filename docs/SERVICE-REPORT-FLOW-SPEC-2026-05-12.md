# Service Report Flow Spec

Date: 2026-05-12
Status: Working spec for implementation

## Purpose

Service reports are Vórtice-authored vessel service records attached to work orders.
They are a client-facing historical record of completed/diagnosed service, but they are not the same thing as the internal work order workflow.

## Terminology

- **Staff / tech**: `owner`, `employee`
- **Client viewers**: `client`, `client_admin`, `client_mechanic`
- **Non-viewers**: `operator`, `client_operator`
- **Work order**: internal service job record
- **Service report**: client-facing service record authored by Vórtice staff/tech and linked to one work order

## Role rules

### Create / edit
Allowed by policy:
- `owner`
- `employee`

Not allowed:
- `client`
- `client_admin`
- `client_mechanic`
- `operator`
- `client_operator`

Implementation note:
- First pass supports creating/additional reports and retrying partially submitted drafts.
- Full edit/update UI is not implemented yet; when added, it must obey this policy and offline sync rules.

### View
Allowed:
- `owner`
- `employee`
- `client`
- `client_admin`
- `client_mechanic`

Not allowed:
- `operator`
- `client_operator`

## Work order relationship

- A work order can have **many** service reports.
- A service report belongs to **exactly one** work order.
- Service reports are append-only operationally: staff create a new report when they need an additional report, follow-up note, or post-invoice correction record.
- The UI should stop pretending there is only one report per work order.

## Work order status rules

Staff may create a new service report for a work order in any status, including:
- `draft`
- `assigned`
- `in_progress`
- `on_hold`
- `pending_review`
- `closed`
- `invoiced`

Reason:
- invoicing should not block historical/service-record capture
- follow-up reporting after invoice is a real shop workflow

## Entry points

### Work order detail
Show a **Service Reports** card that:
- opens the list of reports for that work order
- shows latest-report summary when available
- shows an **Add report** action for staff
- works for invoiced and closed work orders too

### Asset detail
Show a **Service Reports** card that:
- opens asset-related report history for allowed viewers
- does not appear for operator/client-operator viewers

### Client dashboard
Clients with view access may open service report detail from dashboard/history lists.
Operators must not see or open service reports.

## Authoring form

Fields:
- complaint
- cause
- correction
- collateral
- comments
- technician signature
- photos

Required page behavior:
- The authoring page must expose the 5C fields, signature action, and submit action as part of one usable workflow.
- **Signature** and **Submit Report** must remain reachable on phone screens even when the 5C/attachments content is longer than the viewport.
- Do not bury signature or submit only at the bottom of a long scrolling form; use a persistent action area, app-bar action, or equivalent reachable control.
- The signature action must open a signature capture surface, save the captured signature into the draft/report payload, and visibly indicate when a signature has been captured.
- The submit action must validate required fields, preserve local draft/attachment data, and either create/sync the report or leave it in an explicit retryable pending/failed state.
- The page must not trap scroll gestures in photos/signature/attachment controls; users must always be able to scroll back to the 5C fields.

Rules:
- `complaint`, `cause`, and `correction` are required
- signature is supported and should work offline-first
- photos are supported and should work offline-first

## Offline-first requirements

Service reports must behave like a durable field workflow, not a fragile online-only form.

### Must work offline
- create a new report draft
- select/link the target work order from already-cached work orders
- edit local draft fields before sync
- capture technician signature
- capture/store photos locally
- re-open and continue an unfinished draft
- submit into a local pending-sync state when network/storage upload is unavailable

### Required local states
- `draft_local`
- `pending_create`
- `pending_upload`
- `syncing`
- `synced`
- `failed`

Implementation may map these onto existing sync vocabulary, but the user-facing behavior must distinguish:
- local-only unsent draft
- report record created locally but attachments still pending
- sync failed and retry needed

### Reliability requirements
- no duplicate reports caused by retry loops
- no silent field loss after partial upload failure
- no silent photo/signature loss after app restart
- a partially synced report must remain recoverable and retryable

## Detail/list behavior

### List level
Support:
- all reports (staff list)
- reports for a single work order
- reports for a single asset

Sort:
- newest first

### Detail level
Detail screen should fetch by report id directly, not by loading a broad list and filtering client-side.

## Security / RLS intent

### Staff
- full read/write for `owner`, `employee`

### Client viewers
- read-only, only for reports tied to assets they are allowed to see

### Operators
- no service report read access
- no service report photo read access

## Immediate implementation priorities

1. Fix broken navigation/buttons into service reports
2. Remove operator/client-operator visibility
3. Change from one-report-per-work-order to many-reports-per-work-order
4. Add work-order scoped report list behavior
5. Make detail fetch by id
6. Preserve and extend offline draft behavior toward queued sync behavior

## Known gaps after first pass

If the first implementation pass still relies on local draft persistence more than full queued sync, that is acceptable only as an interim state. The end state remains offline-first durable submission with explicit sync state.

Full edit/update UI for already-synced reports is also not part of the first pass. Staff edit/update remains allowed by policy, but needs a deliberate offline-safe implementation rather than a quick online-only patch.