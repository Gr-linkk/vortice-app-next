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

## Manual-source gap

The specific Ellicott 460SL / C15 MCW manual was not located. Searched the local
Desktop service-document collections, Downloads, Documents, Nextcloud,
OpenClawTransfer and likely WSL document-library locations. `lifting dredg.zip`
contains four photographs, not manuals. Located CAT service PDFs include other
applications/serial families; those were not treated as authoritative for this
dredge. No new technical specifications or manufacturer intervals were invented.
Manual-based enrichment remains pending the exact source location.
