// Validates the deployed server credential and FCM permission without delivering
// a notification or claiming the outbox. Never prints credentials or headers.
const ref='thptipcvzevxuysjqvyq';
const config=JSON.parse(await Deno.readTextFile('config/public.json'));
if(config.SUPABASE_URL!==`https://${ref}.supabase.co`)throw new Error('Proyecto no autorizado');
const env=await Deno.readTextFile('.secrets/edge.env');
const secret=env.match(/^PUSH_DISPATCH_SECRET=([a-f0-9]+)\s*$/m)?.[1];
if(!secret)throw new Error('Secreto de despacho ausente');
const url=`${config.SUPABASE_URL}/functions/v1/dispatch-push`;
const report:Record<string,unknown>={date:new Date().toISOString(),project:ref,
 firebase_project:'encargalo-c54ec',android_delivery_verified:false};
try{
 const denied=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(30000)});
 report.unauthorized_status=denied.status;await denied.body?.cancel();
 if(denied.status!==401)throw new Error('La funcion debe rechazar peticiones sin secreto');
 const response=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json','x-dispatch-secret':secret},
  body:JSON.stringify({action:'validate'}),signal:AbortSignal.timeout(45000)});
 const data=await response.json();
 report.validation_status=response.status;
 report.validation=data;
 if(!response.ok||data.validated!==true||data.validate_only!==true)throw new Error('FCM no confirmo validacion del emisor');
 report.result='PASS';
}catch(e){report.result='FAIL';report.error=e instanceof Error?e.message:'Error de validacion';}
await Deno.writeTextFile('../encargalo_documentacion/evidencias/push-servidor.json',JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
if(report.result!=='PASS')Deno.exit(1);
