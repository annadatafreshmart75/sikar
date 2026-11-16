-- Delivery partners (riders), order assignment, status timeline, complaints

create table if not exists public.riders (
  email text primary key,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.riders enable row level security;
revoke all on public.riders from anon, authenticated;

alter table public.orders add column if not exists rider_email text references public.riders(email) on update cascade,
  add column if not exists status_times jsonb not null default '{}'::jsonb;
update public.orders set status_times = jsonb_build_object(status, created_at) where status_times = '{}'::jsonb;

create or replace function public.is_rider() returns boolean
language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.riders r join auth.users u on lower(u.email) = r.email
                 where u.id = auth.uid() and r.active)
$$;
revoke execute on function public.is_rider() from public, anon;
grant execute on function public.is_rider() to authenticated;

-- stamp the time of every status change
create or replace function public.stamp_status() returns trigger
language plpgsql set search_path to '' as $$
begin
  if tg_op = 'INSERT' then
    new.status_times := jsonb_build_object(new.status, now());
  elsif new.status is distinct from old.status then
    new.status_times := coalesce(old.status_times, '{}'::jsonb) || jsonb_build_object(new.status, now());
  end if;
  return new;
end $$;
drop trigger if exists orders_stamp_status on public.orders;
create trigger orders_stamp_status before insert or update of status on public.orders
  for each row execute function public.stamp_status();

-- rider: today's assigned orders. Address/phone only while the order is still open.
create or replace function public.rider_orders() returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare v_email text;
begin
  if not public.is_rider() then raise exception 'NOT_RIDER'; end if;
  select lower(email) into v_email from auth.users where id = auth.uid();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', o.id, 'items', o.items, 'total', o.total, 'pay_method', o.pay_method, 'paid', o.paid,
      'slot', o.slot, 'status', o.status, 'status_times', o.status_times, 'has_kit', o.has_kit,
      'name', split_part(o.name, ' ', 1),
      'address', case when o.status in ('delivered','cancelled') then null else o.address end,
      'landmark', case when o.status in ('delivered','cancelled') then null else o.landmark end,
      'phone', case when o.status in ('delivered','cancelled') then null else o.phone end
    ) order by (o.status in ('delivered','cancelled')), o.id)
    from public.orders o
    where o.rider_email = v_email
      and (o.status not in ('delivered','cancelled') or o.created_at > now() - interval '24 hours')
  ), '[]'::jsonb);
end $$;
revoke execute on function public.rider_orders() from public, anon;
grant execute on function public.rider_orders() to authenticated;

create or replace function public.rider_set_status(p_id bigint, p_status text, p_cash boolean default false) returns void
language plpgsql security definer set search_path to '' as $$
declare v_email text; o public.orders%rowtype;
begin
  if not public.is_rider() then raise exception 'NOT_RIDER'; end if;
  if p_status not in ('out_for_delivery','delivered') then raise exception 'BAD_STATUS'; end if;
  select lower(email) into v_email from auth.users where id = auth.uid();
  select * into o from public.orders where id = p_id and rider_email = v_email for update;
  if not found then raise exception 'NO_ORDER'; end if;
  if o.status in ('cancelled','delivered') then raise exception 'ORDER_CLOSED'; end if;
  update public.orders set status = p_status,
    paid = case when p_status = 'delivered' and o.pay_method = 'cod' and p_cash then true else paid end
  where id = p_id;
end $$;
revoke execute on function public.rider_set_status(bigint, text, boolean) from public, anon;
grant execute on function public.rider_set_status(bigint, text, boolean) to authenticated;

-- admin: manage riders and assign orders
create or replace function public.admin_riders() returns jsonb
language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return coalesce((select jsonb_agg(to_jsonb(r) order by r.active desc, r.name) from public.riders r), '[]'::jsonb);
end $$;
create or replace function public.admin_save_rider(p_email text, p_name text, p_active boolean) returns void
language plpgsql security definer set search_path to '' as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if coalesce(p_email,'') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or coalesce(trim(p_name),'') = '' then raise exception 'BAD_INPUT'; end if;
  insert into public.riders(email, name, active) values (lower(trim(p_email)), trim(p_name), p_active)
  on conflict (email) do update set name = excluded.name, active = excluded.active;
end $$;
create or replace function public.admin_assign_rider(p_id bigint, p_email text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_email is not null and not exists (select 1 from public.riders where email = lower(p_email) and active) then raise exception 'NO_RIDER'; end if;
  update public.orders set rider_email = lower(p_email),
    status = case when p_email is not null and status = 'placed' then 'confirmed' else status end
  where id = p_id and status not in ('delivered','cancelled');
  if not found then raise exception 'NO_ORDER'; end if;
end $$;
revoke execute on function public.admin_riders(), public.admin_save_rider(text, text, boolean), public.admin_assign_rider(bigint, text) from public, anon;
grant execute on function public.admin_riders(), public.admin_save_rider(text, text, boolean), public.admin_assign_rider(bigint, text) to authenticated;

-- customer complaints / feedback about a delivery
create table if not exists public.complaints (
  id bigint generated always as identity primary key,
  order_id bigint not null references public.orders(id),
  user_id uuid not null,
  message text not null,
  status text not null default 'open' check (status in ('open','resolved')),
  created_at timestamptz not null default now()
);
alter table public.complaints enable row level security;
revoke all on public.complaints from anon, authenticated;
grant select on public.complaints to authenticated;
drop policy if exists "own or admin complaints" on public.complaints;
create policy "own or admin complaints" on public.complaints for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

create or replace function public.submit_complaint(p_order bigint, p_message text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  if auth.uid() is null then raise exception 'LOGIN_REQUIRED'; end if;
  if length(trim(coalesce(p_message,''))) < 5 then raise exception 'TOO_SHORT'; end if;
  if not exists (select 1 from public.orders where id = p_order and user_id = auth.uid()) then raise exception 'NO_ORDER'; end if;
  if (select count(*) from public.complaints where user_id = auth.uid() and created_at > now() - interval '1 day') >= 5 then raise exception 'TOO_MANY'; end if;
  insert into public.complaints(order_id, user_id, message) values (p_order, auth.uid(), left(trim(p_message), 1000));
end $$;
create or replace function public.admin_resolve_complaint(p_id bigint) returns void
language plpgsql security definer set search_path to '' as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  update public.complaints set status = 'resolved' where id = p_id;
end $$;
revoke execute on function public.submit_complaint(bigint, text), public.admin_resolve_complaint(bigint) from public, anon;
grant execute on function public.submit_complaint(bigint, text), public.admin_resolve_complaint(bigint) to authenticated;
