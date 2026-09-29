-- =====================================================================
-- driver-notifications-rpcs.sql  (2026-09-29)
-- Applied as migration: driver_notifications_rpcs (project omussxfyrztjahbdrrpi).
-- Driver-home notification bell: list + mark-read, keyed by drivers.manage_token.
-- notify_log columns (live): id bigint, wa_id, kind, dedupe_key, created_at, title, body, url.
-- RLS is on with no policies; the RPCs are security definer. wa_id is never returned.
-- =====================================================================

alter table public.notify_log add column if not exists read_at timestamptz;
create index if not exists notify_log_wa_created_idx on public.notify_log (wa_id, created_at desc);
-- Existing rows count as read, so only NEW notifications show as unread.
update public.notify_log set read_at = now() where read_at is null;

create or replace function public.driver_notifications_list(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_wa text;
  v_list jsonb;
  v_unread int;
begin
  select wa_id into v_wa from public.drivers
  where manage_token = nullif(trim(coalesce(p_token, '')), '') limit 1;
  if v_wa is null then return jsonb_build_object('error', 'invalid_token'); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', n.id, 'kind', n.kind, 'title', n.title, 'body', n.body, 'url', n.url,
           'created_at', n.created_at, 'read', n.read_at is not null)
         order by n.created_at desc, n.id desc), '[]'::jsonb)
    into v_list
  from (select * from public.notify_log
        where wa_id = v_wa and kind is distinct from 'test'
        order by created_at desc, id desc limit 30) n;

  select count(*)::int into v_unread from public.notify_log
  where wa_id = v_wa and kind is distinct from 'test' and read_at is null;

  return jsonb_build_object('notifications', v_list, 'unread_count', v_unread);
end $$;

create or replace function public.driver_notifications_mark_read(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare v_wa text;
begin
  select wa_id into v_wa from public.drivers
  where manage_token = nullif(trim(coalesce(p_token, '')), '') limit 1;
  if v_wa is null then return jsonb_build_object('error', 'invalid_token'); end if;
  update public.notify_log set read_at = now() where wa_id = v_wa and read_at is null;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.driver_notifications_list(text) from public;
revoke all on function public.driver_notifications_mark_read(text) from public;
grant execute on function public.driver_notifications_list(text) to anon, authenticated;
grant execute on function public.driver_notifications_mark_read(text) to anon, authenticated;

-- ROLLBACK
-- drop function if exists public.driver_notifications_list(text);
-- drop function if exists public.driver_notifications_mark_read(text);
-- drop index if exists public.notify_log_wa_created_idx;
-- alter table public.notify_log drop column if exists read_at;
