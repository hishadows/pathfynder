-- PROPOSAL ONLY - not applied. Contract for the passenger join page (/j/<code>, join.html).
-- Built on existing tables: driver_routines = trips, passenger_requests (ride_id) = bookings.
-- Both RPCs are callable by anon; access is only via the trip join code. Never return phone numbers.

-- 1) Load a trip for the join page.
-- Returns: { "trip": {
--     "code": text, "status": "open" | "full",
--     "driver_first_name": text, "round_trip": bool, "title": text,
--     "origin_label": text, "dest_label": text, "stops_count": int,
--     "schedule_text": text,          -- read-only, e.g. 'Mon, Tue, Wed, Thu, Fri · 7:30 AM out · 5:15 PM back'
--     "price_per_seat": numeric | null,
--     "seats_total": int, "seats_left": int, "joined_count": int } }
--   or { "error": "invalid_code" } | { "error": "expired" }   -- unknown code / trip ended or cancelled
create or replace function public.trip_join_get(p_code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
begin
  -- TODO: look up driver_routines by join code; compute seats_left = seats_total - sum(seats of confirmed bookings).
  raise exception 'proposal only';
end $$;

-- 2) Book a seat directly (no driver approval). Must be atomic: lock the trip row (FOR UPDATE),
--    re-count seats, and refuse when p_seats > seats_left.
-- p_pickup / p_dropoff: { "label": text, "lat": float, "lng": float }
-- p_whatsapp: digits only incl. country code, e.g. '16475550123'
-- Returns: { "booking": { "id", "seats", "status": "confirmed", "pickup_label", "dropoff_label" },
--            "trip": <same shape as trip_join_get.trip, with updated seats_left / joined_count> }
--   or { "error": "full" }           -- not enough seats left (seat taken meanwhile)
--    | { "error": "invalid_code" } | { "error": "expired" }
--    | { "error": "invalid_input" }  -- bad seats (<1), empty name, malformed number, missing coords
-- Same whatsapp on the same trip = update the existing booking, not a duplicate (idempotent double-submit).
create or replace function public.trip_join(
  p_code text, p_pickup jsonb, p_dropoff jsonb, p_seats int,
  p_name text, p_whatsapp text, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
begin
  raise exception 'proposal only';
end $$;

-- grant execute on function public.trip_join_get(text) to anon;
-- grant execute on function public.trip_join(text, jsonb, jsonb, int, text, text, text) to anon;
