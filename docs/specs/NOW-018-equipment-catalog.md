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

Build 21 is `1.11.0+21`. Hosted activation and device delivery are pending while
the other task completes its connected tests against the existing catalog.
