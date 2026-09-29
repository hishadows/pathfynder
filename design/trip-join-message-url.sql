-- Join page: trip_join_get / _trip_join_trip_json return trip.message_url
-- Migrations: trip_join_get_message_url, trip_join_message_url_pick_number (both applied 2026-09-29)
-- message_url = https://wa.me/<digits>?text=<url-encoded prefilled text>. Omitted (null) when the
-- driver has no usable number. The raw number is never returned as its own field.
-- Only the helper changes; trip_join_get calls it, so its signature/grants are untouched.

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

-- Grants unchanged (helper: service_role only; trip_join_get: anon/authenticated/service_role).
-- Rollback: re-run the previous body (see design/trip-join-rpcs-live.sql) without message_url.
