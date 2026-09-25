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

On Linux, use the same PowerShell implementation directly:

```sh
pwsh -NoProfile -File scripts/setup.ps1
pwsh -NoProfile -File scripts/run.ps1 --device-id=web-server
pwsh -NoProfile -File scripts/verify.ps1
VORTICE_NEXT_FIREBASE_CONFIG="$PWD/config/vortice-next-firebase.local.json" bash scripts/build-android.sh
```

The current working checkout is `/home/garrett/projects/vortice-app-next`;
the Documents copy is reference-only. The September 24 Linux setup has Flutter
3.44.0/Dart 3.12.0, JDK 17, Android SDK 36, accepted SDK licences, ADB and browser
tooling. PowerShell 7.6.6 and Supabase CLI 2.117.0 are user-local installations
under `~/.local/share/vortice-tools/`, exposed through `~/.local/bin/`. Their
official release archives were SHA-256 checked before extraction. Installation
does not authenticate GitHub or Supabase: use `gh auth login` and
`supabase login --agent no --output-format text` interactively. Never put access
tokens, passwords or signing keys into tracked files or chat.

The app's Next client configuration is present. The four public Firebase client
defines were recovered from the installed independent Next Build 39 APK and
validated against the exact Next project/app/sender IDs; they are in ignored
`config/vortice-next-firebase.local.json`. The matching **Next** debug key was
recovered read-only from the old WSL disk into ignored, owner-only
`config/vortice-next-debug.keystore`. Gradle uses this project-specific key and
checks the established certificate before Debug tasks. Missing or different keys
fail explicitly; the machine's global debug key is unchanged. An isolated
worktree can set `VORTICE_NEXT_DEBUG_KEYSTORE` to the recovered file's absolute
path. Preserve the key privately when moving machines; never commit it.
The S24 accepted an in-place Build 39 → 40 update with all 26 saved app files
unchanged before launch. Production signing remains separately blocked.
Successful compilation does not prove notification delivery. See NEXT-012's
key-recovery receipt and NEXT-009's Linux audit.

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

CI now runs all database contracts and a populated archive restore through
`bash scripts/test-database.sh --restore-drill`, in addition to the Work hub
performance check. The restore stays inside a network-disabled disposable
PostgreSQL container. It does not restore hosted Supabase or Storage objects.

Linux without Docker access can explicitly select an isolated native runner:

```sh
export VORTICE_TEST_DATABASE_BACKEND=local
export VORTICE_PG_BIN="$HOME/.local/share/vortice-tools/postgresql/18.6/bin"
bash scripts/test-database.sh --restore-drill
bash scripts/check-work-hub-performance.sh
```

`VORTICE_PG_BIN` must contain `postgres`, `initdb` and `pg_ctl`; compatible
`psql`, `pg_dump`, `pg_restore` and `createdb` must be on PATH. The current
machine has the extracted PostgreSQL/numactl libraries in the user-local prefix
above. The runner creates a fresh cluster under ignored `work/`, uses a private
Unix socket, disables TCP, overrides connection environment variables and stops
the server on exit. Failed clusters/logs remain for diagnosis; successful runs
remove their disposable files. Docker remains the default for CI, on PostgreSQL
17; the Linux fallback was checked on PostgreSQL 18.6. Neither substitutes for
hosted Supabase Auth, Storage, email or device acceptance.

For one-shot hosted operational checks and local backup staging, see
`docs/operations/PRODUCTION-RUNBOOK.md`. These do not schedule jobs or send alerts.

For Work hub/query changes, run `bash scripts/check-work-hub-performance.sh`
through the configured WSL shell on Windows. This checks 340 assets, 1,500 jobs
and 340 plans in a disposable, network-disabled PostgreSQL container with the
full migration chain. It asserts four role scopes, three timing samples per
scope, a 3-second query budget and bounded overhead for an unrelated company.
The same check runs in CI. It needs Docker, not hosted credentials; it does not
measure phone rendering or network latency. The pre-cache query fails the
isolation-overhead check while the current query passes.

Follow `supabase/README.md`. Setup, verification, app run, and Android build
scripts never deploy or mutate a remote database. A remote migration requires
the dedicated deployment helper and its explicit project-ref argument.

## Finish

Finish the authorized scope with its results and remaining limits. Opening a
pull request, merging it, and deleting a branch are distinct actions; perform
them only within the user-authorized scope. Update affected backlog and durable
decision/specification records when the substantive change requires it.
