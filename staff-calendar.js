/* ===== 작가 개인 캘린더 =====
   링크: /staff-calendar?s=<작가ID>
   · 배정된 예식이 날짜에 표시된다(예식일·시간·장소·신랑신부·옵션. 연락처는 예식 2주 전부터)
   · 촬영이 안 되는 날은 날짜를 눌러 '불가'로 표시
   · 다른 촬영이 있는 날은 시간·장소를 적어두면, 우리 예식과 4시간 이상 벌어질 때만 배정된다 */
const sb = window.supabase && window.OTB_CONFIG
  ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
  : null;

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/* 홈 화면에 «설치»해서 열면 주소에 ?s= 가 없다 — 안드로이드는 manifest 의 start_url 로 열기 때문이다.
   그래서 링크로 한 번 들어온 작가 번호를 기억해 두었다가, 주소에 없을 때만 꺼내 쓴다.
   주소에 번호가 있으면 그것이 언제나 이긴다 (틀린 번호로 들어오면 그대로 오류를 보여줘야 한다).
   이 번호는 이미 그 사람 브라우저의 주소·방문기록에 있는 것이라 새로 새는 것은 없다 */
const SKEY = 'otb_staff_s';
const pickStaff = () => {
  const q = params.get('s');
  try {
    if (q && uuidRe.test(q)) { localStorage.setItem(SKEY, q); return q; }
    if (!q) { const v = localStorage.getItem(SKEY); if (v && uuidRe.test(v)) return v; }
  } catch (_) { /* 사생활보호 모드면 저장이 막힌다 — 주소에 있는 것만 쓴다 */ }
  return q;
};
const staffId = pickStaff();

/* 홈 화면에 추가할 때 **내 링크가 그대로 실리게** 한다.
   ⚠ 2026-08-27 대표가 실제로 막혔다. manifest 를 파일로 걸었더니
   start_url 이 `/staff-calendar` 로 굳어 ?s= 가 떨어져 나갔고,
   아이폰은 홈 화면 앱이 사파리와 저장소를 **따로** 써서 위에 기억해둔 번호도 못 꺼낸다.
   그래서 이 사람 번호가 박힌 manifest 를 그 자리에서 만들어 건다.
   만들다 실패해도 괜찮다 — manifest 가 없으면 브라우저는 **지금 주소 그대로**
   바로가기를 만들므로 예전처럼 돌아간다. 이쪽으로 넘어지는 게 안전하다 */
function manifestInit() {
  if (!staffId || !uuidRe.test(staffId) || !document.head) return;
  try {
    const o = location.origin;
    const here = `${o}/staff-calendar?s=${encodeURIComponent(staffId)}`;
    const m = {
      id: `/staff-calendar?s=${staffId}`,   // 작가마다 다른 앱이어야 서로 안 덮어쓴다
      name: '온더브라이드 작가 캘린더',
      short_name: '내 캘린더',
      description: '배정된 예식과 촬영 불가일',
      start_url: here,
      scope: `${o}/staff-calendar`,
      display: 'standalone',
      background_color: '#ffffff',
      theme_color: '#ffffff',
      icons: [
        { src: `${o}/assets/favicon-staff.png`, sizes: '192x192', type: 'image/png', purpose: 'any' },
        // 안드로이드는 아이콘을 동그랗게 잘라낸다 — 여백 있는 판을 따로 준다
        { src: `${o}/assets/favicon-staff-mask.png`, sizes: '512x512', type: 'image/png', purpose: 'maskable' },
      ],
    };
    const link = document.createElement('link');
    link.rel = 'manifest';
    link.href = URL.createObjectURL(new Blob([JSON.stringify(m)], { type: 'application/manifest+json' }));
    document.head.appendChild(link);
  } catch (_) { /* 못 걸어도 된다 — 지금 주소로 바로가기가 만들어진다 */ }
}
manifestInit();
const esc = (s) => (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const show = (el) => ['errCard', 'loadCard', 'mainCard'].forEach((id) => ($(id).hidden = $(id) !== el));

// 전화번호는 눌러서 바로 걸리게 (대표 요청). 거는 번호에서는 하이픈을 빼고,
// 보이는 글자는 받은 그대로 둔다. 번호가 없으면 아무것도 안 붙인다.
const tel = (phone) => {
  if (!phone) return '';
  const dial = String(phone).replace(/[^0-9+]/g, '');
  if (!dial) return '';
  return ` <a class="sc-tel" href="tel:${esc(dial)}">${esc(phone)}</a>`;
};

// 예식장 길찾기 (대표 요청 2026-08-27). 우리는 주소가 없고 **이름만** 있으므로 찾기로 보낸다.
// 폰에서는 네이버지도 앱이 받아 연다. 이름이 없으면 단추를 아예 안 만든다
const mapLink = (venue) => {
  const v = String(venue || '').trim();
  if (!v) return '';
  return ` <a class="sc-map" href="https://map.naver.com/p/search/${encodeURIComponent(v)}"
    target="_blank" rel="noopener">길찾기</a>`;
};

const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const dayKey = (v) => String(v).slice(0, 10);
const kTime = (t) => {
  if (!t) return '';
  const [h, m] = String(t).split(':').map(Number);
  return h + ':' + pad(m);
};
const todayStr = ymd(new Date());

let view = new Date();               // 보고 있는 달
let data = { bookings: [], busy: [] };
let openDay = null;
// 지금 열어둔 입력칸의 종류 — 'busy'(다른 촬영) | 'personal'(개인 일정) | null(안 열림)
let formKind = null;
let editId = null;                   // 수정 중인 일정 (없으면 새로 등록)

const KIND_NAME = { busy: '다른 촬영', personal: '개인 일정' };

// 여러 날짜리 개인 일정이면 "8/25~8/28 (4일)" 처럼 보여준다
const mdy = (s) => { const [, m, d] = String(s).slice(0, 10).split('-'); return Number(m) + '/' + Number(d); };
const spanText = (x) => (x.group_id && x.g_n > 1 ? mdy(x.g_from) + '~' + mdy(x.g_to) + ' (' + x.g_n + '일)' : '');

// 달력 한 칸에 들어갈 짧은 이름. 좁으니 제목이 있으면 제목만.
// 달력 칸에 넣을 짧은 글. 제목이 길면 다섯 자에서 자른다 (대표 요청) —
// 칸은 좁은데 제목은 얼마든지 길어질 수 있다. 전체 제목은 날짜를 눌러 열면 보인다
const cellTag = (x) => {
  if (x.title) return x.title.length > 5 ? x.title.slice(0, 5) + '…' : x.title;
  return x.kind === 'personal' ? '개인' : (x.all_day ? '종일' : kTime(x.at_time));
};
let slideDir = '';                   // 달을 넘긴 방향(넘어온 티가 나게 살짝 밀어 넣는다)
let multi = false;                   // 여러 날 고르는 중
let picked = new Set();              // 고른 날짜들 (yyyy-mm-dd)

function opts(w) {
  const o = [];
  if (w.option_reception) o.push('연회장 인사촬영');
  if (w.option_pyebaek) o.push('폐백촬영');
  if (w.option_part2) o.push('2부 촬영');
  if (w.photographer === '2인 촬영') o.push('2인 촬영');
  return o;
}

/* 「이 작가가 캘린더를 열었다」 를 남긴다 (대표 «접속 기록이 있음 좋을거 같은데», 2026-08-28).

   ⚠ 대표가 확인하려고 열어본 것은 세면 안 된다 («내가 들어가는게 카운트가 되네»).
     ① 관리자 목록의 📅 단추는 adm=1 을 달고 온다
     ② 그 브라우저가 관리자로 로그인돼 있으면 그것도 대표다 (같은 주소라 세션이 보인다)
   ⚠ 기다리지 않는다. 늦거나 실패해도 캘린더는 그대로 떠야 한다.
     하루에 여러 번 열어도 DB 에는 하루 한 줄로 모인다 */
async function seenMark() {
  if (!sb || !staffId) return;
  try {
    if (new URLSearchParams(location.search).get('adm') === '1') return;
    const { data } = await sb.auth.getSession();
    if (data && data.session) return;                 // 관리자로 로그인된 기기
    await sb.rpc('staff_seen', { p_staff_id: staffId });
  } catch (e) { /* 못 남겨도 화면은 그대로 */ }
}

async function load() {
  if (!sb || !staffId || !uuidRe.test(staffId)) { show($('errCard')); return; }
  const first = new Date(view.getFullYear(), view.getMonth(), 1);
  const last = new Date(view.getFullYear(), view.getMonth() + 1, 0);
  const { data: res, error } = await sb.rpc('staff_calendar', {
    p_staff_id: staffId, p_from: ymd(first), p_to: ymd(last),
  });
  if (error || !res) { show($('errCard')); return; }
  data = { bookings: res.bookings || [], busy: res.busy || [] };
  renderNext(res.next);        // 보고 있는 달과 무관하게 «다음 촬영» 한 줄
  renderTop(res.staff_name);
  helpInit();
  render();
  tabsInit();
  pushInit();          // 늦게 와도 된다 — 단추만 늦게 뜬다
  settingsInit();      // 「설정」 칸을 띄울지 정한다 (지금은 대표만)
  loadNotices();       // 확인할 것 — 폰 알림이 못 갔어도 여기서 본다
  clearBadge();        // 화면을 열었으니 아이콘 숫자를 지운다
  seenMark();          // 열었다는 것만 남긴다 (대표가 열어본 것은 빼고)
  show($('mainCard'));
}

/* 아래로 당겨 새로고침이 부르는 곳 (대표 요청 2026-08-27).
   load() 가 달력·다음 촬영·머리말·알림을 다시 받아온다. **보고 있던 칸도 같이 되살린다** —
   안 그러면 알림 칸을 보다가 당겼을 때 날짜 칸이 새어 나온다 */
async function refreshAll() {
  const cur = curTab();
  await load();
  await settingsInit();          // load() 안에서도 부르지만 여기선 끝나기를 기다린다
  if (cur === 'me') { meLoaded = true; await loadMe(); }
  if (cur === 'set') renderSet();
  applyTab(cur);                 // 맨 마지막에 — render/renderPanel 이 열어둔 것을 닫는다
}

/* 머리말 — 왼쪽 로고, 오른쪽에 사진과 이름 (대표 요청 2026-08-27).
   사진이 없으면 성 한 글자를 동그라미에 넣는다. 「?」(사용안내)도 여기 붙는다 */
function renderTop(name) {
  const box = $('scTopMe');
  if (!box) return;
  const nm = String(name || '').trim();
  box.innerHTML = `<span class="sc-top-name">${esc(nm)}<i>작가님</i></span>`
    + '<button type="button" class="sc-help-ic" id="helpIc" title="사용안내" aria-label="사용안내">?</button>';
}

/* ===== 다음 촬영 한 줄 (대표 요청 2026-08-27 «1 2번 넣자»)
   달력에서 찾아야 했던 것을 맨 위에 올린다 — 작가가 제일 자주 보는 것이다.
   ⚠ 보고 있는 달에서 뽑지 않는다. 서버가 «오늘 이후 첫 예식» 을 따로 준다 —
   다음 촬영이 다음 달이면 이번 달만 봐서는 안 나온다 ===== */
const DOW = ['일', '월', '화', '수', '목', '금', '토'];

/* 접어둔 기기는 다음에 와도 접힌 채로 (대표 요청 2026-08-27).
   저장이 막힌 기기(사파리 비공개 모드 등)에서도 화면은 그대로 돌아가야 한다 —
   그래서 읽기·쓰기 둘 다 try 로 감싼다. 못 읽으면 「펴 있음」이 기본이다 */
const NEXT_KEY = 'otb_sc_next';
const nextShut = () => { try { return localStorage.getItem(NEXT_KEY) === 'shut'; } catch (e) { return false; } };

/* 예식 한 줄 — 「다음 촬영」과 「날짜를 눌러 여는 칸」이 **같은 모양**을 쓴다
   (대표 «지금 이 스타일이 좋네 / 아래 날짜누르면 뜨는 카드도 이렇게 바꾸자»).
   두 군데서 따로 만들면 한쪽만 고쳐져 곧 어긋난다 — 여기 하나만 고친다.
   연락처는 늘 펴 둔다 (대표 «연락처 안접어도 되겠다 그냥 펴주고 접었따 폈다 버튼 없애주고») */
function shootRow(x, extra) {
  // 설문이 아직이면 그렇게 적는다 — 자리를 비워두면 「단추가 왜 없지」가 된다
  const sv = x.has_survey
    ? `<a class="sc-nx-sv" href="survey-view?b=${esc(x.booking_id)}&s=${esc(staffId)}" target="_blank" rel="noopener">설문 보기</a>`
    : '<span class="sc-nx-sv none">설문 아직 없음</span>';
  const who = [
    x.groom_name ? `<span class="sc-nx-p"><i>신랑</i>${esc(x.groom_name)}${tel(x.groom_phone)}</span>` : '',
    x.bride_name ? `<span class="sc-nx-p"><i>신부</i>${esc(x.bride_name)}${tel(x.bride_phone)}</span>` : '',
  ].filter(Boolean).join('');
  return `
  <div class="sc-nx-row">
    <p class="sc-nx-t"><span>${esc(kTime(x.wedding_time) || '시간 미정')} · ${esc(x.wedding_venue || '-')}${mapLink(x.wedding_venue)}${
      x.role === '서브' ? '<span class="sc-role sub">서브</span>' : ''}</span>${sv}</p>
    <div class="sc-nx-b">${who ? `<div class="sc-nx-who">${who}</div>` : ''}${
      x.photo_usage_agree
        ? '<i class="sc-post ok">포스팅 가능</i>'
        : '<i class="sc-post no">포스팅 불가</i>'}</div>
    ${extra || ''}
  </div>`;
}

function renderNext(n) {
  const box = $('scNext');
  if (!box) return;
  if (!n || !n.items || !n.items.length) { box.hidden = true; box.innerHTML = ''; return; }
  const d = new Date(String(n.wedding_date) + 'T00:00:00');
  const when = n.days === 0 ? '오늘' : n.days === 1 ? '내일' : `${n.days}일 뒤`;

  // 날짜 줄을 눌러 그 아래를 접는다 (대표 «다음 촬영 날짜 밑으로는 접을 수 있게 해줘»).
  // 접혀 있어도 날짜와 몇 건인지는 남는다 — 그것까지 감추면 무엇을 폈는지 알 수 없다
  const shut = nextShut();
  box.hidden = false;
  box.innerHTML = `
    <p class="sc-next-l">다음 촬영<i>${esc(when)}</i></p>
    <button type="button" class="sc-next-m${shut ? ' shut' : ''}" id="scNextT"
      aria-expanded="${shut ? 'false' : 'true'}" aria-controls="scNextB">
      <span>${d.getMonth() + 1}월 ${d.getDate()}일(${DOW[d.getDay()]})${
        n.items.length > 1 ? ` <em>${n.items.length}건</em>` : ''}</span><i></i>
    </button>
    <div class="sc-next-b" id="scNextB"${shut ? ' hidden' : ''}>${
      n.items.map((x) => shootRow(x)).join('')}</div>`;

  const tg = $('scNextT'), bd = $('scNextB');
  if (!tg || !bd) return;
  tg.addEventListener('click', () => {
    const off = !bd.hidden;                    // 지금 펴 있으면 접는다
    bd.hidden = off;
    tg.classList.toggle('shut', off);
    tg.setAttribute('aria-expanded', off ? 'false' : 'true');
    try { localStorage.setItem(NEXT_KEY, off ? 'shut' : 'open'); } catch (e) { /* 저장이 막힌 기기 */ }
  });
}

/* ===== 폰 알림 (대표 요청 2026-08-27
   «스케줄 장소나 시간 변동이나 취소있으면 알람 가게»)

   예식 날짜·시간·장소가 바뀌거나 취소되면 DB 트리거가 이 작가에게만 보낸다.
   아이폰은 **홈 화면에 추가한 뒤 그 앱에서** 켜야 알림이 온다 (사파리 제약).
   그래서 홈화면추가 단추 옆에 둔다 ===== */
const VAPID_PUBLIC = 'BBKafqxDWhKLbQCm7VRSkiFA0NwBy7DrlXFju432bq5KMS8v5XRKBFJC4HmKEtf3WZdQsz7xqQ-3RbVkVBJw1QM';
const b64ToU8 = (b64) => {
  const base = (b64 + '='.repeat((4 - (b64.length % 4)) % 4)).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base); const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
  return arr;
};
let scSw = null;

// 홈 화면 아이콘의 숫자를 지운다 (대표 요청 2026-08-27). 못 쓰는 브라우저면 조용히 넘어간다
function clearBadge() {
  try { if (navigator.clearAppBadge) navigator.clearAppBadge(); } catch (_) {}
}

/* 알림 상태를 **한 곳**에 둔다 — 캘린더 아래 단추와 「설정」 칸 스위치가 같은 값을 보고 그린다.
   두 군데가 저마다 상태를 들고 있으면 한쪽만 바뀌어 어긋난다 (2026-08-27 대표 요청으로 둘이 됐다) */
let pushState = 'unknown';        // unknown | unsupported | off | on
let pushMsg = '';
// 이 기기의 등록이 「관리자」 것과 같으면 알림이 관리자 앱으로 뜬다 (아이폰)
let pushAdminApp = false;

function syncPush() {
  const btn = $('scPush');
  if (btn) {
    // 켜져 있으면 캘린더 첫 화면에서는 감춘다 (대표 «알림이 켜져있으면 캘린더 첫화면서 알림은꺼줘»).
    // 켜라고 권하는 단추라 이미 켠 사람에겐 거치적거린다. 끄는 건 「설정」 칸에서 한다
    btn.hidden = pushState !== 'off';
    btn.textContent = '🔔 알림 받기';
  }
  const note = $('scPushNote');
  if (note) { note.hidden = !pushMsg; note.textContent = pushMsg; }

  const sw = $('setPushSw');
  if (sw) {
    const on = pushState === 'on';
    sw.classList.toggle('on', on);
    sw.setAttribute('aria-checked', on ? 'true' : 'false');
    sw.disabled = pushState === 'unsupported' || pushState === 'unknown';
    const lab = sw.querySelector('b');
    if (lab) lab.textContent = pushState === 'unsupported' ? '켤 수 없어요' : on ? '받는 중' : '꺼짐';
  }
  const hint = $('setPushMsg');
  if (hint) {
    // 관리자 앱 안에서 켜면 알림이 그쪽 이름으로 뜬다 — 어디서 켜야 하는지 알려준다
    const wrong = pushAdminApp && pushState === 'on'
      ? '지금은 알림이 「OTB 관리자」 앱으로 갑니다. 홈 화면의 「내 캘린더」 앱을 열어 거기서 켜주세요.'
      : '';
    const m = pushMsg || wrong;
    hint.hidden = !m;
    hint.textContent = m;
  }
}

async function pushInit() {
  const btn = $('scPush');
  if (btn) btn.addEventListener('click', pushToggle);   // 한 번만 건다
  if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
    // 아이폰에서 홈 화면에 추가하지 않고 사파리로 열면 여기로 온다
    pushState = 'unsupported';
    pushMsg = '이 브라우저에서는 알림을 켤 수 없어요. 아이폰은 먼저 「홈 화면에 추가」를 하고 그 앱에서 열어주세요.';
    syncPush();
    return;
  }
  try {
    scSw = await navigator.serviceWorker.register('sw.js', { scope: '/' });
    await navigator.serviceWorker.ready;
  } catch (_) { pushState = 'unsupported'; syncPush(); return; }

  let sub = await scSw.pushManager.getSubscription();
  // 열쇠가 바뀌었으면 옛 구독은 버린다
  if (sub) {
    const cur = b64ToU8(VAPID_PUBLIC);
    const old = new Uint8Array(sub.options && sub.options.applicationServerKey ? sub.options.applicationServerKey : []);
    if (!(old.length === cur.length && old.every((v, i) => v === cur[i]))) {
      try { await sub.unsubscribe(); } catch (_) {}
      sub = null;
    }
  }
  if (sub && Notification.permission === 'granted') {
    await pushSave(sub);            // 이미 켜져 있다 — 이 작가 것으로 다시 적어둔다
    pushState = 'on';
  } else {
    pushState = 'off';
  }
  pushMsg = '';
  syncPush();
}

async function pushToggle() {
  if (pushState === 'on') await pushDisable();
  else if (pushState === 'off') await pushEnable();
}

async function pushEnable() {
  try {
    if ((await Notification.requestPermission()) !== 'granted') {
      pushMsg = '알림이 거부되어 있어요. 폰 설정에서 이 앱의 알림을 켜주세요.';
      syncPush();
      return;
    }
    const sub = await scSw.pushManager.subscribe({
      userVisibleOnly: true, applicationServerKey: b64ToU8(VAPID_PUBLIC),
    });
    await pushSave(sub);
    pushState = 'on';
    pushMsg = '';
  } catch (_) {
    pushMsg = '알림을 켜지 못했어요. 아이폰은 먼저 「홈 화면에 추가」를 하고 그 앱에서 켜주세요.';
  }
  syncPush();
}

async function pushDisable() {
  try {
    const sub = await scSw.pushManager.getSubscription();
    // 이 작가 것만 끈다 — 같은 폰에 관리자 등록이 있으면 그건 그대로 둔다
    if (sub) { await sb.rpc('drop_push_subscription', { p_endpoint: sub.endpoint, p_staff_id: staffId }); }
  } catch (_) {}
  pushState = 'off';
  pushMsg = '';
  syncPush();
}

async function pushSave(sub) {
  const j = sub.toJSON();
  const { data } = await sb.rpc('save_push_subscription', {
    p_endpoint: j.endpoint,
    p_p256dh: j.keys && j.keys.p256dh,
    p_auth: j.keys && j.keys.auth,
    p_staff_id: staffId,          // 이게 있어야 대표 알림과 안 섞인다
  });
  /* ⚠ 이 등록이 이미 「관리자」 것이면, 여기서 켠 알림은 **관리자 앱 이름과 아이콘**으로 뜬다.
     대표가 실제로 그랬다 (2026-08-27) — 관리자 앱 안에서 캘린더를 열고 거기서 켰다.
     아이폰은 홈 화면 앱마다 저장소가 따로라 **켠 앱으로** 알림이 간다.
     막지는 않는다 — 못 받는 것보다 낫다. 대신 어디서 켜야 하는지 알려준다 */
  pushAdminApp = !!(data && data.admin_app);
}

/* ===== 캘린더 · 내 기록 (대표 요청 2026-08-26 «탭 분리해서 넣을거야») ===== */
let meLoaded = false;
// 지금 보고 있는 칸
function curTab() {
  const b = document.querySelector('.sc-tab.active');
  return (b && b.dataset.sct) || 'cal';
}

/* 어느 칸을 보여줄지 — 칸을 누를 때도, 당겨 새로고침한 뒤에도 **여기 하나만** 쓴다.
   ⚠ 두 군데서 따로 여닫으면 곧 어긋난다. 새로고침이 renderPanel() 로 날짜 칸을 다시 그리는데,
      그때 알림 칸을 보고 있으면 날짜 칸이 새어 나온다 (renderPanel 이 hidden 을 푼다) */
function applyTab(cur) {
  // 달력 판·날짜 칸·홈화면추가는 캘린더 칸에서만 보인다.
  // ⚠ «캘린더냐» 로 판단해야 한다 — «내 기록이냐» 로 두면 칸을 더할 때마다 새어 나온다
  const onCal = cur === 'cal';
  ['calWrap', 'dayPanel'].forEach((id) => {
    const el = $(id);
    if (el) el.hidden = !onCal || (id === 'dayPanel' && !el.innerHTML);
  });
  const a2 = document.querySelector('.sc-a2hs-wrap');
  if (a2) a2.hidden = !onCal;
  $('ntBody').hidden = cur !== 'nt';
  $('meBody').hidden = cur !== 'me';
  $('setBody').hidden = cur !== 'set';
}

function tabsInit() {
  const tabs = $('scTabs');
  if (!tabs || tabs.dataset.on) return;
  tabs.dataset.on = '1';
  tabs.addEventListener('click', (e) => {
    const b = e.target.closest('.sc-tab');
    if (!b) return;
    const cur = b.dataset.sct;                 // cal | nt | me | set
    tabs.querySelectorAll('.sc-tab').forEach((x) => x.classList.toggle('active', x === b));
    applyTab(cur);
    if (cur === 'me' && !meLoaded) { meLoaded = true; loadMe(); }
    if (cur === 'set') renderSet();
  });
}

/* ===== 알림 (대표 요청 2026-08-27
   «알림이 안갈수도 있으니까 노티를 해줬으면 하는데 확인할거 따로 모아서»
   «알림 탭이 따로 있었음 좋겠어 / 내역도 볼 수 있고 / 확인안한건 진하게 /
     확인누른건 보통으로 / 10개정도만 해서 페이지 네이션»)

   폰 알림은 못 갈 수 있다 — 안 켰거나, 껐거나, 등록이 죽었거나, 폰이 꺼져 있었거나.
   그래서 보낸 것을 DB 에 남겨두고 여기서 본다. **알림이 갔든 안 갔든 놓치지 않는다.**
   ⚠ 칸으로 빼면 눌러야 보인다 — 그래서 안 읽은 수를 **칸 이름 옆에** 붙여 밖에서도 알게 한다. */
let ntData = null;
let ntPage = 1;

async function loadNotices(page) {
  if (!sb || !staffId) return;
  const { data, error } = await sb.rpc('staff_notices',
    { p_staff_id: staffId, p_page: page || ntPage });
  if (error || !data) return;
  ntData = data;
  ntPage = data.page;
  renderNotices();
}

// 안 읽은 수는 칸 이름 옆에. 0 이면 딱지를 아예 없앤다
function ntBadge() {
  const el = $('ntCount');
  if (!el) return;
  const n = (ntData && ntData.unread) || 0;
  el.hidden = !n;
  el.textContent = n > 99 ? '99+' : String(n);
}

function renderNotices() {
  ntBadge();
  const box = $('ntBody');
  if (!box || !ntData) return;
  const rows = ntData.rows || [];
  if (!rows.length) {
    box.innerHTML = '<p class="sc-nt-empty">아직 알림이 없어요.<br />예식 날짜·시간·장소가 바뀌거나 취소되면 여기에 남습니다.</p>';
    return;
  }

  // 확인 안 한 것은 진하게, 확인한 것은 보통으로 (대표 지시)
  const item = (r) => `
    <div class="sc-nt-item${r.unread ? ' unread' : ''}">
      <p class="sc-nt-t">${esc(r.title)}<span>${esc(r.at)}</span></p>
      <p class="sc-nt-b">${esc(r.body)}</p>
      ${r.unread ? `<button type="button" class="btn-sm sc-nt-ok" data-nt="${r.id}">확인했어요</button>` : ''}
    </div>`;

  const pg = ntData.pages || 1;
  const nums = [];
  for (let i = 1; i <= pg; i++) {
    // 쪽이 많아지면 앞뒤 두 칸과 처음·끝만 남긴다 — 폰에서 줄이 넘치면 못 누른다
    if (i === 1 || i === pg || Math.abs(i - ntPage) <= 1) {
      nums.push(`<button type="button" class="sc-pg-n${i === ntPage ? ' on' : ''}" data-ntp="${i}">${i}</button>`);
    } else if (nums[nums.length - 1] !== '<span class="sc-pg-d">…</span>') {
      nums.push('<span class="sc-pg-d">…</span>');
    }
  }

  box.innerHTML = `
    <div class="sc-nt-head">
      <b>알림 ${ntData.total}건${ntData.unread ? ` <i>안 읽음 ${ntData.unread}</i>` : ''}</b>
      ${ntData.unread ? '<button type="button" class="btn-sm" id="ntAll">모두 확인</button>' : ''}
    </div>
    <div class="sc-nt-list">${rows.map(item).join('')}</div>
    ${pg > 1 ? `<div class="sc-pg">
      <button type="button" class="sc-pg-a" data-ntp="${ntPage - 1}"${ntPage <= 1 ? ' disabled' : ''}>‹</button>
      ${nums.join('')}
      <button type="button" class="sc-pg-a" data-ntp="${ntPage + 1}"${ntPage >= pg ? ' disabled' : ''}>›</button>
    </div>` : ''}`;

  box.querySelectorAll('[data-nt]').forEach((b) =>
    b.addEventListener('click', () => ntRead(Number(b.dataset.nt))));
  box.querySelectorAll('[data-ntp]').forEach((b) =>
    b.addEventListener('click', () => { if (!b.disabled) loadNotices(Number(b.dataset.ntp)); }));
  const all = $('ntAll');
  if (all) all.addEventListener('click', () => ntRead(null));
}

async function ntRead(id) {
  const args = { p_staff_id: staffId, p_page: ntPage };
  if (id != null) args.p_id = id;
  const { data, error } = await sb.rpc('staff_notice_read', args);
  if (error || !data) return;
  ntData = data;
  ntPage = data.page;
  renderNotices();
  clearBadge();        // 다 확인했으면 홈 화면 아이콘 숫자도 지운다
}

/* ===== 설정 (대표 요청 2026-08-27
   «작가별 설정탭을 하나 더 추가해줘 / 거기에 알람여부도 넣고 / 스케줄을 계속 받을지
     그만받을지도 토글 넣어줘 / 지정비용을 넣을 수 있게 해주고 /
     지정비용은 우리랑 촬영 후 후기가 5개이상 쌓여야지만 비용을 넣을 수 있게 해줘»)

   ⚠ 지금은 **대표 캘린더에만** 뜬다 (대표 «레이아웃은 내 김병훈 캘린더에만 보여주고
   나머지는 최종 확인 후 배포하는걸로»). 다 열어줄 때는 아래 is_rep 줄만 지우면 된다.
   ⚠ 후기 5건 문턱은 **서버가 막는다** — 화면만 잠그면 개발자도구로 그냥 부를 수 있다 */
let setData = null;

async function settingsInit() {
  if (!sb || !staffId) return;
  const { data, error } = await sb.rpc('staff_settings', { p_staff_id: staffId });
  if (error || !data) return;
  setData = data;
  if (!data.is_rep) return;                    // ← 다 열어줄 때 이 줄만 지운다
  const b = document.querySelector('.sc-tab[data-sct="set"]');
  if (b) b.hidden = false;
}

const wonFmt = (n) => Number(n || 0).toLocaleString('ko-KR');

function renderSet() {
  const box = $('setBody');
  if (!box) return;
  const d = setData;
  if (!d) { box.innerHTML = '<p class="sv-sub">설정을 불러오지 못했어요.</p>'; return; }
  const fee = d.pick_fee == null ? '' : d.pick_fee;

  box.innerHTML = `
    <div class="sc-set">
      <section class="sc-set-row">
        <h3>알림</h3>
        <p class="sc-set-d">예식 <b>날짜·시간·장소</b>가 바뀌거나,
          <b>연회장·폐백·2부 촬영</b>이 붙고 빠지거나, <b>취소</b>되면 폰으로 알려드려요.</p>
        <p class="sc-set-d"><b>한 기기에서만 받습니다.</b><br />
          다른 기기에서 켜면 이전 기기는 저절로 꺼져요.</p>
        <button type="button" class="sc-sw" id="setPushSw" role="switch" aria-checked="false">
          <span class="sc-sw-k"></span><b>불러오는 중</b>
        </button>
        <p class="sc-set-msg" id="setPushMsg" hidden></p>
      </section>

      <section class="sc-set-row">
        <h3>스케줄 받기</h3>
        <p class="sc-set-d">잠시 쉬실 때는 꺼두세요. 꺼두면 <b>새 예식이 배정되지 않아요.</b></p>
        <p class="sc-set-d"><b>이미 배정된 예식은 진행을 해주셔야 하고,</b><br />
          그마저도 어려우시면 <b>대표와 상의</b>해 주세요.</p>
        <button type="button" class="sc-sw${d.accepting ? ' on' : ''}" id="setAccept"
          role="switch" aria-checked="${d.accepting ? 'true' : 'false'}">
          <span class="sc-sw-k"></span><b>${d.accepting ? '받는 중' : '쉬는 중'}</b>
        </button>
      </section>

      <section class="sc-set-row">
        <h3>지정 촬영비</h3>
        <p class="sc-set-d">신부님이 <b>작가님을 지정해</b> 예약하실 때
          기본가에 더해지는 금액이에요.</p>
        <p class="sc-set-d">기본 작가 페이가 <b>25만원</b>이니,
          여기에 지정 촬영비를 더한 <b>총 금액</b>이 나갑니다.<br />
          안 받으시려면 <b>0</b>을 적어주세요.</p>
        ${d.can_fee ? `
        <div class="sc-fee">
          <input type="text" id="setFee" inputmode="numeric" autocomplete="off"
            value="${fee === '' ? '' : wonFmt(fee)}" placeholder="예) 30,000" />
          <span class="sc-fee-w">원</span>
          <button type="button" class="btn-sm primary" id="setFeeSave">저장</button>
        </div>
        <p class="sc-set-now" id="setFeeNow">${d.pick_fee == null ? '아직 안 정하셨어요.'
          : d.pick_fee === 0 ? '지금은 <b>안 받는 것</b>으로 되어 있어요.'
          : `지금 <b>${wonFmt(d.pick_fee)}원</b> — 신부님이 지정하시면 <b>${wonFmt(250000 + d.pick_fee)}원</b>이 나갑니다.`}</p>`
        : `
        <p class="sc-set-lock">촬영 후기가 <b>${d.need}건</b> 쌓이면 적으실 수 있어요.<br />
          지금은 <b>${d.reviews}건</b>이에요.</p>`}
      </section>
    </div>`;

  // 알림도 스케줄 받기와 같은 스위치로 (대표 «설정에 알림켜짐도 토글로 해줘»).
  // 상태는 pushState 한 곳에서 오고 syncPush() 가 그린다 — 여기서 따로 들고 있지 않는다
  const psw = $('setPushSw');
  if (psw) psw.addEventListener('click', pushToggle);
  syncPush();

  const sw = $('setAccept');
  if (sw) sw.addEventListener('click', () => setSave({ accepting: !setData.accepting }, sw));
  /* 금액에 쉼표를 찍어준다 (대표 «숫자표기로 해줘 쉼표넣어서»).
     ⚠ <input type="number"> 는 쉼표를 못 담는다 — text 로 두고 우리가 찍는다.
     보낼 때는 쉼표를 떼고 숫자만 보낸다 */
  const feeEl = $('setFee');
  if (feeEl) feeEl.addEventListener('input', () => {
    const n = feeEl.value.replace(/[^0-9]/g, '').slice(0, 7);   // 100만원까지
    feeEl.value = n === '' ? '' : wonFmt(n);
  });
  const save = $('setFeeSave');
  if (save) save.addEventListener('click', () => {
    const v = String(($('setFee').value || '')).replace(/[^0-9]/g, '');
    if (v === '') { toastSet('금액을 적어주세요.'); return; }
    setSave({ pick_fee: Number(v) }, save);
  });
}

function toastSet(msg) {
  const el = $('setFeeNow') || $('setBody');
  if (el) el.innerHTML = esc(msg);
}

async function setSave(patch, btn) {
  if (btn) btn.disabled = true;
  const { data, error } = await sb.rpc('staff_settings_set', { p_staff_id: staffId, p_patch: patch });
  if (btn) btn.disabled = false;
  if (error || !data) {
    // 후기가 모자라면 서버가 막는다. 그 말을 그대로 옮기지 않고 알아듣게 바꿔준다
    const m = /need (\d+) reviews \(now (\d+)\)/.exec(error && error.message || '');
    toastSet(m ? `촬영 후기가 ${m[1]}건 쌓이면 적으실 수 있어요. 지금은 ${m[2]}건이에요.`
      : '저장하지 못했어요. 잠시 후 다시 해주세요.');
    return;
  }
  setData = data;
  renderSet();
}

async function loadMe() {
  const box = $('meBody');
  const { data, error } = await sb.rpc('staff_stats', { p_staff_id: staffId });
  if (error || !data) { box.innerHTML = '<p class="sv-sub">기록을 불러오지 못했어요.</p>'; return; }
  const s = data.shot || {}, f = data.fb || {}, sub = data.sub || {};
  const ym = (v) => (v ? String(v).slice(0, 7).replace('-', '. ') : '');
  // 예식장 이름이 길면 홀 이름까지는 안 보여준다 (좁은 화면에서 줄이 밀린다)
  const cut = (v) => esc(String(v).replace(/\s*[-/(,].*$/, '').slice(0, 20));

  const card = (k, v, sub2) => '<div class="me-card"><span class="me-k">' + k + '</span>'
    + '<strong>' + v + '</strong>' + (sub2 ? '<span class="me-s">' + sub2 + '</span>' : '') + '</div>';

  const venues = (data.venues || []).length
    ? '<ol class="me-vn">' + data.venues.map((v) =>
      '<li><span>' + cut(v.venue) + '</span><b>' + v.n + '</b></li>').join('') + '</ol>'
    : '<p class="sv-sub">아직 기록이 없어요.</p>';

  // 후기가 없으면 점수 칸을 아예 안 그린다 — 「-」 만 늘어놓으면 서운하다
  const hasFb = Number(f.n) > 0 || Number(sub.n) > 0;
  const fbCards = hasFb
    ? '<div class="me-cards">'
      + (f.score == null ? '' : card('후기 점수', f.score, '100점 만점'))
      + (f.rec == null ? '' : card('추천 의향', f.rec, '10점 만점'))
      + (f.overall == null ? '' : card('전체 만족', f.overall, '10점 만점'))
      + (f.rate == null ? '' : card('응답률', f.rate + '%', f.target + '건 중 ' + f.n + '건'))
      + (Number(sub.n) ? card('서브 별점', sub.avg, sub.n + '건') : '')
      + '</div>'
    : '<p class="sv-sub">아직 받은 후기가 없어요. 예식 다음날 신부님께 설문이 나갑니다.</p>';

  const said = (data.said || []).map((x) => {
    const d = x.wedding_date ? String(x.wedding_date).slice(0, 10).replace(/-/g, '. ') : '';
    // 신부님 이름도 보여준다 (대표 요청 2026-08-26). 번호·이메일은 여전히 안 온다
    return '<div class="me-say">'
      + '<div class="me-say-h">'
        + (x.bride_name ? '<b>' + esc(x.bride_name) + '</b> · ' : '')
        + esc([d, cut(x.wedding_venue)].filter(Boolean).join(' · '))
        + (x.as_sub ? ' <i>서브</i>' : '') + '</div>'
      + (x.message ? '<p>' + esc(x.message) + '</p>' : '')
      + (x.next_req ? '<p class="me-req">다음엔 — ' + esc(x.next_req) + '</p>' : '')
      + '</div>';
  }).join('');

  box.innerHTML =
    '<div class="me-cards">'
      + card('총 촬영', s.shots || 0, '건')
      + card('가본 예식장', s.venues || 0, '곳')
      + (Number(s.booked) ? card('앞으로', s.booked, '건 예정') : '')
    + '</div>'
    + (s.first ? '<p class="sv-sub me-since">' + ym(s.first) + ' 부터 함께하고 계십니다</p>' : '')
    + '<h3 class="me-h">많이 가신 예식장</h3>' + venues
    + '<h3 class="me-h">후기</h3>' + fbCards
    + (said ? '<h3 class="me-h">신부님이 남긴 글</h3>' + said : '');
}

function render() {
  // 연도는 작게 위에, 달은 크게 — 숫자를 세리프로 보여준다
  $('monthLabel').innerHTML =
    `<i>${view.getFullYear()}</i><b>${view.getMonth() + 1}<em>월</em></b>`;
  const first = new Date(view.getFullYear(), view.getMonth(), 1);
  const days = new Date(view.getFullYear(), view.getMonth() + 1, 0).getDate();

  const byDay = {};
  data.bookings.forEach((b) => { (byDay[dayKey(b.wedding_date)] ||= { bk: [], busy: [] }).bk.push(b); });
  data.busy.forEach((x) => { (byDay[dayKey(x.the_date)] ||= { bk: [], busy: [] }).busy.push(x); });

  let html = '';
  for (let i = 0; i < first.getDay(); i++) html += '<div class="sc-cell empty"></div>';
  for (let d = 1; d <= days; d++) {
    const key = `${view.getFullYear()}-${pad(view.getMonth() + 1)}-${pad(d)}`;
    const it = byDay[key] || { bk: [], busy: [] };
    const off = it.busy.some((x) => x.kind === 'off');
    // 개인일정도 그날 촬영은 못 하는 것으로 본다(대표 방침) — 칸도 같이 막힌 것처럼 보인다
    const blocked = off || it.busy.some((x) => x.kind === 'personal');
    const past = key < todayStr;
    // 고르는 중에는 '이미 불가'거나 '배정된 예식이 있는' 날은 고를 수 없다(서버도 거부한다)
    const lockedForPick = multi && (blocked || it.bk.length > 0);
    const cls = ['sc-cell'];
    if (past) cls.push('past');
    if (blocked) cls.push('off');
    if (key === todayStr) cls.push('today');
    if (!multi && key === openDay) cls.push('sel');
    if (multi && picked.has(key)) cls.push('picked');
    if (lockedForPick) cls.push('nopick');
    html += `<button type="button" class="${cls.join(' ')}" data-d="${key}"${past || lockedForPick ? ' disabled' : ''}>
      <span class="sc-d">${d}</span>
      ${it.bk.map((b) => `<span class="sc-tag bk">${esc(kTime(b.wedding_time) || '예식')}</span>`).join('')}
      ${it.busy.filter((x) => x.kind === 'busy').map((x) => `<span class="sc-tag busy">${esc(cellTag(x))}</span>`).join('')}
      ${it.busy.filter((x) => x.kind === 'personal').map((x) => `<span class="sc-tag pers">${esc(cellTag(x))}</span>`).join('')}
      ${off ? '<span class="sc-tag off">불가</span>' : ''}
    </button>`;
  }
  const g = $('grid');
  g.innerHTML = html;
  if (slideDir) {
    g.classList.remove('sc-in-l', 'sc-in-r');
    void g.offsetWidth;                        // 같은 애니메이션을 다시 태우려면 한 번 끊어줘야 한다
    g.classList.add(slideDir === 'next' ? 'sc-in-r' : 'sc-in-l');
    slideDir = '';
  }
  g.querySelectorAll('.sc-cell[data-d]').forEach((el) =>
    el.addEventListener('click', () => {
      const d = el.dataset.d;
      if (multi) {
        if (picked.has(d)) picked.delete(d); else picked.add(d);
        render();
        return;
      }
      openDay = d; formKind = null; editId = null; render(); renderPanel();
    }));
  renderPickBar();
  if (!multi && openDay) renderPanel();
}

// 여러 날 고르기 — 켜고 끄는 버튼과, 고른 개수·저장 막대
function renderPickBar() {
  const bar = $('pickBar');
  if (!bar) return;
  if (!multi) { bar.hidden = true; bar.innerHTML = ''; return; }
  bar.hidden = false;
  const n = picked.size;
  bar.innerHTML = `
    <p class="pk-hint">촬영이 안 되는 날을 눌러서 고르세요. 배정된 예식이 있는 날은 고를 수 없습니다.</p>
    <div class="pk-row">
      <span class="pk-n">${n ? n + '일 선택' : '고른 날 없음'}</span>
      <button type="button" class="btn-sm primary pk-save"${n ? '' : ' disabled'}>촬영 불가로 저장</button>
      <button type="button" class="btn-sm pk-cancel">취소</button>
    </div>
    <p class="sc-status" id="pkStatus"></p>`;
  const save = bar.querySelector('.pk-save');
  if (save) save.addEventListener('click', savePicked);
  const cancel = bar.querySelector('.pk-cancel');
  if (cancel) cancel.addEventListener('click', () => { multi = false; picked.clear(); render(); });
}

async function savePicked() {
  const st = $('pkStatus');
  const dates = [...picked].sort();
  if (!dates.length) return;
  if (st) st.textContent = '저장 중…';
  const { data, error } = await sb.rpc('staff_busy_add_many', { p_staff_id: staffId, p_dates: dates });
  if (error) { if (st) st.textContent = error.message || '저장하지 못했습니다.'; return; }
  const skipped = (data && data.skipped) || [];
  multi = false; picked.clear();
  await load();
  if (skipped.length) {
    const days = skipped.map((x) => String(x.d).slice(5).replace('-', '/')).join(', ');
    alert(`${(data && data.ok) || 0}일 등록했습니다.\n\n${skipped.length}일은 등록하지 못했습니다 (${days})\n배정된 예식이 있거나 지난 날짜입니다.`);
  }
}

function renderPanel() {
  const p = $('dayPanel');
  if (multi || !openDay) { p.hidden = true; return; }
  const bk = data.bookings.filter((b) => dayKey(b.wedding_date) === openDay);
  const busy = data.busy.filter((x) => dayKey(x.the_date) === openDay);
  const off = busy.find((x) => x.kind === 'off');
  const [y, m, d] = openDay.split('-').map(Number);

  // 날짜 칸도 「다음 촬영」과 같은 줄 모양을 쓴다 (대표 요청 2026-08-27).
  // 옵션 딱지만 이 화면에서 더 붙인다
  const bkHtml = bk.map((b) => {
    const o = opts(b);
    const extra = o.length
      ? `<div class="ss-opts sc-nx-opts">${o.map((x) => `<span class="ss-opt${x === '2인 촬영' ? ' two' : ''}">${esc(x)}</span>`).join('')}</div>`
      : '';
    const rep = b.rep_designation ? '<p class="sc-nx-rep">촬영 : 대표지정</p>' : '';
    return `<div class="sc-item bk">${shootRow(b, rep + extra)}</div>`;
  }).join('');

  const evHtml = busy.filter((x) => x.kind === 'busy' || x.kind === 'personal').map((x) => `
    <div class="sc-item ${x.kind === 'personal' ? 'pers' : 'busy'}">
      <div class="sc-item-h">
        <b>${esc(x.all_day ? '종일' : (kTime(x.at_time) || '시간 미정'))}</b>
        ${x.title ? '<span class="sc-title">' + esc(x.title) + '</span>' : ''}
        ${x.place ? '<span class="sc-place">' + esc(x.place) + '</span>' : ''}
        ${spanText(x) ? '<span class="sc-span">' + esc(spanText(x)) + '</span>' : ''}
        <span class="sc-kind ${x.kind}">${KIND_NAME[x.kind]}</span>
      </div>
      ${x.note ? '<div class="sc-item-b sc-memo">' + esc(x.note) + '</div>' : ''}
      <div class="sc-item-btns">
        <button type="button" class="btn-sm sc-edit" data-id="${x.id}">수정</button>
        <button type="button" class="btn-sm sc-del" data-id="${x.id}"
          data-group="${x.group_id && x.g_n > 1 ? x.group_id : ''}">${x.group_id && x.g_n > 1 ? '전부 지우기' : '지우기'}</button>
      </div>
    </div>`).join('');
  const editing = editId ? busy.find((x) => String(x.id) === String(editId)) : null;

  p.hidden = false;
  p.innerHTML = `
    <div class="sc-panel">
      <h3>${y}년 ${m}월 ${d}일</h3>
      ${bkHtml || ''}
      ${evHtml || ''}
      ${off ? `<div class="sc-item off"><div class="sc-item-h"><b>이 날은 촬영 불가</b><span class="sc-mine">내가 등록</span></div>
                 <button type="button" class="btn-sm sc-del" data-id="${off.id}">해제</button></div>` : ''}
      ${bk.length ? '<p class="sc-hint">배정된 예식이 있는 날입니다.<br />촬영이 어려우시면 <b>대표에게 연락</b>해 주세요.</p>' : ''}
      <div class="sc-add">
        <div class="sc-add-btns">
          ${off || bk.length ? '' : '<button type="button" class="btn-sm sc-off">촬영불가</button>'}
          ${off || formKind ? '' : '<button type="button" class="btn-sm sc-openbusy">다른촬영등록</button>'}
          ${off || formKind || bk.length ? '' : '<button type="button" class="btn-sm sc-openpers">개인일정등록</button>'}
          ${off && !bk.length ? '<button type="button" class="btn-sm primary sc-multi">다른 날짜 같이 선택하기</button>' : ''}
        </div>
        ${formKind ? `<div class="sc-busy-form">
          <button type="button" class="sc-close" aria-label="닫기" title="닫기">×</button>
          <p class="sc-form-t">${KIND_NAME[formKind]} ${editing ? '수정' : '등록'}</p>
          <label class="sc-f"><span>할 일</span><input type="text" id="bTitle"
            placeholder="${formKind === 'personal' ? '예: 병원 / 가족모임 / 휴가' : '예: OO웨딩홀 본식'}"
            value="${editing ? esc(editing.title || '') : ''}" /></label>
          ${formKind === 'personal' && !editing
            ? '<label class="sc-f"><span>언제까지</span>'
              + '<input type="date" id="bUntil" value="' + openDay + '" min="' + openDay + '" /></label>'
              + '<p class="sc-hint-row">하루면 그대로 두세요</p>'
            : ''}
          <label class="sc-f sc-check"><span>종일</span><input type="checkbox" id="bAllDay"${editing && editing.all_day ? ' checked' : ''} /></label>
          <label class="sc-f" id="bTimeRow"><span>시간</span>
            <span class="sc-time">
              <select id="bH">${['<option value="">시</option>']
                .concat(Array.from({ length: 24 }, (_, i) =>
                  `<option value="${pad(i)}"${editing && String(editing.at_time || '').slice(0, 2) === pad(i) ? ' selected' : ''}>${pad(i)}</option>`)).join('')}</select>
              <b>:</b>
              <select id="bM">${Array.from({ length: 12 }, (_, i) =>
                `<option value="${pad(i * 5)}"${editing && String(editing.at_time || '').slice(3, 5) === pad(i * 5) ? ' selected' : ''}>${pad(i * 5)}</option>`).join('')}</select>
            </span>
          </label>
          <label class="sc-f"><span>장소</span><input type="text" id="bPlace" placeholder="예: 아펠가모 광화문"
            value="${editing ? esc(editing.place || '') : ''}" /></label>
          <label class="sc-f"><span>메모</span><textarea id="bNote" rows="2" placeholder="여러 줄로 적으셔도 됩니다">${editing ? esc(editing.note || '') : ''}</textarea></label>
          <div class="sc-form-btns">
            <button type="button" class="btn-sm primary sc-addbusy">${editing ? '수정' : '저장'}</button>
            <button type="button" class="btn-sm sc-cancelbusy">취소</button>
          </div>
          <p class="sc-note">${formKind === 'personal'
            ? '대표님께는 <b>«개인 일정»</b> 이라고만 보입니다. 무슨 일인지·몇 시인지는 안 보입니다.<br />그날은 <b>촬영 불가</b>로 처리됩니다.'
            : '대표님께는 <b>시간과 장소</b>만 보입니다. 메모는 안 보입니다.<br />우리 예식과 <b>4시간 이상</b> 벌어지면 그날도 배정될 수 있습니다.'}</p>
        </div>` : ''}
      </div>
      <p class="sc-status" id="scStatus"></p>
    </div>`;

  p.querySelectorAll('.sc-del').forEach((btn) =>
    btn.addEventListener('click', () => del(btn.dataset.id, btn.dataset.group)));
  const offBtn = p.querySelector('.sc-off');
  if (offBtn) offBtn.addEventListener('click', () => add('off'));
  const multiBtn = p.querySelector('.sc-multi');
  // 이 버튼은 이미 불가로 찍은 날에만 나온다 → 그 날은 담을 필요가 없으니 빈 상태로 시작
  if (multiBtn) multiBtn.addEventListener('click', () => {
    multi = true;
    picked.clear();
    render();
  });
  const openBusy = p.querySelector('.sc-openbusy');
  if (openBusy) openBusy.addEventListener('click', () => { formKind = 'busy'; editId = null; renderPanel(); });
  const openPers = p.querySelector('.sc-openpers');
  if (openPers) openPers.addEventListener('click', () => { formKind = 'personal'; editId = null; renderPanel(); });
  const shut = () => { formKind = null; editId = null; renderPanel(); };
  const cancelBusy = p.querySelector('.sc-cancelbusy');
  if (cancelBusy) cancelBusy.addEventListener('click', shut);
  const closeBtn = p.querySelector('.sc-close');
  if (closeBtn) closeBtn.addEventListener('click', shut);
  const addBtn = p.querySelector('.sc-addbusy');
  if (addBtn) addBtn.addEventListener('click', () => add(formKind));
  p.querySelectorAll('.sc-edit').forEach((btn) => btn.addEventListener('click', () => {
    const it = busy.find((x) => String(x.id) === String(btn.dataset.id));
    editId = btn.dataset.id; formKind = (it && it.kind) || 'busy'; renderPanel();
  }));
  // 메모는 줄이 늘면 칸이 같이 늘어난다 — 스크롤이 생기면 적어둔 게 안 보인다
  const note = p.querySelector('#bNote');
  if (note) {
    const grow = () => { note.style.height = 'auto'; note.style.height = (note.scrollHeight + 2) + 'px'; };
    note.addEventListener('input', grow);
    grow();
  }
  // 종일이면 시간 고를 일이 없다
  const allDay = p.querySelector('#bAllDay');
  const timeRow = p.querySelector('#bTimeRow');
  if (allDay && timeRow) {
    const sync = () => { timeRow.hidden = allDay.checked; };
    allDay.addEventListener('change', sync);
    sync();
  }
}

async function add(kind) {
  const st = $('scStatus');
  const body = { p_staff_id: staffId, p_date: openDay, p_kind: kind };
  if (kind === 'busy' || kind === 'personal') {
    const allDay = !!($('bAllDay') && $('bAllDay').checked);
    const h = $('bH') ? $('bH').value : '';
    const m = $('bM') ? $('bM').value : '00';
    // 다른 촬영은 시간을 알아야 겹치는지 볼 수 있다. 개인일정은 어차피 그날을 막으니 없어도 된다.
    if (kind === 'busy' && !allDay && !h) {
      st.textContent = '시간을 골라 주세요. (하루 종일이면 [종일] 을 켜주세요)'; return;
    }
    body.p_time = (allDay || !h) ? null : h + ':' + m;
    body.p_place = $('bPlace') ? $('bPlace').value.trim() : '';
    body.p_note = $('bNote') ? $('bNote').value.trim() : '';
    body.p_title = $('bTitle') ? $('bTitle').value.trim() : '';
    body.p_all_day = allDay || (kind === 'personal' && !h);
  }
  st.textContent = '저장 중…';
  const cur = editId ? (data.busy || []).find((x) => String(x.id) === String(editId)) : null;
  const until = $('bUntil') ? $('bUntil').value : '';
  let res;
  if (editId && cur && cur.group_id && cur.g_n > 1) {
    // 여러 날짜리는 묶음 통째로 고친다
    res = await sb.rpc('staff_busy_upd_group', {
      p_staff_id: staffId, p_group: cur.group_id,
      p_title: body.p_title, p_note: body.p_note,
      p_time: body.p_time, p_place: body.p_place, p_all_day: body.p_all_day });
  } else if (editId) {
    res = await sb.rpc('staff_busy_upd', {
      p_staff_id: staffId, p_id: Number(editId),
      p_time: body.p_time, p_place: body.p_place, p_note: body.p_note,
      p_title: body.p_title, p_all_day: body.p_all_day });
  } else if (kind === 'personal' && until && until > openDay) {
    res = await sb.rpc('staff_busy_add_range', {
      p_staff_id: staffId, p_from: openDay, p_to: until,
      p_title: body.p_title, p_note: body.p_note,
      p_time: body.p_time, p_place: body.p_place, p_all_day: body.p_all_day });
  } else {
    res = await sb.rpc('staff_busy_add', body);
  }
  if (res.error) { st.textContent = res.error.message || '저장하지 못했습니다.'; return; }
  const skipped = (res.data && res.data.skipped) || [];
  if (skipped.length) {
    alert(((res.data && res.data.n) || 0) + '일 등록했습니다.\n\n'
      + skipped.length + '일은 등록하지 못했습니다 ('
      + skipped.map((x) => String(x.d).slice(5).replace('-', '/')).join(', ') + ')\n'
      + '배정된 예식이 있거나 지난 날짜입니다.');
  }
  st.textContent = '';
  formKind = null;
  editId = null;
  await load();
  renderPanel();
}

async function del(id, group) {
  // 여러 날짜리면 통째로 지운다 — 하루씩 지우게 하면 번거롭다
  if (group) {
    if (!confirm('이 일정이 걸린 날을 전부 지울까요?')) return;
    const { error } = await sb.rpc('staff_busy_del_group', { p_staff_id: staffId, p_group: group });
    if (error) { alert('삭제 실패: ' + error.message); return; }
  } else {
    const { error } = await sb.rpc('staff_busy_del', { p_staff_id: staffId, p_id: Number(id) });
    if (error) { alert('삭제 실패: ' + error.message); return; }
  }
  await load();
  renderPanel();
}

// ── 홈 화면에 추가 ──
(function a2hs() {
  const btn = $('a2hs'), modal = $('a2hsModal');
  if (!btn || !modal) return;
  const ua = navigator.userAgent || '';
  const inApp = /KAKAOTALK|NAVER|Instagram|FBAN|FBAV|Line\//i.test(ua);
  const iOS = /iPhone|iPad|iPod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const android = /Android/i.test(ua);
  const installed = (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || navigator.standalone === true;
  if (installed) { btn.hidden = true; return; }   // 이미 홈 화면에서 연 경우

  const steps = inApp
    ? `<p class="a2-warn">지금은 <b>카카오톡 안</b>에서 보고 계십니다. 여기서는 홈 화면에 추가할 수 없어요.</p>
       <ol><li>화면 오른쪽 <b>⋮ (또는 ···) 메뉴</b></li>
           <li><b>다른 브라우저로 열기</b> ${iOS ? '(Safari)' : '(Chrome)'}</li>
           <li>브라우저에서 이 버튼을 다시 눌러주세요</li></ol>`
    : iOS
    ? `<ol><li>화면 아래 <b>공유 버튼</b> <span class="a2-ic">⬆︎</span></li>
           <li>목록에서 <b>홈 화면에 추가</b></li>
           <li>오른쪽 위 <b>추가</b></li></ol>`
    : android
    ? `<ol><li>화면 오른쪽 위 <b>⋮ 메뉴</b></li>
           <li><b>홈 화면에 추가</b> (또는 앱 설치)</li>
           <li><b>추가</b></li></ol>`
    : `<ol><li>브라우저 메뉴를 엽니다</li>
           <li><b>바로가기 만들기</b> 또는 <b>홈 화면에 추가</b></li></ol>
       <p class="a2-warn">휴대폰에서 열면 더 간단합니다.</p>`;

  $('a2hsSteps').innerHTML = steps + '<p class="a2-note">추가해두시면 카톡을 찾지 않아도 바로 열 수 있습니다.</p>';
  const open = () => { modal.hidden = false; };
  const close = () => { modal.hidden = true; };
  btn.addEventListener('click', open);
  $('a2hsClose').addEventListener('click', close);
  modal.addEventListener('click', (e) => { if (e.target === modal) close(); });
})();

/* 오늘로 돌아오기 (대표 요청 2026-08-27).
   달을 몇 번 넘기고 나면 오늘로 돌아오기가 번거롭다.
   이미 이번 달을 보고 있으면 달은 그대로 두고 오늘 칸만 연다 */
function goToday() {
  const now = new Date();
  const same = view.getFullYear() === now.getFullYear() && view.getMonth() === now.getMonth();
  view = new Date(now.getFullYear(), now.getMonth(), 1);
  openDay = todayStr;
  formKind = null;
  editId = null;
  slideDir = same ? '' : (now < view ? 'l' : 'r');
  if (same) { render(); } else { load().then(() => {}); }
}

function goMonth(step) {
  view = new Date(view.getFullYear(), view.getMonth() + step, 1);
  openDay = null;
  formKind = null;
  editId = null;
  picked.clear();               // 달마다 따로 고른다 — 넘기면 비운다
  $('dayPanel').hidden = true;
  slideDir = step > 0 ? 'next' : 'prev';
  load();
}
$('prevM').addEventListener('click', () => goMonth(-1));
$('nextM').addEventListener('click', () => goMonth(1));
// 오늘로 돌아오기 (대표 요청 2026-08-27)
const todayBtn = $('todayBtn');
if (todayBtn) todayBtn.addEventListener('click', goToday);

// ── 좌우로 밀어 달 넘기기(폰) ──
// 세로로 스크롤하려는 손짓과 헷갈리면 안 된다. 처음 움직인 방향으로 가로/세로를 정하고,
// 가로로 정해졌을 때만 넘긴다. 날짜 상세 칸은 대상에서 빼서 글자 선택을 방해하지 않는다.
(function swipeMonth() {
  const el = $('calWrap');
  if (!el) return;
  const MIN = 45;                    // 이만큼은 밀어야 넘어간다
  let x0 = null, y0 = null, axis = null;
  el.addEventListener('touchstart', (e) => {
    if (e.touches.length !== 1) { x0 = null; return; }
    x0 = e.touches[0].clientX; y0 = e.touches[0].clientY; axis = null;
  }, { passive: true });
  el.addEventListener('touchmove', (e) => {
    if (x0 === null || e.touches.length !== 1) return;
    const dx = e.touches[0].clientX - x0;
    const dy = e.touches[0].clientY - y0;
    if (axis === null && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
      axis = Math.abs(dx) > Math.abs(dy) ? 'x' : 'y';
    }
  }, { passive: true });
  el.addEventListener('touchend', (e) => {
    if (x0 === null || axis !== 'x') { x0 = null; return; }
    const dx = (e.changedTouches[0] || {}).clientX - x0;
    x0 = null;
    if (Math.abs(dx) < MIN) return;
    goMonth(dx < 0 ? 1 : -1);        // 왼쪽으로 밀면 다음 달
  }, { passive: true });
  el.addEventListener('touchcancel', () => { x0 = null; }, { passive: true });
})();

/* ── 아래로 당겨 새로고침(폰) ── (대표 요청 2026-08-27 «아래로 당기면 새로고침 되게해줭»)
   홈 화면에 담은 앱에는 사파리의 「당겨 새로고침」이 아예 없다 — 우리가 만든다.
   ⚠ 세로 스크롤·좌우로 밀어 달 넘기기와 헷갈리면 안 된다:
     ① 화면 **맨 위**에서 시작한 손짓만 받는다 (중간에서 훑어 올리는 것을 가로채면 안 된다)
     ② 처음 8px 로 가로·세로를 정하고 **세로 + 아래쪽** 일 때만 당긴다
     ③ 팝업이 떠 있으면 손대지 않는다
   ⚠ touchmove 를 passive 로 두면 안 된다 — 고무줄처럼 튕기는 것을 막아야 당겨진다.
      대신 당기는 중이 아니면 첫 줄에서 바로 빠져나온다 (스크롤이 굼떠지지 않게) */
(function pullRefresh() {
  const OFF = 50;                  // 평소엔 이만큼 위로 숨어 있다
  const MAX = 96;                  // 이보다 더 당겨도 안 내려온다
  const ON = 56;                   // 이만큼 당기고 놓으면 새로고침
  const bar = document.createElement('div');
  bar.className = 'sc-pull';
  bar.innerHTML = '<span class="sc-pull-c"><i></i><b>당기면 새로고침</b></span>';
  document.body.appendChild(bar);
  const txt = bar.querySelector('b');

  let y0 = null, x0 = 0, axis = null, dist = 0, busy = false;
  const atTop = () => (window.scrollY || document.documentElement.scrollTop || 0) <= 0;
  const put = (d, o) => {
    bar.style.transform = 'translateY(' + (Math.min(d, MAX) - OFF) + 'px)';
    bar.style.opacity = String(o);
  };
  const reset = () => {
    bar.classList.remove('ready', 'go');
    bar.style.transform = ''; bar.style.opacity = '';
    txt.textContent = '당기면 새로고침';
    y0 = null; axis = null; dist = 0;
  };

  document.addEventListener('touchstart', (e) => {
    if (busy || e.touches.length !== 1 || !atTop()) { y0 = null; return; }
    if (document.querySelector('.sc-modal:not([hidden])')) { y0 = null; return; }
    y0 = e.touches[0].clientY; x0 = e.touches[0].clientX; axis = null; dist = 0;
  }, { passive: true });

  document.addEventListener('touchmove', (e) => {
    if (y0 === null || e.touches.length !== 1) return;
    const dy = e.touches[0].clientY - y0;
    const dx = e.touches[0].clientX - x0;
    if (axis === null) {
      if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
      axis = Math.abs(dy) > Math.abs(dx) ? 'y' : 'x';
    }
    if (axis !== 'y' || dy <= 0 || !atTop()) { reset(); return; }
    e.preventDefault();            // 고무줄처럼 튕기는 것을 막아야 당겨진다
    dist = dy * 0.6;               // 손가락보다 천천히 — 당기는 손맛
    put(dist, Math.min(1, dist / ON));
    const ready = dist >= ON;
    bar.classList.toggle('ready', ready);
    txt.textContent = ready ? '놓으면 새로고침' : '당기면 새로고침';
  }, { passive: false });

  document.addEventListener('touchend', () => {
    if (y0 === null) return;
    const go = dist >= ON;
    y0 = null; axis = null;
    if (!go) { reset(); return; }
    busy = true;
    bar.classList.add('go');
    txt.textContent = '새로고침 중…';
    put(ON, 1);
    Promise.resolve(refreshAll()).catch(() => {}).then(() => { busy = false; reset(); });
  }, { passive: true });

  document.addEventListener('touchcancel', () => { if (y0 !== null) reset(); }, { passive: true });
})();

load();

/* 사용안내 팝업 (대표 요청)
   · 처음 오면 저절로 뜬다. 닫아도 다음에 또 뜬다 — 작가가 규칙을 알아야 해서
   · [그만 띄우기] 를 누른 기기에서만 저절로 뜨지 않는다
   · 어느 경우든 인사말 옆 ? 아이콘을 누르면 다시 열린다
   저장이 막힌 기기(사파리 비공개 모드 등)에서도 화면은 그대로 돌아가야 한다 */
const HELP_KEY = 'otb_sc_help';
const helpMuted = () => { try { return localStorage.getItem(HELP_KEY) === 'shut'; } catch (e) { return false; } };

function helpInit() {
  const modal = $('helpModal'), ic = $('helpIc');
  if (!modal || !ic || modal.dataset.bound) return;
  modal.dataset.bound = '1';
  const open = () => { modal.hidden = false; };
  const close = () => { modal.hidden = true; };
  ic.addEventListener('click', open);
  $('helpClose').addEventListener('click', close);
  $('helpX').addEventListener('click', close);
  $('helpStop').addEventListener('click', () => {
    try { localStorage.setItem(HELP_KEY, 'shut'); } catch (e) { /* 저장이 막힌 기기 */ }
    close();
  });
  modal.addEventListener('click', (e) => { if (e.target === modal) close(); });
  if (!helpMuted()) open();
}
