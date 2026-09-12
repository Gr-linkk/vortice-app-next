# NEXT-004 — First-time usability and computer acceptance

September 12, 2026. Requested by Garrett alongside computer E2E testing; he
subsequently confirmed **suggestions and small changes only**.

## Verdict

An operator can probably learn the daily checks and fault-reporting flow with
a short introduction. A mechanic has recognizable work/report actions once
assigned work exists. A new owner or supervisor would still need help setting
up maintenance and understanding the different places that show work.

This is an expert walkthrough of real rendered screens, not a study with new
users. No nontechnical participant was observed, so this does not establish a
task-success percentage or prove the app is self-explanatory. The main problem
is missing guidance at transitions, rather than a need for a new visual design.

## Scope and method

- Five current demo roles: fleet owner, supervisor, mechanic, operator and
  service-company owner. Captured Home, Assets, work/fault navigation, More,
  asset details, fault forms, company/services, maintenance setup and completed
  provider work where applicable. An operator opened a real asset checklist.
- Actual Flutter application widgets, routes, localization and Next backend,
  driven by the computer test host. Local preferences/database are disposable.
  This is connected app-screen testing, not an installed Windows or browser
  package certification. Initial logins and some deep pages use harness/API
  entry; primary destinations and checklist entry use rendered controls.
- English layouts at 390 × 844 and 1440 × 900; 320 × 844 with 200% text checks
  legibility. Parts testing also includes a Spanish/dark/200% form.
- Saved fault-to-repair and parts/recurrence journeys use uniquely named E2E
  fixtures. Setup and some final assertions use repositories/API calls; the
  report identifies those boundaries rather than claiming every action was UI.
- No phone interaction, installation, permission prompt or background-push
  acceptance. Email/SMS delivery remains deferred under NEXT-002.

## What already helps ordinary users

- Fault reporting asks **“What needs attention?”**, provides a useful example
  prompt and has one obvious **Submit report** action.
- Operator asset cards say **Start checklist** and lead directly to the matching
  daily check. Pass / Fail / Not applicable and the completion button are clear.
- Company membership lists use recognizable owner, supervisor, mechanic and
  operator roles. Company connections explain that approval comes first.
- Work creation puts the asset, title and instructions first and folds secondary
  plan/checklist details into **Optional details**.
- Provider reports name the equipment and the customer/provider companies;
  report review separates customer-visible results from internal costs.
- The existing warm background, teal controls and equipment illustrations are
  coherent. Preserve them.

## Small defects corrected in this pass

| ID | Observed problem | Correction | Evidence |
|---|---|---|---|
| U01 | The selected **Show work** label was visibly clipped, hiding which category/count was selected. | Let the dropdown use its normal row height. | Before `brf6R25x/fleet_owner-work-orders.png`; after `l7JkAdce/fleet_owner-work-orders.png`. |
| U02 | Assets used a fixed-height search/filter header. At 320 px / 200% text it overflowed into the asset list. | Let the header take its natural height above the scrollable results. | Failing run `xRWAPY2y`; clean repeat `WVcLV6IO`, including `fleet_owner-assets.png`. |
| U03 | Work footer said **Online planning** even though the screen also supports cached/offline work. | **Schedule times use this device’s time zone**, with matching Spanish wording. | `l7JkAdce/fleet_owner-work-orders.png`. |
| U04 | Internal provider labour displayed a long floating-point fraction. | Display two decimal places, consistent with the recorded labour summary. | `E7PLKNPJ/service_owner-completed-work-footer.png`: **0.14 labour hours**. |
| U13 | Leaving the original work screen while its parts page remained open caused an update on a disposed widget when parts closed. | Check that the originating widget is still mounted before refreshing it. | Connected failure `NFbIjTHm`; focused regression failed before the one-line guard and passed after it. All five parts-screen tests passed. |
| U14 | Confirming a starting meter reading disposed the input controller before the closing dialog animation ended, causing a framework error. | Let the text field own its controller for the complete dialog lifetime; retain the entered reading and existing validation. | Connected failure `AtdtxRsA`; focused regression reproduces the crash before the fix and passes afterward, including the saved reading. |

Screenshot short paths above resolve beneath
`outputs/usability-20260912-<run>/screenshots/audit010/`.

## Suggestions, in priority order — not implemented

| ID / priority | What a new person is likely to ask | Observed cause | Suggested small next step |
|---|---|---|---|
| U05 / High | “Where did my job go?” | Owner Work opens Week, mechanic Work opens Day, while Open counts can include work outside those dates or without a booking. Completed work also requires changing the category. | Explain the date/category scope in the empty state and offer **Show all open work**. Discuss a default List view separately; do not silently change the established calendar behavior. |
| U06 / High | “What do I have to set up first?” | Home says **Maintenance setup**; the maintenance page offers Plan maintenance, Work orders, New work order, Add component and Add plan. These are meaningful to an experienced planner, but their order is implicit. | Add one short instruction: choose equipment, add its maintenance schedule, then assign the generated work. Use a concrete example such as a truck oil change. No setup wizard or rebuild proposed for this pass. |
| U07 / High | “Did I save this, and can anyone else see it?” | Provider editor distinguishes a device draft, **Save to server**, **Submit for review**, and later approval. It already explains that the customer receives the approved report, but the technical save label requires interpretation. | Prefer **Save draft online** and explicit status such as **Saved on this device — waiting to upload** / **Submitted — waiting for review**. Keep approval and customer visibility rules unchanged. Editor wording is source-reviewed; the prior NEXT-003 phone journey supplies its physical acceptance, not this read-only audit. |
| U08 / Medium | “It says no checklists are assigned. Am I supposed to do one?” | Operator Home says **No checklists assigned to you**, immediately followed by available **Start checklist** entries. The actual entry worked. | Explain **No assigned checks. You can start an available equipment check below.** Distinguish available work from assigned obligations. |
| U09 / Medium | “I finished the repair. Why is the fault still open?” | The saved repair journey deliberately requires approval and separate fault verification. | On approval, show who must verify the fault next and link to it for authorized users. Preserve the safety-related separation between recording work and verifying the result. |
| U10 / Medium | “What do these words mean?” | More/setup use **PM**, **Custody & inspections**, **Fixed milestones / transition**, and **Saved work and sync**. | Expand PM to preventive maintenance on first use; use a plain description under advanced scheduling and custody tools. Prefer examples over adding more help buttons. |
| U11 / Medium | “Which company am I working in?” | Home greets the person and uses **My company** for an owner, while the actual company name is clearer on company/work pages. | Show the current company name with the role on Home. This becomes especially useful when joining more than one company. |
| U12 / Low | “Why is everything stretched across my monitor?” | At 1440 px, cards and forms remain full width and related labels/actions can be far apart. | Consider a comfortable maximum content width for desktop forms after discussion. Preserve navigation and mobile layout. |

Do not combine these into a large redesign. Start with U05, U07 and U08 wording,
then test whether new users can identify the next action without coaching.

## Computer checks and evidence

- **Modern-role visual pass:** `outputs/usability-20260912-brf6R25x` and
  `outputs/usability-20260912-l7JkAdce`; five role steps passed. Expanded desktop
  capture `outputs/usability-20260912-E7PLKNPJ` passed. Each directory contains
  `usability-pages.json`, screenshots, a step report and the original run log.
- **Repair journey:** `outputs/usability-20260912-HicjzGAi` passed all six steps:
  operator fault report, prefilled assigned repair, asset-scoped discovery,
  timer/report/draft recovery and submission, approval then fault verification,
  and operator/other-company private-work boundaries.
- That repair used the existing test manager as assigned executor. The ordinary
  shared legacy mechanic has an unrelated running DEMO timer dating September
  10. It was preserved. This pass therefore does **not** certify a fresh saved
  journey under the modern mechanic role; modern role/account scope is checked
  separately. The normal connected test executor remains the mechanic by default.
- **Hosted rollback contracts:** organization membership/invitation/revocation,
  Work hub scoping and recurring-work generation passed against Next. The
  recurrence contract covers repeat generation, frozen tasks, meter context,
  review/completion behavior and authorization. Files:
  `outputs/usability-contracts-20260912/`. These are backend assertions, not a
  real email/SMS invitation delivery or unattended phone acceptance.
- **Focused regression checks:** 17 planning/provider-execution tests passed.
- **Large-text repeat:** `outputs/usability-20260912-WVcLV6IO` passed all five
  role steps with no framework issues at 320 px / 200% text after U02. The
  original run had five header overflows and remains available for comparison.
- **Modern account switching:** repeat `outputs/usability-20260912-aQXqNi6V`
  passed all five roles through the actual development picker, with company,
  capability, asset visibility and meter assertions.
- **Parts/recurrence connected journey:** `outputs/usability-20260912-l4DaXOqx`
  passed all ten steps: published PM parts kit, saved hour/calendar plan, frozen
  job requirements, counted stock, reservations, purchase/receipt, Spanish dark
  200% forms, use/return, submission/approval and net-cost/next-target checks,
  plus other-company denial. Like the repair journey, its assigned executor
  was the test manager. It awaited the app's automatic starting-work upload;
  no manual queue flush or timeout relaxation was used to make it pass.
- **Final guarded verification:** code generation, analysis and all **728**
  Flutter tests passed, including the two new crash regressions.
  `outputs/usability-release-verify-20260912.log` contains the clean-analysis,
  `+728: All tests passed!` and `Project verification passed.` markers. The
  PowerShell redirection wrapper returned 1 from native build-hook stderr,
  despite those stages completing; this is not recorded as a zero wrapper exit.
- **Final cleanup:** repair receipt
  `outputs/usability-20260912-HicjzGAi/cleanup-20260912T204035Z-3f0fc170.json`;
  parts receipt
  `outputs/usability-20260912-l4DaXOqx/cleanup-20260912T205800Z-341f492d.json`.
  Both have `status: complete` and preserved unrelated counts. Failed-attempt
  directories also have completed exact-fixture cleanup receipts.
- **Machine-readable evidence index:** `outputs/usability-final-receipt.json`.
  Five selected connected runs contain 31 successful steps with zero issues.
  The backend check also confirmed the retained phone work remains invoiced,
  its zero-charge invoice remains sent, and the earlier legacy demo timer is
  still running with its original start time.

## Test corrections and limitations

The first audit attempt used three incorrect demo email names and was discarded.
The older repair script selected a duplicate bottom-navigation label instead of
the asset button and expected **Continue service report** on a new blank report
whose current action is **Create service report**. Those were test defects.
The older parts script needed current meter-unit labels and the **Review parts**
entry, and must confirm the starting-meter dialog before touching the work
screen. Failed attempts remain on disk; they are not reported as passing runs.

The first modern account-switch attempt (`BZQ5elWk`) stopped on the mechanic's
six-second asset-workspace timeout during concurrent checks. It is recorded as
a failed attempt, not evidence of permission denial. Repeat `aQXqNi6V` passed
all five roles without changing the app timeout or bypassing its checks. The
timeout's cause was not established; it should not be reclassified as a fixed
performance defect.

Fixture cleanup initially encountered the newer work-source foreign key and
rolled back. Cleanup now deletes only source links belonging to the selected
run’s exact work IDs before deleting those test work orders. Completed receipts
confirm removal of exact test assets/procedures and preservation of unrelated
record counts. No old demo timer or NEXT-003 phone acceptance record was reset.

## Follow-up acceptance with a new user

Give someone these tasks without naming menus: report a problem on a truck;
find the job assigned to them; save unfinished work and return to it; submit a
completed repair; find what requires review; set a recurring service. Observe
where they hesitate, choose a wrong destination, or ask whether data was saved.
Record completion and assistance before deciding on larger changes. This is a
recommended later check, not something completed by the computer audit.

## Delivery boundary

The six fixes are packaged in internal Build 34 (`1.16.5+34`), built from
`c02748d67462c755b03675755a552d8d788dc1e9`. Package, version, ARM64 architecture,
existing signing certificate and isolated Next resources passed inspection.
`INSTALL-Vortice-Next-Build-34.apk` was checksum-verified in both the S24 Downloads
folder and `C:\Users\Garrett\Downloads` on September 12, 2026. SHA-256:
`edf8787ecea87e2067f0ae760cc1a706e55d2741d73b8fff5b62f4145ee2f778`.

Local receipts are `outputs/build34-build-verified.json`,
`outputs/build34-phone-delivery.json` and
`outputs/build34-computer-delivery.json`. Build 34 was not installed and its
physical acceptance remains pending. The S24 UI was not operated during delivery.
No service migration or email/SMS configuration was needed. The eight suggestions
remain unimplemented.
