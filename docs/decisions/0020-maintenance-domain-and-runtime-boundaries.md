# 0020 — Maintenance domain and runtime boundaries

- Status: Accepted for ARCH-001 cleanup; local-first cutover remains unselected
- Date: 2026-09-29
- Backlog: ARCH-001
- Extends: 0016 and 0018; does not reverse their access or company-purpose rules

## Context

Garrett wants the bulk of the architecture audit addressed, but explicitly
excludes cleanup that the concurrent local-first change would make pointless.
The retained Build 45 app and the Build 40-derived Sync Lab have different
runtime responsibilities. Rebuilding hosted infrastructure now would compete
with the experiment while leaving the useful maintenance behavior entangled.

## Decision

Keep maintenance rules in a small pure-Dart `lib/domain/` boundary, with no
Flutter, backend, plugin or storage dependency. Existing internal/provider
paths share report readiness and checklist rules. Use an immutable report
command for exact retries. Keep work-specific persistence and transport in
small adapters/controllers; widgets own presentation, input and navigation.

Contain the hosted member-to-legacy-route mapping in a named adapter. Keep
working-role capability policy independent of that mapping. Do not replace
server authorization or introduce a new device/person role system here.

Use Flutter ink capture instead of the isolated Syncfusion dependency. Add no
replacement package. Preserve existing signature bytes and upload contracts.
License selection and inherited rights remain separate from dependency removal.

Defer hosted SQL/Auth/delivery redesign because the target intends to retire
those implementations. Preserve them, their history and behavior contracts;
continue fixing concrete defects. Do not delete deferred product workflows.

## Consequences

The important maintenance rules can run without an app engine or credentials,
and have one reusable home for the next workflow migration. The retained app
continues to work; tests cover its account isolation and retry guarantees.
This adds neither a universal repository framework nor a new workflow engine.

The lab remains an isolated experiment. Its owner-OS/device model does not
fulfil multi-worker or cross-company authorization. A subsequent complete
workflow migration must select one write authority, preserve history, rehearse
import/rollback and retire the old path explicitly. The first local-first
workflow and its limits are mapped in [the architecture guide](../ARCHITECTURE.md).
