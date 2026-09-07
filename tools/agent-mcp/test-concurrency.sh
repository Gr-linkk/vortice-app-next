#!/usr/bin/env bash
# Local-only race test. All credentials/fixtures die with the no-network container.
set -euo pipefail
cd "$(dirname "$0")/../.."
test "$(git rev-parse --show-toplevel)" = "$(pwd -P)"
test "$(git remote)" = origin
test "$(git remote get-url origin)" = https://github.com/Gr-linkk/vortice-app-next.git
container="vortice-next-agent-races-$$"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
docker run --rm -d --network none --name "$container" -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17 >/dev/null
for attempt in {1..30}; do
  if docker exec "$container" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 1
done
sql() { docker exec -i -e PGOPTIONS='-c search_path=public,extensions' "$container" psql -U postgres -v ON_ERROR_STOP=1 >/dev/null; }
sql < supabase/tests/local_bootstrap.sql
for migration in supabase/migrations/*.sql; do sql < "$migration"; done
sql <<'SQL'
insert into auth.users(id,email,raw_user_meta_data) values('a0190000-0000-4000-8000-000000000001','agent-race@example.invalid','{}');
update public.profiles set role='client' where id='a0190000-0000-4000-8000-000000000001';
insert into public.asset_types(id,category,name) values('a0190000-0000-4000-8000-000000000020','test','Race');
insert into public.assets(id,client_id,asset_type_id,name) values('a0190000-0000-4000-8000-000000000021','a0190000-0000-4000-8000-000000000001','a0190000-0000-4000-8000-000000000020','Race fixture');
insert into public.client_capabilities(client_id,capability_key,enabled) values('a0190000-0000-4000-8000-000000000001','pm_checklists',true);
create table public.agent_race_fixture(credential jsonb);
create table public.agent_race_results(result jsonb);
grant select,insert on public.agent_race_fixture,public.agent_race_results to authenticated,anon;
set role authenticated;
select set_config('request.jwt.claim.sub','a0190000-0000-4000-8000-000000000001',false);
insert into public.agent_race_fixture select public.create_agent_connection('a0190000-0000-4000-8000-000000000001','Local race fixture',true);
SQL
invoke() {
  # Operation is one of the fixed UUIDs in this script, never user text.
  sql <<SQL
set role anon;
insert into public.agent_race_results select public.agent_execute(
 (select credential->>'token' from public.agent_race_fixture),'create_work_order_draft',
 '{"asset_id":"a0190000-0000-4000-8000-000000000021","title":"Concurrent draft"}',
 '$1');
SQL
}
pids=()
for attempt in {1..8}; do invoke a0190000-0000-4000-8000-000000000030 & pids+=("$!"); done
for pid in "${pids[@]}"; do wait "$pid"; done
sql <<'SQL'
do $$ begin
 if (select count(*) from public.work_orders)<>1
 or (select count(*) from public.agent_race_results)<>8
 or exists(select 1 from public.agent_race_results where result ? 'error')
 then raise exception 'Concurrent retries did not produce exactly one draft'; end if;
end $$;
create function public.agent_race_pause() returns trigger language plpgsql as $$ begin
 perform pg_advisory_xact_lock(190019); perform pg_sleep(2); return new; end $$;
create trigger agent_race_pause before insert on public.work_orders for each row execute function public.agent_race_pause();
SQL
echo 'PASS eight concurrent identical requests create one draft'
invoke a0190000-0000-4000-8000-000000000031 & writer=$!
locked=false
for attempt in {1..50}; do
  if [ "$(docker exec "$container" psql -U postgres -Atc "select count(*) from pg_locks where locktype='advisory' and objid=190019 and granted")" = 1 ]; then locked=true; break; fi
  sleep 0.1
done
test "$locked" = true
sql <<'SQL'
set role authenticated;
select set_config('request.jwt.claim.sub','a0190000-0000-4000-8000-000000000001',false);
select public.revoke_agent_connections((select (credential->>'id')::uuid from public.agent_race_fixture));
SQL
wait "$writer"
invoke a0190000-0000-4000-8000-000000000032
sql <<'SQL'
do $$ begin
 if (select count(*) from public.work_orders)<>2
 or (select count(*) from public.agent_race_results where result->>'error'='Access denied')<>1
 then raise exception 'Revocation race allowed a later write'; end if;
end $$;
SQL
echo 'PASS revocation waits for in-flight work and denies later writes'
