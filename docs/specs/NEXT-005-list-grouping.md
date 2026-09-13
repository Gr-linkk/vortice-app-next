# NEXT-005 — Group related choices in lists

Requested September 12, 2026 after Garrett showed the flat Z–A Asset Type picker.
This is a small pass within the existing Field Notes design, not a navigation
or workflow redesign.

## Implemented scope

- Add/Edit equipment type: persistent search above category headings with counts;
  choices sort A–Z within their category. Blank/custom categories appear under
  Other at the end. Search still matches names and English/Spanish categories,
  shows only matching groups and returns the same stable catalog ID. Repeated
  category subtitles are removed so each row is easier to scan.
- Checklist library: keep procedures grouped by asset or equipment type, with
  general checklists last. Group identity uses the asset/type ID so duplicate
  equipment names cannot merge separate scopes. Within each group, pre-operation
  checks stay together and maintenance names use numeric-aware ordering. Search
  also matches the equipment/group name. Existing purpose/publication filters,
  permissions and actions are preserved.
- Operator choices: group available equipment by its recognized equipment type
  and sort numbered names naturally. Matching equipment-specific checklists are
  listed before general checks, with headings. The existing single-match shortcut,
  pinned assignments and draft handling remain in place.

Groups stay expanded; headings do not add an extra click before selection. Long
headings wrap, counts stay alongside them, and accessibility exposes section
headings. English and Spanish text use existing equipment translations.

The pass concentrates on mixed selection lists. Work schedules retain date/status
ordering; technician selection remains a single-kind list. The existing service
checklist selector already separates service intervals and categories. No server
data, access policy or schema change is required.

## Verification and delivery

Focused checks cover category order, cross-category search, stable-ID selection,
cancel/empty states, duplicate asset names, numeric service names, and existing
operator draft/assignment behavior. The real Add/Edit forms are exercised in
Spanish at 320 px / 200% text. Connected rendered checks use the current demo
fleet for catalog, library and operator choices; no asset, checklist or assignment
is saved. Build 36 (`1.16.7+36`) contains this pass; installation and physical
phone acceptance are recorded separately from automated checks and file delivery.

Guarded project verification passed clean analysis and **731 Flutter tests**:
`outputs/list-grouping-verify.log`. The focused selection/draft/library suite
passed 27 checks. Connected acceptance passed all four stages in
`outputs/list-grouping-mF6EEgow/`; its catalog, search, library and operator
screenshots were visually reviewed, including 320 px / 200% text. An initial
capture attempted to scroll before the account transition settled; explicitly
waiting for the current account's templates and screen resolved the harness
timing issue. No production access rule or selection shortcut was changed.
