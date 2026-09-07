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

Native implementation is committed on `codex/now-017-field-notes-ui`.
The guarded verification passes with clean analysis, 499 passing Flutter tests
and 204 existing skips (`work/verify-ui-final.txt`). It includes startup appearance
restoration, persistence failure, platform mode changes, actual selected chip
text, equipment mapping/fallback, role navigation, and real save/retry behavior.

Native screenshots use actual Roboto and Material icons. Representative Home,
Settings, equipment, checklist and form renders are in `outputs/ui-field-notes/`;
Planning day/week/month and Spanish large-text renders are in
`outputs/planning-ui/`. The final rendered subset passes 45 tests. Review corrected
selected filter contrast, status-message contrast, the Spanish operator headings
and a truncated part-number label. Form tests expand optional fields and scroll
lazy controls before asserting the existing save, validation and stale-edit rules.

## Combined Build 20

Integrated NOW-016 checkpoint `0c45fde`, preserving transactional saves, invoice
snapshots/status guards, evidence recovery, and stale-edit protection. Guarded
combined verification passes with clean analysis, 506 Flutter tests and 204
existing skips (`work/verify-combined.txt`). Independent conflict review found
no workflow regressions. NOW-016's unchanged database/deployment evidence remains
recorded in its spec.

Connected read-only audit passes 130 role/routes in light and 130 in dark across
owner, employee, client admin, client mechanic, operator and client. There were
no visible error texts, framework/provider failures, unfinished loaders or
unexpected redirects. All 260 entry screenshots and results are under
`outputs/NOW017/route-audit/`; sampled populated Home, Planning and form screens
were visually inspected. The harness now retains production themes and supports
an explicit audit appearance without saving user preferences.

The guarded Android build produced `1.10.0+20`, package
`com.example.vortice_app_next`, ARM64, with the existing Next signing certificate.
APK inspection verified Next Supabase/Firebase configuration, bundled equipment
art, notification service and password-recovery link. Evidence:
`outputs/NOW-017-build-verified.json`. SHA-256:
`e13e8c827745162207ef42c5baee232b729d517a64889296fbdadf9e4dca8136`.

Physical phone appearance and interaction remain a separate acceptance step.
