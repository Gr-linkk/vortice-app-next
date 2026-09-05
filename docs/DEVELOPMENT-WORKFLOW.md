# Development Workflow

## Start a task

1. Read `AGENTS.md`, `PROJECT.md`, and `BACKLOG.md`.
2. Select one backlog item and confirm its outcome.
3. Update local `main` with a fast-forward pull.
4. Create a short-lived branch such as `feat/NOW-002-checklist-flow`.
5. Read only the current decisions and specifications linked to that scope.

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
example `./scripts/run.cmd -d windows`.

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

Open a pull request using the repository template. The PR should identify its
backlog item, observable behavior, tests, screenshots for UI changes, service
targets, and intentionally deferred work.

## Database changes

Follow `supabase/README.md`. Setup, verification, app run, and Android build
scripts never deploy or mutate a remote database. A remote migration requires
the dedicated deployment helper and its explicit project-ref argument.

## Finish

After CI passes and the PR is merged, delete the feature branch. Update the
backlog and any affected decision/specification in the same change so the next
task starts from current information.
