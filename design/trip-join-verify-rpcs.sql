-- =====================================================================
-- trip-join-verify-rpcs.sql  (2026-09-29)
-- WhatsApp-verified first booking for /j/<code> (join.html).
-- Applied to project omussxfyrztjahbdrrpi as two migrations:
--   trip_join_claims_and_start_status         (PART 1)
--   trip_join_verify_and_close_unverified     (PART 2)
-- Runnable top to bottom. Rollback at the bottom (commented).
--
-- Flow: anon trip_join_start -> claim + 6-char verify_code; passenger sends
-- "BOOK <CODE>" to the WhatsApp bot; n8n calls the service-role RPC
-- trip_join_verify(code, wa_id, name); the page polls trip_join_claim_status and
-- gets the passenger token once the claim is verified.
-- trip_join (direct booking) now REQUIRES a valid saved passenger token.
-- Live passengers table: id, wa_id, name, photo, manage_token, created_at
-- (no unique constraint on wa_id; verify reuses the OLDEST row per wa_id).
-- =====================================================================

-- ============================ PART 1 ================================

create table if not exists public.trip_join_claims (
  id uuid primary key default gen_random_uuid(),
  verify_code text not null,
  trip_id uuid not null references public.driver_routines(id) on delete cascade,
  seats int not null,
  pickup jsonb not null,
  dropoff jsonb not null,
  note text,
  status text not null default 'pending'
    check (status in ('pending', 'verified', 'expired', 'full')),
  passenger_id uuid references public.passengers(id),
  booking_id uuid,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  verified_at timestamptz
);
create unique index if not exists trip_join_claims_pending_code_key
  on public.trip_join_claims (verify_code) where status = 'pending';
create index if not exists trip_join_claims_trip_pending_idx
  on public.trip_join_claims (trip_id) where status = 'pending';
create index if not exists trip_join_claims_created_idx
  on public.trip_join_claims (created_at);

alter table public.trip_join_claims enable row level security;   -- no policies
revoke all on table public.trip_join_claims from public, anon, authenticated;

-- 6-char code, same alphabet as pf_gen_join_code (no 0 O 1 I L); unique among pending claims.
create or replace function public._trip_join_gen_verify_code()
returns text
language plpgsql volatile security definer set search_path = public, extensions
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  c text; i int;
begin
  loop
    c := '';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.trip_join_claims where verify_code = c and status = 'pending');
  end loop;
  return c;
end $$;
revoke all on function public._trip_join_gen_verify_code() from public, anon, authenticated;

-- Validates one place object; returns {label,lat,lng} or null. Same rules trip_join always used.
create or replace function public._trip_join_norm_place(p jsonb)
returns jsonb
language plpgsql immutable set search_path = public, extensions
as $$
declare l text; la float8; ln float8;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return null; end if;
  l := nullif(trim(p->>'label'), '');
  la := (p->>'lat')::float8; ln := (p->>'lng')::float8;
  if l is null or la is null or ln is null
     or la not between -90 and 90 or ln not between -180 and 180 then
    return null;
  end if;
  return jsonb_build_object('label', l, 'lat', la, 'lng', ln);
exception when others then
  return null;
end $$;
revoke all on function public._trip_join_norm_place(jsonb) from public, anon, authenticated;

-- Deletes claims older than 1 day. Service role only; also called from trip_join_start.
create or replace function public.trip_join_claims_cleanup()
returns int
language plpgsql security definer set search_path = public, extensions
as $$
declare n int;
begin
  delete from public.trip_join_claims where created_at < now() - interval '1 day';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.trip_join_claims_cleanup() from public, anon, authenticated;
grant execute on function public.trip_join_claims_cleanup() to service_role;

-- Anon. Returns { claim_id, verify_code, expires_at, trip } | { error: invalid_code|expired|invalid_input|full|busy }
create or replace function public.trip_join_start(
  p_code text, p_pickup jsonb, p_dropoff jsonb, p_seats int, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_note text := nullif(left(trim(coalesce(p_note, '')), 300), '');
  v_pick jsonb; v_drop jsonb;
  t record;
  v_trip jsonb;
  v_claim public.trip_join_claims;
  v_vc text; v_try int := 0;
begin
  if v_code = '' then return jsonb_build_object('error', 'invalid_code'); end if;
  if p_seats is null or p_seats < 1 or p_seats > 8 then return jsonb_build_object('error', 'invalid_input'); end if;
  v_pick := public._trip_join_norm_place(p_pickup);
  v_drop := public._trip_join_norm_place(p_dropoff);
  if v_pick is null or v_drop is null then return jsonb_build_object('error', 'invalid_input'); end if;

  select id, ended_at, is_active, ride_status, departure_datetime into t
  from public.driver_routines where join_code = v_code;
  if not found then return jsonb_build_object('error', 'invalid_code'); end if;
  if t.ended_at is not null
     or coalesce(t.is_active, false) = false
     or coalesce(t.ride_status, '') in ('cancelled', 'canceled', 'completed', 'ended')
     or (t.departure_datetime is not null and t.departure_datetime < now() - interval '3 hours') then
    return jsonb_build_object('error', 'expired');
  end if;

  v_trip := public._trip_join_trip_json(t.id);
  if p_seats > coalesce((v_trip->>'seats_left')::int, 0) then return jsonb_build_object('error', 'full'); end if;

  -- housekeeping (no cron): drop old claims, free codes of lapsed pending claims
  perform public.trip_join_claims_cleanup();
  update public.trip_join_claims set status = 'expired'
   where status = 'pending' and expires_at < now();

  if (select count(*) from public.trip_join_claims where trip_id = t.id and status = 'pending') >= 200 then
    return jsonb_build_object('error', 'busy');
  end if;

  loop
    v_vc := public._trip_join_gen_verify_code();
    begin
      insert into public.trip_join_claims (verify_code, trip_id, seats, pickup, dropoff, note)
      values (v_vc, t.id, p_seats, v_pick, v_drop, v_note)
      returning * into v_claim;
      exit;
    exception when unique_violation then
      v_try := v_try + 1;
      if v_try > 5 then return jsonb_build_object('error', 'busy'); end if;
    end;
  end loop;

  return jsonb_build_object(
    'claim_id', v_claim.id, 'verify_code', v_claim.verify_code,
    'expires_at', v_claim.expires_at, 'trip', v_trip);
end $$;

-- Anon. Returns { status: pending|verified|expired|full|failed, passenger_token?, booking_id?, trip? }
-- Never returns wa_id. passenger_token only when verified.
create or replace function public.trip_join_claim_status(p_claim_id uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  c public.trip_join_claims;
  v_tok text;
  v_trip jsonb;
begin
  if p_claim_id is null then return jsonb_build_object('status', 'failed'); end if;
  select * into c from public.trip_join_claims where id = p_claim_id;
  if not found then return jsonb_build_object('status', 'failed'); end if;

  if c.status = 'pending' and c.expires_at < now() then
    update public.trip_join_claims set status = 'expired' where id = c.id and status = 'pending';
    c.status := 'expired';
  end if;

  v_trip := public._trip_join_trip_json(c.trip_id);

  if c.status = 'verified' then
    select manage_token into v_tok from public.passengers where id = c.passenger_id;
    return jsonb_build_object('status', 'verified', 'passenger_token', v_tok,
                              'booking_id', c.booking_id, 'trip', v_trip);
  end if;
  return jsonb_build_object('status', c.status, 'trip', v_trip);
end $$;

revoke all on function public.trip_join_start(text, jsonb, jsonb, int, text) from public, anon, authenticated;
revoke all on function public.trip_join_claim_status(uuid) from public, anon, authenticated;
grant execute on function public.trip_join_start(text, jsonb, jsonb, int, text) to anon, authenticated;
grant execute on function public.trip_join_claim_status(uuid) to anon, authenticated;

-- ============================ PART 2 ================================

-- Shared booking logic (was inline in trip_join). Caller has already validated inputs, locked the
-- trip row and checked expiry. Returns { booking, trip } | { error: 'full' }.
-- Same seat logic, status 'confirmed', driver push 'passenger_joined' (dedupe 'join:<booking id>').
create or replace function public._trip_join_book(
  p_trip_id uuid, p_passenger_id uuid, p_wa text, p_name text,
  p_pickup jsonb, p_dropoff jsonb, p_seats int, p_note text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  t record;
  v_wa text := regexp_replace(coalesce(p_wa, ''), '\D', '', 'g');
  v_name text := left(coalesce(nullif(trim(coalesce(p_name, '')), ''), 'Passenger'), 80);
  v_note text := nullif(left(trim(coalesce(p_note, '')), 300), '');
  v_ex_id uuid; v_taken int; v_left int; v_id uuid;
  v_plabel text := p_pickup->>'label'; v_dlabel text := p_dropoff->>'label';
  v_plat float8 := (p_pickup->>'lat')::float8; v_plng float8 := (p_pickup->>'lng')::float8;
  v_dlat float8 := (p_dropoff->>'lat')::float8; v_dlng float8 := (p_dropoff->>'lng')::float8;
  v_ins boolean := false;
  v_dwa text; v_tok text; v_first text; v_lft int; v_title text; v_body text;
begin
  select id, available_seats into t from public.driver_routines where id = p_trip_id;
  if not found then return jsonb_build_object('error', 'invalid_code'); end if;

  select id into v_ex_id
  from public.passenger_requests
  where ride_id = t.id
    and (passenger_id = p_passenger_id or passenger_wa_id = v_wa)
    and removed_at is null
    and coalesce(status, '') not in ('declined', 'cancelled', 'canceled', 'removed')
  order by created_at desc nulls last
  limit 1;

  select coalesce(sum(greatest(coalesce(seats, 1), 1)), 0)::int into v_taken
  from public.passenger_requests
  where ride_id = t.id
    and removed_at is null
    and coalesce(status, '') not in ('declined', 'cancelled', 'canceled', 'removed')
    and id is distinct from v_ex_id;

  v_left := greatest(coalesce(t.available_seats, 0), 0) - v_taken;
  if p_seats > v_left then return jsonb_build_object('error', 'full'); end if;

  if v_ex_id is not null then
    update public.passenger_requests
       set seats = p_seats, passenger_name = v_name, note = v_note, status = 'confirmed',
           pickup_label = v_plabel, pickup_lat = v_plat, pickup_lng = v_plng,
           dropoff_label = v_dlabel, dropoff_lat = v_dlat, dropoff_lng = v_dlng,
           passenger_id = p_passenger_id
     where id = v_ex_id
     returning id into v_id;
  else
    insert into public.passenger_requests
      (ride_id, passenger_wa_id, passenger_name, seats, note, status,
       pickup_label, pickup_lat, pickup_lng, dropoff_label, dropoff_lat, dropoff_lng, passenger_id)
    values
      (t.id, v_wa, v_name, p_seats, v_note, 'confirmed',
       v_plabel, v_plat, v_plng, v_dlabel, v_dlat, v_dlng, p_passenger_id)
    returning id into v_id;
    v_ins := true;
  end if;

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
    'trip', public._trip_join_trip_json(t.id));
end $$;
revoke all on function public._trip_join_book(uuid, uuid, text, text, jsonb, jsonb, int, text) from public, anon, authenticated;

-- Builds the trip_join_verify success payload from a verified claim.
create or replace function public._trip_join_verify_result(p_claim_id uuid, p_already boolean)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  c public.trip_join_claims; ps public.passengers; b public.passenger_requests; tj jsonb;
begin
  select * into c from public.trip_join_claims where id = p_claim_id;
  select * into ps from public.passengers where id = c.passenger_id;
  select * into b from public.passenger_requests where id = c.booking_id;
  tj := public._trip_join_trip_json(c.trip_id);
  return jsonb_build_object(
    'ok', true, 'already', coalesce(p_already, false),
    'passenger_url', 'https://www.pathfynder.ca/p/' || ps.manage_token || '?b=' || c.booking_id::text,
    'booking', jsonb_build_object('seats', b.seats, 'pickup_label', b.pickup_label, 'dropoff_label', b.dropoff_label),
    'trip', jsonb_build_object(
      'origin_label', tj->>'origin_label', 'dest_label', tj->>'dest_label',
      'schedule_text', tj->>'schedule_text', 'driver_first_name', tj->>'driver_first_name',
      'seats_left', (tj->>'seats_left')::int),
    'name', ps.name);
end $$;
revoke all on function public._trip_join_verify_result(uuid, boolean) from public, anon, authenticated;

-- SERVICE ROLE ONLY (called by n8n). Returns the payload above or { ok:false, reason }.
create or replace function public.trip_join_verify(p_verify_code text, p_wa_id text, p_name text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_code text := upper(regexp_replace(coalesce(p_verify_code, ''), '\s', '', 'g'));
  v_wa text := regexp_replace(coalesce(p_wa_id, ''), '\D', '', 'g');
  v_name text := left(nullif(btrim(coalesce(p_name, '')), ''), 60);
  c public.trip_join_claims; t record; ps public.passengers; r jsonb;
begin
  if v_code = '' or length(v_wa) < 7 or length(v_wa) > 15 then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;
  if v_code !~ '^[A-Z0-9]{6}$' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_code');
  end if;

  -- pending claim wins over an older verified claim that once used the same code
  select * into c from public.trip_join_claims
   where verify_code = v_code
   order by (status = 'pending') desc, created_at desc
   limit 1 for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;

  if c.status = 'verified' then
    -- idempotent replay, but only for the number that verified it (never leak a token to another sender)
    select * into ps from public.passengers where id = c.passenger_id;
    if not found or ps.wa_id <> v_wa then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
    return public._trip_join_verify_result(c.id, true);
  end if;
  if c.status = 'full' then return jsonb_build_object('ok', false, 'reason', 'full'); end if;
  if c.status = 'expired' then return jsonb_build_object('ok', false, 'reason', 'expired'); end if;

  if c.expires_at < now() then
    update public.trip_join_claims set status = 'expired' where id = c.id;
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  select id, ended_at, is_active, ride_status, departure_datetime into t
  from public.driver_routines where id = c.trip_id for update;
  if not found
     or t.ended_at is not null
     or coalesce(t.is_active, false) = false
     or coalesce(t.ride_status, '') in ('cancelled', 'canceled', 'completed', 'ended')
     or (t.departure_datetime is not null and t.departure_datetime < now() - interval '3 hours') then
    update public.trip_join_claims set status = 'expired' where id = c.id;
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  -- one passengers row per verified wa_id: reuse the oldest legacy row, else create
  perform pg_advisory_xact_lock(hashtext('pax_wa:' || v_wa));
  select * into ps from public.passengers where wa_id = v_wa order by created_at asc nulls last, id limit 1;
  if not found then
    insert into public.passengers (wa_id, name) values (v_wa, coalesce(v_name, 'Passenger'))
    returning * into ps;
  elsif coalesce(btrim(ps.name), '') = '' then
    update public.passengers set name = coalesce(v_name, 'Passenger') where id = ps.id
    returning * into ps;
  end if;

  r := public._trip_join_book(c.trip_id, ps.id, v_wa, ps.name, c.pickup, c.dropoff, c.seats, c.note);
  if r ? 'error' then
    if r->>'error' = 'full' then
      update public.trip_join_claims set status = 'full' where id = c.id;
      return jsonb_build_object('ok', false, 'reason', 'full');
    end if;
    update public.trip_join_claims set status = 'expired' where id = c.id;
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  update public.trip_join_claims
     set status = 'verified', passenger_id = ps.id, booking_id = (r->'booking'->>'id')::uuid, verified_at = now()
   where id = c.id;

  return public._trip_join_verify_result(c.id, false);
end $$;

revoke all on function public.trip_join_verify(text, text, text) from public, anon, authenticated;
grant execute on function public.trip_join_verify(text, text, text) to service_role;

-- trip_join: now REQUIRES a valid saved passenger token. Name / whatsapp params are ignored
-- (kept for backward compatibility); name and wa_id come from the passenger row.
-- Returns { booking, trip, passenger_token } | { error: invalid_code|expired|full|invalid_input|verification_required }
create or replace function public.trip_join(
  p_code text, p_pickup jsonb, p_dropoff jsonb, p_seats int,
  p_name text, p_whatsapp text, p_note text default null, p_passenger_token text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_ptok_in text := nullif(trim(coalesce(p_passenger_token, '')), '');
  v_pick jsonb; v_drop jsonb;
  t record; ps public.passengers; r jsonb;
begin
  if v_code = '' then return jsonb_build_object('error', 'invalid_code'); end if;
  if p_seats is null or p_seats < 1 or p_seats > 8 then return jsonb_build_object('error', 'invalid_input'); end if;
  v_pick := public._trip_join_norm_place(p_pickup);
  v_drop := public._trip_join_norm_place(p_dropoff);
  if v_pick is null or v_drop is null then return jsonb_build_object('error', 'invalid_input'); end if;

  select id, ended_at, is_active, ride_status, departure_datetime into t
  from public.driver_routines where join_code = v_code for update;
  if not found then return jsonb_build_object('error', 'invalid_code'); end if;

  if t.ended_at is not null
     or coalesce(t.is_active, false) = false
     or coalesce(t.ride_status, '') in ('cancelled', 'canceled', 'completed', 'ended')
     or (t.departure_datetime is not null and t.departure_datetime < now() - interval '3 hours') then
    return jsonb_build_object('error', 'expired');
  end if;

  if v_ptok_in is null then return jsonb_build_object('error', 'verification_required'); end if;
  select * into ps from public.passengers where manage_token = v_ptok_in;
  if not found then return jsonb_build_object('error', 'verification_required'); end if;

  r := public._trip_join_book(t.id, ps.id, ps.wa_id, ps.name, v_pick, v_drop, p_seats, p_note);
  if r ? 'error' then return r; end if;
  return r || jsonb_build_object('passenger_token', ps.manage_token);
end $$;

-- create or replace keeps the existing ACL (anon execute, public revoked); restate it explicitly.
revoke all on function public.trip_join(text, jsonb, jsonb, int, text, text, text, text) from public;
grant execute on function public.trip_join(text, jsonb, jsonb, int, text, text, text, text) to anon, authenticated;

-- ============================ ROLLBACK ==============================
-- 1) restore the previous trip_join (live body before this change):
--   create or replace function public.trip_join(p_code text, p_pickup jsonb, p_dropoff jsonb, p_seats int,
--     p_name text, p_whatsapp text, p_note text default null, p_passenger_token text default null)
--   returns jsonb language plpgsql security definer set search_path = public, extensions as $$
--   declare
--     v_code text := upper(trim(coalesce(p_code, '')));
--     v_wa text := regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g');
--     v_name text := trim(coalesce(p_name, ''));
--     v_note text := nullif(left(trim(coalesce(p_note, '')), 300), '');
--     v_ptok_in text := nullif(trim(coalesce(p_passenger_token, '')), '');
--     t record; v_pid uuid; v_ptok text; v_ex_id uuid; v_taken int; v_left int; v_id uuid;
--     v_plabel text; v_dlabel text; v_plat float8; v_plng float8; v_dlat float8; v_dlng float8;
--     v_ins boolean := false;
--     v_dwa text; v_tok text; v_first text; v_lft int; v_title text; v_body text;
--   begin
--     if v_code = '' then return jsonb_build_object('error', 'invalid_code'); end if;
--     if p_seats is null or p_seats < 1 or p_seats > 8 then return jsonb_build_object('error', 'invalid_input'); end if;
--     if v_name = '' or length(v_name) > 80 then return jsonb_build_object('error', 'invalid_input'); end if;
--     if length(v_wa) < 10 or length(v_wa) > 15 then return jsonb_build_object('error', 'invalid_input'); end if;
--     if p_pickup is null or p_dropoff is null
--        or jsonb_typeof(p_pickup) <> 'object' or jsonb_typeof(p_dropoff) <> 'object' then
--       return jsonb_build_object('error', 'invalid_input'); end if;
--     begin
--       v_plabel := nullif(trim(p_pickup->>'label'), ''); v_dlabel := nullif(trim(p_dropoff->>'label'), '');
--       v_plat := (p_pickup->>'lat')::float8;  v_plng := (p_pickup->>'lng')::float8;
--       v_dlat := (p_dropoff->>'lat')::float8; v_dlng := (p_dropoff->>'lng')::float8;
--     exception when others then return jsonb_build_object('error', 'invalid_input'); end;
--     if v_plabel is null or v_dlabel is null or v_plat is null or v_plng is null or v_dlat is null or v_dlng is null
--        or v_plat not between -90 and 90 or v_dlat not between -90 and 90
--        or v_plng not between -180 and 180 or v_dlng not between -180 and 180 then
--       return jsonb_build_object('error', 'invalid_input'); end if;
--     select id, ended_at, is_active, ride_status, departure_datetime, available_seats into t
--       from public.driver_routines where join_code = v_code for update;
--     if not found then return jsonb_build_object('error', 'invalid_code'); end if;
--     if t.ended_at is not null or coalesce(t.is_active, false) = false
--        or coalesce(t.ride_status, '') in ('cancelled', 'canceled', 'completed', 'ended')
--        or (t.departure_datetime is not null and t.departure_datetime < now() - interval '3 hours') then
--       return jsonb_build_object('error', 'expired'); end if;
--     if v_ptok_in is not null then
--       select id, manage_token into v_pid, v_ptok from public.passengers where manage_token = v_ptok_in and wa_id = v_wa;
--     end if;
--     if v_pid is not null then
--       select id into v_ex_id from public.passenger_requests
--        where ride_id = t.id and passenger_id = v_pid and removed_at is null
--          and coalesce(status, '') not in ('declined', 'cancelled', 'canceled', 'removed')
--        order by created_at desc nulls last limit 1;
--     end if;
--     select coalesce(sum(greatest(coalesce(seats, 1), 1)), 0)::int into v_taken from public.passenger_requests
--      where ride_id = t.id and removed_at is null
--        and coalesce(status, '') not in ('declined', 'cancelled', 'canceled', 'removed')
--        and id is distinct from v_ex_id;
--     v_left := greatest(coalesce(t.available_seats, 0), 0) - v_taken;
--     if p_seats > v_left then return jsonb_build_object('error', 'full'); end if;
--     if v_pid is null then
--       insert into public.passengers (wa_id, name) values (v_wa, v_name) returning id, manage_token into v_pid, v_ptok;
--     end if;
--     if v_ex_id is not null then
--       update public.passenger_requests set seats = p_seats, passenger_name = v_name, note = v_note, status = 'confirmed',
--         pickup_label = v_plabel, pickup_lat = v_plat, pickup_lng = v_plng,
--         dropoff_label = v_dlabel, dropoff_lat = v_dlat, dropoff_lng = v_dlng, passenger_id = v_pid
--        where id = v_ex_id returning id into v_id;
--     else
--       insert into public.passenger_requests (ride_id, passenger_wa_id, passenger_name, seats, note, status,
--         pickup_label, pickup_lat, pickup_lng, dropoff_label, dropoff_lat, dropoff_lng, passenger_id)
--       values (t.id, v_wa, v_name, p_seats, v_note, 'confirmed', v_plabel, v_plat, v_plng, v_dlabel, v_dlat, v_dlng, v_pid)
--       returning id into v_id;
--       v_ins := true;
--     end if;
--     if v_ins then
--       begin
--         select coalesce(nullif(dr.driver_wa_id, ''), d.wa_id), d.manage_token into v_dwa, v_tok
--           from public.driver_routines dr left join public.drivers d on d.id = dr.driver_id where dr.id = t.id;
--         if nullif(v_dwa, '') is not null and nullif(v_tok, '') is not null then
--           v_lft := v_left - p_seats; v_first := split_part(v_name, ' ', 1);
--           v_title := left(coalesce(nullif(v_first, ''), 'A passenger'), 40) || ' joined your ride';
--           v_body := p_seats || case when p_seats = 1 then ' seat' else ' seats' end
--             || ' · ' || initcap(trim(split_part(v_plabel, ',', 1))) || ' → ' || initcap(trim(split_part(v_dlabel, ',', 1)))
--             || ' · ' || case when v_lft <= 0 then 'Ride is now full'
--                              else v_lft || case when v_lft = 1 then ' seat left' else ' seats left' end end;
--           perform public.notify_send(v_dwa, 'passenger_joined', v_title, v_body,
--             '/m/' || v_tok || '?t=' || t.id::text, 'join:' || v_id::text);
--         end if;
--       exception when others then null; end;
--     end if;
--     return jsonb_build_object('booking', jsonb_build_object('id', v_id, 'seats', p_seats, 'status', 'confirmed',
--       'pickup_label', v_plabel, 'dropoff_label', v_dlabel),
--       'trip', public._trip_join_trip_json(t.id), 'passenger_token', v_ptok);
--   end $$;
-- 2) drop the new objects:
--   drop function if exists public.trip_join_verify(text, text, text);
--   drop function if exists public._trip_join_verify_result(uuid, boolean);
--   drop function if exists public._trip_join_book(uuid, uuid, text, text, jsonb, jsonb, int, text);
--   drop function if exists public.trip_join_claim_status(uuid);
--   drop function if exists public.trip_join_start(text, jsonb, jsonb, int, text);
--   drop function if exists public.trip_join_claims_cleanup();
--   drop function if exists public._trip_join_norm_place(jsonb);
--   drop function if exists public._trip_join_gen_verify_code();
--   drop table if exists public.trip_join_claims;
