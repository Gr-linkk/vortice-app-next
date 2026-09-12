begin;
create function pg_temp.ok(ok boolean,label text) returns void language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('b0130000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'assets-context-'||n||'@example.invalid','{}' from generate_series(1,2)n;
update public.profiles set role='client',full_name='Assets workspace' where id::text like 'b0130000-%';
insert into public.asset_types(id,category,name) values('b0130000-0000-4000-8000-000000000020','test','Workspace machine');
insert into public.assets(id,client_id,asset_type_id,name) values
('b0130000-0000-4000-8000-000000000021','b0130000-0000-4000-8000-000000000001','b0130000-0000-4000-8000-000000000020','First machine'),
('b0130000-0000-4000-8000-000000000022','b0130000-0000-4000-8000-000000000001','b0130000-0000-4000-8000-000000000020','Second machine'),
('b0130000-0000-4000-8000-000000000023','b0130000-0000-4000-8000-000000000002','b0130000-0000-4000-8000-000000000020','Other company');
insert into public.asset_inspections(id,asset_id,title) values
('b0130000-0000-4000-8000-000000000031','b0130000-0000-4000-8000-000000000021','First certificate'),
('b0130000-0000-4000-8000-000000000032','b0130000-0000-4000-8000-000000000021','Second certificate'),
('b0130000-0000-4000-8000-000000000033','b0130000-0000-4000-8000-000000000023','Other company certificate');
insert into public.inspection_submissions(id,inspection_id,inspected_on,expires_on,procedure_notes,result_notes,evidence_path,submitted_by,submitted_name,status,reviewed_at)
select ('b0130000-0000-4000-8000-'||lpad((40+n)::text,12,'0'))::uuid,('b0130000-0000-4000-8000-'||lpad((30+n)::text,12,'0'))::uuid,
date '2025-01-01',date '2026-01-01','Inspect procedure','Passed inspection','test.jpg','b0130000-0000-4000-8000-000000000001','Fixture','approved',now() from generate_series(1,3)n;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0130000-0000-4000-8000-000000000001',true);
select pg_temp.ok((public.asset_workspace('2026-09-12')->>'total')::int=2,'workspace includes only authorized company assets');
select pg_temp.ok((public.asset_workspace('2026-09-12')->'counts'->>'inspection_expired')::int=1,'two expired certificates count one asset');
select pg_temp.ok((select count(*)=1 from jsonb_array_elements(public.asset_workspace('2026-09-12')->'items') r where r->'categories' ? 'inspection_expired'),'filter result count equals Home indicator');
select pg_temp.ok((select jsonb_array_length(r->'inspections')=2 from jsonb_array_elements(public.asset_workspace('2026-09-12')->'items') r where r->>'id'='b0130000-0000-4000-8000-000000000021'),'both certificate histories remain under original asset');
select set_config('request.jwt.claim.sub','b0130000-0000-4000-8000-000000000002',true);
select pg_temp.ok((public.asset_workspace('2026-09-12')->>'total')::int=1,'other company sees its own independent asset');
rollback;
