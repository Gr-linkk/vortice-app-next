# NOW-007: Asset history, handovers and fleet decisions

Garrett authorized autonomous selection and complete implementation of three
more features through a checked internal APK. Select original items 14, 15 and
16 because they connect investigation, coordination and management around the
maintenance workflow delivered in Builds 8 and 9.

## 14 — One asset history

Provide an asset-scoped chronological record of meter logs, inspections, faults,
availability, work, service reports, parts/internal costs, asset/location changes,
and discussion attachments. Filter by category, date and search; inspect each
event and open its source where permitted. Export the selected service record.

Reuse existing records and immutable events. Clearly identify historical
snapshots of mutable records; do not invent missing events, dates or moves.
Capture subsequent changes as append-only history. Preserve previous values
when a part is removed or an asset's location changes. Imported procedure
documents are asset-type resources, not asset-owned documents; do not falsely
attribute them to individual machines. New manuals/QR/import authoring remains
item 13; financial invoice authorization remains NEXT-001.

History follows current fleet scope and the underlying job/discussion access.
Company operators must not gain private mechanic-job details through history or
export. Provider labour rates and internal notes must not leak to customer
views. Exports obey the same server filtering as the screen, escape spreadsheet
formulas, and cannot silently truncate a large history.

## 15 — Discussion and shift handover

Add discussions to managed maintenance jobs, existing service jobs and faults.
Support immutable comments, named mentions, photo attachments, and structured
handover notes with isolation status and outstanding/next-shift work. Record who
posted and when. Recipients can acknowledge handovers; retries have one effect.
Corrections are new posts so the event trail remains truthful.

Default notes to the author's team: provider staff or the asset's company team.
An explicit shared update is visible to authorized participants across those
teams. Server checks apply to posts, recipient selection, mentions, signed photo
URLs and handover acknowledgments. A mention never grants access. Revoked access
removes the corresponding inbox item. Company boundaries remain mandatory.

Mentions appear in the app's notification inbox with working deep links. This
does not promise background push delivery or escalation (separate item 6).
Upload photos privately and immutably, validate referenced objects before posting,
and preserve input/operation IDs across an uncertain response. Online persistence
is required; durable offline queues remain item 7. Disable writes honestly when
permissions/capabilities are unavailable, retaining authorized history reads.

## 16 — Fleet decisions

Give provider owners and company owners/admins a common actionable overview:
unavailable assets, urgent unresolved faults, overdue service, upcoming work,
service approaching its hour threshold, and work waiting on assignment,
people, parts or review. Every indicator opens its exact underlying records.
Show the three highest-priority distinct decisions first, with clear asset,
reason, due-state and next destination. Keep unknown availability and incomplete
plan setup visible instead of treating missing data as healthy.

Use explicit blocked categories (parts, people, external, other) and the existing
reason; never infer parts shortages from free text or claim inventory integration.
Upcoming calendar work uses the viewer's local date and seven-day horizon;
approaching service means within 50 recorded operating hours, not a forecast.
Server-scoped counts and paginated lists share one query contract. Display when
the data was refreshed; provide loading, empty, failure and retry states. Preserve
the current navy design, shared home landmarks and role-specific execution.

## Observable acceptance and delivery

1. A manager traces an asset's reading, fault, repair, part and completion in one
   history, filters/searches it and exports matching authorized rows. Changes
   and deletions retain truthful snapshots; pagination has deterministic order.
2. An assigned mechanic posts a handover with a private photo and a mention.
   The permitted recipient opens it from the inbox and acknowledges it. Retry
   creates one post/mention/ack; invalid or foreign attachments reject atomically.
3. Company B cannot read Company A's history, counts, posts, mentions or files.
   Provider-only notes are absent from company screens and exports. Operators,
   unassigned staff and disabled capabilities cannot bypass job access.
4. Dashboard counts match filtered record lists. Closed/resolved items disappear
   from actionable buckets; three priority decisions contain no duplicate job.
   Choosing a blocked category changes the correct waiting bucket.
5. Add failing behavior tests before implementation, run all SQL contracts against
   a disposable database, directly review authorization/concurrency/export paths,
   and run whole-project analysis plus the complete Flutter suite. Render actual
   production widgets in English and Spanish at narrow widths and enlarged text.
6. Verify only Next's project ref before additive deployment, run hosted rollback
   contracts and authenticated persona checks, then build `1.4.0+10` with guarded
   helpers. Verify package/version/signature and phone SHA-256/media indexing.
   The original repository, services, credentials and runtime remain untouched.

Physical installation/review remains Garrett's action; distinguish it from
native widget renders, authenticated service checks and APK delivery.

## Verification and activation — 2026-09-06

The three connected features are implemented in the native application. Entries
are available from asset, availability, managed-job, legacy-job and fault
details; every role has the shared mention inbox. Manager homes show three
distinct priorities and link to the full indicator list. English/Spanish
layouts preserve the shared dropdown spacing and safe bottom actions.

Validation completed before APK packaging:

- Whole-project analysis: clean (171.4 seconds). The full suite then caught the
  stale visible build label; it now agrees with `1.4.0+10`. Focused analysis of
  that final constant change and a repeat of the full suite passed: **360 tests,
  204 pre-existing skips, no new skips**.
- All **17 new Dart tests** pass, including history filters/pagination/export,
  CSV formula escaping, stable handover retries with one photo upload, editable
  input after rejected storage requests, read-only permissions, acknowledgment,
  exact mention links, manager route access and fleet-record navigation.
- Actual production widgets rendered at 390 px in English and 320 px with 1.5×
  Spanish text. Checked expanded isolation menus, keyboard viewport, error and
  retry state, history details, overview records and home priorities.
- All four SQL suites pass in disposable PostgreSQL, both as individual
  statements and as batched requests. A separate populated upgrade verifies
  backfill, snapshot labels, existing plans and retained deleted-part detail.
- All four rollback suites pass on **Vortice Next**. Three additive migrations
  are recorded; the new attachment bucket is private. Synthetic users, posts
  and photo metadata are absent after rollback. No real mention was sent.
- Authenticated HTTP reads and indicator/role checks pass for the six existing
  development personas: client, client admin, mechanic, operator, owner and
  employee. Record-specific discussion checks run where accessible records
  exist; the SQL fixtures cover populated threads, private files and Company B.

Direct review checked source authorization, team visibility, write retries,
attachment immutability, stable cursors, CSV output and indicator destinations.
It resolved snapshot dating and a potential attachment discard/post race.
Hosted verification exposed an additional platform deletion guard and the
management API's batched statement timestamp. The test respects the platform
guard; migration `20260906042000_history_read_cutoff.sql` captures the read
cutoff at function entry. The same batched failure was reproduced locally and
passed after the correction. Earlier deployed migrations were not rewritten.

Local evidence: `outputs/NOW-007-verification.log`,
`outputs/NOW-007-full-tests.log`, `outputs/NOW-007-version-analysis.log`,
`outputs/NOW-007-sql.log`, `outputs/NOW-007-batched-sql.log`,
`outputs/NOW-007-deployment-correction.log`,
`outputs/NOW-007-persona-http.log`, and
`outputs/screenshots/coordination/`. Final package and phone delivery evidence
is recorded in `outputs/NOW-007-build-notes.md`.

Build `1.4.0+10` passed package, ARM64 architecture and compatible signing
checks, then reached the Samsung SM-S928W Downloads folder as
`INSTALL-Vortice-Next-Build-10.apk`. The phone's 103,069,729-byte copy matches
the local SHA-256 and was scanned successfully. Physical installation and
device workflow review remain open.
