-- Encárgalo: PostgreSQL hospedado en Supabase Free.
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;
revoke all on schema private from public;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 role text not null check(role in('cliente','negocio')),
 name text not null check(length(name) between 2 and 100),
 district text not null default 'Piura', description text not null default '' check(length(description)<=2000),
 categories text[] not null default '{}', updated_at timestamptz not null default now()
);
create table public.profile_contacts(owner_id uuid primary key references public.profiles(id) on delete cascade,
 phone text not null default '' check(length(phone)<=30));
create table public.categories(id text primary key,name text not null);
insert into public.categories values('estampado','Estampado'),('bordado','Bordado'),('impresion','Impresión'),('personalizados','Otros personalizados');
create table public.requests (
 id uuid primary key, owner_id uuid not null references public.profiles(id),
 title text not null check(length(title) between 3 and 120), detail text not null check(length(detail) between 10 and 5000),
 quantity integer not null check(quantity between 1 and 100000), category_id text not null references public.categories(id),
 district text not null check(length(district) between 2 and 100), desired_date date not null,
 status text not null default 'open' check(status in('open','awarded','deleted')), version integer not null default 1,
 last_operation uuid not null, quote_count integer not null default 0 check(quote_count>=0),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.request_delivery (
 request_id uuid primary key references public.requests(id) on delete cascade,
 reference text not null default '' check(length(reference)<=1000),
 latitude double precision check(latitude between -90 and 90), longitude double precision check(longitude between -180 and 180),
 accuracy double precision check(accuracy>=0), captured_at timestamptz, approximate boolean not null default false,
 check((latitude is null and longitude is null and accuracy is null and captured_at is null)
 or(latitude is not null and longitude is not null and accuracy is not null and captured_at is not null))
);
create table public.request_photos (
 id uuid primary key, request_id uuid not null references public.requests(id) on delete cascade,
 object_path text not null unique, mime text not null check(mime in('image/jpeg','image/png','image/webp')),
 bytes integer not null check(bytes between 1 and 2097152),position integer not null check(position between 0 and 2), unique(request_id,position)
);
create table public.quotes (
 id uuid primary key,request_id uuid not null references public.requests(id),business_id uuid not null references public.profiles(id),
 total_cents bigint not null check(total_cents between 1 and 100000000),quantity integer not null check(quantity>0),
 promised_date date not null,expires_at timestamptz not null,conditions text not null check(length(conditions) between 5 and 3000),
 status text not null default 'sent' check(status in('sent','accepted','not_selected')),version integer not null default 1,
 last_operation uuid not null,created_at timestamptz not null default now(),unique(request_id,business_id)
);
create table public.orders (
 id uuid primary key default gen_random_uuid(),request_id uuid not null unique references public.requests(id),
 quote_id uuid not null unique references public.quotes(id),client_id uuid not null references public.profiles(id),
 business_id uuid not null references public.profiles(id),title text not null,total_cents bigint not null,quantity integer not null,
 promised_date date not null,conditions text not null,business_name text not null,
 status text not null default 'confirmed' check(status in('confirmed','production','ready','delivered')),
 version integer not null default 1,last_operation uuid not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.order_history (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id),
 actor_id uuid not null references public.profiles(id),previous_status text,new_status text not null,created_at timestamptz not null default now(),unique(order_id,new_status)
);
create table public.notifications (
 id uuid primary key default gen_random_uuid(),recipient_id uuid not null references public.profiles(id) on delete cascade,
 event_key text not null unique,title text not null,body text not null,request_id uuid references public.requests(id),
 order_id uuid references public.orders(id),read_at timestamptz,created_at timestamptz not null default now()
);
create table public.device_tokens (
 device_id uuid primary key,owner_id uuid not null references public.profiles(id) on delete cascade,
 token text not null unique check(length(token) between 20 and 4096),updated_at timestamptz not null default now()
);
create table public.push_outbox (
 id uuid primary key references public.notifications(id) on delete cascade,attempts integer not null default 0,
 available_at timestamptz not null default now(),lease_until timestamptz,sent_at timestamptz,last_error text
);
create index requests_owner on public.requests(owner_id,created_at desc);
create index requests_feed on public.requests(category_id,status,created_at desc);
create index requests_district on public.requests(district,status);
create index quotes_business on public.quotes(business_id,created_at desc);
create index quotes_request on public.quotes(request_id,status);
create index orders_client on public.orders(client_id,status,created_at desc);
create index orders_business on public.orders(business_id,status,promised_date);
create index history_order on public.order_history(order_id,created_at);
create index notifications_recipient on public.notifications(recipient_id,created_at desc);
create index outbox_pending on public.push_outbox(available_at) where sent_at is null;

create function public.can_read_request(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.requests r where r.id=p_id and(r.owner_id=auth.uid()
 or exists(select 1 from public.orders o where o.request_id=r.id and o.business_id=auth.uid())
 or(r.status='open' and r.owner_id<>auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='negocio' and r.category_id=any(p.categories)))))
$$;
create function public.can_read_delivery(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.requests where id=p_id and owner_id=auth.uid())
 or exists(select 1 from public.orders where request_id=p_id and business_id=auth.uid())
$$;
create function public.can_read_photo(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.request_photos p where p.object_path=p_path and public.can_read_request(p.request_id))
$$;
create function private.on_signup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if coalesce(new.raw_user_meta_data->>'role','') not in('cliente','negocio') then raise exception 'Tipo de cuenta inválido'; end if;
 insert into public.profiles(id,role,name,district,categories) values(new.id,new.raw_user_meta_data->>'role',trim(new.raw_user_meta_data->>'name'),
 coalesce(nullif(trim(new.raw_user_meta_data->>'district'),''),'Piura'),case when new.raw_user_meta_data->>'role'='negocio' then array['estampado'] else '{}'::text[] end);
 insert into public.profile_contacts(owner_id) values(new.id); return new;
end $$;
create trigger auth_profile after insert on auth.users for each row execute function private.on_signup();
create function public.save_profile(p_name text,p_district text,p_description text,p_categories text[],p_phone text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sesión requerida' using errcode='42501'; end if;
 if exists(select 1 from unnest(p_categories) c where not exists(select 1 from public.categories where id=c)) then raise exception 'Categoría inválida'; end if;
 if(select role from public.profiles where id=auth.uid())='negocio' and cardinality(p_categories)=0 then raise exception 'Seleccione al menos una categoría'; end if;
 update public.profiles set name=trim(p_name),district=trim(p_district),description=p_description,categories=p_categories,updated_at=now() where id=auth.uid();
 update public.profile_contacts set phone=p_phone where owner_id=auth.uid();
end $$;
create function public.publish_request(p_data jsonb,p_operation uuid,p_expected_version integer)
returns public.requests language plpgsql security definer set search_path='' as $$
declare r public.requests;d jsonb;photo jsonb;pos integer:=0;rid uuid:=(p_data->>'id')::uuid;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='cliente') then raise exception 'Solo un cliente puede publicar' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(rid::text,0));
 select * into r from public.requests where id=rid for update;
 if found then
 if r.owner_id<>auth.uid() then raise exception 'Sin autorización' using errcode='42501'; end if;
 if r.last_operation=p_operation then return r; end if;
 if r.status<>'open' or r.version is distinct from p_expected_version then raise exception 'Conflicto: recargue la solicitud' using errcode='40001'; end if;
 if exists(select 1 from public.quotes where request_id=rid) then raise exception 'Una solicitud cotizada no se edita; se puede cancelar'; end if;
 elsif p_expected_version is distinct from 0 then raise exception 'Solicitud ausente' using errcode='P0002'; end if;
 if(p_data->>'desired_date')::date<(now() at time zone 'America/Lima')::date then raise exception 'Fecha vencida'; end if;
 if jsonb_typeof(p_data->'photos')<>'array' or jsonb_array_length(p_data->'photos')>3 then raise exception 'Máximo tres fotos'; end if;
 insert into public.requests(id,owner_id,title,detail,quantity,category_id,district,desired_date,last_operation)
 values(rid,auth.uid(),trim(p_data->>'title'),trim(p_data->>'detail'),(p_data->>'quantity')::integer,p_data->>'category_id',trim(p_data->>'district'),(p_data->>'desired_date')::date,p_operation)
 on conflict(id) do update set title=excluded.title,detail=excluded.detail,quantity=excluded.quantity,category_id=excluded.category_id,
 district=excluded.district,desired_date=excluded.desired_date,version=public.requests.version+1,last_operation=p_operation,updated_at=now() returning * into r;
 d:=p_data->'delivery';
 insert into public.request_delivery(request_id,reference,latitude,longitude,accuracy,captured_at,approximate)
 values(rid,coalesce(d->>'reference',''),(d->>'latitude')::double precision,(d->>'longitude')::double precision,(d->>'accuracy')::double precision,
 (d->>'captured_at')::timestamptz,coalesce((d->>'approximate')::boolean,false))
 on conflict(request_id) do update set reference=excluded.reference,latitude=excluded.latitude,longitude=excluded.longitude,
 accuracy=excluded.accuracy,captured_at=excluded.captured_at,approximate=excluded.approximate;
 delete from public.request_photos where request_id=rid;
 for photo in select value from jsonb_array_elements(p_data->'photos') loop
 if photo->>'object_path'<>auth.uid()::text||'/'||rid::text||'/'||(photo->>'id')||'.jpg' then raise exception 'Ruta de foto inválida'; end if;
 if not exists(select 1 from storage.objects where bucket_id='references' and name=photo->>'object_path' and(metadata->>'size')::bigint=(photo->>'bytes')::bigint) then raise exception 'Foto no confirmada en Storage'; end if;
 insert into public.request_photos(id,request_id,object_path,mime,bytes,position) values((photo->>'id')::uuid,rid,photo->>'object_path',photo->>'mime',(photo->>'bytes')::integer,pos);pos:=pos+1;
 end loop;return r;
end $$;
create function public.delete_request(p_id uuid,p_operation uuid,p_expected_version integer)
returns void language plpgsql security definer set search_path='' as $$
declare r public.requests;
begin
 select * into r from public.requests where id=p_id for update;
 if r.owner_id is distinct from auth.uid() then raise exception 'Sin autorización' using errcode='42501'; end if;
 if r.status='deleted' then return; end if;
 if r.status<>'open' or r.version is distinct from p_expected_version then raise exception 'Conflicto o pedido confirmado' using errcode='40001'; end if;
 update public.requests set status='deleted',version=version+1,last_operation=p_operation,updated_at=now() where id=p_id;
 update public.quotes set status='not_selected' where request_id=p_id;
end $$;
create function private.notify(p_recipient uuid,p_key text,p_title text,p_body text,p_request uuid,p_order uuid)
returns void language plpgsql security definer set search_path='' as $$
declare nid uuid;
begin
 insert into public.notifications(recipient_id,event_key,title,body,request_id,order_id) values(p_recipient,p_key,p_title,p_body,p_request,p_order)
 on conflict(event_key) do nothing returning id into nid;
 if nid is not null then insert into public.push_outbox(id) values(nid); end if;
end $$;
create function public.submit_quote(p_data jsonb,p_operation uuid,p_expected_version integer)
returns public.quotes language plpgsql security definer set search_path='' as $$
declare r public.requests;q public.quotes;
begin
 select * into r from public.requests where id=(p_data->>'request_id')::uuid for update;
 if not found or r.status<>'open' or r.owner_id=auth.uid() or not public.can_read_request(r.id) then raise exception 'No se puede cotizar esta solicitud' using errcode='42501'; end if;
 if not exists(select 1 from public.profiles where id=auth.uid() and role='negocio') then raise exception 'Se requiere negocio' using errcode='42501'; end if;
 select * into q from public.quotes where request_id=r.id and business_id=auth.uid() for update;
 if found then
 if q.last_operation=p_operation then return q; end if;
 if q.version is distinct from p_expected_version then raise exception 'Cotización modificada en otro dispositivo' using errcode='40001'; end if;
 elsif p_expected_version is distinct from 0 then raise exception 'Cotización ausente'; end if;
 if(p_data->>'promised_date')::date<(now() at time zone 'America/Lima')::date or(p_data->>'promised_date')::date>r.desired_date or(p_data->>'expires_at')::timestamptz<=now() then raise exception 'Plazo o vigencia inválidos'; end if;
 insert into public.quotes(id,request_id,business_id,total_cents,quantity,promised_date,expires_at,conditions,last_operation)
 values(coalesce(q.id,(p_data->>'id')::uuid),r.id,auth.uid(),(p_data->>'total_cents')::bigint,r.quantity,(p_data->>'promised_date')::date,(p_data->>'expires_at')::timestamptz,p_data->>'conditions',p_operation)
 on conflict(request_id,business_id) do update set total_cents=excluded.total_cents,promised_date=excluded.promised_date,expires_at=excluded.expires_at,
 conditions=excluded.conditions,last_operation=p_operation,version=public.quotes.version+1 returning * into q;
 if q.version=1 then update public.requests set quote_count=quote_count+1 where id=r.id; end if;
 perform private.notify(r.owner_id,'quote:'||q.id||':'||q.version,'Nueva cotización','Un negocio ha enviado una propuesta para '||r.title,r.id,null);return q;
end $$;
create function public.accept_quote(p_quote uuid,p_operation uuid) returns public.orders
language plpgsql security definer set search_path='' as $$
declare q public.quotes;r public.requests;o public.orders;
begin
 select * into q from public.quotes where id=p_quote;
 if not found then raise exception 'Cotización no disponible'; end if;
 select * into r from public.requests where id=q.request_id for update;
 if r.owner_id is distinct from auth.uid() then raise exception 'Sin autorización' using errcode='42501'; end if;
 select * into o from public.orders where request_id=r.id;
 if found then
 if o.quote_id=p_quote then return o; end if;
 raise exception 'Ya se aceptó otra cotización' using errcode='40001';end if;
 select * into q from public.quotes where id=p_quote;
 if r.status<>'open' or q.status<>'sent' or q.expires_at<=now() or q.promised_date<(now() at time zone 'America/Lima')::date then raise exception 'Propuesta vencida o no disponible'; end if;
 insert into public.orders(request_id,quote_id,client_id,business_id,title,total_cents,quantity,promised_date,conditions,business_name,last_operation)
 values(r.id,q.id,r.owner_id,q.business_id,r.title,q.total_cents,q.quantity,q.promised_date,q.conditions,(select name from public.profiles where id=q.business_id),p_operation) returning * into o;
 update public.requests set status='awarded',version=version+1,updated_at=now() where id=r.id;
 update public.quotes set status=case when id=q.id then 'accepted' else 'not_selected' end where request_id=r.id;
 insert into public.order_history(order_id,actor_id,new_status) values(o.id,auth.uid(),'confirmed');
 perform private.notify(o.business_id,'order:'||o.id||':confirmed','Cotización aceptada','Se confirmó el pedido '||r.title,r.id,o.id);return o;
end $$;
create function public.transition_order(p_order uuid,p_status text,p_operation uuid,p_expected_version integer)
returns public.orders language plpgsql security definer set search_path='' as $$
declare o public.orders;prev text;
begin
 select * into o from public.orders where id=p_order for update;
 if not found or auth.uid() is null or auth.uid() not in(o.client_id,o.business_id) then raise exception 'Sin autorización' using errcode='42501'; end if;
 if o.last_operation=p_operation then
 if o.status=p_status then return o; end if;
 raise exception 'Transición: la clave de operación ya se usó para otro estado';
 end if;
 if o.version is distinct from p_expected_version then raise exception 'Pedido actualizado; recargue' using errcode='40001'; end if;
 if not((auth.uid()=o.business_id and((o.status='confirmed' and p_status='production')or(o.status='production' and p_status='ready')))
 or(auth.uid()=o.client_id and o.status='ready' and p_status='delivered')) then raise exception 'Transición no permitida' using errcode='42501'; end if;
 prev:=o.status;
 update public.orders set status=p_status,version=version+1,last_operation=p_operation,updated_at=now() where id=p_order returning * into o;
 insert into public.order_history(order_id,actor_id,previous_status,new_status) values(o.id,auth.uid(),prev,p_status);
 perform private.notify(case when auth.uid()=o.client_id then o.business_id else o.client_id end,'order:'||o.id||':'||p_status,
 'Actualización del pedido',case p_status when 'production' then 'El pedido está en producción' when 'ready' then 'El pedido está listo' else 'El cliente confirmó la entrega' end,o.request_id,o.id);return o;
end $$;
create function public.register_device(p_device uuid,p_token text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sesión requerida' using errcode='42501'; end if;
 delete from public.device_tokens where token=p_token or(device_id=p_device and owner_id=auth.uid());
 insert into public.device_tokens(device_id,owner_id,token) values(p_device,auth.uid(),p_token)
 on conflict(device_id) do update set owner_id=auth.uid(),token=p_token,updated_at=now();
end $$;
create function public.mark_notification_read(p_id uuid) returns void language sql security definer set search_path='' as $$
 update public.notifications set read_at=coalesce(read_at,now()) where id=p_id and recipient_id=auth.uid()
$$;
create function public.claim_push_batch() returns setof public.notifications language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'Solo servidor' using errcode='42501'; end if;
 return query with picked as(select id from public.push_outbox where sent_at is null and available_at<=now() and(lease_until is null or lease_until<now())
 and attempts<10 order by available_at limit 20 for update skip locked),claimed as(update public.push_outbox b set attempts=b.attempts+1,lease_until=now()+interval '3 minutes'
 from picked p where b.id=p.id returning b.id)select n.* from public.notifications n join claimed c on c.id=n.id;
end $$;
create function public.finish_push(p_id uuid,p_error text default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'Solo servidor' using errcode='42501'; end if;
 update public.push_outbox set sent_at=case when p_error is null then now() else null end,last_error=left(p_error,200),lease_until=null,
 available_at=now()+make_interval(secs=>least(3600,(power(2,attempts)*30)::integer)) where id=p_id;
end $$;
alter table public.profiles enable row level security;
alter table public.profile_contacts enable row level security;
alter table public.categories enable row level security;
alter table public.requests enable row level security;
alter table public.request_delivery enable row level security;
alter table public.request_photos enable row level security;
alter table public.quotes enable row level security;
alter table public.orders enable row level security;
alter table public.order_history enable row level security;
alter table public.notifications enable row level security;
alter table public.device_tokens enable row level security;
alter table public.push_outbox enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or role='negocio');
create policy contacts_private on public.profile_contacts for select to authenticated using(owner_id=auth.uid());
create policy categories_read on public.categories for select to authenticated using(true);
create policy requests_read on public.requests for select to authenticated using(public.can_read_request(id));
create policy delivery_private on public.request_delivery for select to authenticated using(public.can_read_delivery(request_id));
create policy photos_read on public.request_photos for select to authenticated using(public.can_read_request(request_id));
create policy quotes_read on public.quotes for select to authenticated using(business_id=auth.uid() or exists(select 1 from public.requests r where r.id=request_id and r.owner_id=auth.uid()));
create policy orders_read on public.orders for select to authenticated using(auth.uid() in(client_id,business_id));
create policy history_read on public.order_history for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and auth.uid() in(o.client_id,o.business_id)));
create policy notifications_read on public.notifications for select to authenticated using(recipient_id=auth.uid());
create policy tokens_delete on public.device_tokens for delete to authenticated using(owner_id=auth.uid());
create policy tokens_read on public.device_tokens for select to authenticated using(owner_id=auth.uid());
revoke all on all tables in schema public from anon,authenticated;
grant select on public.profiles,public.profile_contacts,public.categories,public.requests,public.request_delivery,public.request_photos,
 public.quotes,public.orders,public.order_history,public.notifications,public.device_tokens to authenticated;
grant delete on public.device_tokens to authenticated;
grant select,delete on public.device_tokens to service_role;
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.can_read_request(uuid),public.can_read_delivery(uuid),public.can_read_photo(text),public.save_profile(text,text,text,text[],text),
 public.publish_request(jsonb,uuid,integer),public.delete_request(uuid,uuid,integer),public.submit_quote(jsonb,uuid,integer),public.accept_quote(uuid,uuid),
 public.transition_order(uuid,text,uuid,integer),public.register_device(uuid,text),public.mark_notification_read(uuid) to authenticated;
grant execute on function public.claim_push_batch(),public.finish_push(uuid,text) to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('references','references',false,2097152,array['image/jpeg','image/png','image/webp']);
create policy references_insert on storage.objects for insert to authenticated with check(bucket_id='references'
 and(storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles where id=auth.uid() and role='cliente'));
create policy references_read on storage.objects for select to authenticated using(bucket_id='references'
 and((storage.foldername(name))[1]=auth.uid()::text or public.can_read_photo(name)));
create policy references_delete on storage.objects for delete to authenticated using(bucket_id='references'
 and(storage.foldername(name))[1]=auth.uid()::text and not public.can_read_photo(name));
alter publication supabase_realtime add table public.requests,public.quotes,public.orders,public.order_history,public.notifications;
