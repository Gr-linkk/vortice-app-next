#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd -P)"
test "$(git rev-parse --show-toplevel)" = "$root"
test "$(git remote)" = origin
for direction in fetch push; do
  remote_args=(remote get-url --all origin)
  if [ "$direction" = push ]; then remote_args=(remote get-url --push --all origin); fi
  urls="$(git "${remote_args[@]}")"
  test -n "$urls"
  while IFS= read -r url; do
    test "$url" = https://github.com/Gr-linkk/vortice-app-next.git
  done <<< "$urls"
done
restore_drill=false
if [ "${1:-}" = --restore-drill ]; then restore_drill=true; shift; fi
backend="${VORTICE_TEST_DATABASE_BACKEND:-docker}"
container="vortice-next-contract-$$"
if [ "$backend" = local ]; then
  # Explicit opt-in for Linux without Docker access. A fresh cluster, private
  # Unix socket and disabled TCP keep all contracts away from hosted databases.
  pg_bin="${VORTICE_PG_BIN:-$(dirname "$(command -v pg_ctl)")}"
  test -x "$pg_bin/pg_ctl"
  test -x "$pg_bin/initdb"
  # Also supports a user-local extracted PostgreSQL package and its libraries.
  export PATH="$pg_bin:$PATH"
  export LD_LIBRARY_PATH="$pg_bin/../lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  for command in psql pg_dump pg_restore createdb; do command -v "$command" >/dev/null; done
  mkdir -p work
  cluster="$(mktemp -d "$root/work/sql-contract-XXXXXXXX")"
  socket="$(mktemp -d /tmp/vortice-pg-XXXXXXXX)"
  cleanup() {
    "$pg_bin/pg_ctl" -D "$cluster/data" -m immediate -w stop >/dev/null 2>&1 || true
    rm -rf -- "$socket"
    # Keep diagnostics and the disposable cluster after failures for inspection.
    if [ "${completed:-false}" = true ]; then rm -rf -- "$cluster"; fi
  }
  trap cleanup EXIT
  "$pg_bin/initdb" -D "$cluster/data" -U postgres -A trust --no-locale -E UTF8 > "$cluster/init.log"
  "$pg_bin/pg_ctl" -D "$cluster/data" -l "$cluster/server.log" \
    -o "-k $socket -c listen_addresses='' -c unix_socket_permissions=0700" -w start >/dev/null
  local_pg() {
    env -u PGHOSTADDR -u PGSERVICE -u PGSERVICEFILE -u PGOPTIONS \
      PGHOST="$socket" PGPORT=5432 PGUSER=postgres PGDATABASE=postgres \
      PGOPTIONS='-c search_path=public,extensions' "$@"
  }
  sql() { local_pg psql -X --no-password -v ON_ERROR_STOP=1 "$@"; }
else
  test "$backend" = docker || { echo 'Use database backend docker or local.' >&2; exit 1; }
  trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
  docker run --rm -d --network none --name "$container" \
    -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17 >/dev/null
  for attempt in {1..30}; do
    if docker exec "$container" pg_isready -U postgres >/dev/null 2>&1; then break; fi
    sleep 1
  done
  sql() {
    docker exec -i -e PGOPTIONS='-c search_path=public,extensions' "$container" \
      psql -X -U postgres -v ON_ERROR_STOP=1 "$@"
  }
fi
run_sql() {
  sql < "$1" >/dev/null
}
run_sql supabase/tests/local_bootstrap.sql
upgrade=false
upgrade_reports=false
single_query=false
if [ "${1:-}" = --upgrade-coordination ]; then upgrade=true; shift; fi
if [ "${1:-}" = --upgrade-reports ]; then upgrade_reports=true; shift; fi
if [ "${1:-}" = --single-query ]; then single_query=true; shift; fi
run_contract() {
  if $single_query; then
    sql -c "$(cat "$1")" >/dev/null
  else
    run_sql "$1"
  fi
}
for migration in supabase/migrations/*.sql; do
  if $upgrade && [ "$(basename "$migration")" = 20260906040000_fleet_coordination.sql ]; then
    run_sql supabase/tests/fixtures/coordination_upgrade_seed.sql
  fi
  if $upgrade_reports && [ "$(basename "$migration")" = 20260906062000_provider_report_history.sql ]; then
    run_sql supabase/tests/fixtures/provider_reports_upgrade_seed.sql
  fi
  run_sql "$migration"
done
if $upgrade_reports; then
  run_sql supabase/tests/fixtures/provider_reports_upgrade_assert.sql
  echo 'PASS populated report-history upgrade'
  completed=true
  exit 0
fi
if $upgrade; then
  run_sql supabase/tests/fixtures/coordination_upgrade_assert.sql
  echo 'PASS populated coordination upgrade'
  completed=true
  exit 0
fi
if [ "$#" -gt 0 ]; then
  for contract in "$@"; do run_contract "$contract"; echo "PASS $contract"; done
else
  for contract in supabase/tests/*.sql; do
    if [ "$(basename "$contract")" != local_bootstrap.sql ]; then
      run_contract "$contract"
      echo "PASS $contract"
    fi
  done
fi

if $restore_drill; then
  # Persist our invoice scenario only after all contracts have rolled back.
  # This runs solely in the disposable container or Unix-socket-only cluster.
  sed 's/^rollback;[[:space:]]*$/commit;/' supabase/tests/invoice_closeout.sql | \
    sql >/dev/null
  if [ "$backend" = local ]; then
    local_pg pg_dump -Fc -f "$cluster/next009.dump" postgres
    local_pg createdb next009_restored
    local_pg pg_restore --exit-on-error --dbname next009_restored "$cluster/next009.dump"
  else
    docker exec "$container" pg_dump -U postgres -Fc -f /tmp/next009.dump postgres
    docker exec "$container" createdb -U postgres next009_restored
    docker exec "$container" pg_restore -U postgres --exit-on-error \
      --dbname next009_restored /tmp/next009.dump
  fi
  sql -d next009_restored < supabase/tests/fixtures/readiness_restore_assert.sql >/dev/null
  echo 'PASS isolated PostgreSQL archive restore, frozen invoice history and restored RLS'
fi
completed=true
