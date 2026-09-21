// Mobile nav toggle and the Services mega menu. Everything else on the site
// works without JavaScript (sector lists are native <details> elements).
(function () {
  var nav = document.getElementById('site-nav');
  var navToggle = document.querySelector('[data-nav-toggle]');
  var menuBtn = document.querySelector('[data-menu-toggle]');
  var menu = document.getElementById('services-menu');

  function setMenu(open) {
    if (!menuBtn || !menu) return;
    menuBtn.setAttribute('aria-expanded', String(open));
    menu.hidden = !open;
  }

  if (navToggle && nav) {
    navToggle.addEventListener('click', function () {
      var open = !nav.classList.contains('open');
      nav.classList.toggle('open', open);
      navToggle.setAttribute('aria-expanded', String(open));
    });
  }

  if (menuBtn && menu) {
    menuBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      setMenu(menu.hidden);
    });
    document.addEventListener('click', function (e) {
      if (!menu.hidden && !menu.contains(e.target)) setMenu(false);
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') setMenu(false);
    });
  }
})();

// Open the sector accordion that a #hash link points at (e.g. /sectors/#outdoor-services).
(function () {
  function openFromHash() {
    var id = location.hash.slice(1);
    var el = id && document.getElementById(id);
    if (el && el.tagName === 'DETAILS') { el.open = true; el.scrollIntoView(); }
  }
  openFromHash();
  window.addEventListener('hashchange', openFromHash);
})();
