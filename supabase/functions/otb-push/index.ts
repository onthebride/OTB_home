// 범용 웹푸시 발송 (Supabase Edge Function, Deno)
// DB(pg_net)가 x-push-secret 헤더 + {title, body, url, tag, staff_id} 로 호출.
//
// staff_id 가 있으면 **그 작가 폰에만**, 없으면 대표(관리자) 폰에만 보낸다.
// 2026-08-27 이전에는 구분이 없어 등록된 것 전부에 보냈다 —
// 작가 구독이 들어온 뒤로는 반드시 걸러야 한다. 안 그러면
// 대표에게 가는 알림(예약·매출·설문)이 작가들에게 다 간다.
import webpush from 'npm:web-push@3.6.7';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method', { status: 405 });
  if (req.headers.get('x-push-secret') !== Deno.env.get('PUSH_SECRET')) {
    return new Response('forbidden', { status: 403 });
  }
  const { title, body, url, tag, staff_id } = await req.json().catch(() => ({}));

  const SUPA = Deno.env.get('SUPABASE_URL');
  const KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const h = { apikey: KEY!, Authorization: `Bearer ${KEY}` };

  // 누구에게 보낼지 — 작가면 그 사람 것만, 아니면 주인 없는 것(=대표)만
  const whose = staff_id ? `staff_id=eq.${encodeURIComponent(staff_id)}` : 'staff_id=is.null';
  const sr = await fetch(`${SUPA}/rest/v1/push_subscriptions?select=endpoint,p256dh,auth,fail_n&${whose}`, { headers: h });
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

  const patch = (ep: string, body: unknown) =>
    fetch(`${SUPA}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(ep)}&${whose}`,
      { method: 'PATCH', headers: { ...h, 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const kill = (ep: string) =>
    fetch(`${SUPA}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(ep)}&${whose}`,
      { method: 'DELETE', headers: h });

  let ok = 0; const gone: string[] = []; const bad: string[] = [];
  for (const s of subs) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload);
      ok++;
      // 살아 있으면 실패 셈을 0 으로 되돌린다 — 잠깐 끊겼던 폰을 잘라내지 않기 위해
      if (s.fail_n) await patch(s.endpoint, { fail_n: 0, last_error: null, last_ok_at: new Date().toISOString() });
      else await patch(s.endpoint, { last_ok_at: new Date().toISOString() });
    } catch (e: any) {
      const code = e && e.statusCode;
      if (code === 404 || code === 410) {
        // 브라우저가 «이 등록은 없다» 고 확실히 말한 것 — 바로 지운다
        gone.push(s.endpoint);
        await kill(s.endpoint);
      } else {
        // 그냥 실패(타임아웃·400 …)는 한 번으로 판단하지 않는다.
        // 세 번 잇달아 실패하면 죽은 것으로 보고 지운다 — 안 그러면 영영 쌓인다
        const n = (s.fail_n || 0) + 1;
        bad.push(s.endpoint);
        if (n >= 3) { gone.push(s.endpoint); await kill(s.endpoint); }
        else await patch(s.endpoint, { fail_n: n, last_error: String(code || (e && e.message) || e).slice(0, 200) });
      }
    }
  }
  return new Response(JSON.stringify({ ok, failed: bad.length, removed: gone.length }),
    { headers: { 'content-type': 'application/json' } });
});
