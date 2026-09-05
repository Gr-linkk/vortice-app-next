# Supabase Workflow

The only authorized hosted target is Vortice Next, project ref
`hkjpojobdbbtjkhaudki`.

## Migration layout

- `migrations/` — the deployable chain, beginning with the verified baseline.
- `migrations_legacy/` — inherited incremental files retained as reference.
- `../supabase-migrations/` — historical/manual SQL retained as reference.
- `../seed/` — reviewed mock fixtures when fixtures are added.

Create each schema change as a new file named
`YYYYMMDDHHMMSS_short_description.sql`. Never edit, rename, or delete a migration
after it has been deployed.

## Validation

`scripts/verify.ps1` validates naming, ordering, immutable migration history
when a base ref is provided, repository identity, ignored local material, and
credential patterns. It does not connect to or mutate Supabase.

This repository does not currently define or promise a Docker-based local
Supabase stack. There is intentionally no `supabase/config.toml`; use the hosted
independent project only through explicit, guarded commands until local-stack
support is deliberately added.

## Hosted deployment

Linking and deployment are separate from normal app setup. Before deployment,
the linked ref in `supabase/.temp/project-ref` must exist and exactly match the
authorized project. Run:

```bash
./scripts/supabase-push.sh --project-ref hkjpojobdbbtjkhaudki
```

The helper rejects missing or different explicit and linked refs before calling
`supabase db push --linked`. Review the SQL and backup/rollback expectations
before invoking it; the helper is a guard, not an approval mechanism.

The checklist seeder in `scripts/seed-checklists.js` is a manual fixture tool,
not part of setup or migrations. It requires the exact Vortice Next host, an
explicit owner ID, an in-repository fixture directory, a service-role key in the
process environment, and the `--confirm-vortice-next` argument.
