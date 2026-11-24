import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

// PostgreSQL WASM aislado: acredita reglas y transacciones, NO despliegue cloud.
let db;
const ids = { client:'11111111-1111-4111-8111-111111111111',biz:'22222222-2222-4222-8222-222222222222',other:'33333333-3333-4333-8333-333333333333',biz2:'44444444-4444-4444-8444-444444444444',request:'55555555-5555-4555-8555-555555555555',quote:'66666666-6666-4666-8666-666666666666',quote2:'77777777-7777-4777-8777-777777777777',op:'88888888-8888-4888-8888-888888888888' };
async function actor(id, role='authenticated') {
 await db.exec('reset role');
 await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role',$2,false)",[id,role]);
 await db.exec(`set role ${role}`);
}
async function rpc(sql, args=[]) { return (await db.query(sql,args)).rows; }
const request = { id:ids.request,title:'30 polos para la UNP',detail:'Polos de algodón morados, tallas variadas',quantity:30,category_id:'estampado',district:'Castilla',desired_date:'2099-12-01',photos:[],delivery:{reference:'Referencia privada',latitude:-5.1,longitude:-80.6,accuracy:10,captured_at:'2026-11-23T10:00:00Z'} };
before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
 create schema auth;create schema storage;create schema extensions;
 create table auth.users(id uuid primary key,raw_user_meta_data jsonb);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
 grant usage on schema auth to authenticated,anon,service_role;grant execute on all functions in schema auth to authenticated,anon,service_role;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,metadata jsonb);
 alter table storage.objects enable row level security;
 create function storage.foldername(text) returns text[] language sql immutable as $$select string_to_array($1,'/')$$;
 grant usage on schema storage to authenticated;grant select,insert,delete on storage.objects to authenticated;
 grant execute on function storage.foldername(text) to authenticated;`);
 let sql=await readFile(new URL('../supabase/migrations/202611230001_encargalo.sql',import.meta.url),'utf8');
 // Solo infraestructura no presente en WASM: pgcrypto (UUID es nativo) y publicación Realtime.
 sql=sql.replace(/create extension if not exists pgcrypto with schema extensions;/,'').replace(/alter publication supabase_realtime[^;]+;/,'');
 await db.exec(sql);
  await db.exec(await readFile(new URL('../supabase/migrations/202611230002_geocoding.sql',import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/202611240001_business_conflicts.sql',import.meta.url),'utf8'));
  for(const migration of ['202611240002_commerce.sql','202611240003_profiles_locations.sql','202611240004_contact_location_guards.sql']){
    const source=(await readFile(new URL(`../supabase/migrations/${migration}`,import.meta.url),'utf8')).replace(/alter publication supabase_realtime[^;]+;/g,'');
    try{await db.exec(source);}catch(e){console.error('Migration diagnostic',migration,{position:e.position,internalPosition:e.internalPosition,internalQuery:e.internalQuery,where:e.where});throw e;}
  }
  await db.exec("insert into public.locations values('200101','Piura','Piura','Piura'),('200104','Piura','Piura','Castilla'),('150101','Lima','Lima','Lima')");
 for(const [id,role,name] of [[ids.client,'cliente','Cliente'],[ids.biz,'negocio','Taller Uno'],[ids.other,'cliente','Ajeno'],[ids.biz2,'negocio','Taller Dos']]) {
  await db.query('insert into auth.users values($1,$2)',[id,{role,name}]);
 }
});
after(async()=>await db?.close());
test('Publicación: JWT, idempotencia, RLS y dirección privada',async()=>{
 await actor(ids.client);
 await rpc('select public.publish_request($1,$2,0)',[request,ids.op]);
 await rpc('select public.publish_request($1,$2,0)',[request,ids.op]);
 assert.equal((await rpc('select * from public.requests')).length,1);
 assert.equal((await rpc('select version from public.requests'))[0].version,1);
 await actor(ids.other);assert.equal((await rpc('select * from public.requests')).length,0);
 assert.equal((await rpc('select * from public.request_delivery')).length,0);
 await actor(ids.biz);assert.equal((await rpc('select * from public.requests')).length,1);
 assert.equal((await rpc('select * from public.request_delivery')).length,0);
 await assert.rejects(rpc("update public.profiles set role='cliente' where id=auth.uid()"),/permission denied/);
 await assert.rejects(rpc('select public.publish_request($1,$2,0)',[{...request,id:ids.other},ids.op]),/Solo un cliente/);
});
test('Cotización: importe, propiedad, categorías y un negocio no ve propuestas ajenas',async()=>{
 const quote = {id:ids.quote,request_id:ids.request,total_cents:90000,promised_date:'2099-11-25',expires_at:'2099-11-30T10:00:00Z',conditions:'Incluye diseño y estampado frontal'};
 await actor(ids.client);await assert.rejects(rpc('select public.submit_quote($1,$2,0)',[quote,ids.op]));
 await actor(ids.biz);
 await assert.rejects(rpc('select public.submit_quote($1,$2,0)',[{...quote,total_cents:0},ids.op]));
 await rpc('select public.submit_quote($1,$2,0)',[quote,ids.op]);
 await rpc('select public.submit_quote($1,$2,0)',[quote,ids.op]);
 assert.equal((await rpc('select * from public.quotes')).length,1);
 await actor(ids.biz2);assert.equal((await rpc('select * from public.quotes')).length,0);
 await rpc('select public.submit_quote($1,$2,0)',[{...quote,id:ids.quote2,total_cents:100000},ids.op]);
 await actor(ids.client);assert.equal((await rpc('select * from public.quotes')).length,2);
 assert.equal((await rpc('select quote_count from public.requests where id=$1',[ids.request]))[0].quote_count,2);
 assert.equal((await rpc('select * from public.notifications')).length,2);
 await assert.rejects(rpc('select * from public.claim_push_batch()'),/permission denied/);
});
test('Aceptación única: reintento, instantánea, no selección y permisos',async()=>{
  await actor(ids.other);await assert.rejects(rpc('select public.accept_quote($1,$2)',[ids.quote,ids.op]),e=>e.code==='42501');
 await actor(ids.client);
 const a=(await rpc('select (public.accept_quote($1,$2)).*',[ids.quote,ids.op]))[0];
 const b=(await rpc('select (public.accept_quote($1,$2)).*',[ids.quote,ids.op]))[0];
 assert.equal(a.id,b.id);assert.equal(a.total_cents,90000);
  await assert.rejects(rpc('select public.accept_quote($1,$2)',[ids.quote2,ids.op]),e=>e.code==='PT409');
 assert.equal((await rpc('select * from public.orders')).length,1);
 assert.equal((await rpc("select * from public.quotes where status='not_selected'")).length,1);
 await actor(ids.biz);assert.equal((await rpc('select * from public.request_delivery')).length,1);
 await rpc('select public.save_profile($1,$2,$3,$4,$5)',['Nuevo nombre','Piura','Descripción',['estampado'],'']);
 assert.equal((await rpc('select business_name from public.orders'))[0].business_name,'Taller Uno');
 await actor(ids.biz2);assert.equal((await rpc('select * from public.orders')).length,0);assert.equal((await rpc('select * from public.request_delivery')).length,0);
});
test('Transiciones, historial y notificaciones solo mediante servidor',async()=>{
 await actor(ids.biz);let o=(await rpc('select * from public.orders'))[0];
  await assert.rejects(rpc('select public.transition_order($1,$2,$3,$4)',[o.id,'ready',crypto.randomUUID(),1]),e=>e.code==='42501');
 const op='99999999-9999-4999-8999-999999999999';
 await rpc('select public.transition_order($1,$2,$3,$4)',[o.id,'production',op,1]);
 await rpc('select public.transition_order($1,$2,$3,$4)',[o.id,'production',op,1]);
  await assert.rejects(rpc('select public.transition_order($1,$2,$3,$4)',[o.id,'ready',ids.op,1]),e=>e.code==='PT409'&&/recargue/.test(e.message));
 await rpc('select public.transition_order($1,$2,$3,$4)',[o.id,'ready',ids.op,2]);
  await assert.rejects(rpc('select public.transition_order($1,$2,$3,$4)',[o.id,'delivered',op,3]),e=>e.code==='42501');
  await actor(ids.client);
  await assert.rejects(rpc('select public.transition_order($1,$2,$3,$4)',[o.id,'delivered',op,3]),e=>e.code==='PT409');
  await rpc('select public.simulate_order_payment($1,$2,true,$3,3)',[o.id,o.total_cents,op]);
  await rpc('select public.transition_order($1,$2,$3,$4)',[o.id,'delivered',op,4]);
 assert.equal((await rpc('select * from public.order_history')).length,4);
 await assert.rejects(rpc("update public.orders set status='confirmed'"),/permission denied/);
 await actor(ids.other);assert.equal((await rpc('select * from public.order_history')).length,0);assert.equal((await rpc('select * from public.notifications')).length,0);
});
test('Anónimo no tiene acceso a tablas ni operaciones',async()=>{
 await actor('', 'anon');await assert.rejects(rpc('select * from public.requests'),/permission denied/);
 await assert.rejects(rpc('select public.accept_quote($1,$2)',[ids.quote,ids.op]),/permission denied/);
});
test('Storage privado: prefijo propio, visibilidad y cero URLs públicas',async()=>{
 await actor(ids.client);
 const path=`${ids.client}/${ids.request}/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`;
 await rpc('insert into storage.objects(bucket_id,name,metadata) values($1,$2,$3)',['references',path,{size:100}]);
 assert.equal((await rpc('select * from storage.objects')).length,1);
 await actor(ids.other);assert.equal((await rpc('select * from storage.objects')).length,0);
 await assert.rejects(rpc('insert into storage.objects(bucket_id,name) values($1,$2)',['references',path+'otro']),/row-level security/);
 await actor(ids.biz);assert.equal((await rpc('select * from storage.objects')).length,0);
 await db.exec('reset role');assert.equal((await rpc("select public from storage.buckets where id='references'"))[0].public,false);
});
test('Cancelación con tombstone no resucita por un reintento viejo',async()=>{
 await actor(ids.client);
 const id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 await rpc('select public.publish_request($1,$2,0)',[{...request,id},ids.op]);
 const op='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
 await rpc('select public.delete_request($1,$2,1)',[id,op]);
 await rpc('select public.delete_request($1,$2,1)',[id,op]);
 await assert.rejects(rpc('select public.publish_request($1,$2,1)',[{...request,id},ids.op]),/Conflicto/);
 assert.equal((await rpc('select status from public.requests where id=$1',[id]))[0].status,'deleted');
 await actor(ids.biz);assert.equal((await rpc('select * from public.requests where id=$1',[id])).length,0);
});
test('Versiones nulas no evitan control optimista y máximo tres adjuntos',async()=>{
 await actor(ids.client);
 const id='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
 await assert.rejects(rpc('select public.publish_request($1,$2,null)',[{...request,id},ids.op]),/Solicitud ausente/);
 await assert.rejects(rpc('select public.publish_request($1,$2,0)',[{...request,id,photos:[{},{},{},{}]},ids.op]),/tres fotos/);
});
test('Outbox: solo servicio, lease único y finalización persistente',async()=>{
 await actor('', 'service_role');
 const batch=await rpc('select * from public.claim_push_batch()');assert.ok(batch.length>0);
 assert.equal((await rpc('select * from public.claim_push_batch()')).length,0);
 await rpc('select public.finish_push($1,null)',[batch[0].id]);
 await db.exec('reset role');
 assert.ok((await rpc('select sent_at from public.push_outbox where id=$1',[batch[0].id]))[0].sent_at);
});
test('Geocodificación: caché de servidor y exclusión global',async()=>{
 await actor('', 'service_role');
 const reserve=(await rpc("select public.geocode_reserve('Piura') as value"))[0].value;
 assert.equal(reserve.reserved,true);
 assert.equal((await rpc("select public.geocode_reserve('Castilla') as value"))[0].value.busy,true);
 await rpc('select public.geocode_finish($1,$2)',['Piura',[{lat:'-5.2',lon:'-80.6',display_name:'Piura'}]]);
 assert.equal((await rpc("select public.geocode_reserve('Piura') as value"))[0].value.cached.length,1);
 await actor(ids.other);await assert.rejects(rpc("select public.geocode_reserve('Piura')"),/permission denied/);
});

async function commerceOrder() {
  await actor(ids.client);
  const id=crypto.randomUUID(),quote=crypto.randomUUID();
  await rpc('select public.publish_request($1,$2,0)',[{...request,id},crypto.randomUUID()]);
  await actor(ids.biz);
  await rpc('select public.submit_quote($1,$2,0)',[{id:quote,request_id:id,total_cents:10000,deposit_cents:5000,promised_date:'2099-11-25',expires_at:'2099-11-30T10:00:00Z',conditions:'Acuerdo de prueba con adelanto simulado'},crypto.randomUUID()]);
  await actor(ids.client);
  return (await rpc('select (public.accept_quote($1,$2)).*',[quote,crypto.randomUUID()]))[0];
}
test('Pagos simulados: rechazo, adelanto parcial, idempotencia, saldo y privacidad',async()=>{
  const o=await commerceOrder();
  await actor(ids.biz);
  await assert.rejects(rpc('select public.transition_order($1,$2,$3,1)',[o.id,'production',crypto.randomUUID()]),e=>e.code==='PT409');
  await assert.rejects(rpc('select public.simulate_order_payment($1,5000,true,$2,1)',[o.id,crypto.randomUUID()]),e=>e.code==='42501');
  await actor(ids.client);
  await rpc('select public.simulate_order_payment($1,5000,false,$2,1)',[o.id,crypto.randomUUID()]);
  assert.equal((await rpc('select paid_cents from public.orders where id=$1',[o.id]))[0].paid_cents,0);
  const operation=crypto.randomUUID();
  const p=(await rpc('select (public.simulate_order_payment($1,3000,true,$2,1)).*',[o.id,operation]))[0];
  const retry=(await rpc('select (public.simulate_order_payment($1,3000,true,$2,1)).*',[o.id,operation]))[0];
  assert.equal(p.id,retry.id);
  await assert.rejects(rpc('select public.simulate_order_payment($1,2000,true,$2,2)',[o.id,operation]),e=>e.code==='PT409');
  await assert.rejects(rpc('select public.simulate_order_payment($1,8000,true,$2,2)',[o.id,crypto.randomUUID()]));
  await actor(ids.biz);
  await assert.rejects(rpc('select public.transition_order($1,$2,$3,2)',[o.id,'production',crypto.randomUUID()]),e=>e.code==='PT409');
  await actor(ids.client);await rpc('select public.simulate_order_payment($1,2000,true,$2,2)',[o.id,crypto.randomUUID()]);
  await actor(ids.biz);await rpc('select public.transition_order($1,$2,$3,3)',[o.id,'production',crypto.randomUUID()]);
  assert.equal((await rpc('select paid_cents from public.orders where id=$1',[o.id]))[0].paid_cents,5000);
  await actor(ids.other);assert.equal((await rpc('select * from public.order_payments where order_id=$1',[o.id])).length,0);
  await actor(ids.client);await assert.rejects(rpc("update public.order_payments set amount_cents=1 where order_id=$1",[o.id]),/permission denied/);
});
test('Cancelacion antes de producir: devolucion integra y reintento sin duplicar',async()=>{
  const o=await commerceOrder();
  await rpc('select public.simulate_order_payment($1,3000,true,$2,1)',[o.id,crypto.randomUUID()]);
  const op=crypto.randomUUID();
  await rpc('select public.request_order_cancellation($1,$2,0,$3,2)',[o.id,'Cambio de fecha del evento solicitado',op]);
  await rpc('select public.request_order_cancellation($1,$2,0,$3,2)',[o.id,'Cambio de fecha del evento solicitado',op]);
  const cancelled=(await rpc('select * from public.orders where id=$1',[o.id]))[0];
  assert.equal(cancelled.status,'cancelled');assert.equal(cancelled.paid_cents,0);
  const refunds=await rpc("select * from public.order_payments where order_id=$1 and kind='refund'",[o.id]);
  assert.equal(refunds.length,1);assert.equal(refunds[0].amount_cents,3000);
});
test('Cancelacion en produccion: acuerdo bilateral, retencion limitada y devolucion atomica',async()=>{
  const o=await commerceOrder();
  await rpc('select public.simulate_order_payment($1,5000,true,$2,1)',[o.id,crypto.randomUUID()]);
  await actor(ids.biz);await rpc('select public.transition_order($1,$2,$3,2)',[o.id,'production',crypto.randomUUID()]);
  await actor(ids.client);
  await assert.rejects(rpc('select public.request_order_cancellation($1,$2,6000,$3,3)',[o.id,'Motivo de cancelacion de prueba',crypto.randomUUID()]));
  const c=(await rpc('select (public.request_order_cancellation($1,$2,1000,$3,3)).*',[o.id,'Motivo de cancelacion de prueba',crypto.randomUUID()]))[0];
  await assert.rejects(rpc('select public.resolve_order_cancellation($1,$2,$3)',[c.id,'accepted',crypto.randomUUID()]),e=>e.code==='42501');
  await assert.rejects(rpc('select public.simulate_order_payment($1,1000,true,$2,4)',[o.id,crypto.randomUUID()]),e=>e.code==='PT409');
  await actor(ids.other);await assert.rejects(rpc('select public.resolve_order_cancellation($1,$2,$3)',[c.id,'accepted',crypto.randomUUID()]),e=>e.code==='42501');
  await actor(ids.biz);await assert.rejects(rpc('select public.transition_order($1,$2,$3,4)',[o.id,'ready',crypto.randomUUID()]),e=>e.code==='PT409');
  const resolution=crypto.randomUUID();
  await rpc('select public.resolve_order_cancellation($1,$2,$3)',[c.id,'accepted',resolution]);
  await rpc('select public.resolve_order_cancellation($1,$2,$3)',[c.id,'accepted',resolution]);
  const final=(await rpc('select * from public.orders where id=$1',[o.id]))[0];
  assert.equal(final.status,'cancelled');assert.equal(final.paid_cents,1000);
  assert.equal((await rpc("select * from public.order_payments where order_id=$1 and kind='refund'",[o.id]))[0].amount_cents,4000);
  assert.equal((await rpc("select * from public.order_history where order_id=$1 and new_status='cancelled'",[o.id])).length,1);
});
test('Perfil completo y ubigeo: campos privados, validacion y resumen por identidad',async()=>{
  await actor(ids.client);
  await rpc('select public.save_profile_details($1)',[{name:'Cliente de pruebas',location_code:'200104',categories:[],phone:'999111222',contact_name:'Contacto de prueba',address_reference:'Referencia privada de fixture'}]);
  assert.equal((await rpc('select district from public.profiles where id=$1',[ids.client]))[0].district,'Castilla');
  await assert.rejects(rpc('select public.save_profile_details($1)',[{name:'Prueba',location_code:'999999',phone:'999111222',contact_name:'Contacto'}]));
  const summary=(await rpc('select public.home_overview() as data'))[0].data;
  assert.ok(summary.requests_count>=0);assert.ok(summary.orders.every(o=>o.client_id===ids.client));
  await actor(ids.other);assert.equal((await rpc('select * from public.profile_contacts where owner_id=$1',[ids.client])).length,0);
});
test('Ubigeo legado no acepta distritos inventados ni accesos ajenos al contacto',async()=>{
  await actor(ids.client);
  await assert.rejects(rpc('select public.publish_request($1,$2,0)',[{...request,id:crypto.randomUUID(),district:'Distrito inventado fuera del catalogo'},crypto.randomUUID()]));
  const id=crypto.randomUUID();
  await rpc('select public.publish_request($1,$2,0)',[{...request,id},crypto.randomUUID()]);
  const changed=(await rpc('select (public.publish_request($1,$2,1)).*',[{...request,id,district:'Piura'},crypto.randomUUID()]))[0];
  assert.equal(changed.location_code,'200101');assert.equal(changed.district,'Piura');
  const order=await commerceOrder();
  const contact=(await rpc('select public.order_contact($1) as data',[order.id]))[0].data;
  assert.deepEqual(Object.keys(contact).sort(),['contact_name','phone']);
  await actor(ids.other);await assert.rejects(rpc('select public.order_contact($1)',[order.id]),e=>e.code==='42501');
});
