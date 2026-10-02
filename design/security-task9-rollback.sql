-- Rollback for migration sec_task9_hq_pass_and_phase_c (project omussxfyrztjahbdrrpi)
-- Recorded pre-change ACLs (pg_class / pg_proc, 2026-10-02):
--   extracted_data_01: anon/authenticated = awdDxtm (no SELECT at table level; column SELECT on id, "Type", "pick up date", pickup_lat)
--   muse_ride_posts, notify_log: anon/authenticated = arwdDxtm (all)
--   match_driver_to_scraped_passengers(uuid): PUBLIC, anon, authenticated, service_role EXECUTE

-- New objects
DROP FUNCTION IF EXISTS public.hq_check(text);
DROP FUNCTION IF EXISTS public.get_feed(timestamptz, timestamptz, text, text, integer, integer, text);
DROP FUNCTION IF EXISTS public.get_power_users(timestamptz, timestamptz, text, integer, text);

-- B. match_driver_to_scraped_passengers
GRANT EXECUTE ON FUNCTION public.match_driver_to_scraped_passengers(uuid) TO PUBLIC, anon, authenticated, service_role;

-- C. muse_ride_posts column-level SELECT back to table-level
REVOKE SELECT (id, external_id, platform, post_type, author, origin, destination, ride_date, ride_time, time_bucket, seats, price, source_url, raw_text, posted_at, fetched_at, fingerprint, duplicate_of, origin_city, destination_city, is_commercial, origin_lat, origin_lng, dest_lat, dest_lng, origin_place, dest_place, origin_place_id, dest_place_id, departing_at, arriving_at, creator_id, creator_rating, creator_rating_count, creator_verified, group_name, group_id, options, instant_book, parent_id, origin_geo, dest_geo, last_seen_at, listing_state) ON public.muse_ride_posts FROM anon, authenticated;
GRANT SELECT ON public.muse_ride_posts TO anon, authenticated;

-- D. write privileges
GRANT INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.muse_ride_posts TO anon, authenticated;
-- extracted_data_01 originally had a,w,d,D,x,t,m (INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN) and no SELECT
GRANT INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.extracted_data_01 TO anon, authenticated;
GRANT ALL ON public.notify_log TO anon, authenticated;
