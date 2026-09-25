"""Create a separate internal test mechanic without disturbing existing timers.

Uses only Next. No emails are sent; secrets stay in ignored private files.
Keep the fixture for repeatable E2E; it is never added to the app's demo picker.
"""
import json
import os
import secrets
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'scripts'))
from next_environment import ROOT, assert_environment, checked

assert_environment()
config = ROOT / 'config/e2e-executor.local.json'
if config.exists():
    raise SystemExit('An isolated executor is already configured; reuse it rather than rotating credentials.')
identity = str(uuid.uuid4())
email = 'e2e_mechanic_' + identity[:8] + '@vortice.dev'
password = secrets.token_urlsafe(32)
folder = ROOT / 'work/isolated-executor-private'
folder.mkdir(mode=0o700, parents=True, exist_ok=True)
sql = folder / 'prepare.sql'
sql.write_text(f"""begin;
do $$ begin
 if not exists(select 1 from public.profiles where email='client_mechanic@vortice.dev'
  and role='client_mechanic' and org_id is not null) then raise exception 'Expected Next test organization is unavailable'; end if;
end $$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change)
values('{identity}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','{email}',
 extensions.crypt('{password}',extensions.gen_salt('bf')),now(),
 '{{"provider":"email","providers":["email"]}}','{{}}',now(),now(),'','','','');
insert into auth.identities(id,provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
values(gen_random_uuid(),'{identity}','{identity}',jsonb_build_object('sub','{identity}','email','{email}','email_verified',true),'email',now(),now(),now());
update public.profiles p set email='{email}',role='client_mechanic',full_name='Isolated E2E Mechanic',org_id=source.org_id
from public.profiles source where source.email='client_mechanic@vortice.dev' and p.id='{identity}';
commit;
""")
os.chmod(sql, 0o600)
checked(['supabase','db','query','--linked','--file',str(sql),'--output','json'])
with config.open('x') as stream:
    json.dump({'id': identity, 'email': email, 'password': password,
               'source': 'client_mechanic@vortice.dev', 'project_ref': 'hkjpojobdbbtjkhaudki'}, stream)
os.chmod(config, 0o600)
print('Prepared isolated test mechanic; credentials saved only in config/e2e-executor.local.json.')
