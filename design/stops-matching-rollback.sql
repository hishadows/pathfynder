-- Rollback for migrations explore_match_via_stops + bot_match_via_stops (plan.md task 11).
-- Captured via pg_get_functiondef on 2026-10-02 BEFORE the change. Run in order.
-- Note: apply_migration hangs on DROP; if the DROP below hangs, run it via the SQL editor / psql.

-- 1) explore_search_core (original)
CREATE OR REPLACE FUNCTION public.explore_search_core(p_mode text DEFAULT 'drivers'::text, p_o_lat double precision DEFAULT NULL::double precision, p_o_lng double precision DEFAULT NULL::double precision, p_d_lat double precision DEFAULT NULL::double precision, p_d_lng double precision DEFAULT NULL::double precision, p_date date DEFAULT NULL::date, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(id text, source text, role text, display_name text, origin_label text, dest_label text, ride_date date, ride_time text, arrive_time text, seats integer, price text, price_num numeric, rating numeric, rating_count integer, verified boolean, luggage text, recurring_label text, posted_count integer, groups jsonb, posted_at timestamp with time zone, is_business boolean, is_coordinator boolean, is_regular boolean, parsed boolean, match_type text, pickup_km numeric, dropoff_km numeric, route_km numeric, pickup_pct numeric, dropoff_pct numeric, score integer, description text, raw_text text, is_urgent boolean, is_airport boolean, is_daily boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
with
prm as (
  select (now() at time zone 'America/Toronto')::date as today,
         case when p_mode = 'passengers' then 'passenger' else 'driver' end as want,
         (p_o_lat is not null and p_o_lng is not null and p_d_lat is not null and p_d_lng is not null) as has_geo,
         (p_o_lat is not null and p_o_lng is not null and (p_d_lat is null or p_d_lng is null)) as near_mode,
         coalesce((p_filters->>'near_km')::numeric, 25) as near_km,
         coalesce((p_filters->>'radius_km')::numeric, 10) as r_km,
         coalesce((p_filters->>'corridor_km')::numeric, 15) as c_km,
         coalesce(greatest(p_date, (now() at time zone 'America/Toronto')::date), (now() at time zone 'America/Toronto')::date) as d1,
         coalesce(greatest(p_date, (now() at time zone 'America/Toronto')::date), (now() at time zone 'America/Toronto')::date + 3) as d2,
         '(airport|pearson|yyz|yhm|yow|ytz|yxu|billy bishop|terminal [0-9])'::text as air_re
),
q as (
  select case when p_o_lat is not null and p_o_lng is not null then st_setsrid(st_makepoint(p_o_lng, p_o_lat), 4326) end as o,
         case when p.has_geo then st_setsrid(st_makepoint(p_d_lng, p_d_lat), 4326) end as d
  from prm p
),
wa_rows as (
  select e.*, case when e."Type" = 'Driver' then 'driver' else 'passenger' end as rl, md5(lower(regexp_replace(btrim(coalesce(e.original_message, '')), '\s+', ' ', 'g'))) as tb
  from extracted_data_01 e, prm
  where ((prm.want = 'driver' and e."Type" = 'Driver') or (prm.want = 'passenger' and e."Type" ilike 'passenger'))
    and e."pick up date" between prm.d1 and prm.d2
    and e.pickup_lat is not null and e.dropoff_lat is not null
),
wa_grp as (
  select sender_number, pickup_label, dropoff_label, "pick up date" as dd, tb, group_name, min("D&T of msg") as first_at
  from wa_rows where group_name is not null
  group by 1, 2, 3, 4, 5, 6
),
wa_grp_agg as (
  select sender_number, pickup_label, dropoff_label, dd, tb,
         jsonb_agg(jsonb_build_object('name', group_name, 'posted_at', first_at) order by first_at) as grps
  from wa_grp group by 1, 2, 3, 4, 5
),
wa_base as (
  select sender_number as sn, pickup_label as pl, dropoff_label as dlb, "pick up date" as dd, tb,
         max(rl) as rl, max(id) as mid, max(sender_name) as nm, coalesce((array_agg("pick up time"::time order by "D&T of msg" desc, id desc))[1], min("pick up time"::time)) as t, count(*)::int as pc,
         max(case when coalesce(ride_frequency, 'one-time') <> 'one-time' then initcap(ride_frequency) end) as rec,
         max("additional conditions") as ds,
         (array_agg(original_message order by "D&T of msg" desc))[1] as raw,
         min("D&T of msg") as pat,
         bool_or(important_ride = 'urgent') as urg,
         bool_or(important_ride = 'airport'
                 or coalesce(pickup_label, '') ~* (select air_re from prm)
                 or coalesce(dropoff_label, '') ~* (select air_re from prm)) as air,
         bool_or(important_ride = 'daily' or ride_frequency = 'daily') as dly,
         avg(pickup_lng) as olng, avg(pickup_lat) as olat, avg(dropoff_lng) as dlng, avg(dropoff_lat) as dlat
  from wa_rows group by 1, 2, 3, 4, 5
),
stats as (
  select e.sender_number as sn,
         count(distinct (e.pickup_label, e.dropoff_label, e."pick up date")) as leads30,
         count(distinct (e.pickup_label, e.dropoff_label)) as routes30
  from extracted_data_01 e, prm
  where prm.want = 'passenger' and e.sender_number in (select sn from wa_base)
    and e."Type" ilike 'passenger' and e."D&T of msg" > now() - interval '30 days'
  group by 1
),
route_freq as (
  select e.sender_number as sn, e.pickup_label as pl, e.dropoff_label as dlb, count(distinct e."pick up date") as days
  from extracted_data_01 e, prm
  where prm.want = 'passenger' and e.sender_number in (select sn from wa_base)
    and e."Type" ilike 'passenger' and e."D&T of msg" > now() - interval '30 days'
  group by 1, 2, 3
),
wa_final as (
  select 'wa:' || b.mid as rid, 'whatsapp'::text as src, b.rl, b.nm,
         b.pl as ol, b.dlb as dl, b.dd, to_char(b.t, 'HH24:MI') as tm, null::text as atm,
         null::int as st, null::text as pr, null::numeric as rt, null::int as rc, null::boolean as vf,
         null::text as lg, b.rec, b.pc, false as biz,
         coalesce(s.leads30 >= 60 or (s.leads30 >= 40 and s.routes30 >= 20), false) as coord,
         (coalesce(rf.days >= 4, false) and not coalesce(s.leads30 >= 60 or (s.leads30 >= 40 and s.routes30 >= 20), false)) as reg,
         b.ds::text as ds, b.raw::text as raw, coalesce(g.grps, '[]'::jsonb) as grps, b.pat, true as parsed,
         px_tod(b.t) as tod,
         st_setsrid(st_makepoint(b.olng, b.olat), 4326) as go, st_setsrid(st_makepoint(b.dlng, b.dlat), 4326) as gd,
         coalesce(b.urg, false) as urg, coalesce(b.air, false) as air, coalesce(b.dly, false) as dly
  from wa_base b
  left join wa_grp_agg g on g.sender_number = b.sn and g.pickup_label is not distinct from b.pl
        and g.dropoff_label is not distinct from b.dlb and g.dd = b.dd and g.tb = b.tb
  left join stats s on s.sn = b.sn
  left join route_freq rf on rf.sn = b.sn and rf.pl is not distinct from b.pl and rf.dlb is not distinct from b.dlb
),
pp as (
  select 'pp:' || m.id, 'poparide'::text, prm.want, m.author,
         coalesce(m.origin_place, m.origin), coalesce(m.dest_place, m.destination),
         coalesce((m.departing_at at time zone 'America/Toronto')::date, m.ride_date),
         coalesce(to_char(m.departing_at at time zone 'America/Toronto', 'HH24:MI'),
                  nullif(m.ride_time, ''),
                  to_char(px_parse_time(m.raw_text), 'HH24:MI')),
         to_char(m.arriving_at at time zone 'America/Toronto', 'HH24:MI'),
         m.seats::int, m.price::text, m.creator_rating::numeric, m.creator_rating_count::int, m.creator_verified::boolean,
         (case when m.options is null then null
               when (m.options->>'luggage')::boolean then coalesce(initcap(m.options->>'luggage_size') || ' bag OK', 'Luggage OK')
               else 'No luggage' end)::text,
         (case when m.parent_id is not null then 'Recurring' end)::text,
         1::int, coalesce(m.is_commercial, false), false, false,
         left(m.raw_text, 800)::text,
         (case when prm.want = 'passenger' then nullif(m.raw_text, '') end)::text,
         '[]'::jsonb, coalesce(m.posted_at, m.fetched_at), true,
         coalesce(m.time_bucket,
                  px_tod(coalesce((m.departing_at at time zone 'America/Toronto')::time, px_parse_time(m.raw_text))))::text,
         coalesce(st_setsrid(m.origin_geo, 4326), st_setsrid(po.geo, 4326)),
         coalesce(st_setsrid(m.dest_geo, 4326), st_setsrid(pd.geo, 4326)),
         coalesce(m.raw_text, '') ~* '(urgent|asap|emergency)',
         (coalesce(m.origin_place, m.origin, '') || ' ' || coalesce(m.dest_place, m.destination, '') || ' ' || coalesce(m.raw_text, '')) ~* prm.air_re,
         false
  from muse_ride_posts m
  cross join prm
  left join places po on po.norm_key = lower(regexp_replace(m.origin_city, '\.', '', 'g'))
  left join places pd on pd.norm_key = lower(regexp_replace(m.destination_city, '\.', '', 'g'))
  where m.platform = 'poparide' and m.duplicate_of is null and coalesce(m.listing_state, '') not in ('gone', 'closed', 'full', 'cancelled')
    and m.post_type = case when prm.want = 'driver' then 'offer' else 'request' end
    and (m.departing_at is null or m.departing_at >= now())
    and coalesce((m.departing_at at time zone 'America/Toronto')::date, m.ride_date) between prm.d1 and prm.d2
),
fb as (
  select 'fb:' || m.id, 'facebook'::text, prm.want, m.author, m.origin, m.destination, m.ride_date, m.ride_time, null::text,
         m.seats, m.price, null::numeric, null::int, null::boolean, null::text,
         (case when coalesce(m.raw_text, '') ~* '(\mdaily\M|every ?day)' then 'Daily' end)::text,
         (select count(*) from muse_ride_posts x where x.fingerprint = m.fingerprint)::int,
         coalesce(m.is_commercial, false), false, false,
         null::text, m.raw_text,
         case when m.group_name is null then '[]'::jsonb
              else jsonb_build_array(jsonb_build_object('name', m.group_name, 'posted_at', coalesce(m.posted_at, m.fetched_at))) end,
         coalesce(m.posted_at, m.fetched_at), true, m.time_bucket,
         st_setsrid(po.geo, 4326), st_setsrid(pd.geo, 4326),
         coalesce(m.raw_text, '') ~* '(urgent|asap|emergency)',
         (coalesce(m.origin, '') || ' ' || coalesce(m.destination, '') || ' ' || coalesce(m.raw_text, '')) ~* prm.air_re,
         coalesce(m.raw_text, '') ~* '(\mdaily\M|every ?day)'
  from muse_ride_posts m
  cross join prm
  join places po on po.norm_key = lower(regexp_replace(m.origin_city, '\.', '', 'g'))
  join places pd on pd.norm_key = lower(regexp_replace(m.destination_city, '\.', '', 'g'))
  where m.platform = 'facebook' and m.duplicate_of is null and m.origin is not null
    and m.post_type = case when prm.want = 'driver' then 'offer' else 'request' end
    and ( m.ride_date between prm.d1 and prm.d2
       or (p_date is null and m.ride_date is null and coalesce(m.posted_at, m.fetched_at) > now() - interval '3 days') )
),
fb_raw as (
  select 'fb:' || m.id, 'facebook'::text, prm.want, m.author, null::text, null::text, null::date, null::text, null::text,
         null::int, null::text, null::numeric, null::int, null::boolean, null::text, null::text,
         1::int, coalesce(m.is_commercial, false), false, false,
         null::text, m.raw_text,
         case when m.group_name is null then '[]'::jsonb
              else jsonb_build_array(jsonb_build_object('name', m.group_name, 'posted_at', coalesce(m.posted_at, m.fetched_at))) end,
         coalesce(m.posted_at, m.fetched_at), false, null::text,
         null::geometry, null::geometry,
         coalesce(m.raw_text, '') ~* '(urgent|asap|emergency)',
         coalesce(m.raw_text, '') ~* prm.air_re,
         coalesce(m.raw_text, '') ~* '(\mdaily\M|every ?day)'
  from muse_ride_posts m
  cross join prm
  where not prm.near_mode
    and m.platform = 'facebook' and m.duplicate_of is null and m.origin is null
    and m.post_type = case when prm.want = 'driver' then 'offer' else 'request' end
    and coalesce(m.posted_at, m.fetched_at) > now() - interval '3 days'
    and (coalesce(p_filters->>'from_name', '') = '' and coalesce(p_filters->>'to_name', '') = ''
         or m.raw_text ilike '%' || nullif(p_filters->>'from_name', '') || '%'
         or m.raw_text ilike '%' || nullif(p_filters->>'to_name', '') || '%')
),
pf as (
  select 'pf:' || x.id as rid, 'pathfynder'::text as src, prm.want as rl, x.nm::text,
         x.pl::text, x.dlb::text, x.dd, to_char(x.t, 'HH24:MI'), null::text,
         x.st, x.pr, null::numeric, null::int, null::boolean, null::text, null::text,
         1::int, false, false, false,
         null::text, null::text, '[]'::jsonb, x.pat, true, px_tod(x.t)::text,
         st_setsrid(st_makepoint(x.olng, x.olat), 4326), st_setsrid(st_makepoint(x.dlng, x.dlat), 4326),
         false, (coalesce(x.pl, '') || ' ' || coalesce(x.dlb, '')) ~* prm.air_re, false
  from prm cross join lateral (
    select d.id, d.driver_wa_id as wa, d.driver_name as nm, d.pickup_label as pl, d.dropoff_label as dlb,
           coalesce(d.dates, (d.departure_datetime at time zone 'America/Toronto')::date) as dd,
           coalesce(d.departure_time, (d.departure_datetime at time zone 'America/Toronto')::time) as t,
           case when d.available_seats > 0 then d.available_seats end as st,
           case when d.fare > 0 then '$' || trim_scale(d.fare)::text || ' CAD' end as pr,
           d.created_at as pat, d.pickup_lat as olat, d.pickup_lng as olng, d.dropoff_lat as dlat, d.dropoff_lng as dlng,
           'driver_routines:' || d.id as ref
    from driver_routines d where prm.want = 'driver'
    union all
    select p.id, p.passenger_wa_id, p.passenger_name, p.pickup_label, p.dropoff_label,
           coalesce(p.date, (p.requested_datetime at time zone 'America/Toronto')::date),
           coalesce(p.time::time, (p.requested_datetime at time zone 'America/Toronto')::time),
           null::int, null::text,
           p.created_at, p.pickup_lat, p.pickup_lng, p.dropoff_lat, p.dropoff_lng,
           'passenger_requests:' || p.id
    from passenger_requests p where prm.want = 'passenger'
  ) x
  where x.dd between prm.d1 and prm.d2
    and x.wa is not null
    and x.olat is not null and x.olng is not null and x.dlat is not null and x.dlng is not null
    and (public.notify_request_open(x.ref)->>'open') = 'true'
    and not exists (select 1 from notify_requests nr
                    where nr.token::text = nullif(p_filters->>'viewer_token', '') and nr.wa_id = x.wa)
),
allr as (
  select * from wa_final
  union all select * from pf
  union all select * from pp
  union all select * from fb
  union all select * from fb_raw
),
calc as (
  select a.*, p.has_geo, p.near_mode, p.near_km, p.r_km, p.c_km,
    case when (p.has_geo or p.near_mode) and a.parsed then st_distance(a.go::geography, q.o::geography) / 1000 end as o_km,
    case when p.has_geo and a.parsed then st_distance(a.gd::geography, q.d::geography) / 1000 end as d_km,
    case when p.has_geo and a.parsed then
      case when p.want = 'driver' then case when not st_equals(a.go, a.gd) then st_makeline(a.go, a.gd) end
           else case when not st_equals(q.o, q.d) then st_makeline(q.o, q.d) end end
    end as ln,
    case when p.want = 'driver' then q.o else a.go end as pa,
    case when p.want = 'driver' then q.d else a.gd end as pb
  from allr a, prm p, q
  where not a.parsed or (a.go is not null and a.gd is not null)
),
calc2 as (
  select c.*,
    case when c.ln is not null then st_distance(c.ln::geography, c.pa::geography) / 1000 end as a_line,
    case when c.ln is not null then st_distance(c.ln::geography, c.pb::geography) / 1000 end as b_line,
    case when c.ln is not null then st_linelocatepoint(c.ln, c.pa) end as fa,
    case when c.ln is not null then st_linelocatepoint(c.ln, c.pb) end as fbp,
    case when c.ln is not null then st_length(c.ln::geography) / 1000 end as lkm
  from calc c
),
matched as (
  select c.*,
    case when not c.has_geo or not c.parsed then null
         when c.o_km <= c.r_km and c.d_km <= c.r_km then 'direct'
         when c.a_line <= c.c_km and c.b_line <= c.c_km and c.fa < c.fbp then 'along_route'
    end as mt
  from calc2 c
),
final as (
  select m.*,
    case when m.mt = 'direct' then m.o_km when m.mt = 'along_route' then m.a_line
         when m.near_mode then m.o_km end as pk,
    case when m.mt = 'direct' then m.d_km when m.mt = 'along_route' then m.b_line end as dk,
    greatest(0, (100
      - coalesce(case when m.mt = 'direct' then m.o_km + m.d_km when m.mt = 'along_route' then m.a_line + m.b_line end, 0) * 2
      - case when m.mt = 'along_route' then 10 else 0 end
      + case when m.src = 'whatsapp' then 10 else 0 end
      + case when m.vf then 5 else 0 end
      + case when coalesce(m.rt, 0) >= 4.5 then 5 else 0 end
      + case when m.reg then 10 else 0 end
      - case when m.biz then 10 else 0 end
      - case when m.coord then 10 else 0 end))::int as sc
  from matched m
  where case when m.near_mode then m.parsed and m.o_km <= m.near_km
             else not m.has_geo or m.mt is not null or not m.parsed end
),
filtered as (
  select f.*,
    row_number() over (partition by f.src order by
      f.parsed desc, f.biz asc,
      case f.mt when 'direct' then 0 when 'along_route' then 1 else 2 end,
      case when f.has_geo then f.sc end desc nulls last,
      f.dd nulls last, f.tm nulls last, f.pk nulls last) as src_rank
  from final f
  where (coalesce(p_filters->>'match', 'all') <> 'direct' or f.mt = 'direct' or f.near_mode)
    and (jsonb_typeof(p_filters->'sources') is distinct from 'array' or jsonb_array_length(p_filters->'sources') = 0
         or f.src in (select jsonb_array_elements_text(p_filters->'sources'))
         or (f.src = 'pathfynder' and p_filters->'sources' @> '["whatsapp"]'::jsonb))
    and (jsonb_typeof(coalesce(p_filters->'time_of_day', p_filters->'times')) is distinct from 'array'
         or jsonb_array_length(coalesce(p_filters->'time_of_day', p_filters->'times')) = 0
         or f.tod in (select jsonb_array_elements_text(coalesce(p_filters->'time_of_day', p_filters->'times'))))
    and (coalesce(p_filters->>'time', '') = ''
         or (f.tm is not null and abs(extract(epoch from (f.tm::time - (p_filters->>'time')::time)) / 60)
              <= coalesce((p_filters->>'flex_min')::int, 60)))
    and (coalesce((p_filters->>'verified_only')::boolean, false) = false or f.vf is true)
    and (coalesce((p_filters->>'hide_business')::boolean, false) = false or not f.biz)
    and (coalesce((p_filters->>'luggage_ok')::boolean, false) = false or (f.lg is not null and f.lg <> 'No luggage'))
    and (coalesce((p_filters->>'urgent')::boolean, false) = false or f.urg)
    and (coalesce((p_filters->>'airport')::boolean, false) = false or f.air)
    and (coalesce((p_filters->>'daily')::boolean, false) = false or f.dly)
)
select f.rid, f.src, f.rl,
  case when f.biz then f.nm else px_short_name(f.nm) end,
  f.ol, f.dl, f.dd, f.tm, f.atm, f.st, f.pr,
  nullif(substring(coalesce(f.pr, '') from '[0-9]+(?:\.[0-9]+)?'), '')::numeric,
  f.rt, f.rc, f.vf, f.lg, f.rec, f.pc, f.grps, f.pat,
  f.biz, f.coord, f.reg, f.parsed, f.mt,
  round(f.pk::numeric, 1), round(f.dk::numeric, 1),
  case when f.mt = 'along_route' then round(f.lkm::numeric, 0) end,
  case when f.mt = 'along_route' then round((f.fa * 100)::numeric, 0) end,
  case when f.mt = 'along_route' then round((f.fbp * 100)::numeric, 0) end,
  f.sc, f.ds, f.raw,
  f.urg, f.air, f.dly
from filtered f
where f.src_rank <= 50
order by (f.src = 'pathfynder') desc, f.parsed desc, f.biz asc,
  case f.mt when 'direct' then 0 when 'along_route' then 1 else 2 end,
  case when f.has_geo then f.sc end desc nulls last,
  f.dd nulls last, f.tm nulls last,
  f.pk nulls last
limit 150;
$function$;

-- 2) bot_match_reply_for (original)
CREATE OR REPLACE FUNCTION public.bot_match_reply_for(p_role text, p_id uuid)
 RETURNS TABLE(match_count integer, reply text, link text, body text, button_text text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_is_driver boolean := lower(coalesce(p_role,'')) like 'driver%';
  v_token uuid;
  r record;
begin
  select nr.token into v_token from notify_requests nr
   where nr.source_ref = case when v_is_driver then 'driver_routines:' else 'passenger_requests:' end || p_id::text;

  if v_is_driver then
    for r in
    select x.* from driver_routines d,
      lateral bot_match_reply('Driver', d.pickup_lat, d.pickup_lng, d.dropoff_lat, d.dropoff_lng,
        coalesce(d.dates, (d.departure_datetime at time zone 'America/Toronto')::date)::text,
        d.pickup_label, d.dropoff_label,
        coalesce(d.departure_time, (d.departure_datetime at time zone 'America/Toronto')::time)::text) x
    where d.id = p_id
    loop
      match_count := r.match_count; reply := r.reply; link := r.link; body := r.body; button_text := r.button_text;
      if v_token is not null and r.link is not null then
        link := r.link || '&t=' || v_token::text;
        reply := replace(r.reply, r.link, link);
      end if;
      return next;
    end loop;
  else
    for r in
    select x.* from passenger_requests pr,
      lateral bot_match_reply('Passenger', pr.pickup_lat, pr.pickup_lng, pr.dropoff_lat, pr.dropoff_lng,
        coalesce(pr.date, (pr.requested_datetime at time zone 'America/Toronto')::date)::text,
        pr.pickup_label, pr.dropoff_label,
        coalesce(pr.time::time, (pr.requested_datetime at time zone 'America/Toronto')::time)::text) x
    where pr.id = p_id
    loop
      match_count := r.match_count; reply := r.reply; link := r.link; body := r.body; button_text := r.button_text;
      if v_token is not null and r.link is not null then
        link := r.link || '&t=' || v_token::text;
        reply := replace(r.reply, r.link, link);
      end if;
      return next;
    end loop;
  end if;
end $function$;

-- 3) notify_check_new_matches (original)
CREATE OR REPLACE FUNCTION public.notify_check_new_matches(p_scope text DEFAULT 'all'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
-- p_scope: which table fired the check (or 'all'); informational, every open trip is checked.
declare
  v_first int := public.notify_setting('first_alert_min')::int;
  v_thr int := public.notify_setting('alert_threshold')::int;
  v_req record;
  v_p record;
  v_title text;
  v_body text;
  v_noun text;
begin
  if coalesce(public.notify_setting('match_alerts_enabled'), 'false') <> 'true' then
    return;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('pf_notify_matches')) then
    return;
  end if;

  create temp table if not exists _pf_trips (token uuid, wa_id text, trip_key uuid) on commit drop;
  create temp table if not exists _pf_cur (token uuid, ride_ref text) on commit drop;
  create temp table if not exists _pf_new (token uuid, ride_ref text) on commit drop;
  truncate _pf_trips, _pf_cur, _pf_new;

  insert into _pf_trips select * from public.notify_open_trips();

  -- current parsed matches per open request; unseen ones become "new"
  for v_req in select r.* from public.notify_requests r join _pf_trips t on t.token = r.token loop
    insert into _pf_cur (token, ride_ref)
    select v_req.token, s.id
    from public.explore_search(v_req.mode, v_req.from_lat, v_req.from_lng, v_req.to_lat, v_req.to_lng, v_req.ride_date,
           -- viewer_token: never alert a requester about their own Pathfynder post. Keep this in any rewrite.
           jsonb_build_object('viewer_token', v_req.token::text)) s
    where s.parsed;
  end loop;

  insert into public.notify_seen (request_token, ride_ref, seeded)
  select c.token, c.ride_ref, false from _pf_cur c on conflict do nothing;

  insert into _pf_new (token, ride_ref)
  select h.request_token, h.ride_ref from public.notify_seen h join _pf_trips t on t.token = h.request_token where not h.seeded;

  -- per trip: stage (max over group), available count (distinct current rides), new count (distinct new rides)
  create temp table if not exists _pf_trip_state (wa_id text, trip_key uuid, stage smallint, avail int, new_n int, next_stage smallint) on commit drop;
  truncate _pf_trip_state;
  insert into _pf_trip_state
  select t.wa_id, t.trip_key,
         max(r.alert_stage)::smallint,
         (select count(distinct c.ride_ref) from _pf_cur c join _pf_trips t2 on t2.token = c.token where t2.trip_key = t.trip_key),
         (select count(distinct n.ride_ref) from _pf_new n join _pf_trips t2 on t2.token = n.token where t2.trip_key = t.trip_key),
         null
  from _pf_trips t join public.notify_requests r on r.token = t.token
  group by t.wa_id, t.trip_key;

  update _pf_trip_state set next_stage = case
      when new_n = 0 then null
      when stage = 0 and new_n >= v_first then case when avail >= v_thr then 2 else 1 end
      when stage = 1 and avail >= v_thr then 2
      else null end;

  -- one push per person: biggest pending trip; other pending trips ride along as "+N more rides"
  for v_p in
    select distinct on (s.wa_id) s.wa_id, s.trip_key, s.avail, s.next_stage,
           (select coalesce(sum(o.new_n), 0) from _pf_trip_state o
             where o.wa_id = s.wa_id and o.next_stage is not null and o.trip_key <> s.trip_key) more
    from _pf_trip_state s
    where s.next_stage is not null
    order by s.wa_id, s.avail desc, s.trip_key
  loop
    select * into v_req from public.notify_requests where token = v_p.trip_key;
    v_noun := case when v_req.mode = 'passengers' then 'passenger' else 'driver' end;
    v_title := v_p.avail || ' ' || v_noun || case when v_p.avail = 1 then '' else 's' end || ' available';
    v_body := coalesce(v_req.label, '') || case when v_p.more > 0 then ' · +' || v_p.more || ' more rides' else '' end;
    perform public.notify_send(v_p.wa_id, 'new_match', v_title, v_body, public.notify_explore_url(v_p.trip_key),
                               'match:' || v_p.wa_id || ':' || v_p.trip_key || ':' || v_p.next_stage);
  end loop;

  -- store stage on every request of every trip that was covered by a push
  update public.notify_requests r set alert_stage = s.next_stage
  from _pf_trips t join _pf_trip_state s on s.trip_key = t.trip_key
  where r.token = t.token and s.next_stage is not null and r.alert_stage < s.next_stage;

  -- everything processed this run is no longer "new"
  update public.notify_seen h set seeded = true
  from _pf_trips t where h.request_token = t.token and not h.seeded;
end;
$function$;

-- 4) notify_send_reminders (original)
CREATE OR REPLACE FUNCTION public.notify_send_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_m int;
  v_p record;
  v_req record;
  v_mins int;
  v_when text;
  v_count int;
  v_title text;
  v_body text;
  v_sent text[] := '{}';
begin
  if coalesce(public.notify_setting('reminder_enabled'), 'false') <> 'true' then
    return;
  end if;
  v_m := public.notify_setting('reminder_minutes_before')::int;

  -- trips (soonest first) that have a request due for a reminder
  for v_p in
    select t.wa_id, t.trip_key, min(r.starts_at) starts_at
    from public.notify_open_trips() t join public.notify_requests r on r.token = t.token
    where r.reminder_sent_at is null and r.starts_at is not null
      and now() between r.starts_at - make_interval(mins => v_m) and r.starts_at
    group by t.wa_id, t.trip_key
    order by t.wa_id, min(r.starts_at)
  loop
    if v_p.wa_id = any(v_sent) then
      continue;  -- one push per person per run; the rest go next run
    end if;

    select * into v_req from public.notify_requests where token = v_p.trip_key;
    select count(distinct s.id) into v_count
    from public.explore_search(v_req.mode, v_req.from_lat, v_req.from_lng, v_req.to_lat, v_req.to_lng, v_req.ride_date, '{}'::jsonb) s
    where s.parsed;

    if v_count > 0 then
      v_mins := ceil(ceil(extract(epoch from v_p.starts_at - now()) / 60) / 5.0)::int * 5;
      v_when := case when v_mins >= 60 then '1 hour' else v_mins || ' min' end;
      if v_req.mode = 'passengers' then
        v_title := 'You leave in ' || v_when || ' · ' || v_count || ' passenger' || case when v_count = 1 then '' else 's' end || ' looking';
        v_body := 'Get your passengers · ' || coalesce(v_req.label, '');
      else
        v_title := 'Your ride is in ' || v_when || ' · ' || v_count || ' driver' || case when v_count = 1 then '' else 's' end || ' available';
        v_body := 'Book your ride · ' || coalesce(v_req.label, '');
      end if;
      perform public.notify_send(v_p.wa_id, 'reminder', v_title, v_body, public.notify_explore_url(v_p.trip_key),
                                 'reminder:' || v_p.wa_id || ':' || v_p.trip_key);
      v_sent := v_sent || v_p.wa_id;
    end if;

    update public.notify_requests r set reminder_sent_at = now()
    from public.notify_open_trips() t
    where t.trip_key = v_p.trip_key and r.token = t.token and r.reminder_sent_at is null;
  end loop;
end;
$function$;

-- 5) notify_create_request (original)
CREATE OR REPLACE FUNCTION public.notify_create_request(p_wa_id text, p_mode text, p_from_lat double precision, p_from_lng double precision, p_to_lat double precision, p_to_lng double precision, p_from_label text, p_to_label text, p_ride_date date, p_label text, p_source_ref text DEFAULT NULL::text, p_name text DEFAULT NULL::text, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_token uuid;
  v_old public.notify_requests%rowtype;
begin
  if p_mode not in ('drivers', 'passengers') then
    raise exception 'invalid_mode';
  end if;

  if p_source_ref is not null then
    select * into v_old from public.notify_requests where source_ref = p_source_ref for update;
    if found then
      update public.notify_requests set
        wa_id = p_wa_id, mode = p_mode,
        from_lat = p_from_lat, from_lng = p_from_lng, to_lat = p_to_lat, to_lng = p_to_lng,
        from_label = p_from_label, to_label = p_to_label, ride_date = p_ride_date,
        label = p_label, name = p_name, starts_at = p_starts_at
      where token = v_old.token;

      if v_old.mode is distinct from p_mode
         or v_old.from_lat is distinct from p_from_lat or v_old.from_lng is distinct from p_from_lng
         or v_old.to_lat is distinct from p_to_lat or v_old.to_lng is distinct from p_to_lng
         or v_old.ride_date is distinct from p_ride_date
         or v_old.starts_at is distinct from p_starts_at then
        delete from public.notify_seen where request_token = v_old.token;
        insert into public.notify_seen (request_token, ride_ref, seeded)
        select v_old.token, s.id, true
        from public.explore_search(p_mode, p_from_lat, p_from_lng, p_to_lat, p_to_lng, p_ride_date, '{}'::jsonb) s
        on conflict do nothing;
        update public.notify_requests set alert_stage = 0, reminder_sent_at = null where token = v_old.token;
      end if;

      return v_old.token::text;
    end if;
  end if;

  insert into public.notify_requests (
    wa_id, mode, from_lat, from_lng, to_lat, to_lng, from_label, to_label, ride_date, label, source_ref, name, starts_at
  ) values (
    p_wa_id, p_mode, p_from_lat, p_from_lng, p_to_lat, p_to_lng, p_from_label, p_to_label, p_ride_date, p_label, p_source_ref, p_name, p_starts_at
  ) returning token into v_token;

  insert into public.notify_seen (request_token, ride_ref, seeded)
  select v_token, s.id, true
  from public.explore_search(p_mode, p_from_lat, p_from_lng, p_to_lat, p_to_lng, p_ride_date, '{}'::jsonb) s
  on conflict do nothing;

  return v_token::text;
end;
$function$;

-- 6) Remove the function added by this change (do this AFTER step 2, which stops referencing it)
DROP FUNCTION IF EXISTS public.bot_match_reply_via(text, double precision, double precision, double precision, double precision, text, text, text, text, integer, jsonb);
