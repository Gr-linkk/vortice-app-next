# Database contract checks

`faults_and_availability.sql` exercises scoped reads, denied direct writes,
role transitions, stale versions, idempotent retries, work-order linkage and
downtime. `signup_role_boundary.sql` exercises forged signup metadata and
invitation role, expiry, usage and capability checks. Each rolls back its fixtures.

`company_maintenance.sql` covers internal execution and costs, supervisor return
and approval, isolated evidence, exact component/plan advancement, immutable
history, retry and revision handling, provider execution and company capability
gates. Company administrator asset creation is scoped to its company owner.

Validated with PostgreSQL 17 in an isolated disposable container with no ports,
network or host volumes. `local_bootstrap.sql` supplies minimal Supabase auth and
storage objects for loading the complete baseline; it is test scaffolding, not
a hosted migration or a full local Supabase environment.

For an empty isolated test database, load `local_bootstrap.sql`, then the migration
files in filename order with psql `ON_ERROR_STOP=1`. Set `check_function_bodies`
back to `on` after the inherited baseline. Run all contract files as postgres
with `ON_ERROR_STOP=1`. Assertions switch database roles and JWT claims to test
the application access boundaries. Do not run the bootstrap against a real service.

These checks do not prove HTTP Auth/PostgREST behavior or replace device testing.

`bash scripts/test-database.sh --restore-drill` additionally commits the existing
invoice scenario in the disposable source database after all contracts pass,
exports a PostgreSQL custom archive and restores it to a second database in the
same isolated container. It verifies frozen invoice/correction history and
customer/other-company access after restore. This runs in CI. It is not a
hosted Supabase or uploaded-file recovery drill; those remain release gates.

From this checkout, `bash scripts/test-database.sh` automates the isolated run.
It verifies the repository identity, uses an existing `postgres:17` Docker image,
loads all migrations, runs all contracts, and removes only its disposable
container on exit. On Windows, invoke it through WSL with this checkout as cwd.
