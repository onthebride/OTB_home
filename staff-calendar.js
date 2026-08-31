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
  loadTodo();          // 확인할 것 — 숫자 뱃지와 맨 위 안내 박스를 만든다
  clearBadge();        // 화면을 열었으니 아이콘 숫자를 지운다
  seenMark();          // 열었다는 것만 남긴다 (대표가 열어본 것은 빼고)
  show($('mainCard'));
  // 언제·며칠 것을 받아왔는지 적어둔다 — 폰으로 돌아왔을 때 다시 받을지 여기서 판단한다
  lastLoad = Date.now();
  lastDay = krDay();
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

/* ===== 폰으로 돌아오면 다시 불러온다 (대표 요청 2026-08-29 «넣자그거»)
   대표 «이거 내일되면 내일 스케줄 뜨는겨?» — 서버는 «오늘 이후 가장 가까운 예식 날» 을
   주므로 자정을 넘기면 바뀐다. 그런데 화면은 열 때 한 번만 받아온다.
   앱을 켜둔 채 밤을 넘기면 **어제 예식이 그대로 떠 있었다.**

   ⚠ 보일 때마다 부르면 안 된다 — 키보드가 오르내리거나 잠깐 다른 앱을 봤다 와도
     visibilitychange 가 뜬다. 그래서 둘 중 하나일 때만 부른다.
       ① 한국 날짜가 바뀌었다 (이게 진짜 이유다 — 「다음 촬영」이 넘어가야 한다)
       ② 마지막으로 받아온 지 5분이 지났다 (그 사이 배정이 바뀌었을 수 있다)
   ⚠ bfcache 로 되살아나면 visibilitychange 가 안 뜨는 기기가 있어 pageshow 도 같이 본다.
   ⚠ 이 자리에는 «판단» 만 둔다. document.addEventListener 는 파일 맨 아래 load() 옆에 건다 —
     여기 두면 화면 시험들이 이 대목을 잘라 돌릴 때 document 가 없어 통째로 터진다 */
const krDay = () => new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10);
let lastLoad = 0;
let lastDay = krDay();
const STALE = 5 * 60e3;

function refreshIfStale() {
  if (!sb || !staffId) return;
  if ($('mainCard') && $('mainCard').hidden) return;   // 아직 못 불러온 화면이면 놔둔다
  const dayChanged = krDay() !== lastDay;
  if (!dayChanged && Date.now() - lastLoad < STALE) return;
  refreshAll().catch(() => {});
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
/* 상품과 촬영 옵션 (대표 2026-08-31). 대표가 카톡에 붙이시던 글에서 캘린더에 없던 둘이다.
   ⚠ 옵션은 **촬영에 관계된 것만** 온다 — 앨범·출장·대표지정은 서버가 아예 안 보낸다
     (대표 «앨범 플러스 같은거 빼고 연회장 2부 폐백 2인촬영 옵션들은 보여»).
     여기서 거르지 않는다. 거르는 곳이 둘이 되면 한쪽만 고쳐진다 */
function prodRow(x) {
  const opts = Array.isArray(x.opts) ? x.opts : [];
  if (!x.product && !opts.length) return '';
  return '<div class="sc-nx-prod">'
    + (x.product ? `<b>${esc(x.product)}</b>` : '')
    + opts.map((o) => `<span class="sc-opt${o === '2인 촬영' ? ' two' : ''}">${esc(o)}</span>`).join('')
    + '</div>';
}

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
    ${prodRow(x)}
    ${extra || ''}
  </div>`;
}

const whenWord = (days) => (days === 0 ? '오늘' : days === 1 ? '내일' : `${days}일 뒤`);

/* 하루치 — 날짜 줄과 그 아래 목록. 첫째 날과 그 뒤 날들이 **같은 모양**을 쓴다 */
function nextDay(day, i, shut) {
  const d = new Date(String(day.wedding_date) + 'T00:00:00');
  const items = day.items || [];
  return `
    <button type="button" class="sc-next-m${shut ? ' shut' : ''}" data-nx="${i}"
      aria-expanded="${shut ? 'false' : 'true'}" aria-controls="scNextB${i}">
      <span>${d.getMonth() + 1}월 ${d.getDate()}일(${DOW[d.getDay()]})${
        items.length > 1 ? ` <em>${items.length}건</em>` : ''}${
        i > 0 ? ` <b class="sc-next-w">${esc(whenWord(day.days))}</b>` : ''}</span><i></i>
    </button>
    <div class="sc-next-b" id="scNextB${i}"${shut ? ' hidden' : ''}>${
      items.map((x) => shootRow(x)).join('')}</div>`;
}

function renderNext(n) {
  const box = $('scNext');
  if (!box) return;
  if (!n || !n.items || !n.items.length) { box.hidden = true; box.innerHTML = ''; return; }

  // 날짜 줄을 눌러 그 아래를 접는다 (대표 «다음 촬영 날짜 밑으로는 접을 수 있게 해줘»).
  // 접혀 있어도 날짜와 몇 건인지는 남는다 — 그것까지 감추면 무엇을 폈는지 알 수 없다.
  //
  // ⚠ 이틀 뒤까지 보여준다 (대표 2026-08-29 «2틀전스케줄부터 보여주면 될거 같아»).
  //   서버가 첫째 날은 next 로, 그 뒤 날들은 next.more 로 준다.
  //   첫째 날만 «접었던 대로» 를 기억한다. 뒤 날들은 늘 접힌 채로 시작한다 —
  //   카드가 길어지면 아래 달력이 밀려 내려가 정작 달력을 못 본다
  const days = [n].concat(n.more || []);
  const shut = nextShut();
  box.hidden = false;
  box.innerHTML = `
    <p class="sc-next-l">다음 촬영<i>${esc(whenWord(n.days))}</i></p>
    ${days.map((day, i) => nextDay(day, i, i === 0 ? shut : true)).join('')}`;

  box.querySelectorAll('[data-nx]').forEach((tg) => {
    const i = tg.dataset.nx;
    const bd = $('scNextB' + i);
    if (!bd) return;
    tg.addEventListener('click', () => {
      const off = !bd.hidden;                  // 지금 펴 있으면 접는다
      bd.hidden = off;
      tg.classList.toggle('shut', off);
      tg.setAttribute('aria-expanded', off ? 'false' : 'true');
      // 기억해 두는 것은 첫째 날뿐 (뒤 날들은 다음에 와도 접힌 채로 시작한다)
      if (i === '0') {
        try { localStorage.setItem(NEXT_KEY, off ? 'shut' : 'open'); } catch (e) { /* 저장이 막힌 기기 */ }
      }
    });
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

/* 어디서 보고 있나 — 알림 켜기와 홈 화면 추가가 같은 것을 봐야 한다.
   ⚠ 카카오톡 링크를 누르면 **카톡 안의 브라우저**가 열린다. 홈에 저장한 앱이 아니다.
     (아이폰은 절대 안 넘어가고, 안드로이드도 카톡이 자기 브라우저로 연다)
     보는 것과 확인하는 것은 거기서도 다 되지만, 알림 켜기·홈 추가는 안 된다 */
const UA = (typeof navigator !== 'undefined' && navigator.userAgent) || '';
const IN_APP = /KAKAOTALK|NAVER|Instagram|FBAN|FBAV|Line\//i.test(UA);
const IS_IOS = /iPhone|iPad|iPod/i.test(UA)
  || (typeof navigator !== 'undefined' && navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

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
    // 글자는 스위치 밖으로 뺐다 (대표 2026-08-29 «글자는 꺼내주고 그 옆에 토글 스위치»).
    // 줄 전체가 켜짐/꺼짐을 같이 입는다 — 글자 색도 따라간다
    const row = $('setPushRow');
    if (row) row.classList.toggle('on', on);
    const lab = $('setPushLbl');
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
  /* ⚠ 카카오톡 링크를 누르면 **카톡 안의 브라우저**가 열린다. 홈에 저장한 앱이 아니다.
       거기서는 알림을 켤 수 없다 — 켜지는 듯해도 카톡 브라우저에만 붙어서 곧 사라진다.
       아무 말 없이 실패하면 작가님이 「켰는데 왜 안 와요」 하시게 된다. 먼저 막고 알린다.
       (홈 화면 추가도 같은 이유로 안 된다 — a2hs 가 같은 안내를 한다) */
  if (IN_APP) {
    pushMsg = '카카오톡 안에서는 알림을 켤 수 없어요.\n오른쪽 위 ⋮ 메뉴에서 '
      + (IS_IOS ? 'Safari' : 'Chrome') + '로 연 뒤에 켜주세요.';
    syncPush();
    return;
  }
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
  $('helpBody').hidden = cur !== 'help';
}

/* 칸을 연다. 손으로 눌러서든(tabsInit), 위 안내 박스의 「확인하러 가기」 로든
   **여기 하나만** 쓴다 — 두 곳에서 따로 열면 딱지(active)와 몸통이 어긋난다 */
function openTab(cur) {
  const tabs = $('scTabs');
  if (!tabs) return;
  const b = tabs.querySelector(`.sc-tab[data-sct="${cur}"]`);
  if (!b || b.hidden) return;
  tabs.querySelectorAll('.sc-tab').forEach((x) => x.classList.toggle('active', x === b));
  applyTab(cur);
  if (cur === 'me' && !meLoaded) { meLoaded = true; loadMe(); }
  if (cur === 'set') renderSet();
  if (cur === 'nt') renderNotices();
}

function tabsInit() {
  const tabs = $('scTabs');
  if (!tabs || tabs.dataset.on) return;
  tabs.dataset.on = '1';
  tabs.addEventListener('click', (e) => {
    const b = e.target.closest('.sc-tab');
    if (!b) return;
    openTab(b.dataset.sct);                    // cal | nt | me | set
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

/* ===== 확인할 것 (대표 2026-08-31)
   «알림은 확인으로 바꾸고 확인할게 있으면 캘린더 상단에 확인할 사항이 있습니다. 라고
     안내박스가 가는거야 그리고 확인 글자에 숫자뱃지»
   «월요일 체크나 금요일 설문체크도 캘린더 기반으로 하고 싶어»

   흩어져 있던 셋을 한 곳으로 모은다 — 알림함 · 월요일 체크 페이지 · 설문 페이지.
   ⚠ 숫자는 **서버가 센다**(staff_todo 의 n). 화면에서 또 세면 «뱃지는 3인데 안에는 2개»
     가 된다. 목록과 숫자가 같은 함수에서 나와야 한다 */
let todo = null;

async function loadTodo() {
  if (!sb || !staffId) return;
  const { data, error } = await sb.rpc('staff_todo', { p_staff_id: staffId });
  if (error || !data) return;
  todo = data;
  ntBadge();
  renderTopTodo();
  if (curTab() === 'nt') renderNotices();
}

async function loadNotices(page) {
  if (!sb || !staffId) return;
  // 「지난 소식」은 **읽은 것만**. 안 읽은 것은 위 「확인이 필요해요」가 들고 있다 —
  // 두 곳에 같은 줄이 뜨면 «아까 확인했는데 왜 또 있지» 가 된다
  const { data, error } = await sb.rpc('staff_notices',
    { p_staff_id: staffId, p_page: page || ntPage, p_read_only: true });
  if (error || !data) return;
  ntData = data;
  ntPage = data.page;
  renderNotices();
}

// 확인 안 한 수는 칸 이름 옆에. 0 이면 딱지를 아예 없앤다
function ntBadge() {
  const el = $('ntCount');
  if (!el) return;
  const n = (todo && todo.n) || 0;
  el.hidden = !n;
  el.textContent = n > 99 ? '99+' : String(n);
}

/* 확인할 것 한 줄. 무엇이냐에 따라 누를 것이 다르다
     check  — 세 가지를 체크하고 「확인 완료」 (월요일 체크와 같은 것)
     survey — 신부 설문을 보고 「확인했어요」
     notice — 배정·변경·취소·공지. 읽었다고 누르면 「지난 소식」으로 내려간다 */
function todoItem(r) {
  const head = `<p class="sc-td-t">${esc(r.title)}`
    + (r.role ? `<em class="sc-td-role${r.role === '서브' ? ' sub' : ''}">${esc(r.role)}</em>` : '')
    + (r.at ? `<span>${esc(r.at)}</span>` : '') + '</p>'
    + (r.body ? `<p class="sc-td-b">${esc(r.body)}</p>` : '');

  if (r.kind === 'check') {
    /* 글귀는 월요일 체크 페이지와 **똑같이** 둔다. 작가님들이 그 말로 익혀 두셨다 */
    const cb = (k, t) => `<label class="sc-td-chk"><input type="checkbox" data-k="${k}" /><span>${t}</span></label>`;
    return `<div class="sc-td check" data-b="${esc(r.booking_id)}">${head}
      ${cb('attend', '참석 / 스케줄 확정')}
      ${cb('arrival', '도착 시간 숙지 (예식 1시간 30분 전)')}
      ${cb('options', '촬영 옵션 확인')}
      <button type="button" class="btn-sm sc-td-go" data-do="check">확인 완료</button>
    </div>`;
  }
  if (r.kind === 'survey') {
    return `<div class="sc-td survey" data-b="${esc(r.booking_id)}">${head}
      <div class="sc-td-acts">
        <a class="btn-sm sc-td-sv" href="/survey-view?b=${encodeURIComponent(r.booking_id)}&s=${encodeURIComponent(staffId)}">설문 보기</a>
        <button type="button" class="btn-sm sc-td-go" data-do="survey">확인했어요</button>
      </div>
    </div>`;
  }
  return `<div class="sc-td notice">${head}
    <button type="button" class="btn-sm sc-td-go" data-do="notice" data-nt="${r.notice_id}">확인했어요</button>
  </div>`;
}

function renderNotices() {
  ntBadge();
  const box = $('ntBody');
  if (!box) return;
  const items = (todo && todo.items) || [];
  const rows = (ntData && ntData.rows) || [];

  const todoBox = items.length
    ? `<section class="sc-tdwrap">
         <h3 class="sc-td-h">확인이 필요해요 <i>${items.length}</i></h3>
         ${items.map(todoItem).join('')}
       </section>`
    /* ⚠ 월요일 체크·설문 확인은 여기 안 뜬다 (대표 2026-08-31 «확인에 띄우지 말고»).
         그것들은 알림톡이 데려가는 페이지에서 한다. 없는 것을 여기 적으면 안 된다 */
    : '<p class="sc-nt-empty">확인하실 것이 없어요. 🙂<br />예식이 새로 배정되거나 바뀌거나 취소되면 여기에 모입니다.</p>';

  if (!rows.length) { box.innerHTML = todoBox; bindTodo(); return; }

  // 이미 확인한 것은 아래에 「지난 소식」으로 (대표 지시 — 확인한 건 보통으로)
  const item = (r) => `
    <div class="sc-nt-item">
      <p class="sc-nt-t">${esc(r.title)}<span>${esc(r.at)}</span></p>
      <p class="sc-nt-b">${esc(r.body)}</p>
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

  box.innerHTML = todoBox + `
    <section class="sc-pastwrap">
      <h3 class="sc-td-h past">지난 소식 <i>${ntData.total}</i></h3>
      <div class="sc-nt-list">${rows.map(item).join('')}</div>
      ${pg > 1 ? `<div class="sc-pg">
        <button type="button" class="sc-pg-a" data-ntp="${ntPage - 1}"${ntPage <= 1 ? ' disabled' : ''}>‹</button>
        ${nums.join('')}
        <button type="button" class="sc-pg-a" data-ntp="${ntPage + 1}"${ntPage >= pg ? ' disabled' : ''}>›</button>
      </div>` : ''}
    </section>`;

  bindTodo();
  box.querySelectorAll('[data-ntp]').forEach((b) =>
    b.addEventListener('click', () => { if (!b.disabled) loadNotices(Number(b.dataset.ntp)); }));
}

/* 「확인이 필요해요」의 단추들. 무엇을 눌렀느냐에 따라 부르는 곳이 다르다 */
function bindTodo() {
  const box = $('ntBody');
  if (!box) return;
  box.querySelectorAll('.sc-td-go').forEach((b) =>
    b.addEventListener('click', () => todoDo(b)));
}

async function todoDo(btn) {
  const card = btn.closest('.sc-td');
  const what = btn.dataset.do;
  const bid = card && card.dataset.b;
  btn.disabled = true;
  let err = null;

  if (what === 'check') {
    // ⚠ 셋을 다 체크해야 확인이다. 월요일 체크 페이지와 같은 규칙이라야 한다
    const on = (k) => !!card.querySelector(`input[data-k="${k}"]`).checked;
    if (!(on('attend') && on('arrival') && on('options'))) {
      btn.disabled = false;
      toastNt('세 가지를 모두 체크해 주세요.');
      return;
    }
    ({ error: err } = await sb.rpc('submit_assignment_check', {
      payload: { booking_id: bid, staff_id: staffId, attend: true, arrival: true, options: true },
    }));
  } else if (what === 'survey') {
    ({ error: err } = await sb.rpc('survey_ack', { p_booking_id: bid, p_staff_id: staffId }));
  } else {
    ({ error: err } = await sb.rpc('staff_notice_read',
      { p_staff_id: staffId, p_page: ntPage, p_id: Number(btn.dataset.nt) }));
  }

  btn.disabled = false;
  if (err) { toastNt('저장하지 못했어요. 잠시 후 다시 해주세요.'); return; }
  // 셋 다 같은 곳을 다시 그린다 — 확인한 것은 목록에서 빠지고 숫자가 하나 준다
  await Promise.all([loadTodo(), loadNotices(ntPage)]);
  clearBadge();
}

function toastNt(msg) {
  const box = $('ntBody');
  if (!box) return;
  let el = box.querySelector('.sc-td-toast');
  if (!el) {
    el = document.createElement('p');
    el.className = 'sc-td-toast';
    box.prepend(el);
  }
  el.textContent = msg;
  clearTimeout(toastNt._t);
  toastNt._t = setTimeout(() => el.remove(), 3000);
}

async function ntRead(id) {
  const args = { p_staff_id: staffId, p_page: ntPage };
  if (id != null) args.p_id = id;
  const { data, error } = await sb.rpc('staff_notice_read', args);
  if (error || !data) return;
  ntData = data;
  ntPage = data.page;
  renderNotices();
  loadTodo();          // 위 안내 박스와 숫자 뱃지도 같이 줄어야 한다
  clearBadge();        // 다 확인했으면 홈 화면 아이콘 숫자도 지운다
}

/* ===== 맨 위 안내 박스 =====
   2026-08-29 대표 «내가 보내는 공지랑 비활성화 안내는 중요공지니까 캘린더 상단에 바로
   보이게 뜨게해줘» 로 만들었고, 그때는 중요 공지 셋만 띄웠다(staff_top_notices).

   2026-08-31 대표 «확인할게 있으면 캘린더 상단에 확인할 사항이 있습니다. 라고 안내박스가
   가는거야» 로 **확인할 것 전부**를 세게 바뀌었다. 월요일 체크·설문 확인이 빠져 있던 것을
   메운 것이다. 그래서 staff_top_notices 는 이제 화면이 안 쓴다 — staff_todo 하나가 준다.
   ⚠ 위쪽은 좁다 — 셋까지만 적고 나머지는 「확인」 칸에서 본다 */

/* 대표 2026-08-31 «확인할게 있으면 캘린더 상단에 확인할 사항이 있습니다. 라고 안내박스가
   가는거야». 그래서 이 자리는 이제 **확인할 것 전부**를 센다 (staff_todo).
   전에는 중요 공지 셋만 띄웠는데, 월요일 체크·설문 확인이 빠져 있었다.
   ⚠ 위쪽은 좁다 — 셋까지만 적고 나머지는 「확인」 칸에서 본다 */
function renderTopTodo() {
  const box = $('scTopNt');
  if (!box) return;
  const items = (todo && todo.items) || [];
  box.hidden = items.length === 0;
  if (!items.length) { box.innerHTML = ''; return; }
  const three = items.slice(0, 3);
  box.innerHTML = `
    <div class="sc-tn warn">
      <p class="sc-tn-t">확인하실 것이 ${items.length}개 있습니다</p>
      <ul class="sc-tn-l">${three.map((r) =>
        `<li><b>${esc(r.title)}</b>${r.body ? `<span>${esc(r.body)}</span>` : ''}</li>`).join('')}
        ${items.length > 3 ? `<li class="more">그 밖에 ${items.length - 3}개</li>` : ''}
      </ul>
      <button type="button" class="btn-sm sc-tn-ok" id="scTodoGo">확인하러 가기</button>
    </div>`;
  const go = $('scTodoGo');
  if (go) go.addEventListener('click', () => openTab('nt'));
}

/* ===== 설정 (대표 요청 2026-08-27
   «작가별 설정탭을 하나 더 추가해줘 / 거기에 알람여부도 넣고 / 스케줄을 계속 받을지
     그만받을지도 토글 넣어줘 / 지정비용을 넣을 수 있게 해주고 /
     지정비용은 우리랑 촬영 후 후기가 5개이상 쌓여야지만 비용을 넣을 수 있게 해줘»)

   2026-08-30 대표 «일단 열고 지정시스템은 추후 공개예정이라고 하면 되지머» 로
   **모든 작가에게** 열었다. (그 전에는 대표 캘린더에만 떴다)
   ⚠ 여기를 다시 막으면 안 된다. 자동 멈춤 안내가 「설정에서 스케줄 받기를 켜주세요」
     라고 하는데, 설정이 안 보이면 작가님이 그대로 할 수가 없다.
   ⚠ 후기 5건 문턱은 **서버가 막는다** — 화면만 잠그면 개발자도구로 그냥 부를 수 있다 */
let setData = null;

async function settingsInit() {
  if (!sb || !staffId) return;
  const { data, error } = await sb.rpc('staff_settings', { p_staff_id: staffId });
  if (error || !data) return;
  setData = data;
  const b = document.querySelector('.sc-tab[data-sct="set"]');
  if (b) b.hidden = false;
}

const wonFmt = (n) => Number(n || 0).toLocaleString('ko-KR');

/* ===== 지정 촬영 요건 (대표 2026-08-30)
   «온더브라이드 스케줄을 최소 3회 이상 촬영 / 후기 3개 이상 /
     신부님들 yes하신 촬영건 중 갤러리에 10장이상 올라가야함»

   ⚠ 숫자는 **서버에서 받아 쓴다**(`d.elig`). 여기에 3·3·10 을 적어두면 대표가 요건을
     바꾸실 때 화면과 서버가 어긋난다 — 「화면엔 됐다는데 저장이 안 된다」 가 된다.
     못 받았을 때만 옛 값으로 버틴다 */
const baseOf = (d) => (d && d.base) || 250000;
const taxOf = (d) => (d && d.tax_bp) || 330;
// 3.3% 를 뗀 실수령. 원 단위로 버린다
const netPay = (d, total) => Math.floor(total * (10000 - taxOf(d)) / 10000);

function reqList(d) {
  const e = d.elig;
  if (!e) return '';
  const rows = [
    ['우리 촬영', e.shots, e.need_shots, '회'],
    ['후기', e.reviews, e.need_reviews, '개'],
    ['갤러리 사진', e.gallery, e.need_gallery, '장'],
  ];
  const li = rows.map(([nm, now, need, unit]) => {
    const done = now >= need;
    const rest = need - now;
    return `<li class="${done ? 'ok' : 'no'}"><i aria-hidden="true">${done ? '✓' : '·'}</i>`
      + `<b>${nm}</b><span>${now}${unit}`
      + (done ? '' : ` <em>${rest}${unit} 더</em>`) + `</span></li>`;
  }).join('');
  // 셋을 다 채웠는데도 안 되는 경우는 「스케줄 받기」 를 꺼두신 때뿐이다
  const shut = e.ok === false && e.accepting === false;
  return `<div class="sc-req${d.can_fee ? ' done' : ''}">
      <p class="sc-req-t">${d.can_fee ? '지정을 받으실 수 있어요.' : '지정을 받으시려면'}</p>
      <ul>${li}</ul>
      ${shut ? '<p class="sc-req-shut">지금은 <b>스케줄 받기</b>가 꺼져 있어요. 켜시면 지정도 함께 열립니다.</p>' : ''}
    </div>`;
}

/* 지금 얼마로 되어 있나 + 3.3% 를 뗀 실수령
   (대표 2026-08-30 «지정비는 전체페이에대한 비용이야 / 차차 지금 페이도 세금공제 할 예정») */
function feeNow(d) {
  if (d.pick_fee == null) return '아직 안 정하셨어요.';
  if (d.pick_fee === 0) return '지금은 <b>안 받는 것</b>으로 되어 있어요.';
  const total = baseOf(d) + d.pick_fee;
  return `지금 <b>${wonFmt(d.pick_fee)}원</b> — 신부님이 지정하시면 <b>${wonFmt(total)}원</b>이 나갑니다.`
    + `<br />세금 3.3%를 떼고 <b>${wonFmt(netPay(d, total))}원</b>을 받으세요.`;
}

function renderSet() {
  const box = $('setBody');
  if (!box) return;
  const d = setData;
  if (!d) { box.innerHTML = '<p class="sv-sub">설정을 불러오지 못했어요.</p>'; return; }
  const fee = d.pick_fee == null ? '' : d.pick_fee;

  box.innerHTML = `
    <div class="sc-set">
      <section class="sc-set-row">
        <div class="sc-set-head">
          <h3>알림</h3>
          <div class="sc-swrow" id="setPushRow">
            <b class="sc-sw-lbl" id="setPushLbl">불러오는 중</b>
            <button type="button" class="sc-sw" id="setPushSw" role="switch"
              aria-checked="false" aria-label="알림 받기"><span class="sc-sw-k"></span></button>
          </div>
        </div>
        <p class="sc-set-d">예식이 <b>바뀌거나 취소</b>되면 폰으로 알려드려요.<br />
          <b>한 기기에서만</b> 받아요 — 다른 기기에서 켜면 이전 기기는 꺼집니다.</p>
        <p class="sc-set-msg" id="setPushMsg" hidden></p>
      </section>

      <section class="sc-set-row">
        <div class="sc-set-head">
          <h3>스케줄 받기</h3>
          <div class="sc-swrow${d.accepting ? ' on' : ''}">
            <b class="sc-sw-lbl">${d.accepting ? '받는 중' : '쉬는 중'}</b>
            <button type="button" class="sc-sw${d.accepting ? ' on' : ''}" id="setAccept"
              role="switch" aria-checked="${d.accepting ? 'true' : 'false'}"
              aria-label="스케줄 받기"><span class="sc-sw-k"></span></button>
          </div>
        </div>
        <p class="sc-set-d">꺼두면 <b>새 예식이 배정되지 않아요.</b> 쉬실 때 꺼두세요.<br />
          <b>이미 배정된 예식은 그대로 진행</b>해 주세요. 어려우시면 대표와 상의해 주세요.</p>
      </section>

      <section class="sc-set-row">
        <h3>지정 촬영비</h3>
        <!-- 대표 요청 2026-08-29. 아직 지정 예약을 안 받고 있어서, 금액만 적어두고
             «왜 지정이 안 들어오지» 하고 기다리시지 않게 먼저 알린다 -->
        <p class="sc-set-soon">지정 촬영은 <b>빠른 시일 내에 도입될 예정</b>입니다.<br />
          ${d.can_fee ? '미리 정해두시면 시작하는 날 바로 반영돼요.'
            : '도입 전까지 아래를 채우시면 그때 정하실 수 있어요.'}</p>
        <p class="sc-set-d">신부님이 <b>작가님을 지정</b>하실 때 더해지는 금액이에요.<br />
          기본 페이 <b>${wonFmt(baseOf(d))}원</b> + 지정 촬영비 = 신부님이 내시는 총액.
          안 받으시려면 <b>0</b>.</p>
        ${reqList(d)}
        ${d.can_fee ? `
        <div class="sc-fee">
          <input type="text" id="setFee" inputmode="numeric" autocomplete="off"
            value="${fee === '' ? '' : wonFmt(fee)}" placeholder="예) 30,000" />
          <span class="sc-fee-w">원</span>
          <button type="button" class="btn-sm primary" id="setFeeSave">저장</button>
        </div>
        <p class="sc-set-now" id="setFeeNow">${feeNow(d)}</p>`
        : ''}
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
    /* 요건이 모자라면 서버가 막는다. 그 말을 그대로 옮기지 않고 알아듣게 바꿔준다.
       서버는 이렇게 보낸다:
         not eligible: shots 9/3 reviews 2/3 gallery 24/10 accepting true */
    const msg = (error && error.message) || '';
    const m = /not eligible: shots (\d+)\/(\d+) reviews (\d+)\/(\d+) gallery (\d+)\/(\d+) accepting (\w+)/.exec(msg);
    if (m) {
      const n = m.map(Number);
      if (m[7] === 'false') { toastSet('<b>스케줄 받기</b>를 켜셔야 지정을 받으실 수 있어요.'); return; }
      const rest = [
        n[1] < n[2] && `촬영 ${n[2] - n[1]}회`,
        n[3] < n[4] && `후기 ${n[4] - n[3]}개`,
        n[5] < n[6] && `갤러리 사진 ${n[6] - n[5]}장`,
      ].filter(Boolean);
      toastSet(rest.length ? `${rest.join(' · ')}이 더 필요해요.` : '아직 요건이 모자라요.');
      return;
    }
    toastSet('저장하지 못했어요. 잠시 후 다시 해주세요.');
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
  // ⚠ 어디서 보고 있나는 **위 한 곳**에서 정한다 (IN_APP·IS_IOS).
  //   여기서 또 재면 알림 켜기와 서로 다른 말을 하게 된다
  const inApp = IN_APP, iOS = IS_IOS;
  const android = /Android/i.test(UA);
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

/* 폰으로 돌아왔을 때 다시 받아올지 refreshIfStale() 이 정한다 (위쪽에 있다).
   ⚠ 거는 곳은 여기다 — 함수 옆에 두면 화면 시험이 그 대목을 잘라 돌릴 때
     document 가 없어 통째로 터진다 (2026-08-29 에 calui.test 가 그렇게 터졌다) */
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') refreshIfStale();
});
window.addEventListener('pageshow', (e) => { if (e.persisted) refreshIfStale(); });

/* 사용안내 (대표 2026-08-31 «사용안내를 상단메뉴에 넣고 내용을 채우자»)
   전에는 팝업이었다 — 처음 한 번 뜨고 닫으면 끝이라, 나중에 「그거 어디서 봤더라」가 됐다.
   이제 「안내」 칸이다. 언제든 열어볼 수 있다.
   · 처음 오시는 분께는 이 칸을 먼저 열어드린다 (한 기기에서 한 번만)
   · 그 뒤로는 칸을 누르거나 인사말 옆 ? 를 누르면 열린다
   ⚠ 저장이 막힌 기기(사파리 비공개 모드 등)에서도 화면은 그대로 돌아가야 한다 —
     못 읽으면 «본 적 있다» 로 친다. 매번 안내부터 열리면 성가시다 */
const HELP_KEY = 'otb_sc_help';
const helpSeen = () => { try { return !!localStorage.getItem(HELP_KEY); } catch (e) { return true; } };

function helpInit() {
  const ic = $('helpIc');
  if (!ic || ic.dataset.bound) return;
  ic.dataset.bound = '1';
  ic.addEventListener('click', () => openTab('help'));
  if (!helpSeen()) {
    try { localStorage.setItem(HELP_KEY, 'seen'); } catch (e) { /* 저장이 막힌 기기 */ }
    openTab('help');
  }
}
