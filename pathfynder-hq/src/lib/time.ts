import { formatInTimeZone, fromZonedTime } from 'date-fns-tz'

export const TZ = 'America/Toronto'

export function torontoToday(): string {
  return formatInTimeZone(new Date(), TZ, 'yyyy-MM-dd')
}

export function torontoDaysAgo(n: number): string {
  const d = new Date()
  d.setUTCDate(d.getUTCDate() - n)
  return formatInTimeZone(d, TZ, 'yyyy-MM-dd')
}

export function torontoRangeToUtc(startDay: string, endDay: string): { startUtc: string; endUtc: string } {
  const startUtc = fromZonedTime(`${startDay}T00:00:00`, TZ).toISOString()
  const end = new Date(`${endDay}T00:00:00`)
  end.setUTCDate(end.getUTCDate() + 1)
  const endDayPlus = end.toISOString().slice(0, 10)
  const endUtc = fromZonedTime(`${endDayPlus}T00:00:00`, TZ).toISOString()
  return { startUtc, endUtc }
}

export function fmtMsgTime(iso: string | null): string {
  if (!iso) return '—'
  return formatInTimeZone(new Date(iso), TZ, 'MMM d, h:mm a')
}

export function fmtClock(iso: string | null): string {
  if (!iso) return '—'
  return formatInTimeZone(new Date(iso), TZ, 'h:mm:ss a')
}

export function fmtRideTime(t: string | null): string {
  if (!t) return '—'
  const m = t.match(/^(\d{2}):(\d{2})/)
  return m ? `${m[1]}:${m[2]}` : t
}

export function nowInToronto(): string {
  return formatInTimeZone(new Date(), TZ, 'EEE, MMM d • h:mm:ss a')
}
