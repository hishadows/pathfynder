// Dynamic PWA manifest: /api/manifest?t=<token>. Same as manifest.webmanifest, but
// start_url carries the personal notify token so the Home Screen icon opens
// Explore with it. Invalid/missing t -> plain /explore.

var UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ?app=driver|passenger&t=<manage token>: the driver (/m) / passenger (/p) home as its own
// installed app, scope '/' so the header Explore link stays inside it. Bad token -> Explore manifest.
var TOKEN_RE = /^[A-Za-z0-9_-]{16,64}$/;
var APPS = {
  driver: { name: 'Pathfynder Driver', id: '/m', path: '/m/', theme: '#008069', bg: '#F0F2F5' },
  passenger: { name: 'Pathfynder Passenger', id: '/p', path: '/p/', theme: '#0E6F73', bg: '#EDF6F6' }
};

module.exports = async function handler(req, res) {
  var t = req.query && req.query.t;
  t = typeof t === 'string' ? t : '';
  var appKey = req.query && req.query.app;
  var app = (appKey === 'driver' || appKey === 'passenger') && TOKEN_RE.test(t) ? APPS[appKey] : null;

  var manifest = app ? {
    name: app.name,
    short_name: 'Pathfynder',
    id: app.id,
    start_url: app.path + t,
    scope: '/',
    display: 'standalone',
    theme_color: app.theme,
    background_color: app.bg,
    icons: [
      { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png' },
      { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png' },
      { src: '/icons/icon-512-maskable.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' }
    ]
  } : {
    name: 'Pathfynder',
    short_name: 'Pathfynder',
    id: '/explore',
    start_url: UUID_RE.test(t) ? '/explore?t=' + t.toLowerCase() : '/explore',
    scope: '/',
    display: 'standalone',
    theme_color: '#008069',
    background_color: '#F0F2F5',
    icons: [
      { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png' },
      { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png' },
      { src: '/icons/icon-512-maskable.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' }
    ]
  };

  res.writeHead(200, {
    'Content-Type': 'application/manifest+json',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(manifest));
};
