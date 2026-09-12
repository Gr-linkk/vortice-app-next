# NEXT-002: Workflow consolidation, Batch 1

September 12, 2026. This delivery implements bounded slices of the active
Kanban; it does not close the whole board. Internal Android version: 1.15.0+28.

## Reconciled plans

- Membership (.18) must precede owner onboarding (.01). Legacy `owner` is
  provider/platform authority; it cannot be relabeled Company Owner safely.
- Checklist and report source/completion links (.03/.05/.07) precede recurring
  generation (.04). The inspection-work bridge must exist before removing
  renewal under .13, preserving immutable certificate history.
- Flexible meters (.15) precede distance-based recurrence. Existing hour and
  calendar plans remain authoritative until their replacement is implemented.
- Common service-report language does not merge private internal snapshots,
  provider publication or billing. Every report has an order; not every order
  must have a report, and an order may have multiple reports.
- Build 27 already activated NOW-023/024. Stale pending-deployment language was
  corrected, and the older unselected inventory is no longer a live priority.

## Delivered behavior

The Work orders destination opens the shared planning hub. List, Day, Week and
Month views preserve filters and date when opening work; Month includes actual
work later in the month and retains access to unscheduled work. Mine, Open,
Unassigned, Unscheduled, Needs review and Completed are available, along with
overdue/blocked filters and asset, component, worker, status and work-type
search. Home's View all my work opens Mine. Provider work retains its existing
access and billing rules, including secondary worker assignments.

Generic operator checklist entry explicitly chooses an active authorized asset,
then its matching published checklist. A single matching checklist opens
directly; several matches require a choice. Assigned entry retains its explicit
asset/checklist context. Unfinished checklists are offered for resume with
asset, checklist version and original start time; starting another preserves
the previous answers, photos, assignment and replay identity. Account-owned
storage imports recoverable older drafts, including returned queue corrections.
The selected asset remains prominent while recording results.

Fault actions say Create/Open work order. Linking existing work stays secondary;
approval does not silently verify a repair or return equipment to service.
Internal report actions and lists use Service report vocabulary.

Team now focuses on members and invitations. The form creates an invite code
and explicitly explains that no email is sent. Copy and Share expose the
existing single-use code, with validation and duplicate-submit protection.
Checklist assignments remain reachable from the Checklist library menu under
the existing company-manager access checks.

The internal build exposes **More > Switch test account** and **Developer
sign-in** on Login. Selecting a configured profile signs in directly; switching
uses normal sign-out first, preserving account-owned drafts and queued work.
The current account and unconfigured entries are disabled. Additional
`@vortice.dev` accounts in the private `DEV_LOGIN_PASSWORDS` build configuration
appear automatically without screen edits or invented roles. The picker and
credentials remain restricted to debug builds on the exact Next backend.
No new accounts, passwords or permissions were created for this change.

## Review corrections

Independent reviews traced work scope and assignment, draft/account isolation,
photo and replay preservation, mounted-state handling and access routes.
Corrections include secondary-provider Mine filtering, provider creation for
employees, exclusion of completed work from overdue/conflict warnings, and
distinguishable same-asset drafts. Provider hub loading batches scoped assets,
components, assignments and worker names, anchors every page to the initiating
account and rejects inconsistent component/asset links. A cold provider-only
probe of the same 154 jobs and 44 plans improved from 4,699 ms to 3,187 ms.

The native account-switch regression exposed overlapping animated shell pages
sharing go_router's navigator key on return to the owner. The authentication
shell now uses a non-animated page; nested work/detail navigation stays intact.
The exact six-account sequence then passed, including returning to the original
draft. No artificial delay or swallowed framework error was added.

The old form-spacing test assumed a removed checklist dropdown and wrapped the
new full-screen selector in an unbounded scroll view. It now exercises the
actual bounded selector and the request dropdown separately, retaining the
320-pixel Spanish large-text layout and selection assertions.

## Verification

- Clean analysis and all 668 Flutter tests passed in the guarded verification.
- The 107 focused/rendered workflow checks passed, including account-switch
  error handling and account/page-boundary regressions for bulk planning reads.
- All 128 role/route checks across six roles passed with zero error text,
  framework/provider errors or remaining loaders. The owner hub rendered in
  2,623 ms in that run. The audit now records route timings and allows a bounded
  10-second live wait, after measuring valid cold requests above its previous
  3.5-second capture window. Evidence:
  `outputs/kanban-live-psWxQ5nj/route-audit/system/en-1.0x/routes.json`.
- The connected native switcher test passes all seven stages: Login to owner,
  More to the other five configured profiles, and back to owner. It asserts
  each actual profile/role, hides the original draft from other accounts and
  recovers it unchanged on return. Evidence: `outputs/kanban-switch-qZWOkNBO/`.
  Fixtures use disposable local preferences/databases; no fleet records changed.

All 25 local PostgreSQL contract suites passed. The additive
`20260912090000_work_hub.sql` migration is active on isolated Next
(`hkjpojobdbbtjkhaudki`), and its rollback-scoped hosted contract passed. The new
read API includes completed work without changing the older forward-planning
contract. No account/data reset or membership-role migration was performed.

Rendered native tests cover light/dark operator entry and recovery, invite
creation/success, work filters/month agenda, and narrow Spanish large text.
Representative PNGs were visually inspected in `outputs/kanban-ui/`.
These checks are separate from installation and physical Android acceptance.

The authentication-shell correction was exercised by the exact connected
regression and all 32 focused navigation/back-button checks after the full
suite. The final shortened picker copy also passed the 107 rendered workflow
checks. The final picker was inspected at 320 pixels with 200% Spanish text.

## Build 28 and source delivery

Source commit: `b25d245cf61c7f24fe8a46172fa322ad1907e00b` on
`codex/kanban-workflows`. The guarded APK build and package inspection passed.
Inspection confirms version 1.15.0+28, the Next package/backend/Firebase,
signing certificate, notification service, recovery link, bundled equipment
artwork and the new work hub, checklist, invite and account-switcher code.
Normalized source matches that commit.

Artifact: `outputs/builds/INSTALL-Vortice-Next-Build-28.apk` (200,135,202 bytes).
SHA-256: `71bd0275c2738051209aa511c8a486accb0f888d2a0c25e85d8be450b0f03620`.
Inspection receipt: `outputs/build28-build-verified.json`.
The APK is prepared locally; installation and physical phone acceptance have
not been performed.

For profile testing, open **More > Switch test account**, or **Developer
sign-in** on Login, then tap the desired profile. Test accounts use their real
current permissions. Creating the future Company Owner/multiple-working-role
test matrix remains part of the coordinated .18 migration.

## Remaining scope and next sequence

Fleet decisions and the asset/inspection destinations remain until all their
signals have matching actionable domain screens and count definitions.
Provider hold records currently lack the managed work's structured blocked
category; they appear under Other blocked work rather than fabricated
parts/people categories.

Operator asset caches need one connected refresh after upgrading before the new
active-asset lifecycle filter can be used offline. Automatic ordinary-use
offline preparation is still .17 work; this batch does not claim its airplane
mode, restart, revocation or expired-authentication acceptance.

Next connected slice: finish .03/.05/.07/.08 work-order checklist/report source
and completion links, then .04 recurring generation and inspection bridging.
Run .18 membership/access migration as its own coordinated slice before .01
onboarding. Do not relabel legacy roles or remove inspection history as a
shortcut. Broader meters, catalog, onboarding and Fleet consolidation remain
open on the Kanban; .21 physical acceptance is still required.
