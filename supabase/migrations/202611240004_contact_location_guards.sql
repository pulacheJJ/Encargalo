-- Canonicalize legacy request writes too: the old RPC must not bypass ubigeo.
create function private.validate_request_location() returns trigger language plpgsql set search_path='' as $$
declare location public.locations;matches integer;matched text;
begin
 if tg_op='UPDATE' then
  if new.location_code is not distinct from old.location_code and lower(new.district)<>lower(old.district) then new.location_code:=null; end if;
 end if;
 if new.location_code is null then
  select count(*),min(code) into matches,matched from public.locations where region='Piura' and lower(district)=lower(trim(new.district));
  if matches<>1 then raise exception 'Selecciona el distrito desde el catalogo territorial'; end if;
  new.location_code:=matched;
 end if;
 select * into location from public.locations where code=new.location_code;
 if not found or location.region<>'Piura' then raise exception 'El punto de servicio debe pertenecer a Piura'; end if;
 new.district:=location.district;
 return new;
end $$;
create trigger validate_request_location before insert or update of district,location_code on public.requests for each row execute function private.validate_request_location();
revoke all on function private.validate_request_location() from public,anon,authenticated;

-- Share only the counterpart contact for an actual agreement, never their
-- personal address reference, auth email or a directory of user contacts.
create function public.order_contact(p_order uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.orders;other_id uuid;contact public.profile_contacts;
begin
 select * into o from public.orders where id=p_order;
 if not found or auth.uid() is null or auth.uid() not in(o.client_id,o.business_id) or o.status='cancelled' then raise exception 'Contacto no disponible para esta cuenta o estado' using errcode='42501'; end if;
 other_id:=case when auth.uid()=o.client_id then o.business_id else o.client_id end;
 select * into contact from public.profile_contacts where owner_id=other_id;
 return jsonb_build_object('contact_name',contact.contact_name,'phone',contact.phone);
end $$;
revoke execute on function public.order_contact(uuid) from public,anon;
grant execute on function public.order_contact(uuid) to authenticated;
