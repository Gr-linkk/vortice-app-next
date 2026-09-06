# 0007: Explicit custody and versioned inspection renewals

Status: Accepted
Date: 2026-09-06
Scope: NOW-009, delegated feature selection and implementation

Custody records a company member, site and lifecycle independently of operational
availability. Every transfer requires a reason and preserves old/new values,
actor and server timestamp. Once custody exists, older location-editing paths
must use the transfer workflow; the database rejects bypasses. Lifecycle does not
silently delete an asset or change whether maintenance work can proceed.

Inspection requirements belong to an asset and optionally one of its components.
Each renewal preserves its procedure reference, results, civil inspection/expiry
dates, uploader and private evidence. Only a manager's reviewed approval becomes
the effective certificate. Returned and superseded submissions remain readable;
a pending renewal never masks an expired certificate. Expiry includes the named
day; the upcoming window is 30 calendar days. This register records inspection
facts and review, not a legal compliance determination or permission to operate.

Asset readers may read custody and inspection history. Managers transfer and
create requirements; managers/mechanics/provider staff with existing asset
access submit renewals. Operators read only. Managers approve or return with a
reason. Reuse existing company boundaries, including the established provider
access model; restrict responsible-person selection to the asset's company.

Checked transactional RPCs own writes, with idempotent operation IDs and stale
revision detection. Evidence is private and immutable after submission. Storage
allows only the uploader to remove unused uploads. Retry uncertain writes with
the same frozen payload; account changes require reopening an unfinished form.

This slice requires connectivity. Offline queues, scheduled push delivery,
qualification/permit rules, GPS and legal compliance automation remain outside
the accepted implementation. Existing asset-history export includes the transfer
and inspection event trail and links back to the full inspection versions.
