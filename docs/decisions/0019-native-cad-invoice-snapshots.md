# 0019: Native CAD invoice snapshots

- Status: Accepted implementation of the NEXT-011 contract
- Date: 2026-09-25
- Extends: NEXT-010 currency valuation and decision 0018 company purpose

New Canadian provider invoices use a separate CAD billing snapshot and
`billing_currency=CAD`. USD/MXN accounting fields remain absent for these
invoices. Existing invoices default to USD and retain their prior saved
valuations, tax field and export snapshots. A currency label never converts
stored money.

The server validates and calculates a whitelisted snapshot: issuer legal/trading
name, address, contact and registration status/numbers; customer name/address;
supplied work and province; explicit reviewed tax treatment and reason; each tax
name/rate/base/rounded amount; labour/parts/subtotal/total; dates/payment terms
and reviewer. No default tax or jurisdiction is inferred. Registration and a
real transaction still require qualified review before customer reliance.

Company Owner manages the issuer profile. The existing provider Billing
permission and company capability control invoice generation, editing and
issue. Draft generation retries return the same invoice. Draft revisions
recalculate on the server. Issue freezes saved details; later company edits do
not rewrite history. Void and replacement preserve the earlier invoice.

Phone, PDF and XLSX share the saved snapshot. Exports re-read through the same
RLS boundary, and issued void history remains readable to its customer.
Canadian invoices do not use the legacy hard-coded Mexico issuer. This decision
does not select a first province, business registration, tax rate, production
identity or domain, and does not authorize customer charges.

## Internal costs and stock

`20260925020000_company_cost_currencies.sql` records CAD or USD on work orders,
stock and used parts. Existing rows retain USD. New company settings default to
CAD; Company Owner can select the currency for future costs. Modern forms send
that choice explicitly. Old clients omitting it retain USD behavior; generated
recurring work reads the company setting. Saved record currencies cannot change.
Stock requirements and used parts must match their job currency.

Approved receipts and history save the same currency. Equipment reports keep
separate CAD and USD subtotals, with the original currency on each source and
CSV row. No exchange rate or mixed-currency grand total is inferred. The older
numeric report fields remain USD for compatibility with older clients.

The issuer editor saves against the organization that opened it; the server
rejects a stale active-company change. Invoice inputs use server cent rounding,
and native totals are bounded to the stored amount's precision.
