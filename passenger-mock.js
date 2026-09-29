/* ---------------------------------------------------------------------
   Local mock data for /p/<token> (passenger.html), matching the
   passenger_home_list / passenger_trip_get / passenger_cancel /
   passenger_request_post RPC contract (design/passenger-home-rpcs.sql).
   Loaded only when ?mock=1. In-memory only. Query params:
     state=upcoming|active|picked_up|completed|cancelled  adds a ride TODAY with that status
     state=invalid   every call answers invalid_token
     empty=1         no rides, no requests (empty state)
     fail=1          the ride list always fails (error page + retry)
     fail=once       only the first list call fails (so Try again works)
     afail=1         cancel / request-post reject (rollback + toast paths)
     nophone=1       driver has no phone (no Call / WhatsApp buttons)
     b=<booking id>  opens that booking (ids: bk-done bk-cancelled bk-up1 bk-up2 bk-up3 bk-today)
     notifs=empty|fail|failonce   notification list states
     pfail=1         profile load fails
   Phone digits appear only where an href needs them (obviously fake 555-01xx).
   TODO: delete this file once the passenger home is verified against the live RPCs.
   --------------------------------------------------------------------- */
(function (global) {
  var WINDSOR = { lat: 42.3149, lng: -83.0364, label: 'Windsor, ON, Canada' };
  var ESSEX = { lat: 42.1751, lng: -82.8185, label: 'Essex, ON, Canada' };
  var KINGSVILLE = { lat: 42.0392, lng: -82.7435, label: 'Kingsville, ON, Canada' };
  var LEAMINGTON = { lat: 42.0531, lng: -82.5998, label: 'Leamington, ON, Canada' };

  function qp(k) { try { return new URLSearchParams(location.search).get(k); } catch (e) { return null; } }
  function clone(o) { return o == null ? o : JSON.parse(JSON.stringify(o)); }
  function isoOffset(ms) { return new Date(Date.now() + ms).toISOString(); }
  function dayAt(off, hh, mm) {
    var d = new Date(); d.setHours(hh == null ? 18 : hh, mm == null ? 30 : mm, 0, 0); d.setDate(d.getDate() + off);
    return d.toISOString();
  }
  function delay(ms, fn) { return new Promise(function (resolve, reject) { setTimeout(function () { try { resolve(fn()); } catch (e) { reject(e); } }, ms); }); }
  function invalid() { return qp('state') === 'invalid'; }

  /* Ride definitions (booking id -> def). status is the passenger-facing booking status. */
  var RIDES = null, REQUESTS = null, postSeq = 0;
  function build() {
    RIDES = [
      { id: 'bk-done', trip: 'trip-done', off: -3, status: 'completed', from: WINDSOR, to: ESSEX, seats: 1, price: 10, pax: 3, picked: 3, pickup: 'Peter Street, Windsor, Ontario, Canada', dropoff: 'Essex, Ontario, Canada', stops: [] },
      { id: 'bk-cancelled', trip: 'trip-cancelled', off: -2, status: 'cancelled', from: ESSEX, to: WINDSOR, seats: 1, price: 10, pax: 2, picked: 0, pickup: 'Essex, Ontario, Canada', dropoff: 'Windsor, Ontario, Canada', stops: [] },
      { id: 'bk-up1', trip: 'trip-up1', off: 1, hh: 8, mm: 15, status: 'upcoming', from: WINDSOR, to: ESSEX, seats: 2, price: 10, pax: 3, picked: 0, pickup: '496 Askin Avenue, Windsor, Ontario N9B 2W8, Canada', dropoff: 'Essex, Ontario, Canada', note: 'Two of us, one small bag.', stops: [{ label: 'Tecumseh, Ontario, Canada', lat: 42.3117, lng: -82.8998 }] },
      { id: 'bk-up2', trip: 'trip-up2', off: 1, hh: 17, mm: 30, status: 'upcoming', from: ESSEX, to: WINDSOR, seats: 1, price: 10, pax: 2, picked: 0, pickup: 'Essex, Ontario, Canada', dropoff: 'Ottawa Street, Windsor, Ontario, Canada', stops: [] },
      { id: 'bk-up3', trip: 'trip-up3', off: 3, hh: 9, mm: 0, status: 'upcoming', from: WINDSOR, to: LEAMINGTON, seats: 1, price: null, pax: 1, picked: 0, pickup: 'Windsor, Ontario, Canada', dropoff: 'Kingsville, Ontario, Canada', stops: [{ label: KINGSVILLE.label, lat: KINGSVILLE.lat, lng: KINGSVILLE.lng }] }
    ];
    var st = qp('state');
    if (['upcoming', 'active', 'picked_up', 'completed', 'cancelled'].indexOf(st) >= 0) {
      RIDES.push({ id: 'bk-today', trip: 'trip-today', off: 0, hh: 18, mm: 30, status: st, from: WINDSOR, to: ESSEX, seats: 1, price: 10, pax: 4,
        picked: st === 'picked_up' ? 2 : (st === 'completed' ? 4 : (st === 'active' ? 1 : 0)), pickup: 'Peter Street, Windsor, Ontario, Canada', dropoff: 'Essex, Ontario, Canada', note: 'Red door, second floor.', stops: [{ label: KINGSVILLE.label, lat: KINGSVILLE.lat, lng: KINGSVILLE.lng }] });
    }
    REQUESTS = [
      { id: 'req-1', depart_at: dayAt(2, 10, 0), pickup_label: 'Windsor, Ontario, Canada', dropoff_label: 'Toronto, Ontario, Canada', pickup_lat: 42.3149, pickup_lng: -83.0364, dropoff_lat: 43.6532, dropoff_lng: -79.3832, seats: 2, status: 'pending', kind: 'request' }
    ];
    if (qp('empty') === '1') { RIDES = []; REQUESTS = []; }
  }
  function ensure() { if (!RIDES) build(); }
  function find(id) { ensure(); for (var i = 0; i < RIDES.length; i++) if (RIDES[i].id === id) return RIDES[i]; return null; }

  var listCalls = 0;
  function tripStatus(s) { return s === 'cancelled' ? 'cancelled' : (s === 'completed' ? 'completed' : (s === 'active' || s === 'picked_up' ? 'active' : 'upcoming')); }
  function pt(o, extra) { return { label: o.label, lat: o.lat, lng: o.lng }; }
  function tripPayload(r) {
    var pk = r.pickup && r.pickup.indexOf('Windsor') === 0 && r.pickup === 'Windsor, Ontario, Canada' ? WINDSOR : null;
    var pickup = pk || (r.pickup.indexOf('Essex') === 0 ? { label: r.pickup, lat: ESSEX.lat, lng: ESSEX.lng } : { label: r.pickup, lat: 42.3178, lng: -83.0310 });
    var dropoff = r.dropoff.indexOf('Essex') === 0 ? { label: r.dropoff, lat: ESSEX.lat, lng: ESSEX.lng } :
      (r.dropoff.indexOf('Kingsville') === 0 ? { label: r.dropoff, lat: KINGSVILLE.lat, lng: KINGSVILLE.lng } : { label: r.dropoff, lat: 42.3080, lng: -83.0065 });
    var picked = r.status === 'picked_up' || r.status === 'completed';
    return {
      trip: {
        id: r.trip, status: tripStatus(r.status), depart_at: dayAt(r.off, r.hh, r.mm),
        origin_label: r.from.label, origin_lat: r.from.lat, origin_lng: r.from.lng,
        dest_label: r.to.label, dest_lat: r.to.lat, dest_lng: r.to.lng,
        stops: r.stops, price_per_seat: r.price, note: null, seats_total: 6,
        join_url: 'https://pathfynder.ca/j/DEMO42',
        driver: { name: 'Rahul Sharma', photo: null, phone: qp('nophone') === '1' ? null : '15550100123' }
      },
      booking: {
        id: r.id, status: r.status, seats: r.seats,
        pickup_label: pickup.label, pickup_lat: pickup.lat, pickup_lng: pickup.lng,
        dropoff_label: dropoff.label, dropoff_lat: dropoff.lat, dropoff_lng: dropoff.lng,
        picked_up_at: picked ? isoOffset(-25 * 60e3) : null,
        dropped_off_at: r.status === 'completed' ? isoOffset(-5 * 60e3) : null, note: r.note || null
      },
      counts: { passengers: r.pax, picked_up: r.picked }
    };
  }

  /* Notifications (mock of passenger_notifications_list / _mark_read). Text is free of phone numbers. */
  var NOTIFS = null, notifCalls = 0;
  function notifMode() { return qp('notifs'); }
  function notifStore() {
    if (NOTIFS) return NOTIFS;
    if (notifMode() === 'empty') { NOTIFS = []; return NOTIFS; }
    NOTIFS = [
      { id: 1, kind: 'ride_started', title: 'Your driver started the trip', body: 'Windsor → Essex', url: '/p/mock?mock=1&b=bk-up1', age: 30e3, read: false },
      { id: 2, kind: 'picked_up', title: 'You\'re picked up', body: 'Peter Street → Essex', url: '/p/mock?mock=1&b=bk-up1', age: 5 * 60e3, read: false },
      { id: 3, kind: 'ride_completed', title: 'Your trip is complete', body: 'Essex → Ottawa Street', url: '/p/mock?mock=1&b=bk-done', age: 2 * 3600e3, read: false },
      { id: 4, kind: 'ride_cancelled', title: 'Your driver cancelled your seat', body: 'Essex → Windsor', url: '/p/mock?mock=1&b=bk-cancelled', age: 30 * 3600e3, read: true },
      { id: 5, kind: 'ride_started', title: 'Your driver started the trip', body: 'A very long notification body to check wrapping on a narrow phone screen without any overflow at all.', url: null, age: 6 * 24 * 3600e3, read: true }
    ];
    return NOTIFS;
  }

  var PROFILE = {
    name: 'Sam Taylor', photo_url: null, whatsapp_masked: '+1 ••• ••• 0111', notifications_enabled: false,
    stats: { rides_completed: 7, rides_upcoming: 3, member_since: '2026-09-01T12:00:00Z', total_spent: 96.5 }
  };

  var PLACES = [
    { name: 'Windsor', sub: 'ON', label: 'Windsor, ON, Canada', lat: 42.3149, lng: -83.0364 },
    { name: 'Essex', sub: 'ON', label: 'Essex, ON, Canada', lat: 42.1751, lng: -82.8185 },
    { name: 'Leamington', sub: 'ON', label: 'Leamington, ON, Canada', lat: 42.0531, lng: -82.5998 },
    { name: 'Toronto', sub: 'ON', label: 'Toronto, ON, Canada', lat: 43.6532, lng: -79.3832 },
    { name: 'London', sub: 'ON', label: 'London, ON, Canada', lat: 42.9849, lng: -81.2453 }
  ];

  global.PF_PASSENGER_MOCK = {
    places: function (q) {
      var n = String(q || '').toLowerCase();
      return Promise.resolve(PLACES.filter(function (p) { return p.name.toLowerCase().indexOf(n) === 0; }).map(clone));
    },
    list: function () {
      return delay(200, function () {
        ensure();
        var call = ++listCalls, f = qp('fail');
        if (f === '1' || (f === 'once' && call === 1)) throw new Error('mock list failure');
        if (invalid()) return { error: 'invalid_token' };
        return {
          rides: RIDES.map(function (r) { return { booking_id: r.id, trip_id: r.trip, depart_at: dayAt(r.off, r.hh, r.mm), status: r.status, kind: 'booking', origin_label: r.from.label, dest_label: r.to.label }; }),
          requests: clone(REQUESTS)
        };
      });
    },
    get: function (token, id) {
      return delay(300, function () {
        if (invalid()) return { error: 'invalid_token' };
        var r = find(id);
        return r ? tripPayload(r) : { error: 'not_found' };
      });
    },
    cancel: function (token, id) {
      return delay(300, function () {
        if (qp('afail') === '1') throw new Error('mock cancel failure');
        ensure();
        var q = REQUESTS.filter(function (x) { return x.id === id; })[0];
        if (q) { REQUESTS = REQUESTS.filter(function (x) { return x.id !== id; }); return { ok: true }; }
        var r = find(id);
        if (!r) return { error: 'not_found' };
        if (r.status === 'cancelled') return { ok: true };
        if (r.status !== 'upcoming') return { error: 'not_allowed' };
        r.status = 'cancelled';
        return { ok: true };
      });
    },
    /* Mirrors passenger_request_post -> { ok, ids } | { error } */
    post: function (token, f) {
      return delay(300, function () {
        if (qp('afail') === '1') throw new Error('mock post failure');
        if (invalid()) return { error: 'invalid_token' };
        ensure();
        function num(n, lim) { return typeof n === 'number' && isFinite(n) && Math.abs(n) <= lim; }
        var deps = f.departures || [], rets = f.returns || [];
        var dk = function (iso) { return new Date(iso).toDateString(); };
        var uniq = function (a) { return a.map(dk).filter(function (k, i, arr) { return arr.indexOf(k) === i; }).length === a.length; };
        var bad = !f.origin_label || !f.dest_label || !num(f.origin_lat, 90) || !num(f.dest_lat, 90) || !num(f.origin_lng, 180) || !num(f.dest_lng, 180) ||
          !(f.seats >= 1 && f.seats <= 8 && Math.floor(f.seats) === f.seats) || (f.note != null && f.note.length > 300) ||
          deps.length < 1 || deps.length > 30 || rets.length > 30 || !uniq(deps) || !uniq(rets) ||
          deps.concat(rets).some(function (iso) { return isNaN(new Date(iso).getTime()); });
        if (bad) return { error: 'invalid_input' };
        if (deps.concat(rets).some(function (iso) { return new Date(iso).getTime() < Date.now(); })) return { error: 'past_time' };
        var ids = [];
        deps.forEach(function (iso) { var id = 'req-new-' + (++postSeq); REQUESTS.push({ id: id, depart_at: new Date(iso).toISOString(), pickup_label: f.origin_label, dropoff_label: f.dest_label, seats: f.seats, status: 'pending', kind: 'request' }); ids.push(id); });
        rets.forEach(function (iso) { var id = 'req-new-' + (++postSeq); REQUESTS.push({ id: id, depart_at: new Date(iso).toISOString(), pickup_label: f.dest_label, dropoff_label: f.origin_label, seats: f.seats, status: 'pending', kind: 'request' }); ids.push(id); });
        return { ok: true, ids: ids };
      });
    },
    recent: function () {
      return delay(200, function () {
        if (invalid()) return { error: 'invalid_token' };
        return { trips: [
          { origin_label: 'Windsor, Ontario, Canada', origin_lat: 42.3149, origin_lng: -83.0364, dest_label: 'Toronto, Ontario, Canada', dest_lat: 43.6532, dest_lng: -79.3832, seats: 2, note: 'One suitcase' },
          { origin_label: 'London, Ontario, Canada', origin_lat: 42.9849, origin_lng: -81.2453, dest_label: 'Windsor, Ontario, Canada', dest_lat: 42.3149, dest_lng: -83.0364, seats: 1, note: null }
        ] };
      });
    },
    profile: function () {
      return delay(200, function () {
        if (invalid()) return { error: 'invalid_token' };
        if (qp('pfail') === '1') throw new Error('mock profile failure');
        return clone(PROFILE);
      });
    },
    updateProfile: function (token, patch) {
      return delay(200, function () {
        if (qp('afail') === '1') throw new Error('mock profile update failure');
        if (patch && patch.name != null) PROFILE.name = String(patch.name).trim();
        if (patch && patch.photo != null) PROFILE.photo_url = patch.photo;
        return { name: PROFILE.name, photo_url: PROFILE.photo_url };
      });
    },
    notifList: function () {
      return delay(200, function () {
        var call = ++notifCalls, m = notifMode();
        if (invalid()) return { error: 'invalid_token' };
        if ((m === 'fail' && call > 1) || (m === 'failonce' && call === 2)) throw new Error('mock notifications failure');
        var st = notifStore();
        return { notifications: st.map(function (n) {
          return { id: n.id, kind: n.kind, title: n.title, body: n.body, url: n.url, created_at: isoOffset(-n.age), read: n.read };
        }), unread_count: st.filter(function (n) { return !n.read; }).length };
      });
    },
    notifMarkRead: function () {
      return delay(100, function () { notifStore().forEach(function (n) { n.read = true; }); return { ok: true }; });
    }
  };
})(window);
