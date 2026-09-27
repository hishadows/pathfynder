/* Pathfynder notification toggle helper (v3: + serverStatus(); status() tolerates a missing pushManager). No dependencies — plain fetch against
   Supabase REST/rpc, same project/key explore.html uses. */
(function (window) {
  'use strict';

  var SUPABASE_URL = 'https://omussxfyrztjahbdrrpi.supabase.co';
  var SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9tdXNzeGZ5cnp0amFoYmRycnBpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0MjI1NjAsImV4cCI6MjA5NTk5ODU2MH0.ySigym7uOaFIQm01nErPfn4kE6j4MOVKoNntt_Mosak';
  var VAPID_PUBLIC_KEY = 'BA2X9v-sHMCnYlNdGbFTpMPRjIvB5kWhe11g_fEnExlftkrYrV-PmIBhHbmY07u44xrFq2Y4fB6Bp0EVk8EMwQg';

  function rpc(fn, payload) {
    return fetch(SUPABASE_URL + '/rest/v1/rpc/' + fn, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_ANON,
        'Authorization': 'Bearer ' + SUPABASE_ANON
      },
      body: JSON.stringify(payload || {})
    }).then(function (res) {
      return res.json().then(function (data) {
        if (!res.ok) {
          var msg = (data && (data.message || data.error)) || 'request_failed';
          throw new Error(msg);
        }
        return data;
      });
    });
  }

  /* ---------- sw registration ---------- */
  var swReady = null;
  function registerSW() {
    if (!('serviceWorker' in navigator)) return Promise.resolve(null);
    if (!swReady) {
      swReady = navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(function () { return null; });
    }
    return swReady;
  }

  /* ---------- state detection ---------- */
  function isIOS() {
    var ua = navigator.userAgent || '';
    var iOSDevice = /iPhone|iPad|iPod/.test(ua);
    var iPadOSMac = navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
    return iOSDevice || iPadOSMac;
  }
  function isStandalone() {
    return (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || window.navigator.standalone === true;
  }
  function iosVersion() {
    var ua = navigator.userAgent || '';
    var m = ua.match(/OS (\d+)_(\d+)/);
    if (!m) return null;
    return { major: parseInt(m[1], 10), minor: parseInt(m[2], 10) };
  }
  function isTooOldIOS() {
    var v = iosVersion();
    return !!(v && (v.major < 16 || (v.major === 16 && v.minor < 4)));
  }
  function isInAppBrowserUA() {
    var ua = navigator.userAgent || '';
    return /WhatsApp|Instagram|FBAN|FBAV|wv/.test(ua);
  }

  function state() {
    if (isIOS()) {
      if (isTooOldIOS()) return 'ios-too-old';
      if (!isStandalone()) return 'ios-needs-install';
    }
    var hasApis = ('serviceWorker' in navigator) && ('PushManager' in window) && ('Notification' in window);
    if (!hasApis) {
      return isInAppBrowserUA() ? 'in-app-browser' : 'unsupported';
    }
    if (Notification.permission === 'granted') return 'granted';
    if (Notification.permission === 'denied') return 'denied';
    return 'default';
  }

  /* ---------- subscribe helpers ---------- */
  function urlBase64ToUint8Array(base64String) {
    var padding = '='.repeat((4 - base64String.length % 4) % 4);
    var base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    var rawData = window.atob(base64);
    var outputArray = new Uint8Array(rawData.length);
    for (var i = 0; i < rawData.length; ++i) outputArray[i] = rawData.charCodeAt(i);
    return outputArray;
  }

  function enable(token) {
    return registerSW().then(function (reg) {
      if (!reg) throw new Error('no_service_worker');
      return Notification.requestPermission().then(function (perm) {
        if (perm !== 'granted') return state();
        return reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
        }).then(function (sub) {
          var json = sub.toJSON();
          return rpc('notify_subscribe', {
            p_token: token || null,
            p_endpoint: json.endpoint,
            p_p256dh: json.keys.p256dh,
            p_auth: json.keys.auth
          }).then(function () { return state(); });
        });
      });
    });
  }

  function disable(token) {
    return registerSW().then(function (reg) {
      var endpoint = null;
      var unsubP = Promise.resolve();
      if (reg) {
        unsubP = reg.pushManager.getSubscription().then(function (sub) {
          if (sub) {
            endpoint = sub.endpoint;
            return sub.unsubscribe();
          }
        }).catch(function () {});
      }
      return unsubP.then(function () {
        return rpc('notify_unsubscribe', { p_token: token || null, p_endpoint: endpoint }).catch(function () {});
      });
    });
  }

  function status(token) {
    return registerSW().then(function (reg) {
      var endpoint = null;
      var getEndpoint = (reg && reg.pushManager)
        ? reg.pushManager.getSubscription().then(function (sub) { if (sub) endpoint = sub.endpoint; }).catch(function () {})
        : Promise.resolve();
      return getEndpoint.then(function () {
        return rpc('notify_status', { p_token: token || null, p_endpoint: endpoint });
      });
    });
  }

  /* Server-only status for a token: no service worker / push lookup, so it works in
     Safari tabs and in-app browsers (v3). The server checks every active subscription
     for that person's number. */
  function serverStatus(token) {
    return rpc('notify_status', { p_token: token, p_endpoint: null });
  }

  /* ---------- token + history (v2) ---------- */
  function token() {
    return window.PF_TOKEN || null;
  }

  function history(token) {
    if (!token) return Promise.resolve([]);
    return rpc('notify_history', { p_token: token }).then(function (rows) {
      return Array.isArray(rows) ? rows : [];
    });
  }

  window.PFNotify = {
    state: state,
    enable: enable,
    disable: disable,
    status: status,
    serverStatus: serverStatus,
    token: token,
    history: history
  };
})(window);
