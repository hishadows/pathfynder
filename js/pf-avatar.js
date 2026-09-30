/* Pathfynder shared DiceBear avatar helper.
   Seed = non-secret user id ONLY. Never pass a name, phone, email or any token (manage/passenger/join/share token). */
(function () {
  var AVATAR_STYLE = "lorelei";
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function avatarUrl(userId) {
    return 'https://api.dicebear.com/9.x/' + AVATAR_STYLE + '/svg?seed=' + encodeURIComponent(userId) + '&backgroundColor=ffffff';
  }
  /* Returns an <img> HTML string, or just the escaped letter when userId is empty (no image request).
     size = px of the existing avatar circle; fbText = the existing letter(s) shown today. */
  function pfAvatarHtml(userId, size, fbText) {
    var id = userId == null ? '' : String(userId).trim();
    if (!id) return esc(fbText);
    var n = Number(size) || 40;
    return '<img class="pf-dice" src="' + esc(avatarUrl(id)) + '" width="' + n + '" height="' + n +
      '" loading="lazy" alt="Profile avatar" data-fb="' + esc(fbText) + '">';
  }
  window.PF_AVATAR_STYLE = AVATAR_STYLE;
  window.pfAvatarHtml = pfAvatarHtml;
  /* On load failure, swap the image for the existing letter inside the same container. */
  document.addEventListener('error', function (e) {
    var t = e.target;
    if (!t || t.tagName !== 'IMG' || !t.classList || !t.classList.contains('pf-dice')) return;
    t.replaceWith(document.createTextNode(t.getAttribute('data-fb') || ''));
  }, true);
  var st = document.createElement('style');
  st.textContent = 'img.pf-dice{width:100%;height:100%;border-radius:50%;object-fit:cover;display:block}';
  document.head.appendChild(st);
})();
