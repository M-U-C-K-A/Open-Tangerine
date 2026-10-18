'use strict';
(() => {
  if (location.hostname !== 'sintaxerrorpvtltd.github.io' || !location.pathname.startsWith('/Open-Tangerine/')) return;
  const storageKey = 'open-tangerine-analytics';
  const lifetime = 180 * 24 * 60 * 60 * 1000;
  const privacySignal = navigator.doNotTrack === '1' || navigator.globalPrivacyControl === true;
  let preference = null;
  try { preference = JSON.parse(localStorage.getItem(storageKey)); } catch {}
  if (!preference || preference.expires <= Date.now() || !['allow', 'deny'].includes(preference.choice)) preference = null;
  let session = null;
  function sessionID() {
    try { session = JSON.parse(sessionStorage.getItem(storageKey)); } catch {}
    if (!session || session.expires <= Date.now()) session = {id: crypto.randomUUID()};
    session.expires = Date.now() + 30 * 60 * 1000;
    try { sessionStorage.setItem(storageKey, JSON.stringify(session)); } catch {}
    return session.id;
  }
  function save(choice) {
    preference = {choice, expires: Date.now() + lifetime, id: choice === 'allow' ? crypto.randomUUID() : null};
    try { localStorage.setItem(storageKey, JSON.stringify(preference)); } catch {}
    if (choice === 'deny') {
      session = null;
      try { sessionStorage.removeItem(storageKey); } catch {}
    }
  }
  function capture(event, extra = {}) {
    if (privacySignal || preference?.choice !== 'allow') return;
    let referrer = '';
    try { referrer = new URL(document.referrer).hostname; } catch {}
    const properties = {
      app: 'open-tangerine', $process_person_profile: false,
      $current_url: location.origin + location.pathname,
      $host: location.hostname, $pathname: location.pathname,
      $referring_domain: referrer || '$direct', $referrer: referrer ? `https://${referrer}/` : '',
      $session_id: sessionID(), ...extra
    };
    const query = new URLSearchParams(location.search);
    for (const name of ['utm_source', 'utm_medium', 'utm_campaign']) {
      const value = query.get(name);
      if (value && /^[a-zA-Z0-9_-]{1,80}$/.test(value)) properties[name] = value;
    }
    // Only explicit aggregate events; no SDK, replay, form text, files, or full query strings.
    fetch('https://us.i.posthog.com/i/v0/e/', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      credentials: 'omit', keepalive: true, referrerPolicy: 'no-referrer',
      body: JSON.stringify({
        api_key: 'phc_t3FQu3jrJmqd4tTmmdf7EUw6WVZFoboQmHKVGnfyMgMP',
        distinct_id: preference.id, event, properties
      })
    }).catch(() => {});
  }
  const banner = document.createElement('section');
  banner.className = 'analytics-choice';
  banner.setAttribute('aria-label', 'Optional website analytics');
  banner.innerHTML = '<p><b>Help improve Open Tangerine?</b> Allow optional visit and download-click analytics, including referral source and approximate location. No files or recordings. <a href="privacy.html">Privacy</a></p><div><button type="button" data-choice="allow">Allow analytics</button><button type="button" data-choice="deny">No thanks</button></div>';
  banner.hidden = privacySignal || preference !== null;
  banner.addEventListener('click', event => {
    const choice = event.target.closest('[data-choice]')?.dataset.choice;
    if (!choice) return;
    const wasAllowed = preference?.choice === 'allow';
    save(choice);
    banner.hidden = true;
    if (choice === 'allow' && !wasAllowed) capture('$pageview');
  });
  document.body.append(banner);
  const settings = document.createElement('button');
  settings.type = 'button';
  settings.className = 'analytics-settings';
  settings.textContent = 'Analytics preferences';
  settings.addEventListener('click', () => {
    if (privacySignal) {
      settings.textContent = 'Analytics disabled by your browser privacy signal';
      return;
    }
    banner.hidden = false;
    banner.querySelector('button').focus();
  });
  document.querySelector('footer nav')?.append(settings);
  document.addEventListener('click', event => {
    const anchor = event.target.closest('a[href]');
    if (!anchor) return;
    const url = new URL(anchor.href, location.href);
    if (url.origin !== 'https://github.com' || !url.pathname.startsWith('/sintaxerrorpvtltd/Open-Tangerine')) return;
    if (/^\/sintaxerrorpvtltd\/Open-Tangerine\/releases\/download\/[^/]+\/[^/]+\.zip$/.test(url.pathname)) {
      capture('ot_download_click', {release: url.pathname.split('/')[5]});
    } else if (url.pathname.includes('/releases')) capture('ot_releases_click');
    else capture('ot_repository_click');
  });
  capture('$pageview');
})();
