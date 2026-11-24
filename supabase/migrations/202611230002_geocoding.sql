-- Caché y exclusión global: máximo una petición externa en curso por proyecto.
create table private.geocode_cache(query text primary key,result jsonb not null,expires_at timestamptz not null);
create table private.geocode_gate(id boolean primary key default true check(id),next_at timestamptz not null default now(),lease_until timestamptz);
insert into private.geocode_gate(id) values(true);
create function public.geocode_reserve(p_query text) returns jsonb language plpgsql security definer set search_path='' as $$
declare cached jsonb;gate private.geocode_gate;
begin
 if auth.role()<>'service_role' then raise exception 'Solo servidor' using errcode='42501'; end if;
 select result into cached from private.geocode_cache where query=p_query and expires_at>now();
 if found then return jsonb_build_object('cached',cached); end if;
 select * into gate from private.geocode_gate where id=true for update;
 if gate.next_at>now() or gate.lease_until>now() then return jsonb_build_object('busy',true); end if;
 update private.geocode_gate set next_at=now()+interval '2 seconds',lease_until=now()+interval '20 seconds' where id=true;
 return jsonb_build_object('reserved',true);
end $$;
create function public.geocode_finish(p_query text,p_result jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'Solo servidor' using errcode='42501'; end if;
 if p_result is not null then
 insert into private.geocode_cache(query,result,expires_at) values(p_query,p_result,now()+interval '7 days')
 on conflict(query) do update set result=excluded.result,expires_at=excluded.expires_at;
 end if;
 update private.geocode_gate set next_at=now()+interval '2 seconds',lease_until=null where id=true;
 delete from private.geocode_cache where expires_at<now();
end $$;
revoke all on function public.geocode_reserve(text),public.geocode_finish(text,jsonb) from public,anon,authenticated;
grant execute on function public.geocode_reserve(text),public.geocode_finish(text,jsonb) to service_role;
