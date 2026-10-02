-- Rollback for migration explore_show_phones_fb_poparide_raw_text (2026-10-02)
-- ACL before: {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.explore_search(p_mode text DEFAULT 'drivers'::text, p_o_lat double precision DEFAULT NULL::double precision, p_o_lng double precision DEFAULT NULL::double precision, p_d_lat double precision DEFAULT NULL::double precision, p_d_lng double precision DEFAULT NULL::double precision, p_date date DEFAULT NULL::date, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(id text, source text, role text, display_name text, origin_label text, dest_label text, ride_date date, ride_time text, arrive_time text, seats integer, price text, price_num numeric, rating numeric, rating_count integer, verified boolean, luggage text, recurring_label text, posted_count integer, groups jsonb, posted_at timestamp with time zone, is_business boolean, is_coordinator boolean, is_regular boolean, parsed boolean, match_type text, pickup_km numeric, dropoff_km numeric, route_km numeric, pickup_pct numeric, dropoff_pct numeric, score integer, description text, raw_text text, is_urgent boolean, is_airport boolean, is_daily boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select c.id, c.source, c.role, c.display_name, c.origin_label, c.dest_label, c.ride_date, c.ride_time, c.arrive_time,
         c.seats, c.price, c.price_num, c.rating, c.rating_count, c.verified, c.luggage, c.recurring_label,
         c.posted_count, c.groups, c.posted_at, c.is_business, c.is_coordinator, c.is_regular, c.parsed,
         c.match_type, c.pickup_km, c.dropoff_km, c.route_km, c.pickup_pct, c.dropoff_pct, c.score,
         px_mask_phone(c.description), px_mask_phone(c.raw_text),
         c.is_urgent, c.is_airport, c.is_daily
  from explore_search_core(p_mode, p_o_lat, p_o_lng, p_d_lat, p_d_lng, p_date, p_filters) c
$function$;
