-- Payments are an explicitly simulated ledger. No real wallet, funds or card.
alter table public.quotes add column deposit_cents bigint not null default 0
 check(deposit_cents>=0 and deposit_cents<=total_cents/2);
alter table public.orders add column deposit_cents bigint not null default 0;
alter table public.orders add column paid_cents bigint not null default 0 check(paid_cents>=0 and paid_cents<=total_cents);
alter table public.orders add column payments_required boolean not null default false;
alter table public.orders drop constraint orders_status_check;
alter table public.orders add constraint orders_status_check check(status in('confirmed','production','ready','delivered','cancelled'));
create table public.order_payments(
 id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id),
 actor_id uuid not null references public.profiles(id),kind text not null check(kind in('payment','refund')),
 amount_cents bigint not null check(amount_cents>0),status text not null check(status in('approved','declined')),
 simulated boolean not null default true check(simulated),operation uuid not null unique,
 created_at timestamptz not null default now()
);
create table public.order_cancellations(
 id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id),
 requested_by uuid not null references public.profiles(id),reason text not null check(length(reason) between 10 and 1000),
 retained_cents bigint not null check(retained_cents>=0),status text not null check(status in('pending','accepted','rejected','withdrawn')),
 resolved_by uuid references public.profiles(id),operation uuid not null unique,resolution_operation uuid unique,
 created_at timestamptz not null default now(),resolved_at timestamptz
);
create unique index cancellation_pending on public.order_cancellations(order_id) where status='pending';
create index payments_order on public.order_payments(order_id,created_at);
create index cancellations_order on public.order_cancellations(order_id,created_at);
alter table public.order_payments enable row level security;
alter table public.order_cancellations enable row level security;
create policy payments_participants on public.order_payments for select to authenticated using(
 exists(select 1 from public.orders o where o.id=order_id and auth.uid() in(o.client_id,o.business_id)));
create policy cancellations_participants on public.order_cancellations for select to authenticated using(
 exists(select 1 from public.orders o where o.id=order_id and auth.uid() in(o.client_id,o.business_id)));
revoke all on public.order_payments,public.order_cancellations from anon,authenticated;
grant select on public.order_payments,public.order_cancellations to authenticated;

create or replace function public.submit_quote(p_data jsonb,p_operation uuid,p_expected_version integer)
returns public.quotes language plpgsql security definer set search_path='' as $$
declare r public.requests;q public.quotes; deposit bigint:=coalesce((p_data->>'deposit_cents')::bigint,0);
begin
 select * into r from public.requests where id=(p_data->>'request_id')::uuid for update;
 if not found or r.status<>'open' or r.owner_id=auth.uid() or not public.can_read_request(r.id) then raise exception 'No se puede cotizar esta solicitud' using errcode='42501'; end if;
 if not exists(select 1 from public.profiles where id=auth.uid() and role='negocio') then raise exception 'Se requiere negocio' using errcode='42501'; end if;
 select * into q from public.quotes where request_id=r.id and business_id=auth.uid() for update;
 if found then
  if q.last_operation=p_operation then
   if q.deposit_cents<>deposit then raise exception 'La operacion ya se utilizo con otro adelanto' using errcode='PT409'; end if;
   return q;
  end if;
  if q.version is distinct from p_expected_version then raise exception 'Cotizacion modificada; recarga' using errcode='PT409'; end if;
 elsif p_expected_version is distinct from 0 then raise exception 'Cotizacion ausente'; end if;
 if(p_data->>'promised_date')::date<(now() at time zone 'America/Lima')::date or(p_data->>'promised_date')::date>r.desired_date or(p_data->>'expires_at')::timestamptz<=now() then raise exception 'Plazo o vigencia invalidos'; end if;
 insert into public.quotes(id,request_id,business_id,total_cents,quantity,promised_date,expires_at,conditions,last_operation,deposit_cents)
 values(coalesce(q.id,(p_data->>'id')::uuid),r.id,auth.uid(),(p_data->>'total_cents')::bigint,r.quantity,(p_data->>'promised_date')::date,(p_data->>'expires_at')::timestamptz,p_data->>'conditions',p_operation,deposit)
 on conflict(request_id,business_id) do update set total_cents=excluded.total_cents,promised_date=excluded.promised_date,expires_at=excluded.expires_at,
 conditions=excluded.conditions,deposit_cents=excluded.deposit_cents,last_operation=p_operation,version=public.quotes.version+1 returning * into q;
 if q.version=1 then update public.requests set quote_count=quote_count+1 where id=r.id; end if;
 perform private.notify(r.owner_id,'quote:'||q.id||':'||q.version,'Nueva cotizacion','Un negocio envio una propuesta para '||r.title,r.id,null);
 return q;
end $$;

create or replace function public.accept_quote(p_quote uuid,p_operation uuid) returns public.orders
language plpgsql security definer set search_path='' as $$
declare q public.quotes;r public.requests;o public.orders;
begin
 select * into q from public.quotes where id=p_quote;
 if not found then raise exception 'Cotizacion no disponible'; end if;
 select * into r from public.requests where id=q.request_id for update;
 if r.owner_id is distinct from auth.uid() then raise exception 'Sin autorizacion' using errcode='42501'; end if;
 select * into o from public.orders where request_id=r.id;
 if found then
  if o.quote_id=p_quote then return o; end if;
  raise exception 'Ya se acepto otra cotizacion' using errcode='PT409';
 end if;
 select * into q from public.quotes where id=p_quote;
 if r.status<>'open' or q.status<>'sent' or q.expires_at<=now() or q.promised_date<(now() at time zone 'America/Lima')::date then raise exception 'Propuesta vencida o no disponible'; end if;
 insert into public.orders(request_id,quote_id,client_id,business_id,title,total_cents,quantity,promised_date,conditions,business_name,last_operation,deposit_cents,payments_required)
 values(r.id,q.id,r.owner_id,q.business_id,r.title,q.total_cents,q.quantity,q.promised_date,q.conditions,(select name from public.profiles where id=q.business_id),p_operation,q.deposit_cents,true) returning * into o;
 update public.requests set status='awarded',version=version+1,updated_at=now() where id=r.id;
 update public.quotes set status=case when id=q.id then 'accepted' else 'not_selected' end where request_id=r.id;
 insert into public.order_history(order_id,actor_id,new_status) values(o.id,auth.uid(),'confirmed');
 perform private.notify(o.business_id,'order:'||o.id||':confirmed','Cotizacion aceptada','Se confirmo el pedido '||r.title,r.id,o.id);
 return o;
end $$;

create function public.simulate_order_payment(p_order uuid,p_amount bigint,p_approved boolean,p_operation uuid,p_expected_version integer)
returns public.order_payments language plpgsql security definer set search_path='' as $$
declare o public.orders;payment public.order_payments;
begin
 select * into o from public.orders where id=p_order for update;
 if not found or o.client_id is distinct from auth.uid() then raise exception 'Solo el cliente paga' using errcode='42501'; end if;
 select * into payment from public.order_payments where operation=p_operation;
 if found then
  if payment.order_id<>o.id or payment.actor_id<>auth.uid() or payment.amount_cents is distinct from p_amount or payment.kind<>'payment' or payment.status is distinct from (case when p_approved then 'approved' else 'declined' end) then raise exception 'Operacion reutilizada' using errcode='PT409'; end if;
  return payment;
 end if;
 if p_approved is null or p_amount is null or p_amount<=0 or p_amount>o.total_cents-o.paid_cents then raise exception 'Importe invalido o excede saldo'; end if;
 if o.status in('cancelled','delivered') then raise exception 'Pedido cerrado' using errcode='PT409'; end if;
 if o.version is distinct from p_expected_version or exists(select 1 from public.order_cancellations where order_id=o.id and status='pending') then raise exception 'Recarga o resuelve la cancelacion pendiente' using errcode='PT409'; end if;
 insert into public.order_payments(order_id,actor_id,kind,amount_cents,status,operation)
 values(o.id,auth.uid(),'payment',p_amount,case when p_approved then 'approved' else 'declined' end,p_operation) returning * into payment;
 if p_approved then
  update public.orders set paid_cents=paid_cents+p_amount,version=version+1,updated_at=now() where id=o.id;
  perform private.notify(o.business_id,'payment:'||payment.id,'Pago simulado registrado','Se registro un pago de prueba; no representa dinero real.',o.request_id,o.id);
 end if;
 return payment;
end $$;

create or replace function public.transition_order(p_order uuid,p_status text,p_operation uuid,p_expected_version integer)
returns public.orders language plpgsql security definer set search_path='' as $$
declare o public.orders;prev text;
begin
 select * into o from public.orders where id=p_order for update;
 if not found or auth.uid() is null or auth.uid() not in(o.client_id,o.business_id) then raise exception 'Sin autorizacion' using errcode='42501'; end if;
 if o.last_operation=p_operation then
  if o.status=p_status then return o; end if;
  raise exception 'Operacion ya utilizada' using errcode='PT409';
 end if;
 if o.version is distinct from p_expected_version then raise exception 'Pedido actualizado; recargue' using errcode='PT409'; end if;
 if exists(select 1 from public.order_cancellations where order_id=o.id and status='pending') then raise exception 'Resuelve la cancelacion pendiente' using errcode='PT409'; end if;
 if not((auth.uid()=o.business_id and((o.status='confirmed' and p_status='production')or(o.status='production' and p_status='ready')))
 or(auth.uid()=o.client_id and o.status='ready' and p_status='delivered')) then raise exception 'Transicion no permitida' using errcode='42501'; end if;
 if o.payments_required and p_status='production' and o.paid_cents<o.deposit_cents then raise exception 'Falta completar el adelanto simulado' using errcode='PT409'; end if;
 if o.payments_required and p_status='delivered' and o.paid_cents<o.total_cents then raise exception 'Falta completar el pago simulado' using errcode='PT409'; end if;
 prev:=o.status;
 update public.orders set status=p_status,version=version+1,last_operation=p_operation,updated_at=now() where id=p_order returning * into o;
 insert into public.order_history(order_id,actor_id,previous_status,new_status) values(o.id,auth.uid(),prev,p_status);
 perform private.notify(case when auth.uid()=o.client_id then o.business_id else o.client_id end,'order:'||o.id||':'||p_status,
 'Actualizacion del pedido',case p_status when 'production' then 'El pedido esta en produccion' when 'ready' then 'El pedido esta listo' else 'El cliente confirmo la entrega' end,o.request_id,o.id);
 return o;
end $$;

create function private.apply_cancellation(p_id uuid,p_actor uuid,p_operation uuid) returns void
language plpgsql security definer set search_path='' as $$
declare c public.order_cancellations;o public.orders;refund bigint;
begin
 select * into c from public.order_cancellations where id=p_id;
 select * into o from public.orders where id=c.order_id for update;
 refund:=o.paid_cents-c.retained_cents;
 if refund<0 then raise exception 'Retencion mayor al pago'; end if;
 if refund>0 then
  insert into public.order_payments(order_id,actor_id,kind,amount_cents,status,operation)
  values(o.id,p_actor,'refund',refund,'approved',p_operation);
 end if;
 update public.orders set status='cancelled',paid_cents=c.retained_cents,version=version+1,last_operation=p_operation,updated_at=now() where id=o.id;
 insert into public.order_history(order_id,actor_id,previous_status,new_status) values(o.id,p_actor,o.status,'cancelled');
 perform private.notify(o.client_id,'cancel:'||c.id||':client','Pedido cancelado','Consulta el acuerdo y la devolucion simulada en tu pedido.',o.request_id,o.id);
 perform private.notify(o.business_id,'cancel:'||c.id||':business','Pedido cancelado','Consulta el acuerdo y la devolucion simulada en tu pedido.',o.request_id,o.id);
end $$;
revoke all on function private.apply_cancellation(uuid,uuid,uuid) from public,anon,authenticated;

create function public.request_order_cancellation(p_order uuid,p_reason text,p_retained bigint,p_operation uuid,p_expected_version integer)
returns public.order_cancellations language plpgsql security definer set search_path='' as $$
declare o public.orders;c public.order_cancellations;
begin
 select * into o from public.orders where id=p_order for update;
 if not found or auth.uid() is null or auth.uid() not in(o.client_id,o.business_id) then raise exception 'Sin autorizacion' using errcode='42501'; end if;
 select * into c from public.order_cancellations where operation=p_operation;
 if found then
  if c.order_id<>o.id or c.requested_by<>auth.uid() or c.reason is distinct from trim(p_reason) or c.retained_cents is distinct from p_retained then raise exception 'Operacion reutilizada' using errcode='PT409'; end if;
  return c;
 end if;
 if o.status not in('confirmed','production','ready') or o.version is distinct from p_expected_version then raise exception 'Pedido cerrado o actualizado' using errcode='PT409'; end if;
 if p_retained is null or p_retained<0 or p_retained>least(o.paid_cents,o.deposit_cents) or(o.status='confirmed' and p_retained<>0) then raise exception 'Retencion no permitida'; end if;
 if exists(select 1 from public.order_cancellations where order_id=o.id and status='pending') then raise exception 'Ya existe una solicitud pendiente' using errcode='PT409'; end if;
 insert into public.order_cancellations(order_id,requested_by,reason,retained_cents,status,operation,resolved_by,resolved_at)
 values(o.id,auth.uid(),trim(p_reason),p_retained,case when o.status='confirmed' then 'accepted' else 'pending' end,p_operation,
 case when o.status='confirmed' then auth.uid() end,case when o.status='confirmed' then now() end) returning * into c;
 if o.status='confirmed' then
  perform private.apply_cancellation(c.id,auth.uid(),p_operation);
 else
  update public.orders set version=version+1,updated_at=now() where id=o.id;
  perform private.notify(case when auth.uid()=o.client_id then o.business_id else o.client_id end,'cancel-request:'||c.id,'Solicitud de cancelacion','Revisa motivo y retencion propuesta; no hay cancelacion sin acuerdo.',o.request_id,o.id);
 end if;
 return c;
end $$;

create function public.resolve_order_cancellation(p_cancellation uuid,p_decision text,p_operation uuid)
returns public.order_cancellations language plpgsql security definer set search_path='' as $$
declare c public.order_cancellations;o public.orders;
begin
 select * into c from public.order_cancellations where id=p_cancellation;
 if not found then raise exception 'Solicitud no disponible'; end if;
 select * into o from public.orders where id=c.order_id for update;
 select * into c from public.order_cancellations where id=p_cancellation for update;
 if auth.uid() is null or auth.uid() not in(o.client_id,o.business_id) then raise exception 'Sin autorizacion' using errcode='42501'; end if;
 if c.resolution_operation=p_operation and c.resolved_by=auth.uid() and c.status=p_decision then return c; end if;
 if c.status<>'pending' or o.status not in('production','ready') then raise exception 'Solicitud ya resuelta' using errcode='PT409'; end if;
 if(p_decision='withdrawn' and auth.uid()<>c.requested_by)or(p_decision in('accepted','rejected') and auth.uid()=c.requested_by)or p_decision not in('accepted','rejected','withdrawn')or p_decision is null then raise exception 'Decision no autorizada' using errcode='42501'; end if;
 update public.order_cancellations set status=p_decision,resolved_by=auth.uid(),resolved_at=now(),resolution_operation=p_operation where id=c.id returning * into c;
 if p_decision='accepted' then perform private.apply_cancellation(c.id,auth.uid(),p_operation);
 else update public.orders set version=version+1,updated_at=now() where id=o.id;
 end if;
 perform private.notify(case when auth.uid()=o.client_id then o.business_id else o.client_id end,'cancel-resolve:'||c.id,'Respuesta a cancelacion','La solicitud de cancelacion tiene una respuesta. Revisa el pedido.',o.request_id,o.id);
 return c;
end $$;
revoke execute on function public.simulate_order_payment(uuid,bigint,boolean,uuid,integer),public.request_order_cancellation(uuid,text,bigint,uuid,integer),public.resolve_order_cancellation(uuid,text,uuid) from public,anon;
grant execute on function public.simulate_order_payment(uuid,bigint,boolean,uuid,integer),public.request_order_cancellation(uuid,text,bigint,uuid,integer),public.resolve_order_cancellation(uuid,text,uuid) to authenticated;
alter publication supabase_realtime add table public.order_payments,public.order_cancellations;
