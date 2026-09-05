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

- Work from short-lived branches based on this repository's `main` branch.
- Keep the original repository's history and contributor attribution intact.
- Record any intentional transfer between projects in the commit or pull
  request that performs it.
