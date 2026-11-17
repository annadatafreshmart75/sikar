-- Stores, distance-based delivery charge, customer pin, rider live location (17 Nov 2026)

-- ---------- settings ----------
create table if not exists public.app_settings (key text primary key, value jsonb not null, updated_at timestamptz default now());
alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon, authenticated;
insert into public.app_settings(key, value) values
  ('delivery', '{"free_first":2,"free_above":299,"default_fee":30,"road_factor":1.3,"max_km":null,"slabs":[]}')
on conflict (key) do nothing;

-- ---------- stores ----------
create table if not exists public.stores (
  id bigserial primary key,
  name text not null,
  address text,
  lat double precision not null,
  lng double precision not null,
  phone text,
  active boolean not null default true,
  created_at timestamptz default now()
);
alter table public.stores enable row level security;
revoke all on public.stores from anon, authenticated;

-- ---------- orders / profiles: pins ----------
alter table public.orders add column if not exists lat double precision;
alter table public.orders add column if not exists lng double precision;
alter table public.orders add column if not exists store_id bigint references public.stores(id);
alter table public.orders add column if not exists distance_km numeric(6,2);
alter table public.profiles add column if not exists lat double precision;
alter table public.profiles add column if not exists lng double precision;

-- ---------- rider live location ----------
create table if not exists public.rider_locations (
  email text primary key,
  lat double precision not null,
  lng double precision not null,
  acc real,
  heading real,
  at timestamptz not null default now()
);
alter table public.rider_locations enable row level security;
revoke all on public.rider_locations from anon, authenticated;

-- ---------- helpers ----------
create or replace function public.km_between(a_lat double precision, a_lng double precision, b_lat double precision, b_lng double precision)
returns double precision language sql immutable as $$
  select 6371 * 2 * asin(sqrt(power(sin(radians(b_lat - a_lat) / 2), 2)
       + cos(radians(a_lat)) * cos(radians(b_lat)) * power(sin(radians(b_lng - a_lng) / 2), 2)))
$$;

-- nearest active store + road-ish distance (straight line x road_factor)
create or replace function public.nearest_store(p_lat double precision, p_lng double precision)
returns table(store_id bigint, km numeric) language sql stable security definer set search_path = '' as $$
  select s.id, round((public.km_between(p_lat, p_lng, s.lat, s.lng)
         * coalesce((select (value->>'road_factor')::numeric from public.app_settings where key = 'delivery'), 1.3))::numeric, 2)
  from public.stores s where s.active and p_lat is not null and p_lng is not null
  order by public.km_between(p_lat, p_lng, s.lat, s.lng) limit 1
$$;
revoke all on function public.nearest_store(double precision, double precision) from public, anon, authenticated;

create or replace function public.free_deliveries_left(p_uid uuid, p_phone text)
returns int language sql stable security definer set search_path = '' as $$
  select greatest(0, coalesce((select (value->>'free_first')::int from public.app_settings where key = 'delivery'), 2)
    - (select count(*) from public.orders o
       where o.status <> 'cancelled' and (o.user_id = p_uid or (p_phone is not null and o.phone = p_phone))))::int
$$;
revoke all on function public.free_deliveries_left(uuid, text) from public, anon, authenticated;

-- fee rule: free while welcome deliveries remain, free at/above free_above, else slab by distance (or default_fee)
create or replace function public.delivery_fee_for(p_sub int, p_free_left int, p_km numeric)
returns int language plpgsql stable security definer set search_path = '' as $$
declare s jsonb; sl jsonb; fee int;
begin
  select value into s from public.app_settings where key = 'delivery';
  if p_free_left > 0 or p_sub >= coalesce((s->>'free_above')::int, 299) then return 0; end if;
  if p_km is null or jsonb_array_length(coalesce(s->'slabs', '[]')) = 0 then return coalesce((s->>'default_fee')::int, 30); end if;
  for sl in select * from jsonb_array_elements(s->'slabs') x order by (x->>'km')::numeric loop
    fee := (sl->>'fee')::int;
    if p_km <= (sl->>'km')::numeric then return fee; end if;
  end loop;
  return fee;  -- beyond the last slab: last slab's fee
end $$;
revoke all on function public.delivery_fee_for(int, int, numeric) from public, anon, authenticated;

-- ---------- customer: quote ----------
create or replace function public.delivery_quote(p_sub int, p_lat double precision default null, p_lng double precision default null, p_phone text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_free int; v_store bigint; v_km numeric; v_max numeric; v_name text;
begin
  v_free := case when v_uid is null then coalesce((select (value->>'free_first')::int from public.app_settings where key = 'delivery'), 2)
                 else public.free_deliveries_left(v_uid, (select phone from public.profiles where id = v_uid)) end;  -- p_phone ignored: no probing of other numbers
  select n.store_id, n.km into v_store, v_km from public.nearest_store(p_lat, p_lng) n;
  select name into v_name from public.stores where id = v_store;
  select (value->>'max_km')::numeric into v_max from public.app_settings where key = 'delivery';
  return jsonb_build_object('free_left', v_free, 'km', v_km, 'store', v_name,
    'out_of_area', v_max is not null and v_km is not null and v_km > v_max,
    'fee', public.delivery_fee_for(coalesce(p_sub, 0), v_free, v_km));
end $$;
revoke all on function public.delivery_quote(int, double precision, double precision, text) from public;
grant execute on function public.delivery_quote(int, double precision, double precision, text) to anon, authenticated;

create or replace function public.my_delivery_info()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); p public.profiles%rowtype;
begin
  if v_uid is null then return jsonb_build_object('free_left', 2); end if;
  select * into p from public.profiles where id = v_uid;
  return jsonb_build_object('free_left', public.free_deliveries_left(v_uid, p.phone), 'lat', p.lat, 'lng', p.lng);
end $$;
revoke all on function public.my_delivery_info() from public;
grant execute on function public.my_delivery_info() to anon, authenticated;

-- ---------- place_order with pin ----------
drop function if exists public.place_order(jsonb, text, text, text, text, text, text, text);
create or replace function public.place_order(p_items jsonb, p_slot text, p_pay text, p_name text, p_phone text, p_address text, p_landmark text, p_client_ref text,
  p_lat double precision default null, p_lng double precision default null)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v_uid uuid := auth.uid(); v_sub int := 0; v_mrp int := 0; v_fee int; v_total int; v_kit boolean := false;
  v_items jsonb := '[]'::jsonb; it jsonb; pr public.products%rowtype; op jsonb; v_qty int; v_id bigint; v_bal int; v_exist public.orders%rowtype;
  v_free int; v_store bigint; v_km numeric; v_max numeric;
begin
  if v_uid is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_pay not in ('wallet','cod','upi') then raise exception 'BAD_INPUT'; end if;
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_address),'') = '' or coalesce(p_phone,'') !~ '^[6-9][0-9]{9}$' then raise exception 'BAD_DETAILS'; end if;
  if (p_lat is null) <> (p_lng is null) or (p_lat is not null and (p_lat not between 6 and 38 or p_lng not between 68 and 98)) then raise exception 'BAD_LOCATION'; end if;
  if p_client_ref is not null then
    select * into v_exist from public.orders where user_id = v_uid and client_ref = p_client_ref;
    if found then return jsonb_build_object('id', v_exist.id, 'total', v_exist.total, 'fee', v_exist.delivery_fee, 'subtotal', v_exist.subtotal, 'status', v_exist.status, 'kit', v_exist.has_kit, 'items', v_exist.items, 'duplicate', true); end if;
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 40 then raise exception 'BAD_ITEMS'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    select * into pr from public.products where id = it->>'id' and active;
    if not found then raise exception 'ITEM_UNAVAILABLE:%', it->>'id'; end if;
    select o into op from jsonb_array_elements(pr.options) o where o->>'k' = it->>'opt' limit 1;
    if op is null then raise exception 'ITEM_UNAVAILABLE:%', it->>'id'; end if;
    v_qty := (it->>'qty')::int;
    if v_qty < 1 or v_qty > 50 then raise exception 'BAD_QTY'; end if;
    v_sub := v_sub + (op->>'price')::int * v_qty;
    v_mrp := v_mrp + coalesce((op->>'mrp')::int, (op->>'price')::int) * v_qty;
    v_kit := v_kit or pr.kit;
    v_items := v_items || jsonb_build_object('id', pr.id, 'name', pr.name_en, 'opt', op->>'en', 'qty', v_qty, 'price', (op->>'price')::int);
  end loop;
  perform pg_advisory_xact_lock(hashtext(v_uid::text));
  select n.store_id, n.km into v_store, v_km from public.nearest_store(p_lat, p_lng) n;
  select (value->>'max_km')::numeric into v_max from public.app_settings where key = 'delivery';
  if v_max is not null and v_km is not null and v_km > v_max then raise exception 'OUT_OF_AREA'; end if;
  v_free := public.free_deliveries_left(v_uid, p_phone);
  v_fee := public.delivery_fee_for(v_sub, v_free, v_km);
  v_total := v_sub + v_fee;
  if p_pay = 'wallet' then
    v_bal := public.wallet_balance(v_uid);
    if v_bal < v_total then raise exception 'LOW_BALANCE'; end if;
  end if;
  insert into public.orders(user_id, items, subtotal, delivery_fee, total, pay_method, zone, slot, name, phone, address, landmark, has_kit, status, paid, client_ref, lat, lng, store_id, distance_km)
  values (v_uid, v_items, v_sub, v_fee, v_total, p_pay, 'sikar', left(p_slot,40), left(trim(p_name),80), p_phone, left(trim(p_address),300),
    left(trim(coalesce(p_landmark,'')),120), v_kit, case when p_pay = 'upi' then 'awaiting_payment' else 'placed' end, p_pay = 'wallet', p_client_ref,
    p_lat, p_lng, v_store, v_km)
  returning id into v_id;
  if p_pay = 'wallet' then
    insert into public.wallet_txns(user_id, amount, kind, ref_id, note) values (v_uid, -v_total, 'order', v_id, 'Order #' || v_id);
  end if;
  update public.profiles set full_name = left(trim(p_name),80), phone = p_phone, address = left(trim(p_address),300),
    landmark = left(trim(coalesce(p_landmark,'')),120), lat = coalesce(p_lat, lat), lng = coalesce(p_lng, lng) where id = v_uid;
  return jsonb_build_object('id', v_id, 'subtotal', v_sub, 'mrp', v_mrp, 'fee', v_fee, 'total', v_total, 'kit', v_kit, 'items', v_items,
    'status', case when p_pay = 'upi' then 'awaiting_payment' else 'placed' end, 'balance', public.wallet_balance(v_uid), 'free_left', greatest(0, v_free - 1));
end $function$;
revoke all on function public.place_order(jsonb, text, text, text, text, text, text, text, double precision, double precision) from public, anon;
grant execute on function public.place_order(jsonb, text, text, text, text, text, text, text, double precision, double precision) to authenticated;

-- ---------- customer: live tracking of own order ----------
create or replace function public.order_tracking(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare o public.orders%rowtype; s public.stores%rowtype; l public.rider_locations%rowtype; rn text;
begin
  select * into o from public.orders where id = p_id and user_id = auth.uid();
  if not found then raise exception 'NO_ORDER'; end if;
  select * into s from public.stores where id = o.store_id;
  if o.status = 'out_for_delivery' and o.rider_email is not null then
    select * into l from public.rider_locations where email = o.rider_email and at > now() - interval '5 minutes';
    select split_part(name, ' ', 1) into rn from public.riders where email = o.rider_email;
  end if;
  return jsonb_build_object('status', o.status, 'lat', o.lat, 'lng', o.lng,
    'store', case when s.id is null then null else jsonb_build_object('name', s.name, 'lat', s.lat, 'lng', s.lng) end,
    'rider', case when l.email is null then null else jsonb_build_object('name', rn, 'lat', l.lat, 'lng', l.lng, 'heading', l.heading, 'at', l.at) end);
end $$;
revoke all on function public.order_tracking(bigint) from public, anon;
grant execute on function public.order_tracking(bigint) to authenticated;

-- ---------- rider: send location, see pins ----------
create or replace function public.rider_ping(p_lat double precision, p_lng double precision, p_acc real default null, p_heading real default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_email text;
begin
  if not public.is_rider() then raise exception 'NOT_RIDER'; end if;
  if p_lat not between 6 and 38 or p_lng not between 68 and 98 then return; end if;
  select lower(email) into v_email from auth.users where id = auth.uid();
  insert into public.rider_locations(email, lat, lng, acc, heading, at) values (v_email, p_lat, p_lng, p_acc, p_heading, now())
  on conflict (email) do update set lat = excluded.lat, lng = excluded.lng, acc = excluded.acc, heading = excluded.heading, at = now();
end $$;
revoke all on function public.rider_ping(double precision, double precision, real, real) from public, anon;
grant execute on function public.rider_ping(double precision, double precision, real, real) to authenticated;

create or replace function public.rider_orders()
 returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
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
      'phone', case when o.status in ('delivered','cancelled') then null else o.phone end,
      'lat', case when o.status in ('delivered','cancelled') then null else o.lat end,
      'lng', case when o.status in ('delivered','cancelled') then null else o.lng end,
      'distance_km', o.distance_km,
      'store', (select jsonb_build_object('name', s.name, 'address', s.address, 'lat', s.lat, 'lng', s.lng, 'phone', s.phone) from public.stores s where s.id = o.store_id)
    ) order by (o.status in ('delivered','cancelled')), o.id)
    from public.orders o
    where o.rider_email = v_email
      and (o.status not in ('delivered','cancelled') or o.created_at > now() - interval '24 hours')
  ), '[]'::jsonb);
end $function$;

-- ---------- admin ----------
create or replace function public.admin_stores()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return jsonb_build_object(
    'stores', coalesce((select jsonb_agg(to_jsonb(s) order by s.id) from public.stores s), '[]'),
    'delivery', (select value from public.app_settings where key = 'delivery'),
    'riders', coalesce((select jsonb_agg(jsonb_build_object('email', r.email, 'name', r.name, 'lat', l.lat, 'lng', l.lng, 'at', l.at) order by l.at desc)
       from public.riders r join public.rider_locations l on l.email = r.email where r.active and l.at > now() - interval '12 hours'), '[]'));
end $$;
revoke all on function public.admin_stores() from public, anon;
grant execute on function public.admin_stores() to authenticated;

create or replace function public.admin_save_store(p_id bigint, p_name text, p_address text, p_lat double precision, p_lng double precision, p_phone text, p_active boolean)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if coalesce(trim(p_name), '') = '' or p_lat not between 6 and 38 or p_lng not between 68 and 98 then raise exception 'BAD_STORE'; end if;
  if p_id is null then
    insert into public.stores(name, address, lat, lng, phone, active) values (left(trim(p_name), 60), left(p_address, 200), p_lat, p_lng, left(p_phone, 15), coalesce(p_active, true)) returning id into v_id;
  else
    update public.stores set name = left(trim(p_name), 60), address = left(p_address, 200), lat = p_lat, lng = p_lng, phone = left(p_phone, 15), active = coalesce(p_active, true)
    where id = p_id returning id into v_id;
  end if;
  return v_id;
end $$;
revoke all on function public.admin_save_store(bigint, text, text, double precision, double precision, text, boolean) from public, anon;
grant execute on function public.admin_save_store(bigint, text, text, double precision, double precision, text, boolean) to authenticated;

create or replace function public.admin_save_delivery(p jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare sl jsonb;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if jsonb_typeof(p->'slabs') <> 'array' or jsonb_array_length(p->'slabs') > 10 then raise exception 'BAD_SETTINGS'; end if;
  for sl in select * from jsonb_array_elements(p->'slabs') loop
    if (sl->>'km')::numeric <= 0 or (sl->>'fee')::int < 0 or (sl->>'fee')::int > 500 then raise exception 'BAD_SETTINGS'; end if;
  end loop;
  update public.app_settings set value = jsonb_build_object(
      'free_first', greatest(0, least(10, coalesce((p->>'free_first')::int, 2))),
      'free_above', greatest(0, coalesce((p->>'free_above')::int, 299)),
      'default_fee', greatest(0, least(500, coalesce((p->>'default_fee')::int, 30))),
      'road_factor', coalesce((value->>'road_factor')::numeric, 1.3),
      'max_km', case when nullif(p->>'max_km', '') is null then null else (p->>'max_km')::numeric end,
      'slabs', p->'slabs'),
    updated_at = now()
  where key = 'delivery';
end $$;
revoke all on function public.admin_save_delivery(jsonb) from public, anon;
grant execute on function public.admin_save_delivery(jsonb) to authenticated;
