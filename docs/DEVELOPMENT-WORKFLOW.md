# Development Workflow

## Start a task

1. Read `AGENTS.md`; verify root, remotes, branch, and working tree before mutations.
2. Load product/backlog/decision documents only as needed for the requested scope.
3. Continue an authorized existing task on its verified branch, preserving unrelated work.
4. For independent new work, agree the base and use a short-lived `codex/` branch. Update `main` only when needed and safe; do not pull or switch merely for startup.
5. Give substantive implementation work a backlog ID and outcome. Narrow mechanical fixes do not require a new ticket.

## Work locally

Run setup once, or whenever dependencies change:

```powershell
./scripts/setup.cmd
```

Run the app against the dedicated backend:

```powershell
./scripts/run.cmd
```

The run helper validates the repository identity and local Supabase target
before invoking Flutter. Extra Flutter arguments may be passed through, for
example `./scripts/run.cmd --device-id=windows`.

An isolated worktree may select an existing Next configuration through the
`VORTICE_NEXT_CONFIG` environment variable. The helper validates the selected
file's exact Next URL and translates its path for WSL; this avoids copying local
credentials. Omit the variable to use the checkout's usual ignored config file.
Use `--device-id=web-server` for browser checks; PowerShell can interpret `-d`
as its own Debug option.

Use `work/` for throwaway analysis, exports, and scripts. Use `outputs/` for
durable local deliverables that should not enter Git. Put reusable findings in
tracked docs instead of leaving them in either directory.

## Verify and review

Run the same verification entry point used by CI:

```powershell
./scripts/verify.cmd
```

For pull-request migration immutability checks, provide the base ref:

```powershell
./scripts/verify.cmd -BaseRef origin/main
```

For local-only work or review, finish with checks appropriate to the change.
Before opening a requested pull request, run the full verification entry point
above and use the repository template. The PR should identify its
backlog item, observable behavior, tests, screenshots for UI changes, service
targets, and intentionally deferred work.

## Database changes

Follow `supabase/README.md`. Setup, verification, app run, and Android build
scripts never deploy or mutate a remote database. A remote migration requires
the dedicated deployment helper and its explicit project-ref argument.

## Finish

Finish the authorized scope with its results and remaining limits. Opening a
pull request, merging it, and deleting a branch are distinct actions; perform
them only within the user-authorized scope. Update affected backlog and durable
decision/specification records when the substantive change requires it.
