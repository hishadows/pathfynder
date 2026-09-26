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
// Same logo explore.html already uses for og:image, served from the repo root.
var OG_IMAGE_URL = 'https://www.pathfynder.ca/logo.png';
var OG_IMAGE_TYPE = 'image/png';
var OG_IMAGE_WIDTH = 301;
var OG_IMAGE_HEIGHT = 303;

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

  var html = '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
    '<title>' + escHtml(title) + '</title>' +
    '<meta property="og:title" content="' + escHtml(title) + '">' +
    '<meta property="og:description" content="' + escHtml(description) + '">' +
    '<meta property="og:url" content="' + escHtml(pageUrl) + '">' +
    '<meta property="og:type" content="website">' +
    '<meta property="og:site_name" content="Pathfynder">' +
    '<meta property="og:image" content="' + escHtml(OG_IMAGE_URL) + '">' +
    '<meta property="og:image:secure_url" content="' + escHtml(OG_IMAGE_URL) + '">' +
    '<meta property="og:image:type" content="' + escHtml(OG_IMAGE_TYPE) + '">' +
    '<meta property="og:image:width" content="' + OG_IMAGE_WIDTH + '">' +
    '<meta property="og:image:height" content="' + OG_IMAGE_HEIGHT + '">' +
    '<meta property="og:image:alt" content="Pathfynder">' +
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
