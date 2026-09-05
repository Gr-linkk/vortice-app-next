# Product Backlog

This is the only live project priority list. Detailed specifications may live
elsewhere, but every active task must be represented here with a stable ID.

## Now

### NOW-001 — Choose the product identity

Outcome: replace the working Vortice Next name with the chosen product name.

Acceptance criteria:

- Product name and customer-facing language are approved.
- Android and iOS application IDs are selected intentionally.
- Repository, app metadata, icons, documentation, and backend naming impacts
  are inventoried before implementation.
- Production signing remains out of scope unless separately approved.

### NOW-002 — Choose the first independent product slice

Outcome: select one user journey to improve first and write observable
acceptance criteria for it.

Candidate input includes the historical product walkthrough in
`docs/PRODUCT-WALKTHROUGH-BACKLOG-2026-06-18.md`; its entries are not active
requirements until promoted here.

## Next

### NEXT-001 — Audit invoice authorization before real client data

Confirm invoice RLS, client scoping, export authorization, and role-based UI
behavior together before non-mock invoice data is introduced.

### NEXT-002 — Turn the selected product slice into an executable specification

Link the approved journey, roles, happy path, failure states, data changes, and
device-level acceptance checks from this item.

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
