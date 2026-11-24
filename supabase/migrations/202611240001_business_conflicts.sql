-- 40001 is reserved for genuine serialization failures, which PostgREST can
-- retry. A permanent business/version conflict must return HTTP 409 instead.
-- Keep deployed bodies, signatures, privileges, locks and RLS unchanged.
do $migration$
declare
 signature text;
 definition text;
begin
 foreach signature in array array[
  'public.publish_request(jsonb,uuid,integer)',
  'public.delete_request(uuid,uuid,integer)',
  'public.submit_quote(jsonb,uuid,integer)',
  'public.accept_quote(uuid,uuid)',
  'public.transition_order(uuid,text,uuid,integer)'
 ] loop
  definition := pg_get_functiondef(signature::regprocedure);
  if position('errcode=''40001''' in definition) = 0 then
   raise exception 'Expected business conflict missing in %', signature;
  end if;
  execute replace(definition, 'errcode=''40001''', 'errcode=''PT409''');
 end loop;
end
$migration$;
