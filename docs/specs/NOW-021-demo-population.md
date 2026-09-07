# NOW-021: Demonstration data

Garrett requested a populated app demonstration, retaining the Ellicott dredge
and using manuals on the Lenovo for supported technical details. This is a data
preparation task for the isolated Next backend, not an application release.

## Populated September 7, 2026

The existing Ellicott 460SL, its CAT C15 MCW10441 and its generator remain in
place. Its previously empty location/notes now describe the demo. Synthetic
meter readings are 7,242 hours for the C15 and 1,845 for the generator; they are
not actual meter observations. Existing names, serials, ownership and original
service intervals/checklists were retained. Two legacy placeholder fault labels
were replaced with neutral inspection-required wording.

The same company now has three supporting demo assets: a marina support boat,
shore excavator and shore generator. New operating records are labeled DEMO:

- 12 work orders: eight company jobs and four provider jobs, with scheduled,
  active, waiting, review and completed examples.
- Three component service plans using the existing Ellicott PM checklists.
- Four faults, seven meter-log entries and eight job handovers.
- Five reports, two draft invoices calculated through the app billing RPC, three
  job part entries and eight stock/catalog items, including out-of-stock stock.
- Four inspection requirements with actual sample-document attachments. Three
  approved sample renewals show current, near-expiry and expired states; one is
  awaiting review. Attachments explicitly state that no inspection is certified.
- Four custody/site records and one completed maintenance checklist record.
- A company-specific demo pre-op checklist copied from the existing Ellicott
  checklist and assigned to the company operator. The original template used a
  different asset category, so a scoped copy was necessary for valid assignment.
- Two service requests, plus application-generated history and operation rows.

No messages, invoices or payments were sent. No new application code, APK,
Supabase migration, original-repository change or original-service access was
required.

## Demo route

Reopen the app with an owner or the Paradise company manager account. Start
with Ellicott 460SL, then Planning, company Work orders, Fleet inspections,
service reports, inventory and invoices. Company mechanic work is assigned to
the existing company mechanic account. The pre-op assignment uses the existing
`client_operator@vortice.dev` account. The other client company remains separate.

## Verification and preservation

The initial database transaction was validated with rollback before applying.
Snapshot comparison retained all 168 pre-existing rows in the 29 checked tables;
only the intended dredge fields, its two component meters and two legacy fault
labels changed. Revision counters advanced on modified existing records. No
labour timers remain running. The connected Flutter audit passed 130 routes
across six roles in English/light mode, with no framework/provider/visible error
failures. Planning and inspection screens were visually reviewed. This is not
physical-device acceptance; it does not prove every new record's full lifecycle.

Ignored local evidence is in `outputs/demo-2026-09-07/`: before/after snapshots,
exact-ID manifest, verification counts, inspection upload receipt, sample
attachment and route audit/screenshots. One-time preparation scripts are saved
there for traceability; they are not a general-purpose seed command. Do not rerun
them or broadly remove demo-prefixed data. A future rollback must use the exact
saved IDs and restore changed fields only after checking for intervening edits.

## Manual-backed follow-up

Garrett identified the WSL maintenance-documents library. The matching unit is
`/home/garrett/.openclaw/workspace/maintenance-docs/units/paradise-marina-dredge-pv-001/`.
Its `maintenance-manual/` contains 140 original page photographs, OCR sidecars and
a C15 PDF. Original photographs were checked visually; the OCR was too noisy to
use alone. Source files were read without changing the library or its hardlinks.

Three original photographs were imported into the company's Maintenance
documents, with uploaded bytes checked against their local SHA-256 hashes:

| App page | Source photograph | Verified information |
| --- | --- | --- |
| 1 | `PXL_20260408_015131353.jpg` | Ellicott 460SL manual cover; S/N `0007-16-502280/1124` |
| 2 | `PXL_20260408_015242230.jpg` | Section I p.2: non-propelled pipeline dredge, spud carriage, swinging ladder, in-hull pump and CAT C15-driven open-loop hydraulics |
| 3 | `PXL_20260408_032606806.jpg` | Section III, Tab 4 p.2: grease cylinder trunnion mountings, ladder trunnions and gimbal thrust washers every 10 hours or daily |

The previously empty dredge serial field and its reference notes now contain
those verified details. A ladder/gimbal component, published two-step company
checklist, 10-hour-or-daily service plan and assigned demo work order were added
through the existing workflow. The total is now 13 demo work orders. The new
component's 7,242-hour meter and 7,240-hour service baseline remain explicitly
synthetic. The app's interval trigger is hour-based; the daily requirement is
retained in the label/instructions and the example job is due September 8.

The saved C15 PDF is SEBU7902 for **JRE1-Up**, while the existing engine serial is
**MCW10441**. Its capacities and engine-specific intervals were not applied.
Existing 250/500/1000-hour demo plans still use the pre-existing checklists; this
follow-up does not newly certify those checklists against an MCW engine manual.

The enrichment transaction passed rollback validation before application. Four
focused rendered company-manager checks passed for the new job, component/plan,
published checklist and source-document library. Job and document screens were
visually checked. Evidence: `manual-before.json`, `manual-receipt.json`,
`manual-apply.json`, `manual-ui.log`, `NOW-010-manual-demo.json`, and screenshots
in the same local demo output directory. Only three relevant source pages were
imported; this is not a bulk import of the entire library.
