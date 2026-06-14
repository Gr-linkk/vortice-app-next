# Vortice Mechanical App

Flutter/Supabase app for Vortice Mechanical's marine and heavy-equipment service workflows.

The app is asset-first: assets are the hub for work orders, service reports, maintenance checklists, operations checklists, telemetry, client history, and invoices.

## Current Scope

- Client and internal role-based access
- Client org/team access for customer staff
- Assets, engines, telemetry summaries, and asset history
- Service requests and work orders
- Staff maintenance checklists and operator checklists
- Saved checklist history
- Service reports
- Invoice generation, review, PDF/Excel export, and payment status tracking

## Local Development

Recommended workspace path on Garrett's WSL machine:

```bash
/home/garrett/projects/vortice-app-main
```

From Windows Android Studio, open the WSL project path:

```text
\\wsl.localhost\Ubuntu\home\garrett\projects\vortice-app-main
```

Install dependencies:

```bash
flutter pub get
```

Run analyzer and tests:

```bash
flutter analyze
flutter test
```

Build a debug APK:

```bash
flutter build apk --debug
```

Install to a connected Android device from WSL using the Windows Android SDK:

```bash
/mnt/c/Users/Garrett/AppData/Local/Android/Sdk/platform-tools/adb.exe install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Useful Docs

- [CONTEXT.md](CONTEXT.md) - current client org/access language and rules.
- [Workflow architecture notes](docs/WORKFLOW-ARCHITECTURE-NOTES-2026-05-08.md) - workflow seams and asset-first direction.
- [Client org access model](docs/CLIENT-ORG-ACCESS-MODEL-2026-05-08.md) - how client teams inherit fleet access.
- [Developer review prep plan](docs/DEVELOPER-REVIEW-PREP-PLAN-2026-05-13.md) - manual review checklist across app workflows.
- [Service report flow spec](docs/SERVICE-REPORT-FLOW-SPEC-2026-05-12.md) - service report workflow decisions.
- [Checklist workflow spec](docs/CHECKLIST-WORKFLOW-SPEC-2026-05-07.md) - checklist workflow decisions.

`NEXT.md` contains older session handoff notes. Treat it as historical context, not the canonical startup document.

Archived build specs under `archives/` are reference material unless they are explicitly promoted back into current docs.

## Contribution Flow

Use short-lived branches from `main`:

```bash
git switch main
git pull --ff-only
git switch -c <type>/<short-description>
```

Keep commits focused and reviewable. Open a PR rather than pushing directly to `main`.

PRs should include:

- Summary of user-facing behavior changes
- Tests or checks run
- Device/build verification when Android behavior changed
- Known follow-up items or scope intentionally left out

Common verification set:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

## Guardrails

- UI role gates are not security. Supabase RLS/policies must enforce client data boundaries.
- Client org users inherit access through their org owner's fleet; avoid ad-hoc per-screen asset queries.
- Saved checklist history is intended to be immutable app history.
- Do not mix telemetry collector/Pi runtime work into app workflow patches unless explicitly scoped.
- Do not treat archived docs or old session notes as current truth without checking the active specs.

## Current Follow-Ups

- Audit invoice RLS/data scope before real client invoice data is used.
- Continue tightening workflow specs as work orders, service reports, invoices, and client visibility settle.
- Keep README/current docs in sync with branch/PR workflow changes.
