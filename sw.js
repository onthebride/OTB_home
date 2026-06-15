/* 온더브라이드 관리자 — 서비스워커 (웹 푸시) */
self.addEventListener('install', (e) => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (e) => {
  let data = {};
  try { data = e.data ? e.data.json() : {}; } catch (_) { data = { title: '온더브라이드', body: e.data ? e.data.text() : '' }; }
  const title = data.title || '온더브라이드';
  const opts = {
    body: data.body || '',
    icon: 'assets/favicon.png',
    badge: 'assets/favicon.png',
    tag: data.tag || 'otb',
    data: { url: data.url || '/admin' },
    vibrate: [80, 40, 80],
  };
  e.waitUntil(self.registration.showNotification(title, opts));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || '/admin';
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) { if (c.url.includes('/admin') && 'focus' in c) return c.focus(); }
      return self.clients.openWindow(url);
    })
  );
});
