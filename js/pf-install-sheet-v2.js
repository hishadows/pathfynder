/* Pathfynder "Add to Home Screen" sheet (v2: + openLink() "Last step: link WhatsApp" sheet). iPhone only: iOS Safari can't
   receive push until the site is opened from the Home Screen. Self-contained
   (own CSS + DOM, WhatsApp light/dark palette), no dependencies.
   window.PFInstall.needed() -> true on iOS 16.4+ outside the Home Screen app
   window.PFInstall.open()   -> shows the sheet
   window.PFInstall.openLink(code, onClose) -> "Last step" sheet: send ALERTS <code> to the bot */
(function (window, document) {
  'use strict';

  var CSS =
    ':root{--pfi-card:#FFFFFF;--pfi-text:#111B21;--pfi-text-2:#667781;--pfi-divider:#E9EDEF;--pfi-soft:#D9FDD3;--pfi-soft-ink:#006D5B;' +
      '--pfi-key:#F0F2F5;--pfi-key-line:#D1D7DB;--pfi-cta:#25D366;--pfi-cta-hover:#1EBE5A;--pfi-cta-text:#111B21;--pfi-overlay:rgba(11,20,26,.45);--pfi-grab:#D1D7DB;' +
      '--pfi-hero:linear-gradient(160deg,#D9FDD3 0%,#E7F8F2 55%,#F0F2F5 100%);--pfi-tip:#FFF6E0;--pfi-tip-ink:#6B5518}' +
    '@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--pfi-card:#202C33;--pfi-text:#E9EDEF;--pfi-text-2:#8696A0;--pfi-divider:#2A3942;--pfi-soft:#0A332C;--pfi-soft-ink:#25D366;' +
      '--pfi-key:#111B21;--pfi-key-line:#3B4A54;--pfi-cta:#00A884;--pfi-cta-hover:#06CF9C;--pfi-cta-text:#111B21;--pfi-overlay:rgba(0,0,0,.62);--pfi-grab:#3B4A54;' +
      '--pfi-hero:linear-gradient(160deg,#0A332C 0%,#15302D 55%,#202C33 100%);--pfi-tip:#182229;--pfi-tip-ink:#FFD279}}' +
    ':root[data-theme="dark"]{--pfi-card:#202C33;--pfi-text:#E9EDEF;--pfi-text-2:#8696A0;--pfi-divider:#2A3942;--pfi-soft:#0A332C;--pfi-soft-ink:#25D366;' +
      '--pfi-key:#111B21;--pfi-key-line:#3B4A54;--pfi-cta:#00A884;--pfi-cta-hover:#06CF9C;--pfi-cta-text:#111B21;--pfi-overlay:rgba(0,0,0,.62);--pfi-grab:#3B4A54;' +
      '--pfi-hero:linear-gradient(160deg,#0A332C 0%,#15302D 55%,#202C33 100%);--pfi-tip:#182229;--pfi-tip-ink:#FFD279}' +
    '.pfi-layer{position:fixed;inset:0;z-index:60;display:flex;flex-direction:column;justify-content:flex-end;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}' +
    '.pfi-backdrop{position:absolute;inset:0;background:var(--pfi-overlay);opacity:0;transition:opacity .22s ease}' +
    '.pfi-layer.is-in .pfi-backdrop{opacity:1}' +
    '.pfi-sheet{position:relative;width:100%;max-width:720px;margin:0 auto;max-height:92vh;overflow-y:auto;overscroll-behavior:contain;background:var(--pfi-card);color:var(--pfi-text);' +
      'border-radius:20px 20px 0 0;padding:0 20px calc(18px + env(safe-area-inset-bottom));box-shadow:0 -8px 30px rgba(11,20,26,.18);transform:translateY(100%);transition:transform .28s cubic-bezier(.2,.8,.2,1);outline:none}' +
    '.pfi-layer.is-in .pfi-sheet{transform:translateY(0)}' +
    '.pfi-sheet.is-dragging{transition:none}' +
    '.pfi-grab{width:36px;height:4px;margin:8px auto 0;border-radius:2px;background:var(--pfi-grab)}' +
    '.pfi-x{position:absolute;top:10px;right:10px;width:40px;height:40px;border:0;border-radius:50%;background:transparent;color:var(--pfi-text-2);display:grid;place-items:center;cursor:pointer}' +
    '.pfi-x:hover{background:var(--pfi-key)}' +
    '.pfi-hero{margin:14px 0 18px;padding:22px 0 20px;border-radius:16px;background:var(--pfi-hero);display:flex;justify-content:center}' +
    '.pfi-app{position:relative;width:68px;height:68px}' +
    '.pfi-app img{width:68px;height:68px;border-radius:16px;display:block;box-shadow:0 6px 18px rgba(0,80,65,.22);background:#fff}' +
    '.pfi-bell{position:absolute;right:-10px;bottom:-8px;width:32px;height:32px;border-radius:50%;background:var(--pfi-cta);color:#fff;display:grid;place-items:center;border:3px solid var(--pfi-card);animation:pfi-ring 2.4s ease-in-out .5s infinite}' +
    '@keyframes pfi-ring{0%,60%,100%{transform:rotate(0)}8%{transform:rotate(16deg)}16%{transform:rotate(-14deg)}24%{transform:rotate(10deg)}32%{transform:rotate(-6deg)}40%{transform:rotate(0)}}' +
    '@media (prefers-reduced-motion: reduce){.pfi-bell{animation:none}.pfi-sheet,.pfi-backdrop{transition:none}}' +
    '.pfi-title{margin:0;font-size:21px;font-weight:700;line-height:1.25;text-align:center;letter-spacing:-.01em}' +
    '.pfi-sub{margin:8px auto 18px;max-width:340px;font-size:14.5px;line-height:1.45;color:var(--pfi-text-2);text-align:center}' +
    '.pfi-steps{list-style:none;margin:0;padding:0;border-top:1px solid var(--pfi-divider)}' +
    '.pfi-steps li{display:flex;align-items:flex-start;gap:12px;padding:13px 0;border-bottom:1px solid var(--pfi-divider);font-size:15px;line-height:1.5}' +
    '.pfi-num{flex:none;width:26px;height:26px;margin-top:-1px;border-radius:50%;background:var(--pfi-soft);color:var(--pfi-soft-ink);font-size:13px;font-weight:700;display:grid;place-items:center}' +
    '.pfi-step small{display:block;margin-top:2px;font-size:13px;color:var(--pfi-text-2)}' +
    '.pfi-key{display:inline-flex;align-items:center;gap:5px;padding:1px 8px 1px 6px;margin:0 1px;border:1px solid var(--pfi-key-line);border-radius:7px;background:var(--pfi-key);font-size:13.5px;font-weight:600;white-space:nowrap;vertical-align:1px}' +
    '.pfi-key svg{width:15px;height:15px;color:#0A84FF}' +
    '.pfi-tip{display:flex;gap:10px;margin:14px 0 0;padding:10px 12px;border-radius:10px;background:var(--pfi-tip);color:var(--pfi-tip-ink);font-size:13px;line-height:1.45}' +
    '.pfi-tip svg{flex:none;width:18px;height:18px;margin-top:1px}' +
    '.pfi-cta{display:block;width:100%;margin:16px 0 0;height:48px;border:0;border-radius:24px;background:var(--pfi-cta);color:var(--pfi-cta-text);font-size:16px;font-weight:600;cursor:pointer}' +
    '.pfi-cta:hover{background:var(--pfi-cta-hover)}' +
    'a.pfi-cta{display:flex;align-items:center;justify-content:center;gap:8px;text-decoration:none;box-sizing:border-box}' +
    'a.pfi-cta svg{width:20px;height:20px}' +
    '.pfi-ghost{display:block;width:100%;margin:8px 0 0;height:44px;border:0;border-radius:22px;background:transparent;color:var(--pfi-soft-ink);font-size:15px;font-weight:600;cursor:pointer}' +
    '.pfi-code{display:block;margin:0 auto;width:max-content;padding:10px 18px;border:1px dashed var(--pfi-key-line);border-radius:12px;background:var(--pfi-key);font:600 17px/1.2 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.08em}' +
    '.pfi-lock{overflow:hidden}';

  function svg(paths, extra) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="' + (extra || '2') + '" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + paths + '</svg>';
  }
  var I_SHARE = svg('<path d="M12 3v12"/><path d="M8 7l4-4 4 4"/><path d="M8 11H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-8a1 1 0 0 0-1-1h-2"/>');
  var I_MORE = svg('<circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/>', '2.4');
  var I_ADD = svg('<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M12 8v8M8 12h8"/>');
  var I_BELL = svg('<path d="M10 5a2 2 0 1 1 4 0a7 7 0 0 1 4 6v3a4 4 0 0 0 2 3H4a4 4 0 0 0 2-3v-3a7 7 0 0 1 4-6"/><path d="M9 17v1a3 3 0 0 0 6 0v-1"/>');
  var I_X = svg('<path d="M18 6L6 18M6 6l12 12"/>');
  var I_WA = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2zm0 18.2c-1.5 0-3-.4-4.2-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8-.2-.1-.4-.1-.6.1l-.8 1c-.1.2-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.2-.4.2-.4.7-1.3.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2 5.2 5.2 0 0 0 1.1 2.8 12 12 0 0 0 4.6 4c1.7.7 2.4.8 3.2.7.5-.1 1.5-.6 1.8-1.2.2-.6.2-1.1.1-1.2l-.5-.3z"/></svg>';
  var I_INFO = svg('<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>');

  function linkHtml(code) {
    var href = window.PFNotify && window.PFNotify.waLinkUrl ? window.PFNotify.waLinkUrl(code) : '#';
    return '<div class="pfi-backdrop" data-pfi-close></div>' +
      '<div class="pfi-sheet" role="dialog" aria-modal="true" aria-labelledby="pfiTitle" tabindex="-1">' +
        '<div class="pfi-grab"></div>' +
        '<button type="button" class="pfi-x" data-pfi-close aria-label="Close">' + I_X + '</button>' +
        '<div class="pfi-hero"><div class="pfi-app"><img src="/icons/apple-touch-icon-180.png" alt="" width="68" height="68"><span class="pfi-bell">' + I_BELL + '</span></div></div>' +
        '<h2 class="pfi-title" id="pfiTitle">Last step: link your WhatsApp</h2>' +
        '<p class="pfi-sub">Notifications are on for this phone. Send one message to our WhatsApp so we know which rides to ping you about.</p>' +
        '<span class="pfi-code" aria-label="Your code">ALERTS ' + esc(code) + '</span>' +
        '<a class="pfi-cta" href="' + esc(href) + '" target="_blank" rel="noopener" data-pfi-sent>' + I_WA + 'Link on WhatsApp</a>' +
        '<p class="pfi-tip">' + I_INFO + '<span>Then post your ride on WhatsApp — we’ll ping you here when a match comes in. The code works for 24 hours.</span></p>' +
        '<button type="button" class="pfi-ghost" data-pfi-close>Later</button>' +
      '</div>';
  }

  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function html() {
    return '<div class="pfi-backdrop" data-pfi-close></div>' +
      '<div class="pfi-sheet" role="dialog" aria-modal="true" aria-labelledby="pfiTitle" tabindex="-1">' +
        '<div class="pfi-grab"></div>' +
        '<button type="button" class="pfi-x" data-pfi-close aria-label="Close">' + I_X + '</button>' +
        '<div class="pfi-hero"><div class="pfi-app"><img src="/icons/apple-touch-icon-180.png" alt="" width="68" height="68"><span class="pfi-bell">' + I_BELL + '</span></div></div>' +
        '<h2 class="pfi-title" id="pfiTitle">Add Pathfynder to your Home Screen</h2>' +
        '<p class="pfi-sub">On iPhone, notifications only work when Pathfynder is opened from your Home Screen. It takes 10 seconds.</p>' +
        '<ol class="pfi-steps">' +
          '<li><span class="pfi-num">1</span><span class="pfi-step">Tap <span class="pfi-key">' + I_SHARE + 'Share</span> in Safari<small>Don’t see it? Tap <span class="pfi-key">' + I_MORE + '</span> first.</small></span></li>' +
          '<li><span class="pfi-num">2</span><span class="pfi-step">Scroll down, tap <span class="pfi-key">' + I_ADD + 'Add to Home Screen</span></span></li>' +
          '<li><span class="pfi-num">3</span><span class="pfi-step">Tap <b>Add</b>, then open <b>Pathfynder</b> from your Home Screen</span></li>' +
          '<li><span class="pfi-num">4</span><span class="pfi-step">Tap <span class="pfi-key">' + I_BELL + 'Turn on notifications</span> there</span></li>' +
        '</ol>' +
        '<p class="pfi-tip">' + I_INFO + '<span>Opened this link inside WhatsApp? Open it in Safari first, then follow the steps.</span></p>' +
        '<button type="button" class="pfi-cta" data-pfi-close>Got it</button>' +
      '</div>';
  }

  var layer = null, lastFocus = null, onCloseCb = null;

  function injectCss() {
    if (document.getElementById('pfiCss')) return;
    var s = document.createElement('style');
    s.id = 'pfiCss';
    s.textContent = CSS;
    document.head.appendChild(s);
  }

  function close() {
    if (!layer) return;
    var l = layer;
    layer = null;
    l.classList.remove('is-in');
    document.documentElement.classList.remove('pfi-lock');
    document.removeEventListener('keydown', onKey);
    setTimeout(function () { if (l.parentNode) l.parentNode.removeChild(l); }, 280);
    if (lastFocus && lastFocus.focus) { try { lastFocus.focus(); } catch (e) {} }
    var cb = onCloseCb; onCloseCb = null;
    if (cb) { try { cb(); } catch (e) {} }
  }

  function onKey(e) { if (e.key === 'Escape') close(); }

  function bindDrag(sheet) {
    var y0 = null, dy = 0;
    sheet.addEventListener('touchstart', function (e) {
      if (sheet.scrollTop > 0 || e.touches.length !== 1) { y0 = null; return; }
      y0 = e.touches[0].clientY; dy = 0;
    }, { passive: true });
    sheet.addEventListener('touchmove', function (e) {
      if (y0 === null) return;
      dy = e.touches[0].clientY - y0;
      if (dy <= 0) { sheet.style.transform = ''; sheet.classList.remove('is-dragging'); return; }
      sheet.classList.add('is-dragging');
      sheet.style.transform = 'translateY(' + dy + 'px)';
    }, { passive: true });
    sheet.addEventListener('touchend', function () {
      if (y0 === null) return;
      y0 = null;
      sheet.classList.remove('is-dragging');
      sheet.style.transform = '';
      if (dy > 90) close();
    });
  }

  function open(content) {
    if (layer) return;
    injectCss();
    lastFocus = document.activeElement;
    layer = document.createElement('div');
    layer.className = 'pfi-layer';
    layer.innerHTML = typeof content === 'string' ? content : html();
    layer.addEventListener('click', function (e) {
      if (e.target.closest('[data-pfi-close]')) close();
      /* Link tapped: WhatsApp opens; close so the page re-checks when they come back */
      else if (e.target.closest('[data-pfi-sent]')) setTimeout(close, 300);
    });
    document.body.appendChild(layer);
    document.documentElement.classList.add('pfi-lock');
    document.addEventListener('keydown', onKey);
    var sheet = layer.querySelector('.pfi-sheet');
    bindDrag(sheet);
    void layer.offsetWidth; // start the slide-up transition from the off-screen position
    layer.classList.add('is-in');
    try { sheet.focus({ preventScroll: true }); } catch (e) { sheet.focus(); }
  }

  function needed() {
    return !!(window.PFNotify && window.PFNotify.state() === 'ios-needs-install');
  }

  function openLink(code, onClose) {
    if (!code || layer) return;
    onCloseCb = onClose || null;
    open(linkHtml(code));
  }

  window.PFInstall = { needed: needed, open: function () { open(); }, openLink: openLink, close: close };
})(window, document);
