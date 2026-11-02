/* 작가 캘린더 구독 주소 — https://onthebride.com/cal/<열쇠>.ics  (대표 2026-10-28 «1번 해볼까?»)
   vercel.json 의 rewrites 가 /cal/… 을 여기로 돌린다.
   작가가 이 주소를 아이폰·구글·네이버 캘린더에 한 번 넣어 두면, 그쪽이 때때로 와서 다시 받아 간다.
   배정이 바뀌거나 취소되면 다음에 받아 갈 때 그쪽에서도 바뀐다 (구글은 하루쯤 늦다 — 구글이 정한 것).

   ⚠ DB 를 못 읽었을 때 빈 캘린더를 내면 안 된다. 받아 간 쪽이 「일정이 다 없어졌다」로 알고
     작가 폰에서 예식을 통째로 지운다. 그럴 땐 503 — 그쪽은 갖고 있던 것을 그대로 둔다.
   ⚠ 신랑신부 이름·연락처는 싣지 않는다. DB(staff_cal_feed)가 애초에 안 준다.
   ⚠ 일정 번호(UID)는 예약 번호가 아니다 — 예약 번호는 신부님 포털 열쇠라 DB 가 md5 로 바꿔서 준다.
   ⚠ 「자세히 보기」 주소에 작가 번호(?s=)를 붙이지 않는다. 구독 주소가 새도 작가 캘린더는 안 열리게 */
'use strict';

// config.js 와 같은 값 (공개용 키). 시험이 둘이 같은지 본다
const SUPABASE_URL = 'https://cthpxcgesorvtgjdgrtu.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN0aHB4Y2dlc29ydnRnamRncnR1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM5ODc3MDYsImV4cCI6MjA5OTU2MzcwNn0.nZmNgmpqoc2pe6swnER-SiH_1_PFibsXVuFCql1mQGA';
const SITE = 'https://onthebride.com';

const ARRIVE_MIN = 90;    // 작가님은 예식 1시간 30분 전 도착 (월요일 체크와 같은 말)
const AFTER_MIN = 120;    // 예식 뒤 두 시간까지를 촬영으로 잡아 둔다

const pad = (n) => String(n).padStart(2, '0');

// 글자 안의 \ ; , 줄바꿈은 ics 규칙대로 바꾼다
const icsText = (s) => String(s == null ? '' : s)
  .replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');

/* 한 줄이 75바이트를 넘으면 접는다 (다음 줄은 빈칸 하나로 시작).
   ⚠ 바이트로 센다 — 한글은 한 글자가 3바이트다. 글자 한가운데서 자르면 깨진다 */
function fold(line) {
  const out = [];
  let cur = '';
  let bytes = 0;
  for (const ch of line) {
    const b = Buffer.byteLength(ch, 'utf8');
    if (bytes + b > 75) { out.push(cur); cur = ' ' + ch; bytes = 1 + b; } else { cur += ch; bytes += b; }
  }
  out.push(cur);
  return out.join('\r\n');
}

const utcStamp = (d) => `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}`
  + `T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;

// 한국 시각(서머타임 없음, +9) → 그 순간
function kst(ymd, hhmm, plusMin) {
  const [y, m, d] = ymd.split('-').map(Number);
  const [h, mi] = hhmm.split(':').map(Number);
  return new Date(Date.UTC(y, m - 1, d, h - 9, mi + plusMin));
}

const dateOnly = (ymd, plusDays) => {
  const [y, m, d] = ymd.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + plusDays));
  return `${t.getUTCFullYear()}${pad(t.getUTCMonth() + 1)}${pad(t.getUTCDate())}`;
};

const hm = (d) => {
  const k = new Date(d.getTime() + 9 * 3600e3);
  return `${pad(k.getUTCHours())}:${pad(k.getUTCMinutes())}`;
};

// 작가 캘린더 opts() 와 같은 이름
function optNames(e) {
  const o = [];
  if (e.reception) o.push('연회장 인사촬영');
  if (e.pyebaek) o.push('폐백촬영');
  if (e.part2) o.push('2부 촬영');
  if (e.two) o.push('2인 촬영');
  return o;
}

function eventLines(e, stamp) {
  const okDate = /^\d{4}-\d{2}-\d{2}$/.test(String(e.date || ''));
  if (!okDate || !e.id) return [];
  const t = String(e.time || '');
  const timed = /^([01]\d|2[0-3]):[0-5]\d$/.test(t);
  const venue = String(e.venue || '').trim() || '예식장 미정';
  const role = e.role === '서브' ? '서브' : '메인';

  const desc = [];
  if (timed) desc.push(`예식 ${t} · 도착 ${hm(kst(e.date, t, -ARRIVE_MIN))} (예식 1시간 30분 전)`);
  desc.push(e.peer_name ? `${role} · 함께 가는 작가: ${e.peer_name} (${e.peer_role || ''})` : role);
  const o = optNames(e);
  if (o.length) desc.push('옵션: ' + o.join(' · '));
  if (e.pick) desc.push('신부님이 지정하신 촬영');
  if (e.rep) desc.push('촬영: 대표지정');
  desc.push('');
  desc.push('신랑신부 연락처·설문은 작가 캘린더에서 보세요.');
  desc.push(`${SITE}/staff-calendar`);

  const L = [
    'BEGIN:VEVENT',
    `UID:${e.id}@onthebride.com`,
    `DTSTAMP:${stamp}`,
  ];
  if (timed) {
    L.push(`DTSTART:${utcStamp(kst(e.date, t, -ARRIVE_MIN))}`);
    L.push(`DTEND:${utcStamp(kst(e.date, t, AFTER_MIN))}`);
  } else {
    L.push(`DTSTART;VALUE=DATE:${dateOnly(e.date, 0)}`);
    L.push(`DTEND;VALUE=DATE:${dateOnly(e.date, 1)}`);
  }
  L.push(`SUMMARY:${icsText(`[${role}] ${venue}` + (timed ? ` · 예식 ${t}` : ''))}`);
  L.push(`LOCATION:${icsText(venue)}`);
  L.push(`DESCRIPTION:${icsText(desc.join('\n'))}`);
  L.push(`URL:${SITE}/staff-calendar`);
  L.push('END:VEVENT');
  return L;
}

function buildIcs(events, now) {
  const stamp = utcStamp(now || new Date());
  const L = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//onthebride//staff-calendar//KO',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    `X-WR-CALNAME:${icsText('온더브라이드 촬영')}`,
    `X-WR-CALDESC:${icsText('온더브라이드 작가 캘린더에 배정된 예식')}`,
    'X-WR-TIMEZONE:Asia/Seoul',
    // 애플·아웃룩은 이걸 보고 다시 받으러 온다. 구글은 안 본다
    'REFRESH-INTERVAL;VALUE=DURATION:PT1H',
    'X-PUBLISHED-TTL:PT1H',
  ];
  for (const e of (Array.isArray(events) ? events : [])) L.push(...eventLines(e, stamp));
  L.push('END:VCALENDAR');
  return L.map(fold).join('\r\n') + '\r\n';
}

// 누가 받아 가나 — 작가님들이 어느 캘린더에 넣으셨는지 세는 데만 쓴다
function clientOf(ua) {
  const s = String(ua || '');
  if (/google/i.test(s)) return 'google';
  if (/naver/i.test(s)) return 'naver';
  if (/dataaccessd|CalendarAgent|iOS\/|iPhone|iPad|Macintosh|Mac OS X|macOS/i.test(s)) return 'apple';
  return 'other';
}

function send(res, code, type, body, extra) {
  res.statusCode = code;
  res.setHeader('Content-Type', type);
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex');
  for (const [k, v] of Object.entries(extra || {})) res.setHeader(k, v);
  res.end(body);
}

async function handler(req, res) {
  const q = (req && req.query) || {};
  const raw = String(q.f || q.t || '');
  const tok = raw.replace(/\.ics$/i, '').toLowerCase();
  if (!/^[0-9a-f]{32}$/.test(tok)) return send(res, 404, 'text/plain; charset=utf-8', 'not found');
  const ua = (req.headers && req.headers['user-agent']) || '';
  let feed;
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/staff_cal_feed`, {
      method: 'POST',
      headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_token: tok, p_client: clientOf(ua), p_ua: String(ua).slice(0, 200) }),
      signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) throw new Error('rpc ' + r.status);
    feed = await r.json();
  } catch (_) {
    return send(res, 503, 'text/plain; charset=utf-8', 'try again later', { 'Retry-After': '600' });
  }
  if (!feed || !Array.isArray(feed.events)) return send(res, 404, 'text/plain; charset=utf-8', 'not found');
  return send(res, 200, 'text/calendar; charset=utf-8', buildIcs(feed.events, new Date()),
    { 'Content-Disposition': 'inline; filename="onthebride.ics"' });
}

module.exports = handler;
module.exports.buildIcs = buildIcs;
module.exports.clientOf = clientOf;
module.exports.fold = fold;
module.exports.SUPABASE_URL = SUPABASE_URL;
module.exports.SUPABASE_KEY = SUPABASE_KEY;
