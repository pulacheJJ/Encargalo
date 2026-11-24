// Static catalog provisioning only; never uses service_role for user actions.
import {createClient} from '@supabase/supabase-js';
const ref='thptipcvzevxuysjqvyq';
const config=JSON.parse(await Deno.readTextFile('config/public.json'));
if(config.SUPABASE_URL!==`https://${ref}.supabase.co`)throw new Error('Proyecto no autorizado');
const result=await new Deno.Command('cmd.exe',{args:['/d','/c','npm','exec','--yes','--package=supabase@3.3.0','--','supabase','projects','api-keys',`--remote=${ref}`,'--reveal','--output','json'],stdout:'piped',stderr:'piped'}).output();
if(!result.success)throw new Error('No se pudo autorizar catalogo');
const keys=JSON.parse(new TextDecoder().decode(result.stdout));
const key=keys.find((k:{name:string;type:string})=>k.name==='service_role'&&k.type==='legacy')?.api_key;
if(!key)throw new Error('Credencial administrativa ausente');
const db=createClient(config.SUPABASE_URL,key,{auth:{persistSession:false,autoRefreshToken:false}});
const rows=JSON.parse(await Deno.readTextFile('assets/locations/peru.json')).locations;
for(let i=0;i<rows.length;i+=200){
 const {error}=await db.from('locations').upsert(rows.slice(i,i+200),{onConflict:'code'});
 if(error)throw new Error(`Catalogo: ${error.code}`);
}
console.log(JSON.stringify({project:ref,seeded:rows.length,type:'catalogo territorial publico real; no usuarios ni direcciones personales'}));
