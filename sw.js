/* 온더브라이드 — 서비스워커 (웹 푸시)
   관리자와 작가 캘린더가 같이 쓴다. 어디로 갈지는 알림에 실려 오는 url 이 정한다 */
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
      // 알림이 알려준 주소와 같은 곳이 이미 열려 있으면 그 창을 쓴다.
      // 예전에는 '/admin' 이 박혀 있어서 작가 알림도 관리자 창을 깨웠다 (2026-08-27)
      const path = (url.split('?')[0] || '/');
      for (const c of list) { if (c.url.includes(path) && 'focus' in c) return c.focus(); }
      return self.clients.openWindow(url);
    })
  );
});
