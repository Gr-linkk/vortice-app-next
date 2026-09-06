begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(position('OLD-42' in public.asset_history('a0080000-0000-4000-8000-000000000021')::text)>0,'existing legacy parts backfilled');
select pg_temp.assert_true(position('NEW-42' in public.asset_history('a0080000-0000-4000-8000-000000000021')::text)>0,'existing managed operations backfilled');
select pg_temp.assert_true(position('PROVIDER_PRIVATE_SENTINEL' in public.asset_history('a0080000-0000-4000-8000-000000000021')::text)=0,'backfill excludes internal work-order notes');
select pg_temp.assert_true(position('historical_snapshot' in public.asset_history('a0080000-0000-4000-8000-000000000021','asset')::text)>0,'mutable records labelled as historical snapshots');
select pg_temp.assert_true((public.fleet_attention('2026-09-06')->'counts'->>'approaching_service')::int=1,'existing plans appear in attention');
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true(jsonb_array_length(public.asset_history('a0080000-0000-4000-8000-000000000021','parts')->'entries')=0,'operator cannot read backfilled job costs');
reset role;
delete from public.parts where id='a0080000-0000-4000-8000-000000000031';
set local role authenticated;
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(position('OLD-42' in (public.asset_history('a0080000-0000-4000-8000-000000000021','parts')->'entries'->0)::text)>0,'deleted legacy part retains identity');
rollback;
