-- Run in Supabase SQL Editor (project omussxfyrztjahbdrrpi). Plan.md task 11, notify part.
-- apply_migration timed out for notify_check_new_matches; the other two notify functions were applied.
-- Only change vs. the live definition: the explore_search filters now also carry the driver's own stops ('via')
-- for requests whose source_ref starts with 'driver_routines:'. Same signature, ACL is preserved by CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION public.notify_check_new_matches(p_scope text DEFAULT 'all'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
-- p_scope: which table fired the check (or 'all'); informational, every open trip is checked.
declare
  v_first int := public.notify_setting('first_alert_min')::int;
  v_thr int := public.notify_setting('alert_threshold')::int;
  v_req record;
  v_p record;
  v_title text;
  v_body text;
  v_noun text;
begin
  if coalesce(public.notify_setting('match_alerts_enabled'), 'false') <> 'true' then
    return;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('pf_notify_matches')) then
    return;
  end if;

  create temp table if not exists _pf_trips (token uuid, wa_id text, trip_key uuid) on commit drop;
  create temp table if not exists _pf_cur (token uuid, ride_ref text) on commit drop;
  create temp table if not exists _pf_new (token uuid, ride_ref text) on commit drop;
  truncate _pf_trips, _pf_cur, _pf_new;

  insert into _pf_trips select * from public.notify_open_trips();

  -- current parsed matches per open request; unseen ones become "new"
  for v_req in select r.* from public.notify_requests r join _pf_trips t on t.token = r.token loop
    insert into _pf_cur (token, ride_ref)
    select v_req.token, s.id
    from public.explore_search(v_req.mode, v_req.from_lat, v_req.from_lng, v_req.to_lat, v_req.to_lng, v_req.ride_date,
           -- viewer_token: never alert a requester about their own Pathfynder post. Keep this in any rewrite.
           -- via: a driver's own stops (driver_routines:<id> requests) so passengers near a stop count as matches.
           jsonb_build_object('viewer_token', v_req.token::text)
           || coalesce((select jsonb_build_object('via', d.stops) from public.driver_routines d
                         where v_req.source_ref like 'driver_routines:%' and d.id::text = substr(v_req.source_ref, 17)
                           and jsonb_typeof(d.stops) = 'array' and jsonb_array_length(d.stops) > 0), '{}'::jsonb)) s
    where s.parsed;
  end loop;

  insert into public.notify_seen (request_token, ride_ref, seeded)
  select c.token, c.ride_ref, false from _pf_cur c on conflict do nothing;

  insert into _pf_new (token, ride_ref)
  select h.request_token, h.ride_ref from public.notify_seen h join _pf_trips t on t.token = h.request_token where not h.seeded;

  -- per trip: stage (max over group), available count (distinct current rides), new count (distinct new rides)
  create temp table if not exists _pf_trip_state (wa_id text, trip_key uuid, stage smallint, avail int, new_n int, next_stage smallint) on commit drop;
  truncate _pf_trip_state;
  insert into _pf_trip_state
  select t.wa_id, t.trip_key,
         max(r.alert_stage)::smallint,
         (select count(distinct c.ride_ref) from _pf_cur c join _pf_trips t2 on t2.token = c.token where t2.trip_key = t.trip_key),
         (select count(distinct n.ride_ref) from _pf_new n join _pf_trips t2 on t2.token = n.token where t2.trip_key = t.trip_key),
         null
  from _pf_trips t join public.notify_requests r on r.token = t.token
  group by t.wa_id, t.trip_key;

  update _pf_trip_state set next_stage = case
      when new_n = 0 then null
      when stage = 0 and new_n >= v_first then case when avail >= v_thr then 2 else 1 end
      when stage = 1 and avail >= v_thr then 2
      else null end;

  -- one push per person: biggest pending trip; other pending trips ride along as "+N more rides"
  for v_p in
    select distinct on (s.wa_id) s.wa_id, s.trip_key, s.avail, s.next_stage,
           (select coalesce(sum(o.new_n), 0) from _pf_trip_state o
             where o.wa_id = s.wa_id and o.next_stage is not null and o.trip_key <> s.trip_key) more
    from _pf_trip_state s
    where s.next_stage is not null
    order by s.wa_id, s.avail desc, s.trip_key
  loop
    select * into v_req from public.notify_requests where token = v_p.trip_key;
    v_noun := case when v_req.mode = 'passengers' then 'passenger' else 'driver' end;
    v_title := v_p.avail || ' ' || v_noun || case when v_p.avail = 1 then '' else 's' end || ' available';
    v_body := coalesce(v_req.label, '') || case when v_p.more > 0 then ' · +' || v_p.more || ' more rides' else '' end;
    perform public.notify_send(v_p.wa_id, 'new_match', v_title, v_body, public.notify_explore_url(v_p.trip_key),
                               'match:' || v_p.wa_id || ':' || v_p.trip_key || ':' || v_p.next_stage);
  end loop;

  -- store stage on every request of every trip that was covered by a push
  update public.notify_requests r set alert_stage = s.next_stage
  from _pf_trips t join _pf_trip_state s on s.trip_key = t.trip_key
  where r.token = t.token and s.next_stage is not null and r.alert_stage < s.next_stage;

  -- everything processed this run is no longer "new"
  update public.notify_seen h set seeded = true
  from _pf_trips t where h.request_token = t.token and not h.seeded;
end;
$function$;
