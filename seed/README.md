# Seed Fixtures

Reviewed, repeatable mock fixtures belong here, separate from schema migrations.
Do not store exports, credentials, production data, or one-time transfer files in
this directory.

Checklist JSON fixtures used by `scripts/seed-checklists.js` belong under
`seed/checklists/`. The seeder is manual and intentionally excluded from setup,
verification, migrations, and CI.
