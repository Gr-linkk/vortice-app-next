# NOW-009: Custody and inspection renewals

## Selected outcome

Original continuation areas 19 and 20 form one everyday equipment-readiness
workflow: locate the asset and its responsible person, then check whether its
inspection is current before planning work. Preserve existing screens and style.

## Rules and acceptance

Custody is an explicit manager action from the asset: site, responsible company
member, lifecycle (active, stored, retired) and a required reason. Capture old
and new values, actor and server time. Update the existing location display in
the same transaction. Never implicitly change operational availability. Other
company members cannot be selected; mechanics/operators read but cannot transfer.
Retirement records state; it does not delete assets or historical maintenance.

An inspection register contains named asset/component requirements. A manager
creates a requirement; company managers/mechanics and provider staff with asset
access may submit a renewal with inspection date, expiry date, procedure and
result notes plus photo evidence. A manager approves or returns with a reason.
Only approval replaces the effective certificate. Keep all submitted versions,
review results and evidence, including rejected versions. A pending renewal never
hides an expired approved certificate. Dates are civil dates; expiry includes its
listed day. Upcoming means expiry within 30 days, expired means before today.
An item without approval is unverified. These are recorded inspection facts,
not a claim of legal compliance or automated permission to operate equipment.

Every write is transactional with a stable operation ID and revision check.
Retry the same frozen payload after uncertain responses. RLS and checked RPCs
enforce asset access; private evidence requires the same access. Account changes
invalidate queries. Show loading, retryable errors, empty states and saved data.
Online writes are required; offline queues and scheduled push alerts are out of
scope. Preserve input after failures and guard navigation away from dirty forms.

Observable acceptance: transfer and reopen the asset; submit a dated inspection
with evidence, reopen it, return and resubmit, approve and check the register;
renew again without losing prior evidence. Check expiry boundaries, stale writes,
duplicate retries, role restrictions and cross-company rows/media. Exercise the
actual connected UI using marked E2E-009 records and remove those records/objects.
Supplement with SQL contracts, Flutter interactions and narrow EN/ES renders.

## Delivery

Use only `hkjpojobdbbtjkhaudki`. Additive migration only. Baseline is Build 11's
`655f96b`, explicitly authorized ahead of main. Internal Android `1.5.0+12`;
verify package, signature, architecture and phone-copy SHA-256. Device installation
and physical interaction are distinct from automated or browser coverage.

## Verified implementation — 2026-09-06

Both features are implemented in the native app, its asset history and a fleet
inspection register. The two additive migrations are active only on Next.
The older asset-location editing paths now direct users to custody transfers;
a database guard also rejects attempts to bypass their history.

Guarded verification completed with clean analysis, 388 passing tests and 204
existing skips. All six hosted SQL suites passed. The new contract verifies
transactional persistence, duplicate retries, stale changes, role restrictions,
company/media isolation, retained versions and the location-bypass guard.
English and Spanish forms/registers rendered at 320 logical pixels and 150%
text scale without layout exceptions.

A connected native Flutter harness exercised the actual screens, authentication,
repositories, database and private Storage: save/reopen a transfer and inspection
requirement; mechanic submission with byte-verified image; manager return;
mechanic correction/resubmission; approval; a further renewal that retains the
effective certificate until approval; operator read-only access; and denial of
another company's register, direct asset link and image. Only photo selection
used an injected synthetic file. All five marked fixture assets and four uploaded
images (including earlier harness attempts) were removed; unrelated asset,
inspection and work counts were preserved.

Review corrected legacy location bypass, photo replacement operation IDs,
post-upload account-change protection and calendar-day expiry calculations.
Browser automation did not complete login because the browser was locked by
another extension; no browser-workflow coverage is claimed. Physical Android
installation, photo picker and touch interaction remain for device review.
Writes require connectivity; this slice does not schedule notifications.

Build `1.5.0+12` is delivered to Samsung Downloads as
`INSTALL-Vortice-Next-Build-12.apk`. Package `com.example.vortice_app_next`,
ARM64 Flutter engine and the existing internal signing certificate are verified.
The local APK and phone copy share SHA-256
`7d4fede1edf2c1d7ad78c392959f6c5e48d3d24dd9dd3b6d7eee0a16755e1352`.

Detailed local evidence: `outputs/NOW-009-verification.log`,
`outputs/NOW-009-hosted-contracts.log`, `outputs/NOW-009-live-workflows.log`,
`outputs/NOW-009-cleanup.json`, `outputs/screenshots/assurance/` and
`outputs/NOW-009-build-notes.md`.
