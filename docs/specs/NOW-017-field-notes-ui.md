# NOW-017 — Field Notes UI

Garrett approved implementing the audited UI refinements and the Field Notes
concept, including the original fine teal generator style, offline equipment
art and saved System/Light/Dark appearance settings. Decision 0013 records this
direction. Work is isolated from the concurrent NOW-016 workflow stabilization.

## Acceptance

- All native screens resolve semantic theme colors; dialogs, forms, chips and
  status text remain legible in both modes.
- Settings restores a saved preference at startup, persists changes and handles
  failure; System follows the device. English and Spanish remain usable at narrow
  widths and enlarged text.
- Home puts actionable attention, personal work and operator checks ahead of
  tools, with explicit loading, empty and recovery states.
- Planning gives the schedule first position, retaining day/week/month,
  filtering, queues, service plans, booking and rescheduling behavior.
- Asset rows/details and relevant dashboard cards use accurate category mapping
  to bundled fine technical drawings, with unknown/load-failure fallback.
- Work-order naming and selected navigation reflect the screen being viewed.
  Optional creation details collapse without losing values. Long selected form
  labels remain readable. Checklist setup and steps have a clear visual boundary.
- Sync recovery explains the consequence in plain language, preserving NOW-016
  behavior. No service or role-policy changes are part of this UI work.

## Verification

Implementation and verification in progress. Final evidence will record guarded
analysis/tests, representative native light/dark screenshots and the packaged
APK. Physical phone appearance and interaction remain a separate acceptance step.
