import { supabase } from './supabase'
import { torontoRangeToUtc } from './time'

export interface FeedRow {
  id: number
  type: string | null
  original_message: string | null
  sender_name: string | null
  sender_number: number | null
  pickup_label: string | null
  dropoff_label: string | null
  ride_time: string | null
  ride_date: string | null
  additional_conditions: string | null
  group_name: string | null
  msg_ts: string | null
  ride_frequency: string | null
  important_ride: string | null
  geo_status: string | null
  pickup_lat: number | null
  pickup_lng: number | null
  dropoff_lat: number | null
  dropoff_lng: number | null
  total_count: number
}

export interface WindowStats {
  total: number
  passengers: number
  drivers: number
  unique_senders: number
  active_groups: number
  urgent: number
  geo_ok: number
  geo_failed: number
}

export type FeedType = 'all' | 'passenger' | 'driver'

const typeArg = (t: FeedType): string | null =>
  t === 'passenger' ? 'passenger' : t === 'driver' ? 'Driver' : null

/** Paginated feed for a Toronto day-range. */
export async function fetchFeed(opts: {
  startDay: string
  endDay: string
  type: FeedType
  search: string
  limit: number
  offset: number
}): Promise<{ rows: FeedRow[]; total: number }> {
  const { startUtc, endUtc } = torontoRangeToUtc(opts.startDay, opts.endDay)
  const { data, error } = await supabase.rpc('get_feed', {
    p_start: startUtc,
    p_end: endUtc,
    p_type: typeArg(opts.type),
    p_search: opts.search || null,
    p_limit: opts.limit,
    p_offset: opts.offset,
  })
  if (error) throw error
  const rows = (data ?? []) as FeedRow[]
  return { rows, total: rows.length ? Number(rows[0].total_count) : 0 }
}

/** KPI aggregates for a Toronto day-range. */
export async function fetchWindowStats(startDay: string, endDay: string): Promise<WindowStats> {
  const { startUtc, endUtc } = torontoRangeToUtc(startDay, endDay)
  const { data, error } = await supabase.rpc('get_window_stats', { p_start: startUtc, p_end: endUtc })
  if (error) throw error
  return data as WindowStats
}

// ── Insight RPCs already present in the project ──
export async function fetchHourly(): Promise<{ hour: number; count: number }[]> {
  const { data, error } = await supabase.rpc('get_hourly_activity')
  if (error) throw error
  return (data ?? []) as any
}

export async function fetchCorridors(lim = 10): Promise<any[]> {
  const { data, error } = await supabase.rpc('get_top_corridors', { lim })
  if (error) throw error
  return (data ?? []) as any
}

export async function fetchGroups(lim = 8): Promise<any[]> {
  const { data, error } = await supabase.rpc('get_top_groups', { lim })
  if (error) throw error
  return (data ?? []) as any
}

export interface DayPoint { day: string; total: number; passengers: number; drivers: number }

export async function fetchDailySeries(startDay: string, endDay: string): Promise<DayPoint[]> {
  const { startUtc, endUtc } = torontoRangeToUtc(startDay, endDay)
  const { data, error } = await supabase.rpc('get_daily_series', { p_start: startUtc, p_end: endUtc })
  if (error) throw error
  return (data ?? []).map((d: any) => ({
    day: d.day, total: Number(d.total), passengers: Number(d.passengers), drivers: Number(d.drivers),
  }))
}

export interface PowerUser {
  sender_number: number | null
  sender_name: string | null
  msg_count: number
  passenger_count: number
  driver_count: number
  last_seen: string | null
  top_pickup: string | null
  top_dropoff: string | null
}

/** Top senders by message count for a Toronto day-range, split by role. */
export async function fetchPowerUsers(
  startDay: string, endDay: string, type: FeedType, limit: number,
): Promise<PowerUser[]> {
  const { startUtc, endUtc } = torontoRangeToUtc(startDay, endDay)
  const { data, error } = await supabase.rpc('get_power_users', {
    p_start: startUtc,
    p_end: endUtc,
    p_type: typeArg(type),
    p_limit: limit,
  })
  if (error) throw error
  return (data ?? []).map((d: any) => ({
    sender_number: d.sender_number,
    sender_name: d.sender_name,
    msg_count: Number(d.msg_count),
    passenger_count: Number(d.passenger_count),
    driver_count: Number(d.driver_count),
    last_seen: d.last_seen,
    top_pickup: d.top_pickup,
    top_dropoff: d.top_dropoff,
  }))
}
