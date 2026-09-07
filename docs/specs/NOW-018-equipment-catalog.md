# NOW-018 — Equipment catalog coverage

Garrett requested additional smaller boats, industrial fishing vessels and
land-based heavy equipment, each with a matching fine technical line drawing.
Continue the accepted Field Notes style from decision 0013.

## Scope

Preserve the thirteen existing types and their IDs. Add nineteen standard choices:
Pump, Marine Crane, Diesel Engine, RIB / Inflatable Boat, Aluminum Skiff,
Cabin Cruiser, Commercial Trawler, Purse Seiner, Tugboat, Backhoe Loader,
Skid Steer, Dump Truck, Motor Grader, Forklift, Telehandler, Road Roller,
Mobile Crane, Tower Crane and Davit. Garrett explicitly added land cranes and
davits to the request; keep these separate from Marine Crane.

The shared database catalog drives add/edit asset and checklist choices. Additive
migration only: do not alter existing assets, engine relationships, templates,
tracking units, roles or access policies. The expanded catalog continues using
engine hours as the existing maintenance tracking unit. Custom / Other remains
available for unusual equipment; this is broad practical coverage, not a claim
to enumerate every equipment class.

Every standard choice resolves by its complete stable ID and exact catalog name
to a dedicated category drawing. New drawings are bundled offline and use the
same theme-aware ink treatment. Unknown custom types retain the generic fallback.
Add/edit asset type rows show the matching drawing beside the type name.

## Acceptance

### Requested road-vehicle and button follow-up

Added LV / Light Vehicle and Highway Truck as distinct Road Vehicles choices,
bringing the standard catalog to 34. Both have dedicated bundled illustrations
and stable IDs ending in 021 and 022. LV also resolves by its abbreviation.
The additive migration preserves all 32 existing hosted rows. Tracking remains
engine hours under the current maintenance model.

The Add Asset floating button set a primary background without a matching
foreground, producing unreadable inherited text and icons in both appearances.
The shared floating-action-button theme now pairs primary with onPrimary. This
also fixes the same pattern in clients, requests, work orders, hours, engines,
parts, service intervals, organization codes and team actions. Default floating
buttons use the same pair throughout maintenance, reports, invoices and faults.
Regular filled, elevated, outlined and text buttons, including success/error
variants, passed contrast checks before, during and after pressing.

Build 22 (`1.11.1+22`) verification: clean analysis, 535 Flutter tests passed
(204 existing skips), local and hosted catalog contracts passed. The regression
first reproduced the incorrect foreground in both themes. Native light/dark
render checks passed. Evidence: `outputs/NOW018-followup/`. Device acceptance
remains separate from these automated checks.

- Existing catalog rows and asset links are unchanged; applying the new seed
  again does not create duplicates or overwrite owner edits.
- All 32 standard types have distinct mapped drawings, packaged in the app.
- Small boats and industrial fishing vessels are visually distinct. Heavy
  equipment shows the correct chassis, working attachment and silhouette.
- Add/edit selection retains the chosen stable ID; required validation and save
  behavior stay intact, including at narrow widths and enlarged text.
- Native light/dark renders show complete uncropped subjects without paper boxes.
- Local SQL contracts, catalog/art tests and guarded app verification pass.
- Hosted catalog activation, APK identity and physical-device acceptance are
  recorded separately.

## Verification

Implemented on `codex/now-018-equipment-isolated` in `work/equipment-catalog`.
The shared checkout was restored after every owned file was copied and
SHA-256-verified, because the stress-test and agent-access tasks are active.
The grouped Settings change is retained in the base commit `aeb7f40`.

Guarded verification passes with clean analysis, 519 Flutter tests and 204
existing skips. All 18 local SQL suites pass with the new migration. Focused
render/form verification passes 35 checks; the actual Add Asset form also passes
two light/dark selection proofs using all 32 choices and Mobile Crane's stable ID.
Evidence is under `outputs/NOW018/`, including all-category contact sheets,
native form captures, `verify.log`, `focused.log`, and `database.log`.

Sixteen new individual drawings were visually reviewed in both themes. Thumbnail
ink strength was corrected after the initial renders were too faint; the final
filter preserves the neutral-paper threshold and all transparent-background
checks pass. Original atlas drawings remain unchanged.

Build 21 (`1.11.0+21`) is packaged from `c422f12`. Inspection verifies the Next
package, signing certificate, Supabase/Firebase targets, notification service,
recovery link and exact bytes of all 17 artwork files. Source/APK evidence:
`outputs/NOW-018-build-verified.json`. SHA-256:
`9522e72e13d0989a17ea9aa06f899e1294da5feb31bb731a1cb852ad21ca1427`.

Delivered to verified Samsung `SM-S928W` Downloads as
`INSTALL-Vortice-Next-Build-21.apk`; the final phone SHA-256 matches. Installation
and physical-device acceptance were not performed. Delivery evidence:
`outputs/NOW018/phone-delivery.json`.

After the stress-test task completed its frozen-snapshot run and fixture cleanup,
migration `20260907130000_equipment_catalog.sql` was activated on Vortice Next.
Hosted verification finds all 32 types, confirms all 13 original rows unchanged,
and passes the new authenticated/anonymous access contract. Evidence:
`outputs/NOW018/catalog-verified.json`, `catalog-after.json`, `deploy.log` and
`hosted-contract.json`. The primary checkout includes this catalog checkpoint;
the concurrent agent-access work remains separate.
