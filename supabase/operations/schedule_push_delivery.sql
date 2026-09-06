-- Run only on hkjpojobdbbtjkhaudki after the dedicated Next Firebase sender
-- and push-delivery function are configured. Create push_worker_secret in
-- Supabase Vault with the same random value as the function secret first.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
select cron.schedule('vortice-next-push','* * * * *',$task$
 select net.http_post(
  url:='https://hkjpojobdbbtjkhaudki.supabase.co/functions/v1/push-delivery',
  headers:=jsonb_build_object('Content-Type','application/json','x-push-worker-secret',
    (select decrypted_secret from vault.decrypted_secrets where name='push_worker_secret')),
  body:='{}'::jsonb,timeout_milliseconds:=60000);
$task$);
