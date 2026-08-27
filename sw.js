/* 온더브라이드 — 서비스워커 (웹 푸시)
   관리자와 작가 캘린더가 같이 쓴다. 어디로 갈지는 알림에 실려 오는 url 이 정한다 */
self.addEventListener('install', (e) => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (e) => {
  let data = {};
  try { data = e.data ? e.data.json() : {}; } catch (_) { data = { title: '온더브라이드', body: e.data ? e.data.text() : '' }; }
  const title = data.title || '온더브라이드';
  const url = data.url || '/admin';
  // 작가에게 가는 알림은 작가 캘린더 아이콘(어두운 것)으로 띄운다 — 관리자 알림과 한눈에 갈린다
  const icon = url.includes('staff-calendar') ? 'assets/favicon-staff.png' : 'assets/favicon.png';
  const opts = {
    body: data.body || '',
    icon,
    badge: 'assets/favicon.png',
    tag: data.tag || 'otb',
    data: { url },
    vibrate: [80, 40, 80],
  };
  // 알림을 띄우고, 홈 화면 아이콘에도 숫자를 붙인다 (대표 요청 2026-08-27).
  // 안 읽은 알림 수 = 지금 떠 있는 알림 수. 눌러서 열면 지운다.
  // setAppBadge 를 못 쓰는 브라우저도 있으므로 실패해도 알림 자체는 뜨게 따로 감싼다
  e.waitUntil((async () => {
    await self.registration.showNotification(title, opts);
    try {
      const n = (await self.registration.getNotifications()).length;
      if (self.navigator && self.navigator.setAppBadge) await self.navigator.setAppBadge(n || 1);
    } catch (_) { /* 뱃지를 못 붙여도 알림은 떴다 */ }
  })());
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || '/admin';
  // 눌러서 열면 아이콘 숫자를 지운다. 남은 알림이 있으면 그만큼만 남긴다
  e.waitUntil((async () => {
    try {
      const n = (await self.registration.getNotifications()).length;
      if (self.navigator && self.navigator.clearAppBadge && !n) await self.navigator.clearAppBadge();
      else if (self.navigator && self.navigator.setAppBadge && n) await self.navigator.setAppBadge(n);
    } catch (_) {}
  })());
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
