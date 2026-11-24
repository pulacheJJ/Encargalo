import { createClient } from '@supabase/supabase-js';
import { importPKCS8, SignJWT } from 'jose';
const env = (key: string): string => {
 const value = Deno.env.get(key);
 if (!value) throw new Error(`Configuración ausente: ${key}`);
 return value;
};
let oauth: { token: string; until: number } | undefined;
async function accessToken(sa: { private_key: string; client_email: string }) {
 if (oauth && oauth.until > Date.now()) return oauth.token;
 const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
 .setProtectedHeader({ alg: 'RS256' }).setIssuer(sa.client_email).setAudience('https://oauth2.googleapis.com/token')
 .setIssuedAt().setExpirationTime('55m').sign(await importPKCS8(sa.private_key, 'RS256'));
 const response = await fetch('https://oauth2.googleapis.com/token', { method: 'POST',
 headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
 body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }) });
 if (!response.ok) throw new Error(`OAuth ${response.status}`);
 const data = await response.json();
 oauth = { token: data.access_token, until: Date.now() + (data.expires_in - 120) * 1000 };
 return oauth.token;
}
Deno.serve(async (req) => {
 if (req.method !== 'POST') return new Response('Método no permitido', { status: 405 });
 if (req.headers.get('x-dispatch-secret') !== env('PUSH_DISPATCH_SECRET')) return new Response('No autorizado', { status: 401 });
 const db = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });
 try {
 const sa = JSON.parse(env('FCM_SERVICE_ACCOUNT_JSON'));
 if (sa.project_id !== 'encargalo-c54ec' || sa.client_email !== 'encargalo-fcm@encargalo-c54ec.iam.gserviceaccount.com') throw new Error('Cuenta FCM no autorizada');
 const token = await accessToken(sa);
 const input = await req.json().catch(() => ({}));
 if (input?.action === 'validate') {
  // FCM validates IAM and message syntax but sends NOTHING. This does not
  // claim Android delivery, and does not claim or consume the outbox.
  const validation = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
   method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
   body: JSON.stringify({ validate_only: true, message: { topic: 'encargalo-server-validation', data: { kind: 'server-validation' } } })
  });
  if (!validation.ok) {
   const detail = await validation.json().catch(() => ({}));
   return Response.json({ validated: false, fcm_status: validation.status,
    fcm_error: detail.error?.status ?? 'UNKNOWN', android_delivery_verified: false }, { status: 503 });
  }
  await validation.body?.cancel();
  return Response.json({ validated: true, validate_only: true, android_delivery_verified: false });
 }
 const { data: events, error } = await db.rpc('claim_push_batch');
 if (error) throw error;
 let completed = 0, acceptedByFcm = 0, noDevices = 0, failed = 0, invalidated = 0;
 for (const event of events ?? []) {
 let failure: string | null = null;
 const { data: devices, error: devicesError } = await db.from('device_tokens').select('device_id,token').eq('owner_id', event.recipient_id);
 if (devicesError) failure = 'No se pudieron consultar dispositivos';
 if (!devicesError && !devices?.length) noDevices++;
 for (const device of devices ?? []) {
 try {
 const response = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
 method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
 body: JSON.stringify({ message: { token: device.token, android: { priority: 'HIGH', ttl: '86400s' },
 data: { event_id: event.id, recipient_id: event.recipient_id, title: event.title, body: event.body,
 request_id: event.request_id ?? '', order_id: event.order_id ?? '' } } }) });
 if (!response.ok) {
 const detail = await response.json();
 const invalid = detail.error?.details?.some((d: { errorCode?: string }) => d.errorCode === 'UNREGISTERED');
 if (invalid) {
  const { error: deleteError } = await db.from('device_tokens').delete().eq('device_id', device.device_id).eq('token', device.token);
  if (deleteError) failure = 'No se pudo retirar token invalido';
  else invalidated++;
 }
 else failure = `FCM ${response.status}`;
 }
 else { acceptedByFcm++; await response.body?.cancel(); }
 } catch { failure = 'Transporte FCM no disponible'; }
 }
 const { error: finishError } = await db.rpc('finish_push', { p_id: event.id, p_error: failure });
 if (finishError) throw finishError;
 if (!failure) completed++; else failed++;
 }
 return Response.json({ processed: events?.length ?? 0, completed, accepted_by_fcm: acceptedByFcm,
  no_devices: noDevices, failed, invalidated });
 } catch {
 return Response.json({ error: 'Emisor no disponible; los eventos siguen pendientes' }, { status: 503 });
 }
});
