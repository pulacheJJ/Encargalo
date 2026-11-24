import {createClient} from '@supabase/supabase-js';
const cfg=JSON.parse(await Deno.readTextFile('config/public.json'));
const accounts=JSON.parse(await Deno.readTextFile('.secrets/cloud-test-accounts.json'));
const prior=JSON.parse(await Deno.readTextFile('../encargalo_documentacion/evidencias/pruebas-cloud.json'));
const options={auth:{persistSession:false,autoRefreshToken:false}};
const owner=createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY,options);
const biz=createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY,options);
const events:unknown[]=[];
try{
 for(const [sdk,a] of [[owner,accounts[0]],[biz,accounts[1]]] as const){const r=await sdk.auth.signInWithPassword({email:a.email,password:a.password});if(r.error)throw new Error('Auth del diagnostico fallo');}
 const session=(await owner.auth.getSession()).data.session!;
 await owner.realtime.setAuth(session.access_token);
 let resolveEvent:(()=>void)|undefined;
 const done=new Promise<void>(resolve=>resolveEvent=resolve);
 const channel=owner.channel(`probe-${crypto.randomUUID()}`).on('system',{},payload=>events.push({kind:'system',status:payload.status,message:payload.message,extension:payload.extension}))
 .on('postgres_changes',{event:'*',schema:'public',table:'quotes'},payload=>{events.push({kind:'quotes',event:payload.eventType});resolveEvent?.();})
 .on('postgres_changes',{event:'*',schema:'public',table:'notifications'},payload=>{events.push({kind:'notifications',event:payload.eventType});resolveEvent?.();});
 await new Promise<void>((resolve,reject)=>{const t=setTimeout(()=>reject(new Error('Subscribe timeout')),20000);channel.subscribe(status=>{events.push({kind:'status',status});if(status==='SUBSCRIBED'){clearTimeout(t);resolve();}if(status==='CHANNEL_ERROR'){clearTimeout(t);reject(new Error('Channel error'));}});});
 const q=await biz.from('quotes').select('*').eq('request_id',prior.request_id).single();if(q.error)throw new Error('No se encontro cotizacion propia');
 const change=await biz.rpc('submit_quote',{p_data:{id:q.data.id,request_id:q.data.request_id,total_cents:q.data.total_cents,promised_date:q.data.promised_date,expires_at:q.data.expires_at,conditions:`[PRUEBA REALTIME] ${new Date().toISOString()}`},p_operation:crypto.randomUUID(),p_expected_version:q.data.version});
 events.push({kind:'mutation',success:!change.error,code:change.error?.code});
 // Espera acotada de evento de prueba, no sondeo ni implementación productiva de tiempo real.
 let timer:ReturnType<typeof setTimeout>|undefined;
 await Promise.race([done,new Promise<void>(resolve=>timer=setTimeout(resolve,20000))]);if(timer)clearTimeout(timer);
}catch(e){events.push({kind:'error',message:e instanceof Error?e.message:'diagnostic error'});}
finally{await owner.removeAllChannels();await biz.removeAllChannels();await owner.auth.signOut({scope:'local'});await biz.auth.signOut({scope:'local'});await Deno.writeTextFile('../encargalo_documentacion/evidencias/realtime-cloud.json',JSON.stringify(events,null,2));console.log(JSON.stringify(events,null,2));}
