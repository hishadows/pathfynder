-- Migration: add_user_ids_for_avatars
-- Additive only: exposes non-secret user ids (used as DiceBear avatar seed). No tokens/phones added.
-- Signatures, SECURITY DEFINER, search_path, volatility and grants unchanged.

CREATE OR REPLACE FUNCTION public._trip_join_trip_json(p_trip_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  t record;
  v_first text;
  v_joined int;
  v_left int;
  v_total int;
  v_num text;
  v_text text;
  v_bytes bytea;
  v_enc text := '';
  v_b int;
  v_url text := null;
  v_wa text;
  v_ph text;
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

  -- WhatsApp message link (digits only, no raw number returned)
  -- Pick the first candidate with 11-15 digits. Telegram-form trips store a 10-digit wa_id
  -- (no country code, not on WhatsApp), so driver_phone goes first for those.
  v_wa := regexp_replace(coalesce(t.driver_wa_id, ''), '\D', '', 'g');
  v_ph := regexp_replace(coalesce(t.driver_phone, ''), '\D', '', 'g');
  if coalesce(t.platform, '') ilike 'telegram%' or t.telegram_chat_id is not null then
    v_num := case when length(v_ph) between 11 and 15 then v_ph
                  when length(v_wa) between 11 and 15 then v_wa end;
  else
    v_num := case when length(v_wa) between 11 and 15 then v_wa
                  when length(v_ph) between 11 and 15 then v_ph end;
  end if;
  if v_num is not null then
    v_text := 'Hi ' || coalesce(v_first, 'there') || ', I am joining your ride '
      || coalesce(nullif(trim(split_part(coalesce(t.pickup_label, ''), ',', 1)), ''), 'your ride')
      || ' to '
      || coalesce(nullif(trim(split_part(coalesce(t.dropoff_label, ''), ',', 1)), ''), 'your destination')
      || case when t.departure_datetime is not null
           then ' on ' || to_char(t.departure_datetime at time zone 'America/Toronto', 'Dy, Mon FMDD "at" FMHH12:MI AM')
         when t.departure_time is not null
           then ' at ' || to_char(t.departure_time, 'FMHH12:MI AM')
         else '' end
      || '.';
    v_bytes := convert_to(v_text, 'UTF8');
    for i in 0 .. length(v_bytes) - 1 loop
      v_b := get_byte(v_bytes, i);
      if (v_b between 48 and 57) or (v_b between 65 and 90) or (v_b between 97 and 122) or v_b in (45, 46, 95, 126) then
        v_enc := v_enc || chr(v_b);
      else
        v_enc := v_enc || '%' || upper(lpad(to_hex(v_b), 2, '0'));
      end if;
    end loop;
    v_url := 'https://wa.me/' || v_num || '?text=' || v_enc;
  end if;

  return jsonb_build_object(
    'code', t.join_code,
    'driver_id', t.driver_id,
    'status', case when v_left <= 0 then 'full' else 'open' end,
    'driver_first_name', coalesce(v_first, 'Your driver'),
    'round_trip', false,
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
    'joined_count', v_joined,
    'message_url', v_url
  );
end $function$;

CREATE OR REPLACE FUNCTION public._trip_manage_payload(p_driver_id uuid, p_trip_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
        'passenger_id', p.passenger_id,
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

CREATE OR REPLACE FUNCTION public.driver_profile_get(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  d public.drivers;
  v_digits text;
  v_cc text;
  v_mask text;
  v_notif boolean;
  v_trips int;
  v_pass bigint;
  v_earned numeric;
begin
  select * into d from public.drivers where manage_token = p_token;
  if not found then return jsonb_build_object('error','invalid_token'); end if;

  v_digits := regexp_replace(coalesce(d.wa_id,''), '\D', '', 'g');
  if length(v_digits) < 8 then
    v_mask := '•••';
  else
    v_cc := case when left(v_digits,1) = '1' then '1' else left(v_digits,2) end;
    v_mask := '+' || v_cc || ' ••• ••• ' || right(v_digits,4);
  end if;

  select exists (select 1 from public.notify_subscriptions s where s.wa_id = d.wa_id and s.active)
    into v_notif;

  select count(*) into v_trips
    from public.driver_routines r where r.driver_id = d.id and r.ended_at is not null;

  select coalesce(sum(coalesce(pr.seats,1)),0),
         coalesce(sum(coalesce(r.fare,0) * coalesce(pr.seats,1)),0)
    into v_pass, v_earned
    from public.passenger_requests pr
    join public.driver_routines r on r.id = pr.ride_id
   where r.driver_id = d.id and pr.dropped_off_at is not null and pr.removed_at is null;

  return jsonb_build_object(
    'id', d.id,
    'name', d.name,
    'photo_url', d.photo,
    'whatsapp_masked', v_mask,
    'notifications_enabled', coalesce(v_notif,false),
    'stats', jsonb_build_object(
      'trips_completed', v_trips,
      'member_since', d.created_at,
      'passengers_drove', v_pass,
      'total_earned', round(v_earned,2)
    )
  );
end $function$;

CREATE OR REPLACE FUNCTION public.passenger_profile_get(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
    'id', ps.id,
    'name', ps.name, 'photo_url', ps.photo, 'whatsapp_masked', v_mask,
    'notifications_enabled', coalesce(v_notif, false),
    'stats', jsonb_build_object(
      'rides_completed', v_done, 'rides_upcoming', v_up,
      'member_since', ps.created_at, 'total_spent', round(v_spent, 2)));
end $function$;

CREATE OR REPLACE FUNCTION public.passenger_trip_get(p_token text, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
      'driver', jsonb_build_object('id', d.id, 'name', coalesce(d.name, r.driver_name), 'photo', d.photo, 'phone', v_phone)),
    'booking', jsonb_build_object(
      'id', b.id, 'status', v_bstatus, 'seats', b.seats,
      'pickup_label', b.pickup_label, 'pickup_lat', b.pickup_lat, 'pickup_lng', b.pickup_lng,
      'dropoff_label', b.dropoff_label, 'dropoff_lat', b.dropoff_lat, 'dropoff_lng', b.dropoff_lng,
      'picked_up_at', b.picked_up_at, 'dropped_off_at', b.dropped_off_at, 'note', b.note),
    'counts', jsonb_build_object('passengers', v_cnt, 'picked_up', v_picked));
end $function$;
