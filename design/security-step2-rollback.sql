-- Rollback for migration sec_step2_hide_sender_number. NOT applied.
-- Prior state: anon & authenticated had table-level SELECT (all columns) on both tables.

-- 1. Tables
REVOKE SELECT (id, "pick up date", pickup_lat, "Type") ON public.extracted_data_01 FROM anon, authenticated;
GRANT SELECT ON public.extracted_data_01 TO anon, authenticated;
REVOKE SELECT (id, "pick up date", "Type") ON public."Extracted data" FROM anon, authenticated;
GRANT SELECT ON public."Extracted data" TO anon, authenticated;
-- rides_v untouched (anon/authenticated retain full table grants as before).

-- 2. Stats functions back to SECURITY INVOKER, no proconfig
ALTER FUNCTION public.get_demand_signals() SECURITY INVOKER RESET search_path;
ALTER FUNCTION public.get_window_stats(timestamptz, timestamptz) SECURITY INVOKER RESET search_path;
ALTER FUNCTION public.get_daily_series(timestamptz, timestamptz) SECURITY INVOKER RESET search_path;
ALTER FUNCTION public.get_hourly_activity() SECURITY INVOKER RESET search_path;
ALTER FUNCTION public.get_top_corridors(integer) SECURITY INVOKER RESET search_path;
ALTER FUNCTION public.get_top_groups(integer) SECURITY INVOKER RESET search_path;

-- 3. Restore EXECUTE (original ACL: PUBLIC, postgres, anon, authenticated, service_role)
GRANT EXECUTE ON FUNCTION public.find_matched_passengers(uuid,double precision,double precision,double precision,double precision,date,double precision) TO public, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_extracted_data_01(double precision,double precision,double precision,double precision,double precision,date,time without time zone,double precision) TO public, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_passenger_requests(double precision,double precision,double precision,double precision,double precision,date,time without time zone,double precision) TO public, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.match_drivers_to_all_passengers(double precision,double precision,double precision,double precision,time with time zone,date,text,integer) TO public, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.match_drivers_to_all_passengers(double precision,double precision,double precision,double precision,time without time zone,date,text,integer,integer,integer,integer) TO public, anon, authenticated, service_role;

-- 4. Migration sec_step2_hq_functions_definer reverse
ALTER FUNCTION public.get_feed(timestamptz,timestamptz,text,text,integer,integer) SECURITY INVOKER RESET search_path;
ALTER FUNCTION public.get_power_users(timestamptz,timestamptz,text,integer) SECURITY INVOKER RESET search_path;
