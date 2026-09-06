#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd -P)"
test "$(git rev-parse --show-toplevel)" = "$root"
test "$(git remote)" = origin
test "$(git remote get-url origin)" = https://github.com/Gr-linkk/vortice-app-next.git
container="vortice-next-contract-$$"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
docker run --rm -d --network none --name "$container" \
  -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17 >/dev/null
for attempt in {1..30}; do
  if docker exec "$container" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 1
done
run_sql() {
  docker exec -i -e PGOPTIONS='-c search_path=public,extensions' "$container" \
    psql -U postgres -v ON_ERROR_STOP=1 < "$1" >/dev/null
}
run_sql supabase/tests/local_bootstrap.sql
for migration in supabase/migrations/*.sql; do run_sql "$migration"; done
if [ "$#" -gt 0 ]; then
  for contract in "$@"; do run_sql "$contract"; echo "PASS $contract"; done
else
  for contract in supabase/tests/*.sql; do
    if [ "$(basename "$contract")" != local_bootstrap.sql ]; then
      run_sql "$contract"
      echo "PASS $contract"
    fi
  done
fi
