// Dynamic PWA manifest: /api/manifest?t=<token>. Same as manifest.webmanifest, but
// start_url carries the personal notify token so the Home Screen icon opens
// Explore with it. Invalid/missing t -> plain /explore.

var UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

module.exports = async function handler(req, res) {
  var t = req.query && req.query.t;
  t = typeof t === 'string' ? t : '';

  var manifest = {
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
