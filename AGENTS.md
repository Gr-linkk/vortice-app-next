# Independent Repository Guardrails

This checkout is the independent continuation of the Vortice application. It
was separated from `https://github.com/Gr-linkk/vortice-app` at commit
`7014867dbb20c2b67df6077128e509129eb0f9b0`.

## Repository identity

- Treat this repository and the original repository as unrelated working
  environments after the separation commit.
- Never edit, commit, push, open pull requests against, or change settings for
  the original repository unless Garrett explicitly names it and requests that
  exact action.
- Before every push or destructive Git operation, verify the repository root,
  current branch, and every configured remote.
- This checkout must have only its independent GitHub repository configured as
  `origin`. Do not add the original repository as `upstream` or another remote
  unless Garrett explicitly requests a one-time integration task.
- Do not automatically merge, rebase, cherry-pick, or copy changes between the
  repositories.

## Service isolation

- Never connect this checkout to the original Supabase project
  `REDACTED_SUPABASE_PROJECT`.
- The only authorized Supabase target for this checkout is `Vortice Next`,
  project ref `hkjpojobdbbtjkhaudki`.
- Before every Supabase deployment, verify that `supabase/.temp/project-ref`
  contains exactly `hkjpojobdbbtjkhaudki`. Stop if it is absent or different.
- The deployable migration chain starts with the reviewed current-schema
  baseline in `supabase/migrations/`. Older incomplete incremental migrations
  are reference-only files under `supabase/migrations_legacy/`.
- Require explicit `SUPABASE_URL` and `SUPABASE_ANON_KEY` build-time values.
- Keep Firebase projects, mobile application identifiers, signing material,
  deployment targets, secrets, and service accounts separate from the
  original application.
- Historical documents that mention the original repository or live services
  are reference material, not authorization to use those targets.

## Development

### Usability completion requirement

- Make routine work obvious. Apply this to every product change and release,
  not only to a dedicated usability pass. Use NEXT-006 in BACKLOG.md for the
  current cleanup scope.
- Use consistent user-facing names across entry points, lists, details and
  actions. Explain distinctions only where they affect a user's decision;
  database or billing terminology must not become unexplained navigation.
- Keep related checklists, findings, photos, parts and labour accessible from
  the equipment or job. Make the next action and its result clear, including
  what is still required to finish. Keep secondary actions secondary.
- Before delivering a build, walk through the affected ordinary workflow from
  its normal entry as a first-time user. Check real rendered screens, selection
  and completion at phone size and with large text. Record the path, findings,
  fixes and remaining limitations in the owning scope document. Passing code
  tests alone does not satisfy this requirement; distinguish rendered checks
  from physical phone acceptance.
- In the NEXT-006 round, prioritize small fixes to the existing workflow and
  preserve the Field Notes design. Defer new features and major redesigns.

- Continue an existing authorized task on its verified branch. For independent
  new work, use a short-lived `codex/` branch from the agreed current base; do not
  reset or switch an active checkout merely to satisfy a startup ritual.
- Keep the original repository's history and contributor attribution intact.
- Record any intentional transfer between projects in the commit or pull
  request that performs it.
- For product behavior changes, read `PROJECT.md`, the relevant `BACKLOG.md`
  item, and applicable current decisions/specifications. For narrow mechanical
  changes, read affected files and applicable guards; reuse current context.
- Treat `PROJECT.md` as the product and document-authority map, `BACKLOG.md` as
  the only live priority list, and `docs/decisions/` as the record of durable
  technical and product decisions. Dated plans and archived documents are
  inputs, not current authority.
- Use `scripts/verify.cmd` on Windows (or `verify.ps1` in CI) before opening a
  pull request. Use the guarded run,
  build, and Supabase helpers instead of reconstructing commands from old
  notes.
- Put disposable agent artifacts in ignored `work/`, durable local deliverables
  in ignored `outputs/`, local credentials in ignored `config/*.local.json`,
  and reusable project knowledge in tracked documentation.
