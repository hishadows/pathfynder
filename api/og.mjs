// Link-preview image (Open Graph) for shared Pathfynder links.
//   /api/og?v=join&code=ABC123    trip card (route, time, price, seats, driver)
//   /api/og?v=invite&code=ABC123  "ride together" invite card for the same trip
//   /api/og?v=request&id=<uuid>  "needs a ride" card for an open passenger request (request_card_get)
//   anything else / unknown code  -> brand card
// Only public facts from anon RPCs (trip_join_get, request_card_get): no phone numbers.
import { ImageResponse } from '@vercel/og';
import { readFile } from 'node:fs/promises';
import LOGO from './_og/logo.mjs';

var SUPABASE_URL = 'https://omussxfyrztjahbdrrpi.supabase.co';
var SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9tdXNzeGZ5cnp0amFoYmRycnBpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0MjI1NjAsImV4cCI6MjA5NTk5ODU2MH0.ySigym7uOaFIQm01nErPfn4kE6j4MOVKoNntt_Mosak';
var CODE_RE = /^[A-Za-z0-9]{4,12}$/;
var UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
var TZ = 'America/Toronto';
var W = 1200, H = 630;

function ab(buf) { return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength); }
var fontsP = null;
function loadFonts() {
  if (!fontsP) {
    fontsP = Promise.all([
      readFile(new URL('./_og/Inter-ExtraBold.woff', import.meta.url)),
      readFile(new URL('./_og/Inter-Bold.woff', import.meta.url)),
    ]).then(function (b) {
      return [{ name: 'Inter', data: ab(b[0]), weight: 800, style: 'normal' }, { name: 'Inter', data: ab(b[1]), weight: 700, style: 'normal' }];
    });
  }
  return fontsP;
}

function h(type, style, children) { return { type: type, props: { style: style, children: children } }; }
function box(style, children) { return h('div', Object.assign({ display: 'flex' }, style), children); }
function txt(style, s) { return h('div', Object.assign({ display: 'flex' }, style), String(s)); }
function shortLabel(s) { return String(s || '').split(',')[0].trim() || 'Pathfynder'; }
function initial(s) { var m = String(s || '').match(/\p{L}/u); return m ? m[0].toUpperCase() : 'P'; }
function citySize(a, b) { var n = Math.max(a.length, b.length); return n <= 10 ? 84 : n <= 16 ? 72 : n <= 24 ? 58 : 46; }

// Date/time in America/Toronto: day "Today (Fri, Oct 9)" / "Tomorrow (Sat, Oct 10)" / "Fri, Oct 9", time "10:00 AM".
function ymd(d) {
  var o = {};
  new Intl.DateTimeFormat('en-US', { timeZone: TZ, year: 'numeric', month: 'numeric', day: 'numeric' }).formatToParts(d).forEach(function (p) { o[p.type] = p.value; });
  return o.year + '-' + o.month + '-' + o.day;
}
function whenParts(iso, now) {
  var d = new Date(iso);
  if (!iso || isNaN(d.getTime())) return null;
  now = now || new Date();
  var short = new Intl.DateTimeFormat('en-US', { timeZone: TZ, weekday: 'short', month: 'short', day: 'numeric' }).format(d);
  var time = new Intl.DateTimeFormat('en-US', { timeZone: TZ, hour: 'numeric', minute: '2-digit', hour12: true }).format(d).replace(/\s/g, ' ');
  var td = ymd(now).split('-').map(Number), tmr = new Date(Date.UTC(td[0], td[1] - 1, td[2] + 1, 12));
  var k = ymd(d);
  var key = function (a) { return a.getUTCFullYear() + '-' + (a.getUTCMonth() + 1) + '-' + a.getUTCDate(); };
  var day = k === ymd(now) ? 'Today (' + short + ')' : (k === key(tmr) ? 'Tomorrow (' + short + ')' : short);
  return { day: day, time: time };
}
// Right-hand date/time block: day label over a big time, behind a thin divider.
function whenBlock(w, dark) {
  return box({ flexDirection: 'column', alignItems: 'flex-end', flexShrink: 0, paddingLeft: 36, borderLeft: dark ? '3px solid rgba(255,255,255,0.25)' : '3px solid #c9dbd1' }, [
    txt({ fontSize: dark ? 30 : 28, fontWeight: 700, color: dark ? '#9fe3c3' : '#3b6b59', whiteSpace: 'nowrap' }, w.day),
    txt({ marginTop: 6, fontSize: dark ? 92 : 76, fontWeight: 800, lineHeight: 1, whiteSpace: 'nowrap' }, w.time),
  ]);
}
// Dots + From/To, used by the join and request cards (maxW caps each city name).
function routeBlock(from, to, sz, maxW) {
  return box({ alignItems: 'flex-start', minWidth: 0 }, [
    box({ flexDirection: 'column', alignItems: 'center', justifyContent: 'space-between', height: Math.round(sz * 1.05 * 2 + 22 - sz * 0.6), marginTop: Math.round(sz * 0.3), marginRight: 30, flexShrink: 0 }, [
      box({ width: 26, height: 26, borderRadius: 13, background: '#FFFFFF', flexShrink: 0 }),
      box({ flexGrow: 1, width: 0, margin: '6px 0', borderLeft: '4px dashed rgba(255,255,255,0.7)' }),
      box({ width: 26, height: 26, borderRadius: 13, background: '#25D366', flexShrink: 0 }),
    ]),
    box({ flexDirection: 'column' }, [
      txt({ fontSize: sz, fontWeight: 800, lineHeight: 1.05, maxWidth: maxW, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }, from),
      txt({ marginTop: 22, fontSize: sz, fontWeight: 800, lineHeight: 1.05, maxWidth: maxW, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }, to),
    ]),
  ]);
}

async function getTrip(code) {
  if (!CODE_RE.test(code || '')) return null;
  try {
    var ctl = new AbortController(); var t = setTimeout(function () { ctl.abort(); }, 3000);
    var r = await fetch(SUPABASE_URL + '/rest/v1/rpc/trip_join_get', {
      method: 'POST', signal: ctl.signal,
      headers: { 'Content-Type': 'application/json', apikey: SUPABASE_ANON, Authorization: 'Bearer ' + SUPABASE_ANON },
      body: JSON.stringify({ p_code: code }),
    });
    clearTimeout(t);
    if (!r.ok) return null;
    var d = await r.json();
    d = Array.isArray(d) ? d[0] : d;
    return d && d.trip ? d.trip : null;
  } catch (e) { return null; }
}

async function getRequest(id) {
  if (!UUID_RE.test(id || '')) return null;
  try {
    var ctl = new AbortController(); var t = setTimeout(function () { ctl.abort(); }, 3000);
    var r = await fetch(SUPABASE_URL + '/rest/v1/rpc/request_card_get', {
      method: 'POST', signal: ctl.signal,
      headers: { 'Content-Type': 'application/json', apikey: SUPABASE_ANON, Authorization: 'Bearer ' + SUPABASE_ANON },
      body: JSON.stringify({ p_id: id }),
    });
    clearTimeout(t);
    if (!r.ok) return null;
    var d = await r.json();
    d = Array.isArray(d) ? d[0] : d;
    return d && typeof d === 'object' && d.open === true ? d : null;
  } catch (e) { return null; }
}

function logoImg() { return { type: 'img', props: { src: LOGO, width: 62, height: 62, style: { objectFit: 'contain' } } }; }
function brandHeader(dark) {
  return box({ alignItems: 'center' }, [
    box({ width: 84, height: 84, borderRadius: 22, background: '#FFFFFF', alignItems: 'center', justifyContent: 'center', overflow: 'hidden', border: dark ? '0px solid #fff' : '2px solid #dbe6df' }, logoImg()),
    txt({ marginLeft: 20, fontSize: 34, fontWeight: 700, color: dark ? '#FFFFFF' : '#0B3D2E' }, 'Pathfynder'),
  ]);
}

function joinCard(t) {
  var from = shortLabel(t.origin_label), to = shortLabel(t.dest_label), sz = citySize(from, to);
  var full = t.status === 'full' || Number(t.seats_left) <= 0;
  var w = whenParts(t.depart_at);
  var pills = [];
  if (!w && t.schedule_text) pills.push(String(t.schedule_text));
  if (t.price_per_seat != null && Number(t.price_per_seat) > 0) pills.push('$' + Number(t.price_per_seat) + ' / seat');
  pills.push(full ? 'Ride full' : (Number(t.seats_left) + (Number(t.seats_left) === 1 ? ' seat left' : ' seats left')));
  var pillEls = pills.map(function (p, i) {
    return txt({ background: 'rgba(255,255,255,0.16)', border: '2px solid rgba(255,255,255,0.28)', borderRadius: 999, padding: '14px 28px', fontSize: 32, fontWeight: 700, marginRight: 16 }, p);
  });
  var drvName = String(t.driver_first_name || '').trim();
  return box({ width: W, height: H, position: 'relative', flexDirection: 'column', padding: '64px 72px', color: '#FFFFFF', fontFamily: 'Inter', backgroundImage: 'linear-gradient(135deg, #0B3D2E 0%, #0F5C43 55%, #138a63 100%)' }, [
    brandHeader(true),
    txt({ marginTop: 46, fontSize: 26, fontWeight: 700, letterSpacing: 3, color: '#9fe3c3' }, 'JOIN THIS RIDE'),
    w ? box({ marginTop: 14, alignItems: 'center', justifyContent: 'space-between', width: 1056 }, [routeBlock(from, to, Math.min(sz, 76), 500), whenBlock(w, true)])
      : box({ marginTop: 14 }, routeBlock(from, to, sz, 1000)),
    box({ position: 'absolute', left: 72, bottom: 56 }, pillEls),
    drvName ? box({ position: 'absolute', right: 72, top: 62, alignItems: 'center' }, [
      txt({ width: 84, height: 84, borderRadius: 42, background: '#FFFFFF', color: '#0F5C43', fontSize: 42, fontWeight: 800, alignItems: 'center', justifyContent: 'center' }, initial(drvName)),
      box({ flexDirection: 'column', marginLeft: 20 }, [
        txt({ fontSize: 22, fontWeight: 700, color: '#9fe3c3' }, 'Driver'),
        txt({ fontSize: 36, fontWeight: 800, maxWidth: 240, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }, drvName),
      ]),
    ]) : null,
  ].filter(Boolean));
}

function inviteCard(t) {
  var from = shortLabel(t.origin_label), to = shortLabel(t.dest_label);
  var drvName = String(t.driver_first_name || '').trim() || 'your driver';
  var w = whenParts(t.depart_at);
  var sub = from + ' to ' + to + (!w && t.schedule_text ? ' · ' + t.schedule_text : '');
  return box({ width: W, height: H, position: 'relative', flexDirection: 'column', padding: '64px 72px', background: '#EEF3EF', color: '#0B3D2E', fontFamily: 'Inter' }, [
    box({ position: 'absolute', left: 0, right: 0, bottom: 0, height: 128, background: '#0F5C43' }),
    brandHeader(false),
    box({ alignItems: 'center', justifyContent: 'space-between', marginTop: 26, width: 1056 }, [
      box({ alignItems: 'center' }, [
      txt({ width: 120, height: 120, borderRadius: 60, background: '#0F5C43', color: '#FFFFFF', fontSize: 58, fontWeight: 800, alignItems: 'center', justifyContent: 'center', border: '8px solid #EEF3EF' }, initial(drvName)),
      txt({ width: 120, height: 120, borderRadius: 60, background: '#25D366', color: '#0B3D2E', fontSize: 58, fontWeight: 800, alignItems: 'center', justifyContent: 'center', border: '8px solid #EEF3EF', marginLeft: -34 }, '+'),
      ]),
      w ? whenBlock(w, false) : null,
    ].filter(Boolean)),
    txt({ marginTop: 22, fontSize: 64, fontWeight: 800, lineHeight: 1.08, maxWidth: 1056, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }, 'Ride together with ' + drvName),
    txt({ marginTop: 10, fontSize: 36, fontWeight: 700, color: '#3b6b59', maxWidth: 1056, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }, sub),
    txt({ position: 'absolute', left: 72, bottom: 30, background: '#FFFFFF', color: '#0B3D2E', borderRadius: 999, padding: '16px 38px', fontSize: 34, fontWeight: 800 }, 'Join the ride'),
    txt({ position: 'absolute', right: 72, bottom: 44, color: '#cfeee0', fontSize: 32, fontWeight: 700 }, 'pathfynder.ca'),
  ]);
}

function requestCard(q) {
  var from = shortLabel(q.from_label), to = shortLabel(q.to_label), sz = Math.min(citySize(from, to), 76);
  var w = whenParts(q.depart_at) || { day: '', time: '' };
  var n = Number(q.seats) || 1;
  var seats = n + (n === 1 ? ' seat' : ' seats');
  var name = String(q.first_name || '').trim();
  return box({ width: W, height: H, position: 'relative', flexDirection: 'column', padding: '64px 72px', color: '#FFFFFF', fontFamily: 'Inter', backgroundImage: 'linear-gradient(135deg, #0B3D2E 0%, #0F5C43 55%, #138a63 100%)' }, [
    brandHeader(true),
    txt({ marginTop: 46, fontSize: 26, fontWeight: 700, letterSpacing: 3, color: '#9fe3c3' }, 'NEEDS A RIDE'),
    box({ marginTop: 14, alignItems: 'center', justifyContent: 'space-between', width: 1056 }, [routeBlock(from, to, sz, 500), whenBlock(w, true)]),
    box({ position: 'absolute', left: 72, bottom: 56 }, [
      txt({ background: 'rgba(255,255,255,0.16)', border: '2px solid rgba(255,255,255,0.28)', borderRadius: 999, padding: '14px 28px', fontSize: 32, fontWeight: 700 }, seats),
    ]),
    txt({ position: 'absolute', right: 72, bottom: 56, background: '#25D366', color: '#0B3D2E', borderRadius: 999, padding: '14px 30px', fontSize: 32, fontWeight: 800 }, 'Offer a ride'),
    name ? box({ position: 'absolute', right: 72, top: 62, alignItems: 'center' }, [
      txt({ width: 84, height: 84, borderRadius: 42, background: '#FFFFFF', color: '#0F5C43', fontSize: 42, fontWeight: 800, alignItems: 'center', justifyContent: 'center' }, initial(name)),
      box({ flexDirection: 'column', marginLeft: 20 }, [
        txt({ fontSize: 22, fontWeight: 700, color: '#9fe3c3' }, 'Passenger'),
        txt({ fontSize: 36, fontWeight: 800, maxWidth: 240, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }, name),
      ]),
    ]) : null,
  ].filter(Boolean));
}

function brandCard() {
  return box({ width: W, height: H, position: 'relative', alignItems: 'center', justifyContent: 'center', flexDirection: 'column', fontFamily: 'Inter', color: '#FFFFFF', backgroundImage: 'linear-gradient(140deg, #0E6F73 0%, #0B4F52 100%)' }, [
    box({ width: 210, height: 210, borderRadius: 52, background: '#FFFFFF', alignItems: 'center', justifyContent: 'center', marginBottom: 34 },
      { type: 'img', props: { src: LOGO, width: 150, height: 150, style: { objectFit: 'contain' } } }),
    txt({ fontSize: 92, fontWeight: 800 }, 'Pathfynder'),
    txt({ marginTop: 16, fontSize: 42, fontWeight: 700, color: '#bfeff0' }, 'Community rideshare across Ontario'),
  ]);
}

export default {
  async fetch(request) {
    var u = new URL(request.url);
    var v = u.searchParams.get('v') || 'brand';
    var code = u.searchParams.get('code') || '';
    try {
      var card = null;
      if (v === 'request') {
        var rq = await getRequest(u.searchParams.get('id') || '');
        if (rq) card = requestCard(rq);
      } else if (v === 'join' || v === 'invite') {
        var trip = await getTrip(code);
        if (trip) card = v === 'invite' ? inviteCard(trip) : joinCard(trip);
      }
      if (!card) card = brandCard();
      var img = new ImageResponse(card, { width: W, height: H, fonts: await loadFonts() });
      /* ImageResponse adds a 1-year immutable cache header; re-wrap so seats/time stay fresh (CDN 10 min, browsers/crawlers 5 min). */
      return new Response(img.body, { status: 200, headers: { 'Content-Type': 'image/png', 'Cache-Control': 'public, max-age=300, s-maxage=600, stale-while-revalidate=3600' } });
    } catch (e) {
      console.error('[og] render failed', e && e.message);
      return new Response(null, { status: 302, headers: { Location: 'https://www.pathfynder.ca/og-brand.png' } });
    }
  },
};
