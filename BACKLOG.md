# Product Backlog

This is the only live project priority list. Detailed specifications may live
elsewhere, but every active task must be represented here with a stable ID.

## Now

### NOW-004 — Restore internal dev persona login

Outcome: the login logo's dev panel fills both email and the corresponding
Next mock-account password in the internal Android APK. Load passwords from
ignored local build configuration only, gate them to debug builds targeting
Next, verify all six accounts through the app's runtime configuration, and
deliver build 1.1.2+4 to the phone. This includes correcting the inherited
placeholder API-key constant and checking config wiring before every APK build.

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
