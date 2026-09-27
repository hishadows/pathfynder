/* Pathfynder notifications service worker. Minimal by design — no fetch/cache handling. */
self.addEventListener('install', function (event) {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', function (event) {
  var data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) {}

  var title = data.title || 'Pathfynder';
  var options = {
    body: data.body || '',
    icon: '/icons/icon-192.png',
    badge: '/icons/icon-192.png',
    tag: data.tag || undefined,
    data: { url: data.url || '/notifications' }
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', function (event) {
  var url = (event.notification.data && event.notification.data.url) || '/notifications';
  event.notification.close();

  event.waitUntil((async function () {
    var target = new URL(url, self.location.origin);
    var clientsList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (var i = 0; i < clientsList.length; i++) {
      var c = clientsList[i];
      if (new URL(c.url).origin === target.origin) {
        await c.focus();
        if ('navigate' in c) { try { await c.navigate(target.href); } catch (e) {} }
        return;
      }
    }
    await self.clients.openWindow(target.href);
  })());
});
