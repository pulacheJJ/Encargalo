// Prueba contra Supabase REAL. Las identidades se provisionan mediante Auth Admin
// SOLO para preparar fixtures; todas las acciones de negocio utilizan JWT de usuario.
// No envía correos ni acredita captura/GPS/push físicos. Nunca imprime credenciales.
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));
const config=JSON.parse(await Deno.readTextFile(join(root,'config/public.json')));
const ref='thptipcvzevxuysjqvyq';
if(config.SUPABASE_URL!==`https://${ref}.supabase.co`)throw new Error('Proyecto no autorizado para esta prueba');
const report:{[key:string]:unknown}={project:ref,date:new Date().toISOString(),kind:'Cloud real con cuentas Auth de prueba',
 physical_device_verified:false,email_delivery_verified:false,fcm_delivery_verified:false,checks:[]};
const checks=report.checks as {name:string;passed:boolean}[];
const clients:SupabaseClient[]=[];
function check(value:unknown,name:string):asserts value {
 checks.push({name,passed:!!value});if(!value)throw new Error(`Fallo de aceptacion: ${name}`);
}
function record(value:unknown):Record<string,unknown>{
 const row=Array.isArray(value)&&value.length===1?value[0]:value;
 if(!row||typeof row!=='object'||Array.isArray(row))throw new Error('Confirmacion RPC invalida');
 return row as Record<string,unknown>;
}
function client(){const c=createClient(config.SUPABASE_URL,config.SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});clients.push(c);return c;}
async function rpc(c:SupabaseClient,name:string,args:Record<string,unknown>){const r=await c.rpc(name,args);if(r.error)throw new Error(`${name}: ${r.error.code??r.status??'error'}`);return r.data;}
const day=(plus:number)=>new Date(Date.now()+plus*86400000).toISOString().slice(0,10);
type Account={id:string;email:string;password:string;role:string;label:string};
let admin:SupabaseClient|undefined;
try{
 const file=join(root,'.secrets/cloud-test-accounts.json');
 let accounts:Account[]=[];
 try{accounts=JSON.parse(await Deno.readTextFile(file));}catch(e){if(!(e instanceof Deno.errors.NotFound))throw e;}
 for(const spec of [{role:'cliente',label:'Cliente de prueba cloud'}, {role:'negocio',label:'Taller de prueba cloud A'},
  {role:'negocio',label:'Taller de prueba cloud B'},{role:'cliente',label:'Cuenta ajena de prueba cloud'}]){
   if(accounts.some(a=>a.label===spec.label))continue;
   // Least privilege: existing Auth fixtures need no administrative access.
   // Read a server key in memory ONLY if an identity actually needs creating.
   if(!admin){
    const command=await new Deno.Command('cmd.exe',{args:['/d','/c','npm','exec','--yes','--package=supabase@3.3.0','--','supabase','projects','api-keys',`--remote=${ref}`,'--reveal','--output','json'],cwd:root,stdout:'piped',stderr:'piped'}).output();
    if(!command.success)throw new Error('No se pudo autorizar la preparacion de cuentas de prueba');
    const keys=JSON.parse(new TextDecoder().decode(command.stdout));
    const key=keys.find((k:{name:string;type:string;api_key:string})=>k.name==='service_role'&&k.type==='legacy'&&k.api_key.startsWith('eyJ'))?.api_key;
    if(!key)throw new Error('No esta disponible la credencial administrativa para preparar fixtures');
    const payload=JSON.parse(atob(key.split('.')[1].replaceAll('-','+').replaceAll('_','/')));
    if(payload.role!=='service_role'||(payload.ref&&payload.ref!==ref))throw new Error('Credencial de otro proyecto o tipo');
    admin=createClient(config.SUPABASE_URL,key,{auth:{persistSession:false,autoRefreshToken:false}});
   }
  const bytes=crypto.getRandomValues(new Uint8Array(24));
  const password=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
  const email=`encargalo-${crypto.randomUUID()}@example.invalid`;
  const response=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{role:spec.role,name:spec.label,district:'Castilla'}});
  if(response.error||!response.data.user)throw new Error(`Preparacion Auth: ${response.error?.code??'error'}`);
  accounts.push({...spec,email,password,id:response.data.user.id});
  await Deno.writeTextFile(file,JSON.stringify(accounts,null,2));
 }
 const [a,b,c,d]=accounts;
 report.test_accounts=accounts.map(({id,role,label})=>({id,role,label}));
 const sessions=[];
 for(const account of [a,b,c,d,a]){
  const sdk=client();const result=await sdk.auth.signInWithPassword({email:account.email,password:account.password});
  check(!result.error&&result.data.user?.id===account.id,`Auth real: ${account.label}`);sessions.push(sdk);
 }
 const [owner,biz1,biz2,outsider,device2]=sessions;
 const anonymous=client();
 const anon=await anonymous.from('requests').select('id').limit(1);
 check(!!anon.error,'Anonimo no puede consultar solicitudes');
 const requestId=crypto.randomUUID(),photoId=crypto.randomUUID(),operation=crypto.randomUUID();
 report.request_id=requestId;
 const path=`${a.id}/${requestId}/${photoId}.jpg`;
 const image=await Deno.readFile(join(root,'.secrets/reference-fixture.jpg'));
 const upload=await owner.storage.from('references').upload(path,image,{contentType:'image/jpeg',upsert:false});
 check(!upload.error,'Subida JPEG autentica a Storage privado');
 const data={id:requestId,title:'[PRUEBA CLOUD] 30 polos para Castilla',detail:'Fixture de aceptacion: polos morados, estampado frontal y tallas variadas. No es un pedido de un comerciante real.',
  quantity:30,category_id:'estampado',district:'Castilla',desired_date:day(7),photos:[{id:photoId,object_path:path,mime:'image/jpeg',bytes:image.length}],
  delivery:{reference:'[PRUEBA] Referencia privada, coordenadas controladas, no lectura GPS',latitude:-5.198,longitude:-80.63,accuracy:15,captured_at:new Date().toISOString(),approximate:false}};
 const request=record(await rpc(owner,'publish_request',{p_data:data,p_operation:operation,p_expected_version:0}));
 const repeated=record(await rpc(owner,'publish_request',{p_data:data,p_operation:operation,p_expected_version:0}));
 check(request.version===1&&repeated.version===1,'Publicacion repetida no duplica ni incrementa version');
 const own=await owner.from('requests').select('id').eq('id',requestId);check(own.data?.length===1,'Un unico registro remoto');
 const wrong=await outsider.from('requests').select('id').eq('id',requestId);check(wrong.data?.length===0,'Otro cliente no ve la solicitud');
 const feed=await biz1.from('requests').select('id').eq('id',requestId);check(feed.data?.length===1,'Negocio de categoria compatible ve oportunidad');
 const hidden=await biz1.from('request_delivery').select('*').eq('request_id',requestId);check(hidden.data?.length===0,'Direccion precisa oculta antes del acuerdo');
 const photo=await biz1.storage.from('references').download(path);check(!photo.error&&photo.data.size===image.length,'Negocio autorizado descarga la referencia');
 const deniedPhoto=await outsider.storage.from('references').download(path);check(!!deniedPhoto.error,'Otra cuenta no descarga imagen privada');
 const escalation=await biz1.from('profiles').update({role:'cliente'}).eq('id',b.id);check(!!escalation.error,'El usuario no cambia su rol directamente');
 const forged=await biz1.rpc('publish_request',{p_data:{...data,id:crypto.randomUUID()},p_operation:crypto.randomUUID(),p_expected_version:0});check(!!forged.error,'Servidor rechaza publicacion de negocio');
 let realEvents=0;let eventResolve:(()=>void)|undefined;
 const eventPromise=new Promise<void>(resolve=>eventResolve=resolve);
 const session=(await owner.auth.getSession()).data.session;
 if(!session)throw new Error('Realtime requiere sesion de usuario');
 await owner.realtime.setAuth(session.access_token);
 const channel=owner.channel(`cloud-acceptance-${requestId}`).on('postgres_changes',{event:'INSERT',schema:'public',table:'quotes',filter:`request_id=eq.${requestId}`},()=>{realEvents++;eventResolve?.();});
 await new Promise<void>((resolve,reject)=>{
  const timeout=setTimeout(()=>reject(new Error('Realtime: PostgreSQL no confirmo suscripcion')),25000);
  channel.on('system',{},payload=>{
   if(payload.extension!=='postgres_changes')return;
   if(payload.status==='ok'){clearTimeout(timeout);report.realtime_postgres_ready=true;resolve();}
   if(payload.status==='error'){clearTimeout(timeout);reject(new Error('Realtime rechazo replicacion PostgreSQL'));}
  });
  channel.subscribe(status=>{
   if(['CHANNEL_ERROR','TIMED_OUT','CLOSED'].includes(status)){clearTimeout(timeout);reject(new Error(`Realtime: ${status}`));}
  });
 });
 const quoteId1=crypto.randomUUID(),quoteId2=crypto.randomUUID(),quoteOp=crypto.randomUUID();
 const base={request_id:requestId,promised_date:day(5),expires_at:new Date(Date.now()+2*86400000).toISOString(),conditions:'[PRUEBA] Incluye diseno y estampado; total acordado por 30 unidades.'};
 const q1=record(await rpc(biz1,'submit_quote',{p_data:{...base,id:quoteId1,total_cents:120000},p_operation:quoteOp,p_expected_version:0}));
 await rpc(biz1,'submit_quote',{p_data:{...base,id:quoteId1,total_cents:120000},p_operation:quoteOp,p_expected_version:0});
 const q2=record(await rpc(biz2,'submit_quote',{p_data:{...base,id:quoteId2,total_cents:115000},p_operation:crypto.randomUUID(),p_expected_version:0}));
 let eventTimer:ReturnType<typeof setTimeout>|undefined;
 await Promise.race([eventPromise,new Promise<void>((_,reject)=>eventTimer=setTimeout(()=>reject(new Error('No se recibio cotizacion por Realtime')),25000))]);
 if(eventTimer)clearTimeout(eventTimer);
 check(realEvents>0,'Cotizacion recibida por Realtime con JWT del cliente');report.realtime_quote_events=realEvents;
 await owner.removeChannel(channel);
 const list=await owner.from('quotes').select('id').eq('request_id',requestId);check(list.data?.length===2,'Cliente compara dos cotizaciones reales');
 const businessQuotes=await biz1.from('quotes').select('id').eq('request_id',requestId);check(businessQuotes.data?.length===1,'Negocio no ve propuestas privadas ajenas');
 const outboxDenied=await biz1.rpc('claim_push_batch');check(!!outboxDenied.error,'Un usuario no ejecuta el emisor de servidor');
 const attempts=[{sdk:owner,quote:q1.id,operation:crypto.randomUUID()},{sdk:device2,quote:q2.id,operation:crypto.randomUUID()}];
 const acceptances=await Promise.all(attempts.map(a=>a.sdk.rpc('accept_quote',{p_quote:a.quote,p_operation:a.operation})));
 report.concurrent_acceptance_initial=acceptances.map(r=>({status:r.status,code:r.error?.code,success:!r.error}));
 // A gateway timeout does not prove a transaction was rejected. Retry the same
 // idempotent operation to learn its committed outcome, then require a real
 // HTTP 409 business conflict for the losing proposal, not any gateway error.
 for(let i=0;i<acceptances.length;i++){
  if(acceptances[i].status>=500||acceptances[i].status===0){
   const a=attempts[i];
   acceptances[i]=await a.sdk.rpc('accept_quote',{p_quote:a.quote,p_operation:a.operation});
  }
 }
 report.concurrent_acceptance_resolved=acceptances.map(r=>({status:r.status,code:r.error?.code,success:!r.error}));
 const successes=acceptances.filter(r=>!r.error);check(successes.length===1,'Aceptacion concurrente produce exactamente un ganador');
 check(acceptances.filter(r=>r.error).every(r=>r.status===409&&r.error?.code==='PT409'),'Propuesta perdedora recibe HTTP 409 explicito, no timeout');
 let order=record(successes[0].data);report.order_id=order.id;report.concurrent_acceptance_errors=acceptances.filter(r=>r.error).map(r=>({code:r.error?.code,status:r.status}));
 const orders=await owner.from('orders').select('*').eq('request_id',requestId);check(orders.data?.length===1,'Restriccion remota: un pedido por solicitud');
 const retry=record(await rpc(owner,'accept_quote',{p_quote:order.quote_id,p_operation:crypto.randomUUID()}));check(retry.id===order.id,'Reintento de aceptacion devuelve el mismo pedido');
 const winner=order.business_id===b.id?biz1:biz2;const loser=order.business_id===b.id?biz2:biz1;
 const delivery=await winner.from('request_delivery').select('*').eq('request_id',requestId);check(delivery.data?.length===1&&delivery.data[0].accuracy===15,'Solo ganador obtiene entrega confirmada');
 const deniedDelivery=await loser.from('request_delivery').select('*').eq('request_id',requestId);check(deniedDelivery.data?.length===0,'No seleccionado no obtiene la ubicacion');
 const wrongOrder=await outsider.from('orders').select('*').eq('id',order.id);check(wrongOrder.data?.length===0,'Usuario ajeno no ve pedido');
 const nameBefore=order.business_name;
 await rpc(winner,'save_profile',{p_name:'[PRUEBA] Perfil comercial modificado',p_district:'Castilla',p_description:'Negocio de pruebas cloud autorizado',p_categories:['estampado'],p_phone:''});
 const snapshot=await owner.from('orders').select('business_name,total_cents,conditions').eq('id',order.id).single();check(snapshot.data?.business_name===nameBefore,'Instantanea comercial no cambia al editar perfil');
 const skip=await winner.rpc('transition_order',{p_order:order.id,p_status:'ready',p_operation:crypto.randomUUID(),p_expected_version:order.version});check(!!skip.error,'Servidor rechaza salto de estados');
 for(const status of ['production','ready'])order=record(await rpc(winner,'transition_order',{p_order:order.id,p_status:status,p_operation:crypto.randomUUID(),p_expected_version:order.version}));
 const businessDeliver=await winner.rpc('transition_order',{p_order:order.id,p_status:'delivered',p_operation:crypto.randomUUID(),p_expected_version:order.version});check(!!businessDeliver.error,'Negocio no confirma entrega en nombre del cliente');
 const paymentOperation=crypto.randomUUID();
 const payment=record(await rpc(owner,'simulate_order_payment',{p_order:order.id,p_amount:order.total_cents,p_approved:true,p_operation:paymentOperation,p_expected_version:order.version}));
 const repeatedPayment=record(await rpc(owner,'simulate_order_payment',{p_order:order.id,p_amount:order.total_cents,p_approved:true,p_operation:paymentOperation,p_expected_version:order.version}));
 check(payment.id===repeatedPayment.id&&payment.simulated===true,'Pago simulado persistente e idempotente, sin dinero real');
 const paidOrder=await owner.from('orders').select('*').eq('id',order.id).single();if(paidOrder.error)throw new Error('No se recupero pedido pagado');order=paidOrder.data;
 order=record(await rpc(owner,'transition_order',{p_order:order.id,p_status:'delivered',p_operation:crypto.randomUUID(),p_expected_version:order.version}));
 check(order.status==='delivered'&&order.version===5,'Cliente confirma Entregado mediante transicion autorizada y pago simulado');
 const history=await owner.from('order_history').select('*').eq('order_id',order.id);check(history.data?.length===4,'Historial de cuatro estados con actor y fecha de servidor');
 const notices=await owner.from('notifications').select('*').eq('request_id',requestId);check(notices.data?.length===4,'Notificaciones persistidas para cotizaciones y avances');
 const notice=notices.data![0];await rpc(outsider,'mark_notification_read',{p_id:notice.id});
 const unread=await owner.from('notifications').select('read_at').eq('id',notice.id).single();check(unread.data?.read_at===null,'Otra cuenta no marca lectura de avisos ajenos');
 await rpc(owner,'mark_notification_read',{p_id:notice.id});const read=await owner.from('notifications').select('read_at').eq('id',notice.id).single();check(!!read.data?.read_at,'Destinatario puede marcar su notificacion como leida');
 const catalog=await anonymous.from('locations').select('code').eq('region','Piura');
 check(!catalog.error&&(catalog.data?.length??0)>50,'Catalogo territorial real consultable por API publica sin datos personales');
 await rpc(owner,'save_profile_details',{p_data:{name:a.label,location_code:'200104',description:'',categories:[],phone:'999111222',contact_name:'[PRUEBA] Contacto autorizado',address_reference:'[PRUEBA] Referencia personal que no debe compartirse'}});
 const ownProfile=await owner.from('profiles').select('location_code,district').eq('id',a.id).single();
 check(ownProfile.data?.location_code==='200104'&&ownProfile.data.district==='Castilla','Perfil completo persiste ubigeo validado en PostgreSQL');
 const contact=await rpc(winner,'order_contact',{p_order:order.id});
 check(contact.phone==='999111222'&&Object.keys(contact).sort().join(',')==='contact_name,phone','Contraparte solo obtiene contacto minimo del acuerdo, no domicilio personal ni correo');
 const deniedContact=await outsider.rpc('order_contact',{p_order:order.id});
 check(deniedContact.error?.code==='42501','Cuenta ajena no consulta contacto del acuerdo');
 const invalidLocation=await owner.rpc('publish_request',{p_data:{...data,id:crypto.randomUUID(),photos:[],district:'Distrito inventado fuera del catalogo'},p_operation:crypto.randomUUID(),p_expected_version:0});
 check(!!invalidLocation.error,'La RPC anterior tampoco permite evadir el catalogo con distritos inventados');
 const overviewStart=performance.now();
 const overview=await rpc(owner,'home_overview',{});
 report.home_overview_ms=Math.round(performance.now()-overviewStart);
 check(overview.requests.every((r:{owner_id:string})=>r.owner_id===a.id)&&overview.orders.every((o:{client_id:string})=>o.client_id===a.id),'Inicio agregado solo contiene datos autorizados del cliente');
 async function makeCommerceOrder(label:string){
  const id=crypto.randomUUID();
  const published=record(await rpc(owner,'publish_request_v2',{p_data:{...data,id,title:`[PRUEBA COMERCIO] ${label}`,photos:[],location_code:'200104',specifications:{material:'Algodon',dimensions:'Tallas variadas',delivery_mode:'recojo'}},p_operation:crypto.randomUUID(),p_expected_version:0}));
  check(published.location_code==='200104'&&published.district==='Castilla','Solicitud enriquecida conserva ubigeo y especificaciones reales');
  const quote=record(await rpc(biz1,'submit_quote',{p_data:{...base,id:crypto.randomUUID(),request_id:id,total_cents:10000,deposit_cents:5000},p_operation:crypto.randomUUID(),p_expected_version:0}));
  return record(await rpc(owner,'accept_quote',{p_quote:quote.id,p_operation:crypto.randomUUID()}));
 }
 const before=await makeCommerceOrder('cancelacion antes de producir');
 await rpc(owner,'simulate_order_payment',{p_order:before.id,p_amount:3000,p_approved:true,p_operation:crypto.randomUUID(),p_expected_version:1});
 const beforeOp=crypto.randomUUID();
 const args={p_order:before.id,p_reason:'[PRUEBA] Cambio de fecha del evento',p_retained:0,p_operation:beforeOp,p_expected_version:2};
 const firstCancel=record(await rpc(owner,'request_order_cancellation',args));
 const retryCancel=record(await rpc(owner,'request_order_cancellation',args));
 check(firstCancel.id===retryCancel.id,'Cancelacion previa idempotente');
 const beforeState=await owner.from('orders').select('status,paid_cents').eq('id',before.id).single();
 const beforeRefunds=await owner.from('order_payments').select('amount_cents').eq('order_id',before.id).eq('kind','refund');
 check(beforeState.data?.status==='cancelled'&&beforeState.data.paid_cents===0&&beforeRefunds.data?.length===1&&beforeRefunds.data[0].amount_cents===3000,'Antes de produccion se cancela y devuelve todo el pago simulado una sola vez');
 const producing=await makeCommerceOrder('cancelacion bilateral en produccion');
 const blockedProduction=await biz1.rpc('transition_order',{p_order:producing.id,p_status:'production',p_operation:crypto.randomUUID(),p_expected_version:1});
 check(blockedProduction.error?.code==='PT409','No se inicia produccion sin adelanto simulado pactado');
 await rpc(owner,'simulate_order_payment',{p_order:producing.id,p_amount:5000,p_approved:false,p_operation:crypto.randomUUID(),p_expected_version:1});
 const declinedState=await owner.from('orders').select('paid_cents,version').eq('id',producing.id).single();
 check(declinedState.data?.paid_cents===0&&declinedState.data.version===1,'Pago simulado rechazado no aumenta el saldo pagado');
 await rpc(owner,'simulate_order_payment',{p_order:producing.id,p_amount:5000,p_approved:true,p_operation:crypto.randomUUID(),p_expected_version:1});
 await rpc(biz1,'transition_order',{p_order:producing.id,p_status:'production',p_operation:crypto.randomUUID(),p_expected_version:2});
 const proposal=record(await rpc(owner,'request_order_cancellation',{p_order:producing.id,p_reason:'[PRUEBA] Cancelacion con retencion de materiales',p_retained:1000,p_operation:crypto.randomUUID(),p_expected_version:3}));
 const selfResolve=await owner.rpc('resolve_order_cancellation',{p_cancellation:proposal.id,p_decision:'accepted',p_operation:crypto.randomUUID()});
 check(selfResolve.error?.code==='42501','El solicitante no puede aprobar su propia retencion');
 const strangerResolve=await outsider.rpc('resolve_order_cancellation',{p_cancellation:proposal.id,p_decision:'accepted',p_operation:crypto.randomUUID()});
 check(strangerResolve.error?.code==='42501','Una cuenta ajena no resuelve cancelaciones');
 const blockedAdvance=await biz1.rpc('transition_order',{p_order:producing.id,p_status:'ready',p_operation:crypto.randomUUID(),p_expected_version:4});
 check(blockedAdvance.error?.code==='PT409','Cancelacion pendiente bloquea cambios de estado hasta acuerdo o rechazo');
 const resolveOp=crypto.randomUUID();const resolution={p_cancellation:proposal.id,p_decision:'accepted',p_operation:resolveOp};
 await rpc(biz1,'resolve_order_cancellation',resolution);await rpc(biz1,'resolve_order_cancellation',resolution);
 const finalCancel=await owner.from('orders').select('status,paid_cents,total_cents,deposit_cents').eq('id',producing.id).single();
 const finalRefunds=await owner.from('order_payments').select('amount_cents').eq('order_id',producing.id).eq('kind','refund');
 check(finalCancel.data?.status==='cancelled'&&finalCancel.data.paid_cents===1000&&finalRefunds.data?.length===1&&finalRefunds.data[0].amount_cents===4000,'Cancelacion bilateral conserva solo retencion acordada y devuelve resto simulado atomico');
 const strangerPayments=await outsider.from('order_payments').select('id').eq('order_id',producing.id);
 const strangerCancellations=await outsider.from('order_cancellations').select('id').eq('order_id',producing.id);
 check(strangerPayments.data?.length===0&&strangerCancellations.data?.length===0,'RLS protege pagos y cancelaciones de cuentas ajenas');
 const cancelledContact=await owner.rpc('order_contact',{p_order:producing.id});
 check(cancelledContact.error?.code==='42501','Un acuerdo cancelado ya no expone el contacto de la contraparte');
 report.commerce_fixture_orders=[before.id,producing.id];report.payments_are_simulated=true;
 report.result='PASS';
}catch(e){report.result='FAIL';report.error=e instanceof Error?e.message:'Error de prueba';}
finally{
 for(const c of clients){await c.removeAllChannels();await c.auth.signOut({scope:'local'});}
 await admin?.auth.signOut({scope:'local'});
 const evidence=join(root,'../encargalo_documentacion/evidencias');
 const current=join(evidence,'pruebas-cloud.json');
 try{
  const prior=await Deno.readTextFile(current);
  const date=JSON.parse(prior).date.replaceAll(/[^0-9A-Za-z]/g,'-');
  await Deno.writeTextFile(join(evidence,`pruebas-cloud-${date}.json`),prior,{createNew:true});
 }catch(e){if(!(e instanceof Deno.errors.NotFound)&&!(e instanceof Deno.errors.AlreadyExists))throw e;}
 await Deno.writeTextFile(current,JSON.stringify(report,null,2));
 console.log(JSON.stringify(report,null,2));
}
if(report.result!=='PASS')Deno.exit(1);
