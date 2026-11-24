create table public.locations(code text primary key check(code~'^[0-9]{6}$'),region text not null,province text not null,district text not null);
create index locations_hierarchy on public.locations(region,province,district);
alter table public.locations enable row level security;
create policy locations_catalog on public.locations for select to anon,authenticated using(true);
revoke all on public.locations from anon,authenticated;
grant select on public.locations to anon,authenticated;
grant all on public.locations to service_role;
alter table public.profiles add column location_code text references public.locations(code);
alter table public.profiles add column business_address text not null default '' check(length(business_address)<=300);
alter table public.profiles add column business_hours text not null default '' check(length(business_hours)<=200);
alter table public.profiles add column website text not null default '' check(website='' or(website~'^https://[^[:space:]]+$' and length(website)<=300));
alter table public.profile_contacts add column contact_name text not null default '' check(length(contact_name)<=100);
alter table public.profile_contacts add column address_reference text not null default '' check(length(address_reference)<=500);
alter table public.requests add column location_code text references public.locations(code);
alter table public.requests add column specifications jsonb not null default '{}' check(jsonb_typeof(specifications)='object' and octet_length(specifications::text)<=5000);

create function public.save_profile_details(p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
declare location public.locations; r text;categories text[];
begin
 if auth.uid() is null then raise exception 'Sesion requerida' using errcode='42501'; end if;
 select * into location from public.locations where code=p_data->>'location_code';
 if not found then raise exception 'Selecciona una region, provincia y distrito validos'; end if;
 select role into r from public.profiles where id=auth.uid();
 if coalesce(p_data->>'phone','')!~'^\+?[0-9 ()-]{7,20}$' then raise exception 'Telefono de contacto invalido'; end if;
 if length(trim(coalesce(p_data->>'contact_name','')))<2 then raise exception 'Indica la persona de contacto'; end if;
 categories:=array(select jsonb_array_elements_text(coalesce(p_data->'categories','[]'::jsonb)));
 perform public.save_profile(p_data->>'name',location.district,coalesce(p_data->>'description',''),categories,p_data->>'phone');
 update public.profiles set location_code=location.code,
 business_address=case when r='negocio' then trim(coalesce(p_data->>'business_address','')) else '' end,
 business_hours=case when r='negocio' then trim(coalesce(p_data->>'business_hours','')) else '' end,
 website=case when r='negocio' then trim(coalesce(p_data->>'website','')) else '' end where id=auth.uid();
 update public.profile_contacts set contact_name=trim(p_data->>'contact_name'),address_reference=trim(coalesce(p_data->>'address_reference','')) where owner_id=auth.uid();
end $$;

create function private.on_signup_details() returns trigger language plpgsql security definer set search_path='' as $$
declare location public.locations; contact_phone text:=coalesce(new.raw_user_meta_data->>'phone','');
begin
 if new.raw_user_meta_data->>'location_code' is not null then
  select * into location from public.locations where code=new.raw_user_meta_data->>'location_code';
  if not found then raise exception 'Distrito no valido'; end if;
  update public.profiles set location_code=location.code,district=location.district where id=new.id;
 end if;
 if contact_phone<>'' and contact_phone!~'^\+?[0-9 ()-]{7,20}$' then raise exception 'Telefono invalido'; end if;
 update public.profile_contacts set phone=contact_phone,contact_name=left(coalesce(new.raw_user_meta_data->>'contact_name',new.raw_user_meta_data->>'name',''),100) where owner_id=new.id;
 return new;
end $$;
create trigger zz_encargalo_profile_details after insert on auth.users for each row execute function private.on_signup_details();
revoke all on function private.on_signup_details() from public,anon,authenticated;

create function public.publish_request_v2(p_data jsonb,p_operation uuid,p_expected_version integer)
returns public.requests language plpgsql security definer set search_path='' as $$
declare r public.requests; location public.locations; spec jsonb:=coalesce(p_data->'specifications','{}'::jsonb); item record;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='cliente') then raise exception 'Solo cliente' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_data->>'id',0));
 select * into r from public.requests where id=(p_data->>'id')::uuid for update;
 if found then
  if r.owner_id is distinct from auth.uid() then raise exception 'Sin autorizacion' using errcode='42501'; end if;
  if r.last_operation=p_operation then return r; end if;
 end if;
 select * into location from public.locations where code=p_data->>'location_code';
 if not found or location.region<>'Piura' then raise exception 'El punto de servicio debe pertenecer a Piura'; end if;
 if jsonb_typeof(spec)<>'object' then raise exception 'Especificaciones invalidas'; end if;
 for item in select * from jsonb_each(spec) loop
  if item.key not in('material','color','dimensions','design','finish','delivery_mode') or jsonb_typeof(item.value)<>'string' or length(item.value::text)>1000 then raise exception 'Campo de especificacion invalido'; end if;
 end loop;
 r:=public.publish_request(p_data||jsonb_build_object('district',location.district),p_operation,p_expected_version);
 update public.requests set location_code=location.code,specifications=spec where id=r.id returning * into r;
 return r;
end $$;
revoke execute on function public.save_profile_details(jsonb),public.publish_request_v2(jsonb,uuid,integer) from public,anon;
grant execute on function public.save_profile_details(jsonb),public.publish_request_v2(jsonb,uuid,integer) to authenticated;

create function public.home_overview() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where id=auth.uid();
 if not found then raise exception 'Sesion requerida' using errcode='42501'; end if;
 select jsonb_build_object(
  'requests_count',(select count(*) from public.requests r where r.status='open' and(r.owner_id=p.id or(p.role='negocio' and r.owner_id<>p.id and r.category_id=any(p.categories)))),
  'quotes_count',(select count(*) from public.quotes q join public.requests r on r.id=q.request_id where r.status='open' and q.status='sent' and(case when p.role='negocio' then q.business_id=p.id else r.owner_id=p.id end)),
  'orders_count',(select count(*) from public.orders o where o.status not in('delivered','cancelled') and p.id in(o.client_id,o.business_id)),
  'requests',coalesce((select jsonb_agg(items.item) from (
   select to_jsonb(r)||jsonb_build_object('request_photos',coalesce((select jsonb_agg(to_jsonb(ph)) from public.request_photos ph where ph.request_id=r.id),'[]'::jsonb)) as item
   from public.requests r where r.status='open' and(r.owner_id=p.id or(p.role='negocio' and r.owner_id<>p.id and r.category_id=any(p.categories))) order by r.created_at desc,r.id limit 3
  )items),'[]'::jsonb),
  'orders',coalesce((select jsonb_agg(to_jsonb(items)) from (select * from public.orders o where p.id in(o.client_id,o.business_id) and o.status not in('delivered','cancelled') order by o.promised_date,o.id limit 3)items),'[]'::jsonb)
 ) into result;
 return result;
end $$;
revoke execute on function public.home_overview() from public,anon;
grant execute on function public.home_overview() to authenticated;
