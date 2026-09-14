# NEXT-010 — Canadian dollar support

Requested September 14, 2026: add CAD alongside USD/MXN and check calculations.

## Contract

- USD remains the accounting base for charges and reports. CAD and MXN are
  equivalent valuations of the same invoice, not three separate amounts owed.
- Store CAD per USD (six decimals) and total CAD (two decimals). Existing MXN
  precision is unchanged. Convert the rounded USD invoice total exactly once.
- Fetch both rates from the same USD response. Reject invalid rates. The
  organization charge form shows fetched values for review; if unavailable,
  require explicit positive rates instead of assuming parity.
- Server calculates totals atomically, preserves the chosen tax percentage,
  and freezes CAD with all other issued fields. Retries retain original rates.
- Existing issued invoices are not backfilled. Missing CAD is shown as unavailable.
  Legacy drafts can acquire CAD through Refresh exchange rate.
- USD/MXN/CAD selector, line items, summary, work-order totals, list and exports
  use the saved valuation. PDF retains its existing USD line table and includes
  all three totals; XLSX includes a CAD column alongside USD/MXN.
- Field Notes styling, company-purpose permissions and Work order vocabulary stay.
- CAD support does not select GST/HST/PST rules or a new invoice issuer identity.

## Verification

- Red/green database test first failed because the CAD generation interface did
  not exist, then passed with the migration.
- All 49 local SQL suites passed (`outputs/next010/database-all.log`). CAD
  contract covers cents/precision, retry preservation, invalid rates, draft
  charges/tax recalculation, refresh, issued protection, old-client compatibility
  and company isolation. Organization billing additionally proves CAD propagation,
  retry stability and refusal of the legacy generation bypass.
- Guarded verification passed: 788 Flutter tests and clean analysis
  (`outputs/next010/verify-final.log`). One additional focused form test passed:
  invalid CAD retains the entered labour/rates for correction. Final capture
  rerun passed all four invoice journeys after a test-only font-loading fix.
- Rendered normal path: invoice list -> invoice -> CAD -> summary -> MXN -> USD,
  390x844 with 1x/2x text, current and historical invoices. Saved totals are visible,
  large amounts wrap, and missing CAD never becomes a zero or parity amount.
  Fixture font rendering does not include emoji glyphs; phone flags remain a
  physical acceptance check. Captures: `outputs/next010/screens/`.
- Generated English/Spanish 90-part PDF/XLSX exports; decoded XLSX CAD headers,
  totals and rate; inspected PDF totals and pagination in both languages.
  Moved invoice identity into the PDF page footer to avoid an orphan footer page.
  Files: `outputs/next010/exports/`.
- Direct review traced generation, form validation, database triggers, frozen
  history, view, exports and update paths. Fixed client draft edits that tried to
  recompute tax at a hardcoded rate; server now owns all final calculations.
- Applied only `20260914120000_invoice_cad.sql` to verified Next ref
  `hkjpojobdbbtjkhaudki`. Hosted rollback contracts `invoice_cad`, `invoice_closeout`
  and `organization_provider_work` all passed. No historical invoice revaluation.

## Internal Build 40 and Garrett's next steps

Version `1.19.0+40`, existing isolated Android package and debug signer.
APK: `outputs/builds/INSTALL-Vortice-Next-Build-40.apk`.
SHA-256: `0531027d5b9747fe25c2643efe27316bccaf0cc7605b7b715b3d97fa4b609d50`.
Windows Downloads copy is prepared after package/certificate/Next-config checks.
No device was visible in either Windows or WSL ADB. No installation is claimed.

1. Transfer/install Build 40 while preserving app data. Open a draft with saved
   CAD (refresh a legacy draft if necessary), select CAD, and compare its total
   with PDF/Excel. Check an issued historical invoice remains unchanged.
2. Decide whether Rivetrail or another proposal fits the product; domain choice
   waits until Garrett is home. The app still uses its existing working name.
3. Before Canadian customer invoicing, select tax/issuer settings and the pilot
   scope from NEXT-009. This currency addition does not choose regional taxes.

Physical Android acceptance remains separate from automated/build evidence.
