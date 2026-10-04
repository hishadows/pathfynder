// Short link resolver: /r/:code -> /api/r?code=:code (see vercel.json rewrite).
// Looks the code up via the public get_bot_link RPC (read-only, anon key — same
// Supabase project/key explore.html uses) and either 302s to /explore on any
// invalid/missing/unsafe result, or serves a tiny same-HTML-for-everyone page
// with the right OG tags that immediately redirects a human to the real target.

var SUPABASE_URL = 'https://omussxfyrztjahbdrrpi.supabase.co';
var SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9tdXNzeGZ5cnp0amFoYmRycnBpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0MjI1NjAsImV4cCI6MjA5NTk5ODU2MH0.ySigym7uOaFIQm01nErPfn4kE6j4MOVKoNntt_Mosak';
var FALLBACK_URL = 'https://www.pathfynder.ca/explore';
var TARGET_PREFIX = 'https://www.pathfynder.ca/';
var CODE_RE = /^[A-Za-z0-9]{8}$/;
// Same brand card explore.html and index.html use for og:image, served from the repo root.
var OG_IMAGE_URL = 'https://www.pathfynder.ca/og-brand.png';
var OG_IMAGE_TYPE = 'image/png';
var OG_IMAGE_WIDTH = 1200;
var OG_IMAGE_HEIGHT = 630;
var FOCUS_RE = /[?&]focus=pf(?::|%3A)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:[&#]|$)/i;
var TZ = 'America/Toronto';

// Same Today/Tomorrow rule as api/og.mjs, in America/Toronto.
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
  var tk = tmr.getUTCFullYear() + '-' + (tmr.getUTCMonth() + 1) + '-' + tmr.getUTCDate();
  var day = k === ymd(now) ? 'Today (' + short + ')' : (k === tk ? 'Tomorrow (' + short + ')' : short);
  return { day: day, time: time };
}
function cityOf(s) { return String(s || '').split(',')[0].trim(); }

// Open passenger request behind an explore focus link -> public facts, or null.
async function getOpenRequest(target) {
  var m = FOCUS_RE.exec(target);
  if (!m) return null;
  try {
    var ctl = new AbortController(); var t = setTimeout(function () { ctl.abort(); }, 2500);
    var r = await fetch(SUPABASE_URL + '/rest/v1/rpc/request_card_get', {
      method: 'POST', signal: ctl.signal,
      headers: { 'Content-Type': 'application/json', apikey: SUPABASE_ANON, Authorization: 'Bearer ' + SUPABASE_ANON },
      body: JSON.stringify({ p_id: m[1] }),
    });
    clearTimeout(t);
    if (!r.ok) return null;
    var d = await r.json();
    d = Array.isArray(d) ? d[0] : d;
    if (!d || typeof d !== 'object' || d.open !== true || !cityOf(d.from_label) || !cityOf(d.to_label)) return null;
    d.id = m[1];
    return d;
  } catch (e) { return null; }
}

function escHtml(s) {
  return String(s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}

function escJsString(s) {
  // Safe to drop into a JSON.stringify()'d string literal inside <script>: also
  // break up "</" so the target can never prematurely close the script tag.
  return JSON.stringify(String(s)).replace(/<\//g, '<\\/');
}

function redirect(res, location) {
  res.writeHead(302, { Location: location });
  res.end();
}

module.exports = async function handler(req, res) {
  var code = req.query && req.query.code;
  code = typeof code === 'string' ? code : '';

  if (!CODE_RE.test(code)) return redirect(res, FALLBACK_URL);

  var row;
  try {
    var r = await fetch(SUPABASE_URL + '/rest/v1/rpc/get_bot_link', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SUPABASE_ANON,
        Authorization: 'Bearer ' + SUPABASE_ANON,
      },
      body: JSON.stringify({ p_code: code }),
    });
    if (!r.ok) return redirect(res, FALLBACK_URL);
    var data = await r.json();
    row = Array.isArray(data) ? data[0] : data;
  } catch (e) {
    return redirect(res, FALLBACK_URL);
  }

  if (!row || !row.target) return redirect(res, FALLBACK_URL);

  var target = String(row.target);
  if (target.indexOf(TARGET_PREFIX) !== 0) return redirect(res, FALLBACK_URL);

  var title = row.title || 'Pathfynder';
  var description = row.description || '';
  var pageUrl = 'https://www.pathfynder.ca/r/' + code;
  var imgUrl = OG_IMAGE_URL, imgAlt = 'Pathfynder';

  var rq = await getOpenRequest(target);
  if (rq) {
    var w = whenParts(rq.depart_at);
    var n = Number(rq.seats) || 1;
    title = 'Ride request: ' + cityOf(rq.from_label) + ' \u2192 ' + cityOf(rq.to_label);
    description = (w ? w.day + ' \u00b7 ' + w.time + ' \u00b7 ' : '') + n + (n === 1 ? ' seat' : ' seats') + '. Tap to see it and offer a ride.';
    imgUrl = 'https://www.pathfynder.ca/api/og?v=request&id=' + rq.id;
    imgAlt = 'Ride request from ' + cityOf(rq.from_label) + ' to ' + cityOf(rq.to_label);
  }

  var html = '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
    '<title>' + escHtml(title) + '</title>' +
    '<meta property="og:title" content="' + escHtml(title) + '">' +
    '<meta property="og:description" content="' + escHtml(description) + '">' +
    '<meta property="og:url" content="' + escHtml(pageUrl) + '">' +
    '<meta property="og:type" content="website">' +
    '<meta property="og:site_name" content="Pathfynder">' +
    '<meta property="og:image" content="' + escHtml(imgUrl) + '">' +
    '<meta property="og:image:secure_url" content="' + escHtml(imgUrl) + '">' +
    '<meta property="og:image:type" content="' + escHtml(OG_IMAGE_TYPE) + '">' +
    '<meta property="og:image:width" content="' + OG_IMAGE_WIDTH + '">' +
    '<meta property="og:image:height" content="' + OG_IMAGE_HEIGHT + '">' +
    '<meta property="og:image:alt" content="' + escHtml(imgAlt) + '">' +
    '<meta name="twitter:card" content="summary">' +
    '</head><body>' +
    '<a href="' + escHtml(target) + '">Open on Pathfynder</a>' +
    '<script>location.replace(' + escJsString(target) + ');</script>' +
    '</body></html>';

  res.writeHead(200, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'public, s-maxage=86400',
  });
  res.end(html);
};
