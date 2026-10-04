/* ---------------------------------------------------------------------
   Local mock data for /explore, matching the explore_search RPC row
   shape exactly (see CLAUDE.md "Search RPC"). Used ONLY as a fallback
   when the RPC is missing (42883 / "does not exist") so the page can
   be built and demoed before explore_search ships.
   TODO: delete this file once explore_search is live in all envs.
   --------------------------------------------------------------------- */
(function (global) {
  var G = function (name, posted_at) { return { name: name, posted_at: posted_at }; };

  var ROWS = [
    { id: 'gurpreet', source: 'whatsapp', role: 'driver', parsed: true, display_name: 'Gurpreet S.',
      origin_label: 'Mississauga, ON', dest_label: 'Niagara Falls, ON', ride_date: '2026-09-26', ride_time: '18:00',
      arrive_time: '19:30', seats: 3, price: 25, luggage: 'Medium bag OK', match_type: 'direct',
      groups: [G('GTA ↔ Niagara Rideshare', '2026-09-26T05:40'), G('Niagara Local Rides', '2026-09-26T05:41'), G('Brampton–Mississauga Rides', '2026-09-26T05:44')],
      posted_at: '2026-09-26T05:40', raw_text: 'Driving Square One → Niagara Falls today 6pm 🚗\n3 seats, $25 each. Medium bag ok 👍' },
    { id: 'daniel', source: 'poparide', role: 'driver', parsed: true, display_name: 'Daniel R.',
      origin_label: 'Mississauga, ON', dest_label: 'Niagara Falls, ON', ride_date: '2026-09-26', ride_time: '14:30',
      arrive_time: '16:00', seats: 2, price: 22, rating: 4.9, rating_count: 38, verified: true, luggage: 'No luggage',
      posted_at: '2026-09-25T20:10', match_type: 'direct' },
    { id: 'omar', source: 'poparide', role: 'driver', parsed: true, display_name: 'Omar K.',
      origin_label: 'Toronto, ON', dest_label: 'Niagara Falls, ON', ride_date: '2026-09-26', ride_time: '22:15',
      arrive_time: '00:00', seats: 4, price: 26, rating: 5.0, rating_count: 11, verified: true, luggage: 'Medium bag OK',
      posted_at: '2026-09-25T18:00', match_type: 'along_route', pickup_km: 9.5, dropoff_km: 0,
      route_km: 130, pickup_pct: 24, dropoff_pct: 100,
      description: 'Heading home to the Falls after work every Saturday. Pickup at Yorkdale Mall or Scarborough Town Centre. I can also grab you along the QEW if it\'s on the way, just message me first. Drop-offs anywhere in Niagara Falls, Clifton Hill area preferred. A medium bag fits in the trunk. Please be on time, I leave 5 minutes after the pickup time. Quiet ride, no smoking.' },
    { id: 'nxshuttle', source: 'whatsapp', role: 'driver', parsed: true, is_business: true, display_name: 'Niagara Express Shuttle',
      origin_label: 'Mississauga, ON', dest_label: 'Niagara Falls, ON', ride_date: '2026-09-26', ride_time: '10:00',
      arrive_time: '11:45', seats: 8, price: 39, recurring_label: 'Daily', luggage: 'Large bags OK', match_type: 'direct',
      groups: [G('GTA ↔ Niagara Rideshare', '2026-09-26T04:00')], posted_at: '2026-09-26T04:00',
      raw_text: '🚐 NIAGARA EXPRESS SHUTTLE 🚐\nDaily Mississauga ⇄ Niagara Falls. Door-to-door. $39/seat. Book now!' },

    { id: 'jaspreet', source: 'whatsapp', role: 'driver', parsed: true, display_name: 'Jaspreet S.',
      origin_label: 'Welland, ON', dest_label: 'Niagara Falls, ON', ride_date: '2026-09-26', ride_time: '08:00',
      match_type: 'direct', groups: [G('Niagara Local Rides', '2026-09-25T21:30'), G('Welland ↔ Niagara Carpool', '2026-09-25T21:32')],
      posted_at: '2026-09-25T21:30', raw_text: 'Going Welland to Niagara Falls Sat 8am, leaving from Seaway Mall. Can take people 🚗' },
    { id: 'navdeep', source: 'whatsapp', role: 'driver', parsed: true, display_name: 'Navdeep G.',
      origin_label: 'Port Colborne, ON', dest_label: 'Niagara Falls, ON', ride_date: '2026-09-26', ride_time: '09:30',
      arrive_time: '10:15', seats: 2, price: 10, recurring_label: 'Daily', match_type: 'along_route', pickup_km: 3.1, dropoff_km: 0,
      groups: [G('Welland ↔ Niagara Carpool', '2026-09-25T19:00')], posted_at: '2026-09-25T19:00',
      raw_text: 'Daily Port Colborne → Niagara Falls 9:30am via Welland. 2 seats $10' },
    { id: 'sam', source: 'facebook', role: 'driver', parsed: true, display_name: 'Sam T.',
      origin_label: 'Welland, ON', dest_label: 'Niagara Falls, ON', ride_date: '2026-09-26', ride_time: '08:30',
      arrive_time: '09:00', seats: 2, price: 8, match_type: 'direct',
      groups: [G('Niagara Region Rideshare', '2026-09-25T20:15')], posted_at: '2026-09-25T20:15',
      raw_text: 'Driving Welland → Niagara Falls Saturday 8:30am, back around 5. 2 seats, $8. Can pick up near Niagara College 🚙' },
    { id: 'fbwelland', source: 'facebook', role: 'driver', parsed: false, display_name: 'Brandon', posted_at: '2026-09-26T06:00',
      raw_text: 'anyone need a lift to the falls from my area tmrw morning? got room for 2, just chip in for gas' },

    { id: 'sukh', source: 'whatsapp', role: 'driver', parsed: true, display_name: 'Sukh B.',
      origin_label: 'Toronto, ON', dest_label: 'St. Catharines, ON', ride_date: '2026-09-27', ride_time: '09:00',
      arrive_time: '10:30', seats: 3, price: 20, match_type: 'along_route', pickup_km: 1.5, dropoff_km: 16,
      groups: [G('GTA ↔ Niagara Rideshare', '2026-09-26T06:20')], posted_at: '2026-09-26T06:20',
      raw_text: 'Toronto → St Catharines Sunday 9am, 3 spots $20' },
    { id: 'amrit', source: 'poparide', role: 'driver', parsed: true, display_name: 'Amrit T.',
      origin_label: 'Burlington, ON', dest_label: 'Niagara-on-the-Lake, ON', ride_date: '2026-09-27', ride_time: '16:00',
      arrive_time: '17:10', seats: 2, price: 18, rating: 4.8, rating_count: 27, verified: true, luggage: 'Small bag OK',
      posted_at: '2026-09-25T15:00', match_type: 'along_route', pickup_km: 12, dropoff_km: 14 },

    { id: 'mehak', source: 'whatsapp', role: 'passenger', parsed: true, display_name: 'Mehak S.', is_urgent: true,
      origin_label: 'St. Catharines, ON', dest_label: 'Welland, ON', ride_date: '2026-09-26', ride_time: '08:30', seats: 1,
      match_type: 'direct', groups: [G('Niagara Local Rides', '2026-09-26T06:25')], posted_at: '2026-09-26T06:25',
      raw_text: 'Need ride St Catharines → Welland (Niagara College) 8:30 today, 1 person' },
    { id: 'tom', source: 'poparide', role: 'passenger', parsed: true, display_name: 'Tom W.', is_daily: true, recurring_label: 'Daily',
      origin_label: 'St. Catharines, ON', dest_label: 'Welland, ON', ride_date: '2026-09-26', ride_time: '17:00', seats: 2,
      posted_at: '2026-09-25T21:00', match_type: 'direct' },
    { id: 'harleen', source: 'whatsapp', role: 'passenger', parsed: true, display_name: 'Harleen K.', is_regular: true,
      origin_label: 'St. Catharines, ON', dest_label: 'Niagara Falls, ON', ride_date: '2026-09-26', ride_time: '19:00', seats: 1,
      match_type: 'along_route', dropoff_km: 9, groups: [G('Niagara Local Rides', '2026-09-26T05:05')], posted_at: '2026-09-26T05:05',
      raw_text: 'Need ride StC → Niagara Falls 7pm today. 1 person 🙏' },
    { id: 'raj', source: 'whatsapp', role: 'passenger', parsed: true, display_name: 'Raj P.', is_coordinator: true,
      origin_label: 'Niagara Falls, ON', dest_label: 'Welland, ON', ride_date: '2026-09-26', ride_time: '16:00', seats: 3,
      match_type: 'along_route', pickup_km: 8, groups: [G('Niagara Local Rides', '2026-09-26T03:10'), G('Welland ↔ Niagara Carpool', '2026-09-26T03:12')],
      posted_at: '2026-09-26T03:10', raw_text: '3 people need ride Niagara Falls → Welland 4pm today. Message me for details' },
    { id: 'dots', source: 'whatsapp', role: 'passenger', parsed: true, display_name: '.....', is_airport: true,
      origin_label: 'Niagara Falls, ON', dest_label: 'Toronto Pearson Airport, ON', ride_date: '2026-09-26', ride_time: '05:00', seats: 1,
      match_type: 'along_route', pickup_km: 4, groups: [G('Niagara Local Rides', '2026-09-26T02:00')],
      posted_at: '2026-09-26T02:00', raw_text: 'Need ride to Pearson early flight tmrw 5am, 1 person, can pay extra for early pickup 🙏' },
  ];

  function norm(s) { return String(s || '').toLowerCase(); }

  function mockSearch(params) {
    var mode = params.p_mode === 'passengers' ? 'passenger' : 'driver';
    var filters = params.p_filters || {};
    var sources = filters.sources || ['whatsapp', 'poparide'];
    var fromName = norm(filters.from_name || '');
    var toName = norm(filters.to_name || '');
    var date = params.p_date || null;

    var rows = ROWS.filter(function (r) {
      if (r.role !== mode) return false;
      if (r.source !== 'facebook' && sources.indexOf(r.source) === -1) return false;
      if (r.source === 'facebook' && sources.indexOf('facebook') === -1) return false;
      if (fromName && !norm(r.origin_label).includes(fromName)) return false;
      if (toName && !norm(r.dest_label).includes(toName)) return false;
      if (date && r.ride_date && r.ride_date !== date) return false;
      if (filters.match === 'direct' && r.match_type !== 'direct') return false;
      if (filters.verified_only && !r.verified) return false;
      if (filters.hide_business && r.is_business) return false;
      if (filters.luggage_ok && (!r.luggage || r.luggage === 'No luggage')) return false;
      return true;
    });

    // rank: parsed first, business last, direct before along_route
    rows.sort(function (a, b) {
      if (!!a.parsed !== !!b.parsed) return a.parsed ? -1 : 1;
      if (!!a.is_business !== !!b.is_business) return a.is_business ? 1 : -1;
      var at = a.match_type === 'direct' ? 0 : 1, bt = b.match_type === 'direct' ? 0 : 1;
      if (at !== bt) return at - bt;
      return 0;
    });
    return rows;
  }

  /* contact_link_start fallback (RPC missing): fake code so the create-profile sheet can be demoed */
  function mockLinkStart(role) { return Promise.resolve(role === 'driver' ? 'MOCKD4' : 'MOCKP7'); }

  global.EXPLORE_MOCK = { search: mockSearch, rows: ROWS, linkStart: mockLinkStart };
})(window);
