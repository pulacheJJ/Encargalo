import { createClient } from '@supabase/supabase-js';
// No es un geocodificador genérico: solo consultas manuales de distritos de Piura.
const districts = ['Piura','Castilla','Catacaos','Veintiséis de Octubre','La Arena','La Unión','Cura Mori','El Tallán','Las Lomas','Tambogrande'];
const normalize = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
Deno.serve(async (req) => {
 if (req.method !== 'GET') return new Response('Método no permitido', { status: 405 });
 const auth = req.headers.get('Authorization') ?? '';
 const base = Deno.env.get('SUPABASE_URL')!;
 const client = createClient(base, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } } });
 const { data: user, error: authError } = await client.auth.getUser();
 if (authError || !user.user) return Response.json({ error: 'Sesión requerida' }, { status: 401 });
 const input = new URL(req.url).searchParams.get('q') ?? '';
 const district = districts.find(d => normalize(input) === normalize(`${d}, Piura, Perú`));
 if (!district) return Response.json({ error: 'La búsqueda admite únicamente un distrito de Piura, no direcciones privadas.' }, { status: 400 });
 const query = `${district}, Piura, Perú`;
 const db = createClient(base, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
 const { data: reservation, error } = await db.rpc('geocode_reserve', { p_query: query });
 if (error) return Response.json({ error: 'Buscador no disponible' }, { status: 503 });
 if (reservation.cached) return Response.json(reservation.cached);
 if (reservation.busy) return Response.json({ error: 'Espere unos segundos antes de volver a buscar.' }, { status: 429 });
 try {
  const endpoint = Deno.env.get('GEOCODER_URL') ?? 'https://nominatim.openstreetmap.org/search';
  const contact = Deno.env.get('GEOCODER_CONTACT');
  if (!contact) throw new Error('Falta contacto identificable del responsable');
  const url = new URL(endpoint);
  url.search = new URLSearchParams({ q: query, format: 'jsonv2', countrycodes: 'pe', limit: '3' }).toString();
  const response = await fetch(url, { headers: { 'User-Agent': `Encargalo-UNP/1.0 (${contact})`, 'Accept-Language': 'es' }, signal: AbortSignal.timeout(12000) });
  if (!response.ok) throw new Error('Proveedor no disponible');
  const results = await response.json();
  if (!Array.isArray(results)) throw new Error('Respuesta inválida');
  const safe = results.map(p => ({ display_name: p.display_name, lat: p.lat, lon: p.lon }));
  const { error: cacheError } = await db.rpc('geocode_finish', { p_query: query, p_result: safe });
  if (cacheError) throw cacheError;
  return Response.json(safe);
 } catch {
  await db.rpc('geocode_finish', { p_query: query, p_result: null });
  return Response.json({ error: 'No se obtuvo una referencia. Se puede escribir manualmente.' }, { status: 503 });
 }
});
