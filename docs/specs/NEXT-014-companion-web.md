# NEXT-014: One web workspace for office and field

Garrett requested this after mobile completion and clarified on September 25:
one web app with an office dashboard and full field workflows. This authorizes
adapting the existing app, not separate products or duplicated company data.

## Contract

Reuse Flutter screens, Next authentication and server permissions. Wide office
screens should make priorities, equipment, work planning and company tools easy
to reach; phone browsers retain compact navigation and the same execution forms.
Include reports, checklists, photos, parts, labour and approval as permitted by
role. Browser downloads must support PDF/XLSX/CSV. Account-owned browser storage
must preserve drafts and pending operations across refreshes and account changes.
Never compile demo passwords, service keys or local management credentials into
the web bundle. Require the independent public URL and client key.

Prepare a local runnable build and deployment instructions without purchasing a
domain or assigning an unselected public identity. HTTPS, browser storage
retention, actual camera/file-picker behavior and domain recovery callbacks need
explicit browser acceptance; mobile push configuration does not establish web
push. A successful compilation alone is not delivery evidence.

## Acceptance plan

Inspect real browser screens at office and phone widths, follow normal sign-in,
navigation, planning and field work entry points, and verify persisted language
and account isolation. Exercise browser evidence and downloads. Record exact
checks and limitations here after implementation.

## Implementation and browser acceptance — September 25

One Flutter application now supplies labelled office navigation and a two-column
Home on wide displays, with compact navigation and the same role-permitted
forms at phone width. The Field Notes design, Next authentication, company
permissions, data and shared workflow implementations are retained. Browser
URLs preserve equipment/job navigation on refresh. Recovery callbacks use the
same origin and require the eventual domain's explicit Next allowlist entry.
PDF and XLSX exports use browser downloads. Public builds filter local config
to the independent URL/client key, omit demo passwords and compiler maps, and
bundle their own runtime assets. A local-only preview and future deployment
instructions are in `docs/operations/WEB-DEPLOYMENT.md`.

Real Chromium testing signed in through the normal form, inspected Home at
1440×1000, opened Assets and equipment detail, resized to 390×844, disconnected
the browser, reloaded the same equipment URL, and returned online to the shared
work-order calendar. These five checks pass with no unhandled JavaScript
errors (`outputs/web/acceptance-storage.log`, `acceptance.json`, screenshots).
Offline preparation reports a successful refresh. Browser testing caught and
fixed a real quota failure: reference pages overflowed localStorage. The app
now uses committed IndexedDB writes for browser preferences/drafts/read caches
and account-specific SQLite/OPFS for its durable outbox. Two actual browser tests
pass for 6 MB persistence, reopen, account-specific removal and safe migration.
The office/sidebar and offline banner were also restored to the browser's
accessibility tree around nested navigation.

Shared mobile workflow fixes in this round: an operator can resume an assigned
checklist while the fleet is refreshing; a same-account permission-epoch race
retries a read once against the server without permitting stale-cache fallback.
Regression tests cover simultaneous refresh, changed accounts and denied reads.

This is a local release-mode preview, not public hosting. Final domain/email
callback acceptance, phone-browser camera/gallery behavior, browser push and
Safari/Firefox acceptance remain open. Browser storage is origin-specific and
can be evicted/cleared; move to the eventual domain only after syncing. The
bundled offline shell is substantial (about 81 MB uncompressed), so first-load
and slow-network download optimization remain polish work before a public web
rollout. A cached shell alone does not establish prepared company data.

Guarded shared-app verification: 818 tests and clean analysis, recorded in
`outputs/web/verify42.log`. Final web artifact inspection confirms that none of
the configured developer passwords nor `DEV_LOGIN_PASSWORDS` appears in the
compiled JavaScript. Build 42 artifact: `outputs/web-build-dEXYMBLJ/`; superseded below by Build 43.

French browser preference also survives reload at 320 px; the independently
reviewed mobile French and large-text evidence remains in NEXT-013. The S24
Build 42 startup screen and settled offline-ready Home were inspected after the
preserving update (`outputs/build42/first-launch.png`, `settled-home.png`).

A further mechanic browser test found that warming every active library template
could request private pages outside the equipment scope. The server correctly
denied those pages and invalidated the read cache, preventing offline reopening.
Preparation now uses the same equipment/company/type scope matching as the
checklist picker, retains explicit pending/in-progress assignments, and prepares
component instructions from the assigned jobs. It does not bypass source access
checks. A regression covers unrelated company/equipment/type/component scopes
and retained historical assignments. The real browser then reopened its report
and saved photo offline under Build 43.

Build 43 final artifact: `outputs/web-build-UKNBBOgq/`; guarded verification passes
819 tests with clean analysis. Both exported files were downloaded by the actual
browser from an existing issued demonstration invoice. The PDF parses as a
one-page invoice and the XLSX archive/workbook structure and CRCs pass
(`outputs/web/invoice-browser.pdf`, `invoice-browser.xlsx`). Historical invoice
identity/currency were retained; this is not an unreviewed Canadian issuer setup.

The field write test used a dedicated fixture and isolated mechanic. Normal entry
was Work orders → Unscheduled → Continue work → Start work → Pause → Create
service report. It filled findings/results, attached a photo through the actual
browser file chooser, saved a note offline, refreshed the browser, and reopened
the same draft/photo. It then attached a second photo while offline and submitted
for review. The UI showed two pending uploads; reconnect + Retry uploads marked
the report and both photos Synced. Hosted readback confirms `pending_review`,
the exact findings/results/offline note, and two evidence paths. Captures and
readback: `outputs/web/field-workflow/` (`field-offline-restored43.png`,
`field-submitted-offline.png`, `field-reconnected.png`, `server-submission.json`).

The office account signed in within the same browser after the mechanic signed
out, found the submitted work, reviewed it and chose Approve & complete → Confirm.
Hosted readback is `closed` with both photos and unchanged report text
(`approval-readback.json`, `office-review43.png`, `office-approved43.png`).
Calendar search's undated-result gap was found during this path and fixed under
NEXT-006: non-empty searches open the results List automatically. Domain, real
phone-browser camera and cross-browser acceptance remain separate.

Final source-page diagnosis also found old work-order snapshots whose individual
items omit `template_id`, although the saved parent publication is present.
Read models now carry that parent ID into missing item fields for maintenance,
provider context and checklist snapshots. Existing item IDs are preserved and
stored snapshots are not rewritten. A real denied request with a null template
succeeded through the same authenticated source RPC when given its saved parent
ID; no access rule or source data was changed. Regression coverage verifies
inheritance, explicit identities and non-mutation. Final artifact and verification
receipts supersede the intermediate Build 43 evidence above.

## Final Build 45 receipt

Final website artifact: **`outputs/web-build-cb6CegKd/`**, matching shared Build 45
(`1.20.4+45`). Guarded verification passes **822 tests and clean analysis**
(`outputs/web/verify45-final.log`). Artifact scanning checks all 11 configured
developer passwords and the private login define: none appear in the public
files (`outputs/web/public-config-scan45.json`). The S24 installation and file
preservation receipt are in NEXT-009.

Normal office Month → Search & filters → text query → Show work orders now opens
List and exposes undated and completed matching work (`office-search44.png`).

The final fresh-browser replay passes all four stages with **zero unhandled
JavaScript errors**: permitted offline preparation; report draft reopened after
an offline browser refresh; actual file-picker photo and report queued offline;
reconnect with exact hosted report/evidence readback. Receipts:
`outputs/web/field-workflow/build45-final-smoke.log`, `final-browser.json`,
`final-offline.png`, `final-synced.png`.

Office acceptance on the final artifact then followed normal Work orders search,
opened that submitted job and chose Approve & complete → Confirm. Hosted readback
is `closed` with the same report text and its photo. Evidence:
`office-search45.png`, `office-review45.png`, `office-approved45.png`,
`approval-readback45.json` in the same receipt directory.

All browser-created fixture jobs, the exact fixture asset and seven evidence
objects were removed after acceptance. Unrelated record counts were preserved:
`cleanup.log`, `cleanup-20260925T070705Z-93a8faaa.json` in that directory.

The earlier opaque browser error was traced to an eagerly created signed-photo
URL future that nobody observed while the local photo rendered. The widget now
waits for the outbox's initial restore and only requests a remote URL when its
result is needed and observed. The regression proves local evidence renders
without a remote request. Browser dispatch also retains queued work without
starting transport while the browser reports offline. Previous failing receipts
remain diagnostic history; the final run supersedes them.

A second real browser check deliberately rejects one app-shell cache asset.
Sign-in still renders with no unhandled exception. Startup now observes a failed
service-worker installation instead of waiting indefinitely on `ready`.
Evidence: `outputs/web/shell-fallback45.json`, `shell-fallback45.png`.

## Remaining acceptance and polish

These are the current limits of this local preview, not additional products:

- Connect the chosen HTTPS domain/host and recovery email domain, then verify
  the actual response headers and a real password-recovery inbox/callback.
- Exercise camera/gallery, QR and notification behavior on the supported physical
  devices and browsers. Chromium field execution is verified; Safari/Firefox and
  actual phone-browser device APIs are not yet accepted. Web push is unconfigured.
- Reduce the first offline-shell download (about 81 MB uncompressed); category
  illustrations and bundled runtime variants dominate. A reliable connection is
  needed for initial preparation, and browser storage can still be evicted.
- Complete less common French setup/coordination/recurrence strings and hosted
  email/export headings identified in NEXT-013. Ordinary French workflows and
  large-text layouts have separate rendered evidence.
- Polish the read-only linked-fault offline message: it currently uses a generic
  connection error above the retained job/report. Pending work remains stored;
  parts availability and other fresh server decisions require a connection.

Production issuer/tax review, recovery proof and operating decisions remain in
NEXT-009/NEXT-011. Google Play remains deferred by Garrett. This local preview
and internal debug APK are not a public production release.
