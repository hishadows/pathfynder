// /j/:code -> /api/j?code=:code (see vercel.json rewrite).
// Serves the normal join page (fetched from /join on the same site, so join.html stays the single source of truth)
// with per-trip Open Graph tags injected into <head>, so a shared link shows the route / time / seats card.
//   ?i=friend  -> "Ride together with <driver>" invite card instead of the join card
// Only public trip facts from trip_join_get (the anon RPC the join page already uses). No phone numbers.
// Invalid / expired / unreachable trips get the generic brand card. The page itself always loads.

var SUPABASE_URL = 'https://omussxfyrztjahbdrrpi.supabase.co';
var SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9tdXNzeGZ5cnp0amFoYmRycnBpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0MjI1NjAsImV4cCI6MjA5NTk5ODU2MH0.ySigym7uOaFIQm01nErPfn4kE6j4MOVKoNntt_Mosak';
var SITE = 'https://www.pathfynder.ca';
var CODE_RE = /^[A-Za-z0-9]{4,12}$/;
var BRAND_TITLE = 'Pathfynder · Community rideshare';
var BRAND_DESC = 'Find drivers and passengers across Ontario, from WhatsApp groups, Poparide and more.';

function esc(s) {
  return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; });
}
function shortLabel(s) { return String(s || '').split(',')[0].trim() || 'Pathfynder'; }
function timed(url, opts, ms) {
  var ctl = new AbortController(); var t = setTimeout(function () { ctl.abort(); }, ms);
  opts = opts || {}; opts.signal = ctl.signal;
  return fetch(url, opts).finally(function () { clearTimeout(t); });
}

async function getTrip(code) {
  try {
    var r = await timed(SUPABASE_URL + '/rest/v1/rpc/trip_join_get', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: SUPABASE_ANON, Authorization: 'Bearer ' + SUPABASE_ANON },
      body: JSON.stringify({ p_code: code }),
    }, 2500);
    if (!r.ok) return null;
    var d = await r.json();
    d = Array.isArray(d) ? d[0] : d;
    return d && d.trip ? d.trip : null;
  } catch (e) { return null; }
}

function buildMeta(code, friend, trip) {
  var pageUrl = SITE + '/j/' + code + (friend ? '?i=friend' : '');
  var title = BRAND_TITLE, desc = BRAND_DESC, image = SITE + '/og-brand.png', alt = 'Pathfynder';
  if (trip) {
    var from = shortLabel(trip.origin_label), to = shortLabel(trip.dest_label);
    var when = trip.schedule_text ? ' · ' + trip.schedule_text : '';
    var full = trip.status === 'full' || Number(trip.seats_left) <= 0;
    var seats = full ? 'This ride is full.' : (Number(trip.seats_left) + (Number(trip.seats_left) === 1 ? ' seat left.' : ' seats left.'));
    var price = trip.price_per_seat != null && Number(trip.price_per_seat) > 0 ? '$' + Number(trip.price_per_seat) + ' per seat · ' : '';
    var drv = String(trip.driver_first_name || '').trim();
    if (friend) {
      title = 'Ride together with ' + (drv || 'your driver');
      desc = from + ' to ' + to + when + '. ' + seats + (full ? '' : ' Tap to join the ride.');
      image = SITE + '/api/og?v=invite&code=' + encodeURIComponent(code);
      alt = 'Invitation to ride ' + from + ' to ' + to;
    } else {
      title = from + ' → ' + to + when;
      desc = price + seats + (drv ? ' Ride with ' + drv + '.' : '') + (full ? '' : ' Tap to book your seat.');
      image = SITE + '/api/og?v=join&code=' + encodeURIComponent(code);
      alt = 'Ride from ' + from + ' to ' + to;
    }
  } else {
    title = 'This ride isn’t available · Pathfynder';
  }
  return { title: title, tags:
    '<title>' + esc(title) + '</title>' +
    '<meta name="robots" content="noindex">' +
    '<meta name="description" content="' + esc(desc) + '">' +
    '<meta property="og:site_name" content="Pathfynder">' +
    '<meta property="og:type" content="website">' +
    '<meta property="og:title" content="' + esc(title) + '">' +
    '<meta property="og:description" content="' + esc(desc) + '">' +
    '<meta property="og:url" content="' + esc(pageUrl) + '">' +
    '<meta property="og:image" content="' + esc(image) + '">' +
    '<meta property="og:image:secure_url" content="' + esc(image) + '">' +
    '<meta property="og:image:type" content="image/png">' +
    '<meta property="og:image:width" content="1200">' +
    '<meta property="og:image:height" content="630">' +
    '<meta property="og:image:alt" content="' + esc(alt) + '">' +
    '<meta name="twitter:card" content="summary_large_image">' +
    '<meta name="twitter:title" content="' + esc(title) + '">' +
    '<meta name="twitter:description" content="' + esc(desc) + '">' +
    '<meta name="twitter:image" content="' + esc(image) + '">' };
}

module.exports = async function handler(req, res) {
  var code = req.query && req.query.code;
  code = typeof code === 'string' ? code : '';
  var friend = req.query && req.query.i === 'friend';
  var origin = 'https://' + (req.headers['x-forwarded-host'] || req.headers.host || 'www.pathfynder.ca');

  var pageP = timed(origin + '/join', { headers: { 'x-pf-internal': '1' } }, 4000).then(function (r) { return r.ok ? r.text() : null; }).catch(function () { return null; });
  var tripP = CODE_RE.test(code) ? getTrip(code) : Promise.resolve(null);
  var results = await Promise.all([pageP, tripP]);
  var html = results[0], trip = results[1];

  if (!html) { res.writeHead(302, { Location: SITE + '/explore' }); res.end(); return; }

  var meta = buildMeta(CODE_RE.test(code) ? code : '', friend && !!trip, trip);
  html = html
    .replace(/<title>[\s\S]*?<\/title>/i, '')
    .replace(/<meta\s+(?:property|name)=["'](?:og:|twitter:)[^>]*>/gi, '')
    .replace(/<meta\s+name=["'](?:description|robots)["'][^>]*>/gi, '');
  html = /<\/head>/i.test(html) ? html.replace(/<\/head>/i, meta.tags + '</head>') : meta.tags + html;

  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  // Seats left change, so keep the CDN copy short-lived; crawlers/browsers revalidate quickly.
  res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=60, stale-while-revalidate=300');
  res.end(html);
};
