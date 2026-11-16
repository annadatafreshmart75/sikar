-- Anonymous visitor tracking (no names, phones or emails) + admin Visitors report
create table if not exists public.site_events (
  id bigserial primary key,
  at timestamptz not null default now(),
  vid text not null,          -- random id kept in the visitor's browser
  sid text not null,          -- random id per browser session
  kind text not null check (kind in ('visit','view_item','add_cart','checkout','order')),
  item text,
  src text,
  device text,
  is_new boolean
);
create index if not exists site_events_at_idx on public.site_events (at);
create index if not exists site_events_sid_idx on public.site_events (sid);
alter table public.site_events enable row level security;
revoke all on public.site_events from anon, authenticated;

create or replace function public.track_event(p_vid text, p_sid text, p_kind text, p_item text default null, p_src text default null, p_device text default null, p_new boolean default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_vid is null or length(p_vid) not between 6 and 40 or p_sid is null or length(p_sid) not between 6 and 40 then return; end if;
  if p_kind not in ('visit','view_item','add_cart','checkout','order') then return; end if;
  -- one visit row per session
  if p_kind = 'visit' and exists (select 1 from site_events where sid = p_sid and kind = 'visit') then return; end if;
  insert into site_events (vid, sid, kind, item, src, device, is_new)
  values (p_vid, p_sid, p_kind, left(p_item, 40), left(p_src, 20), left(p_device, 10), p_new);
end $$;
revoke all on function public.track_event(text,text,text,text,text,text,boolean) from public;
grant execute on function public.track_event(text,text,text,text,text,text,boolean) to anon, authenticated;

create or replace function public.admin_visitors(p_days int default 7)
returns json language plpgsql security definer set search_path = public as $$
declare since timestamptz; r json;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  since := case when p_days <= 1 then date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'
                else now() - make_interval(days => p_days) end;
  with e as (select * from site_events where at >= since),
  v as (select * from e where kind = 'visit')
  select json_build_object(
    'visitors', (select count(distinct vid) from e),
    'sessions', (select count(*) from v),
    'new_visitors', (select count(distinct vid) from v where is_new),
    'returning', (select count(distinct vid) from v where not coalesce(is_new, false)),
    'cart_sessions', (select count(distinct sid) from e where kind = 'add_cart'),
    'checkout_sessions', (select count(distinct sid) from e where kind = 'checkout'),
    'order_sessions', (select count(distinct sid) from e where kind = 'order'),
    'sources', (select coalesce(json_agg(x order by x.n desc), '[]') from (select coalesce(src,'direct') k, count(*) n from v group by 1) x),
    'devices', (select coalesce(json_agg(x order by x.n desc), '[]') from (select coalesce(device,'?') k, count(*) n from v group by 1) x),
    'viewed', (select coalesce(json_agg(x order by x.n desc), '[]') from (select item k, count(distinct sid) n from e where kind = 'view_item' and item is not null group by 1 order by 2 desc limit 8) x),
    'carted', (select coalesce(json_agg(x order by x.n desc), '[]') from (select item k, count(distinct sid) n from e where kind = 'add_cart' and item is not null group by 1 order by 2 desc limit 8) x),
    'daily', (select coalesce(json_agg(x order by x.d), '[]') from (
        select to_char((at at time zone 'Asia/Kolkata')::date, 'DD Mon') l, (at at time zone 'Asia/Kolkata')::date d, count(distinct vid) n
        from v group by 1, 2) x)
  ) into r;
  return r;
end $$;
revoke all on function public.admin_visitors(int) from public, anon;
grant execute on function public.admin_visitors(int) to authenticated;
