# Product Backlog

This is the only live project priority list. Detailed specifications may live
elsewhere, but every active task must be represented here with a stable ID.

## Now

### NOW-006 — Continue the remaining feature areas

Outcome: choose and deliver the next useful end-to-end feature from the 20
remaining areas in the original 22-item assessment. Garrett requested a new
project task for this continuation after the initial two features and UX work.
Inventory, existing foundations and proposed next discussion:
`docs/specs/NOW-006-feature-continuation.md`.

Resolve recorded deployment/device follow-ups, then agree one focused slice.
Do not treat the whole inventory as a single implementation task.

### NOW-005 — Make the whole app easier to navigate and use

Outcome: existing and new workflows feel like one app for less technical users.
Garrett authorized a broad UX pass, including removal of unnecessary duplication.
Specification: `docs/specs/NOW-005-ux-cohesion.md`.

Implementation is verified for internal build `1.2.2+7`: clean analysis and
328 passing tests (204 existing skipped walkthrough checks). Awaiting Garrett's
device review; findings and evidence are recorded in the specification.
Build 7 is in phone Downloads; its checksum and media indexing are verified.

Follow-up: restore Sign out at the top right of every profile's home dashboard
while retaining it in More. Both entry points share the same confirmation.

Completed follow-up: standardized every dashboard around a shared Home header,
greeting, fleet status, action cards, and section headings. Keep role-specific
work and capability gates while removing redundant shortcut layouts.

- Consistent role-aware navigation exposes the main work and a searchable tools
  directory without losing existing functionality or bypassing capability rules.
- Fix misleading routes, duplicate dashboards and inert controls; use plain
  language, actionable errors and recoverable empty/search states.
- Asset, fault, checklist, work-order, report, invoice and request journeys keep
  clear context and protect entered work from accidental navigation.
- Verify role routing and changed interactions, render phone/large-text states,
  run prescribed checks, and deliver an internal APK for review.

### NOW-003 — Fault-to-repair tracking and asset availability

Outcome: report an asset fault, assign and track its repair, verify resolution,
and explicitly record availability and downtime in an internal Android build.

Selected by Garrett's September 5 request to autonomously build two features
and deliver an APK to his phone. Specification:
`docs/specs/NOW-003-faults-and-availability.md`.

Acceptance criteria:

- Fleet-scoped fault reporting, assignment, progress, review and event history
  work for company owners/admins, mechanics, operators and provider staff.
- Authorized managers record availability changes with reasons and history;
  downtime survives transitions between unavailable states.
- Cross-company access, invalid transitions, stale edits and duplicate retries
  are rejected or handled safely by the backend, not only the UI.
- Flutter verification, database authorization tests and rendered UI checks
  pass; the isolated internal APK is copied to the phone's Downloads folder.

### NOW-001 — Choose the product identity

Outcome: replace the working Vortice Next name with the chosen product name.

Acceptance criteria:

- Product name and customer-facing language are approved.
- Android and iOS application IDs are selected intentionally.
- Repository, app metadata, icons, documentation, and backend naming impacts
  are inventoried before implementation.
- Production signing remains out of scope unless separately approved.

## Next

### NEXT-001 — Audit invoice authorization before real client data

Confirm invoice RLS, client scoping, export authorization, and role-based UI
behavior together before non-mock invoice data is introduced.

## Later

### LATER-001 — Establish production mobile identity and signing

Replace placeholder application IDs and debug signing, then establish a
repeatable signed release process. Until this is complete, builds are internal
or test artifacts only.

### LATER-002 — Define the app/telemetry runtime boundary

Document ownership, contracts, environments, and deployment flow before adding
collector or Raspberry Pi runtime work to this repository.

## Intake rules

- Add new ideas to `Later` unless Garrett explicitly changes priority.
- Moving work into `Now` requires an outcome and acceptance criteria.
- A pull request names one primary backlog ID; incidental fixes are called out.
- Remove completed items in the same pull request that delivers them and record
  durable outcomes in a decision or current specification when needed.
- Do not create competing priority lists in session notes, issues, or plans.
