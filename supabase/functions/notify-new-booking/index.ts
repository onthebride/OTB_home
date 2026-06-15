// 신규 예약 → 관리자 기기로 웹 푸시 발송 (Supabase Edge Function, Deno)
// DB 트리거(pg_net)가 x-push-secret 헤더 + {booking_id} 로 호출.
import webpush from 'npm:web-push@3.6.7';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method', { status: 405 });
  if (req.headers.get('x-push-secret') !== Deno.env.get('PUSH_SECRET')) {
    return new Response('forbidden', { status: 403 });
  }
  const { booking_id } = await req.json().catch(() => ({}));
  const SUPA = Deno.env.get('SUPABASE_URL');
  const KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const h = { apikey: KEY!, Authorization: `Bearer ${KEY}` };

  let name = '', dateStr = '', venue = '';
  if (booking_id) {
    const r = await fetch(`${SUPA}/rest/v1/bookings?id=eq.${booking_id}&select=contractor_name,wedding_date,wedding_venue`, { headers: h });
    const b = (await r.json())[0];
    if (b) { name = b.contractor_name || ''; dateStr = b.wedding_date || ''; venue = b.wedding_venue || ''; }
  }

  const sr = await fetch(`${SUPA}/rest/v1/push_subscriptions?select=endpoint,p256dh,auth`, { headers: h });
  const subs = await sr.json();

  webpush.setVapidDetails(
    Deno.env.get('VAPID_SUBJECT') || 'mailto:onthebride@naver.com',
    Deno.env.get('VAPID_PUBLIC')!,
    Deno.env.get('VAPID_PRIVATE')!,
  );
  const payload = JSON.stringify({
    title: '🔔 신규 예약',
    body: name ? `${name}님${dateStr ? ' · ' + dateStr : ''}${venue ? ' · ' + venue : ''}` : '새 예약이 들어왔어요',
    url: '/admin',
    tag: 'new-booking',
  });

  let ok = 0; const gone: string[] = [];
  for (const s of subs) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload);
      ok++;
    } catch (e: any) {
      if (e && (e.statusCode === 404 || e.statusCode === 410)) gone.push(s.endpoint);
    }
  }
  for (const ep of gone) {
    await fetch(`${SUPA}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(ep)}`, { method: 'DELETE', headers: h });
  }
  return new Response(JSON.stringify({ ok, removed: gone.length }), { headers: { 'content-type': 'application/json' } });
});
