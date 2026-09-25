# NEXT-011: Canadian company money and provider invoicing

Selected September 24, 2026. The first target is a general construction company
in Canada. The province and actual company are not yet selected. This scope
extends NEXT-010; its saved CAD valuation of a USD invoice is not itself a
Canadian invoice.

## Product contract

- A Fleet owner manages its own equipment and costs. It does not need a
  customer-invoice action. Service provider and Both keep own-equipment work and
  may invoice approved customer work when Billing permission is present.
- New Canadian company money entry and reporting must identify CAD as the
  amount's currency. Do not silently relabel historical USD figures as CAD.
- A Canadian provider invoice bills in CAD. The company supplies its issuer
  identity and registration details; the customer, work, amount, tax lines,
  currency, dates and payment terms are recorded and frozen on issue.
- Province, supply type, registration status and taxability affect Canadian tax.
  The app must not infer the applicable tax solely from the issuer's address.
  Until a province and reviewed rules are selected, make treatment explicit and
  editable, with no invented default. Preserve each line's rate, taxable base,
  calculated amount and the reviewed reason for zero tax.
- Historical USD/MXN/CAD invoices retain their saved amounts and export
  snapshots. Avoid changing an issued document's identity or recalculating it
  against current company settings.
- Customer work stays behind the existing relationship and Billing permissions;
  internal costs and private drafts do not become customer-visible.

## Current findings

- Build 40 stores CAD as a valuation of USD and uses a single `iva_pct` field.
  The modern provider form asks for USD charges and one unlabeled tax percentage.
- The PDF/XLSX issuer is hard-coded as Vortice Mechanical in Mexico. This is
  unsuitable for another company's Canadian invoice.
- Parts, labour and equipment reports show USD in several own-equipment paths.
  Their stored values need a currency contract before a Canadian company enters
  costs. A label-only conversion would misstate historical values.

## September 24 implementation and verification receipt

- On `codex/canada-play-readiness`, the new
  `20260924100000_company_billing_purpose.sql` migration rejects enabling
  provider work or customer billing for Fleet owner. It turns billing off when
  an owner changes a company to Fleet owner, and rejects new or first-issued
  customer invoices for that purpose. Existing issued history stays intact. Company services hides
  the billing switch for a Fleet owner and explains customer billing only to
  providers.
- The migration and changed contracts parsed with PostgreSQL syntax tools.
  All 64 current migrations and all 49 local SQL contracts then passed on an
  isolated, Unix-socket-only PostgreSQL 18.6 instance in ignored `work/`.
  The affected `company_purpose` and `organization_provider_work` contracts
  explicitly cover the new fleet boundary and old issued invoice retention.
  The disposable server was stopped. The authorized hosted Next target has
  **not** received this migration; hosted checks are still required.
- Targeted Flutter analysis and purpose tests pass. The Company services screen
  was rendered at 320×844 with 200% text for Fleet owner and Service provider.
  Fleet showed its company code and connection path without a billing switch;
  Service provider showed the customer-billing switch and explanation without
  clipped text. Local captures are under ignored
  `outputs/next011/rendered/`. Flutter test rendering uses substitute icon
  glyphs; real Android icons and touch still require phone acceptance. No new
  APK or customer invoice was delivered.
- Native CAD company costs, issuer profile, explicit Canadian tax lines,
  frozen Canadian invoice totals, PDF/XLSX and customer acceptance remain open.

## Completion evidence required

1. Canadian company cost entry, stock, work and equipment reporting show the
   correct currency; mixed historical data is identified rather than converted
   silently. Ordinary fleet-owner and provider paths are checked at phone size
   and large text.
2. Canadian provider charges, tax lines, frozen issuer/customer snapshots,
   rounding, corrections, PDF/XLSX and the customer's permitted view agree.
3. Database contracts cover cross-company access, Billing permission, fleet
   owner boundary, retries, invalid tax/rate inputs, old invoices and freeze on
   issue. Relevant hosted contracts pass on the authorized Next target.
4. A real Canadian issuer/province/tax case receives owner and qualified tax
   review before a customer relies on an invoice. Physical phone acceptance is
   recorded separately from automated and rendered checks.

## Source references

- [CRA GST/HST rates and place-of-supply rules](https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/charge-collect-place-supply.html)
- [CRA invoice information for input-tax-credit support](https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/calculate-prepare-report/input-tax-credit.html)

These references inform the implementation; they do not select a company's tax
registration, a transaction's place of supply, or provincial tax treatment.
