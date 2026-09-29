-- =====================================================================
-- trip-join-rpcs-live.sql  (2026-09-29)
-- Verified against the live schema on 2026-09-29 (project omussxfyrztjahbdrrpi).
-- Applied as migrations: trip_join_rpcs_live (Parts A+B),
--   trip_manage_payload_join_url (Part C),
--   passenger_requests_notify_triggers_pending_only (Part D).
-- Supersedes design/trip-join-rpcs.sql (which only raised 'proposal only').
--
-- Live column mapping used below:
--  driver_routines (= trips): pickup_label, dropoff_label, departure_datetime
--     (timestamptz, nullable; recurring rows use dates + departure_time),
--     available_seats (TOTAL seats), fare, ride_status ('open'|'started'), is_active,
--     ended_at, stops, driver_id -> drivers(id, name).
--  passenger_requests (= bookings): passenger_wa_id, passenger_name, seats, note,
--     status, removed_at, ride_id, pickup_*/dropoff_* (lat/lng NOT NULL).
--  Expiry = ended_at not null OR is_active = false OR ride_status in
--     (cancelled, canceled, completed, ended) OR departure_datetime < now() - 3h.
--  round_trip = false (each leg is its own row).
--  Bookings are written with status 'confirmed'; notify_request_open treats
--     non-pending as closed, so they do not show as open requests. Part D stops the
--     n8n "new request" alerts from firing for them.
-- =====================================================================

-- =========================== PART A: join code =======================

alter table public.driver_routines add column if not exists join_code text;

create or replace function public.pf_gen_join_code()
returns text
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; -- no 0 O 1 I L
  c text;
  i int;
begin
  loop
    c := '';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.driver_routines where join_code = c);
  end loop;
  return c;
end $$;

-- Backfill row by row (so each generated code sees the previous ones).
do $$
declare r record;
begin
  for r in select id from public.driver_routines where join_code is null loop
    update public.driver_routines set join_code = public.pf_gen_join_code() where id = r.id;
  end loop;
end $$;

-- New trips (bot rows, trip_post) get a code automatically via the default.
alter table public.driver_routines alter column join_code set default public.pf_gen_join_code();
create unique index if not exists driver_routines_join_code_key on public.driver_routines (join_code);

-- Not callable from the browser; only used as a column default.
revoke all on function public.pf_gen_join_code() from public, anon, authenticated;

-- ====================== PART B: join RPCs ===========================

-- Internal: builds the { trip } object shape join.html expects. Never returns phone numbers.
create or replace function public._trip_join_trip_json(p_trip_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  t record;
  v_first text;
  v_joined int;
  v_left int;
  v_total int;
begin
  select * into t from public.driver_routines where id = p_trip_id;
  if not found then return null; end if;

  select nullif(split_part(trim(coalesce(d.name, '')), ' ', 1), '') into v_first
  from public.drivers d where d.id = t.driver_id;

  v_total := greatest(coalesce(t.available_seats, 0), 0);

  select coalesce(sum(greatest(coalesce(b.seats, 1), 1)), 0)::int,
         count(*)::int
    into v_left, v_joined
  from public.passenger_requests b
  where b.ride_id = t.id
    and b.removed_at is null
    and coalesce(b.status, '') not in ('declined', 'cancelled', 'canceled', 'removed');

  v_left := greatest(v_total - v_left, 0);

  return jsonb_build_object(
    'code', t.join_code,
    'status', case when v_left <= 0 then 'full' else 'open' end,
    'driver_first_name', coalesce(v_first, 'Your driver'),
    'round_trip', false,  -- assumption: each leg is its own driver_routines row
    'title', coalesce(t.pickup_label, '') || ' to ' || coalesce(t.dropoff_label, ''),
    'origin_label', t.pickup_label,
    'dest_label', t.dropoff_label,
    'stops_count', case when jsonb_typeof(t.stops) = 'array' then jsonb_array_length(t.stops) else 0 end,
    'schedule_text', case
      when t.departure_datetime is not null
        then to_char(t.departure_datetime at time zone 'America/Toronto', 'Dy, Mon FMDD "·" FMHH12:MI AM')
      when t.departure_time is not null
        then 'Recurring · ' || to_char(t.departure_time, 'FMHH12:MI AM')
      else null end,
    'price_per_seat', case when coalesce(t.fare, 0) > 0 then t.fare else null end,
    'seats_total', v_total,
    'seats_left', v_left,
    'joined_count', v_joined
  );
end $$;
revoke all on function public._trip_join_trip_json(uuid) from public, anon, authenticated;

-- Returns { trip: {...} } | { error: 'invalid_code' } | { error: 'expired' }
create or replace function public.trip_join_get(p_code text)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  t record;
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  if v_code = '' then return jsonb_build_object('error', 'invalid_code'); end if;

  select id, ended_at, is_active, ride_status, departure_datetime into t
  from public.driver_routines where join_code = v_code;
  if not found then return jsonb_build_object('error', 'invalid_code'); end if;

  -- expired: ended/cancelled/completed, or departure more than 3 hours ago
  if t.ended_at is not null
     or coalesce(t.is_active, false) = false
     or coalesce(t.ride_status, '') in ('cancelled', 'canceled', 'completed', 'ended')
     or (t.departure_datetime is not null and t.departure_datetime < now() - interval '3 hours') then
    return jsonb_build_object('error', 'expired');
  end if;

  return jsonb_build_object('trip', public._trip_join_trip_json(t.id));
end $$;

-- p_pickup / p_dropoff: { label, lat, lng }; p_whatsapp: digits incl. country code.
-- Returns { booking, trip } | { error: invalid_code|expired|full|invalid_input }
create or replace function public.trip_join(
  p_code text, p_pickup jsonb, p_dropoff jsonb, p_seats int,
  p_name text, p_whatsapp text, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_wa text := regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g');
  v_name text := trim(coalesce(p_name, ''));
  v_note text := nullif(left(trim(coalesce(p_note, '')), 300), '');
  t record;
  v_ex_id uuid;
  v_taken int;
  v_left int;
  v_id uuid;
  v_plabel text; v_dlabel text;
  v_plat float8; v_plng float8; v_dlat float8; v_dlng float8;
begin
  -- input validation (before touching the trip)
  if v_code = '' then return jsonb_build_object('error', 'invalid_code'); end if;
  if p_seats is null or p_seats < 1 or p_seats > 8 then return jsonb_build_object('error', 'invalid_input'); end if;
  if v_name = '' or length(v_name) > 80 then return jsonb_build_object('error', 'invalid_input'); end if;
  if length(v_wa) < 10 or length(v_wa) > 15 then return jsonb_build_object('error', 'invalid_input'); end if;
  if p_pickup is null or p_dropoff is null
     or jsonb_typeof(p_pickup) <> 'object' or jsonb_typeof(p_dropoff) <> 'object' then
    return jsonb_build_object('error', 'invalid_input');
  end if;

  begin
    v_plabel := nullif(trim(p_pickup->>'label'), '');
    v_dlabel := nullif(trim(p_dropoff->>'label'), '');
    v_plat := (p_pickup->>'lat')::float8;  v_plng := (p_pickup->>'lng')::float8;
    v_dlat := (p_dropoff->>'lat')::float8; v_dlng := (p_dropoff->>'lng')::float8;
  exception when others then
    return jsonb_build_object('error', 'invalid_input');
  end;
  if v_plabel is null or v_dlabel is null
     or v_plat is null or v_plng is null or v_dlat is null or v_dlng is null
     or v_plat not between -90 and 90 or v_dlat not between -90 and 90
     or v_plng not between -180 and 180 or v_dlng not between -180 and 180 then
    return jsonb_build_object('error', 'invalid_input');
  end if;

  -- lock the trip row so concurrent joins serialise
  select id, ended_at, is_active, ride_status, departure_datetime, available_seats into t
  from public.driver_routines where join_code = v_code for update;
  if not found then return jsonb_build_object('error', 'invalid_code'); end if;

  if t.ended_at is not null
     or coalesce(t.is_active, false) = false
     or coalesce(t.ride_status, '') in ('cancelled', 'canceled', 'completed', 'ended')
     or (t.departure_datetime is not null and t.departure_datetime < now() - interval '3 hours') then
    return jsonb_build_object('error', 'expired');
  end if;

  -- same whatsapp on same trip = update that booking (idempotent double submit)
  select id into v_ex_id
  from public.passenger_requests
  where ride_id = t.id and passenger_wa_id = v_wa
    and removed_at is null
    and coalesce(status, '') not in ('declined', 'cancelled', 'canceled', 'removed')
  order by created_at desc nulls last
  limit 1;

  select coalesce(sum(greatest(coalesce(seats, 1), 1)), 0)::int into v_taken
  from public.passenger_requests
  where ride_id = t.id
    and removed_at is null
    and coalesce(status, '') not in ('declined', 'cancelled', 'canceled', 'removed')
    and id is distinct from v_ex_id;   -- an existing booking is replaced, not added on top

  v_left := greatest(coalesce(t.available_seats, 0), 0) - v_taken;
  if p_seats > v_left then return jsonb_build_object('error', 'full'); end if;

  if v_ex_id is not null then
    update public.passenger_requests
       set seats = p_seats, passenger_name = v_name, note = v_note, status = 'confirmed',
           pickup_label = v_plabel, pickup_lat = v_plat, pickup_lng = v_plng,
           dropoff_label = v_dlabel, dropoff_lat = v_dlat, dropoff_lng = v_dlng
     where id = v_ex_id
     returning id into v_id;
  else
    insert into public.passenger_requests
      (ride_id, passenger_wa_id, passenger_name, seats, note, status,
       pickup_label, pickup_lat, pickup_lng, dropoff_label, dropoff_lat, dropoff_lng)
    values
      (t.id, v_wa, v_name, p_seats, v_note, 'confirmed',
       v_plabel, v_plat, v_plng, v_dlabel, v_dlat, v_dlng)
    returning id into v_id;
  end if;

  return jsonb_build_object(
    'booking', jsonb_build_object(
      'id', v_id, 'seats', p_seats, 'status', 'confirmed',
      'pickup_label', v_plabel, 'dropoff_label', v_dlabel),
    'trip', public._trip_join_trip_json(t.id));
end $$;

revoke all on function public.trip_join_get(text) from public, anon;
revoke all on function public.trip_join(text, jsonb, jsonb, int, text, text, text) from public, anon;
grant execute on function public.trip_join_get(text) to anon;
grant execute on function public.trip_join(text, jsonb, jsonb, int, text, text, text) to anon;


-- =====================================================================
-- PART C: trip_manage_get -> trip.join_url  (applied: trip_manage_payload_join_url)
-- Only change vs the live body: 'join_url', null  ->  case when r.join_code ...
-- =====================================================================
create or replace function public._trip_manage_payload(p_driver_id uuid, p_trip_id uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
as $function$
declare v jsonb;
begin
  select jsonb_build_object(
    'trip', jsonb_build_object(
      'id', r.id,
      'status', case when r.ended_at is not null then 'completed'
                     when r.ride_status = 'started' or r.started_at is not null then 'active'
                     else 'draft' end,
      'driver_name', d.name,
      'origin_label', r.pickup_label, 'origin_lat', r.pickup_lat, 'origin_lng', r.pickup_lng,
      'dest_label', r.dropoff_label, 'dest_lat', r.dropoff_lat, 'dest_lng', r.dropoff_lng,
      'depart_at', coalesce(r.departure_datetime, ((r.dates + r.departure_time) at time zone 'America/Toronto')),
      'seats_total', r.available_seats,
      'price_per_seat', r.fare,
      'stops', r.stops,
      'note', r.notes,
      'join_url', case when r.join_code is not null then 'https://pathfynder.ca/j/' || r.join_code end),
    'bookings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'name', coalesce(p.passenger_name_web, p.passenger_name),
        'phone', regexp_replace(coalesce(p.passenger_phone_web, p.passenger_wa_id, ''), '\D', '', 'g'),
        'seats', p.seats,
        'pickup_label', p.pickup_label, 'pickup_lat', p.pickup_lat, 'pickup_lng', p.pickup_lng,
        'dropoff_label', p.dropoff_label, 'dropoff_lat', p.dropoff_lat, 'dropoff_lng', p.dropoff_lng,
        'pickup_time', p.pickup_time::text,
        'created_at', p.created_at,
        'picked_up_at', p.picked_up_at,
        'dropped_off_at', p.dropped_off_at,
        'note', p.note) order by p.created_at)
      from public.passenger_requests p
      where p.ride_id = r.id and p.removed_at is null), '[]'::jsonb))
  into v
  from public.driver_routines r join public.drivers d on d.id = r.driver_id
  where r.id = p_trip_id and r.driver_id = p_driver_id;
  return v;
end $function$;

-- =====================================================================
-- PART D: n8n "new request" triggers fire for pending rows only
-- (applied: passenger_requests_notify_triggers_pending_only)
-- trip_join inserts status 'confirmed', which must not raise a "new request" alert.
-- Existing pending flows (bot, web) are unchanged.
-- =====================================================================
drop trigger if exists notify_n8n_passenger_request on public.passenger_requests;
create trigger notify_n8n_passenger_request
  after insert on public.passenger_requests
  for each row when (NEW.status = 'pending')
  execute function supabase_functions.http_request(
    'https://pathy.dpdns.org/webhook/notify_n8n_passenger_request', 'POST',
    '{"Content-type":"application/json"}', '{}', '5000');

drop trigger if exists trg_new_passenger_request on public.passenger_requests;
create trigger trg_new_passenger_request
  after insert on public.passenger_requests
  for each row when (NEW.status = 'pending')
  execute function notify_n8n_on_new_request();

-- ROLLBACK for Part D (restores the original unconditional triggers):
--   drop trigger if exists notify_n8n_passenger_request on public.passenger_requests;
--   create trigger notify_n8n_passenger_request
--     after insert on public.passenger_requests for each row
--     execute function supabase_functions.http_request(
--       'https://pathy.dpdns.org/webhook/notify_n8n_passenger_request', 'POST',
--       '{"Content-type":"application/json"}', '{}', '5000');
--   drop trigger if exists trg_new_passenger_request on public.passenger_requests;
--   create trigger trg_new_passenger_request
--     after insert on public.passenger_requests for each row
--     execute function notify_n8n_on_new_request();
