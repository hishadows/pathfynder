-- =====================================================================
-- trip-join-rpcs-live.sql  (2026-09-29)  -- UNVERIFIED: never executed.
-- Supabase MCP was down when this was written, so nothing here has been run
-- or checked against the live schema. Pranay: run the PRE-FLIGHT query first,
-- compare with the ASSUMPTIONS, fix names if needed, then run Part A + B.
-- Supersedes design/trip-join-rpcs.sql (which only raised 'proposal only').
-- =====================================================================
--
-- PRE-FLIGHT (read-only). Run this alone and check every column below exists:
--
--   select table_name, column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--   where table_schema = 'public'
--     and table_name in ('driver_routines','passenger_requests','drivers')
--   order by table_name, ordinal_position;
--
--   -- also useful: any existing constraints/triggers that a booking insert must satisfy
--   select tgname, tgrelid::regclass from pg_trigger
--   where tgrelid in ('public.passenger_requests'::regclass) and not tgisinternal;
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--   where conrelid = 'public.passenger_requests'::regclass;
--
-- SCHEMA ASSUMPTIONS (the changelog does not list every column; verify each):
--  driver_routines (= trips): id uuid PK; driver_id (-> drivers.id); wa_id text;
--     origin_label text; dest_label text; stops jsonb (array, may be null);
--     depart_at timestamptz; available_seats int (= TOTAL seats offered, not decremented);
--     fare numeric (per seat; 0/null = no price); status text ('open' while bookable);
--     ended_at timestamptz. Returned join page fields that have no obvious column are
--     derived: round_trip = false, title = 'origin to dest'.
--  drivers: id uuid PK; name text (first word is shown as driver_first_name).
--  passenger_requests (= bookings): id uuid PK; ride_id (-> driver_routines.id);
--     wa_id text (digits only); name text; seats int; note text; status text;
--     removed_at timestamptz; created_at timestamptz; pickup_label/pickup_lat/pickup_lng;
--     dropoff_label/dropoff_lat/dropoff_lng.
--  ACTIVE booking = removed_at is null AND coalesce(status,'') not in
--     ('declined','cancelled','canceled','removed'). Real status values were not
--     found in the repo; the RPC writes status = 'confirmed' (joining = confirmed,
--     no driver approval, per plan task 7). NOTE: explore_search treats OPEN
--     passenger_requests as "needs ride" posts, so a 'confirmed' status is assumed
--     NOT to count as open in notify_request_open(); check that a booking does not
--     show up on Explore after a test join.
--  Inserting into passenger_requests fires the existing notify_sync_source trigger
--     (creates a notify token; failures only RAISE WARNING) - assumed harmless.
--  If passenger_requests has other NOT NULL columns (e.g. date/time/origin/dest),
--     the insert in trip_join will fail: add them to the insert list.
-- =====================================================================

-- =========================== PART A: join code =======================

alter table public.driver_routines add column if not exists join_code text;

create or replace function public.pf_gen_join_code()
returns text
language plpgsql volatile
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
revoke all on function public.pf_gen_join_code() from public;

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
    'title', coalesce(t.origin_label, '') || ' to ' || coalesce(t.dest_label, ''),
    'origin_label', t.origin_label,
    'dest_label', t.dest_label,
    'stops_count', case when jsonb_typeof(t.stops) = 'array' then jsonb_array_length(t.stops) else 0 end,
    'schedule_text', to_char(t.depart_at at time zone 'America/Toronto', 'Dy, Mon FMDD "·" FMHH12:MI AM'),
    'price_per_seat', case when coalesce(t.fare, 0) > 0 then t.fare else null end,
    'seats_total', v_total,
    'seats_left', v_left,
    'joined_count', v_joined
  );
end $$;
revoke all on function public._trip_join_trip_json(uuid) from public;

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

  select id, ended_at, status, depart_at into t
  from public.driver_routines where join_code = v_code;
  if not found then return jsonb_build_object('error', 'invalid_code'); end if;

  -- expired: ended/cancelled/completed, or departure more than 3 hours ago
  if t.ended_at is not null
     or coalesce(t.status, '') in ('cancelled', 'canceled', 'completed', 'ended')
     or (t.depart_at is not null and t.depart_at < now() - interval '3 hours') then
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
  select id, ended_at, status, depart_at, available_seats into t
  from public.driver_routines where join_code = v_code for update;
  if not found then return jsonb_build_object('error', 'invalid_code'); end if;

  if t.ended_at is not null
     or coalesce(t.status, '') in ('cancelled', 'canceled', 'completed', 'ended')
     or (t.depart_at is not null and t.depart_at < now() - interval '3 hours') then
    return jsonb_build_object('error', 'expired');
  end if;

  -- same whatsapp on same trip = update that booking (idempotent double submit)
  select id into v_ex_id
  from public.passenger_requests
  where ride_id = t.id and wa_id = v_wa
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
       set seats = p_seats, name = v_name, note = v_note, status = 'confirmed',
           pickup_label = v_plabel, pickup_lat = v_plat, pickup_lng = v_plng,
           dropoff_label = v_dlabel, dropoff_lat = v_dlat, dropoff_lng = v_dlng
     where id = v_ex_id
     returning id into v_id;
  else
    insert into public.passenger_requests
      (ride_id, wa_id, name, seats, note, status,
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

revoke all on function public.trip_join_get(text) from public;
revoke all on function public.trip_join(text, jsonb, jsonb, int, text, text, text) from public;
grant execute on function public.trip_join_get(text) to anon;
grant execute on function public.trip_join(text, jsonb, jsonb, int, text, text, text) to anon;

-- =====================================================================
-- PART C: trip_manage_get -> trip.join_url   (NOT auto-applied - read this)
-- The live body of trip_manage_get / _trip_manage_payload is not in the repo, so it is
-- NOT redefined here (would risk breaking the manage page). Do this instead:
--   1) select pg_get_functiondef(p.oid) from pg_proc p
--      where p.proname in ('_trip_manage_payload','trip_manage_get');
--   2) Find where the 'trip' jsonb object is built (likely _trip_manage_payload; it may
--      already contain 'join_url', null). Set that key to:
--         'join_url', case when <trip_row>.join_code is not null
--                          then 'https://pathfynder.ca/j/' || <trip_row>.join_code end
--      (replace <trip_row> with the driver_routines row alias/variable in that function).
--   3) Re-run that function with CREATE OR REPLACE (same signature keeps grants).
-- Check: open /m/<token> and Invite passengers shares https://pathfynder.ca/j/<CODE>.
-- Paste the function body back to Claude if you want it patched for you.
-- =====================================================================
