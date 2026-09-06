# 0008: Account-owned field work and independent delivery

Status: Accepted
Date: 2026-09-06
Scope: NOW-011, Garrett's six post-audit recommendations.

This supersedes the connectivity limitation in decision 0005. Mechanic execution
and operator checklists persist immutable operations and photo bytes in an
account-owned SQLite queue before attempting network delivery. Account switches
dispose the previous queue; every request captures that account's authorization.
Unattributed legacy databases remain on disk without being opened as another
account's data. Cached reads fall back only for connection failures, never for
server permission denials. Offline preparation and per-record draft keys also
belong to the signed-in account.

Maintenance field actions retain revision checks and device-recorded labour
times. Scheduling, assignment and approval remain online. Rejected submissions
keep their data visible; archiving a rejected record restores report/checklist
input for correction without silently replaying rejected changes. Photo retries
accept only authenticated byte-identical objects. Foreground/resume retries are
explicit; the app does not promise operating-system background data uploads.

Operator run, answers and saved history commit in one server transaction after
all evidence exists. Immutable IDs make identical retries harmless. Old builds
cannot use direct partial operator writes after the approved migration.
Request, operator and maintenance evidence is private and access checked against
the associated company, request, asset or job.

Android notifications use the separate Firebase project `vortice-next` and a
service account with only `cloudmessaging.messages.create`. Device registrations
are account-scoped; server-selected recipients and generic lock-screen messages
avoid disclosing job content. The authenticated Next worker runs every minute,
with database leases, retries and invalid-token cleanup. Provider acceptance and
physical phone delivery are different evidence levels.

Recovery uses Next Supabase Auth and the app callback
`com.vortice.next://auth/recovery`. Production customer email delivery requires
an approved sending domain and SMTP provider. No domain has been selected;
default Supabase email limitations must remain visible in release readiness.

The internal application ID remains `com.example.vortice_app_next`; store
identity, production signing and a main-branch merge are separate decisions.
