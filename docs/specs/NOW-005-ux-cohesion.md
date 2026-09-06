# NOW-005: UX cohesion

Garrett approved a broad usability pass across the existing Next codebase after
testing build 1.1.2+4. Priorities: simple discovery, consistent interactions and
removal of unnecessary duplication. Preserve useful features and the current
navy visual identity. This is an app UX pass, not a new service or product slice.

## Working scope

1. Review the role entrypoints and asset-to-work journeys. Consolidate primary
   navigation and group secondary tools with plain descriptions and search.
2. Keep asset and fault routes consistent for company and provider roles.
   Remove redundant retired dashboards and inactive UI only after caller checks.
3. Improve loading/error/empty/filter states in the main lists and forms.
   Explain recovery in ordinary language; do not expose backend exceptions.
4. Put useful asset actions before secondary details, connect history to current
   work, and protect unsaved form input when navigating away.
5. Verify actual Flutter rendering and interactions at phone widths, with
   enlarged text and English/Spanish coverage for the shared changes.

## Boundaries

All changes stay in Vortice Next. Preserve company scoping and existing optional
capability gates. No feature removal based merely on low usage; remove only
proven duplication or nonfunctional controls. Do not delete user data. The two
previously prepared backend migrations remain pending explicit hosted approval.

## Validation and delivery

Record concrete findings and dispositions in this document. Run role/navigation
and form regression checks plus the prescribed verification. Build with the
existing guarded helper, verify package/config/signature, and place a clearly
named APK in the phone's shared Downloads folder with a matching checksum.

## Implemented findings

| Area | Finding and correction |
| --- | --- |
| Navigation | Replaced seven repeated role menus with one destination catalogue. Home, Assets, Faults and More remain visible for every role; staff retain Work and enabled operators retain Checks. Secondary tools have searchable English/Spanish descriptions. |
| Role boundaries | Client-admin, mechanic and operator asset taps previously defaulted to owner URLs. They now use client routes; employees have their own asset list/detail routes. Asset creation remains owner-only. Service requests are offered only to the two client manager roles and provider staff, matching the existing controller policy. |
| Shell forms | GoRouter shell `matchedLocation` stayed on the previous page after a push. Using the current URI hides tabs on authoring routes and selects the correct tab on detail pages. Android Back now uses `maybePop`, respecting form protection. |
| Unsaved input | Fault, service-request and work-order forms prompt to keep editing or discard. Saving blocks Back. Explicit form back buttons also work when opened without a previous page. Existing persistent report/checklist draft flows remain in place. |
| Report drafts | Reproduced loss of the final edit when Back cancelled the 350ms debounce timer. Disposal now captures pending text; clearing a submitted draft cancels the timer so it cannot restore cleared content. |
| Assets | Current work, readiness and workflow actions precede secondary identification details. Serial number, year, location and assignment remain available in an expandable Details card. Search can be cleared, unmatched searches explain recovery, short lists support refresh, and long locations wrap. |
| Requests | The existing client request-history screen was unreachable because its route redirected to a new form. The list is now reachable from More, with its existing Request Service button. Successful direct form submission returns to history. |
| Recovery | Replaced raw exception text across asset, work, report, invoice, checklist, parts, telemetry, company and login surfaces with plain guidance. Main list/detail errors have retry controls where added; the service-request asset error no longer silently disappears. Forgot Password now explains how to get access help instead of doing nothing. |
| Account | More contains language selection, deliberate sign-out and the build number. On Garrett's follow-up request, the same confirmed sign-out action is also available at the top right of every dashboard. A regression checks the displayed version against pubspec. |
| Duplication | Removed unreferenced `ClientDashboard` and `ClientDashboardFree`; kept their used role dispatcher in a dedicated file. The legacy operator dashboard route redirects to the canonical operator experience. Removed two trivial legacy fault wrappers while retaining their working routes. |
| Dashboard coherence | Removed a static Scheduled Maintenance placeholder. Existing open-fault rows now open fault details, and nearby labels use Assets/Faults consistently. |
| Large text | More gives text the full row width at larger font sizes; verified English and Spanish Flutter rendering at 320–390 logical pixels, including 1.4–1.5 text scaling. |

## Review and verification record

- Direct review of changed routes, role policies, capability gates, caller
  references, form exits, draft persistence and error recovery. No independent
  reviewer was used.
- Seventeen navigation/interaction regressions cover all seven role enum values,
  existence of every destination in the actual app router, role-correct asset
  taps, search, large Spanish text, shell Back and direct-form Back/discard.
- Two report-draft regressions cover immediate exit and clearing submitted work.
  The immediate-exit test failed before the fix and passed after it.
- Rendered Flutter evidence is in ignored `outputs/screenshots/ux-*.png`.
  These are actual widget renders with fixture data, not physical-device proof.
- Final prescribed verification and APK delivery results are recorded in
  `outputs/NOW-005-ux-build-notes.md`.
- Build `1.2.0+5` passed the prescribed verification (311 tests, 204 existing
  skips) and was delivered as `INSTALL-Vortice-Next-Build-5.apk` to the phone's
  shared Downloads. Package, signing certificate, embedded build configuration,
  phone checksum and media indexing were verified. User installation/review is
  pending.

The inherited app is not fully translated by this pass. Invoice authorization
before real customer data remains the separate backlog audit. The prior two
hosted migrations are still pending; this UX task changes no hosted schema.

## Sign-out placement follow-up

Garrett requested Sign out at the top right of every home dashboard as well as
More. Build `1.2.1+6` uses a shared `SignOutButton` and confirmation handler for
owner, employee, client manager, mechanic, operator and telemetry dashboards.
The dashboard icon is the final app-bar action, to the right of the notification
bell where present. The More account action remains available. Both entry points
use the existing English/Spanish confirmation and error handling.

Verification: clean analysis and 311 passing tests (204 existing skipped
checks). Build 6 was delivered to shared phone Downloads with its checksum and
media indexing verified. Details: `outputs/NOW-005-signout-build-notes.md`.


## Dashboard consistency follow-up

Garrett requested a consistent dashboard experience across profiles. Build
`1.2.2+7` preserves the navy visual identity and uses one shared Home app bar,
greeting and role/date line, fleet status card, four quick actions, section
headings and pull-to-refresh behavior. Sign out stays at the far right and in
More. The common action cards adapt to one column for narrow screens or large
text; role-specific destinations and capability checks remain in place.

Removed three repeated notification buttons, two competing KPI/shortcut
layouts, the extra owner floating action, and duplicate request/fault buttons.
Their actions remain in the shared shortcuts, bottom navigation, or More.
The mechanic parts section was a confirmed placeholder whose provider always
returned an empty list; it was removed without changing parts workflows.
Checklist entry cards now use the same tappable list pattern and keep asset
and template context. Owner alerts/work appear before the client directory;
client faults appear before historical service. Employee Home remains usable
while the work queue is loading or unavailable. Telemetry cards and client
summaries wrap on narrow displays instead of overflowing.

Seventeen new widget checks cover all seven roles, populated dashboards at
320 px with Spanish and 1.5x text, checklist navigation, disabled capability
shortcuts, and usable loading/error states. Existing route checks now also
verify all dashboard destinations. Phone-sized screenshots are saved under
`outputs/screenshots/dashboard-*.png`; final verification and APK delivery
are recorded in `outputs/NOW-005-dashboard-build-notes.md`.
