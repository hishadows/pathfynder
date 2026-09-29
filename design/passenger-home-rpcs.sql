-- =====================================================================
-- passenger-home-rpcs.sql  (2026-09-29)
-- Backend for the passenger home page /p/<token> (passenger.html).
-- Applied (project omussxfyrztjahbdrrpi) as three migrations:
--   1. passenger_tokens_and_trip_join_token        (PART 1)
--   2. passenger_home_rpcs                         (PART 2)
--   3. passenger_request_post_and_notifications    (PART 3)
-- Runnable top to bottom (idempotent: create-if-not-exists / create or replace).
--
-- IDENTITY MODEL
--   The WhatsApp number typed on the join form is UNVERIFIED, so a token is per
--   device/join: every trip_join call without a valid passenger token mints a NEW
--   passengers row (and manage_token). A token only ever sees bookings/requests
--   linked to it through passenger_requests.passenger_id. An existing token is
--   reused only when its wa_id equals the submitted number.
--
-- NOTIFICATIONS KEY (deliberate deviation from "keyed by wa_id")
--   Passenger push/notify rows use the synthetic key  'pax:' || passengers.id
--   in notify_log.wa_id and notify_subscriptions.wa_id (the push-send edge function
--   just matches that string, so it needs no change). Reason: notification urls
--   contain the passenger token (/p/<token>?b=...); keying by the (unverified)
--   phone number would let anyone who types a victim's number read/receive the
--   victim's alerts and take over their token. It also keeps driver and passenger
--   notify_log rows fully separate.
-- =====================================================================


-- =====================================================================
-- PART 1: passengers table, passenger_requests.passenger_id, trip_join
-- (migration: passenger_tokens_and_trip_join_token)
-- =====================================================================

create table if not exists public.passengers (
  id           uuid primary key default gen_random_uuid(),
  wa_id        text not null,
  name         text,
  photo        text,
  manage_token text not null unique
    default substr(replace(replace(encode(extensions.gen_random_bytes(18), 'base64'), '+', '-'), '/', '_'), 1, 24),
  created_at   timestamptz default now()
);
create index if not exists passengers_wa_id_idx on public.passengers (wa_id);

alter table public.passengers enable row level security;   -- no policies: RPC-only access
revoke all on table public.passengers from anon, authenticated;

alter table public.passenger_requests
  add column if not exists passenger_id uuid references public.passengers(id);
create index if not exists passenger_requests_passenger_id_idx
  on public.passenger_requests (passenger_id) where passenger_id is not null;

-- New optional parameter appended at the end: existing anon callers (7 named args) keep working.
drop function if exists public.trip_join(text, jsonb, jsonb, int, text, text, text);

create or replace function public.trip_join(
  p_code text, p_pickup jsonb, p_dropoff jsonb, p_seats int,
  p_name text, p_whatsapp text, p_note text default null,
  p_passenger_token text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_wa text := regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g');
  v_name text := trim(coalesce(p_name, ''));
  v_note text := nullif(left(trim(coalesce(p_note, '')), 300), '');
  v_ptok_in text := nullif(trim(coalesce(p_passenger_token, '')), '');
  t record;
  v_pid uuid; v_ptok text;
  v_ex_id uuid;
  v_taken int;
  v_left int;
  v_id uuid;
  v_plabel text; v_dlabel text;
  v_plat float8; v_plng float8; v_dlat float8; v_dlng float8;
  v_ins boolean := false;
  v_dwa text; v_tok text; v_first text; v_lft int; v_title text; v_body text;
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

  -- reuse a passenger token only when it belongs to the SAME submitted number
  if v_ptok_in is not null then
    select id, manage_token into v_pid, v_ptok
    from public.passengers where manage_token = v_ptok_in and wa_id = v_wa;
  end if;

  -- same passenger (token) on same trip = update that booking (idempotent double submit)
  if v_pid is not null then
    select id into v_ex_id
    from public.passenger_requests
    where ride_id = t.id and passenger_id = v_pid
      and removed_at is null
      and coalesce(status, '') not in ('declined', 'cancelled', 'canceled', 'removed')
    order by created_at desc nulls last
    limit 1;
  end if;

  select coalesce(sum(greatest(coalesce(seats, 1), 1)), 0)::int into v_taken
  from public.passenger_requests
  where ride_id = t.id
    and removed_at is null
    and coalesce(status, '') not in ('declined', 'cancelled', 'canceled', 'removed')
    and id is distinct from v_ex_id;   -- an existing booking is replaced, not added on top

  v_left := greatest(coalesce(t.available_seats, 0), 0) - v_taken;
  if p_seats > v_left then return jsonb_build_object('error', 'full'); end if;

  -- no valid token for this number: mint a NEW passenger token (never hand out an existing one)
  if v_pid is null then
    insert into public.passengers (wa_id, name) values (v_wa, v_name)
    returning id, manage_token into v_pid, v_ptok;
  end if;

  if v_ex_id is not null then
    update public.passenger_requests
       set seats = p_seats, passenger_name = v_name, note = v_note, status = 'confirmed',
           pickup_label = v_plabel, pickup_lat = v_plat, pickup_lng = v_plng,
           dropoff_label = v_dlabel, dropoff_lat = v_dlat, dropoff_lng = v_dlng,
           passenger_id = v_pid
     where id = v_ex_id
     returning id into v_id;
  else
    insert into public.passenger_requests
      (ride_id, passenger_wa_id, passenger_name, seats, note, status,
       pickup_label, pickup_lat, pickup_lng, dropoff_label, dropoff_lat, dropoff_lng, passenger_id)
    values
      (t.id, v_wa, v_name, p_seats, v_note, 'confirmed',
       v_plabel, v_plat, v_plng, v_dlabel, v_dlat, v_dlng, v_pid)
    returning id into v_id;
    v_ins := true;
  end if;

  -- notify the driver (web push) about a NEW booking only; never fail the booking
  if v_ins then
    begin
      select coalesce(nullif(dr.driver_wa_id, ''), d.wa_id), d.manage_token
        into v_dwa, v_tok
      from public.driver_routines dr
      left join public.drivers d on d.id = dr.driver_id
      where dr.id = t.id;

      if nullif(v_dwa, '') is not null and nullif(v_tok, '') is not null then
        v_lft := v_left - p_seats;
        v_first := split_part(v_name, ' ', 1);
        v_title := left(coalesce(nullif(v_first, ''), 'A passenger'), 40) || ' joined your ride';
        v_body := p_seats || case when p_seats = 1 then ' seat' else ' seats' end
          || ' · ' || initcap(trim(split_part(v_plabel, ',', 1)))
          || ' → ' || initcap(trim(split_part(v_dlabel, ',', 1)))
          || ' · ' || case when v_lft <= 0 then 'Ride is now full'
                           else v_lft || case when v_lft = 1 then ' seat left' else ' seats left' end end;
        perform public.notify_send(v_dwa, 'passenger_joined', v_title, v_body,
                                   '/m/' || v_tok || '?t=' || t.id::text, 'join:' || v_id::text);
      end if;
    exception when others then
      null;  -- notification failure must never affect the booking
    end;
  end if;

  return jsonb_build_object(
    'booking', jsonb_build_object(
      'id', v_id, 'seats', p_seats, 'status', 'confirmed',
      'pickup_label', v_plabel, 'dropoff_label', v_dlabel),
    'trip', public._trip_join_trip_json(t.id),
    'passenger_token', v_ptok);
end $$;

revoke all on function public.trip_join(text, jsonb, jsonb, int, text, text, text, text) from public, anon;
grant execute on function public.trip_join(text, jsonb, jsonb, int, text, text, text, text) to anon;

-- ROLLBACK for PART 1 (restores the Part E body from design/trip-join-rpcs-live.sql):
--   drop function if exists public.trip_join(text, jsonb, jsonb, int, text, text, text, text);
--   -- then re-run "PART E" of design/trip-join-rpcs-live.sql (7-arg trip_join + grants)
--   drop index if exists public.passenger_requests_passenger_id_idx;
--   alter table public.passenger_requests drop column if exists passenger_id;
--   drop table if exists public.passengers;


-- =====================================================================
-- PART 2: read / cancel / profile RPCs  (migration: passenger_home_rpcs)
-- All: security definer, search_path public+extensions, token based,
-- invalid token -> {error:'invalid_token'}. Never return wa_id / other passengers' data.
-- =====================================================================

-- Internal helper: the next four functions share this booking-status mapping.
create or replace function public._pax_booking_status(
  p_status text, p_removed timestamptz, p_picked timestamptz, p_dropped timestamptz,
  p_started timestamptz, p_ended timestamptz, p_ride_status text)
returns text
language sql immutable
as $$
  select case
    when coalesce(p_status, '') in ('cancelled', 'canceled') or p_removed is not null
      or coalesce(p_ride_status, '') in ('cancelled', 'canceled') then 'cancelled'
    when p_dropped is not null or p_ended is not null then 'completed'
    when p_picked is not null then 'picked_up'
    when p_started is not null or coalesce(p_ride_status, '') = 'started' then 'active'
    else 'upcoming' end
$$;
revoke all on function public._pax_booking_status(text, timestamptz, timestamptz, timestamptz, timestamptz, timestamptz, text) from public, anon, authenticated;

-- { rides:[{booking_id, trip_id, depart_at, status, kind:'booking', origin_label, dest_label}],
--   requests:[{id, depart_at, pickup_label, dropoff_label, seats, status, kind:'request'}] }
-- Rides include cancelled / driver-removed bookings (status 'cancelled') so the passenger can see them.
create or replace function public.passenger_home_list(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare ps public.passengers; v_rides jsonb; v_reqs jsonb;
begin
  select * into ps from public.passengers where manage_token = nullif(trim(coalesce(p_token, '')), '');
  if not found then return jsonb_build_object('error', 'invalid_token'); end if;

  select coalesce(jsonb_agg(x.j order by x.d, x.c), '[]'::jsonb) into v_rides
  from (
    select coalesce(r.departure_datetime, ((r.dates + r.departure_time) at time zone 'America/Toronto')) d,
           pr.created_at c,
           jsonb_build_object(
             'booking_id', pr.id, 'trip_id', r.id,
             'depart_at', coalesce(r.departure_datetime, ((r.dates + r.departure_time) at time zone 'America/Toronto')),
             'status', public._pax_booking_status(pr.status, pr.removed_at, pr.picked_up_at, pr.dropped_off_at, r.started_at, r.ended_at, r.ride_status),
             'kind', 'booking',
             'origin_label', r.pickup_label, 'dest_label', r.dropoff_label) j
    from public.passenger_requests pr
    join public.driver_routines r on r.id = pr.ride_id
    where pr.passenger_id = ps.id
    order by 1, 2
    limit 200
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', pr.id, 'depart_at', pr.requested_datetime,
           'pickup_label', pr.pickup_label, 'dropoff_label', pr.dropoff_label,
           'seats', pr.seats, 'status', pr.status, 'kind', 'request')
         order by pr.requested_datetime, pr.created_at), '[]'::jsonb) into v_reqs
  from public.passenger_requests pr
  where pr.passenger_id = ps.id and pr.ride_id is null
    and pr.status = 'pending' and pr.removed_at is null;

  return jsonb_build_object('rides', v_rides, 'requests', v_reqs);
end $$;

-- One booking with its trip. Driver phone = digits only (for tel:/wa.me hrefs).
-- Other passengers: counts only.
create or replace function public.passenger_trip_get(p_token text, p_booking_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  ps public.passengers; b public.passenger_requests; r public.driver_routines; d public.drivers;
  v_phone text; v_cnt int; v_picked int; v_tstatus text; v_bstatus text;
begin
  select * into ps from public.passengers where manage_token = nullif(trim(coalesce(p_token, '')), '');
  if not found then return jsonb_build_object('error', 'invalid_token'); end if;

  select * into b from public.passenger_requests
   where id = p_booking_id and passenger_id = ps.id and ride_id is not null;
  if not found then return jsonb_build_object('error', 'not_found'); end if;

  select * into r from public.driver_routines where id = b.ride_id;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  select * into d from public.drivers where id = r.driver_id;

  v_tstatus := case
    when coalesce(r.ride_status, '') in ('cancelled', 'canceled') then 'cancelled'
    when r.ended_at is not null then 'completed'
    when r.started_at is not null or coalesce(r.ride_status, '') = 'started' then 'active'
    else 'upcoming' end;
  v_bstatus := public._pax_booking_status(b.status, b.removed_at, b.picked_up_at, b.dropped_off_at, r.started_at, r.ended_at, r.ride_status);

  v_phone := regexp_replace(coalesce(
    nullif(r.driver_phone, ''),
    (select tu.whatsapp_number from public.telegram_users tu
      where d.wa_id is not null and (tu.telegram_chat_id = d.wa_id or tu.telegram_user_id = d.wa_id) limit 1),
    ''), '\D', '', 'g');
  if length(v_phone) < 7 then v_phone := null; end if;

  -- same counting as the driver page: one per active booking row
  select count(*)::int, count(*) filter (where p.picked_up_at is not null)::int
    into v_cnt, v_picked
  from public.passenger_requests p
  where p.ride_id = r.id and p.removed_at is null
    and coalesce(p.status, '') not in ('declined', 'cancelled', 'canceled', 'removed');

  return jsonb_build_object(
    'trip', jsonb_build_object(
      'id', r.id, 'status', v_tstatus,
      'depart_at', coalesce(r.departure_datetime, ((r.dates + r.departure_time) at time zone 'America/Toronto')),
      'origin_label', r.pickup_label, 'origin_lat', r.pickup_lat, 'origin_lng', r.pickup_lng,
      'dest_label', r.dropoff_label, 'dest_lat', r.dropoff_lat, 'dest_lng', r.dropoff_lng,
      'stops', r.stops, 'price_per_seat', r.fare, 'note', r.notes, 'seats_total', r.available_seats,
      'join_url', case when r.join_code is not null then 'https://pathfynder.ca/j/' || r.join_code end,
      'driver', jsonb_build_object('name', coalesce(d.name, r.driver_name), 'photo', d.photo, 'phone', v_phone)),
    'booking', jsonb_build_object(
      'id', b.id, 'status', v_bstatus, 'seats', b.seats,
      'pickup_label', b.pickup_label, 'pickup_lat', b.pickup_lat, 'pickup_lng', b.pickup_lng,
      'dropoff_label', b.dropoff_label, 'dropoff_lat', b.dropoff_lat, 'dropoff_lng', b.dropoff_lng,
      'picked_up_at', b.picked_up_at, 'dropped_off_at', b.dropped_off_at, 'note', b.note),
    'counts', jsonb_build_object('passengers', v_cnt, 'picked_up', v_picked));
end $$;

-- Cancel own booking (before pickup/start) or own pending request. Idempotent.
create or replace function public.passenger_cancel(p_token text, p_booking_id uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  ps public.passengers; b public.passenger_requests; r public.driver_routines;
  v_dwa text; v_tok text; v_taken int; v_left int; v_first text; v_body text;
begin
  select * into ps from public.passengers where manage_token = nullif(trim(coalesce(p_token, '')), '');
  if not found then return jsonb_build_object('error', 'invalid_token'); end if;

  select * into b from public.passenger_requests
   where id = p_booking_id and passenger_id = ps.id for update;
  if not found then return jsonb_build_object('error', 'not_found'); end if;

  -- request without a driver yet
  if b.ride_id is null then
    if coalesce(b.status, '') not in ('cancelled', 'canceled') then
      update public.passenger_requests set status = 'cancelled' where id = b.id;
    end if;
    return jsonb_build_object('ok', true);
  end if;

  -- booking: already cancelled / removed -> idempotent success
  if coalesce(b.status, '') in ('cancelled', 'canceled') or b.removed_at is not null then
    return jsonb_build_object('ok', true);
  end if;

  select * into r from public.driver_routines where id = b.ride_id for update;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  if b.picked_up_at is not null or b.dropped_off_at is not null
     or r.started_at is not null or coalesce(r.ride_status, '') = 'started' or r.ended_at is not null then
    return jsonb_build_object('error', 'not_allowed');
  end if;

  update public.passenger_requests set status = 'cancelled', removed_at = now() where id = b.id;

  -- tell the driver; never fail the cancel
  begin
    select coalesce(nullif(r.driver_wa_id, ''), d.wa_id), d.manage_token into v_dwa, v_tok
    from public.drivers d where d.id = r.driver_id;
    if nullif(v_dwa, '') is not null and nullif(v_tok, '') is not null then
      select coalesce(sum(greatest(coalesce(seats, 1), 1)), 0)::int into v_taken
      from public.passenger_requests
      where ride_id = r.id and removed_at is null
        and coalesce(status, '') not in ('declined', 'cancelled', 'canceled', 'removed');
      v_left := greatest(greatest(coalesce(r.available_seats, 0), 0) - v_taken, 0);
      v_first := split_part(trim(coalesce(b.passenger_name, '')), ' ', 1);
      v_body := b.seats || case when b.seats = 1 then ' seat' else ' seats' end
        || ' · ' || initcap(trim(split_part(coalesce(b.pickup_label, r.pickup_label), ',', 1)))
        || ' → ' || initcap(trim(split_part(coalesce(b.dropoff_label, r.dropoff_label), ',', 1)))
        || ' · ' || v_left || case when v_left = 1 then ' seat left' else ' seats left' end;
      perform public.notify_send(v_dwa, 'passenger_cancelled',
        left(coalesce(nullif(v_first, ''), 'A passenger'), 40) || ' cancelled', v_body,
        '/m/' || v_tok || '?t=' || r.id::text, 'cancel:' || b.id::text);
    end if;
  exception when others then
    null;
  end;

  return jsonb_build_object('ok', true);
end $$;

-- Profile (mirrors driver_profile_get / _update). WhatsApp pre-masked; never raw.
create or replace function public.passenger_profile_get(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  ps public.passengers; v_digits text; v_cc text; v_mask text; v_notif boolean;
  v_done int; v_up int; v_spent numeric;
begin
  select * into ps from public.passengers where manage_token = nullif(trim(coalesce(p_token, '')), '');
  if not found then return jsonb_build_object('error', 'invalid_token'); end if;

  v_digits := regexp_replace(coalesce(ps.wa_id, ''), '\D', '', 'g');
  if length(v_digits) < 8 then v_mask := '•••';
  else
    v_cc := case when left(v_digits, 1) = '1' then '1' else left(v_digits, 2) end;
    v_mask := '+' || v_cc || ' ••• ••• ' || right(v_digits, 4);
  end if;

  select exists (select 1 from public.notify_subscriptions s where s.wa_id = 'pax:' || ps.id::text and s.active)
    into v_notif;

  select count(*) filter (where pr.dropped_off_at is not null and pr.removed_at is null),
         count(*) filter (where pr.removed_at is null and coalesce(pr.status, '') not in ('cancelled', 'canceled')
                            and pr.dropped_off_at is null and r.ended_at is null),
         coalesce(sum(coalesce(r.fare, 0) * coalesce(pr.seats, 1))
                  filter (where pr.dropped_off_at is not null and pr.removed_at is null), 0)
    into v_done, v_up, v_spent
  from public.passenger_requests pr
  join public.driver_routines r on r.id = pr.ride_id
  where pr.passenger_id = ps.id;

  return jsonb_build_object(
    'name', ps.name, 'photo_url', ps.photo, 'whatsapp_masked', v_mask,
    'notifications_enabled', coalesce(v_notif, false),
    'stats', jsonb_build_object(
      'rides_completed', v_done, 'rides_upcoming', v_up,
      'member_since', ps.created_at, 'total_spent', round(v_spent, 2)));
end $$;

create or replace function public.passenger_profile_update(p_token text, p_name text, p_photo text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare ps public.passengers; v_name text; v_photo text;
begin
  select * into ps from public.passengers where manage_token = nullif(trim(coalesce(p_token, '')), '');
  if not found then return jsonb_build_object('error', 'invalid_token'); end if;

  v_name := ps.name;
  if p_name is not null then
    v_name := btrim(p_name);
    if char_length(v_name) < 1 or char_length(v_name) > 60 then return jsonb_build_object('error', 'invalid_name'); end if;
  end if;

  v_photo := ps.photo;
  if p_photo is not null then
    if p_photo = '' then v_photo := null;
    elsif p_photo ~ '^data:image/(jpeg|png|webp);base64,' and char_length(p_photo) <= 60000 then v_photo := p_photo;
    else return jsonb_build_object('error', 'invalid_photo');
    end if;
  end if;

  update public.passengers set name = v_name, photo = v_photo where id = ps.id;
  return jsonb_build_object('ok', true, 'name', v_name, 'photo_url', v_photo);
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'passenger_home_list(text)', 'passenger_trip_get(text, uuid)', 'passenger_cancel(text, uuid)',
    'passenger_profile_get(text)', 'passenger_profile_update(text, text, text)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

-- ROLLBACK for PART 2:
--   drop function if exists public.passenger_home_list(text);
--   drop function if exists public.passenger_trip_get(text, uuid);
--   drop function if exists public.passenger_cancel(text, uuid);
--   drop function if exists public.passenger_profile_get(text);
--   drop function if exists public.passenger_profile_update(text, text, text);
--   drop function if exists public._pax_booking_status(text, timestamptz, timestamptz, timestamptz, timestamptz, timestamptz, text);


-- =====================================================================
-- PART 3: request-a-ride, notifications, driver-action alerts
-- (migration: passenger_request_post_and_notifications)
-- =====================================================================

-- "Request a ride" (modelled on trip_post). One pending passenger_requests row per
-- departure date / return date, ride_id null. NOTE: these inserts intentionally fire the
-- existing new-request triggers (n8n webhook, notify_n8n_on_new_request, notify_sync):
-- that is the normal request flow. Columns follow the existing bot rows: requested_datetime,
-- date + time (Toronto local wall clock), source_geo / destination_geo, status 'pending';
-- platform 'web' (same as the existing web rows).
create or replace function public.passenger_request_post(
  p_token text,
  p_origin_label text, p_origin_lat double precision, p_origin_lng double precision,
  p_dest_label text, p_dest_lat double precision, p_dest_lng double precision,
  p_seats integer, p_note text,
  p_departures timestamptz[], p_returns timestamptz[] default '{}')
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  ps public.passengers; v_note text; ts timestamptz; local_ts timestamp;
  ids uuid[] := '{}'; new_id uuid; n_dep int; n_ret int; n_dates int; v_open int;
begin
  select * into ps from public.passengers where manage_token = nullif(trim(coalesce(p_token, '')), '');
  if not found then return jsonb_build_object('error', 'invalid_token'); end if;

  n_dep := coalesce(cardinality(p_departures), 0);
  n_ret := coalesce(cardinality(p_returns), 0);

  if coalesce(btrim(p_origin_label), '') = '' or coalesce(btrim(p_dest_label), '') = ''
     or char_length(p_origin_label) > 200 or char_length(p_dest_label) > 200
     or p_origin_lat is null or p_origin_lng is null or p_dest_lat is null or p_dest_lng is null
     or p_origin_lat not between -90 and 90 or p_dest_lat not between -90 and 90
     or p_origin_lng not between -180 and 180 or p_dest_lng not between -180 and 180
     or p_seats is null or p_seats < 1 or p_seats > 8
     or (p_note is not null and char_length(p_note) > 300)
     or n_dep = 0 or n_dep > 30 or n_ret > 30 then
    return jsonb_build_object('error', 'invalid_input');
  end if;
  if exists (select 1 from unnest(p_departures) x where x is null)
     or exists (select 1 from unnest(p_returns) x where x is null) then
    return jsonb_build_object('error', 'invalid_input');
  end if;

  -- one request per local (Toronto) date, for departures and for returns
  select count(distinct (x at time zone 'America/Toronto')::date) into n_dates from unnest(p_departures) x;
  if n_dates <> n_dep then return jsonb_build_object('error', 'invalid_input'); end if;
  if n_ret > 0 then
    select count(distinct (x at time zone 'America/Toronto')::date) into n_dates from unnest(p_returns) x;
    if n_dates <> n_ret then return jsonb_build_object('error', 'invalid_input'); end if;
  end if;

  if exists (select 1 from unnest(p_departures) x where x < now())
     or exists (select 1 from unnest(p_returns) x where x < now()) then
    return jsonb_build_object('error', 'past_time');
  end if;

  -- anti-spam: at most 30 open requests per passenger token
  select count(*)::int into v_open from public.passenger_requests
   where passenger_id = ps.id and ride_id is null and status = 'pending';
  if v_open + n_dep + n_ret > 30 then return jsonb_build_object('error', 'too_many'); end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');

  foreach ts in array p_departures loop
    local_ts := ts at time zone 'America/Toronto';
    insert into public.passenger_requests (
      passenger_wa_id, passenger_name, passenger_id,
      pickup_label, pickup_lat, pickup_lng, dropoff_label, dropoff_lat, dropoff_lng,
      source_geo, destination_geo, requested_datetime, date, time,
      seats, note, status, platform, created_at)
    values (
      ps.wa_id, ps.name, ps.id,
      btrim(p_origin_label), p_origin_lat, p_origin_lng, btrim(p_dest_label), p_dest_lat, p_dest_lng,
      st_setsrid(st_makepoint(p_origin_lng, p_origin_lat), 4326)::geography,
      st_setsrid(st_makepoint(p_dest_lng, p_dest_lat), 4326)::geography,
      ts, local_ts::date, local_ts::time,
      p_seats, v_note, 'pending', 'web', now())
    returning id into new_id;
    ids := ids || new_id;
  end loop;

  if n_ret > 0 then
    foreach ts in array p_returns loop
      local_ts := ts at time zone 'America/Toronto';
      insert into public.passenger_requests (
        passenger_wa_id, passenger_name, passenger_id,
        pickup_label, pickup_lat, pickup_lng, dropoff_label, dropoff_lat, dropoff_lng,
        source_geo, destination_geo, requested_datetime, date, time,
        seats, note, status, platform, created_at)
      values (
        ps.wa_id, ps.name, ps.id,
        btrim(p_dest_label), p_dest_lat, p_dest_lng, btrim(p_origin_label), p_origin_lat, p_origin_lng,
        st_setsrid(st_makepoint(p_dest_lng, p_dest_lat), 4326)::geography,
        st_setsrid(st_makepoint(p_origin_lng, p_origin_lat), 4326)::geography,
        ts, local_ts::date, local_ts::time,
        p_seats, v_note, 'pending', 'web', now())
      returning id into new_id;
      ids := ids || new_id;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'ids', to_jsonb(ids));
end $$;

-- Recent distinct routes of THIS token (bookings and requests) for quick re-request.
create or replace function public.passenger_request_recent(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare ps public.passengers; v jsonb;
begin
  select * into ps from public.passengers where manage_token = nullif(trim(coalesce(p_token, '')), '');
  if not found then return jsonb_build_object('error', 'invalid_token'); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'origin_label', t.pickup_label, 'origin_lat', t.pickup_lat, 'origin_lng', t.pickup_lng,
      'dest_label', t.dropoff_label, 'dest_lat', t.dropoff_lat, 'dest_lng', t.dropoff_lng,
      'seats', t.seats, 'note', t.note) order by t.created_at desc), '[]'::jsonb) into v
  from (
    select * from (
      select distinct on (r.pickup_label, r.dropoff_label) r.*
      from public.passenger_requests r
      where r.passenger_id = ps.id
        and coalesce(btrim(r.pickup_label), '') <> '' and coalesce(btrim(r.dropoff_label), '') <> ''
      order by r.pickup_label, r.dropoff_label, r.created_at desc
    ) u order by u.created_at desc limit 3
  ) t;

  return jsonb_build_object('trips', v);
end $$;

-- Ride-alerts switch (mirrors driver_notify_set). Subscriptions are keyed 'pax:<passenger id>'.
create or replace function public.passenger_notify_set(
  p_token text, p_endpoint text, p_p256dh text, p_auth text, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare ps public.passengers; v_key text; v_id uuid;
begin
  select * into ps from public.passengers where manage_token = nullif(trim(coalesce(p_token, '')), '');
  if not found then return jsonb_build_object('error', 'invalid_token'); end if;
  if p_endpoint is null or p_endpoint = '' then return jsonb_build_object('error', 'invalid_request'); end if;
  v_key := 'pax:' || ps.id::text;

  if coalesce(p_on, false) then
    if p_p256dh is null or p_auth is null then return jsonb_build_object('error', 'invalid_request'); end if;
    update public.notify_subscriptions
       set p256dh = p_p256dh, auth = p_auth, active = true, off_reason = null
     where endpoint = p_endpoint and wa_id = v_key
    returning id into v_id;

    if found then
      delete from public.notify_subscriptions where endpoint = p_endpoint and wa_id is null;
    else
      update public.notify_subscriptions
         set wa_id = v_key, p256dh = p_p256dh, auth = p_auth, active = true,
             off_reason = null, link_code = null, link_code_at = null
       where endpoint = p_endpoint and wa_id is null
      returning id into v_id;
      if not found then
        insert into public.notify_subscriptions (wa_id, endpoint, p256dh, auth, active)
        values (v_key, p_endpoint, p_p256dh, p_auth, true);
      end if;
    end if;
    return jsonb_build_object('ok', true, 'on', true);
  else
    update public.notify_subscriptions set active = false, off_reason = 'user'
     where wa_id = v_key and endpoint = p_endpoint and off_reason is distinct from 'gone';
    return jsonb_build_object('ok', true, 'on', false);
  end if;
end $$;

-- Notification bell (mirrors driver_notifications_*). Only passenger kinds, only this token's key.
create or replace function public.passenger_notifications_list(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare ps public.passengers; v_key text; v_list jsonb; v_unread int;
begin
  select * into ps from public.passengers where manage_token = nullif(trim(coalesce(p_token, '')), '');
  if not found then return jsonb_build_object('error', 'invalid_token'); end if;
  v_key := 'pax:' || ps.id::text;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', n.id, 'kind', n.kind, 'title', n.title, 'body', n.body, 'url', n.url,
           'created_at', n.created_at, 'read', n.read_at is not null)
         order by n.created_at desc, n.id desc), '[]'::jsonb)
    into v_list
  from (select * from public.notify_log
        where wa_id = v_key
          and kind in ('ride_started', 'picked_up', 'ride_completed', 'ride_cancelled', 'passenger_request_update')
        order by created_at desc, id desc limit 30) n;

  select count(*)::int into v_unread from public.notify_log
  where wa_id = v_key and read_at is null
    and kind in ('ride_started', 'picked_up', 'ride_completed', 'ride_cancelled', 'passenger_request_update');

  return jsonb_build_object('notifications', v_list, 'unread_count', v_unread);
end $$;

create or replace function public.passenger_notifications_mark_read(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare ps public.passengers;
begin
  select * into ps from public.passengers where manage_token = nullif(trim(coalesce(p_token, '')), '');
  if not found then return jsonb_build_object('error', 'invalid_token'); end if;
  update public.notify_log set read_at = now()
   where wa_id = 'pax:' || ps.id::text and read_at is null
     and kind in ('ride_started', 'picked_up', 'ride_completed', 'ride_cancelled', 'passenger_request_update');
  return jsonb_build_object('ok', true);
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'passenger_request_post(text, text, double precision, double precision, text, double precision, double precision, integer, text, timestamptz[], timestamptz[])',
    'passenger_request_recent(text)', 'passenger_notify_set(text, text, text, text, boolean)',
    'passenger_notifications_list(text)', 'passenger_notifications_mark_read(text)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

-- Internal: push + log one alert to the passenger who owns a booking. Never raises, never
-- returns tokens/phones. Skips silently when the booking has no passenger_id.
create or replace function public._pax_notify(p_booking_id uuid, p_kind text, p_title text, p_dedupe text)
returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare b public.passenger_requests; v_tok text; v_body text;
begin
  select * into b from public.passenger_requests where id = p_booking_id;
  if not found or b.passenger_id is null then return; end if;
  select manage_token into v_tok from public.passengers where id = b.passenger_id;
  if v_tok is null then return; end if;
  v_body := initcap(trim(split_part(coalesce(b.pickup_label, ''), ',', 1)))
    || ' → ' || initcap(trim(split_part(coalesce(b.dropoff_label, ''), ',', 1)));
  perform public.notify_send('pax:' || b.passenger_id::text, p_kind, p_title, v_body,
                             '/p/' || v_tok || '?b=' || b.id::text, p_dedupe);
exception when others then
  null;
end $$;
revoke all on function public._pax_notify(uuid, text, text, text) from public, anon, authenticated;

-- trip_manage_action: unchanged behaviour; adds passenger alerts (each in its own
-- begin/exception block so an alert can never fail the driver's action).
--   start     -> every active booking: 'ride_started'
--   end       -> every active booking: 'ride_completed'
--   picked_up -> that booking: 'picked_up'
--   remove    -> that booking: 'ride_cancelled'
-- (There is no whole-trip cancel action in trip_manage_action, so none is sent for it.)
create or replace function public.trip_manage_action(
  p_token text, p_trip_id uuid, p_action text, p_booking_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare d public.drivers; v jsonb; n int; r_started timestamptz; r_ended timestamptz; r_status text;
begin
  select * into d from public.drivers where manage_token = p_token;
  if not found then return jsonb_build_object('error','invalid_token'); end if;
  select started_at, ended_at, ride_status into r_started, r_ended, r_status from public.driver_routines where id = p_trip_id and driver_id = d.id for update;
  if not found then return jsonb_build_object('error','invalid_token'); end if;

  if p_action = 'start' then
    update public.driver_routines set started_at = coalesce(started_at, now()), ride_status = 'started' where id = p_trip_id;
    begin
      perform public._pax_notify(b.id, 'ride_started', 'Your driver started the trip', 'start:' || b.id::text)
        from public.passenger_requests b
       where b.ride_id = p_trip_id and b.removed_at is null and coalesce(b.status, '') not in ('declined', 'cancelled', 'canceled', 'removed');
    exception when others then null; end;
  elsif p_action = 'end' then
    update public.driver_routines set ended_at = coalesce(ended_at, now()) where id = p_trip_id;
    begin
      perform public._pax_notify(b.id, 'ride_completed', 'Your trip is complete', 'end:' || b.id::text)
        from public.passenger_requests b
       where b.ride_id = p_trip_id and b.removed_at is null and coalesce(b.status, '') not in ('declined', 'cancelled', 'canceled', 'removed');
    exception when others then null; end;
  elsif p_action in ('picked_up','dropped_off','remove') then
    if p_booking_id is null then return jsonb_build_object('error','invalid_booking'); end if;
    if p_action in ('picked_up','dropped_off') and not ((r_started is not null or r_status = 'started') and r_ended is null) then
      return jsonb_build_object('error','not_started');
    end if;
    if p_action = 'picked_up' then
      update public.passenger_requests set picked_up_at = coalesce(picked_up_at, now()) where id = p_booking_id and ride_id = p_trip_id and removed_at is null;
    elsif p_action = 'dropped_off' then
      update public.passenger_requests set dropped_off_at = coalesce(dropped_off_at, now()) where id = p_booking_id and ride_id = p_trip_id and removed_at is null;
    else
      update public.passenger_requests set removed_at = coalesce(removed_at, now()) where id = p_booking_id and ride_id = p_trip_id;
    end if;
    get diagnostics n = row_count;
    if n = 0 then return jsonb_build_object('error','invalid_booking'); end if;
    if p_action = 'picked_up' then
      begin perform public._pax_notify(p_booking_id, 'picked_up', 'You''re picked up', 'pickup:' || p_booking_id::text);
      exception when others then null; end;
    elsif p_action = 'remove' then
      begin perform public._pax_notify(p_booking_id, 'ride_cancelled', 'Your driver cancelled your seat', 'removed:' || p_booking_id::text);
      exception when others then null; end;
    end if;
  else
    return jsonb_build_object('error','invalid_action');
  end if;
  return public._trip_manage_payload(d.id, p_trip_id);
end $$;
-- grants of trip_manage_action are unchanged (create or replace keeps them).

-- ROLLBACK for PART 3:
--   drop function if exists public.passenger_request_post(text, text, double precision, double precision, text, double precision, double precision, integer, text, timestamptz[], timestamptz[]);
--   drop function if exists public.passenger_request_recent(text);
--   drop function if exists public.passenger_notify_set(text, text, text, text, boolean);
--   drop function if exists public.passenger_notifications_list(text);
--   drop function if exists public.passenger_notifications_mark_read(text);
--   create or replace function public.trip_manage_action(p_token text, p_trip_id uuid, p_action text, p_booking_id uuid default null)
--   returns jsonb language plpgsql security definer set search_path = public, extensions as $$
--   declare d public.drivers; v jsonb; n int; r_started timestamptz; r_ended timestamptz; r_status text;
--   begin
--     select * into d from public.drivers where manage_token = p_token;
--     if not found then return jsonb_build_object('error','invalid_token'); end if;
--     select started_at, ended_at, ride_status into r_started, r_ended, r_status from public.driver_routines where id = p_trip_id and driver_id = d.id for update;
--     if not found then return jsonb_build_object('error','invalid_token'); end if;
--     if p_action = 'start' then
--       update public.driver_routines set started_at = coalesce(started_at, now()), ride_status = 'started' where id = p_trip_id;
--     elsif p_action = 'end' then
--       update public.driver_routines set ended_at = coalesce(ended_at, now()) where id = p_trip_id;
--     elsif p_action in ('picked_up','dropped_off','remove') then
--       if p_booking_id is null then return jsonb_build_object('error','invalid_booking'); end if;
--       if p_action in ('picked_up','dropped_off') and not ((r_started is not null or r_status = 'started') and r_ended is null) then
--         return jsonb_build_object('error','not_started');
--       end if;
--       if p_action = 'picked_up' then
--         update public.passenger_requests set picked_up_at = coalesce(picked_up_at, now()) where id = p_booking_id and ride_id = p_trip_id and removed_at is null;
--       elsif p_action = 'dropped_off' then
--         update public.passenger_requests set dropped_off_at = coalesce(dropped_off_at, now()) where id = p_booking_id and ride_id = p_trip_id and removed_at is null;
--       else
--         update public.passenger_requests set removed_at = coalesce(removed_at, now()) where id = p_booking_id and ride_id = p_trip_id;
--       end if;
--       get diagnostics n = row_count;
--       if n = 0 then return jsonb_build_object('error','invalid_booking'); end if;
--     else
--       return jsonb_build_object('error','invalid_action');
--     end if;
--     return public._trip_manage_payload(d.id, p_trip_id);
--   end $$;
--   drop function if exists public._pax_notify(uuid, text, text, text);
