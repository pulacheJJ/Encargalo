-- Ingresar primero secretos en Vault mediante dashboard, nunca versionar valores:
-- encargalo_push_url = https://<ref>.supabase.co/functions/v1/dispatch-push
-- encargalo_push_secret = mismo PUSH_DISPATCH_SECRET de la Edge Function.
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
-- El nombre estable actualiza el trabajo existente, no crea copias al repetir.
select cron.schedule('encargalo-push-outbox','* * * * *', $schedule$
 select net.http_post(
 url := (select decrypted_secret from vault.decrypted_secrets where name='encargalo_push_url'),
 headers := jsonb_build_object('Content-Type','application/json','x-dispatch-secret',
 (select decrypted_secret from vault.decrypted_secrets where name='encargalo_push_secret')),
 body := '{}'::jsonb, timeout_milliseconds := 10000);
$schedule$);
