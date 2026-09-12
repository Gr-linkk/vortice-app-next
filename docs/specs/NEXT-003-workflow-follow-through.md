# NEXT-003 — Workflow polish and field verification

Authorized September 12, 2026, following internal Build 29. Continue on the
verified independent `codex/kanban-workflows` branch.

| Item | Outcome | Status |
| --- | --- | --- |
| 1 | New demo roles first, older profiles collapsed, current company/role clear | Implemented; picker tests pass, including 320 px at 200% text |
| 2 | Create, assign, perform, return, correct, approve and invoice one job | S24 connected and authorized; pending updated build |
| 3 | Provider evidence capture survives offline interruption and reopening | SQLite restart, retry and permission tests pass; S24 verification pending |
| 4 | Shared execution/evidence rules reduce drift between workflow paths | Shared report readiness and immutable evidence helpers implemented |
| 5 | Repeatable Work hub performance check with representative populated data | Local positive and historical regression probes pass; CI job added |

Provider work starts from its authorized work order and frozen procedure.
Answers, meter readings and captured photos stay account-owned on this device.
Server submission checks current permission/revision and retains retry identity.
Approval, billing, assignments and permission changes still require connectivity.
Use shared production helpers where contracts match; preserve workflow-specific
RPCs and private/customer report boundaries.

Acceptance includes native narrow/large-text account selection, offline evidence
reopen and retry, stale account/revoked access protection, complete saved job
transitions and repeatable populated performance checks. Keep automated Flutter,
hosted SQL, actual Android execution and human acceptance explicitly separate.

No account deletion, original-app changes, new chat product, email/SMS setup or
visual redesign is included. The Build 29 receipt remains historical evidence.

The offline restart test also exposed a scoped-read dependency race: observing
membership's intermediate loading state could invalidate the awaited provider
work context. Service reads now await resolved membership before fetching their
scoped context, retaining account and permission invalidation.

The first physical restart on Build 30 exposed a second delay that the local
server-stop test did not: service-detail enrichment had no request timeout.
Android could keep retrying after both networks were disabled, preventing the
Work list from reaching its existing cache. Each page now has the same six-second
read limit as other workspace reads. A stalled-transport regression verifies
that the warmed asset, component and worker details return within 15 seconds.
This correction is packaged as Build 31; Build 30 remains an intermediate receipt.

Build 31's repeated phone test exposed another refresh dependency: every photo
outbox update restarted hosted Work hub and service enrichment reads. Build 32
separates cached/server planning from the local operation projection. A widget
regression first reproduced the extra fetch, then verified repeated photo retries
keep Work readable, local work actions still update progress, and explicit
Refresh still fetches current server data. Physical Build 32 acceptance follows.

The performance fixture contains 340 assets, 1,500 jobs and 340 plans. It checks
three samples for four roles under forced generic query plans, a 3-second ceiling
and a same-machine isolation budget. Current medians were about 471 ms for the
provider owner, 491 ms for the fleet owner, 419 ms for the assigned mechanic and
72 ms for an unrelated company. Reinstating the historical slow function in the
disposable test database failed the isolation budget (760 ms versus 609 ms).
This is local repeatable regression evidence, not hosted load or remote CI proof.
