// 범용 웹푸시 발송 (Supabase Edge Function, Deno)
// DB(pg_net)가 x-push-secret 헤더 + {title, body, url, tag} 로 호출.
// 신규예약·알림톡 실패 등 모든 관리자 푸시를 이 함수 하나로 처리.
import webpush from 'npm:web-push@3.6.7';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method', { status: 405 });
  if (req.headers.get('x-push-secret') !== Deno.env.get('PUSH_SECRET')) {
    return new Response('forbidden', { status: 403 });
  }
  const { title, body, url, tag } = await req.json().catch(() => ({}));

  const SUPA = Deno.env.get('SUPABASE_URL');
  const KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const h = { apikey: KEY!, Authorization: `Bearer ${KEY}` };

  const sr = await fetch(`${SUPA}/rest/v1/push_subscriptions?select=endpoint,p256dh,auth`, { headers: h });
  const subs = await sr.json();

  webpush.setVapidDetails(
    Deno.env.get('VAPID_SUBJECT') || 'mailto:onthebride@naver.com',
    Deno.env.get('VAPID_PUBLIC')!,
    Deno.env.get('VAPID_PRIVATE')!,
  );
  const payload = JSON.stringify({
    title: title || '온더브라이드',
    body: body || '',
    url: url || '/admin',
    tag: tag || 'otb',
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
