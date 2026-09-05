begin;
insert into auth.users(id,email,raw_user_meta_data) values
 ('a0031000-0000-4000-8000-000000000001','now003-role-probe@example.invalid',
  '{"role":"owner","subscription_tier":3}');
do $$ begin
 if not exists(select 1 from public.profiles where id='a0031000-0000-4000-8000-000000000001'
   and role='client' and org_id is null and subscription_tier=0) then
   raise exception 'FAIL: user metadata must not grant roles, membership or paid tier';
 end if;
end $$;

-- Membership must also be server-selected, even if the supplied org exists.
insert into public.client_orgs(id,name,owner_profile_id) values
 ('a0031000-0000-4000-8000-000000000010','Signup boundary fixture','a0031000-0000-4000-8000-000000000001');
insert into auth.users(id,email,raw_user_meta_data) values
 ('a0031000-0000-4000-8000-000000000002','now003-org-probe@example.invalid',
  '{"role":"client_mechanic","org_id":"a0031000-0000-4000-8000-000000000010"}');
do $$ begin
 if not exists(select 1 from public.profiles where id='a0031000-0000-4000-8000-000000000002'
   and role='client' and org_id is null) then raise exception 'FAIL: forged org membership'; end if;
end $$;
insert into public.org_codes(id,code,intended_role,org_id,single_use,max_uses,use_count)
 values('a0031000-0000-4000-8000-000000000020','NOW003-INVITE','client_admin',
 'a0031000-0000-4000-8000-000000000010',true,1,0);
insert into auth.users(id,email,raw_user_meta_data) values
 ('a0031000-0000-4000-8000-000000000003','now003-invite-probe@example.invalid',
  '{"org_code_used":"now003-invite","role":"owner"}');
do $$ begin
 if not exists(select 1 from public.profiles where id='a0031000-0000-4000-8000-000000000003'
   and role='client_admin' and org_id='a0031000-0000-4000-8000-000000000010') then
   raise exception 'FAIL: valid invitation did not assign the server-selected role'; end if;
 if (select use_count from public.org_codes where code='NOW003-INVITE')<>1 then
   raise exception 'FAIL: invite usage was not consumed once'; end if;
 begin
   insert into auth.users(id,email,raw_user_meta_data) values
    ('a0031000-0000-4000-8000-000000000004','now003-reused-probe@example.invalid','{"org_code_used":"NOW003-INVITE"}');
 exception when others then
   if position('orgCodeUsed' in sqlerrm)>0 then return; end if;
   raise;
 end;
 raise exception 'FAIL: invitation reuse was allowed';
end $$;
update public.org_codes set code='NOW003-EXPIRED',use_count=0,expires_at=now()-interval '1 day'
 where id='a0031000-0000-4000-8000-000000000020';
do $$ begin
 begin
   insert into auth.users(id,email,raw_user_meta_data) values
    ('a0031000-0000-4000-8000-000000000005','now003-expired-probe@example.invalid','{"org_code_used":"NOW003-EXPIRED"}');
 exception when others then
   if position('orgCodeExpired' in sqlerrm)>0 then return; end if;
   raise;
 end;
 raise exception 'FAIL: expired invitation was allowed';
end $$;
update public.org_codes set code='NOW003-MECHANIC',intended_role='client_mechanic',expires_at=null
 where id='a0031000-0000-4000-8000-000000000020';
do $$ begin
 begin
   insert into auth.users(id,email,raw_user_meta_data) values
    ('a0031000-0000-4000-8000-000000000006','now003-capability-probe@example.invalid','{"org_code_used":"NOW003-MECHANIC"}');
 exception when others then
   if position('capability is not enabled' in sqlerrm)>0 then return; end if;
   raise;
 end;
 raise exception 'FAIL: disabled mechanic invitation was allowed';
end $$;
insert into public.client_capabilities(client_id,capability_key,enabled) values
 ('a0031000-0000-4000-8000-000000000001','pm_checklists',true);
insert into auth.users(id,email,raw_user_meta_data) values
 ('a0031000-0000-4000-8000-000000000006','now003-capability-probe@example.invalid','{"org_code_used":"NOW003-MECHANIC"}');
do $$ begin
 if not exists(select 1 from public.profiles where id='a0031000-0000-4000-8000-000000000006'
   and role='client_mechanic') then raise exception 'FAIL: enabled mechanic invite'; end if;
end $$;
rollback;
select 'Signup role boundary passed; all fixtures rolled back' as result;
