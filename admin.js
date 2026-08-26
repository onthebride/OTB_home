/* ===== Supabase ===== */
const sb = window.supabase.createClient(
  window.OTB_CONFIG.SUPABASE_URL,
  window.OTB_CONFIG.SUPABASE_KEY
);

const $ = (id) => document.getElementById(id);
const esc = (s) =>
  (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
  );
const won = (n) => (n == null ? '-' : Number(n).toLocaleString('ko-KR') + '만원');
// 전화번호에 하이픈 넣기. 모르는 모양은 손대지 않는다(국제번호·자릿수 안 맞는 것).
function fmtPhone(v) {
  const s = String(v == null ? '' : v);
  if (!s.trim()) return s;
  const d = s.replace(/[^0-9]/g, '');
  const cut = (a, b) => d.slice(0, a) + '-' + d.slice(a, a + b) + '-' + d.slice(a + b);
  if (/^01[016789][0-9]{7}$/.test(d)) return cut(3, 3);
  if (/^01[016789][0-9]{8}$/.test(d)) return cut(3, 4);
  if (/^02[0-9]{7}$/.test(d)) return cut(2, 3);
  if (/^02[0-9]{8}$/.test(d)) return cut(2, 4);
  if (/^0[3-6][0-9]{8}$/.test(d)) return cut(3, 3);
  if (/^0[3-6][0-9]{9}$/.test(d)) return cut(3, 4);
  if (/^1[0-9]{7}$/.test(d)) return d.slice(0, 4) + '-' + d.slice(4);
  return s;
}
// 칸을 벗어날 때 한 번 다듬는다 — 타이핑 중에 끼어들면 커서가 튄다
function hookPhone(root2) {
  (root2 || document).querySelectorAll('.js-phone').forEach((el) => {
    if (el.dataset.phoneHooked) return;
    el.dataset.phoneHooked = '1';
    el.addEventListener('blur', () => { el.value = fmtPhone(el.value); });
  });
}
const fmtDate = (s) => (s ? new Date(s).toLocaleDateString('ko-KR') : '-');
const fmtDateShort = (s) => { if (!s) return '-'; const d = new Date(s); return `${String(d.getFullYear() % 100).padStart(2, '0')}. ${d.getMonth() + 1}. ${d.getDate()}.`; };
const fmtDateTime = (s) =>
  s ? new Date(s).toLocaleString('ko-KR', { dateStyle: 'medium', timeStyle: 'short' }) : '-';

let allBookings = [];
let eventDiscounts = {}; // {booking_id: 승인된 할인 만원}
const evDc = (b) => Number(eventDiscounts[b.id]) || 0;
const effBalance = (b) => (b.total_price != null ? b.total_price - 10 - evDc(b) : null);
let filter = '전체';
let bkSearchTerm = '';
let bkMonth = null; // 예약 목록 월별 페이지 {y, m}
let surveyIds = new Set(); // 설문 제출된 예약 ID
let allUnconfirmed = []; // 작가 미확인 (admin_unconfirmed)
let alimtalkFails = []; // 알림톡 발송 실패 (admin_alimtalk_failures)
let reminders = []; // 관리자 할 일 리마인더 (admin_reminders_list)
let pricingList = []; // 상품·옵션 카탈로그 (admin_pricing_list)
let pricingMap = {}; // code → {name, price, active, ...}
let calMonth = null; // 캘린더 현재 월 {y, m}
let dayOvKey = null; // 캘린더 날짜 팝업 열린 날 {y, m, d}
let unpaidTab = 'deposit'; // 미입금 탭: deposit | balance
let allStaff = [];
let staffMap = {};
const ATK_TPLS = [['A', '계약안내'], ['B', '한달 전'], ['C', '잔금안내'], ['D', '최종안내'], ['E', '링크안내'], ['F', '입금확인'], ['G', '촬영설문']];
const notCancelled = (b) => b.status !== '취소';
const phBadge = (b) =>
  (b.rep_designation ? ' <span class="ph-badge rep">대표지정</span>' : '')
  + (b.photographer === '2인 촬영' ? ' <span class="ph-badge two">2인촬영</span>' : '');
// 색상환을 고르게 돌며 서로 멀리 떨어진 색들 — 앞쪽일수록 대비가 크다(작가 수가 적을 때 최대 구분).
// 작가 수가 이 색 개수를 넘으면 색이 한 바퀴 돌아 겹칠 수 있음 → 그때는 작가별 색 직접지정 권장.
const STAFF_COLORS = ['#2f6fae', '#cf4d4d', '#3f9d5a', '#8a52c0', '#d98a2b', '#2fa3a3', '#c04d95', '#7a6a55', '#a9a832', '#5b5bbf', '#1f7a6b', '#b5462f'];
const isHex = (c) => typeof c === 'string' && /^#[0-9a-fA-F]{6}$/.test(c);
// 작가별 색: ① 담당자 관리에서 직접 지정한 색(staff.color)이 있으면 그걸 최우선.
// ② 없으면 자동 배정 — id 해시는 두 작가가 겹칠 수 있어서, 정렬한 '자리 순서'로 팔레트 배정.
function staffColor(id) {
  if (!id) return null;
  const s = allStaff.find((x) => x.id === id);
  if (s && isHex(s.color)) return s.color;
  const ids = allStaff.map((x) => x.id).sort();
  const idx = ids.indexOf(id);
  if (idx >= 0) return STAFF_COLORS[idx % STAFF_COLORS.length];
  let h = 0; // 목록에 없는 id(삭제된 작가 등)는 해시로 대체
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
  return STAFF_COLORS[h % STAFF_COLORS.length];
}
function tint(hex, a) { // 작가 색을 옅은 배경(rgba)으로
  if (!hex || hex[0] !== '#') return 'transparent';
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
}

/* ===== Auth views ===== */
const SAVED_EMAIL_KEY = 'otb_admin_email';
const SAVED_PW_KEY = 'otb_admin_pw';   // 예전에 저장하던 자리 — 지우기만 한다
// 예전 버전이 비밀번호를 이 브라우저에 남겨뒀을 수 있다. 열자마자 지운다.
try { localStorage.removeItem(SAVED_PW_KEY); } catch (_) {}
const showLogin = () => {
  $('loginView').hidden = false;
  $('dashView').hidden = true;
  // 아이디만 자동 입력한다 (비밀번호는 저장하지 않는다)
  let savedEmail = '';
  try { savedEmail = localStorage.getItem(SAVED_EMAIL_KEY) || ''; } catch (_) {}
  if (savedEmail) $('email').value = savedEmail;
  if ($('saveCreds')) $('saveCreds').checked = !!savedEmail;
  const pw = $('password');
  if (savedEmail && pw) setTimeout(() => pw.focus(), 0);
};
const showDash = (email) => {
  $('loginView').hidden = true;
  $('dashView').hidden = false;
  $('dashUser').textContent = email || '';
  syncHeadHeight();  // 숨김 상태에선 높이가 0이라 표시 직후 다시 실측
  // 예약 데이터를 먼저 받은 뒤 탭을 복원한다. 먼저 복원하면 캘린더 같은 탭이
  // 빈 데이터로 그려진 채 남는다(loadBookings 는 캘린더를 다시 그리지 않음).
  loadBookings().then(applyHash);
  initPush();
};

// onAuthStateChange fires INITIAL_SESSION on load (handling the initial view)
// and SIGNED_IN / SIGNED_OUT thereafter — single source of truth, no race.
sb.auth.onAuthStateChange((_event, session) => {
  if (session) showDash(session.user.email);
  else showLogin();
});

/* ===== Login ===== */
$('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const btn = $('loginBtn');
  const msg = $('loginMsg');
  msg.textContent = '';
  btn.disabled = true;
  btn.textContent = '로그인 중...';
  const email = $('email').value.trim();
  const { error } = await sb.auth.signInWithPassword({
    email,
    password: $('password').value,
  });
  btn.disabled = false;
  btn.textContent = '로그인';
  if (error) {
    msg.textContent = '로그인 실패: 이메일 또는 비밀번호를 확인해 주세요.';
  } else {
    // '저장' 체크 ON이면 아이디만 남긴다. 비밀번호는 어떤 경우에도 저장하지 않는다.
    try {
      if ($('saveCreds') && $('saveCreds').checked) localStorage.setItem(SAVED_EMAIL_KEY, email);
      else localStorage.removeItem(SAVED_EMAIL_KEY);
      localStorage.removeItem(SAVED_PW_KEY);
    } catch (_) {}
  }
});

$('logoutBtn').addEventListener('click', () => {
  try { localStorage.removeItem(SAVED_PW_KEY); } catch (_) {}
  sb.auth.signOut();
});
$('refreshBtn').addEventListener('click', () => loadBookings());

/* ===== Load + render ===== */
async function loadBookings() {
  // 모든 조회는 서로 독립적이라 한 번에 병렬로 — 순차 대기 제거(체감 속도 개선)
  const [res, sres, ures, dres, fres, rres, pres] = await Promise.all([
    sb.rpc('admin_list_bookings'),    // 예약 목록
    sb.rpc('admin_survey_ids'),       // 설문 제출 여부
    sb.rpc('admin_unconfirmed'),      // 작가 미확인
    sb.rpc('admin_event_discounts'),  // 이벤트 할인
    sb.rpc('admin_alimtalk_log'),     // 알림톡 발송 내역
    sb.rpc('admin_reminders_list'),   // 할 일 리마인더
    sb.rpc('admin_pricing_list'),     // 상품·옵션 카탈로그
    loadStaff(),                      // 작가 목록
  ]);
  const { data, error } = res;
  if (error) {
    console.error(error);
    $('bkRows').innerHTML =
      '<tr><td colspan="6" style="padding:40px;text-align:center;color:#c0392b">목록을 불러오지 못했습니다. (' +
      esc(error.message) + ')</td></tr>';
    return;
  }
  allBookings = data || [];
  surveyIds = new Set(Array.isArray(sres.data) ? sres.data : []);
  allUnconfirmed = Array.isArray(ures.data) ? ures.data : [];
  eventDiscounts = (dres.data && typeof dres.data === 'object') ? dres.data : {};
  alimtalkFails = Array.isArray(fres.data) ? fres.data : [];
  reminders = Array.isArray(rres.data) ? rres.data : [];
  pricingList = Array.isArray(pres.data) ? pres.data : [];
  pricingMap = {}; pricingList.forEach((p) => { pricingMap[p.code] = p; });
  render();
  renderDashboard();
  renderReminders();
  refreshEventBadge();
}

// 시작할 때 이벤트를 받아둔다. 예전엔 배지 숫자만 챙기면 됐지만
// 이제 홈 카드라서 목록까지 그려야 한다 (2026-08-24)
async function refreshEventBadge() {
  await loadEvents();
}

// 작가 평가 점수를 받아둔다 — 배정 드롭다운에서 이름 옆에 보여준다 (대표 요청 2026-08-24).
// 전체 기간으로 본다. 배정할 때 궁금한 건 «이 사람이 어떤 작가인가» 라 기간을 좁힐 이유가 없다
async function loadStaffScores() {
  const { data, error } = await sb.rpc('admin_feedback', { p_days: 3650 });
  if (error || !data) return;
  const byName = {};
  (data.staff || []).forEach((x) => { byName[x.staff_name] = x; });
  staffScore = {};
  allStaff.forEach((s) => {
    const v = byName[s.name];
    // 추천 의향도 같이 담는다 — 지정 근거로 보는 값이다 (2026-08-25)
    if (v) staffScore[s.id] = { score: v.avg_score, n: Number(v.n) || 0,
      rec: v.avg_rec, recN: Number(v.rec_n) || 0 };
  });
}

async function loadStaff() {
  const { data } = await sb.rpc('admin_staff_list');
  allStaff = data || [];
  staffMap = {};
  allStaff.forEach((s) => { staffMap[s.id] = s; });
  populateAssigneeSelects();
  loadStaffScores();          // 늦게 와도 된다 — 오면 다음에 그릴 때 붙는다
}
const staffName = (id) => (id && staffMap[id] ? staffMap[id].name : '');

/* 배정 충돌 — 예약id별 { 작가id: {s:'off'|'tight', d:'사유'} }
   off   = 작가가 그날을 촬영 불가로 찍음
   tight = 같은 날 다른 일정과 4시간 안에 붙음 */
let confMap = {};
const confMonths = new Set();           // 이미 불러온 달
let allowConf = false;                  // '겹쳐도 배정' 스위치
const monthKey = (y, m) => `${y}-${String(m + 1).padStart(2, '0')}`;
async function ensureConf(y, m, onLoad) {
  const key = monthKey(y, m);
  if (confMonths.has(key)) return;
  confMonths.add(key);                  // 먼저 넣어야 다시 그릴 때 또 부르지 않는다
  const last = new Date(y, m + 1, 0).getDate();
  const { data, error } = await sb.rpc('admin_assign_conflicts',
    { p_from: `${key}-01`, p_to: `${key}-${String(last).padStart(2, '0')}` });
  if (error) { confMonths.delete(key); return; }
  Object.assign(confMap, data || {});
  if (onLoad) onLoad();
}
function invalidateConf() { confMap = {}; confMonths.clear(); }
// 예약 하나에 대한 충돌표(없으면 아직 안 불러온 것)
function confOf(b) { return confMap[b && b.id] || null; }

// slot: 'main' | 'sub' — 그 자리를 맡을 수 있는 작가를 위로 올린다.
// 역할이 안 맞아도 잠그지는 않는다. 겹침과 달리 '못 하는 것'이 아니라 '보통 안 하는 것'이라서.
// 작가 평가 점수 — 배정할 때 같이 보이게 (대표 요청 2026-08-24).
// { 작가id: { score: 99.1, n: 2 } }. loadStaffScores() 가 채운다
let staffScore = {};
// 이름 뒤에 붙일 점수. 응답이 적으면 그렇다고 적는다 — 한 건짜리 100점을 곧이곧대로
// 보면 안 된다. 아직 평가가 없는 작가는 «-» 로 두고 만점으로 채우지 않는다
function scoreTag(id) {
  const v = staffScore[id];
  if (!v || v.score == null) return ' · 평가 -';
  // 추천 의향이 쌓이면 같이 보여준다. 100점 점수는 다들 만점 언저리라 안 갈리는데
  // 이건 갈린다 — 지정할 때 실제로 볼 값이다 (2026-08-25).
  // 줄 세우는 기준은 아직 점수 그대로다. 추천이 충분히 쌓이면 그때 바꾼다
  const rec = v.rec == null ? '' : ' · 추천 ' + v.rec;
  return ' · ' + v.score + '점' + rec + (v.n < FB_THIN ? '(응답 ' + v.n + ')' : '');
}

function assigneeOptions(selId, conf, slot) {
  const one = (s, extra, dis) =>
    `<option value="${s.id}"${s.id === selId ? ' selected' : ''}${dis ? ' disabled' : ''}>${esc(s.name)}${extra}</option>`;
  if (!conf && !slot) {
    return '<option value="">미배정</option>' +
      allStaff.map((s) => one(s, s.active ? '' : ' (비활성)', false)).join('');
  }
  const fits = (s) => !slot || (slot === 'sub' ? s.can_sub !== false : s.can_main !== false);
  const ok = [], bad = [], other = [], off = [];
  // 배정 가능한 사람은 점수 높은 순으로. 평가가 없는 사람은 뒤로 —
  // 만점으로 쳐서 위로 올리면 거짓말이 된다
  const byScore = allStaff.slice().sort((a, b) => {
    const x = staffScore[a.id], y = staffScore[b.id];
    const xs = x && x.score != null ? Number(x.score) : -1;
    const ys = y && y.score != null ? Number(y.score) : -1;
    return ys - xs;
  });
  byScore.forEach((s) => {
    if (!s.active) { off.push(one(s, ' (비활성)', false)); return; }
    if (!fits(s)) { other.push(one(s, scoreTag(s.id), false)); return; }
    const v = conf ? conf[s.id] : null;
    if (!v) { ok.push(one(s, scoreTag(s.id), false)); return; }
    const why = v.s === 'off' ? '불가' : '겹침';
    const d = v.d ? String(v.d) : '';
    const shortD = d.length > 16 ? d.slice(0, 16) + '…' : d;
    // 지금 배정된 작가는 잠그지 않는다 — 잠그면 되돌릴 수가 없다
    bad.push(one(s, ` · ${why}${shortD ? ' ' + esc(shortD) : ''}`, s.id !== selId && !allowConf));
  });
  const grp = (label, arr) => (arr.length ? `<optgroup label="${label}">${arr.join('')}</optgroup>` : '');
  return '<option value="">미배정</option>'
    + grp(`배정 가능 ${ok.length}명 (점수 높은 순)`, ok)
    + grp(`겹침·불가 ${bad.length}명`, bad)
    + grp(`${slot === 'sub' ? '메인 전용' : '서브 전용'} ${other.length}명`, other)
    + grp('비활성', off);
}
function populateAssigneeSelects() {
  const sa = $('schedAssignee');
  if (sa) sa.innerHTML = '<option value="">담당자 선택…</option>' +
    allStaff.filter((s) => s.active).map((s) => `<option value="${s.id}">${esc(s.name)}</option>`).join('');
}

/* ===== 예약 목록 필터 · 월 이동 헬퍼 ===== */
// 계약금 입금확인 후 이 시간(72h) 동안은 '신규' 목록에 계속 보여줌 — 입금 즉시 사라져 놓치는 것 방지
const NEW_GRACE_MS = 3 * 24 * 60 * 60 * 1000;
// 입금확인 시각: deposit_paid_at(정식) → 없으면 입금확인 알림톡(F) 발송시각으로 대체
function depositPaidAt(b) {
  const t = b.deposit_paid_at || (b.alimtalk_sent && b.alimtalk_sent.F);
  const ms = t ? Date.parse(t) : NaN;
  return Number.isNaN(ms) ? null : ms;
}
// '신규' 필터 대상: 신규 + 최근 3일 내 입금확인된 확정 건
function isNewish(b) {
  if (b.status === '신규') return true;
  if (b.status !== '확정' || !b.deposit_paid) return false;
  const ms = depositPaidAt(b);
  return ms != null && Date.now() - ms < NEW_GRACE_MS;
}
// 현재 필터·검색어에 해당하는 예약 (월 제한 없음)
function bkFiltered() {
  const term = bkSearchTerm.toLowerCase();
  return allBookings.filter((b) => {
    if (filter === '신규') { if (!isNewish(b)) return false; }
    else if (filter !== '전체' && b.status !== filter) return false;
    if (!term) return true;
    return [b.contractor_name, b.wedding_venue, b.contractor_phone, b.groom_name, b.bride_name]
      .some((v) => (v || '').toLowerCase().includes(term));
  });
}
const mKey = (y, m) => y * 12 + m;
const fromKey = (k) => ({ y: Math.floor(k / 12), m: k % 12 });
// 해당 필터의 예약이 실제로 있는 월 목록(오름차순) — 빈 달은 건너뛰기 위함
function bkMonthKeys() {
  const set = new Set();
  bkFiltered().forEach((b) => { const d = wDate(b); if (d) set.add(mKey(d.getFullYear(), d.getMonth())); });
  return [...set].sort((a, b) => a - b);
}
// 오늘 기준 가장 가까운 월(이번 달 이후 우선, 없으면 가장 최근 과거 달)
function bkNearestMonth() {
  const keys = bkMonthKeys();
  if (!keys.length) return null;
  const t = new Date();
  const now = mKey(t.getFullYear(), t.getMonth());
  const next = keys.find((k) => k >= now);
  return fromKey(next != null ? next : keys[keys.length - 1]);
}
// 예약이 있는 이전/다음 달로만 이동
function bkStepMonth(dir) {
  if (!bkMonth) return;
  const keys = bkMonthKeys();
  const cur = mKey(bkMonth.y, bkMonth.m);
  const target = dir < 0 ? keys.filter((k) => k < cur).pop() : keys.find((k) => k > cur);
  if (target == null) return;
  bkMonth = fromKey(target);
  render();
}

function render() {
  const counts = { 전체: allBookings.length, 신규: 0, 확정: 0, 미입금: 0, 취소: 0 };
  allBookings.forEach((b) => {
    if (counts[b.status] != null) counts[b.status]++;
    if (b.status !== '신규' && isNewish(b)) counts['신규']++;  // 입금확인 3일 유예분
  });
  $('c_all').textContent = counts['전체'];
  $('c_new').textContent = counts['신규'];
  if ($('c_confirm')) $('c_confirm').textContent = counts['확정'];
  if ($('c_unpaid')) $('c_unpaid').textContent = counts['미입금'];
  if ($('c_cancel')) $('c_cancel').textContent = counts['취소'];

  if (!bkMonth) {
    const t = new Date();
    bkMonth = { y: t.getFullYear(), m: t.getMonth() };
    const near = bkNearestMonth(); // 이번 달에 예약이 없으면 가장 가까운 달로
    if (near && !bkFiltered().some((b) => { const d = wDate(b); return d && d.getFullYear() === bkMonth.y && d.getMonth() === bkMonth.m; })) bkMonth = near;
  }
  const searching = !!bkSearchTerm;

  let rows = bkFiltered();

  if (searching) {
    if ($('bkMonthNav')) $('bkMonthNav').hidden = true;
    rows.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  } else {
    if ($('bkMonthNav')) $('bkMonthNav').hidden = false;
    const totalAll = rows.filter((b) => wDate(b)).length;
    rows = rows.filter((b) => { const d = wDate(b); return d && d.getFullYear() === bkMonth.y && d.getMonth() === bkMonth.m; });
    rows.sort((a, b) => (wDate(a) - wDate(b)) || (a.wedding_time || '').localeCompare(b.wedding_time || ''));
    const other = totalAll - rows.length;
    if ($('bkMonthLabel')) $('bkMonthLabel').textContent =
      `${bkMonth.y}년 ${bkMonth.m + 1}월 · ${rows.length}건` + (other > 0 ? ` (다른 달 ${other}건)` : '');
    const keys = bkMonthKeys();
    const cur = mKey(bkMonth.y, bkMonth.m);
    if ($('bkPrev')) $('bkPrev').disabled = !keys.some((k) => k < cur);
    if ($('bkNext')) $('bkNext').disabled = !keys.some((k) => k > cur);
  }
  $('emptyMsg').hidden = rows.length > 0;

  $('bkRows').innerHTML = rows
    .map((b) => {
      const opts = bookingOpts(b);
      return `<tr data-id="${b.id}">
        <td data-label="예식일">${esc(fmtDateShort(b.wedding_date))}</td>
        <td data-label="계약자">${esc(b.contractor_name || '-')}${phBadge(b)}${surveyIds.has(b.id) ? ' <span class="survey-badge" title="설문 제출됨">📝</span>' : ''}</td>
        <td data-label="예식장">${esc(b.wedding_venue || '-')}</td>
        <td data-label="작가">${esc(staffName(b.assignee_id) || '-')}</td>
        <td data-label="옵션">${opts.length ? opts.map((o) => `<span class="bk-opt">${esc(o)}</span>`).join('') : '<span class="muted">-</span>'}</td>
        <td data-label="상태"><span class="badge ${esc(b.status)}">${esc(b.status)}</span>${b.status !== '신규' && isNewish(b) ? ' <span class="bk-fresh">입금확인</span>' : ''}</td>
      </tr>`;
    })
    .join('');

  document.querySelectorAll('#bkRows tr').forEach((tr) =>
    tr.addEventListener('click', () => openDetail(tr.dataset.id))
  );
}

$('filters').addEventListener('click', (e) => {
  const btn = e.target.closest('.filter');
  if (!btn) return;
  filter = btn.dataset.f;
  document.querySelectorAll('.filter').forEach((f) => f.classList.toggle('active', f === btn));
  const near = bkNearestMonth(); // 오늘 기준 가장 가까운 해당 예약이 있는 달로 이동
  if (near) bkMonth = near;
  render();
});

if ($('bkSearch')) {
  $('bkSearch').addEventListener('input', (e) => { bkSearchTerm = e.target.value.trim(); render(); });
}
if ($('bkPrev')) {
  $('bkPrev').addEventListener('click', () => bkStepMonth(-1));
  $('bkNext').addEventListener('click', () => bkStepMonth(1));
}

/* ===== Detail modal ===== */
// 베이직(데이터형) 기본가: 상시 55만원. 단, 2026-06-24~07-05 인하기간 접수분만 49만원 유지.
// 각 예약은 접수일(created_at) 기준 단가 유지(저장된 총액·내역 보존).
const PRICE49_FROM = Date.parse('2026-06-24T01:00:00Z');
const PRICE55_AGAIN_FROM = Date.parse('2026-07-05T10:50:00Z'); // 다시 55만원으로 환원한 시점
// 49만원 인하 스킴(2026-06-24~) 접수 여부 — 촬영본 사용동의 -1만원 폐지 등 스킴 판정용
const isNewPricing = (b) => !!(b && b.created_at && Date.parse(b.created_at) >= PRICE49_FROM);
// 베이직 49만원 적용 대상: 인하기간(2026-06-24 ~ 2026-07-05) 접수분만
const isBasic49 = (b) => { const t = (b && b.created_at) ? Date.parse(b.created_at) : 0; return t >= PRICE49_FROM && t < PRICE55_AGAIN_FROM; };
// 촬영본 사용동의 -1만원 할인.
// 접수일(created_at)로 판정하면 안 된다 — 지금 데이터의 접수일은 '시스템에 옮겨 적은 날'이라
// 실제 계약 시점이 아니다. 같은 6월 9일 접수 안에도 할인 받은 건과 아닌 건이 섞여 있다.
// 그래서 그 예약의 스냅샷(line_items)에 적힌 대로만 따른다. 스냅샷이 아직 없는 예약만 규칙으로.
const USAGE_DC = '촬영본 사용동의';
function usageDcPrice(b) {
  const li = Array.isArray(b && b.line_items) ? b.line_items : null;
  if (li && li.length) { const it = li.find((x) => x && x.name === USAGE_DC); return it ? (Number(it.price) || 0) : 0; }
  return isNewPricing(b) ? 0 : -1;
}

// 앨범 1권 추가 옵션: 5만원. (2026-06-25~07-04 잠시 10만원 적용했으나 해당 기간 앨범 예약 0건 → 5만원 환원)
const albumPrice = (b) => 5;
function basicBasePrice(b) {
  if (b.package === '베이직(구)') return 50;
  if (b.package === '스페셜') return 55; // 구상품
  return isBasic49(b) ? 49 : 55; // 베이직(데이터형): 인하기간만 49, 그 외 55
}

// 상품 + 옵션을 한 카테고리로 (가격 분리표시)
// 예약 시점 스냅샷(line_items)이 있으면 그대로 사용 → 가격 변경돼도 기존 예약 보존
function productOptions(b) {
  if (Array.isArray(b.line_items) && b.line_items.length) {
    return b.line_items.map((it) => ({ name: it.name, price: Number(it.price) || 0 }));
  }
  const rows = [];
  const base = basicBasePrice(b);
  if (b.package) rows.push({ name: String(b.package).replace('(데이터형)', ''), price: base });
  if (b.travel_fee) rows.push({ name: '출장비', price: b.photographer === '2인 촬영' ? 10 : 5 });
  if (b.option_album) rows.push({ name: '앨범 1권 추가', price: albumPrice(b) });
  if (b.option_reception) rows.push({ name: '연회장 인사촬영', price: 5 });
  if (b.option_pyebaek) rows.push({ name: '폐백촬영', price: 10 });
  if (b.option_part2) rows.push({ name: '2부 촬영', price: 10 });
  (Array.isArray(b.custom_options) ? b.custom_options : []).forEach((o) => { if (o && o.name) rows.push({ name: o.name, price: Number(o.price) || 0 }); });
  if (b.photographer === '2인 촬영') rows.push({ name: '2인 촬영', price: 25 });
  if (b.rep_designation) rows.push({ name: '대표지정', price: 35 });
  if (b.photo_usage_agree && usageDcPrice(b)) rows.push({ name: USAGE_DC, price: usageDcPrice(b) });
  return rows;
}
function productOptionsHtml(b) {
  const rows = productOptions(b);
  if (!rows.length) return '<span class="dv">없음</span>';
  return '<div class="po-list">' + rows.map((r) =>
    `<div class="po-row"><span class="po-nm">${esc(r.name)}</span><span class="po-pr">${won(r.price)}</span></div>`).join('') + '</div>';
}

/* ===== 상품·가격 관리 (카탈로그) ===== */
// 카탈로그 현재 단가
const catPrice = (code, dflt) => { const c = pricingMap[code]; return c && c.price != null ? c.price : dflt; };
// 수정폼 단가: 이 예약 스냅샷에 있으면 그 값(기존 예약 보존), 없으면 현재 카탈로그가
function editPrice(b, name, code) {
  const snap = Array.isArray(b.line_items) ? b.line_items.find((it) => it.name === name) : null;
  if (snap && snap.price != null) return Number(snap.price) || 0;
  return catPrice(code, 0);
}
// 앨범 추가 수량·단가: line_items 스냅샷 우선(신규 예약), 없으면 boolean(과거=1권)
function albumSnap(b) {
  const li = Array.isArray(b.line_items) ? b.line_items : [];
  const it = li.find((x) => x && /앨범/.test(x.name || ''));
  if (it) {
    const cat = catPrice('album', 5) || 5;
    const qty = (it.qty != null) ? Math.max(0, parseInt(it.qty, 10) || 0)
                                 : Math.max(1, Math.round((Number(it.price) || 0) / cat));
    const unit = qty > 0 ? Math.round((Number(it.price) || 0) / qty) : cat;
    return { qty, unit: unit || cat };
  }
  return { qty: b.option_album ? 1 : 0, unit: catPrice('album', 5) || 5 };
}
function renderPricing() {
  const wrap = $('pricingList');
  if (!wrap) return;
  if (!pricingList.length) { wrap.innerHTML = '<p class="empty">불러오는 중…</p>'; return; }
  const kindLabel = { product: '상품', option: '옵션', photographer: '작가' };
  wrap.innerHTML = pricingList.map((p) => `
    <div class="pr-row${p.editable ? '' : ' locked'}" data-code="${p.code}">
      <input class="pr-name" value="${esc(p.name)}" ${p.editable ? '' : 'disabled'} />
      <span class="pr-kind">${kindLabel[p.kind] || esc(p.kind)}${p.is_core ? '' : ' · 추가'}</span>
      <div class="pr-price"><input class="pr-price-in" type="number" min="0" value="${p.price}" ${p.editable ? '' : 'disabled'} /><span>만원</span></div>
      <label class="pr-active"><input type="checkbox" class="pr-active-in" ${p.active ? 'checked' : ''} ${p.editable ? '' : 'disabled'} /> 폼 노출</label>
      ${p.editable ? '<button class="btn-sm pr-save">저장</button>' : '<span class="pr-locktag">구상품</span>'}
      ${p.is_core ? '' : '<button class="btn-sm pr-del" title="삭제">🗑</button>'}
      <span class="pr-msg"></span>
    </div>`).join('') + `
    <div class="pr-add">
      <input class="pr-add-name" placeholder="새 옵션 이름 (예: 드론 촬영)" />
      <div class="pr-price"><input class="pr-add-price" type="number" min="0" placeholder="가격" /><span>만원</span></div>
      <button class="btn-primary pr-add-btn">+ 옵션 추가</button>
      <span class="pr-add-msg"></span>
    </div>`;
  wrap.querySelectorAll('.pr-save').forEach((btn) => btn.addEventListener('click', () => savePricing(btn.closest('.pr-row'))));
  wrap.querySelectorAll('.pr-del').forEach((btn) => btn.addEventListener('click', () => deletePricing(btn.closest('.pr-row'))));
  const addBtn = wrap.querySelector('.pr-add-btn');
  if (addBtn) addBtn.addEventListener('click', () => addPricing(wrap));
}
async function addPricing(wrap) {
  const name = wrap.querySelector('.pr-add-name').value.trim();
  const price = Number(wrap.querySelector('.pr-add-price').value);
  const msg = wrap.querySelector('.pr-add-msg');
  if (!name) { msg.textContent = '이름을 입력하세요'; msg.style.color = '#c0392b'; return; }
  if (!(price >= 0)) { msg.textContent = '가격 확인'; msg.style.color = '#c0392b'; return; }
  msg.textContent = '추가 중…'; msg.style.color = 'var(--ink-soft)';
  const { data, error } = await sb.rpc('admin_pricing_add', { p_name: name, p_price: price });
  if (error) { msg.textContent = '실패: ' + error.message; msg.style.color = '#c0392b'; return; }
  if (data) { pricingList.push(data); pricingMap[data.code] = data; }
  renderPricing();
  toast('옵션을 추가했어요. 예약 폼에 바로 노출됩니다.');
}
async function deletePricing(row) {
  const code = row.dataset.code;
  const name = row.querySelector('.pr-name').value;
  if (!confirm(`"${name}" 옵션을 삭제할까요?\n예약 폼에서 사라집니다. 이미 이 옵션으로 접수된 예약은 그대로 유지돼요.`)) return;
  const { error } = await sb.rpc('admin_pricing_delete', { p_code: code });
  if (error) { alert('삭제 실패: ' + error.message); return; }
  pricingList = pricingList.filter((p) => p.code !== code); delete pricingMap[code];
  renderPricing();
}
async function savePricing(row) {
  const code = row.dataset.code;
  const name = row.querySelector('.pr-name').value.trim();
  const price = Number(row.querySelector('.pr-price-in').value);
  const active = row.querySelector('.pr-active-in').checked;
  const msg = row.querySelector('.pr-msg');
  if (!name) { msg.textContent = '이름을 입력하세요'; msg.style.color = '#c0392b'; return; }
  if (!(price >= 0)) { msg.textContent = '가격 확인'; msg.style.color = '#c0392b'; return; }
  msg.textContent = '저장 중…'; msg.style.color = 'var(--ink-soft)';
  const { data, error } = await sb.rpc('admin_pricing_update', { p_code: code, p_name: name, p_price: price, p_active: active });
  if (error) { msg.textContent = '실패: ' + error.message; msg.style.color = '#c0392b'; return; }
  const p = pricingMap[code]; if (p && data) { p.name = data.name; p.price = data.price; p.active = data.active; }
  msg.textContent = '저장됨 ✓'; msg.style.color = '#2f7d4f';
  setTimeout(() => { msg.textContent = ''; }, 2000);
}
// 수정폼 → line_items 스냅샷 (총액은 recalcEdit 사용, 항목은 이 배열)
function buildEditLineItems() {
  const items = [];
  const two = $('e_photographer') && $('e_photographer').value === '2인 촬영';
  const pkSel = $('e_package') && $('e_package').selectedOptions[0];
  const pkPriceEl = $('e_package_price');
  const pkPrice = pkPriceEl ? (Number(pkPriceEl.value) || 0) : (pkSel ? (Number(pkSel.dataset.price) || 0) : 0);
  if (pkSel && $('e_package').value) items.push({ group: '상품', name: $('e_package').value.replace('(데이터형)', ''), price: pkPrice });
  if ($('e_travel') && $('e_travel').checked) items.push({ group: '상품', name: '출장비', price: (Number($('e_travel').dataset.price) || 0) + (two ? 5 : 0) });
  const _aqi = $('e_album_qty');
  const _aq = _aqi ? (parseInt(_aqi.value, 10) || 0) : 0;
  if (_aq > 0) items.push({ group: '옵션', name: `앨범 추가 ${_aq}권`, price: (Number(_aqi.dataset.unit) || 0) * _aq, qty: _aq });
  [['e_option_reception', '연회장 인사촬영'], ['e_option_pyebaek', '폐백촬영'], ['e_option_part2', '2부 촬영']].forEach(([id, nm]) => {
    if ($(id) && $(id).checked) items.push({ group: '옵션', name: nm, price: Number($(id).dataset.price) || 0 });
  });
  if (two) items.push({ group: '옵션', name: '2인 촬영', price: Number($('e_photographer').selectedOptions[0].dataset.price) || 0 });
  if ($('e_rep') && $('e_rep').checked) items.push({ group: '옵션', name: '대표지정', price: Number($('e_rep').dataset.price) || 0 });
  document.querySelectorAll('#customOpts .co-row').forEach((r) => {
    const nm = r.querySelector('.co-name').value.trim();
    if (nm) items.push({ group: '옵션', name: nm, price: Number(r.querySelector('.co-price').value) || 0 });
  });
  const dcEl = $('e_usage');
  if (dcEl && dcEl.checked && Number(dcEl.dataset.price)) {
    items.push({ group: '할인', name: USAGE_DC, price: Number(dcEl.dataset.price) });
  }
  return items;
}

const kTimeDisp = (t) => {
  if (!t) return '-';
  const [hh, mm] = t.split(':').map(Number);
  return (hh < 12 ? '오전' : '오후') + ' ' + (hh % 12 === 0 ? 12 : hh % 12) + ':' + String(mm).padStart(2, '0');
};

async function openDetail(id) {
  const b = allBookings.find((x) => x.id === id);
  if (!b) return;
  $('modal').hidden = false;
  renderView(b);
  // 설문: 작성됐으면 내용, 아니면 고객 설문 링크 복사 바
  let surveyData = null;
  if (surveyIds.has(id)) {
    const { data } = await sb.rpc('admin_survey_get', { p_booking_id: id });
    surveyData = data;
  }
  const slot = $('surveySlot');
  if (slot && slot.dataset.bid === id) { slot.innerHTML = renderSurvey(surveyData, id); bindSurveyControls(); }
  // 작가 예식 전 확인 상태
  if (b.assignee_id) {
    const cr = await sb.rpc('admin_booking_checks', { p_booking_id: id });
    const cslot = $('checkSlot');
    if (cslot && cslot.dataset.bid === id) {
      cslot.innerHTML = renderChecks(b, Array.isArray(cr.data) ? cr.data : []);
      cslot.querySelectorAll('.chk-link').forEach((btn) => btn.addEventListener('click', () => copyCheckLink(btn.dataset.bid, btn.dataset.staff, btn.dataset.role, btn.dataset.role)));
    }
  }
}

function copyCheckLink(bid, sid, roleLabel, role) {
  if (!sid) { toast('먼저 작가를 배정하세요.'); return; }
  const buildUrl = async () => {
    const lr = await sb.rpc('admin_make_check_link', { p_booking_id: bid, p_staff_id: sid });
    return lr.data ? location.origin + '/c?k=' + lr.data : location.origin + '/staff-schedule?s=' + sid + '&b=' + bid;
  };
  const finish = async (url) => {
    const { data } = await sb.rpc('admin_mark_check_sent', { p_id: bid, p_on: true, p_role: String(role || '').includes('서브') ? '서브' : '메인' });
    const i = allBookings.findIndex((x) => x.id === bid);
    if (i >= 0 && data) allBookings[i] = data;
    const ures = await sb.rpc('admin_unconfirmed');
    allUnconfirmed = Array.isArray(ures.data) ? ures.data : [];
    toast(`${roleLabel} 체크 링크 복사됨 · 보냄 표시`);
    renderDashboard();
  };
  // iOS 포함: 사용자 제스처 안에서 비동기 URL을 클립보드에 (ClipboardItem + Promise). 실패 시 writeText 폴백.
  if (window.ClipboardItem && navigator.clipboard && navigator.clipboard.write) {
    let u;
    navigator.clipboard.write([
      new ClipboardItem({ 'text/plain': buildUrl().then((url) => { u = url; return new Blob([url], { type: 'text/plain' }); }) }),
    ]).then(() => finish(u)).catch(async () => {
      const url = u || await buildUrl();
      try { await navigator.clipboard.writeText(url); } catch (_) {}
      finish(url);
    });
  } else {
    buildUrl().then(async (url) => { try { await navigator.clipboard.writeText(url); } catch (_) {} finish(url); });
  }
}

// 작가 체크 링크를 카톡 등으로 공유 (모바일 공유 시트) — 공유 후 '보냄' 표시
async function shareCheckLink(bid, sid, roleLabel, role) {
  if (!sid) { toast('먼저 작가를 배정하세요.'); return; }
  const b = allBookings.find((x) => x.id === bid);
  const lr = await sb.rpc('admin_make_check_link', { p_booking_id: bid, p_staff_id: sid });
  const url = lr.data ? location.origin + '/c?k=' + lr.data : location.origin + '/staff-schedule?s=' + sid + '&b=' + bid;
  const head = b ? [fmtDate(b.wedding_date), kTimeShort(b.wedding_time), b.contractor_name, b.wedding_venue].filter(Boolean).join(' · ') : '';
  // 메시지(설명)가 먼저, 링크가 그 다음에 오도록 한 덩어리로 합쳐서 공유 — url 필드를 따로 넘기면 카톡이 링크 카드를 위에 띄움
  const text = ((head ? head + '\n' : '') + '예식 전 확인 부탁드려요\n' + url).trim();
  const markSent = async () => {
    const { data } = await sb.rpc('admin_mark_check_sent', { p_id: bid, p_on: true, p_role: String(role || '').includes('서브') ? '서브' : '메인' });
    const i = allBookings.findIndex((x) => x.id === bid);
    if (i >= 0 && data) allBookings[i] = data;
    const ures = await sb.rpc('admin_unconfirmed');
    allUnconfirmed = Array.isArray(ures.data) ? ures.data : [];
    renderDashboard();
  };
  if (navigator.share) {
    try {
      await navigator.share({ text });
    } catch (e) {
      if (e && e.name === 'AbortError') return; // 사용자가 공유 취소 — 보냄 표시 안 함
      try { await navigator.clipboard.writeText(text); } catch (_) {}
      await markSent();
      toast(`${roleLabel} 링크 복사됨 · 보냄 표시`);
      return;
    }
    await markSent();
    toast(`${roleLabel} 공유 완료 · 보냄 표시`);
  } else {
    try { await navigator.clipboard.writeText(text); } catch (_) {}
    await markSent();
    toast(`${roleLabel} 링크 복사됨 (공유 미지원) · 보냄 표시`);
  }
}

function renderChecks(b, checks) {
  const byName = {};
  checks.forEach((c) => { byName[c.staff] = c; });
  const line = (sid, role) => {
    if (!sid) return '';
    const name = staffName(sid);
    const c = byName[name];
    // 완료 판정은 서버(check_done)가 준다 — 배정 체크 셋만 본다
    const ok = c && (c.done != null ? c.done : (c.attend && c.arrival && c.options));
    const items = c ? `참석 ${c.attend ? '✓' : '✕'} · 도착 ${c.arrival ? '✓' : '✕'} · 옵션 ${c.options ? '✓' : '✕'}` : '';
    // 설문 확인은 따로 — 예식 하루 전 설문 링크를 받고 그 화면에서 누른다
    const sv = c && c.survey_ack_at
      ? `<div class="chk-sv ok">📝 설문 확인 <small>${esc(fmtDateTime(c.survey_ack_at))}</small></div>`
      : (c ? '<div class="chk-sv">📝 설문 미확인</div>' : '');
    const st = c ? (ok ? '✔ 확인완료' : '△ 일부확인') : '미확인';
    return `<div class="chk-line ${ok ? 'ok' : c ? 'partial' : 'none'}">
      <div class="chk-head">
        <span class="chk-role">${esc(role)} · ${esc(name)}</span>
        <span class="chk-st">${st}${c && c.checked_at ? ' <small>' + esc(fmtDateTime(c.checked_at)) + '</small>' : ''}</span>
        <button class="btn-sm chk-link" data-bid="${esc(b.id)}" data-staff="${esc(sid)}" data-role="${esc(role)}">${ok ? '재전송' : '체크 링크'}</button>
      </div>
      ${items ? `<div class="chk-items">${esc(items)}</div>` : ''}
      ${sv}
      ${c && c.note ? `<div class="chk-note">📝 ${esc(c.note)}</div>` : ''}
    </div>`;
  };
  return `<div class="chk-box"><p class="chk-title">🧑‍🎨 작가 예식 전 확인</p>${line(b.assignee_id, '메인작가')}${(b.photographer === '2인 촬영' && b.sub_assignee_id) ? line(b.sub_assignee_id, '서브작가') : ''}</div>`;
}

const PROG_ALL = ['신랑신부 동시 입장', '예물교환', '주례말씀', '축사', '축가', '예배식'];

function renderSurvey(s, bid) {
  const customerUrl = location.origin + '/survey?b=' + bid;
  if (!s) return ''; // 설문 미작성 박스는 표시 안 함 (설문은 고객 포털에 통합됨)
  const row = (label, value) =>
    value ? `<div class="sv-row"><span class="sv-l">${esc(label)}</span><span class="sv-v">${esc(value)}</span></div>` : '';
  const yn = (v) => (v ? '예' : '');
  const prog = Array.isArray(s.prog_items) ? s.prog_items.join(', ') : '';
  const refs = Array.isArray(s.refs) ? s.refs : [];
  const refHtml = refs.length
    ? `<div class="sv-row col"><span class="sv-l">레퍼런스 (${refs.length})</span>
        <div class="sv-refs">${refs.map((u, i) => `<img src="${esc(u)}" data-i="${i}" alt="레퍼런스" />`).join('')}</div></div>`
    : '';
  // 배정된 작가를 실어 보내야 그 작가가 [확인했습니다] 를 누를 수 있다
  const sb0 = allBookings.find((x) => x.id === bid);
  const shareUrl = location.origin + '/survey-view?b=' + bid
    + (sb0 && sb0.assignee_id ? '&s=' + sb0.assignee_id : '');
  return `
    <div class="survey-box">
      <div class="survey-bar">
        <button type="button" class="survey-toggle" id="svToggle" aria-expanded="false">
          📝 예식 전 설문 <small>${esc(fmtDateTime(s.updated_at))} 작성</small> <span class="sv-caret">▾</span>
        </button>
        <button type="button" class="survey-share" data-url="${esc(customerUrl)}">고객 링크</button>
        <button type="button" class="survey-share" data-url="${esc(shareUrl)}">작가 공유</button>
      </div>
      <div class="survey-detail" id="svDetail" hidden>
        ${row('안내사항 확인', yn(s.agree_check))}
        ${row('촬영 우선순위', s.priority)}
        ${row('반지·청첩장 소품', yn(s.prop_ring))}
        ${row('신부대기실 요청', s.bride_room_req)}
        ${row('본식 진행항목', prog)}
        ${row('본식 중점', s.bridal_focus)}
        ${row('원판 선진행', yn(s.wonpan_first))}
        ${row('원판 조명', s.wonpan_light)}
        ${row('추가 요청', s.extra_req)}
        ${row('기타 요청', s.etc_req)}
        ${row('설문 이메일', s.email)}
        ${refHtml}
      </div>
    </div>`;
}

function bindSurveyControls() {
  const toggle = $('svToggle');
  const detail = $('svDetail');
  if (toggle && detail) {
    toggle.addEventListener('click', () => {
      const open = detail.hidden;
      detail.hidden = !open;
      toggle.setAttribute('aria-expanded', String(open));
      const caret = toggle.querySelector('.sv-caret');
      if (caret) caret.textContent = open ? '▴' : '▾';
    });
  }
  document.querySelectorAll('#surveySlot .survey-share').forEach((share) => {
    share.addEventListener('click', async () => {
      const url = share.dataset.url;
      try {
        await navigator.clipboard.writeText(url);
        const t = share.textContent;
        share.textContent = '복사됨! ✓';
        share.classList.add('copied');
        setTimeout(() => { share.textContent = t; share.classList.remove('copied'); }, 1600);
      } catch (_) {
        prompt('아래 링크를 복사하세요:', url);
      }
    });
  });
}

// 읽기 전용 보기 (한눈에) — "수정" 누르면 편집 모드로
function renderView(b, flash) {
  const field = (label, value) =>
    `<div><p class="dl">${label}</p><p class="dv">${esc(value || '-')}</p></div>`;
  $('modalCard').innerHTML = `
    <button class="modal-close" id="modalClose">&times;</button>
    <p class="modal-title">${esc(b.contractor_name || '예약')} 님 <span class="badge ${esc(b.status)}">${esc(b.status)}</span></p>
    <p class="modal-sub">접수 ${esc(fmtDateTime(b.created_at))}</p>
    ${flash ? `<p class="save-msg ok" style="text-align:left;margin:0 0 12px">${esc(flash)}</p>` : ''}

    <div class="md-assignee">
      <span class="md-asg-label">메인작가</span>
      <select id="mAssignee" class="md-sel">${assigneeOptions(b.assignee_id, confOf(b), 'main')}</select>
      ${b.photographer === '2인 촬영' ? `<span class="md-asg-label">서브작가</span><select id="mSubAssignee" class="md-sel">${assigneeOptions(b.sub_assignee_id, confOf(b), 'sub')}</select>` : ''}
    </div>

    <div class="detail-grid">
      ${field('연락처', b.contractor_phone)}
      ${field('이메일', b.contractor_email)}
      ${field('예식일', fmtDate(b.wedding_date))}
      ${field('예식시간', kTimeDisp(b.wedding_time))}
      <div class="full2">${field('예식장소', b.wedding_venue)}</div>
      ${field('신랑님', (b.groom_name || '') + ' / ' + (b.groom_phone || ''))}
      ${field('신부님', (b.bride_name || '') + ' / ' + (b.bride_phone || ''))}
      <div class="full2"><p class="dl">상품 · 옵션</p>${productOptionsHtml(b)}</div>
      <div><p class="dl">촬영본 사용동의</p><p class="dv"><span class="usage-${b.photo_usage_agree ? 'yes' : 'no'}">${b.photo_usage_agree ? 'YES' : 'NO'}</span></p></div>
      ${field('합계', won(b.total_price))}
      <div><p class="dl">계약금</p><p class="dv">${won(10)} · <span class="pay-st ${b.deposit_paid ? 'paid' : ''}">${b.deposit_paid ? '입금완료 ✓' : '미입금'}</span> <button class="pay-toggle" data-pay="deposit">${b.deposit_paid ? '해제' : '입금확인'}</button></p></div>
      ${evDc(b) > 0 ? `<div><p class="dl">이벤트 할인</p><p class="dv" style="color:#2f7d4f;font-weight:600">−${evDc(b)}만원</p></div>` : ''}
      <div><p class="dl">잔금${evDc(b) > 0 ? ' <small style="color:#2f7d4f">(할인적용)</small>' : ''}</p><p class="dv">${effBalance(b) != null ? won(effBalance(b)) : '-'} · <span class="pay-st ${b.balance_paid ? 'paid' : ''}">${b.balance_paid ? '입금완료 ✓' : '미입금'}</span> <button class="pay-toggle" data-pay="balance">${b.balance_paid ? '해제' : '입금확인'}</button></p></div>
      ${b.admin_note ? `<div class="full2">${field('관리자 메모', b.admin_note)}</div>` : ''}
    </div>

    ${b.assignee_id ? `<div id="checkSlot" data-bid="${esc(b.id)}">${renderChecks(b, [])}</div>` : ''}
    <div id="eventSlot" data-bid="${esc(b.id)}">${eventSlotHtml(null)}</div>
    <div id="surveySlot" data-bid="${esc(b.id)}">${surveyIds.has(b.id) ? '<p class="survey-loading">📝 설문 불러오는 중…</p>' : ''}</div>

    <div class="portal-link">
      <p class="dl">고객 예약확인 페이지</p>
      <div class="portal-link-actions">
        <a class="btn-sm" href="portal?b=${esc(b.id)}" target="_blank" rel="noopener">열기</a>
        <button class="btn-sm" id="copyPortal" data-bid="${esc(b.id)}">링크 복사</button>
      </div>
    </div>

    <div class="dl-detail-box">
      <p class="dl">📁 촬영본 원본 링크 ${(b.alimtalk_sent && b.alimtalk_sent.E) ? '<span class="dl-esent">· E 발송됨 ✓</span>' : ''}</p>
      ${b.balance_paid
        ? `<div class="dl-dlrow">
             <input type="text" class="dl-link dl-link-d" placeholder="다운로드 링크 붙여넣기" value="${esc(b.download_link || '')}" />
             <button class="btn-sm dl-save-btn" id="dlSaveD" data-id="${esc(b.id)}">저장</button>
           </div>
           ${b.download_link ? `<a class="dl-open-d" href="${esc(b.download_link)}" target="_blank" rel="noopener">현재 링크 열기 ↗</a>` : '<span class="dl-empty-hint">아직 등록된 링크가 없어요</span>'}
           <button class="btn-sm dbx-btn" id="dbxBtn">📦 드롭박스에서 공유</button>
           <button class="btn-sm dbx-btn" id="selBtn">🖼 셀렉 RAW 찾기</button>
           <div id="dbxBox"></div>
           <div id="selBox"></div>`
        : `<span class="dl-blocked-msg">🔒 잔금 입금 확인 후 입력 가능</span>`}
    </div>

    <div class="atk-prog">
      <p class="dl">알림톡 발송 <small>([발송]=실제 전송 · 배지=보냄 수동표시 · [복사]=문구 복사해 카톡 수동발송)</small></p>
      <div class="atk-rows">
        ${ATK_TPLS.map(([k, label]) => {
          const on = b.alimtalk_sent && b.alimtalk_sent[k];
          return `<div class="atk-row">
            <button class="atk-send" data-send-atk="${k}">발송</button>
            <button class="atk-badge${on ? ' on' : ''}" data-atk="${k}">${esc(k)}. ${esc(label)}${on ? ' ✓' : ''}</button>
            <button class="atk-copy" data-copy-atk="${k}" title="이 안내 문구를 복사 — 카톡에 붙여넣어 수동 발송(외국 고객 등 알림톡 불가 시)">📋 복사</button>
          </div>`;
        }).join('')}
      </div>
    </div>

    <div class="modal-btns">
      <button class="btn-primary" id="mEdit">수정</button>
      <button class="btn-outline" id="mCancelBk">${b.status === '취소' ? '취소 해제' : '예약 취소'}</button>
      <button class="btn-del" id="mDelete">삭제</button>
    </div>`;

  if ($('dbxBtn')) $('dbxBtn').addEventListener('click', () =>
    dbxShare(b, $('dbxBtn'), $('dbxBox'), document.querySelector('.dl-link-d')));
  if ($('selBtn')) $('selBtn').addEventListener('click', () => dbxSelect(b));
  $('modalClose').addEventListener('click', closeModal);
  $('mEdit').addEventListener('click', () => renderEdit(b));
  $('mDelete').addEventListener('click', () => deleteBooking(b.id));
  $('mCancelBk').addEventListener('click', () => cancelBooking(b.id));
  const saveAssignees = async () => {
    const main = $('mAssignee').value || null;
    // 서브 선택칸이 없으면(=2인 촬영 아님) 서브는 비움
    const sub = $('mSubAssignee') ? ($('mSubAssignee').value || null) : null;
    const { error } = await sb.rpc('admin_set_assignees', { p_id: b.id, p_main: main, p_sub: sub });
    if (error) { alert('배정 실패: ' + error.message); return; }
    b.assignee_id = main; b.sub_assignee_id = sub;
    const i = allBookings.findIndex((x) => x.id === b.id);
    if (i >= 0) { allBookings[i].assignee_id = main; allBookings[i].sub_assignee_id = sub; }
    renderDashboard();
    toast('작가 배정을 변경했어요.');
  };
  if ($('mAssignee')) $('mAssignee').addEventListener('change', saveAssignees);
  if ($('mSubAssignee')) $('mSubAssignee').addEventListener('change', saveAssignees);
  refillAsg(b, { mAssignee: ['assignee_id', 'main'], mSubAssignee: ['sub_assignee_id', 'sub'] });

  // 계약금/잔금 입금 토글 (잘못 누르면 다시 눌러 해제)
  $('modalCard').querySelectorAll('.pay-toggle').forEach((btn) =>
    btn.addEventListener('click', async () => {
      const kind = btn.dataset.pay;
      const fn = kind === 'balance' ? 'admin_set_balance' : 'admin_set_deposit';
      const cur = kind === 'balance' ? b.balance_paid : b.deposit_paid;
      btn.disabled = true;
      const { data, error } = await sb.rpc(fn, { p_id: b.id, p_paid: !cur });
      if (error) { btn.disabled = false; alert('처리 실패: ' + error.message); return; }
      const i = allBookings.findIndex((x) => x.id === b.id);
      if (i >= 0 && data) allBookings[i] = data;
      // '미입금'으로 분류했던 건이 실제로 계약금을 내면 확정으로 되돌림
      // (admin_set_deposit 은 신규→확정만 자동전환하므로 여기서 보완)
      if (kind === 'deposit' && !cur && data && data.status === '미입금') {
        const { data: cd } = await sb.rpc('admin_update_booking', { p_id: b.id, p_status: '확정' });
        if (i >= 0 && cd) allBookings[i] = cd;
      }
      render();
      renderDashboard();
      renderView(allBookings[i] || data || b);
      // 계약금을 '입금완료'로 켤 때 입금확인 알림톡(F) 발송 — 이미 보냈으면 생략
      const nb = allBookings[i] || data || b;
      if (kind === 'deposit' && !cur && !(nb && nb.alimtalk_sent && nb.alimtalk_sent.F)) sendAlimtalk(b.id, 'F');
    })
  );
  $('modalCard').querySelectorAll('.atk-badge').forEach((btn) =>
    btn.addEventListener('click', async () => {
      const k = btn.dataset.atk;
      const on = !(b.alimtalk_sent && b.alimtalk_sent[k]);
      btn.disabled = true;
      const { data, error } = await sb.rpc('admin_set_alimtalk', { p_id: b.id, p_template: k, p_on: on });
      if (error) { btn.disabled = false; alert('처리 실패: ' + error.message); return; }
      const i = allBookings.findIndex((x) => x.id === b.id);
      if (i >= 0 && data) allBookings[i] = data;
      renderDashboard();
      renderView(data || b);
    })
  );
  // 알림톡 실제 발송
  $('modalCard').querySelectorAll('.atk-send').forEach((btn) =>
    btn.addEventListener('click', () => sendAlimtalk(b.id, btn.dataset.sendAtk))
  );
  // 수동발송용 문구 복사 (알림톡 못 받는 외국 고객 등 → 카톡에 붙여넣기)
  $('modalCard').querySelectorAll('.atk-copy').forEach((btn) =>
    btn.addEventListener('click', async () => {
      await copySchedText(atkManualText(b, btn.dataset.copyAtk), '문구를 복사했어요 📋 카톡에 붙여넣어 보내세요');
      const t = btn.textContent; btn.textContent = '복사됨 ✓';
      setTimeout(() => (btn.textContent = t), 1400);
    })
  );

  // 고객 예약확인 페이지 링크 복사
  const cpBtn = $('copyPortal');
  if (cpBtn) cpBtn.addEventListener('click', () => {
    const url = `${location.origin}/portal?b=${b.id}`;
    navigator.clipboard?.writeText(url);
    cpBtn.textContent = '복사됨 ✓';
    setTimeout(() => (cpBtn.textContent = '링크 복사'), 1500);
  });

  // 촬영본 원본 링크 저장 (상세)
  const dlSaveD = $('dlSaveD');
  if (dlSaveD) dlSaveD.addEventListener('click', async () => {
    const inp = $('modalCard').querySelector('.dl-link-d');
    dlSaveD.disabled = true;
    const { data, error } = await sb.rpc('admin_set_download_link', { p_id: b.id, p_link: inp.value.trim() });
    if (error) { dlSaveD.disabled = false; alert('저장 실패: ' + error.message); return; }
    const i = allBookings.findIndex((x) => x.id === b.id);
    if (i >= 0 && data) allBookings[i] = data;
    toast('다운로드 링크를 저장했어요.');
    renderDashboard();
    renderView(allBookings[i] || b);
  });

  // 작가 확인 박스: 즉시 표시된 골격에 버튼 바인딩(상태는 openDetail에서 비동기 갱신)
  const cslot0 = $('checkSlot');
  if (cslot0) cslot0.querySelectorAll('.chk-link').forEach((btn) => btn.addEventListener('click', () => copyCheckLink(btn.dataset.bid, btn.dataset.staff, btn.dataset.role, btn.dataset.role)));
  // 이벤트 참여 박스: 골격은 즉시 보이고, 실제 상태·바인딩은 비동기 갱신
  loadEventSlot(b);

  // 레퍼런스 사진 클릭 → 크게 보기 (좌우로 밀어 넘길 수 있다)
  bindRefLightbox($('modalCard'), '.sv-refs img');
}

/* ── 레퍼런스 사진 크게 보기 ────────────────────────────────
   한 장만 띄우던 것을 여러 장 넘겨보게 바꿨다 (대표 요청).
   폰은 좌우로 밀어서, 컴퓨터는 ‹ › 나 화살표 키로. 배경을 누르면 닫힌다.
   사진 자체를 눌러도 안 닫는다 — 밀다가 손을 떼면 눌린 것으로 잡혀 꺼져버린다.
   ※ 작가용 설문 보기(survey-view.js)에도 같은 것이 있다. 고칠 땐 둘 다 */
function bindRefLightbox(root, sel) {
  if (!root || root.dataset.lbBound) return;
  root.dataset.lbBound = '1';
  root.addEventListener('click', (e) => {
    const im = e.target.closest(sel);
    if (!im) return;
    const list = Array.from(root.querySelectorAll(sel)).map((x) => x.src);
    openRefLightbox(list, list.indexOf(im.src));
  });
}

function openRefLightbox(list, start) {
  if (!list.length) return;
  let i = Math.max(0, start);
  const lb = document.createElement('div');
  lb.className = 'sv-lb';
  lb.innerHTML = '<img alt="레퍼런스" />'
    + (list.length > 1 ? '<button type="button" class="sv-lb-nav prev" aria-label="이전">‹</button>'
      + '<button type="button" class="sv-lb-nav next" aria-label="다음">›</button>'
      + '<span class="sv-lb-n"></span>' : '')
    + '<button type="button" class="sv-lb-x" aria-label="닫기">&times;</button>';
  const img = lb.querySelector('img');
  const cnt = lb.querySelector('.sv-lb-n');
  const draw = () => {
    img.src = list[i];
    if (cnt) cnt.textContent = `${i + 1} / ${list.length}`;
  };
  const go = (step) => { i = (i + step + list.length) % list.length; draw(); };
  const close = () => { lb.remove(); document.removeEventListener('keydown', onKey); };
  const onKey = (e) => {
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowRight') go(1);
    else if (e.key === 'ArrowLeft') go(-1);
  };
  lb.addEventListener('click', (e) => {
    if (e.target.closest('.sv-lb-x')) return close();
    if (e.target.closest('.sv-lb-nav.prev')) return go(-1);
    if (e.target.closest('.sv-lb-nav.next')) return go(1);
    if (e.target === lb) close();          // 배경만. 사진을 눌러서는 안 닫힌다
  });
  // 좌우로 밀어 넘기기 — 세로로 긁는 손짓과 헷갈리지 않게 가로가 더 클 때만
  let x0 = null, y0 = null;
  lb.addEventListener('touchstart', (e) => {
    if (e.touches.length !== 1) { x0 = null; return; }
    x0 = e.touches[0].clientX; y0 = e.touches[0].clientY;
  }, { passive: true });
  lb.addEventListener('touchend', (e) => {
    if (x0 === null) return;
    const t = e.changedTouches[0];
    const dx = t.clientX - x0, dy = t.clientY - y0;
    x0 = null;
    if (Math.abs(dx) > 45 && Math.abs(dx) > Math.abs(dy)) go(dx < 0 ? 1 : -1);
  }, { passive: true });
  document.addEventListener('keydown', onKey);
  draw();
  document.body.appendChild(lb);
}

// 이벤트 참여 박스 HTML (data=null이면 기본 골격 — 즉시 표시용)
function eventSlotHtml(data) {
  const bd = (data && data.buddy) || { state: 'none' };
  const rv = data && data.review;
  const buddyApproved = bd.state === 'approved';
  const reviewApproved = !!(rv && rv.status === 'approved');
  const rewardSel = (id, val) =>
    `<select class="evd-reward" id="${id}"><option value="할인"${val === '할인' ? ' selected' : ''}>1만원 할인</option><option value="앨범"${val === '앨범' ? ' selected' : ''}>앨범 1권</option></select>`;
  const stateTxt = { sent_waiting: '상대 확인 대기', incoming_confirm: '고객 확인 대기', matched: '고객 확인됨 · 승인 대기' };
  const buddyCtx = (bd.state && bd.state !== 'none' && !buddyApproved)
    ? `<span class="evd-ctx">${bd.partner_name ? esc(bd.partner_name) + '님 · ' : ''}${stateTxt[bd.state] || ''}</span>` : '';
  const reviewCtx = (rv && rv.status !== 'approved' && rv.link && rv.link !== '(관리자 처리)')
    ? `<span class="evd-ctx"><a href="${esc(rv.link)}" target="_blank" rel="noopener" class="evd-link">후기 링크</a></span>` : '';
  return `
    <div class="ev-detail">
      <p class="dl">🎉 이벤트 참여 <small>(관리자 직접 체크 — 할인은 잔금에 반영)</small></p>
      <div class="evd-ctrl">
        <label class="evd-chk"><input type="checkbox" id="evBuddyOn" ${buddyApproved ? 'checked' : ''}/> 짝꿍 참여</label>
        ${rewardSel('evBuddyReward', bd.reward)}
        ${buddyCtx}
      </div>
      <div class="evd-ctrl">
        <label class="evd-chk"><input type="checkbox" id="evReviewOn" ${reviewApproved ? 'checked' : ''}/> 후기 참여</label>
        ${rewardSel('evReviewReward', rv && rv.reward)}
        ${reviewCtx}
      </div>
    </div>`;
}

// 예약 상세: 이벤트 참여 관리자 직접 체크(참여 토글 + 혜택)
async function loadEventSlot(b) {
  const slot = document.getElementById('eventSlot');
  if (!slot) return;
  const { data } = await sb.rpc('portal_booking_info', { p_booking_id: b.id });
  if (slot.dataset.bid !== b.id) return; // 그 사이 다른 예약 열면 무시
  slot.innerHTML = eventSlotHtml(data);
  bindEventSlot(b);
}

function bindEventSlot(b) {
  if (!document.getElementById('evBuddyOn')) return;
  const afterEv = async (res) => {
    if (res && res.error) { alert('처리 실패: ' + res.error.message); return; }
    const dres = await sb.rpc('admin_event_discounts');
    eventDiscounts = (dres.data && typeof dres.data === 'object') ? dres.data : {};
    toast('이벤트 참여를 저장했어요.');
    renderDashboard();
    renderView(b);
  };
  const applyBuddy = () => sb.rpc('admin_set_buddy', { p_booking: b.id, p_on: $('evBuddyOn').checked, p_reward: $('evBuddyReward').value }).then(afterEv);
  const applyReview = () => sb.rpc('admin_set_review', { p_booking: b.id, p_on: $('evReviewOn').checked, p_reward: $('evReviewReward').value }).then(afterEv);
  $('evBuddyOn').addEventListener('change', applyBuddy);
  $('evBuddyReward').addEventListener('change', () => { if ($('evBuddyOn').checked) applyBuddy(); });
  $('evReviewOn').addEventListener('change', applyReview);
  $('evReviewReward').addEventListener('change', () => { if ($('evReviewOn').checked) applyReview(); });
}

// 편집 모드
function renderEdit(b) {
  const v = (s) => esc(s == null ? '' : s);
  const dval = (s) => (s ? esc(String(s).slice(0, 10)) : '');
  const ck = (c) => (c ? 'checked' : '');
  const sl = (a, bb) => (a === bb ? 'selected' : '');
  const asnap = albumSnap(b);
  const basicPrice = editPrice(b, '베이직', 'basic'); // 베이직(데이터형) 단가(스냅샷 우선, 없으면 카탈로그가)
  // 가격칸 초깃값은 '이 예약의 상품' 기준이어야 함.
  // 베이직가로 채우면 스페셜·베이직(구) 예약을 열어 저장만 해도 베이직가로 덮어써짐.
  const OLD_PKG_PRICE = { '스페셜': 55, '베이직(구)': 50 };  // 구상품 정가(카탈로그에 없음)
  const pkgVal = b.package || '베이직(데이터형)';
  const pkgSnap = Array.isArray(b.line_items)
    ? b.line_items.find((it) => it && it.name === pkgVal.replace('(데이터형)', ''))  // 스냅샷 이름 규칙은 buildEditLineItems와 동일
    : null;
  const basePrice = pkgSnap && pkgSnap.price != null
    ? (Number(pkgSnap.price) || 0)
    : (OLD_PKG_PRICE[pkgVal] != null ? OLD_PKG_PRICE[pkgVal] : basicPrice);

  $('modalCard').innerHTML = `
    <button class="modal-close" id="modalClose">&times;</button>
    <p class="modal-title">예약 수정</p>
    <p class="modal-sub">접수 ${esc(fmtDateTime(b.created_at))}</p>

    <h5 class="eg">계약자 정보</h5>
    <div class="edit-grid">
      <div class="field"><label>계약자 성함</label><input id="e_contractor_name" value="${v(b.contractor_name)}" /></div>
      <div class="field"><label>연락처</label><input id="e_contractor_phone" class="js-phone" value="${v(b.contractor_phone)}" /></div>
      <div class="field full2"><label>이메일</label><input id="e_contractor_email" value="${v(b.contractor_email)}" /></div>
    </div>

    <h5 class="eg">예식 정보</h5>
    <div class="edit-grid">
      <div class="field"><label>예식날짜</label><input type="date" id="e_wedding_date" value="${dval(b.wedding_date)}" /></div>
      <div class="field"><label>예식시간</label><input type="time" id="e_wedding_time" value="${v(b.wedding_time)}" /></div>
      <div class="field full2"><label>예식장소</label><input id="e_wedding_venue" value="${v(b.wedding_venue)}" /></div>
    </div>

    <h5 class="eg">신랑 · 신부</h5>
    <div class="edit-grid">
      <div class="field"><label>신랑 성함</label><input id="e_groom_name" value="${v(b.groom_name)}" /></div>
      <div class="field"><label>신랑 연락처</label><input id="e_groom_phone" class="js-phone" value="${v(b.groom_phone)}" /></div>
      <div class="field"><label>신부 성함</label><input id="e_bride_name" value="${v(b.bride_name)}" /></div>
      <div class="field"><label>신부 연락처</label><input id="e_bride_phone" class="js-phone" value="${v(b.bride_phone)}" /></div>
    </div>

    <h5 class="eg">상품 · 옵션 <small>(체크 시 합계 자동 변경)</small></h5>
    <div class="field" style="margin-bottom:10px">
      <label>상품 <small style="font-weight:400;opacity:.6">· 가격 직접 수정 가능</small></label>
      <div style="display:flex;gap:8px;align-items:center">
        <select id="e_package" style="flex:1">
          <option value="베이직(데이터형)" data-price="${basicPrice}" ${sl(b.package, '베이직(데이터형)')}>베이직 (데이터형)</option>
          <option value="스페셜" data-price="55" ${sl(b.package, '스페셜')}>스페셜 (구상품)</option>
          <option value="베이직(구)" data-price="50" ${sl(b.package, '베이직(구)')}>베이직(구) (구상품)</option>
        </select>
        <div style="display:flex;align-items:center;gap:4px;white-space:nowrap"><input id="e_package_price" type="number" min="0" step="1" value="${basePrice}" inputmode="numeric" aria-label="상품 가격(만원)" style="width:72px;text-align:right" /><span>만원</span></div>
      </div>
    </div>
    <div class="edit-opts">
      <label class="eopt"><input type="checkbox" id="e_travel" data-price="${catPrice('travel', 5)}" ${ck(b.travel_fee)} /><span>출장비</span><b>${catPrice('travel', 5)}만원</b></label>
      <div class="eopt eopt-qty"><input type="checkbox" id="e_option_album" ${asnap.qty > 0 ? 'checked' : ''} /><span>앨범 추가</span><div class="qty-stepper" data-qty-for="e_album"><button type="button" class="qty-btn" data-step="-1" aria-label="수량 줄이기">−</button><input type="number" id="e_album_qty" class="qty-input" value="${asnap.qty}" min="0" max="9" step="1" inputmode="numeric" data-unit="${asnap.unit}" readonly aria-label="앨범 수량" /><button type="button" class="qty-btn" data-step="1" aria-label="수량 늘리기">+</button></div><b>+${asnap.unit}만원</b></div>
      <label class="eopt"><input type="checkbox" id="e_option_reception" data-price="${editPrice(b, '연회장 인사촬영', 'reception')}" ${ck(b.option_reception)} /><span>연회장 인사촬영</span><b>+${editPrice(b, '연회장 인사촬영', 'reception')}만원</b></label>
      <label class="eopt"><input type="checkbox" id="e_option_pyebaek" data-price="${editPrice(b, '폐백촬영', 'pyebaek')}" ${ck(b.option_pyebaek)} /><span>폐백촬영</span><b>+${editPrice(b, '폐백촬영', 'pyebaek')}만원</b></label>
      <label class="eopt"><input type="checkbox" id="e_option_part2" data-price="${editPrice(b, '2부 촬영', 'part2')}" ${ck(b.option_part2)} /><span>2부 촬영</span><b>+${editPrice(b, '2부 촬영', 'part2')}만원</b></label>
    </div>
    <div class="field" style="margin-top:10px">
      <label>작가 선택</label>
      <select id="e_photographer">
        <option value="기본" data-price="0" ${sl(b.photographer, '기본')}>기본 (1인 촬영)</option>
        <option value="2인 촬영" data-price="${catPrice('photographer_2p', 25)}" ${sl(b.photographer, '2인 촬영')}>2인 촬영 (+${catPrice('photographer_2p', 25)}만원)</option>
      </select>
    </div>
    <label class="eopt" style="margin-top:8px"><input type="checkbox" id="e_rep" data-price="${editPrice(b, '대표지정', 'rep')}" ${ck(b.rep_designation)} /><span>대표지정</span><b>+${editPrice(b, '대표지정', 'rep')}만원</b></label>
    <label class="eopt" style="margin-top:8px"><input type="checkbox" id="e_usage" data-price="${usageDcPrice(b)}" ${ck(b.photo_usage_agree)} /><span>촬영본 사용동의 (YES)</span><b>${usageDcPrice(b) ? usageDcPrice(b) + '만원' : ''}</b></label>

    <h5 class="eg">커스텀 옵션 <small>(예전·비표준 옵션)</small></h5>
    <div id="customOpts" class="custom-opts"></div>
    <button type="button" class="btn-sm" id="addCustom" style="margin-top:8px">+ 옵션 추가</button>

    <h5 class="eg">작가 배정 · 입금</h5>
    <div class="edit-grid">
      <div class="field"><label>메인작가</label><select id="e_assignee">${assigneeOptions(b.assignee_id, confOf(b), 'main')}</select></div>
      ${b.photographer === '2인 촬영' ? `<div class="field"><label>서브작가</label><select id="e_sub_assignee">${assigneeOptions(b.sub_assignee_id, confOf(b), 'sub')}</select></div>` : ''}
    </div>
    <label class="eopt"><input type="checkbox" id="e_deposit" ${ck(b.deposit_paid)} /><span>계약금 입금 완료</span><b></b></label>
    <label class="eopt"><input type="checkbox" id="e_balance" ${ck(b.balance_paid)} /><span>잔금 입금 완료</span><b></b></label>

    <h5 class="eg">확인사항</h5>
    <label class="eopt"><input type="checkbox" id="e_agree_available" ${ck(b.agree_available)} /><span>예약가능 답변 확인</span><b></b></label>
    <label class="eopt"><input type="checkbox" id="e_agree_terms" ${ck(b.agree_terms)} /><span>규정 동의</span><b></b></label>

    <div class="bk-total" style="margin-top:16px"><span>합계</span><strong id="eTotal">${won(b.total_price)}</strong></div>

    <div class="row-2" style="margin-top:14px">
      <div class="field"><label>상태</label>
        <select id="mStatus">
          <option value="신규" ${sl(b.status, '신규')}>신규</option>
          <option value="확정" ${sl(b.status, '확정')}>확정</option>
          <option value="미입금" ${sl(b.status, '미입금')}>미입금</option>
          <option value="취소" ${sl(b.status, '취소')}>취소</option>
        </select>
      </div>
    </div>
    <div class="field" style="margin-top:12px"><label>관리자 메모</label><textarea id="mNote" rows="2">${esc(b.admin_note || '')}</textarea></div>

    <div class="modal-btns">
      <button class="btn-ghost" id="mCancel">취소</button>
      <button class="btn-primary" id="mSave">저장</button>
    </div>
    <p class="save-msg" id="mMsg"></p>`;

  const recalcEdit = () => {
    let sum = 0;
    $('modalCard')
      .querySelectorAll('input[data-price]:checked')
      .forEach((el) => (sum += Number(el.dataset.price) || 0));
    const aqi = $('e_album_qty');
    if (aqi) sum += (Number(aqi.dataset.unit) || 0) * (parseInt(aqi.value, 10) || 0);
    const pkPriceEl = $('e_package_price');
    const pk = $('e_package') && $('e_package').selectedOptions[0];
    if (pkPriceEl) sum += Number(pkPriceEl.value) || 0;
    else if (pk) sum += Number(pk.dataset.price) || 0;
    const ph = $('e_photographer').selectedOptions[0];
    if (ph) sum += Number(ph.dataset.price) || 0;
    // 2인 촬영 + 출장비 → 출장비 1인당(+5)
    if ($('e_travel') && $('e_travel').checked && $('e_photographer').value === '2인 촬영') sum += 5;
    document.querySelectorAll('#customOpts .co-price').forEach((el) => (sum += Number(el.value) || 0));
    $('eTotal').textContent = sum.toLocaleString('ko-KR') + '만원';
    return sum;
  };
  renderCustomOpts(Array.isArray(b.custom_options) ? b.custom_options : []);
  $('addCustom').addEventListener('click', () => { addCustomRow('', ''); recalcEdit(); });
  $('modalCard').addEventListener('change', recalcEdit);
  $('modalCard').addEventListener('input', (e) => { if (e.target.classList.contains('co-price') || e.target.id === 'e_package_price') recalcEdit(); });
  // 상품 바꾸면 가격칸을 그 상품 기본가로 채움(그 뒤 직접 수정 가능)
  if ($('e_package')) $('e_package').addEventListener('change', () => {
    const opt = $('e_package').selectedOptions[0];
    const pp = $('e_package_price');
    if (opt && pp) pp.value = Number(opt.dataset.price) || 0;
    recalcEdit();
  });
  $('modalCard').querySelectorAll('.qty-stepper').forEach((st) => {
    const input = st.querySelector('.qty-input');
    if (!input) return;
    st.classList.toggle('on', (parseInt(input.value, 10) || 0) > 0);
    st.querySelectorAll('.qty-btn').forEach((btn) => btn.addEventListener('click', () => {
      const min = Number(input.min) || 0, max = input.max === '' ? Infinity : Number(input.max);
      input.value = Math.max(min, Math.min(max, (parseInt(input.value, 10) || 0) + (Number(btn.dataset.step) || 0)));
      st.classList.toggle('on', (parseInt(input.value, 10) || 0) > 0);
      if (input.id === 'e_album_qty' && $('e_option_album')) $('e_option_album').checked = (parseInt(input.value, 10) || 0) > 0;
      input.dispatchEvent(new Event('change', { bubbles: true }));
    }));
  });
  if ($('e_option_album')) $('e_option_album').addEventListener('change', () => {
    const qi = $('e_album_qty'); if (!qi) return;
    const max = qi.max === '' ? Infinity : Number(qi.max);
    qi.value = $('e_option_album').checked ? Math.max(1, Math.min(max, parseInt(qi.value, 10) || 0)) : 0;
    const st = qi.closest('.qty-stepper'); if (st) st.classList.toggle('on', (parseInt(qi.value, 10) || 0) > 0);
  });
  recalcEdit();

  hookPhone($('modalCard'));
  $('modalClose').addEventListener('click', closeModal);
  $('mCancel').addEventListener('click', () => renderView(b));
  $('mSave').addEventListener('click', () => saveDetail(b.id, recalcEdit));
}

function closeModal() {
  $('modal').hidden = true;
}
$('modalBackdrop').addEventListener('click', closeModal);

// 설문 레퍼런스 사진 파일 삭제 (DB 행은 예약 삭제 시 cascade 되지만 스토리지 파일은 남으므로 직접 지움)
async function removeRefFiles(id) {
  const dir = `refs/${id}`;
  const { data: files, error } = await sb.storage.from('gallery').list(dir, { limit: 200 });
  if (error) return { ok: false, msg: error.message };
  if (!files || !files.length) return { ok: true, n: 0 };
  const { error: rmErr } = await sb.storage.from('gallery').remove(files.map((f) => `${dir}/${f.name}`));
  if (rmErr) return { ok: false, msg: rmErr.message };
  return { ok: true, n: files.length };
}

async function deleteBooking(id) {
  if (!confirm('이 예약을 완전히 삭제할까요?\n설문·레퍼런스도 함께 삭제되며 되돌릴 수 없습니다.')) return;
  // 파일 먼저 삭제 — 예약을 지우면 경로를 찾을 근거(설문 행)가 사라지기 때문
  const rf = await removeRefFiles(id);
  if (!rf.ok && !confirm('레퍼런스 사진 파일을 지우지 못했어요: ' + rf.msg + '\n\n예약만 삭제하고 사진 파일은 남겨둘까요?')) return;
  const { error } = await sb.rpc('admin_delete_booking', { p_id: id });
  if (error) { alert('삭제 실패: ' + error.message); return; }
  allBookings = allBookings.filter((b) => b.id !== id);
  closeModal();
  render();
  renderDashboard();
  toast('예약을 삭제했어요.' + (rf.ok && rf.n ? ` (레퍼런스 사진 ${rf.n}장 함께 삭제)` : ''));
}

async function markUnpaid(id) {
  const b = allBookings.find((x) => x.id === id);
  if (!b) return;
  const revert = b.status === '미입금';
  if (!confirm(revert
    ? '미입금 분류를 해제할까요? (신규로 되돌림)'
    : '이 예약을 "미입금"으로 분류할까요?\n계약 의사가 없는 건으로 표시됩니다. (기록은 남고, 나중에 되돌릴 수 있어요)')) return;
  const { data, error } = await sb.rpc('admin_update_booking', { p_id: id, p_status: revert ? '신규' : '미입금' });
  if (error) { alert('처리 실패: ' + error.message); return; }
  const i = allBookings.findIndex((x) => x.id === id);
  if (i >= 0 && data) allBookings[i] = data;
  render();
  renderDashboard();
  renderView(data || b);
  toast(revert ? '미입금 분류를 해제했어요.' : '미입금으로 분류했어요.');
}

async function cancelBooking(id) {
  const b = allBookings.find((x) => x.id === id);
  if (!b) return;
  const reactivate = b.status === '취소';
  if (!confirm(reactivate ? '예약 취소를 해제할까요? (신규로 되돌림)' : '이 예약을 취소 처리할까요? (기록은 남고 목록/캘린더에서 제외)')) return;
  const { data, error } = await sb.rpc('admin_update_booking', { p_id: id, p_status: reactivate ? '신규' : '취소' });
  if (error) { alert('처리 실패: ' + error.message); return; }
  const i = allBookings.findIndex((x) => x.id === id);
  if (i >= 0 && data) allBookings[i] = data;
  render();
  renderDashboard();
  renderView(data || b);
  toast(reactivate ? '취소를 해제했어요.' : '예약을 취소 처리했어요.');
}

function addCustomRow(name, price) {
  const wrap = $('customOpts');
  if (!wrap) return;
  const div = document.createElement('div');
  div.className = 'co-row';
  div.innerHTML = `<input type="text" class="co-name" placeholder="옵션명 (예: 플러스)" value="${esc(name || '')}" />
    <input type="number" class="co-price" placeholder="0" value="${price === '' || price == null ? '' : esc(price)}" /><span class="co-unit">만원</span>
    <button type="button" class="co-del" aria-label="삭제">×</button>`;
  div.querySelector('.co-del').addEventListener('click', () => {
    div.remove();
    $('modalCard').dispatchEvent(new Event('change', { bubbles: true }));
  });
  wrap.appendChild(div);
}
function renderCustomOpts(list) {
  const wrap = $('customOpts');
  if (!wrap) return;
  wrap.innerHTML = '';
  list.forEach((o) => addCustomRow(o.name, o.price));
}

async function saveDetail(id, recalcEdit) {
  const btn = $('mSave');
  const msg = $('mMsg');
  btn.disabled = true;
  msg.className = 'save-msg';
  msg.textContent = '저장 중...';
  const cv = (eid) => $(eid).value.trim();
  const cc = (eid) => $(eid).checked;
  const payload = {
    status: $('mStatus').value,
    admin_note: $('mNote').value,
    contractor_name: cv('e_contractor_name'),
    contractor_phone: cv('e_contractor_phone'),
    contractor_email: cv('e_contractor_email'),
    wedding_date: cv('e_wedding_date'),
    wedding_time: cv('e_wedding_time'),
    wedding_venue: cv('e_wedding_venue'),
    groom_name: cv('e_groom_name'),
    groom_phone: cv('e_groom_phone'),
    bride_name: cv('e_bride_name'),
    bride_phone: cv('e_bride_phone'),
    package: $('e_package') ? $('e_package').value : '베이직(데이터형)',
    travel_fee: cc('e_travel'),
    option_album: ($('e_album_qty') ? (parseInt($('e_album_qty').value, 10) || 0) : 0) > 0,
    option_album_qty: $('e_album_qty') ? (parseInt($('e_album_qty').value, 10) || 0) : 0,
    option_reception: cc('e_option_reception'),
    option_pyebaek: cc('e_option_pyebaek'),
    option_part2: cc('e_option_part2'),
    photographer: $('e_photographer').value,
    rep_designation: cc('e_rep'),
    photo_usage_agree: cc('e_usage'),
    agree_available: cc('e_agree_available'),
    agree_terms: cc('e_agree_terms'),
    total_price: recalcEdit(),
    deposit_paid: cc('e_deposit'),
    balance_paid: cc('e_balance'),
    assignee_id: $('e_assignee') ? $('e_assignee').value : '',
  };
  // 2인 촬영이 아니면 서브작가는 항상 비움(2인 → 기본 변경 시 잔존 방지)
  payload.sub_assignee_id = (payload.photographer === '2인 촬영' && $('e_sub_assignee')) ? ($('e_sub_assignee').value || null) : null;
  payload.custom_options = Array.from(document.querySelectorAll('#customOpts .co-row'))
    .map((r) => ({ name: r.querySelector('.co-name').value.trim(), price: Number(r.querySelector('.co-price').value) || 0 }))
    .filter((o) => o.name);
  payload.line_items = buildEditLineItems(); // 수정 내용으로 단가 스냅샷 갱신
  const { data, error } = await sb.rpc('admin_save_booking', { p_id: id, payload });
  btn.disabled = false;
  if (error) {
    msg.className = 'save-msg err';
    msg.textContent = '저장 실패: ' + error.message;
    return;
  }
  const i = allBookings.findIndex((x) => x.id === id);
  if (i >= 0 && data) allBookings[i] = data;
  render();
  renderDashboard();
  renderView(data || allBookings[i], '저장되었습니다.');
}

/* ===== Dashboard ===== */
function startOfToday() { const d = new Date(); d.setHours(0, 0, 0, 0); return d; }
function wDate(b) {
  if (!b.wedding_date) return null;
  const d = new Date(b.wedding_date); d.setHours(0, 0, 0, 0); return d;
}
const kTimeShort = (t) => {
  if (!t) return '';
  const [hh, mm] = String(t).split(':').map(Number);
  return (hh < 12 ? '오전' : '오후') + (hh % 12 === 0 ? 12 : hh % 12) + ':' + String(mm).padStart(2, '0');
};

// 알림톡을 못 받는 외국 고객(한국번호 없음) 등에게 수동발송할 문구 — 카톡에 붙여넣어 보냄.
// 실제 카카오 알림톡 템플릿(A~F)과 문구를 동일하게 맞춘다. 변수는 #{고객명} 하나뿐이고,
// 금액·계좌·일정 등 나머지 정보는 [내 예약 확인하기] 포털 페이지가 항상 최신으로 보여준다.
const ATK_MANUAL = {
  A: `#{고객명}님,

온더브라이드 본식스냅 예약이 접수되었습니다

신청하신 상품·옵션, 입금 계좌, 앞으로의 진행 안내, 예식 전 설문, 짝꿍·후기 이벤트까지

아래 [내 예약 확인하기]에서 한 번에 확인하실 수 있어요.

계약금 입금이 확인되면 예약이 확정됩니다.

궁금하신 점은 카카오톡 채널로 편하게 문의해 주세요. 😊`,
  B: `#{고객명}님,

예식이 한 달 앞으로 다가왔어요! 🤍

[내 예약 확인하기]에서 예식 정보가 맞는지 확인해 주시고, '예식 전 설문'을 미리 작성해 주세요.

짝꿍·후기 이벤트도 페이지에서 바로 신청하시면 혜택이 있어요!

예식 일주일 전 최종 스케줄 체크 안내 드리겠습니다!`,
  C: `#{고객명}님,

예식이 일주일 앞으로 다가왔어요!

[내 예약 확인하기]에서 스케줄이 맞는지 한번 더 확인 부탁드립니다!

· 담당 작가 확인
· 최종 스케줄 체크
· 잔금 결제 (계좌는 페이지에 안내)
· 예식 전 설문 (아직이면 꼭 작성 부탁드려요)

확인 후 잔금 결제까지 마쳐주시면 됩니다. 🤍`,
  D: `#{고객명}님,

예식이 코앞이에요! 😊

· 작가님은 예식 1시간 30분 전 도착합니다.
· 담당 작가 정보는 [내 예약 확인하기]에서 확인하실 수 있어요!

· 촬영본 원본은 예식 후 약 일주일 내 [내 예약 확인하기]에서 받으실 수 있어요. (잔금 입금 확인 후 활성화)

행복한 예식 되세요! 🤍`,
  E: `#{고객명}님,

온더브라이드로 본식스냅을 예약하신 고객님께 안내 드립니다!

소중한 예식 촬영본이 준비됐어요! 🤍

[내 예약 확인하기]의 '원본파일 다운로드'에서 받으실 수 있어요.

· 잔금 입금이 확인되면 다운로드가 열립니다.
· 링크는 3개월간 유지돼요. 기간 내 꼭 받아주세요.

궁금하신 점 있으시면 카톡으로 문의주세요!`,
  F: `#{고객명}님,

계약금 입금 확인되어 예약이 확정되었습니다.

궁금하신 점 있으시면 언제든 톡으로 문의주시면 바로 답변드리겠습니다!

감사합니다!`,
};
function atkManualText(b, tpl) {
  const name = b.contractor_name || '고객';
  const portal = `${location.origin}/portal?b=${b.id}`;
  const body = (ATK_MANUAL[tpl] || `#{고객명}님,`).replace(/#\{고객명\}/g, name);
  // 알림톡의 [내 예약 확인하기] 버튼은 수동발송 시 링크로 대체
  return `${body}\n\n▶ 내 예약 확인하기\n${portal}`;
}

// 목록을 예식 날짜별로 묶어 날짜 헤더 삽입
const dateGroupLabel = (dstr) => {
  if (!dstr) return '날짜 미정';
  const d = new Date(dstr);
  return `${d.getFullYear()}. ${d.getMonth() + 1}. ${d.getDate()}. (${WD[d.getDay()]})`;
};
function groupByDate(items, renderItem) {
  let last = null, out = '';
  for (const b of items) {
    if (b.wedding_date !== last) { out += `<div class="dl-datehdr">${esc(dateGroupLabel(b.wedding_date))}</div>`; last = b.wedding_date; }
    out += renderItem(b);
  }
  return out;
}

function toast(msg) {
  let el = $('toast');
  if (!el) { el = document.createElement('div'); el.id = 'toast'; el.className = 'toast'; document.body.appendChild(el); }
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => el.classList.remove('show'), 2600);
}

// 알림톡 실제 발송 (솔라피)
const ATK_NAME = { A: '계약안내', B: '한달전', C: '잔금안내', D: '최종안내', E: '링크안내', F: '입금확인', G: '촬영설문' };
async function sendAlimtalk(id, tpl) {
  const b = allBookings.find((x) => x.id === id);
  if (!confirm(`${b ? b.contractor_name + '님께 ' : ''}"${ATK_NAME[tpl] || tpl}" 알림톡을 실제로 발송할까요?`)) return;
  const { data, error } = await sb.rpc('admin_send_alimtalk', { p_booking_id: id, p_template: tpl });
  if (error) { alert('발송 실패: ' + error.message); return; }
  const i = allBookings.findIndex((x) => x.id === id);
  if (i >= 0) {
    if (!allBookings[i].alimtalk_sent || typeof allBookings[i].alimtalk_sent !== 'object') allBookings[i].alimtalk_sent = {};
    allBookings[i].alimtalk_sent[tpl] = new Date().toISOString();
  }
  toast(`"${ATK_NAME[tpl] || tpl}" 알림톡 발송 완료 📨`);
  renderDashboard();
  if (!$('modal').hidden && b) renderView(allBookings[i] || b);
}

// 작가 공유용 설문(읽기전용) 링크 복사 — 예식날짜·성함을 링크 위에 함께 복사
function copySurveyShare(id) {
  const b = allBookings.find((x) => x.id === id);
  // 배정된 작가를 링크에 실어야 그 작가 화면에 [확인했습니다] 단추가 뜬다.
  // 배정 전이면 그냥 읽기 전용 링크가 된다
  const url = location.origin + '/survey-view?b=' + id
    + (b && b.assignee_id ? '&s=' + b.assignee_id : '');
  const head = b ? `${fmtDate(b.wedding_date)} ${b.contractor_name || ''}`.trim() + ' 예식 설문' : '';
  const text = head ? `${head}\n${url}` : url;
  if (navigator.clipboard) navigator.clipboard.writeText(text);
  toast(surveyIds.has(id) ? '작가 공유용 설문 링크를 복사했어요 📋 (날짜·성함 포함)' : '설문 링크 복사 — 아직 고객이 설문 미작성 상태예요');
}

const ATK_FAIL_NAME = { A: '계약안내', B: '한달전', C: '일주일전·잔금', D: '전날', E: '촬영본 안내', F: '입금확인', G: '촬영 설문' };
const ATK_FAILCODE = { '3101': '발신프로필 오류', '3102': '카카오채널 친구 아님', '3103': '템플릿 불일치', '3104': '카카오톡 미사용자(번호 오류 등)', '3105': '미등록 템플릿', '3106': '메시지 타입 오류', '3107': '비활성/수신차단', '3108': '발송가능시간 외(08~20시)' };
const atkFailReason = (code) => (code ? (ATK_FAILCODE[code] || ('전달실패 코드 ' + code)) : '전달 실패');
const ATK_STATUS = (s) => ({
  completed: '<span style="color:#2f7d4f;font-weight:600">✅ 성공</span>',
  delivered: '<span style="color:#8a7a52;font-weight:600">📨 확인중</span>',
  sent: '<span style="color:#8a7a52;font-weight:600">📨 발송중</span>',
  failed: '<span style="color:#c0392b;font-weight:600">❌ 실패</span>',
  gaveup: '<span style="color:#c0392b;font-weight:600">❌ 실패</span>',
}[s] || esc(s || ''));
function renderAtkFail() {
  const card = $('card-atkfail');
  if (!card) return;
  const items = alimtalkFails || [];
  card.hidden = items.length === 0;
  $('dcAtkFail').textContent = items.length;
  if (!items.length) { $('listAtkFail').innerHTML = ''; return; }
  $('listAtkFail').innerHTML = items.map((f) => {
    const failed = f.status === 'failed' || f.status === 'gaveup';
    const detail = f.status === 'failed' ? '❌ ' + atkFailReason(f.fail_code)
      : f.status === 'gaveup' ? '발송 실패 (접수 안 됨)'
      : f.status === 'completed' ? '정상 전달됨'
      : '발송됨 · 결과 확인 중';
    return `
    <div class="dl-item${failed ? ' overdue' : ''}" data-id="${f.booking_id}">
      <div class="dl-main">
        <span class="dl-name">${esc(f.name || '-')} <b style="font-weight:600;color:var(--ink-soft)">${esc(ATK_FAIL_NAME[f.template] || f.template)}</b> ${ATK_STATUS(f.status)}</span>
        <span class="dl-meta">${esc(fmtDate(f.wedding_date))} · ${esc(detail)}</span>
      </div>
      <div class="dl-actions">
        ${failed ? `<button class="btn-sm atk-copytext" data-id="${f.booking_id}" data-tpl="${f.template}">📋 내용 복사</button>
        <button class="btn-sm btn-kakao-sm atk-resend" data-id="${f.booking_id}" data-tpl="${f.template}">다시 보내기</button>` : ''}
        <button class="btn-sm atk-dismiss" data-id="${f.booking_id}" data-tpl="${f.template}">✓ 확인</button>
      </div>
    </div>`;
  }).join('');
  $('listAtkFail').querySelectorAll('.atk-resend').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); resendFailed(btn.dataset.id, btn.dataset.tpl); }));
  $('listAtkFail').querySelectorAll('.atk-copytext').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); copyFailText(btn.dataset.id, btn.dataset.tpl); }));
  $('listAtkFail').querySelectorAll('.atk-dismiss').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); dismissFail(btn.dataset.id, btn.dataset.tpl); }));
  $('listAtkFail').querySelectorAll('.dl-main').forEach((m) =>
    m.addEventListener('click', () => openDetail(m.closest('.dl-item').dataset.id)));
}

async function resendFailed(id, tpl) {
  const b = allBookings.find((x) => x.id === id);
  if (!confirm(`${b ? b.contractor_name + '님께 ' : ''}"${ATK_FAIL_NAME[tpl] || tpl}" 알림톡을 다시 보낼까요?`)) return;
  const { error } = await sb.rpc('admin_send_alimtalk', { p_booking_id: id, p_template: tpl });
  if (error) { alert('재발송 실패: ' + error.message); return; }
  alimtalkFails = alimtalkFails.filter((f) => !(f.booking_id === id && f.template === tpl));
  toast('다시 보냈어요. (1분 뒤 결과 자동 확인)');
  renderAtkFail();
}

// 실패 건 메시지 본문 복사 (수동 발송용) — 본문 + 내 예약 확인 링크
function copyFailText(id, tpl) {
  const f = (alimtalkFails || []).find((x) => x.booking_id === id && x.template === tpl);
  const portal = location.origin + '/portal?b=' + id;
  const body = (f && f.text) ? f.text : '';
  const text = (body ? body + '\n\n' : '') + '▶ 내 예약 확인하기\n' + portal;
  copySchedText(text, '메시지 내용을 복사했어요 — 고객에게 직접 보내세요 📋');
}

// 발송 내역 '확인'(숨김) — 개별 (확인 즉시 숨김, 별도 확인창 없음)
async function dismissFail(id, tpl) {
  const { error } = await sb.rpc('admin_dismiss_alimtalk_fail', { p_booking_id: id, p_template: tpl });
  if (error) { alert('처리 실패: ' + error.message); return; }
  alimtalkFails = (alimtalkFails || []).filter((x) => !(x.booking_id === id && x.template === tpl));
  renderAtkFail();
}
// 발송 내역 전체 '확인'(숨김)
async function dismissAllAtk() {
  if (!confirm('발송 내역을 전부 확인 처리할까요? (목록에서 사라집니다)')) return;
  const { error } = await sb.rpc('admin_dismiss_alimtalk_all');
  if (error) { alert('처리 실패: ' + error.message); return; }
  alimtalkFails = [];
  toast('전체 확인 처리했어요.');
  renderAtkFail();
}
if ($('atkDismissAll')) $('atkDismissAll').addEventListener('click', dismissAllAtk);

/* ===== 할 일 리마인더 (상단 배너) ===== */
function renderReminders() {
  const bar = $('reminderBar');
  if (!bar) return;
  const items = reminders || [];
  bar.hidden = items.length === 0;
  if ($('remCount')) $('remCount').textContent = items.length;
  if (!items.length) { $('reminderList').innerHTML = ''; return; }
  $('reminderList').innerHTML = items.map((r) => {
    const ico = r.kind === 'staff_survey' ? '📋' : r.kind === 'survey_share' ? '📋' : '🗓';
    const openable = !!r.booking_id;
    // 알림톡을 대표 승인으로 내보내는 항목 — 자동 발송은 하지 않는다
    const sendable = r.kind === 'staff_survey' ? '설문 안내 발송'
                   : r.kind === 'weekly_schedule' ? '스케줄 톡 발송' : '';
    return `
    <div class="reminder-item" data-id="${r.id}">
      <span class="reminder-ico">${ico}</span>
      <div class="reminder-text${openable ? ' rem-open' : ''}"${openable ? ` data-bid="${r.booking_id}"` : ''}>
        <b>${esc(r.title)}</b>${r.body ? `<span>${esc(r.body)}</span>` : ''}
      </div>
      ${sendable ? `<button class="btn-sm btn-kakao-sm rem-send" data-id="${r.id}" data-kind="${esc(r.kind)}">${sendable}</button>` : ''}
      <button class="btn-sm rem-dismiss" data-id="${r.id}">✓ 확인</button>
    </div>`;
  }).join('');
  $('reminderList').querySelectorAll('.rem-send').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); sendReminderBatch(btn); }));
  $('reminderList').querySelectorAll('.rem-dismiss').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); dismissReminder(btn.dataset.id); }));
  $('reminderList').querySelectorAll('.rem-open').forEach((el) =>
    el.addEventListener('click', () => openDetail(el.dataset.bid)));
}


/* ===== '오늘 할 일'에서 알림톡 일괄 발송 =====
   자동으로 나가는 알림톡은 없다. 대표가 이 버튼을 눌러야 나간다.
   한 명씩 순서대로 보내고, 중간에 실패해도 나머지는 계속 보낸 뒤 결과를 알려준다. */
async function sendReminderBatch(btn) {
  const kind = btn.dataset.kind;
  const isSurvey = kind === 'staff_survey';
  const rpcList = isSurvey ? 'admin_staff_survey_targets' : 'admin_staff_check_targets';
  const { data, error } = await sb.rpc(rpcList);
  if (error) { alert('대상을 불러오지 못했습니다.\n' + error.message); return; }

  let list = (Array.isArray(data) ? data : []).filter((x) => x.has_phone);
  if (isSurvey) list = list.filter((x) => !x.sent);        // 이미 보낸 건 제외
  if (!list.length) {
    alert(isSurvey ? '보낼 대상이 없습니다. (이미 다 보냈거나 배정·연락처가 없습니다)'
                   : '보낼 대상이 없습니다. (모두 확인했거나 연락처가 없습니다)');
    return;
  }

  const lines = isSurvey
    ? list.map((x) => '· ' + x.staff_name + ' (' + x.role + ') — ' + x.line + (x.has_survey ? '' : ' ※설문 미작성'))
    : list.map((x) => '· ' + x.staff_name + ' — 미확인 ' + x.unchecked + '건');
  if (!confirm((isSurvey ? '내일 예식 담당 작가에게 설문 안내를 보냅니다.' : '작가에게 스케줄 확인 톡을 보냅니다.')
    + '\n\n' + lines.join('\n'))) return;

  btn.disabled = true;
  const before = btn.textContent;
  let ok = 0; const failed = [];
  for (const x of list) {
    btn.textContent = '보내는 중 ' + (ok + failed.length + 1) + '/' + list.length;
    const res = isSurvey
      ? await sb.rpc('admin_send_staff_survey', { p_booking_id: x.booking_id, p_staff_id: x.staff_id })
      : await sb.rpc('admin_send_staff_check', { p_staff_id: x.id });
    if (res.error) failed.push(x.staff_name + ' (' + res.error.message + ')'); else ok++;
  }
  btn.disabled = false;
  btn.textContent = before;

  if (failed.length) alert('보냄 ' + ok + '건 / 실패 ' + failed.length + '건\n\n' + failed.join('\n'));
  else { toast(ok + '건 보냈습니다'); await dismissReminder(btn.dataset.id); }
}

async function dismissReminder(id) {
  const { error } = await sb.rpc('admin_reminder_dismiss', { p_id: id });
  if (error) { alert('처리 실패: ' + error.message); return; }
  reminders = (reminders || []).filter((r) => r.id !== id);
  renderReminders();
}

async function dismissAllReminders() {
  if (!confirm('할 일 알림을 전부 확인 처리할까요? (배너에서 사라집니다)')) return;
  const { error } = await sb.rpc('admin_reminders_dismiss_all');
  if (error) { alert('처리 실패: ' + error.message); return; }
  reminders = [];
  renderReminders();
}
if ($('remDismissAll')) $('remDismissAll').addEventListener('click', dismissAllReminders);

function renderDashboard() {
  if (!$('tab-dashboard')) return;
  renderAtkFail();
  renderHomeStats();          // 홈의 「한눈에」 — 늦게 와도 되니 기다리지 않는다
  const today = startOfToday();

  // 🔔 신규 예약 (계약안내 보내기 전)
  const news = allBookings.filter((b) => b.status === '신규' && !(b.alimtalk_sent && b.alimtalk_sent.A))
    .sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  $('dcNew').textContent = news.length;
  $('listNew').innerHTML = news.length
    ? news.slice(0, 40).map((b) => `
      <div class="dl-item" data-id="${b.id}">
        <div class="dl-main">
          <span class="dl-name">${esc(b.contractor_name || '-')}${phBadge(b)}</span>
          <span class="dl-meta">${esc(fmtDate(b.wedding_date))} · ${esc(b.wedding_venue || '-')} · ${esc(won(b.total_price))}</span>
        </div>
        <div class="dl-actions">
          <button class="btn-sm btn-kakao-sm" data-send="${b.id}" data-tpl="A">계약안내 전송</button>
        </div>
      </div>`).join('')
    : '<p class="dash-empty">새 예약이 없어요.</p>';

  // 📅 다가오는 예식 (오늘 ~ 일주일)
  const in7 = new Date(today); in7.setDate(in7.getDate() + 7);
  const upcoming = allBookings.filter((b) => { const d = wDate(b); return d && d >= today && d <= in7 && b.status === '확정'; })
    .sort((a, b) => wDate(a) - wDate(b));
  $('dcUpcoming').textContent = upcoming.length;
  // 작가 확인 여부 맵 (admin_unconfirmed: main_ok/sub_ok)
  const confMap = {};
  allUnconfirmed.forEach((u) => { confMap[u.booking_id] = u; });
  $('listUpcoming').innerHTML = upcoming.length
    ? groupByDate(upcoming, (b) => {
      const d = wDate(b);
      const dleft = Math.round((d - today) / 86400000);
      const dtag = dleft === 0 ? '오늘' : 'D-' + dleft;
      const mainSent = !!b.check_sent_at;
      const subSent = !!b.sub_check_sent_at;
      const needsSub = b.photographer === '2인 촬영' && !!b.sub_assignee_id;
      // 2인 촬영이면 서브작가도 함께 보여준다 (대표 요청) — 누가 같이 가는지 목록에서 바로 보이게
      const asgBadge = b.assignee_id
        ? `<span class="dl-asgs">
             <span class="dl-asg" style="color:${staffColor(b.assignee_id)}">● ${esc(staffName(b.assignee_id))}</span>
             ${needsSub ? `<span class="dl-asg sub" style="color:${staffColor(b.sub_assignee_id)}">＋ ${esc(staffName(b.sub_assignee_id))}</span>` : ''}
           </span>`
        : '<span class="dl-asg none">미배정</span>';
      const conf = confMap[b.id];
      const mainOk = !!(conf && conf.main_ok);
      const subOk = !!(conf && conf.sub_ok);
      const roleFlag = (sent, ok, role) => ok
        ? `<span class="chk-confirmed">${role} 확인 ✓</span>`
        : (sent ? '<span class="chk-sentflag">보냄 ✓</span>' : '');
      // 설문 복사는 첫 줄 오른쪽 끝에 붙인다 — 아래로 한 줄 더 내려가지 않게 (대표 요청)
      const svCopyBtn = (x) => `<button class="btn-sm sv-copy${surveyIds.has(x.id) ? '' : ' muted'}" data-id="${x.id}">${surveyIds.has(x.id) ? '설문 복사' : '설문 복사(미작성)'}</button>`;
      return `
      <div class="dl-item soon" data-id="${b.id}">
        <div class="dl-main">
          <div class="dl-toprow">
            <span class="dl-name">${esc(b.contractor_name || '-')}${phBadge(b)} <span class="dday">${dtag}</span></span>
            ${asgBadge}
          </div>
          <span class="dl-meta">${esc(fmtDate(b.wedding_date))} ${esc(kTimeShort(b.wedding_time))} · ${esc(b.wedding_venue || '-')}</span>
        </div>
        <div class="dl-actions">
          ${b.assignee_id
            ? `<div class="chk-rolerow">
                 <button class="btn-sm chk-send" data-id="${b.id}" data-staff="${b.assignee_id}" data-role="메인">${mainSent ? '메인 재전송' : '메인 체크'}</button>
                 <button class="btn-sm btn-kakao-sm chk-share" data-id="${b.id}" data-staff="${b.assignee_id}" data-role="메인" title="카톡으로 공유">공유</button>
                 ${roleFlag(mainSent, mainOk, '메인')}
                 ${svCopyBtn(b)}
               </div>
               ${needsSub ? `<div class="chk-rolerow">
                 <button class="btn-sm chk-send" data-id="${b.id}" data-staff="${b.sub_assignee_id}" data-role="서브">${subSent ? '서브 재전송' : '서브 체크'}</button>
                 <button class="btn-sm btn-kakao-sm chk-share" data-id="${b.id}" data-staff="${b.sub_assignee_id}" data-role="서브" title="카톡으로 공유">공유</button>
                 ${roleFlag(subSent, subOk, '서브')}
               </div>` : ''}`
            : `<div class="chk-rolerow"><span class="dl-na">작가 미배정</span>${svCopyBtn(b)}</div>`}
        </div>
      </div>`;
    })
    : '<p class="dash-empty">일주일 내 예식이 없어요.</p>';

  // 💳 미입금 (계약금 / 잔금)
  const byDate = (a, b) => (wDate(a) || 0) - (wDate(b) || 0);
  // 계약금 미입금: 계약안내(A) 보낸 뒤 ~ 입금 확인 전 ('미입금'으로 분류한 건은 팔로업 목록에서 제외)
  const depUnpaid = allBookings.filter((b) => b.alimtalk_sent && b.alimtalk_sent.A && !b.deposit_paid && notCancelled(b) && b.status !== '미입금').sort(byDate);
  // 잔금 미입금: 잔금안내(C) 보낸 뒤 ~ 입금 확인 전
  const balUnpaid = allBookings.filter((b) => b.alimtalk_sent && b.alimtalk_sent.C && !b.balance_paid && notCancelled(b) && b.status !== '미입금').sort(byDate);
  const nowMs = Date.now();
  const unpaidItem = (b, kind) => {
    const amt = kind === 'deposit' ? won(10) : (effBalance(b) != null ? won(effBalance(b)) : '-');
    const sent = b.alimtalk_sent && b.alimtalk_sent[kind === 'deposit' ? 'A' : 'C'];
    const days = sent ? Math.floor((nowMs - new Date(sent).getTime()) / 86400000) : 0;
    const overdue = days >= 5;
    return `
    <div class="dl-item${overdue ? ' overdue' : ''}" data-id="${b.id}">
      <div class="dl-main">
        <span class="dl-name">${esc(b.contractor_name || '-')}${phBadge(b)}${overdue ? ` <span class="od-badge">⚠️ ${days}일 미입금</span>` : ''}</span>
        <span class="dl-meta">${esc(fmtDate(b.wedding_date))} · ${esc(b.wedding_venue || '-')} · ${kind === 'deposit' ? '계약금' : '잔금'} ${esc(amt)}</span>
      </div>
      <div class="dl-actions">
        <button class="btn-sm dl-paid" data-id="${b.id}" data-pay="${kind}">${kind === 'deposit' ? '계약금 확인' : '잔금 확인'}</button>
        ${overdue && kind === 'deposit' ? `<button class="btn-sm od-unpaid" data-id="${b.id}">미입금 처리</button>` : ''}
        ${overdue && kind === 'deposit' ? `<button class="btn-sm od-cancel" data-id="${b.id}">예약 취소</button>` : ''}
      </div>
    </div>`;
  };
  $('dcUnpaid').textContent = depUnpaid.length + balUnpaid.length;
  // 선택 탭이 비어 있고 다른 탭에 미입금이 있으면 그 탭을 우선 표시
  let activeTab = unpaidTab;
  if (activeTab === 'deposit' && depUnpaid.length === 0 && balUnpaid.length > 0) activeTab = 'balance';
  else if (activeTab === 'balance' && balUnpaid.length === 0 && depUnpaid.length > 0) activeTab = 'deposit';
  const activeUnpaid = activeTab === 'balance' ? balUnpaid : depUnpaid;
  $('listUnpaid').innerHTML =
    `<div class="unpaid-tabs">
      <button class="upt${activeTab === 'deposit' ? ' active' : ''}" data-upt="deposit">계약금 ${depUnpaid.length}</button>
      <button class="upt${activeTab === 'balance' ? ' active' : ''}" data-upt="balance">잔금 ${balUnpaid.length}</button>
    </div>` +
    (activeUnpaid.length
      ? activeUnpaid.slice(0, 40).map((b) => unpaidItem(b, activeTab)).join('')
      : '<p class="dash-empty sm">없음</p>');

  // ⬇️ 다운로드 링크 필요 (예식 당일·이후 + E 미발송)
  const endToday = new Date(today); endToday.setHours(23, 59, 59, 999);
  const needDl = allBookings.filter((b) => { const d = wDate(b); return d && d <= endToday && !(b.alimtalk_sent && b.alimtalk_sent.E) && notCancelled(b) && b.status !== '미입금'; })
    .sort((a, b) => wDate(b) - wDate(a));
  $('dcDownload').textContent = needDl.length;
  $('listDownload').innerHTML = needDl.length
    ? groupByDate(needDl.slice(0, 40), (b) => {
        const dlrow = b.balance_paid
          ? `<div class="dl-dlrow">
               <input type="text" class="dl-link" data-id="${b.id}" placeholder="다운로드 링크 붙여넣기" value="${esc(b.download_link || '')}" />
               <button class="btn-sm dl-save" data-id="${b.id}">저장</button>
               <button class="btn-sm dbx-row-btn" data-id="${b.id}">📦 드롭박스</button>
               <button class="btn-sm btn-kakao-sm" data-send="${b.id}" data-tpl="E">카톡 전송</button>
             </div>
             <div class="dbx-box" data-id="${b.id}"></div>`
          : `<div class="dl-dlrow dl-blocked">
               <span class="dl-blocked-msg">🔒 잔금 입금 확인 후 링크 입력 가능</span>
               <button class="btn-sm dl-paid" data-id="${b.id}" data-pay="balance">잔금 확인</button>
             </div>`;
        return `
      <div class="dl-item dl-download" data-id="${b.id}">
        <div class="dl-main">
          <span class="dl-name">${esc(b.contractor_name || '-')}${phBadge(b)}</span>
          <span class="dl-meta">${esc(fmtDate(b.wedding_date))} · ${esc(b.wedding_venue || '-')}</span>
        </div>
        ${dlrow}
      </div>`;
      })
    : '<p class="dash-empty">모두 처리됐어요 👍</p>';

  // 🧑‍🎨 작가 미확인 (30일 내)
  const unconf = allUnconfirmed.filter((u) => !u.main_ok || !u.sub_ok);
  if ($('dcUnconf')) $('dcUnconf').textContent = unconf.length;
  if ($('listUnconf')) $('listUnconf').innerHTML = unconf.length
    ? unconf.slice(0, 40).map((u) => {
      const who = [];
      if (!u.main_ok && u.assignee_id) who.push('메인 ' + staffName(u.assignee_id));
      if (!u.sub_ok && u.sub_assignee_id) who.push('서브 ' + staffName(u.sub_assignee_id));
      return `<div class="dl-item" data-id="${u.booking_id}">
        <div class="dl-main">
          <span class="dl-name">${esc(u.contractor_name || '-')}</span>
          <span class="dl-meta">${esc(fmtDate(u.wedding_date))} ${esc(kTimeShort(u.wedding_time))} · ${esc(u.wedding_venue || '-')} · <span class="unconf-who">${esc(who.join(', ') || '미확인')}</span></span>
        </div>
      </div>`;
    }).join('')
    : '<p class="dash-empty">모두 확인됐어요 👍</p>';

  bindDashEvents();
  renderCalendar();
  renderSchedule();
}

function bindDashEvents() {
  // 미입금 탭(계약금/잔금)
  document.querySelectorAll('#listUnpaid .upt').forEach((btn) =>
    btn.addEventListener('click', () => { unpaidTab = btn.dataset.upt; renderDashboard(); })
  );
  // 작가 체크 링크 전송(복사 + 보냄 표시)
  document.querySelectorAll('#tab-dashboard .chk-send').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); copyCheckLink(btn.dataset.id, btn.dataset.staff, `${btn.dataset.role} 작가(${staffName(btn.dataset.staff)})`, btn.dataset.role); })
  );
  // 작가 체크 링크 카톡 공유(공유 시트 + 보냄 표시)
  document.querySelectorAll('#tab-dashboard .chk-share').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); shareCheckLink(btn.dataset.id, btn.dataset.staff, `${btn.dataset.role} 작가(${staffName(btn.dataset.staff)})`, btn.dataset.role); })
  );
  // 작가 공유용 설문 링크 복사
  document.querySelectorAll('#tab-dashboard .sv-copy').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); copySurveyShare(btn.dataset.id); })
  );
  // 항목(이름/메타) 클릭 → 상세
  document.querySelectorAll('#tab-dashboard .dl-main').forEach((m) =>
    m.addEventListener('click', () => openDetail(m.closest('.dl-item').dataset.id))
  );
  // 카톡 전송
  document.querySelectorAll('#tab-dashboard [data-send]').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); sendAlimtalk(btn.dataset.send, btn.dataset.tpl); })
  );
  // 5일+ 미입금 → '미입금'으로 분류 (취소와 달리 기록·목록 유지, 미입금 탭으로 이동)
  document.querySelectorAll('#tab-dashboard .od-unpaid').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); markUnpaid(btn.dataset.id); })
  );
  // 5일+ 미입금 → 예약 취소
  document.querySelectorAll('#tab-dashboard .od-cancel').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); cancelBooking(btn.dataset.id); })
  );
  // 입금 확인 (계약금/잔금)
  document.querySelectorAll('#tab-dashboard .dl-paid').forEach((btn) =>
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const id = btn.dataset.id;
      const kind = btn.dataset.pay;
      const fn = kind === 'balance' ? 'admin_set_balance' : 'admin_set_deposit';
      btn.disabled = true;
      const { data, error } = await sb.rpc(fn, { p_id: id, p_paid: true });
      if (error) { btn.disabled = false; alert('처리 실패: ' + error.message); return; }
      const i = allBookings.findIndex((x) => x.id === id);
      if (i >= 0 && data) allBookings[i] = data;
      toast((kind === 'balance' ? '잔금' : '계약금') + ' 입금 확인했어요.');
      renderDashboard();
      // 계약금 확인 시 입금확인 알림톡(F) 발송 — 이미 보냈으면 생략
      const nb = allBookings[i] || data;
      if (kind === 'deposit' && !(nb && nb.alimtalk_sent && nb.alimtalk_sent.F)) sendAlimtalk(id, 'F');
    })
  );
  // 홈 목록에서 드롭박스 폴더 골라 공유
  document.querySelectorAll('#tab-dashboard .dbx-row-btn').forEach((btn) =>
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const id = btn.dataset.id;
      const b = allBookings.find((x) => x.id === id);
      if (!b) return;
      dbxShare(b, btn,
        document.querySelector('#tab-dashboard .dbx-box[data-id="' + id + '"]'),
        document.querySelector('#tab-dashboard .dl-link[data-id="' + id + '"]'));
    })
  );

  // 다운로드 링크 저장
  document.querySelectorAll('#tab-dashboard .dl-save').forEach((btn) =>
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const id = btn.dataset.id;
      const inp = document.querySelector(`#tab-dashboard .dl-link[data-id="${id}"]`);
      btn.disabled = true; btn.textContent = '저장중';
      const { data, error } = await sb.rpc('admin_set_download_link', { p_id: id, p_link: inp.value.trim() });
      btn.disabled = false;
      if (error) { btn.textContent = '저장'; alert('저장 실패: ' + error.message); return; }
      const i = allBookings.findIndex((x) => x.id === id);
      if (i >= 0 && data) allBookings[i] = data;
      btn.textContent = '저장됨 ✓';
      setTimeout(() => { btn.textContent = '저장'; }, 1500);
    })
  );
}

function renderCalendar() {
  if (!calMonth) { const t = new Date(); calMonth = { y: t.getFullYear(), m: t.getMonth() }; }
  const { y, m } = calMonth;
  document.querySelectorAll('.cal-label').forEach((el) => (el.textContent = `${y}년 ${m + 1}월`));
  const startDay = new Date(y, m, 1).getDay();
  const days = new Date(y, m + 1, 0).getDate();
  const today = startOfToday();

  const byDay = {};
  allBookings.forEach((b) => {
    const d = wDate(b);
    if (d && d.getFullYear() === y && d.getMonth() === m && notCancelled(b) && b.deposit_paid) (byDay[d.getDate()] = byDay[d.getDate()] || []).push(b);
  });

  const legend = allStaff.filter((s) => s.active).map((s) => `<span class="cal-leg"><i style="background:${staffColor(s.id)}"></i>${esc(s.name)}</span>`).join('');
  let html = legend ? `<div class="cal-legend">${legend}</div>` : '';
  html += '<div class="cal-grid">';
  ['일', '월', '화', '수', '목', '금', '토'].forEach((w) => (html += `<div class="cal-wd">${w}</div>`));
  for (let i = 0; i < startDay; i++) html += '<div class="cal-cell empty"></div>';
  for (let dnum = 1; dnum <= days; dnum++) {
    const items = (byDay[dnum] || []).sort((a, b) => (a.wedding_time || '').localeCompare(b.wedding_time || ''));
    const isToday = today.getFullYear() === y && today.getMonth() === m && today.getDate() === dnum;
    const cnt = items.length;
    const bal = items.filter((b) => !b.balance_paid).length;
    const noAsg = items.filter((b) => !b.assignee_id).length;
    const subNoAsg = items.filter((b) => b.photographer === '2인 촬영' && !b.sub_assignee_id).length;
    const dots = items.slice(0, 12).map((b) => `<i style="background:${staffColor(b.assignee_id) || '#c9c4bc'}"></i>`).join('');
    html += `<div class="cal-cell${isToday ? ' today' : ''}${cnt ? ' has' : ''}"${cnt ? ` data-day="${dnum}"` : ''}>
      <span class="cal-d">${dnum}</span>
      ${cnt ? `<div class="cal-dots">${dots}</div>
        <div class="cal-sum"><b>${cnt}건</b>${noAsg ? `<span class="cal-flag asg">미배정 ${noAsg}</span>` : ''}${subNoAsg ? `<span class="cal-flag subasg">서브 ${subNoAsg}</span>` : ''}${bal ? `<span class="cal-flag bal">잔금 ${bal}</span>` : ''}</div>` : ''}
    </div>`;
  }
  html += '</div>';
  document.querySelectorAll('.cal-mount').forEach((mount) => {
    mount.innerHTML = html;
    mount.querySelectorAll('.cal-cell.has').forEach((c) =>
      c.addEventListener('click', () => showDayList(y, m, +c.dataset.day))
    );
  });
  renderDayOv(); // 열려있는 날짜 팝업도 현재 데이터로 갱신
}

// 특정 날짜의 (확정·미취소) 예약을 시간순으로
function dayItems(y, m, d) {
  return allBookings.filter((b) => {
    const dt = wDate(b);
    return dt && dt.getFullYear() === y && dt.getMonth() === m && dt.getDate() === d && notCancelled(b) && b.deposit_paid;
  }).sort((a, b) => (a.wedding_time || '').localeCompare(b.wedding_time || ''));
}
function showDayList(y, m, d) { dayOvKey = { y, m, d }; renderDayOv(); }

function closeDayOv() { dayOvKey = null; const o = document.getElementById('dayOv'); if (o) o.remove(); }
function renderDayOv() {
  if (!dayOvKey) return;
  const { y, m, d } = dayOvKey;
  const sorted = dayItems(y, m, d);
  const old = document.getElementById('dayOv');
  if (sorted.length === 0) { closeDayOv(); return; } // 그날 예약이 다 없어지면 팝업 닫기
  const label = `${y}년 ${m + 1}월 ${d}일`;
  if (old) old.remove();
  const ov = document.createElement('div');
  ov.id = 'dayOv';
  ov.className = 'day-ov';
  ov.innerHTML = `<div class="day-ov-bg"></div>
    <div class="day-ov-card">
      <div class="day-ov-head"><strong>${esc(label)}</strong> <span class="muted">${sorted.length}건</span><button class="day-ov-x" aria-label="닫기">&times;</button></div>
      <div class="day-ov-list">${sorted.map((b) => {
        const main = b.assignee_id
          ? `<span class="dchip ok" style="color:${staffColor(b.assignee_id)}">● ${esc(staffName(b.assignee_id))}</span>`
          : '<span class="dchip warn">메인 미배정</span>';
        const sub = b.photographer === '2인 촬영'
          ? (b.sub_assignee_id ? `<span class="dchip ok" style="color:${staffColor(b.sub_assignee_id)}">● ${esc(staffName(b.sub_assignee_id))}</span>` : '<span class="dchip warn">서브 미배정</span>')
          : '';
        const balf = !b.balance_paid ? '<span class="dchip bal">잔금 미입금</span>' : '';
        return `<button class="day-ov-item" data-id="${b.id}">
          <span class="day-ov-time">${esc(kTimeShort(b.wedding_time)) || '-'}</span>
          <span class="day-ov-name">${esc(b.contractor_name || '-')}${phBadge(b)}</span>
          <span class="day-ov-venue">${esc(b.wedding_venue || '-')}</span>
          <span class="day-ov-status">${main}${sub}${balf}</span>
        </button>`;
      }).join('')}</div>
    </div>`;
  document.body.appendChild(ov);
  ov.querySelector('.day-ov-bg').addEventListener('click', closeDayOv);
  ov.querySelector('.day-ov-x').addEventListener('click', closeDayOv);
  ov.querySelectorAll('.day-ov-item').forEach((it) => it.addEventListener('click', () => openDetail(it.dataset.id)));
}

function ensureCalMonth() { if (!calMonth) { const t = new Date(); calMonth = { y: t.getFullYear(), m: t.getMonth() }; } }
document.querySelectorAll('.cal-prev').forEach((b) =>
  b.addEventListener('click', () => { ensureCalMonth(); calMonth.m--; if (calMonth.m < 0) { calMonth.m = 11; calMonth.y--; } renderCalendar(); renderSchedule(); }));
document.querySelectorAll('.cal-next').forEach((b) =>
  b.addEventListener('click', () => { ensureCalMonth(); calMonth.m++; if (calMonth.m > 11) { calMonth.m = 0; calMonth.y++; } renderCalendar(); renderSchedule(); }));
document.querySelectorAll('.cal-today').forEach((b) =>
  b.addEventListener('click', () => { const t = new Date(); calMonth = { y: t.getFullYear(), m: t.getMonth() }; renderCalendar(); renderSchedule(); }));

/* ===== 날짜 조회 · 배정 가능 작가 =====
   문의가 왔을 때 "그날 받을 수 있나"를 바로 보기 위한 화면.
   가능 여부는 서버(admin_day_check → admin_staff_availability)가 판단하고,
   여기서는 보여주기만 한다. 순서: 가능한 사람 먼저 → 평점 → 최근 배정 적은 순 */
// 평점은 100점 만점 가중 점수다 (도착25·친절25·요청15·진행15·하객20, 전체만족도는 뺌)
function dcStar(s) {
  if (s.fb_avg == null) return '<span class="dc-none">평가 없음</span>';
  return `<b>${Number(s.fb_avg).toFixed(1)}</b><small>점 · ${s.fb_n}건</small>`
    + (s.fb_n < FB_THIN ? '<small class="dc-thin">응답 적음</small>' : '');
}
function dayCheckHtml(r) {
  const d = new Date(String(r.the_date).slice(0, 10) + 'T00:00:00');
  const label = `${d.getMonth() + 1}월 ${d.getDate()}일 (${WD[d.getDay()]})`
    + (r.at_time ? ' ' + (kTimeShort(r.at_time) || r.at_time) : '');
  const can = r.ok_n > 0;
  const head = `<div class="dc-head ${can ? 'can' : 'cant'}">
      <b>${esc(label)}</b>
      <span>${can ? `메인 가능 ${r.ok_n}명 / ${r.total_n}명` : '메인을 맡을 작가가 없습니다'}`
    + (r.ok_sub_n != null ? ` · 서브 가능 ${r.ok_sub_n}명` : '') + `</span>
    </div>`;

  const w = r.weddings || [];
  const weds = w.length
    ? `<p class="dc-sub">이 날 예식 ${w.length}건</p>
       <ul class="dc-weds">${w.map((x) => `<li><b>${esc(kTimeShort(x.wedding_time) || '-')}</b>
         ${esc(x.contractor_name || '')} · ${esc(x.wedding_venue || '-')}
         <span>${x.main_name ? esc(x.main_name) : '미배정'}${x.sub_name ? ' + ' + esc(x.sub_name) : ''}</span></li>`).join('')}</ul>`
    : '<p class="dc-sub">이 날 잡힌 예식은 없습니다.</p>';

  let rank = 0;
  const row = (s) => {
    const badge = s.status === 'ok' ? '<span class="dc-b ok">가능</span>'
      : s.status === 'off' ? '<span class="dc-b off">불가</span>'
      : r.at_time ? '<span class="dc-b tight">겹침</span>'
      : '<span class="dc-b tight">일정 있음</span>';
    // 순위는 '메인을 맡을 수 있고 그날 되는' 작가에게만 매긴다
    const main = s.can_main !== false;
    const ranked = s.status === 'ok' && main;
    if (ranked) rank += 1;
    return `<li class="dc-row ${esc(s.status)}${main ? '' : ' subonly'}">
      <span class="dc-rank">${ranked ? rank : '·'}</span>
      <span class="dc-name">${esc(s.name)}${main ? '' : '<span class="dc-role">서브 전용</span>'}</span>
      <span class="dc-star">${dcStar(s)}</span>
      <span class="dc-load">최근 배정 ${s.load_n}건</span>
      ${badge}
      ${s.detail ? `<span class="dc-detail">${esc(s.detail)}</span>` : ''}
    </li>`;
  };
  // 작가가 많으면 다 보기 불편하다 → 위 3명만 두고 나머지는 접는다
  const list = r.staff || [];
  const top = list.slice(0, 3).map(row).join('');
  const rest = list.slice(3).map(row).join('');

  const notes = [];
  if (!r.at_time) {
    notes.push('시간을 안 넣으면 그날 일정이 있는 작가는 모두 «일정 있음»으로 둡니다.'
      + ' 시간을 넣으면 4시간 규칙으로 정확히 봅니다.');
  }
  if ((r.fb_total || 0) < 10) {
    notes.push(`촬영 후 설문이 아직 ${r.fb_total || 0}건이라 평점 순위는 참고만 해주세요.`
      + ' 평점이 없는 작가는 최근 배정이 적은 순으로 놓았습니다.');
  }
  return head + weds
    + `<ol class="dc-staff">${top}</ol>`
    + (rest ? `<ol class="dc-staff" id="dcRest" hidden>${rest}</ol>
         <button type="button" class="btn-sm dc-more" id="dcMore">나머지 ${list.length - 3}명 더보기</button>` : '')
    + (notes.length ? `<p class="dc-note">${notes.map(esc).join('<br />')}</p>` : '');
}
/* ── 문의 글에서 날짜·시간 읽어내기 (대표 요청) ──────────────
   카톡으로 온 문의를 그대로 붙여넣으면 날짜 칸을 채워준다.
   AI 를 부르지 않고 규칙으로 읽는다 — 즉시 나오고, 돈이 안 들고, 늘 같은 답을 준다.
   대신 «이렇게 읽었습니다» 를 화면에 보여줘서 대표가 눈으로 확인하게 한다. */
function dcParse(text, today) {
  const now = today || new Date();
  let s = String(text || '');
  // 전화번호·금액·장수를 먼저 걷어낸다 — 010-3931-1365 를 날짜로 읽으면 안 된다
  s = s.replace(/01[016-9][-. ]?\d{3,4}[-. ]?\d{4}/g, ' ')
       .replace(/\d+\s*만\s*원|\d+\s*원|\d+\s*장|\d+\s*명|\d+\s*인/g, ' ');

  let y = null, mo = null, d = null;
  const pick = (yy, mm, dd) => { y = yy; mo = mm; d = dd; };
  let m;
  // 2026-10-03 · 2026.10.3 · 2026/10/03 · 2026년 10월 3일
  if ((m = s.match(/(20\d{2})\s*[-./년]\s*(\d{1,2})\s*[-./월]\s*(\d{1,2})/))) pick(+m[1], +m[2], +m[3]);
  // 26.10.03 · 26년 10월 3일
  else if ((m = s.match(/(?:^|[^\d])(\d{2})\s*[-./년]\s*(\d{1,2})\s*[-./월]\s*(\d{1,2})(?!\d)/))) pick(2000 + +m[1], +m[2], +m[3]);
  // 20261003 · 261003
  else if ((m = s.match(/(?:^|[^\d])(20\d{2})(\d{2})(\d{2})(?!\d)/))) pick(+m[1], +m[2], +m[3]);
  else if ((m = s.match(/(?:^|[^\d])(\d{2})(\d{2})(\d{2})(?!\d)/))) pick(2000 + +m[1], +m[2], +m[3]);
  // 10월 3일 · 10/3 · 10.3  (연도는 아래서 정한다)
  else if ((m = s.match(/(\d{1,2})\s*월\s*(\d{1,2})\s*일?/))) pick(null, +m[1], +m[2]);
  else if ((m = s.match(/(?:^|[^\d])(\d{1,2})\s*[/.]\s*(\d{1,2})(?!\d)/))) pick(null, +m[1], +m[2]);
  // 오늘·내일·모레
  else if (/글피/.test(s)) { const t = new Date(now); t.setDate(t.getDate() + 3); pick(t.getFullYear(), t.getMonth() + 1, t.getDate()); }
  else if (/모레/.test(s)) { const t = new Date(now); t.setDate(t.getDate() + 2); pick(t.getFullYear(), t.getMonth() + 1, t.getDate()); }
  else if (/내일/.test(s)) { const t = new Date(now); t.setDate(t.getDate() + 1); pick(t.getFullYear(), t.getMonth() + 1, t.getDate()); }
  else if (/오늘/.test(s)) pick(now.getFullYear(), now.getMonth() + 1, now.getDate());

  if (mo == null || mo < 1 || mo > 12 || d == null || d < 1 || d > 31) return { date: null, time: null };
  // 연도를 안 적었으면 «앞으로 오는 그날» 로 — 예식 문의는 지난 날을 묻지 않는다
  if (y == null) {
    y = now.getFullYear();
    const today0 = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    if (new Date(y, mo - 1, d) < today0) y += 1;
  }
  const dt = new Date(y, mo - 1, d);
  if (dt.getMonth() !== mo - 1 || dt.getDate() !== d) return { date: null, time: null };  // 2월 30일 같은 것
  const date = `${y}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

  /* ── 시간 ── */
  let hh = null, mi = 0, ampm = null;
  if (/오전|아침/.test(s)) ampm = 'am';
  else if (/오후|저녁|낮/.test(s)) ampm = 'pm';
  // 날짜로 이미 쓴 부분은 시간 후보에서 뺀다
  const rest = m ? s.replace(m[0], ' ') : s;
  let t2;
  if ((t2 = rest.match(/(\d{1,2})\s*:\s*(\d{2})/))) { hh = +t2[1]; mi = +t2[2]; }
  else if ((t2 = rest.match(/(\d{1,2})\s*시\s*(?:(\d{1,2})\s*분|(반))?/))) {
    hh = +t2[1]; mi = t2[3] ? 30 : (t2[2] ? +t2[2] : 0);
  }
  if (hh == null) return { date, time: null };
  if (ampm === 'pm' && hh < 12) hh += 12;
  else if (ampm === 'am' && hh === 12) hh = 0;
  // 오전·오후를 안 적은 한 자리 시각은 낮으로 본다 — 예식은 새벽에 없다
  else if (ampm == null && hh >= 1 && hh <= 7) hh += 12;
  if (hh > 23 || mi > 59) return { date, time: null };
  return { date, time: `${String(hh).padStart(2, '0')}:${String(mi).padStart(2, '0')}` };
}

async function dayCheck() {
  const box = $('dcResult');
  const d = $('dcDate') ? $('dcDate').value : '';
  if (!box) return;
  if (!d) { box.innerHTML = '<p class="dash-empty">날짜를 선택해 주세요.</p>'; return; }
  box.innerHTML = '<p class="dash-empty">확인 중…</p>';
  const { data, error } = await sb.rpc('admin_day_check', { p_date: d, p_time: $('dcTime').value || null });
  if (error) { box.innerHTML = `<p class="dash-empty">${esc(error.message)}</p>`; return; }
  box.innerHTML = dayCheckHtml(data);
  const more = $('dcMore');
  if (more) more.addEventListener('click', () => {
    const rest = $('dcRest');
    rest.hidden = !rest.hidden;
    more.textContent = rest.hidden ? `나머지 ${rest.children.length}명 더보기` : '접기';
  });
}
// 붙여넣은 글에서 날짜를 읽어 칸을 채우고 바로 조회한다
function dcFromPaste() {
  const inp = $('dcPaste'), read = $('dcRead');
  if (!inp || !read) return;
  const txt = inp.value.trim();
  if (!txt) { read.textContent = ''; read.className = 'dc-read'; return; }
  const r = dcParse(txt);
  if (!r.date) {
    read.textContent = '날짜를 못 찾았어요. 아래에서 직접 골라주세요.';
    read.className = 'dc-read miss';
    return;
  }
  $('dcDate').value = r.date;
  $('dcTime').value = r.time || '';
  const d = new Date(r.date + 'T00:00:00');
  read.textContent = `${d.getFullYear()}년 ${d.getMonth() + 1}월 ${d.getDate()}일 (${WD[d.getDay()]})`
    + (r.time ? ' ' + kTimeShort(r.time) : ' · 시간 없음') + ' 로 읽었어요';
  read.className = 'dc-read ok';
  dayCheck();
}

if ($('dcGo')) {
  $('dcGo').addEventListener('click', dayCheck);
  if ($('dcPaste')) {
    // 붙여넣기는 값이 들어온 다음에 읽어야 한다
    $('dcPaste').addEventListener('paste', () => setTimeout(dcFromPaste, 0));
    $('dcPaste').addEventListener('input', dcFromPaste);
    $('dcPaste').addEventListener('keydown', (e) => { if (e.key === 'Enter') dcFromPaste(); });
  }
  ['dcDate', 'dcTime'].forEach((id) => {
    const el = $(id);
    if (!el) return;
    el.addEventListener('change', dayCheck);
    el.addEventListener('keydown', (e) => { if (e.key === 'Enter') dayCheck(); });
  });
  // 처음 열면 오늘 날짜만 채워두고, 조회는 누를 때 한다
  const t = new Date();
  $('dcDate').value = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')}`;
}

/* ===== 월별 일정 · 담당자 배정 ===== */
if ($('schedToggle')) {
  $('schedToggle').addEventListener('click', () => {
    const body = $('schedBody');
    const open = body.hidden;
    body.hidden = !open;
    $('schedToggle').setAttribute('aria-expanded', String(open));
    const caret = $('schedToggle').querySelector('.sv-caret');
    if (caret) caret.textContent = open ? '▴' : '▾';
    if (open) renderSchedule();
  });
}

const WD = ['일', '월', '화', '수', '목', '금', '토'];
const wdLabel = (b) => { const d = wDate(b); return d ? WD[d.getDay()] : ''; };
function bookingOpts(b) {
  const o = [];
  if (b.option_album) { const q = albumSnap(b).qty; o.push(q > 1 ? `앨범×${q}` : '앨범'); }
  if (b.option_reception) o.push('연회장');
  if (b.option_pyebaek) o.push('폐백');
  if (b.option_part2) o.push('2부');
  if (b.travel_fee) o.push('출장');
  if (b.photographer === '2인 촬영') o.push('2인');
  if (b.rep_designation) o.push('대표지정');
  (Array.isArray(b.custom_options) ? b.custom_options : []).forEach((c) => { if (c && c.name) o.push(c.name); });
  return o;
}
function schedMonthItems() {
  if (!calMonth) return [];
  const { y, m } = calMonth;
  return allBookings
    .filter((b) => { const d = wDate(b); return d && d.getFullYear() === y && d.getMonth() === m && notCancelled(b) && b.deposit_paid; })
    .sort((a, b) => (wDate(a) - wDate(b)) || (a.wedding_time || '').localeCompare(b.wedding_time || ''));
}

let schedFilter = 'all'; // 'all' | 'none' | staffId
let schedLock = (() => { try { return localStorage.getItem('otb_sched_lock') === '1'; } catch (_) { return false; } })(); // 수정금지: 배정된 일정 잠금
function setSchedFilter(s) { schedFilter = s; renderSchedule(); }
function schedMatch(b) {
  if (schedFilter === 'all') return true;
  if (schedFilter === 'none') return !b.assignee_id;
  return b.assignee_id === schedFilter || b.sub_assignee_id === schedFilter;
}

function renderSchedule() {
  const wrap = $('schedList');
  if (!wrap || !calMonth) return;
  ensureConf(calMonth.y, calMonth.m, renderSchedule);   // 오면 다시 그린다
  const wasChecked = schedChecked();                    // 다시 그려도 선택은 유지
  const all = schedMonthItems();
  renderSchedTags(all);

  if (!all.length) { wrap.innerHTML = '<p class="dash-empty">이 달 예식이 없어요.</p>'; updateSchedCount(); return; }
  const items = all.filter(schedMatch);
  if (!items.length) { wrap.innerHTML = '<p class="dash-empty">해당 작가 일정이 없어요.</p>'; updateSchedCount(); return; }

  const groups = {};
  items.forEach((b) => { const k = fmtDate(b.wedding_date); (groups[k] = groups[k] || []).push(b); });

  wrap.innerHTML = Object.keys(groups).map((k) => `
    <div class="sched-group">
      <p class="sched-date">${esc(k)}${groups[k][0] ? ' (' + wdLabel(groups[k][0]) + ')' : ''} <span>· ${groups[k].length}건</span></p>
      ${groups[k].map((b) => {
        const opts = bookingOpts(b);
        const is2 = b.photographer === '2인 촬영';
        const assigned = b.assignee_id && (!is2 || b.sub_assignee_id); // 배정 완료(2인은 서브까지)
        // 배정 행: 옅은 배경 tint만 (왼쪽 세로 바는 제거)
        const sc = staffColor(b.assignee_id);
        const bg = assigned ? ` style="background:${tint(sc, 0.16)}"` : '';
        const flag = !b.assignee_id ? '미배정' : (is2 && !b.sub_assignee_id ? '서브 미배정' : '');
        return `
        <div class="sched-row${assigned ? ' assigned' : ' unassigned'}" data-id="${b.id}"${bg}>
          <input type="checkbox" class="sched-cb" value="${b.id}" />
          <span class="sched-time">${esc(kTimeShort(b.wedding_time)) || '-'}</span>
          <span class="sched-name">${esc(b.contractor_name || '-')}</span>
          <div class="sched-mid">
            ${flag ? `<span class="sched-flag">⚠ ${flag}</span>` : ''}
            <span class="sched-venue">${esc(b.wedding_venue || '-')}</span>
            ${opts.length ? `<span class="sched-opts">${opts.map((o) => `<span class="sched-optag">${esc(o)}</span>`).join('')}</span>` : ''}
          </div>
          <div class="sched-asg-ctrls">
            <div class="sched-sels">
              <select class="sched-main" data-id="${b.id}" title="메인작가">${assigneeOptions(b.assignee_id, confOf(b), 'main')}</select>
              ${is2 ? `<select class="sched-sub" data-id="${b.id}" title="서브작가">${assigneeOptions(b.sub_assignee_id, confOf(b), 'sub')}</select>` : ''}
            </div>
            <button type="button" class="sched-copy1" data-id="${b.id}" title="이 예식 스케줄 복사">📋</button>
          </div>
        </div>`;
      }).join('')}
    </div>`).join('');
  wasChecked.forEach((id) => {
    const cb = wrap.querySelector('.sched-cb[value="' + id + '"]');
    if (cb) cb.checked = true;
  });
  bindSchedule();
}

function clearSchedChecks() {
  document.querySelectorAll('#schedList .sched-cb').forEach((c) => { c.checked = false; });
  if ($('schedAll')) $('schedAll').checked = false;
  updateSchedCount();
}

function renderSchedTags(items) {
  const el = $('schedTags');
  if (!el) return;
  const used = {};
  items.forEach((b) => { [b.assignee_id, b.sub_assignee_id].forEach((id) => { if (id) used[id] = (used[id] || 0) + 1; }); });
  const ids = Object.keys(used).sort((a, b) => used[b] - used[a]);
  const unassigned = items.filter((b) => !b.assignee_id).length;
  const on = (s) => (schedFilter === s ? ' active' : '');
  el.innerHTML =
    '<span class="sched-tags-label">작가별 보기:</span>' +
    `<button type="button" class="sched-tag${on('all')}" data-staff="all">전체 ${items.length}</button>` +
    ids.map((id) => `<button type="button" class="sched-tag${on(id)}" data-staff="${id}"><i style="background:${staffColor(id)}"></i>${esc(staffName(id))} ${used[id]}</button>`).join('') +
    (unassigned ? `<button type="button" class="sched-tag none${on('none')}" data-staff="none">미배정 ${unassigned}</button>` : '');
  el.querySelectorAll('.sched-tag').forEach((btn) => btn.addEventListener('click', () => setSchedFilter(btn.dataset.staff)));
}

function schedChecked() {
  return Array.from(document.querySelectorAll('#schedList .sched-cb:checked')).map((c) => c.value);
}
function updateSchedCount() {
  const n = schedChecked().length;
  if ($('schedSelCount')) $('schedSelCount').textContent = n ? `${n}건 선택` : '';
}
// 수정금지: 배정된 드롭다운(메인/서브)만 잠그고, 미배정은 수정 가능하게
function applySchedLock() {
  document.querySelectorAll('#schedList .sched-main, #schedList .sched-sub').forEach((sel) => {
    const lock = schedLock && !!sel.value;
    sel.disabled = lock;
    sel.classList.toggle('locked', lock);
  });
}
function bindSchedule() {
  document.querySelectorAll('#schedList .sched-cb').forEach((c) => c.addEventListener('change', updateSchedCount));
  // 행 클릭 → 체크 토글 (작가 드롭다운/체크박스 클릭은 제외)
  document.querySelectorAll('#schedList .sched-row').forEach((row) =>
    row.addEventListener('click', (e) => {
      if (e.target.closest('.sched-asg-ctrls') || e.target.classList.contains('sched-cb')) return;
      const cb = row.querySelector('.sched-cb');
      cb.checked = !cb.checked; updateSchedCount();
    })
  );
  // 개별 스케줄 복사
  document.querySelectorAll('#schedList .sched-copy1').forEach((btn) =>
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const b = allBookings.find((x) => x.id === btn.dataset.id);
      if (!b) return;
      copySchedText(schedShareText([b]), `${b.contractor_name || ''} 스케줄 복사됨!`);
    })
  );
  // 인라인 작가 배정 (메인/서브)
  document.querySelectorAll('#schedList .sched-main, #schedList .sched-sub').forEach((sel) =>
    sel.addEventListener('change', async () => {
      const id = sel.dataset.id;
      const row = sel.closest('.sched-row');
      const main = (row.querySelector('.sched-main') || {}).value || null;
      const subEl = row.querySelector('.sched-sub');
      // 서브 선택칸이 없으면(=2인 촬영 아님) 서브는 비움
      const sub = subEl ? (subEl.value || null) : null;
      const { error } = await sb.rpc('admin_set_assignees', { p_id: id, p_main: main, p_sub: sub });
      if (error) { alert('배정 실패: ' + error.message); return; }
      const b = allBookings.find((x) => x.id === id);
      if (b) { b.assignee_id = main; b.sub_assignee_id = sub; }
      invalidateConf();
      renderCalendar(); renderDashboard(); renderSchedule();
      toast('작가 배정 변경됨');
    })
  );
  applySchedLock();
  updateSchedCount();
}
if ($('schedAll')) {
  $('schedAll').addEventListener('change', (e) => {
    document.querySelectorAll('#schedList .sched-cb').forEach((c) => { c.checked = e.target.checked; });
    updateSchedCount();
  });
}
if ($('schedAllowConf')) {
  const wrap = $('schedAllowConfWrap');
  $('schedAllowConf').addEventListener('change', (e) => {
    allowConf = e.target.checked;
    if (wrap) wrap.classList.toggle('is-on', allowConf);
    renderSchedule();
  });
}

// 모달·편집 폼은 화면을 다시 그리기 어렵다 → 충돌표가 늦게 오면 선택칸만 갈아끼운다
function refillAsg(b, map) {
  const d = wDate(b);
  if (!d) return;
  const fill = () => Object.keys(map).forEach((id) => {
    const sel = $(id);
    if (!sel) return;
    const keep = sel.value;
    sel.innerHTML = assigneeOptions(b[map[id][0]] || '', confOf(b), map[id][1]);
    sel.value = keep;
  });
  if (confOf(b)) return;            // 이미 있으면 그릴 때 반영됐다
  ensureConf(d.getFullYear(), d.getMonth(), fill);
}

if ($('schedLock')) {
  const wrap = $('schedLockWrap');
  const syncLock = () => { if (wrap) wrap.classList.toggle('is-on', schedLock); };
  $('schedLock').checked = schedLock;
  syncLock();
  $('schedLock').addEventListener('change', (e) => {
    schedLock = e.target.checked;
    try { localStorage.setItem('otb_sched_lock', schedLock ? '1' : '0'); } catch (_) {}
    syncLock();
    applySchedLock();
    toast(schedLock ? '🔒 수정금지 ON · 배정된 일정 잠금' : '🔓 수정금지 해제');
  });
}
let lastAssign = null; // 직전 배정 스냅샷 [{id, main, sub}]
function updateUndoBtn() { if ($('schedUndo')) $('schedUndo').hidden = !lastAssign; }
async function bulkAssign(role) {
  let ids = schedChecked();
  const aid = $('schedAssignee').value;
  if (!ids.length) { toast('배정할 일정을 선택하세요.'); return; }
  if (!aid) { toast('담당자를 선택하세요.'); return; }
  let skipped = 0;
  if (schedLock) { // 수정금지: 이미 배정된 일정은 제외하고 미배정만 배정
    const before = ids.length;
    ids = ids.filter((id) => { const b = allBookings.find((x) => x.id === id) || {}; return role === 'sub' ? !b.sub_assignee_id : !b.assignee_id; });
    skipped = before - ids.length;
    if (!ids.length) { toast('🔒 수정금지: 이미 배정된 일정은 변경되지 않아요.'); return; }
  }
  const who = staffMap[aid] || {};
  const fitsRole = role === 'sub' ? who.can_sub !== false : who.can_main !== false;
  if (!fitsRole && !confirm(`${staffName(aid)} 작가는 ${role === 'sub' ? '서브' : '메인'} 배정 대상이 아닙니다.\n그래도 배정할까요?`)) return;

  // 겹치거나 불가인 일정이 섞여 있으면 알려주고 물어본다
  const clash = ids.filter((id) => (confMap[id] || {})[aid]);
  if (clash.length && !allowConf) {
    const lines = clash.slice(0, 6).map((id) => {
      const b = allBookings.find((x) => x.id === id) || {};
      const v = (confMap[id] || {})[aid] || {};
      return `· ${fmtDate(b.wedding_date)} ${kTimeShort(b.wedding_time) || ''} ${b.contractor_name || ''}`
        + ` — ${v.s === 'off' ? '작가가 불가로 표시' : '겹침 ' + (v.d || '')}`;
    }).join('\n');
    const more = clash.length > 6 ? `\n… 외 ${clash.length - 6}건` : '';
    if (!confirm(`${staffName(aid)} 작가는 아래 ${clash.length}건이 걸립니다.\n\n${lines}${more}\n\n그래도 배정할까요?`)) return;
  }
  // 되돌리기용 직전 상태 스냅샷
  lastAssign = ids.map((id) => { const b = allBookings.find((x) => x.id === id) || {}; return { id, main: b.assignee_id || '', sub: b.sub_assignee_id || '' }; });
  const { error } = await sb.rpc('admin_assign_role', { p_ids: ids, p_assignee: aid, p_role: role });
  if (error) { lastAssign = null; alert('배정 실패: ' + error.message); return; }
  ids.forEach((id) => { const b = allBookings.find((x) => x.id === id); if (b) { if (role === 'sub') b.sub_assignee_id = aid; else b.assignee_id = aid; } });
  toast(`${ids.length}건 → ${staffName(aid)} ${role === 'sub' ? '서브' : '메인'} 배정 완료${skipped ? ` (배정된 ${skipped}건 제외)` : ''}`);
  invalidateConf();
  updateUndoBtn();
  renderSchedule(); renderCalendar(); renderDashboard();
  clearSchedChecks();
}
if ($('schedAssignMain')) $('schedAssignMain').addEventListener('click', () => bulkAssign('main'));
if ($('schedAssignSub')) $('schedAssignSub').addEventListener('click', () => bulkAssign('sub'));
if ($('schedUndo')) {
  $('schedUndo').addEventListener('click', async () => {
    if (!lastAssign || !lastAssign.length) { toast('되돌릴 배정이 없어요.'); return; }
    const snap = lastAssign;
    const { error } = await sb.rpc('admin_restore_assignees', { p_rows: snap });
    if (error) { alert('되돌리기 실패: ' + error.message); return; }
    snap.forEach((s) => { const b = allBookings.find((x) => x.id === s.id); if (b) { b.assignee_id = s.main || null; b.sub_assignee_id = s.sub || null; } });
    lastAssign = null; updateUndoBtn(); invalidateConf();
    toast(`${snap.length}건 직전 배정으로 되돌림`);
    renderSchedule(); renderCalendar(); renderDashboard();
  });
}
function schedShareText(rows) {
  const fmtDot = (s) => (s ? String(s).slice(0, 10).replace(/-/g, '.') : '-');
  const pkg = (b) => ((b.package || '').replace(/\s*\(.*\)\s*/, '') || '베이직');
  return rows.map((b) => {
    const opts = bookingOpts(b);
    return [
      `* 예식날짜 : ${fmtDot(b.wedding_date)}`,
      `* 예식장소 : ${b.wedding_venue || '-'}`,
      `* 예식시간 : ${b.wedding_time || '-'}`,
      '',
      `* 신부님 성함 : ${b.bride_name || '-'}`,
      `* 신부님 연락처 : ${b.bride_phone || '-'}`,
      '',
      `* 신랑님 성함 : ${b.groom_name || '-'}`,
      `* 신랑님 연락처 : ${b.groom_phone || '-'}`,
      '',
      `* 상품 : ${pkg(b)}`,
      `* 옵션 : ${opts.length ? opts.join(', ') : '없음'}`,
    ].join('\n');
  }).join('\n\n━━━━━━━━━━\n\n');
}
async function copySchedText(text, okMsg) {
  try { await navigator.clipboard.writeText(text); toast(okMsg); }
  catch (_) { prompt('아래 내용을 복사하세요:', text); }
}
if ($('schedShare')) {
  $('schedShare').addEventListener('click', async () => {
    const ids = schedChecked();
    if (!ids.length) { toast('공유할 일정을 선택하세요.'); return; }
    const rows = ids.map((id) => allBookings.find((b) => b.id === id)).filter(Boolean)
      .sort((a, b) => (wDate(a) - wDate(b)) || (a.wedding_time || '').localeCompare(b.wedding_time || ''));
    await copySchedText(schedShareText(rows), `${rows.length}건 스케줄 복사됨! 작가에게 붙여넣기 하세요.`);
  });
}

/* ===== 담당자 관리 ===== */
// 작가 카카오톡 채널 '온더브라이드 작가전용'.
// 채널을 추가하고 작가가 먼저 말을 걸어와야 우리가 카톡을 보낼 수 있다.
// 채널 홈(http://pf.kakao.com/_LmxgiX) 대신 채팅 주소를 쓴다 — 누르면 바로 채팅창이라
// '성함 한 번 보내기' 까지 손이 제일 적게 간다. 비워두면 안내문에서 채널 부분이 통째로 빠진다.
const STAFF_CHANNEL = 'https://pf.kakao.com/_LmxgiX/chat';
const STAFF_CHANNEL_NAME = '온더브라이드 작가전용';

// 작가에게 보낼 안내문. 링크는 작가마다 다르다.
function staffCalMsg(id) {
  const s = staffMap[id] || {};
  const url = location.origin + '/staff-calendar?s=' + id;
  const ch = STAFF_CHANNEL
    ? [
        // 알림톡은 번호만 있으면 간다 — 채널 친구가 아니어도 된다(친구톡과 다르다).
        // 예전 문구는 «먼저 말을 걸어주셔야 카톡을 보낼 수 있다» 였는데 사실이 아니었다.
        // 신부들에게 나가는 알림톡도 채널 추가 없이 잘 가고 있다 (2026-08-24 대표 지적으로 바로잡음)
        '① 카카오톡 채널 추가하기',
        '앞으로 촬영 배정·설문 요청을 카카오톡으로 보내드립니다.',
        '아래를 눌러 [' + STAFF_CHANNEL_NAME + '] 채널을 추가해 주세요.',
        '추가해두시면 저희가 보낸 톡이 한곳에 모이고,',
        '궁금한 것도 그 채팅창으로 바로 물어보실 수 있습니다.',
        '',
        STAFF_CHANNEL,
        '',
        '② 전용 캘린더',
      ]
    : [];
  return [
    '[온더브라이드] ' + (s.name || '') + ' 작가님' + (ch.length ? ', 두 가지만 부탁드립니다.' : ' 전용 캘린더입니다.'),
    '',
  ].concat(ch).concat([
    url,
    '',
    '· 배정된 예식의 날짜·시간·장소·신랑신부·촬영 옵션을 보실 수 있습니다',
    '  (신랑신부 연락처는 예식 2주 전부터 보입니다)',
    '· 촬영이 안 되는 날은 날짜를 눌러 [촬영불가] 로 표시해 주세요',
    '· 다른 촬영이 있는 날은 [다른촬영등록] 을 눌러 시간과 장소를 적어주세요.',
    '  저희 예식과 4시간 이상 벌어지면 저희 촬영도 가능한 날로 등록됩니다',
    '· 개인 일정은 [개인일정등록] 에 적어두시면 달력에서 함께 보실 수 있습니다.',
    '  개인 일정은 제가 볼 수 없게 되어 있으니 안심하고 쓰셔도 됩니다.',
    '  (저에게는 «개인 일정» 이라고만 보입니다)',
    '  개인 일정이 있는 날은 촬영 불가로 보고 배정 대상에서 빼둡니다.',
    '· 저희 스케줄이 배정되면 불가로 바꿀 수 없습니다. 어려우시면 저에게 연락 주세요',
    '',
    '스케줄을 주기적으로 업데이트 부탁드립니다.',
    '',
    '링크는 작가님 전용이니 다른 분께 전달하지 말아 주세요.',
    '휴대폰이시면 맨 아래 [홈 화면에 추가] 를 눌러두시면 찾기 편합니다.',
  ]).join('\n');
}

function renderStaff() {
  if (!$('staffList')) return;
  $('staffEmpty').hidden = allStaff.length > 0;
  $('staffList').innerHTML = allStaff.map((s) => `
    <div class="staff-item${s.active ? '' : ' inactive'}" data-id="${s.id}">
      <input type="text" class="st-name" data-id="${s.id}" value="${esc(s.name || '')}" placeholder="이름" />
      <input type="text" class="st-phone js-phone" data-id="${s.id}" value="${esc(s.phone || '')}" placeholder="연락처" />
      <span class="st-color-wrap" title="달력·스케줄에 표시될 작가 색">
        <input type="color" class="st-color" data-id="${s.id}" value="${isHex(s.color) ? s.color : (staffColor(s.id) || '#888888')}" ${isHex(s.color) ? '' : 'disabled'} />
        <label class="st-active"><input type="checkbox" class="st-auto" data-id="${s.id}" ${isHex(s.color) ? '' : 'checked'} /> 자동색</label>
      </span>
      <label class="st-active" title="메인 작가로 배정할 수 있음"><input type="checkbox" class="st-main" data-id="${s.id}" ${s.can_main !== false ? 'checked' : ''} /> 메인</label>
      <label class="st-active" title="2인 촬영 서브로 배정할 수 있음"><input type="checkbox" class="st-sub" data-id="${s.id}" ${s.can_sub !== false ? 'checked' : ''} /> 서브</label>
      <button type="button" class="st-rep${s.is_rep ? ' on' : ''}" data-id="${s.id}"
        title="${s.is_rep ? '대표입니다' : '이 분을 대표로 지정'}">대표</button>
      <label class="st-active"><input type="checkbox" class="st-act" data-id="${s.id}" ${s.active ? 'checked' : ''} /> 활성</label>
      <a class="btn-sm st-cal" href="/staff-calendar?s=${s.id}" target="_blank" rel="noopener" title="작가 캘린더 열기">📅 캘린더</a>
      <button class="btn-sm st-callink" data-id="${s.id}" title="작가에게 그대로 붙여넣을 안내문 복사">안내문 복사</button>
      <button class="btn-sm st-save" data-id="${s.id}">저장</button>
      <button class="btn-sm st-del" data-id="${s.id}">삭제</button>
    </div>`).join('');

  hookPhone($('staffList'));

  // 작가에게 카톡으로 그대로 붙여넣을 안내문 (링크 포함)
  $('staffList').querySelectorAll('.st-callink').forEach((btn) =>
    btn.addEventListener('click', async () => {
      const text = staffCalMsg(btn.dataset.id);
      try { await navigator.clipboard.writeText(text); toast('안내문 복사됨 · 작가에게 붙여넣으세요'); }
      catch (_) { prompt('아래 내용을 복사하세요:', text); }
    }));

  // 대표는 한 명뿐이라 줄마다 네모를 두지 않는다 (대표 요청 2026-08-24).
  // 누르면 그 자리에서 바로 옮겨간다 — 저장을 따로 안 눌러도 된다.
  // 서버(admin_staff_update)가 나머지 사람의 대표 표시를 알아서 내린다.
  $('staffList').querySelectorAll('.st-rep').forEach((el) =>
    el.addEventListener('click', async () => {
      if (el.classList.contains('on')) { toast('이미 대표로 되어 있습니다.'); return; }
      const id = el.dataset.id;
      const q = (c) => $('staffList').querySelector(`.${c}[data-id="${id}"]`);
      const auto = q('st-auto').checked;
      el.disabled = true;
      // 이 줄에 손대던 값이 있으면 그대로 함께 보낸다 (대표만 바꾸다 다른 걸 날리지 않게)
      const { error } = await sb.rpc('admin_staff_update', {
        p_id: id, p_name: q('st-name').value.trim(), p_phone: q('st-phone').value.trim(),
        p_active: q('st-act').checked, p_rep: true,
        p_color: auto ? '' : q('st-color').value,
        p_can_main: q('st-main').checked, p_can_sub: q('st-sub').checked });
      el.disabled = false;
      if (error) { alert('대표 지정 실패: ' + error.message); return; }
      await loadStaff();
      invalidateConf();
      renderStaff();
      renderDashboard();
      toast((staffMap[id] || {}).name + ' 작가님을 대표로 지정했습니다.');
    }));

  // '자동색' 체크 → 색 선택기 비활성(자동 팔레트), 해제 → 직접 지정 가능
  $('staffList').querySelectorAll('.st-auto').forEach((cb) =>
    cb.addEventListener('change', () => {
      const picker = $('staffList').querySelector(`.st-color[data-id="${cb.dataset.id}"]`);
      picker.disabled = cb.checked;
    })
  );

  $('staffList').querySelectorAll('.st-save').forEach((btn) =>
    btn.addEventListener('click', async () => {
      const id = btn.dataset.id;
      const name = $('staffList').querySelector(`.st-name[data-id="${id}"]`).value.trim();
      const phone = $('staffList').querySelector(`.st-phone[data-id="${id}"]`).value.trim();
      const active = $('staffList').querySelector(`.st-act[data-id="${id}"]`).checked;
      const rep = $('staffList').querySelector(`.st-rep[data-id="${id}"]`).classList.contains('on');
      const auto = $('staffList').querySelector(`.st-auto[data-id="${id}"]`).checked;
      const color = auto ? '' : $('staffList').querySelector(`.st-color[data-id="${id}"]`).value; // ''=자동, #RRGGBB=지정
      const canMain = $('staffList').querySelector(`.st-main[data-id="${id}"]`).checked;
      const canSub = $('staffList').querySelector(`.st-sub[data-id="${id}"]`).checked;
      if (!name) { alert('이름을 입력하세요.'); return; }
      if (!canMain && !canSub) { alert('메인·서브 중 하나는 체크해 주세요.'); return; }
      btn.disabled = true;
      const { error } = await sb.rpc('admin_staff_update', { p_id: id, p_name: name, p_phone: phone, p_active: active, p_rep: rep, p_color: color, p_can_main: canMain, p_can_sub: canSub });
      btn.disabled = false;
      if (error) { alert('저장 실패: ' + error.message); return; }
      await loadStaff();
      invalidateConf();
      renderStaff();
      renderDashboard();
      toast('저장되었습니다.');
    })
  );
  $('staffList').querySelectorAll('.st-del').forEach((btn) =>
    btn.addEventListener('click', async () => {
      if (!confirm('이 담당자를 삭제할까요? (배정된 예식은 미배정으로 바뀝니다)')) return;
      const { error } = await sb.rpc('admin_staff_delete', { p_id: btn.dataset.id });
      if (error) { alert('삭제 실패: ' + error.message); return; }
      await loadStaff();
      renderStaff();
    })
  );
}
if ($('stAddBtn')) {
  $('stAddBtn').addEventListener('click', async () => {
    const name = $('stName').value.trim();
    const phone = $('stPhone').value.trim();
    const msg = $('stMsg');
    if (!name) { msg.textContent = '이름을 입력하세요.'; return; }
    $('stAddBtn').disabled = true;
    const { error } = await sb.rpc('admin_staff_add', { p_name: name, p_phone: phone });
    $('stAddBtn').disabled = false;
    if (error) { msg.textContent = '추가 실패: ' + error.message; return; }
    $('stName').value = ''; $('stPhone').value = ''; msg.textContent = '';
    await loadStaff();
    renderStaff();
    toast('담당자를 추가했어요.');
  });
}

/* ===== Gallery management ===== */
// 다가오는 예식 / 다운로드 링크 — 한 박스 안 탭 전환
const schedTabs = document.querySelector('.sched-tabs');
if (schedTabs) {
  schedTabs.addEventListener('click', (e) => {
    const t = e.target.closest('.stab');
    if (!t) return;
    const which = t.dataset.stab;
    schedTabs.querySelectorAll('.stab').forEach((x) => x.classList.toggle('active', x === t));
    $('listUpcoming').hidden = which !== 'upcoming';
    $('listDownload').hidden = which !== 'download';
  });
}

/* 탭바 고정: 헤더 높이를 실측해 --headh 로 넘김(버튼 줄바꿈·모바일 대응) */
function syncHeadHeight() {
  const head = document.querySelector('.dash-head');
  if (!head || !head.offsetHeight) return;
  document.documentElement.style.setProperty('--headh', head.offsetHeight + 'px');
}
window.addEventListener('resize', syncHeadHeight);
window.addEventListener('load', syncHeadHeight);
if (window.ResizeObserver) {
  const h = document.querySelector('.dash-head');
  if (h) new ResizeObserver(syncHeadHeight).observe(h);
}
syncHeadHeight();

/* ===== 새로고침·뒤로가기해도 보던 탭 유지 =====
   현재 위치를 주소 해시(#stats/feedback 같은)에 적어두고, 열 때 그대로 되살린다.
   되살리는 동안에는 해시를 다시 쓰지 않도록 applyingHash 로 잠근다(무한루프 방지). */
let applyingHash = false;
function setHash(v) {
  if (applyingHash) return;
  if (location.hash.slice(1) !== v) history.replaceState(null, '', '#' + v);
}
function applyHash() {
  const [tab, sub] = (location.hash.slice(1) || 'dashboard').split('/');
  const btn = document.querySelector('.dtab[data-tab="' + (tab || 'dashboard') + '"]');
  if (!btn) return;
  applyingHash = true;
  try {
    if (!btn.classList.contains('active') || tab === 'dashboard') btn.click();
    if (tab === 'settings' && sub) {
      const sb2 = document.querySelector('.sub-tab[data-subtab="' + sub + '"]');
      if (sb2) sb2.click();
    }
    if (tab === 'stats' && (sub || stFirst()) !== stCur) stSub(sub || stFirst());
  } finally { applyingHash = false; }
}
window.addEventListener('hashchange', applyHash);

const dashTabs = document.querySelector('.dash-tabs');
if (dashTabs) {
  dashTabs.addEventListener('click', (e) => {
    const t = e.target.closest('.dtab');
    if (!t) return;
    document.querySelectorAll('.dtab').forEach((x) => x.classList.toggle('active', x === t));
    const tab = t.dataset.tab;
    $('tab-dashboard').hidden = tab !== 'dashboard';
    $('tab-calendar').hidden = tab !== 'calendar';
    $('tab-bookings').hidden = tab !== 'bookings';
    $('tab-select').hidden = tab !== 'select';
    $('tab-album').hidden = tab !== 'album';
    $('tab-stats').hidden = tab !== 'stats';
    $('tab-settings').hidden = tab !== 'settings';
    if (tab === 'dashboard') { renderDashboard(); loadEvents(); }
    if (tab === 'calendar') { renderCalendar(); renderSchedule(); }
    if (tab === 'select') renderSelect();
    if (tab === 'album') renderAlbum();
    // 통계를 열면 홈의 「한눈에」 숫자도 같이 새로 받아둔다
    if (tab === 'stats') { stSub(stCur); renderHomeStats(true); }
    if (tab === 'settings') showSubtab(currentSubtab);
    setHash(tab === 'settings' ? 'settings/' + currentSubtab : tab);
    if (window.scrollY > 0) window.scrollTo({ top: 0 });  // 새 탭 내용을 처음부터 보이게
  });
}


/* ===== 통계 (자체 방문 집계) =====
   수집은 analytics.js → log_pageview RPC. 여기서는 admin_analytics 로 집계만 읽는다. */
let statsDays = 7;
let statsLoaded = false;

// 유입 도메인을 사람이 읽는 이름으로
const REF_NAMES = [
  [/(^|.)naver.com$/, '네이버'], [/(^|.)google./, '구글'], [/(^|.)daum.net$|(^|.)kakao.com$/, '다음·카카오'],
  [/(^|.)instagram.com$/, '인스타그램'], [/(^|.)facebook.com$|(^|.)fb./, '페이스북'],
  [/(^|.)youtube.com$|(^|.)youtu.be$/, '유튜브'], [/(^|.)bing.com$/, '빙'], [/(^|.)tistory.com$/, '티스토리'],
];
function refLabel(r) {
  if (!r || r[0] === '(') return r || '(직접 · 즐겨찾기)';
  for (const [re, nm] of REF_NAMES) if (re.test(r)) return nm + ' (' + r + ')';
  return r;
}
const HOME_SECTIONS = { about: '소개 · 이야기', gallery: '갤러리', pricing: '상품 가격', event: '이벤트', contact: '문의하기', booking: '예약신청', 'booking-start': '예약신청 시작 버튼 ⭐' };
function pathLabel(p) {
  if (p === '/' || p === '') return '홈 (첫 화면)';
  if (p.startsWith('/#')) { const k = p.slice(2); return '홈 · ' + (HOME_SECTIONS[k] || k); }
  if (p === '/blog') return '블로그 목록';
  if (p.startsWith('/blog/posts/')) return '블로그 글 · ' + p.replace('/blog/posts/', '');
  if (p === '/rules') return '규정 안내';
  if (p === '/privacy') return '개인정보처리방침';
  return p;
}
const stNum = (n) => Number(n || 0).toLocaleString('ko-KR');

/* ── 홈의 「한눈에」 요약 (대표 요청 2026-08-23) ──────────────
   홈에 있던 예식 캘린더를 빼고 그 자리에 넣는다. 캘린더는 캘린더 탭에 같은 것이 있고,
   대표가 홈에서는 잘 안 보게 된다고 해서.
   여기서는 숫자만 훑고, 자세히 볼 일은 통계 탭에서 한다. */
let homeStatsAt = 0;
async function renderHomeStats(force) {
  const box = $('homeStatsBody');
  if (!box) return;
  // 새로고침을 눌러도 1분 안에는 다시 안 부른다 — 홈을 그릴 때마다 세 번씩 물을 이유가 없다
  if (!force && homeStatsAt && Date.now() - homeStatsAt < 60000) return;
  const [an, fb, pd] = await Promise.all([
    sb.rpc('admin_analytics', { p_days: 7 }),
    sb.rpc('admin_feedback', { p_days: 90 }),
    sb.rpc('admin_feedback_pending'),
  ]);
  if (an.error && fb.error) { box.innerHTML = '<p class="empty sm">통계를 불러오지 못했습니다.</p>'; return; }
  homeStatsAt = Date.now();
  const a = an.data || {}, f = fb.data || {};
  const pend = Array.isArray(pd.data) ? pd.data.filter((x) => !x.done) : [];
  const tile = (k, v, sub, warn) =>
    '<div class="st-mini-t' + (warn ? ' warn' : '') + '"><span class="st-k">' + esc(k) + '</span>'
    + '<strong>' + v + '</strong><span class="st-sub">' + esc(sub) + '</span></div>';
  box.innerHTML =
    tile('오늘 방문', stNum(a.today && a.today.visits), '페이지뷰 ' + stNum(a.today && a.today.views))
    + tile('최근 7일', stNum(a.week && a.week.visits), '페이지뷰 ' + stNum(a.week && a.week.views))
    + tile('모바일', stNum(a.mobile_pct) + '%', '휴대폰으로 본 비율')
    + tile('작가 평가', (f.avg_score == null ? '-' : f.avg_score), '100점 만점 · ' + (f.count || 0) + '건')
    + tile('설문 미응답', pend.length, '최근 60일 예식', pend.length > 0);

  renderHomeReviews(Array.isArray(f.items) ? f.items : []);
  // 많이 간 예식장 — 한 번만 받아 두면 된다 (2026-08-25 통계에서 홈으로 옮김)
  if (!staffShots) await loadStaffShots();
  renderHomeVenues();
}

/* 신부님들이 설문에 남긴 글 세 개. 위에서 이미 받아온 것을 나눠 쓴다 — 따로 안 부른다 */
const HOME_REV_N = 5;                 // 대표 요청 2026-08-24: 셋 → 다섯
function renderHomeReviews(items) {
  const box = $('homeReviewsBody');
  if (!box) return;
  const said = items.filter((x) => x.next_req || x.message).slice(0, HOME_REV_N);
  if (!said.length) { box.innerHTML = '<p class="empty sm">아직 남겨주신 글이 없습니다.</p>'; return; }
  box.innerHTML = said.map((x) => {
    const wd = x.wedding_date ? String(x.wedding_date).slice(0, 10).replace(/-/g, '.') : '';
    const who = x.bride_name || x.contractor_name || '';
    return '<div class="hr-item" data-id="' + esc(x.booking_id) + '">'
      + '<div class="hr-head">'
        + '<span class="hr-who">' + esc(who) + '</span>'
        + '<span class="hr-staff">' + esc(x.staff_name || '') + (wd ? ' · ' + esc(wd) : '') + '</span>'
        + (x.score == null ? '' : '<span class="hr-score">' + x.score + '점</span>')
      + '</div>'
      // 「다음에 부탁」이 있으면 그걸 먼저 — 고칠 거리라서
      + (x.next_req ? '<p class="hr-next">📝 ' + esc(x.next_req) + '</p>' : '')
      + (x.message ? '<p class="hr-msg">' + esc(x.message) + '</p>' : '')
      + '</div>';
  }).join('');
}

// 홈에서 통계 탭으로. 후기 쪽은 「작가 평가」 칸까지 열어준다
function goStats(sub) {
  const t = document.querySelector('.dtab[data-tab="stats"]');
  if (t) t.click();
  if (sub) stSub(sub);
}
if ($('homeStatsMore')) $('homeStatsMore').addEventListener('click', () => goStats());
if ($('homeReviewsMore')) $('homeReviewsMore').addEventListener('click', () => goStats('feedback'));

async function renderStats() {
  const wrap = $('statsBody');
  if (!wrap) return;
  if (!statsLoaded) wrap.innerHTML = '<p class="empty">불러오는 중…</p>';
  const { data, error } = await sb.rpc('admin_analytics', { p_days: statsDays });
  if (error || !data) {
    wrap.innerHTML = '<p class="empty">통계를 불러오지 못했습니다. (' + esc(error ? error.message : '응답 없음') + ')</p>';
    return;
  }
  statsLoaded = true;
  const d = data;
  const daily = Array.isArray(d.daily) ? d.daily : [];
  const max = daily.reduce((m, x) => Math.max(m, Number(x.views) || 0), 0) || 1;
  // 날짜 라벨은 최대 10개만 (30·90일에서 글자가 겹치지 않게). 오늘이 항상 표시되도록 뒤에서부터 센다.
  const step = Math.max(1, Math.ceil(daily.length / 10));
  let lblSeq = 0;  // 표시되는 라벨의 순번 — 짝수번째만 모바일에 남긴다
  const bars = daily.map((x, i) => {
    const v = Number(x.views) || 0;
    const md = String(x.d).slice(0, 10).slice(5).replace('-', '.');  // 'YYYY-MM-DD...' → 'MM.DD'
    const showLbl = (daily.length - 1 - i) % step === 0;
    return '<div class="st-bar-col">'
      + '<span class="st-tip"><b>' + esc(md) + '</b>'
        + '<span>페이지뷰 ' + esc(stNum(v)) + '</span>'
        + '<span>방문 ' + esc(stNum(x.visits)) + '</span></span>'
      + '<div class="st-bar-fill" style="height:' + Math.round((v / max) * 100) + '%"></div>'
      + (showLbl ? '<span class="st-bar-lbl' + (lblSeq++ % 2 ? ' alt' : '') + '">' + esc(md) + '</span>' : '') + '</div>';
  }).join('');

  const list = (rows, keyFn, valFn, empty) => rows && rows.length
    ? rows.map((r) => {
        const val = Number(valFn(r)) || 0;
        const top = Number(valFn(rows[0])) || 1;
        return '<div class="st-row"><span class="st-row-bar" style="width:' + Math.round((val / top) * 100) + '%"></span>'
          + '<span class="st-row-k">' + esc(keyFn(r)) + '</span><span class="st-row-v">' + stNum(val) + '</span></div>';
      }).join('')
    : '<p class="empty">' + empty + '</p>';

  wrap.innerHTML =
    '<div class="st-cards">'
    + '<div class="st-card"><span class="st-k">오늘</span><strong>' + stNum(d.today.visits) + '</strong><span class="st-sub">방문 · 페이지뷰 ' + stNum(d.today.views) + '</span></div>'
    + '<div class="st-card"><span class="st-k">최근 7일</span><strong>' + stNum(d.week.visits) + '</strong><span class="st-sub">방문 · 페이지뷰 ' + stNum(d.week.views) + '</span></div>'
    // 기간이 7일이면 바로 위 칸과 똑같은 숫자가 두 번 나온다 — 그때는 뺀다 (대표 요청 2026-08-24)
    + (Number(d.days) === 7 ? ''
      : '<div class="st-card"><span class="st-k">최근 ' + d.days + '일</span><strong>' + stNum(d.range.visits) + '</strong><span class="st-sub">방문 · 페이지뷰 ' + stNum(d.range.views) + '</span></div>')
    + '<div class="st-card"><span class="st-k">모바일</span><strong>' + stNum(d.mobile_pct) + '%</strong><span class="st-sub">휴대폰으로 본 비율</span></div>'
    // 한 번 들어와서 몇 쪽이나 보고 가나. 새로 받아올 것 없이 이미 있는 두 숫자를 나눈다.
    // 1쪽에 가까우면 첫 화면만 보고 나간 것, 커질수록 이것저것 눌러본 것이다.
    // (재방문율은 못 센다 — 방문 번호가 창을 닫으면 없어져서 같은 사람인지 알 수 없다)
    + '<div class="st-card"><span class="st-k">한 번에</span><strong>'
    + (Number(d.range.visits) ? (Math.round((Number(d.range.views) / Number(d.range.visits)) * 10) / 10) : '-')
    + '</strong><span class="st-sub">쪽 · 한 번 들어와서 본 쪽수</span></div>'
    + '</div>'
    + '<div class="dash-card st-chart-card"><div class="dash-card-head"><h3>📈 일자별 <small>(막대 = 페이지뷰)</small></h3></div>'
    + '<div class="st-chart" style="gap:' + (daily.length > 45 ? 1 : 3) + 'px">' + bars + '</div></div>'
    + '<div class="dash-cards st-two">'
    + '<div class="dash-card"><div class="dash-card-head"><h3>📄 많이 본 페이지</h3></div>'
    + list(d.pages, (r) => pathLabel(r.path), (r) => r.views, '아직 기록이 없습니다.') + '</div>'
    + '<div class="dash-card"><div class="dash-card-head"><h3>🔗 어디서 들어왔나 <small>(방문 수)</small></h3></div>'
    + list(d.refs, (r) => refLabel(r.ref), (r) => r.visits, '아직 기록이 없습니다.') + '</div>'
    + '</div>'
    + '<div id="clarityBox"></div>'
    + '<p class="st-note">방문 = 브라우저 한 번 열어 둘러본 단위. 구글 애널리틱스 숫자와 몇 % 다를 수 있습니다(광고 차단 사용 등). 기록은 180일 후 자동 삭제됩니다.</p>';
  renderClarity();
}

/* ===== 셀렉 매칭 — 신부가 고른 40장의 RAW 찾아 복사 =====
   파일은 올리지 않는다. 브라우저에서 이름만 읽어 쓴다. */
// 맥에서 온 이름은 한글 자모가 풀려 있다(NFD). 드롭박스 쪽은 붙어 있다(NFC).
// 눈에는 같아 보여도 글자로는 달라서, 맞춰보기 전에 한 모양으로 통일한다.
const nfc = (s) => { try { return String(s == null ? '' : s).normalize('NFC'); } catch (e) { return String(s == null ? '' : s); } };
const selBase = (n) => nfc(n).replace(/\.[^.]+$/, '').trim();   // 확장자 뺀 이름

// 신부가 고른 이름들(want) 과 RAW 파일들(files) 을 맞춰본다.
// 확장자는 무시하고 이름만 본다(M4200526.JPG ↔ M4200526.ARW). 대소문자도 무시.
function selMatch(want, files) {
  const byBase = {};
  (files || []).forEach((f) => { byBase[selBase(f.name).toLowerCase()] = f; });
  const seen = {}, hit = [], miss = [], dup = [];
  (want || []).forEach((n) => {
    const k = selBase(n).toLowerCase();
    if (!k) return;
    if (seen[k]) { dup.push(selBase(n)); return; }   // 같은 걸 두 번 고른 경우 — 한 번만 복사
    seen[k] = true;
    if (byBase[k]) hit.push(byBase[k]); else miss.push(selBase(n));
  });
  return { hit, miss, dup };
}

// 예식 폴더 안에서 RAW 폴더를 찾고, 그 안 파일 이름을 전부 모은다(이어보기 포함)
async function dbxRawFiles(folderPath, say) {
  say('예식 폴더를 여는 중…');
  let r = await sb.rpc('admin_dbx_ls_req', { p_path: folderPath, p_cursor: null });
  if (r.error) return { error: r.error.message };
  if (r.data && r.data.error) return { error: r.data.error };
  let res = await dbxWait('admin_dbx_ls_res', { p_req: r.data.req });
  if (res.error || res.missing) return { error: res.error || '폴더를 찾지 못했습니다.' };

  const raw = (res.entries || []).find((e) => e.dir && /raw/i.test(e.name));
  if (!raw) return { error: '이 예식 폴더 안에 RAW 폴더가 없습니다.' };

  const files = [];
  let cursor = null;
  for (let page = 0; page < 12; page++) {
    say('RAW 목록을 읽는 중… ' + (files.length ? files.length + '장' : ''));
    r = await sb.rpc('admin_dbx_ls_req', cursor ? { p_path: null, p_cursor: cursor } : { p_path: raw.path, p_cursor: null });
    if (r.error) return { error: r.error.message };
    res = await dbxWait('admin_dbx_ls_res', { p_req: r.data.req });
    if (res.error) return { error: res.error };
    (res.entries || []).forEach((e) => { if (!e.dir) files.push(e); });
    if (!res.more) break;
    cursor = res.cursor;
  }
  return { rawName: raw.name, files };
}

/* ── 폴더 이름에서 예식일과 사람 이름 뽑기 ────────────────────────
   신부가 보내는 폴더 이름은 제각각이다. 실제로 쌓여 있는 것들:
     "2025.01.11 김창수&김란희"  "24년3월17일 일요일 (…) 신부 정혜진"
     "25.08.30 최아름"  "20251228_오선녀"  "최혜지 이관성 본식 셀렉_40장"
   날짜가 있으면 날짜로, 없으면 이름으로 찾는다. */
const SEL_STOP = ['셀렉', '원본', '사진', '파일', '최종', '보정', '완료', '신부', '신랑', '본식',
  '예식', '앨범', '다운', '폴더', '선택', '선별', '확정', '스냅', '결혼식', '웨딩', '호텔', '컨벤션',
  '일요일', '토요일', '금요일', '목요일', '수요일', '화요일', '월요일', '새폴더'];
const selPad = (n) => String(n).padStart(2, '0');

function selParse(name) {
  const s = nfc(name).replace(/[\\/]+/g, ' ');
  let y = null, m = null, d = null, t;
  if ((t = s.match(/(20\d{2})\s*[.\-_/년]\s*(\d{1,2})\s*[.\-_/월]\s*(\d{1,2})/))) { y = +t[1]; m = +t[2]; d = +t[3]; }
  else if ((t = s.match(/(?:^|\D)(20\d{2})(\d{2})(\d{2})(?:\D|$)/))) { y = +t[1]; m = +t[2]; d = +t[3]; }
  else if ((t = s.match(/(?:^|\D)(\d{2})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일/))) { y = 2000 + +t[1]; m = +t[2]; d = +t[3]; }
  else if ((t = s.match(/(?:^|\D)(\d{2})\s*[.\-_/]\s*(\d{1,2})\s*[.\-_/]\s*(\d{1,2})(?:\D|$)/))) { y = 2000 + +t[1]; m = +t[2]; d = +t[3]; }
  else if ((t = s.match(/(?:^|\D)(\d{2})(\d{2})(\d{2})(?:\D|$)/))) { y = 2000 + +t[1]; m = +t[2]; d = +t[3]; }
  else if ((t = s.match(/(\d{1,2})\s*월\s*(\d{1,2})\s*일/))) { m = +t[1]; d = +t[2]; }
  const okd = m >= 1 && m <= 12 && d >= 1 && d <= 31;
  const names = (s.match(/[가-힣]{2,4}/g) || []).filter((w) => SEL_STOP.indexOf(w) < 0);
  return {
    date: okd && y ? y + '-' + selPad(m) + '-' + selPad(d) : null,
    md: okd ? selPad(m) + '-' + selPad(d) : null,
    names: names,
  };
}

// 뽑아낸 것으로 우리 예약을 찾는다. 날짜가 맞으면 크게, 이름이 맞으면 그 다음으로 친다.
function selCandidates(p, bookings) {
  const out = [];
  (bookings || []).forEach((b) => {
    const wd = String(b.wedding_date || '').slice(0, 10);
    if (!wd) return;
    let sc = 0;
    if (p.date) {
      if (wd !== p.date) return;            // 연도까지 알면 그 날짜만 본다
      sc += 5;
    } else if (p.md && wd.slice(5) === p.md) {
      sc += 3;                              // 연도를 못 읽었을 때만 월·일로 좁힌다
    }
    const who = [b.contractor_name, b.bride_name, b.groom_name].filter(Boolean);
    if (p.names.some((n) => who.indexOf(n) >= 0)) sc += 4;
    else if (p.names.some((n) => who.some((w) => w.indexOf(n) >= 0 || n.indexOf(w) >= 0))) sc += 2;
    if (sc > 0) out.push({ b: b, score: sc });
  });
  out.sort((x, z) => z.score - x.score || String(x.b.wedding_date).localeCompare(String(z.b.wedding_date)));
  return out;
}

// 대표가 쓰는 규칙 그대로: 예식일 여섯 자리를 앞에 붙이고 신부가 준 폴더 이름을 그대로 둔다
function selDestName(dateStr, folder, who) {
  const ymd = String(dateStr || '').slice(2, 10).replace(/-/g, '');
  const tail = String(folder || '').trim();
  return tail ? ymd + '-' + tail : (ymd + ' ' + (who || '')).trim();
}

const selDayPath = (dateStr) => {
  const s = String(dateStr || '').slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  return '/온더브라이드 백업/' + s.slice(0, 4) + '년/' + s.slice(5, 7) + '월/'
    + s.slice(2, 4) + '.' + s.slice(5, 7) + '.' + s.slice(8, 10);
};
// 드롭박스 웹에서 그 폴더 열기.
// 우리는 팀 계정이라 보는 자리가 두 군데다 —
//   API 가 보는 곳 : /2026 셀렉파일/…
//   웹에서 보는 곳 : /byunghoon kim/2026 셀렉파일/…  (팀 공간 아래 내 폴더)
// 그래서 웹 링크에는 내 폴더 이름을 앞에 붙여야 한다(admin_dbx_home 이 알려준다).
let selHome = '';                       // 예: '/byunghoon kim'
const selDbxUrl = (p) =>
  'https://www.dropbox.com/home?path=' + encodeURIComponent(selHome + String(p || ''));

/* ── 탭 그리기 ───────────────────────────────────────────────── */
function selDayLabel(s) {
  const d = new Date(String(s).slice(0, 10) + 'T00:00:00');
  if (isNaN(d)) return String(s || '');
  return String(d.getFullYear() % 100).padStart(2, '0') + '.' + selPad(d.getMonth() + 1) + '.'
    + selPad(d.getDate()) + '(' + WD[d.getDay()] + ')';
}

let selRoots = null;   // 셀렉파일 폴더 목록 — 한 번만 읽어 둔다

function renderSelect() {
  const el = $('tab-select');
  if (!el || el.dataset.ready) { selRecent(); return; }
  el.dataset.ready = '1';
  el.innerHTML =
    '<div class="sel-head">'
    + '<h2>셀렉 RAW 찾기</h2>'
    + '<p class="sel-lead">신부가 보낸 <b>셀렉 폴더를 여기 끌어다 놓으면</b> 폴더 이름으로 예식을 찾아,'
    + ' 그 예식 RAW 중에서 같은 사진을 골라 줍니다.<br />'
    + '셀렉 폴더를 새로 만들어 <b>신부가 보낸 JPG 와 찾은 RAW 를 함께</b> 넣습니다.</p>'
    + '</div>'
    + '<div class="sel-drop" id="selDrop">'
    + '<span class="sel-drop-ico">📂</span>'
    + '<b class="sel-drop-t">셀렉 폴더를 끌어다 놓으세요</b>'
    + '<span class="sel-drop-s">또는</span>'
    + '<span class="sel-drop-b">'
    + '<label class="btn-sm sel-pick-lbl">폴더 고르기<input type="file" id="selDir" multiple webkitdirectory hidden /></label>'
    + '<label class="btn-sm sel-pick-lbl">파일 고르기<input type="file" id="selFiles" multiple hidden /></label>'
    + '</span></div>'
    + '<details class="sel-manual"><summary>이름 목록만 왔을 때 (메일로 목록만 온 경우)</summary>'
    + '<textarea id="selText" rows="4" class="sel-text" placeholder="M4200526.JPG&#10;M4200529.JPG"></textarea>'
    + '<input type="text" id="selWho" class="sel-dest" placeholder="예식 찾기 — 이름이나 날짜 (예: 이솔 / 260822)" />'
    + '<button type="button" class="btn-sm primary" id="selTextGo">이 목록으로 찾기</button>'
    + '</details>'
    + '<div id="selWork"></div>'
    + '<div id="selLog"></div>';

  const dz = $('selDrop');
  ['dragenter', 'dragover'].forEach((n) => dz.addEventListener(n, (e) => {
    e.preventDefault(); dz.classList.add('over');
  }));
  ['dragleave', 'drop'].forEach((n) => dz.addEventListener(n, (e) => {
    e.preventDefault(); if (n === 'dragleave' && dz.contains(e.relatedTarget)) return;
    dz.classList.remove('over');
  }));
  dz.addEventListener('drop', async (e) => {
    const got = await selFromDrop(e.dataTransfer);
    selStart(got.folder, got.items);
  });

  $('selDir').addEventListener('change', (e) => {
    const fs2 = Array.from(e.target.files || []);
    const rel = (fs2[0] && fs2[0].webkitRelativePath) || '';
    selStart(rel.split('/')[0] || '', fs2.map((f) => ({ name: f.name, file: f })));
    e.target.value = '';
  });
  $('selFiles').addEventListener('change', (e) => {
    selStart('', Array.from(e.target.files || []).map((f) => ({ name: f.name, file: f })));
    e.target.value = '';
  });
  $('selTextGo').addEventListener('click', () => {
    const want = $('selText').value.split(/[\r\n,\t]+/).map((s) => s.trim()).filter(Boolean);
    if (!want.length) { toast('파일 이름을 붙여넣어 주세요'); return; }
    // 이름만 왔으면 올릴 파일은 없다 — RAW 만 찾아 넣는다
    selStart($('selWho').value.trim(), want.map((n) => ({ name: n, file: null })));
  });
  selRecent();
  if (!selHome) {
    sb.rpc('admin_dbx_home').then((r) => { if (r && r.data) selHome = r.data; });
  }
}

// 끌어다 놓은 것에서 폴더 이름과 파일들을 꺼낸다
function selFromDrop(dt) {
  const items = Array.from((dt && dt.items) || []);
  const ents = items.map((i) => (i.webkitGetAsEntry ? i.webkitGetAsEntry() : null)).filter(Boolean);
  const dir = ents.find((e) => e.isDirectory);
  if (dir) return selReadDir(dir).then((items2) => ({ folder: dir.name, items: items2 }));
  const files = Array.from((dt && dt.files) || []);
  return Promise.resolve({ folder: '', items: files.map((f) => ({ name: f.name, file: f })) });
}

// 폴더 안을 훑는다(한 번에 100개씩 오므로 끝까지 돈다). 하위 폴더도 두 겹까지 들어간다.
function selReadDir(dir, depth) {
  return new Promise((done) => {
    const out = [];
    const rd = dir.createReader();
    const subs = [];
    const step = () => rd.readEntries((es) => {
      if (!es.length) {
        if (!subs.length || (depth || 0) >= 2) return done(out);
        return Promise.all(subs.map((s) => selReadDir(s, (depth || 0) + 1)))
          .then((rs) => done(out.concat.apply(out, rs)));
      }
      es.forEach((e) => {
        if (e.isFile) out.push({ name: e.name, entry: e });
        else subs.push(e);
      });
      step();
    }, () => done(out));
    step();
  });
}

// 끌어다 놓은 것은 알맹이를 따로 꺼내야 한다
const selFile = (it) => (it.file ? Promise.resolve(it.file)
  : it.entry ? new Promise((ok, no) => it.entry.file(ok, no)) : Promise.resolve(null));

/* ── 폴더 이름으로 예식 찾기 ──────────────────────────────────── */
function selStart(folder, items) {
  const box = $('selWork');
  if (!box) return;
  // 사진이 아닌 것(.DS_Store, Thumbs.db, 메모 …)은 빼고 본다
  const keep = (items || []).filter((it) =>
    /\.(jpe?g|png|tiff?|heic|arw|cr[23]|nef|raf|dng)$/i.test(it.name) || !/\./.test(it.name));
  const p = selParse(folder);
  const cands = selCandidates(p, allBookings);
  const head = '<p class="dbx-msg">' + (folder ? '폴더 <b>' + esc(folder) + '</b>' : '고른 파일')
    + ' · ' + keep.length + '장</p>';

  if (cands.length && (cands.length === 1 || cands[0].score > cands[1].score)) {
    return selOpen({ b: cands[0].b, date: String(cands[0].b.wedding_date).slice(0, 10), folder: folder }, keep);
  }
  if (cands.length) {
    box.innerHTML = head + '<div class="sel-panel"><p class="dbx-msg">어느 예식인가요?</p>'
      + '<div class="sel-cands">' + cands.slice(0, 8).map((c, i) =>
        '<button type="button" class="sel-cand" data-i="' + i + '">'
        + '<b>' + esc(selDayLabel(c.b.wedding_date)) + '</b>'
        + '<span>' + esc(c.b.contractor_name || '') + '</span>'
        + '<small>' + esc([c.b.bride_name && '신부 ' + c.b.bride_name,
                           c.b.groom_name && '신랑 ' + c.b.groom_name].filter(Boolean).join(' · ')) + '</small>'
        + '</button>').join('') + '</div></div>';
    box.querySelectorAll('.sel-cand').forEach((el2) => el2.addEventListener('click', () => {
      const c = cands[Number(el2.dataset.i)];
      return selOpen({ b: c.b, date: String(c.b.wedding_date).slice(0, 10), folder: folder }, keep);
    }));
    return;
  }
  if (p.date) {
    // 우리 시스템이 생기기 전 예식이면 예약이 없다 — 날짜만으로도 백업 폴더는 찾을 수 있다
    return selOpen({ b: null, date: p.date, folder: folder }, keep);
  }
  box.innerHTML = head
    + '<div class="sel-panel"><p class="dbx-msg err">폴더 이름에서 예식을 못 찾았습니다.</p>'
    + '<p class="dbx-msg">예식 날짜나 이름을 넣어주세요 — 예: <b>260822</b> 또는 <b>이솔</b></p>'
    + '<input type="text" class="sel-dest sel-find" placeholder="260822 이솔" />'
    + '<button type="button" class="btn-sm primary sel-find-go">찾기</button></div>';
  const go = () => selStart(box.querySelector('.sel-find').value.trim(), keep);
  box.querySelector('.sel-find-go').addEventListener('click', go);
  box.querySelector('.sel-find').addEventListener('keydown', (e) => { if (e.key === 'Enter') go(); });
}

/* ── 고른 예식으로 RAW 찾아 보여주기 ──────────────────────────── */
async function selOpen(ctx, items) {
  const box = $('selWork');
  if (!box) return;
  const who = ctx.b ? (ctx.b.contractor_name || '') : '';
  const dayPath = selDayPath(ctx.date);
  box.innerHTML =
    '<div class="sel-panel">'
    + '<div class="sel-who"><b>' + esc(selDayLabel(ctx.date)) + '</b>'
    + '<span>' + esc(who || '(우리 예약에 없는 예식)') + '</span>'
    + (ctx.folder ? '<small class="sel-from">넣은 폴더 · ' + esc(ctx.folder) + '</small>'
                  : '<small class="sel-from">폴더 이름 없이 파일만 고르셨습니다</small>')
    + (ctx.b && ctx.b.wedding_venue ? '<small>' + esc(ctx.b.wedding_venue) + '</small>' : '')
    + '<button type="button" class="btn-sm sel-again">다시 고르기</button></div>'
    + '<div class="sel-step" id="selFolder"></div>'
    + '<div class="sel-step" id="selResult"></div>'
    + '</div>';
  box.querySelector('.sel-again').addEventListener('click', () => { box.innerHTML = ''; });

  const fbox = $('selFolder');
  const rbox = $('selResult');
  const say = (h) => { fbox.innerHTML = '<p class="dbx-msg">' + h + '</p>'; };
  if (!dayPath) { say('<span class="err">예식 날짜를 알 수 없습니다.</span>'); return; }

  say('드롭박스에서 그날 폴더를 여는 중…');
  const r = await sb.rpc('admin_dbx_ls_req', { p_path: dayPath, p_cursor: null });
  if (r.error) { say('<span class="err">' + esc(r.error.message) + '</span>'); return; }
  if (r.data && r.data.error) { say('<span class="err">' + esc(r.data.error) + '</span>'); return; }
  const day = await dbxWait('admin_dbx_ls_res', { p_req: r.data.req });
  if (day.missing) {
    say('<span class="err">드롭박스에 <b>' + esc(dayPath) + '</b> 폴더가 없습니다.<br />'
      + '아직 백업 전이거나 날짜 폴더 이름이 다릅니다.</span>'); return;
  }
  if (day.error) { say('<span class="err">' + esc(day.error) + '</span>'); return; }
  const folders = (day.entries || []).filter((e) => e.dir);
  if (!folders.length) { say('<span class="err">그날 폴더 안에 예식 폴더가 없습니다.</span>'); return; }

  // 어느 폴더를 볼지 고른다. 하나가 아니라 여럿일 수 있다 —
  // 2인 촬영이면 신부가 고른 사진이 메인·서브 폴더에 나뉘어 있다.
  // (정소민 예식: 40장 중 홍창완 31장 / 최선종 9장)
  const chunks = nfc(ctx.folder)
    .split(/[^0-9A-Za-z가-힣]+/)
    .filter((x) => x.length >= 2 && !/^\d+$/.test(x));   // 날짜 같은 숫자 토막은 뺀다
  const hints = [who, ctx.b && ctx.b.bride_name, ctx.b && ctx.b.groom_name]
    .concat(selParse(ctx.folder).names).concat(chunks).filter(Boolean);
  const byName = hints.length
    ? folders.map((f, i) => (hints.some((n) => nfc(f.name).indexOf(nfc(n)) >= 0) ? i : -1)).filter((i) => i >= 0)
    : [];

  // 그날 폴더가 하나뿐이면 고민할 게 없다
  const on = new Set(folders.length === 1 ? [0] : byName);
  let photo = null;                     // 사진으로 세어본 결과 {i: 몇 장}
  let photoWeak = false;                // 조금밖에 안 겹쳐서 믿기 어려운 경우

  // 이름으로 못 맞췄으면 사진으로 맞춘다.
  // 신부가 준 파일 이름이 어느 폴더 RAW 에 실제로 들어 있는지 보면 확실하다.
  async function matchByPhoto() {
    const want = (items || []).map((x) => selBase(x.name).toLowerCase()).filter(Boolean);
    if (!want.length) return null;
    const cnt = {};
    for (let i = 0; i < folders.length && i < 6; i++) {
      say('사진으로 맞춰보는 중… (' + (i + 1) + '/' + Math.min(folders.length, 6) + ')');
      const got = await dbxRawFiles(folders[i].path, () => {});
      if (got.error) continue;
      const have = {};
      got.files.forEach((f) => { have[selBase(f.name).toLowerCase()] = 1; });
      const n = want.filter((w) => have[w]).length;
      if (n > 0) cnt[i] = n;
    }
    return Object.keys(cnt).length ? cnt : null;
  }

  const drawFolder = () => {
    const total = items.length;
    fbox.innerHTML =
      '<div class="sel-row"><span class="sel-lab">예식 폴더</span>'
      + '<div class="sel-folders">' + folders.map((f, i) =>
          '<label class="sel-fold' + (on.has(i) ? ' on' : '') + '">'
          + '<input type="checkbox" class="sel-fchk" data-i="' + i + '"' + (on.has(i) ? ' checked' : '') + ' />'
          + '<span>' + esc(f.name) + '</span>'
          + (photo && photo[i] ? '<b class="sel-fn">' + photo[i] + '장</b>'
             : photo ? '<b class="sel-fn none">0장</b>' : '')
          + '</label>').join('') + '</div></div>'
      + (photo && photoWeak
          ? '<p class="dbx-msg sel-warn">⚠ 사진을 세어봤지만 조금밖에 안 맞습니다'
            + ' — 같은 작가가 같은 카메라로 찍으면 번호가 우연히 겹칩니다.'
            + '<br />맞는 폴더를 직접 골라 주세요.</p>'
          : photo
          ? '<p class="dbx-msg sel-ok-in">✓ 사진이 어느 폴더에 있는지 세어봤습니다.'
            + (Object.keys(photo).length > 1 ? ' <b>두 폴더에 나뉘어 있어 둘 다 골랐습니다.</b>' : '') + '</p>'
          : byName.length > 1
          ? '<p class="dbx-msg sel-ok-in">✓ 이름이 맞는 폴더가 ' + byName.length + '개라 모두 골랐습니다'
            + ' (2인 촬영이면 사진이 나뉘어 있습니다)</p>'
          : !byName.length && folders.length > 1
          ? '<p class="dbx-msg sel-warn">⚠ 어느 예식인지 몰라 못 골랐습니다 — 직접 골라 주세요</p>'
          : '')
      + '<button type="button" class="btn-sm primary sel-go"' + (on.size ? '' : ' disabled') + '>'
      + '고른 폴더에서 RAW ' + total + '장 찾기</button>'
      + '<p class="dbx-msg sel-fstat"></p>';
    fbox.querySelectorAll('.sel-fchk').forEach((el2) => el2.addEventListener('change', () => {
      const i = Number(el2.dataset.i);
      if (el2.checked) on.add(i); else on.delete(i);
      rbox.innerHTML = '';
      drawFolder();
    }));
    fbox.querySelector('.sel-go').addEventListener('click', run);
  };

  async function run() {
    if (!on.size) return;
    const btn = fbox.querySelector('.sel-go');
    btn.disabled = true;
    const stat = fbox.querySelector('.sel-fstat');
    // 고른 폴더를 전부 훑어 RAW 를 한 자루에 담는다
    const files = [];
    const names = [];
    for (const i of [...on].sort((x, y) => x - y)) {
      const got = await dbxRawFiles(folders[i].path, (h) => { stat.textContent = folders[i].name + ' — ' + h; });
      if (got.error) { btn.disabled = false; stat.innerHTML = '<span class="err">' + esc(got.error) + '</span>'; return; }
      files.push.apply(files, got.files);
      names.push(got.rawName + ' ' + got.files.length.toLocaleString('ko-KR') + '장');
    }
    btn.disabled = false;
    stat.textContent = names.join(' + ') + (names.length > 1
      ? ' = 모두 ' + files.length.toLocaleString('ko-KR') + '장' : '');
    return selShow(rbox, ctx, folders[[...on][0]], { rawName: names.join(' + '), files: files }, items);
  }

  if (!byName.length && folders.length > 1 && items.length) {
    const cnt = await matchByPhoto();
    if (cnt) {
      photo = cnt;
      // 다 합쳐 절반도 안 되면 우연히 번호가 겹친 것일 수 있다 — 정하지 말고 물어본다
      const sum = Object.keys(cnt).reduce((a, k) => a + cnt[k], 0);
      photoWeak = sum * 2 < items.length;
      if (!photoWeak) Object.keys(cnt).forEach((i) => on.add(Number(i)));
    }
  }
  drawFolder();
  // 골라진 게 있으면 바로 찾는다. 아무것도 못 골랐으면 사람이 고르게 둔다.
  if (items.length && on.size) return run();
}

/* ── 결과 ─────────────────────────────────────────────────────── */
const selMB = (n) => (n >= 1024 * 1024 * 1024
  ? (n / 1024 / 1024 / 1024).toFixed(1) + 'GB' : Math.round(n / 1024 / 1024) + 'MB');

async function selShow(rbox, ctx, folder, got, items) {
  const want = (items || []).map((it) => it.name);
  const ups = (items || []).filter((it) => it.file || it.entry);   // 올릴 수 있는 것(알맹이가 있는 것)
  // 이름만 붙여넣은 경우(ups 가 아예 0)는 원래 그런 것이라 넘어간다.
  // 몇 장만 알맹이가 없는 건 다른 얘기다 — 그건 읽다 만 것이니 알려줘야 한다
  const noBody = ups.length ? (items || []).filter((it) => !it.file && !it.entry).map((it) => it.name) : [];
  const { hit, miss, dup } = selMatch(want, got.files);
  if (!selRoots) selRoots = await selLoadRoots();
  // 자동으로 넣는 것은 «YYYY 자동셀렉» 에 모은다 — 손으로 하던 «셀렉파일» 과 갈라둔다.
  // 연도는 예식 연도가 아니라 셀렉한 시점이다. 해가 바뀌면 저절로 다음 해 폴더를 쓴다.
  const thisYear = new Date().getFullYear() + ' 자동셀렉';
  const roots = [ '/' + thisYear ].concat((selRoots || []).filter((p) => p !== '/' + thisYear));
  const name = selDestName(ctx.date, ctx.folder, ctx.b && ctx.b.contractor_name);
  const bytes = ups.reduce((s, it) => s + ((it.file && it.file.size) || 0), 0);

  rbox.innerHTML =
    '<div class="sel-nums">'
    + '<div class="sel-num ok"><b>' + hit.length + '</b><span>찾음</span></div>'
    + '<div class="sel-num' + (miss.length ? ' bad' : '') + '"><b>' + miss.length + '</b><span>못 찾음</span></div>'
    + '<div class="sel-num' + (dup.length ? ' warn' : '') + '"><b>' + dup.length + '</b><span>중복</span></div>'
    + '</div>'
    + (miss.length
        ? '<div class="sel-miss-box"><b>못 찾은 사진 ' + miss.length + '장</b>'
          + '<div class="sel-names">' + miss.map((n) => '<code>' + esc(n) + '</code>').join('') + '</div>'
          + '<p class="dbx-msg">이름이 바뀌었거나, 다른 예식 폴더일 수 있습니다. 위에서 예식 폴더를 바꿔 보세요.</p></div>'
        : '')
    + (dup.length
        ? '<p class="dbx-msg">같은 사진을 두 번 고르셨습니다 — 한 번만 복사합니다: '
          + esc(dup.join(', ')) + '</p>'
        : '')
    + (hit.length
        ? '<details class="sel-hits"><summary>찾은 ' + hit.length + '장 보기</summary>'
          + '<div class="sel-names">' + hit.map((f) => '<code>' + esc(f.name) + '</code>').join('') + '</div></details>'
        : '')
    + ((hit.length || ups.length)
        ? '<div class="sel-dest-box">'
          + '<div class="sel-row"><span class="sel-lab">넣을 곳</span>'
          + '<select class="sel-sel sel-root">' + roots.map((p, i) =>
              '<option value="' + esc(p) + '"' + (i === 0 ? ' selected' : '') + '>' + esc(p) + '</option>').join('')
          + '</select></div>'
          + '<input type="text" class="sel-dest sel-name" value="' + esc(name) + '" />'
          + '<p class="dbx-msg sel-plan">이 폴더를 새로 만들고 '
          + (ups.length ? '<b>신부 JPG ' + ups.length + '장</b>' + (bytes ? ' (' + selMB(bytes) + ')' : '') : '')
          + (ups.length && hit.length ? ' 과 ' : '')
          + (hit.length ? '<b>RAW ' + hit.length + '장</b>' : '')
          + ' 을 넣습니다.</p>'
          // 이름은 왔는데 알맹이가 안 온 것 — 그대로 두면 «올렸습니다» 라고 하면서
          // 조용히 그 수만큼 모자라게 들어간다 (대표 신고 2026-08-24: RAW 40 · JPG 38)
          + (ups.length && noBody.length
              ? '<p class="dbx-msg sel-nobody">⚠ ' + noBody.length + '장은 <b>알맹이가 안 와서 못 올립니다</b> — '
                + esc(noBody.slice(0, 8).join(', '))
                + (noBody.length > 8 ? ' 외 ' + (noBody.length - 8) + '장' : '')
                + '<br />폴더를 다시 끌어다 놓거나 [파일 고르기] 로 다시 골라주세요. '
                + 'RAW 는 이름만으로 찾으니 그대로 들어갑니다.</p>'
              : '')
          + '<button type="button" class="btn-sm primary sel-copy">업로드 &amp; 복사</button>'
          + '<div class="sel-bar" hidden><i></i></div>'
          + '<p class="dbx-msg sel-stat"></p></div>'
        : '<p class="dbx-msg err">넣을 게 없습니다.</p>');

  const cp = rbox.querySelector('.sel-copy');
  if (!cp) return;
  cp.addEventListener('click', async () => {
    const dest = rbox.querySelector('.sel-root').value + '/' + rbox.querySelector('.sel-name').value.trim();
    const stat = rbox.querySelector('.sel-stat');
    const bar = rbox.querySelector('.sel-bar');
    const fill = bar && bar.querySelector('i');
    cp.disabled = true;
    if (bar) bar.hidden = false;
    const prog = (a, b) => { if (fill) fill.style.width = Math.round((a / Math.max(b, 1)) * 100) + '%'; };

    // ① 신부가 보낸 JPG 를 올린다 — 대표 PC 에서 드롭박스로 곧장 간다
    let upDone = 0, warn = '';
    if (ups.length) {
      const r = await selUpload(dest, ups, (a, bad) => {
        upDone = a; prog(a + (bad || 0), ups.length);
        stat.textContent = '신부 JPG 올리는 중… ' + a + ' / ' + ups.length
          + (bad ? '  (못 올린 것 ' + bad + ')' : '');
      });
      if (r.stopped) {
        cp.disabled = false; if (bar) bar.hidden = true;
        stat.innerHTML = '<span class="err">' + esc(r.stopped) + '</span>'; return;
      }
      upDone = r.done;
      // 못 올린 게 있으면 마지막까지 들고 간다 — 끝났다는 말에 묻히면 안 된다
      if (r.failed.length) {
        // 못 올린 것만 새 자리를 받아 한 번 더. 낱장 재시도(세 번)로도 안 되면 여기로 온다
        const again = ups.filter((it) => r.failed.some((f) => f.name === it.name));
        stat.textContent = '못 올린 ' + again.length + '장을 다시 올리는 중…';
        const r2 = await selUpload(dest, again, (a) => {
          stat.textContent = '다시 올리는 중… ' + a + ' / ' + again.length;
        });
        upDone += r2.done;
        if (r2.failed.length) {
          // 왜 안 올라갔는지 같이 적는다 — 이유를 모르면 손쓸 데가 없다 (2026-08-24)
          const why = {};
          r2.failed.forEach((f) => { (why[f.why] = why[f.why] || []).push(f.name); });
          warn = '<br /><span class="err">' + r2.failed.length + '장을 못 올렸습니다.<br />'
            + Object.keys(why).map((k) => esc(k) + ' — ' + esc(why[k].slice(0, 8).join(', '))
                + (why[k].length > 8 ? ' 외 ' + (why[k].length - 8) + '장' : '')).join('<br />')
            + '<br />드롭박스에서 확인하고 그것만 직접 올려주세요.</span>';
        }
      }
    }

    // ② 찾은 RAW 를 복사한다
    if (!hit.length) {
      if (upDone) await sb.rpc('admin_dbx_up_log',
        { p_booking_id: (ctx.b && ctx.b.id) || null, p_dest: dest, p_n: upDone });
      if (bar) bar.hidden = true;
      cp.textContent = '완료 ✓';
      stat.innerHTML = '<b class="sel-ok">✓ JPG ' + upDone + '장 올렸습니다.</b><br />'
        + '<a href="' + esc(selDbxUrl(dest)) + '" target="_blank" rel="noopener">' + esc(dest) + ' 열어보기 ↗</a>'
        + warn;
      toast('JPG ' + upDone + '장 올렸습니다');
      selRecent();
      return;
    }

    stat.textContent = 'RAW 복사하는 중… (장수가 많으면 조금 걸립니다)';
    const s = await sb.rpc('admin_dbx_copy_req',
      { p_booking_id: (ctx.b && ctx.b.id) || null, p_dest: dest, p_files: hit.map((f) => f.path) });
    if (s.error || (s.data && s.data.error)) {
      cp.disabled = false; if (bar) bar.hidden = true;
      stat.innerHTML = '<span class="err">' + esc((s.error && s.error.message) || s.data.error) + '</span>';
      return;
    }
    const args = { p_booking_id: (ctx.b && ctx.b.id) || null, p_dest: dest, p_n: s.data.n, p_up: upDone };
    let res = await dbxWait('admin_dbx_copy_res',
      Object.assign({ p_req: s.data.req, p_job: null }, args), 40000);
    // 장수가 많으면 드롭박스가 뒤에서 처리한다 — 다 될 때까지 물어본다(최대 3분)
    const until = Date.now() + 180000;
    while (res.again && Date.now() < until) {
      await new Promise((x) => setTimeout(x, 1500));
      stat.textContent = 'RAW 복사하는 중… 드롭박스가 처리하고 있습니다';
      res = await dbxWait('admin_dbx_copy_res',
        Object.assign({ p_req: res.again, p_job: res.job }, args), 60000);
    }
    if (res.again) res = { error: '복사가 아직 진행 중입니다. 잠시 후 드롭박스에서 확인해 주세요.' };
    if (bar) bar.hidden = true;
    if (res.error) { cp.disabled = false; stat.innerHTML = '<span class="err">' + esc(res.error) + '</span>'; return; }
    // 드롭박스가 장마다 결과를 주는데, 일부만 실패해도 예전엔 다 됐다고 말했다
    if (res.failed) {
      warn += '<br /><span class="err">RAW ' + res.failed + '장은 복사되지 않았습니다'
        + (res.why ? ' (' + esc(res.why) + ')' : '')
        + '<br />폴더를 열어 확인하고 그것만 다시 해주세요.</span>';
    }
    // 셀렉은 기본 40장이라 JPG 와 RAW 수가 같아야 한다 (대표 2026-08-24).
    // 어긋나면 어딘가 빠진 것이니 «넣었습니다» 로 끝내지 않고 짚어준다
    if (upDone && res.n && upDone !== res.n) {
      warn += '<br /><span class="err">⚠ JPG ' + upDone + '장 · RAW ' + res.n
        + '장 — <b>' + Math.abs(upDone - res.n) + '장이 어긋납니다.</b>'
        + '<br />셀렉은 짝이 맞아야 합니다. 폴더를 열어 모자란 쪽을 채워주세요.</span>';
    }
    stat.innerHTML = '<b class="sel-ok">✓ '
      + (upDone ? 'JPG ' + upDone + '장 + ' : '') + 'RAW ' + res.n + '장 넣었습니다.</b><br />'
      + '<a href="' + esc(selDbxUrl(res.dest)) + '" target="_blank" rel="noopener">' + esc(res.dest) + ' 열어보기 ↗</a>'
      + warn;
    cp.textContent = '완료 ✓';
    toast((upDone ? upDone + '장 올리고 ' : '') + res.n + '장 복사했습니다');
    selRecent();
  });
}

/* 신부가 보낸 JPG 올리기.
   파일은 우리 서버를 거치지 않는다 — 서버는 '이 경로에만 쓸 수 있는' 임시 링크만 내주고,
   알맹이는 대표 PC 에서 드롭박스로 곧장 간다. 한 번에 8장씩 받는다(그 이상은 드롭박스가 막는다). */
async function selUpload(dest, items, onProg) {
  const failed = [];      // 못 올린 것들 (이름)
  let done = 0;
  let stop = '';          // 아예 더 갈 수 없는 사정(연결 끊김 등)

  for (let i = 0; i < items.length && !stop; i += 8) {
    const part = items.slice(i, i + 8);
    // 링크 받기 — 한 번 어긋나면 한 번 더 해본다(드롭박스가 잠깐 막을 때가 있다)
    let got = null;
    for (let tryN = 0; tryN < 2 && !got; tryN++) {
      if (tryN) await new Promise((x) => setTimeout(x, 1500));
      const r = await sb.rpc('admin_dbx_up_req', { p_dest: dest, p_names: part.map((x) => x.name) });
      if (r.error) { if (tryN) stop = r.error.message; continue; }
      if (r.data && r.data.error) { stop = r.data.error; break; }   // 경로가 막힌 것 — 다시 해도 소용없다
      const res = await dbxWait('admin_dbx_up_res', { p_reqs: r.data.reqs }, 40000);
      if (res && res.links) got = res;
      else if (tryN) stop = (res && res.error) || '드롭박스가 응답하지 않습니다.';
    }
    if (!got) {
      // 이 묶음은 건너뛴다. 뒤는 계속 올린다 — 통째로 그만두면 «올라가다 말고» 가 된다
      part.forEach((it) => failed.push({ name: it.name, why: '올릴 자리를 못 받았습니다' }));
      continue;
    }

    const byName = {};
    (got.links || []).forEach((l) => { byName[l.name] = l; });
    // 한 묶음 안에서는 넷씩만 동시에 — 한꺼번에 여덟이면 회선이 막혀 더 느려진다
    for (let k = 0; k < part.length; k += 4) {
      await Promise.all(part.slice(k, k + 4).map(async (it) => {
        const l = byName[it.name];
        if (!l || !l.url) { failed.push({ name: it.name, why: (l && l.error) || '올릴 자리를 못 받았습니다' }); return; }
        let blob = null;
        try { blob = await selFile(it); } catch (e) { blob = null; }
        if (!blob) { failed.push({ name: it.name, why: '파일을 읽지 못했습니다' }); return; }
        // 한 장씩 세 번까지 다시 해본다. 예전엔 한 번 어긋나면 그걸로 끝이라
        // 매번 몇 장씩 남아 대표가 손으로 다시 눌러야 했다 (2026-08-24)
        let why = '';
        for (let tryN = 0; tryN < 3; tryN++) {
          if (tryN) await new Promise((x) => setTimeout(x, 800 * tryN));
          try {
            const up = await fetch(l.url, { method: 'POST',
              headers: { 'Content-Type': 'application/octet-stream' }, body: blob });
            if (up.ok) { done++; why = ''; break; }
            why = '드롭박스가 거절했습니다 (' + up.status + ')';
            // 400대는 다시 해도 같은 답이 온다. 429(너무 잦음)만 예외로 다시 해본다
            if (up.status >= 400 && up.status < 500 && up.status !== 429) break;
          } catch (e) { why = '올리는 도중 연결이 끊겼습니다'; }
        }
        if (why) failed.push({ name: it.name, why: why });
        if (onProg) onProg(done, failed.length);
      }));
    }
  }
  return { done: done, failed: failed, stopped: stop };
}

async function selLoadRoots() {
  const r = await sb.rpc('admin_dbx_roots_req');
  if (r.error || !r.data || r.data.error) return [];
  const res = await dbxWait('admin_dbx_roots_res', { p_req: r.data.req });
  return (res && res.roots) || [];
}

// 최근에 복사한 것 — 뭘 이미 했는지 한눈에
async function selRecent() {
  const el = $('selLog');
  if (!el) return;
  const { data } = await sb.rpc('admin_dbx_copy_recent');
  const rows = Array.isArray(data) ? data : [];
  if (!rows.length) { el.innerHTML = ''; return; }
  el.innerHTML = '<div class="sel-log"><h3>최근에 복사한 것</h3>'
    + rows.map((x) => {
        // 셀렉은 기본 40장이라 JPG 와 RAW 수가 같아야 한다 (대표 2026-08-24).
        // 어긋난 줄은 붉게 짚어준다 — 251129 백다은 건이 JPG 38 · RAW 40 으로
        // 조용히 지나갔다. 목록에서 눈에 띄었으면 바로 알았을 것이다
        const odd = x.up && x.n && Number(x.up) !== Number(x.n);
        return '<div class="sel-log-row' + (odd ? ' odd' : '') + '"><span class="sel-log-n">'
          + (x.up ? 'JPG ' + x.up + (x.n ? ' + RAW ' + x.n : '') : x.n + '장')
          + (odd ? '<em title="JPG 와 RAW 수가 다릅니다">⚠ ' + Math.abs(x.up - x.n) + '장 차이</em>' : '')
          + '</span>'
          + '<a href="' + esc(selDbxUrl(x.dest)) + '" target="_blank" rel="noopener">' + esc(x.dest) + '</a>'
          + '<small>' + esc(fmtDateTime(x.at)) + '</small></div>';
      }).join('')
    + '</div>';
}

// 예약 상세의 버튼 — 전용 탭으로 넘겨준다
function dbxSelect(b) {
  const t = document.querySelector('.dtab[data-tab="select"]');
  if (t) t.click();
  const wd = String(b.wedding_date || '').slice(0, 10);
  setTimeout(() => selOpen({ b: b, date: wd, folder: '' }, []), 0);
}

/* ===== 드롭박스에서 신부에게 공유 =====
   앱 권한이 '읽기 + 공유 링크 만들기' 뿐이라 여기서 파일이 지워질 일은 없다.
   pg_net 이 비동기라 '요청 → 잠깐 기다렸다 꺼내기' 두 단계로 돈다. */
const dbxPicked = {};   // { 예약id: {path, name} } — 공유할 때 고른 예식 폴더

async function dbxWait(fn, args, ms = 20000) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    await new Promise((r) => setTimeout(r, 600));
    const { data, error } = await sb.rpc(fn, args);
    if (error) return { error: error.message };
    if (!data || !data.pending) return data || {};
  }
  return { error: '드롭박스가 응답하지 않습니다. 잠시 후 다시 눌러주세요.' };
}

async function dbxShare(b, btn, box, input) {
  if (!box) return;
  const say = (h) => { box.innerHTML = h; };
  const pick = (sel) => box.querySelector(sel);
  btn.disabled = true;
  say('<p class="dbx-msg">드롭박스에서 폴더를 찾는 중…</p>');

  const start = await sb.rpc('admin_dbx_list_req', { p_booking_id: b.id });
  if (start.error) { say('<p class="dbx-msg err">' + esc(start.error.message) + '</p>'); btn.disabled = false; return; }
  if (start.data && start.data.error) { say('<p class="dbx-msg err">' + esc(start.data.error) + '</p>'); btn.disabled = false; return; }

  const list = await dbxWait('admin_dbx_list_res', { p_req: start.data.req });
  btn.disabled = false;
  if (list.error) { say('<p class="dbx-msg err">' + esc(list.error) + '</p>'); return; }
  if (list.missing) {
    say('<p class="dbx-msg err">드롭박스에 <b>' + esc(start.data.path) + '</b> 폴더가 없습니다.<br />아직 백업 전이거나 날짜 폴더 이름이 다릅니다.</p>');
    return;
  }
  const folders = list.folders || [];
  if (!folders.length) { say('<p class="dbx-msg err">그날 폴더 안에 예식 폴더가 없습니다.</p>'); return; }

  // 계약자·신부 이름이 들어간 폴더를 먼저 고른다
  const names = [b.contractor_name, b.bride_name].filter(Boolean);
  const hit = folders.findIndex((f) => names.some((n) => String(f.name).includes(n)));
  const sel = hit >= 0 ? hit : 0;
  say('<p class="dbx-msg">어느 폴더를 보낼까요?</p>'
    + '<div class="dbx-list">' + folders.map((f, i) =>
        '<label class="dbx-item"><input type="radio" name="dbxPick" value="' + i + '"' + (i === sel ? ' checked' : '') + ' />'
        + '<span>' + esc(f.name) + '</span></label>').join('') + '</div>'
    + '<button type="button" class="btn-sm primary dbx-go">이 폴더로 공유 링크 만들기</button>'
    + '<p class="dbx-msg dbx-stat"></p>');

  const go = pick('.dbx-go');
  if (!go) return;
  go.addEventListener('click', async () => {
    const idx = Number((pick('input[name="dbxPick"]:checked') || {}).value || 0);
    const f = folders[idx];
    dbxPicked[b.id] = f;
    go.disabled = true;
    pick('.dbx-stat').textContent = '공유 링크를 만드는 중…';
    const s = await sb.rpc('admin_dbx_share_req', { p_booking_id: b.id, p_path: f.path });
    if (s.error || (s.data && s.data.error)) {
      pick('.dbx-stat').textContent = (s.error && s.error.message) || s.data.error; go.disabled = false; return;
    }
    let res = await dbxWait('admin_dbx_share_res', { p_req: s.data.req, p_booking_id: b.id, p_path: f.path });
    // 이미 공유 링크가 있는 폴더면 서버가 기존 링크를 물어본다 — 그 답을 이어서 기다린다
    if (res.relist) {
      res = await dbxWait('admin_dbx_share_res', { p_req: res.relist, p_booking_id: b.id, p_path: f.path });
    }
    go.disabled = false;
    if (res.error) { pick('.dbx-stat').textContent = res.error; return; }
    b.download_link = res.url;
    const i = allBookings.findIndex((x) => x.id === b.id);
    if (i >= 0) allBookings[i].download_link = res.url;
    if (input) input.value = res.url;
    const sent = !!(b.alimtalk_sent && b.alimtalk_sent.E);
    say('<p class="dbx-msg ok">✓ 공유 링크를 만들어 저장했습니다.</p>'
      + '<p class="dbx-url">' + esc(res.url) + '</p>'
      + '<div class="dbx-done">'
      + '<a class="btn-sm" href="' + esc(res.url) + '" target="_blank" rel="noopener">링크 열어보기 ↗</a>'
      + '<button type="button" class="btn-sm btn-kakao-sm dbx-atk">'
      + (sent ? '카톡 다시 보내기' : '📨 신부에게 카톡 보내기') + '</button>'
      + '</div>'
      + '<p class="dbx-msg dbx-stat2"></p>');
    const atk = pick('.dbx-atk');
    if (atk) atk.addEventListener('click', async () => {
      atk.disabled = true;
      const before = atk.textContent;
      atk.textContent = '보내는 중…';
      const { error } = await sb.rpc('admin_send_alimtalk', { p_booking_id: b.id, p_template: 'E' });
      if (error) {
        atk.disabled = false; atk.textContent = before;
        const st = pick('.dbx-stat2'); if (st) st.textContent = '발송 실패: ' + error.message;
        return;
      }
      atk.textContent = '보냈습니다 ✓';
      b.alimtalk_sent = Object.assign({}, b.alimtalk_sent, { E: new Date().toISOString() });
      const i = allBookings.findIndex((x) => x.id === b.id);
      if (i >= 0) allBookings[i] = b;
      toast(esc(b.contractor_name || '') + '님께 보냈습니다');
      // 보내고 나면 '다운로드 링크' 목록에서 빠져야 한다
      renderDashboard();
    });
  });
}

/* ===== 클래리티 — 손님이 어디서 막혔나 =====
   우리 자체 집계는 '몇 명이 왔나'를 보여주고, 이건 '와서 어땠나'를 보여준다.
   매일 한 번 받아 쌓는다(클래리티 API 는 최근 3일치만 내주고 하루 10번 제한). */
const clSec = (s) => {
  const n = Number(s) || 0;
  return n >= 60 ? Math.floor(n / 60) + '분 ' + (n % 60) + '초' : n + '초';
};
function clarityHtml(d) {
  const L = d && d.latest;
  if (!L) {
    return '<div class="dash-card"><div class="dash-card-head"><h3>🖱 방문자 행동 <small>(클래리티)</small></h3></div>'
      + '<p class="dash-empty">아직 받아온 기록이 없습니다. 매일 아침 9시 30분에 하루치가 쌓입니다.</p></div>';
  }
  const md = String(L.the_date).slice(5).replace('-', '.');
  const num = (v) => (v == null ? '-' : stNum(v));
  const card = (k, v, sub) => '<div class="st-card"><span class="st-k">' + k + '</span><strong>' + v
    + '</strong><span class="st-sub">' + (sub || '') + '</span></div>';
  // 답답함 신호 — 0이면 조용히, 있으면 눈에 띄게
  const sig = (label, cnt, pct, why) => {
    const on = Number(cnt) > 0;
    return '<div class="cl-sig' + (on ? ' on' : '') + '">'
      + '<span class="cl-sig-k">' + label + '</span>'
      + '<b>' + num(cnt) + '회</b>'
      + (on ? '<span class="cl-sig-p">세션의 ' + (Number(pct) || 0) + '%</span>' : '<span class="cl-sig-p">없음</span>')
      + '<span class="cl-sig-w">' + why + '</span></div>';
  };
  const pages = (d.pages || []).map((p) => {
    const u = String(p.url || '').replace(/^https?:\/\/[^/]+/, '') || '/';
    const top = Number((d.pages[0] || {}).visits) || 1;
    return '<div class="st-row"><span class="st-row-bar" style="width:' + Math.round((Number(p.visits) / top) * 100) + '%"></span>'
      + '<span class="st-row-k">' + esc(u) + '</span><span class="st-row-v">' + stNum(p.visits) + '</span></div>';
  }).join('');
  return '<div class="dash-card st-chart-card">'
    + '<div class="dash-card-head"><h3>🖱 방문자 행동 <small>(클래리티 · ' + esc(md) + ' 하루치)</small></h3></div>'
    + '<div class="st-cards">'
      + card('세션', num(L.sessions), (L.bots ? '봇 ' + num(L.bots) + ' 제외 전' : ''))
      + card('순 방문자', num(L.users), '')
      + card('평균 스크롤', (L.scroll_avg == null ? '-' : L.scroll_avg + '%'), '아래까지 내려봄')
      + card('머문 시간', clSec(L.active_time), '실제로 움직인 시간')
    + '</div>'
    + '<div class="cl-sigs">'
      + sig('죽은 클릭', L.dead_cnt, L.dead_pct, '눌러도 아무 일 없는 곳을 눌렀다')
      + sig('분노 클릭', L.rage_cnt, L.rage_pct, '같은 자리를 연달아 눌렀다')
      + sig('빠른 이탈', L.quick_cnt, L.quick_pct, '들어왔다가 바로 뒤로 갔다')
      + sig('스크립트 오류', L.err_cnt, L.err_pct, '화면에서 뭔가 깨졌다')
    + '</div>'
    + (pages ? '<div class="cl-pages"><p class="cl-h">페이지별 열린 횟수 <small>(사람 수가 아니라 열린 횟수)</small></p>' + pages + '</div>' : '')
    + '<p class="st-note">클래리티는 최근 3일치만 내려주기 때문에 매일 아침 받아서 쌓습니다. '
    + '녹화 영상과 AI 요약은 클래리티 화면에서만 볼 수 있습니다.</p>'
    + '</div>';
}

async function renderClarity() {
  const box = $('clarityBox');
  if (!box) return;
  const { data, error } = await sb.rpc('admin_clarity', { p_days: 30 });
  if (error) { box.innerHTML = ''; return; }
  box.innerHTML = clarityHtml(data);
}

const stRange = document.querySelector('.st-range');
if (stRange) {
  stRange.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-days]');
    if (!b) return;
    statsDays = parseInt(b.dataset.days, 10) || 7;
    stRange.querySelectorAll('button').forEach((x) => x.classList.toggle('active', x === b));
    statsLoaded = false;
    renderStats();
  });
}




/* ===== 배정 이력·점검 =====
   작가 배정은 사라지면 안 되는 데이터라, 바뀔 때마다 이전 값을 남기고(트리거)
   매시간 배정 수를 점검해 줄어들면 대표 폰으로 알림이 간다. 여기서는 그 결과를 본다. */
const AUDIT_ACT = { set: '배정', change: '작가 변경', clear: '배정 해제', booking_deleted: '예약 삭제' };
const AUDIT_FIELD = { assignee_id: '메인', sub_assignee_id: '서브' };

async function renderAudit() {
  const wrap = $('tab-audit');
  if (!wrap) return;
  const { data, error } = await sb.rpc('admin_assignment_audit', { p_days: 30 });
  if (error) { wrap.innerHTML = '<p class="empty">불러오지 못했습니다. (' + esc(error.message) + ')</p>'; return; }
  const d = data || {};
  const now = d.now || {};
  const last = d.last_check || {};
  const items = Array.isArray(d.items) ? d.items : [];
  const when = last.at ? new Date(last.at).toLocaleString('ko-KR') : '아직 없음';

  const rows = items.length ? items.map((x) => {
    const dt = new Date(x.at).toLocaleString('ko-KR', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' });
    const wd = x.wedding_date ? String(x.wedding_date).slice(0, 10).replace(/-/g, '.') : '';
    const risky = x.action === 'clear' || x.action === 'booking_deleted';
    const who = x.action === 'change' ? esc(x.old_staff_name || '-') + ' → ' + esc(x.new_staff_name || '-')
      : x.action === 'set' ? esc(x.new_staff_name || '-') : esc(x.old_staff_name || '-');
    return '<div class="au-row' + (risky ? ' risky' : '') + '">'
      + '<span class="au-at">' + esc(dt) + '</span>'
      + '<span class="au-act">' + esc((AUDIT_FIELD[x.field] || '') + ' ' + (AUDIT_ACT[x.action] || x.action)) + '</span>'
      + '<span class="au-who">' + who + '</span>'
      + '<span class="au-bk">' + esc(x.contractor_name || '-') + (wd ? ' · ' + esc(wd) : '') + '</span>'
      + '</div>';
  }).join('') : '<p class="empty">최근 30일 안에 배정이 바뀐 적이 없습니다.</p>';

  wrap.innerHTML =
    '<div class="st-cards">'
    + '<div class="st-card"><span class="st-k">앞으로 예식</span><strong>' + (now.upcoming_total || 0) + '</strong><span class="st-sub">취소 제외</span></div>'
    + '<div class="st-card"><span class="st-k">작가 배정됨</span><strong>' + (now.upcoming_assigned || 0) + '</strong><span class="st-sub">메인 기준</span></div>'
    + '<div class="st-card"><span class="st-k">2주 내 미배정</span><strong>' + (now.unassigned_soon || 0) + '</strong><span class="st-sub">배정 필요</span></div>'
    + '</div>'
    + '<p class="st-note">매시간 자동 점검합니다. 배정 수가 줄어들면 대표님 폰으로 바로 알림이 갑니다. 마지막 점검: ' + esc(when) + '</p>'
    + '<div class="dash-card st-chart-card"><div class="dash-card-head"><h3>🕘 배정 변경 이력 <small>(최근 30일 · 최대 100건)</small></h3></div>'
    + '<div class="au-list">' + rows + '</div></div>';
}

/* ===== 작가 평가 (촬영 후 설문) =====
   응답은 대표만 열람. 작가에게 자동으로 가지 않으며, 필요할 때 [공유] 로 대표가 직접 보낸다. */
const ARRIVAL_TXT = { ontime: '제시간', late_small: '조금 늦음', late_big: '많이 늦음' };
// 점수는 10점 만점. 별은 5칸으로 줄여 그리고(÷2), 정확한 값은 옆에 숫자로 적는다
const FB_LOW = 6;                       // 이 점수 이하면 눈에 띄게 표시
// 응답이 두어 건뿐이면 한 사람 답에 점수가 크게 흔들린다 — 곧이곧대로 보지 않게 표시한다.
// 날짜 조회(dcStar)와 통계 화면이 함께 쓴다
const FB_THIN = 3;
// 응답률이 이보다 낮으면 눈에 띄게 — 설문이 제대로 나갔는지부터 봐야 한다
const FB_RATE_LOW = 20;
const stars = (n) => { const k = Math.max(0, Math.min(5, Math.round((Number(n) || 0) / 2)));
  return '★★★★★'.slice(0, k) + '☆☆☆☆☆'.slice(0, 5 - k); };
const avg1 = (v) => (v == null ? '-' : Number(v).toFixed(1));
let fbDays = 90;         // 응답 조회 기간 (기본 3개월)
let fbStaff = null;      // 특정 작가만 보기
let fbPendAll = false;   // '설문 안 온 예식'을 2주 이전까지 펼쳤는지
let fbPendOpen = false;  // '설문 안 온 예식' 카드를 폈는지 (기본 접힘)
let fbPage = 0;          // 받은 응답 페이지 (0부터)
const FB_PER = 10;       // 한 페이지에 보여줄 응답 수
const fbRangeLabel = () => (fbDays >= 3650 ? '전체 기간' : fbDays >= 365 ? '최근 1년' : '최근 3개월');

async function renderFeedback() {
  const wrap = $('fbBody');
  if (!wrap) return;
  // 촬영 이력은 한 번만 받아 두면 된다 (기간을 바꿔도 안 바뀐다)
  const [fr, pr] = await Promise.all([
    sb.rpc('admin_feedback', { p_days: fbDays }),
    sb.rpc('admin_feedback_pending'),
    staffShots ? Promise.resolve() : loadStaffShots(),
  ]);
  if (fr.error) { wrap.innerHTML = '<p class="empty">불러오지 못했습니다. (' + esc(fr.error.message) + ')</p>'; return; }
  const d = fr.data || {};
  const staff = Array.isArray(d.staff) ? d.staff : [];
  const allItems = Array.isArray(d.items) ? d.items : [];
  const items = fbStaff ? allItems.filter((x) => x.staff_name === fbStaff) : allItems;

  // ── 설문 안 온 예식: 기본은 최근 2주만. 오래된 건 이제 와서 보내기 어색하므로 접어둔다 ──
  const pendAll = (Array.isArray(pr.data) ? pr.data : []).filter((x) => !x.done);
  const cut = new Date(); cut.setDate(cut.getDate() - 14);
  const isRecent = (x) => new Date(String(x.wedding_date).slice(0, 10) + 'T00:00:00') >= cut;
  const pendShown = fbPendAll ? pendAll : pendAll.filter(isRecent);
  const pendHidden = pendAll.length - pendShown.length;

  const pendRows = pendShown.map((x) => {
    const dd = String(x.wedding_date).slice(0, 10).replace(/-/g, '.');
    return '<div class="fb-prow">'
      + '<span class="fb-pdate">' + esc(dd) + '</span>'
      + '<span class="fb-pname">' + esc(x.contractor_name || '-') + '</span>'
      + '<span class="fb-pstaff">' + esc(x.staff_name || '미배정') + '</span>'
      + (x.sent ? '<span class="fb-psent">알림톡 보냄</span>' : '')
      + '<button class="btn-sm fb-copy" data-id="' + esc(x.id) + '">설문 링크</button>'
      + '<button class="btn-sm btn-kakao-sm fb-sharelink" data-id="' + esc(x.id) + '" data-name="' + esc(x.contractor_name || '') + '">공유</button>'
      + '</div>';
  }).join('');

  // 평점과 촬영 건수를 한 줄에 묶는다 (대표 요청 2026-08-25 «작가 평점과 건수는 묶어서»).
  // 촬영 이력은 이름으로 맞춘다 — 설문 쪽은 이름만 들고 온다
  const shotsBy = {};
  ((staffShots && staffShots.staff) || []).forEach((x) => { shotsBy[x.staff_name] = x; });
  const staffRows = staff.length ? staff.map((s, si) => {
    const on = fbStaff === s.staff_name;
    const sh = shotsBy[s.staff_name];
    // 많이 간 곳은 셋만 보이고 나머지는 접는다 (대표 요청). 열면 열 곳까지
    const tops = (sh && sh.top) || [];
    const vName = (v) => esc(String(v).replace(/\s*[-/(,].*$/, '').slice(0, 16));
    const venue = tops.length
      ? '<span class="fb-svn">'
        + tops.slice(0, 3).map((x) => vName(x.venue) + ' <b>' + x.n + '</b>').join(' · ')
        + (tops.length > 3
          ? '<span class="fb-svn-more" hidden id="fbvn' + si + '"> · '
            + tops.slice(3, 10).map((x) => vName(x.venue) + ' <b>' + x.n + '</b>').join(' · ') + '</span>'
            + '<button type="button" class="fb-svn-btn" data-vn="' + si + '">더보기</button>'
          : '') + '</span>'
      : '';
    // 한 줄에 다 넣고 칸 높이를 낮춘다 (대표 요청 2026-08-25 «작가들 칸 높이를 낮춰줘»).
    // 「예식장 N곳」은 뺐다 — 대표가 「이건 뭐지? 빼도 될거 같은데」
    // 응답은 「9건 중 응답 2건 22%」 차례로 (대표가 정해준 말차례)
    const rate = s.target
      ? '<span class="fb-rate' + (Number(s.rate) < FB_RATE_LOW ? ' low' : '') + '">'
        + s.target + '건 중 응답 ' + s.n + '건 ' + (s.rate == null ? '-' : s.rate + '%') + '</span>'
      : '<span class="fb-rate">응답 ' + s.n + '건</span>';
    // 「응답 적음」은 뺐다 (대표 요청 2026-08-26). 응답률이 20% 아래면 붉게 뜨는 것으로 충분하다
    const tags = [
      s.avg_rec == null ? '' : '추천 ' + s.avg_rec,
      s.avg_overall == null ? '' : '만족 ' + avg1(s.avg_overall),
      s.sub_n ? '서브 ' + s.sub_avg : '',
      Number(s.late_n) ? '지각 ' + s.late_n : '',
      s.req_n ? '부탁 ' + s.req_n : '',
    ].filter(Boolean).join(' · ');
    return '<div class="fb-srow' + (on ? ' on' : '') + '" data-staff="' + esc(s.staff_name) + '" title="누르면 이 작가 응답만 보기">'
      + '<span class="fb-sname">' + esc(s.staff_name) + '</span>'
      // 순위는 100점 만점 가중 점수. 2026-08-25 부터 추천 의향이 들어갔다
      + '<span class="fb-sscore"><b>' + (s.avg_score == null ? '-' : s.avg_score) + '</b><small>점</small></span>'
      // 촬영 건수 — 평점과 같은 줄에. 응답률은 그 바로 옆에 붙인다
      + '<span class="fb-sshot">' + (sh ? '<b>' + sh.shots + '</b>건' : '') + '</span>'
      + '<span class="fb-sn">' + rate + '</span>'
      + '<span class="fb-stags">' + tags + '</span>'
      + venue
      + '</div>';
  }).join('') : '<p class="empty">아직 응답이 없습니다.</p>';

  // 한 번도 응답이 없는 작가. 만점으로 채우지 않고 그대로 «평가 없음» 으로 둔다 —
  // 무응답은 만족이 아니라 «모른다» 이고, 안 찍힌 작가가 100점이 되면 그건 거짓 숫자다
  const silent = Array.isArray(d.silent) ? d.silent : [];
  const silentRow = silent.length
    ? '<div class="fb-silent">아직 응답이 하나도 없는 작가 — '
      + silent.map((x) => esc(x.staff_name) + ' <b>' + x.n + '건</b>').join(' · ')
      + '<small>점수를 만점으로 채우지 않습니다. 응답이 없는 건 «만족»이 아니라 «모름»이라서요.</small></div>'
    : '';

  // 서브로만 다닌 작가는 위 순위에 아예 안 뜬다 (메인 응답이 없어서). 따로 적어준다.
  // 별점(5점)과 위의 100점 만점 점수는 섞지 않는다 — 물어본 것이 다르다 (2026-08-24)
  const subs = (Array.isArray(d.subs) ? d.subs : [])
    .filter((x) => !staff.some((s) => s.staff_name === x.staff_name));
  const subRow = subs.length
    ? '<div class="fb-silent fb-subs">서브로 참여한 작가 — '
      + subs.map((x) => esc(x.staff_name) + ' <b>' + x.avg + '점</b> (' + x.n + '건)').join(' · ')
      + '<small>서브는 10점 만점 한 문항입니다. 위의 100점 만점 점수와는 물어본 것이 달라 섞지 않습니다.</small></div>'
    : '';

  // 페이지네이션 — 필터/기간이 바뀌어 목록이 짧아지면 마지막 페이지로 당겨준다
  const pageMax = Math.max(0, Math.ceil(items.length / FB_PER) - 1);
  if (fbPage > pageMax) fbPage = pageMax;
  const paged = items.slice(fbPage * FB_PER, fbPage * FB_PER + FB_PER);

  const chip = (label, val, bad) =>
    '<span class="fb-chip' + (bad ? ' bad' : '') + '">' + esc(label) + (val == null ? '' : ' <b>' + val + '</b>') + '</span>';

  const itemRows = paged.length ? paged.map((x) => {
    const wd = x.wedding_date ? String(x.wedding_date).slice(0, 10).replace(/-/g, '.') : '';
    const who = x.bride_name || x.contractor_name || '-';
    const low = Number(x.overall) <= FB_LOW;
    return '<div class="fb-item' + (low ? ' low' : '') + '" data-id="' + esc(x.booking_id) + '">'
      + '<div class="fb-ihead">'
        + '<span class="fb-istar">' + stars(x.overall) + ' <b>' + x.overall + '</b><small>/10</small></span>'
        + '<span class="fb-iwho">' + esc(x.staff_name) + ' <small>(' + esc(who) + (wd ? ' · ' + esc(wd) : '') + ')</small></span>'
      + '</div>'
      + '<div class="fb-chips">'
        + chip('도착 ' + (ARRIVAL_TXT[x.arrival] || x.arrival), null, x.arrival !== 'ontime')
        + chip('친절', x.kindness, Number(x.kindness) <= FB_LOW)
        + chip('요청', x.requests, Number(x.requests) <= FB_LOW)
        + chip('진행', x.flow, Number(x.flow) <= FB_LOW)
        + (x.family == null ? '' : chip('하객', x.family, Number(x.family) <= FB_LOW))
        // 추천 의향 — 0 도 답이라 == null 로만 걸러야 한다 (2026-08-25)
        + (x.recommend == null ? '' : chip('추천', x.recommend, Number(x.recommend) <= FB_LOW))
      + '</div>'
      // 「다음에 부탁드리고 싶은 것」 — 점수는 만점인데 여기에만 적히는 경우가 있다.
      // 실제로 고칠 거리라 제일 눈에 띄게 둔다
      + (x.next_req ? '<div class="fb-inext">📝 다음엔 — ' + esc(x.next_req) + '</div>' : '')
      + (x.issue && x.issue_text ? '<div class="fb-iissue">⚠️ ' + esc(x.issue_text) + '</div>'
         : (x.issue ? '<div class="fb-iissue">⚠️ 불편했던 점 있음(내용 미작성)</div>' : ''))
      + (x.message ? '<div class="fb-imsg">💬 ' + esc(x.message) + '</div>' : '')
      + (x.message || x.issue_text || x.next_req ? '<button class="btn-sm fb-share" data-id="' + esc(x.booking_id) + '">작가에게 공유</button>' : '')
      + '</div>';
  }).join('') : '<p class="empty">' + (fbStaff ? '이 작가의 응답이 없습니다.' : '아직 응답이 없습니다.') + '</p>';

  const pager = items.length > FB_PER
    ? '<div class="fb-pager">'
      + '<button class="btn-sm fb-pg" data-pg="' + (fbPage - 1) + '"' + (fbPage <= 0 ? ' disabled' : '') + '>‹</button>'
      + '<span>' + (fbPage * FB_PER + 1) + '–' + Math.min(items.length, (fbPage + 1) * FB_PER) + ' / ' + items.length + '건</span>'
      + '<button class="btn-sm fb-pg" data-pg="' + (fbPage + 1) + '"' + (fbPage >= pageMax ? ' disabled' : '') + '>›</button>'
      + '</div>'
    : '';

  const rangeBtn = (v, t) => '<button class="btn-sm fb-range' + (fbDays === v ? ' active' : '') + '" data-days="' + v + '">' + t + '</button>';

  wrap.innerHTML =
    '<div class="st-cards fb-top">'
    + '<div class="st-card"><span class="st-k">응답</span><strong>' + (d.count || 0) + '</strong><span class="st-sub">' + esc(fbRangeLabel()) + '</span></div>'
    + '<div class="st-card"><span class="st-k">평균 점수</span><strong>' + (d.avg_score == null ? '-' : d.avg_score) + '</strong><span class="st-sub">100점 만점 · 가중</span></div>'
    // 지정 근거 (대표 요청 2026-08-25). 점수와 달리 이건 갈린다
    + '<div class="st-card"><span class="st-k">추천 의향</span><strong>' + (d.avg_rec == null ? '-' : d.avg_rec) + '</strong>'
      + '<span class="st-sub">10점 만점 · ' + (d.rec_n || 0) + '건</span></div>'
    + '<div class="st-card"><span class="st-k">응답률</span><strong'
      + (d.rate != null && Number(d.rate) < FB_RATE_LOW ? ' class="ab-no"' : '') + '>'
      + (d.rate == null ? '-' : d.rate + '%') + '</strong>'
      + '<span class="st-sub">지난 예식 ' + (d.target || 0) + '건 중</span></div>'
    + '<div class="st-card"><span class="st-k">설문 안 온 예식</span><strong>' + pendAll.length + '</strong><span class="st-sub">최근 60일 · 미응답</span></div>'
    + '</div>'
    + '<div class="dash-card st-chart-card"><div class="dash-card-head"><h3>👤 작가별 <small>(점수 높은 순 · 누르면 그 작가 응답만)</small></h3></div>'
      + '<p class="st-note">점수 = 도착 20 · 친절 20 · 요청 10 · 진행 15 · 하객 15 · <b>추천 20</b> (100점 만점)</p>'

      + staffRows + silentRow + subRow + '</div>'
    + '<div class="dash-card">'
      + '<div class="dash-card-head"><h3>💬 받은 응답 <small>(최근순)</small></h3>'
        + '<span class="fb-rangebar">' + rangeBtn(90, '3개월') + rangeBtn(365, '1년') + rangeBtn(3650, '전체') + '</span></div>'
      + (fbStaff ? '<div class="fb-filter"><b>' + esc(fbStaff) + '</b> 작가 응답만 보는 중 <button class="btn-sm fb-clear">전체 보기</button></div>' : '')
      + '<div class="fb-list">' + itemRows + '</div>'
      + pager
    + '</div>'
    + (pendAll.length
      ? '<div class="dash-card fb-pendcard' + (fbPendOpen ? ' open' : '') + '">'
        + '<div class="dash-card-head"><button type="button" class="fb-pendtoggle" aria-expanded="' + (fbPendOpen ? 'true' : 'false') + '">'
          + '📮 설문 안 온 예식 <small>(링크를 복사해 직접 보낼 수 있습니다)</small> '
          + '<span class="dash-count">' + pendAll.length + '</span> <span class="sv-caret">' + (fbPendOpen ? '▴' : '▾') + '</span></button></div>'
        + (fbPendOpen
          ? '<div class="fb-pend">' + (pendShown.length ? pendRows : '<p class="empty">최근 2주 안에는 없습니다.</p>') + '</div>'
            + (pendHidden > 0 || fbPendAll
              ? '<button class="btn-sm fb-pendmore">' + (fbPendAll ? '최근 2주만 보기' : '2주 이전 ' + pendHidden + '건 더 보기') + '</button>'
              : '')
          : '')
        + '</div>'
      : '')
    + '<p class="st-note">응답은 지워지지 않고 계속 남습니다. 기간 버튼으로 예전 것도 언제든 다시 보실 수 있습니다. [작가에게 공유]를 누르면 손님 이름을 뺀 내용이 복사되어, 카톡에 붙여넣어 보내실 수 있습니다.</p>';

  const fbUrl = (id) => location.origin + '/f?b=' + id;
  wrap.querySelectorAll('.fb-copy').forEach((b) => b.addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(fbUrl(b.dataset.id)); toast('설문 링크 복사됨 · 카톡에 붙여넣어 보내세요'); }
    catch (_) { prompt('아래 링크를 복사하세요:', fbUrl(b.dataset.id)); }
  }));
  wrap.querySelectorAll('.fb-sharelink').forEach((b) => b.addEventListener('click', async () => {
    const nm = b.dataset.name;
    const text = (nm ? nm + '님, ' : '') + '결혼 진심으로 축하드립니다.\n촬영을 담당한 작가에 대해 짧게 여쭙고 싶습니다. 30초면 됩니다.\n' + fbUrl(b.dataset.id);
    if (navigator.share) { try { await navigator.share({ text }); return; } catch (e) { if (e && e.name === 'AbortError') return; } }
    try { await navigator.clipboard.writeText(text); toast('메시지 복사됨 · 카톡에 붙여넣어 보내세요'); }
    catch (_) { prompt('아래 내용을 복사하세요:', text); }
  }));
  wrap.querySelectorAll('.fb-share').forEach((b) => b.addEventListener('click', () => {
    const it = allItems.find((x) => x.booking_id === b.dataset.id);
    if (!it) return;
    const txt = ['[촬영 후 설문]',
      '전체 ' + it.overall + '/10점 · 친절 ' + it.kindness + ' · 요청 ' + it.requests + ' · 진행 ' + it.flow,
      it.issue && it.issue_text ? '아쉬운 점: ' + it.issue_text : '',
      it.message ? '한마디: ' + it.message : ''].filter(Boolean).join(String.fromCharCode(10));
    navigator.clipboard?.writeText(txt);
    toast('복사됐습니다 · 카톡에 붙여넣어 보내세요');
  }));
  const pt = wrap.querySelector('.fb-pendtoggle');
  if (pt) pt.addEventListener('click', () => { fbPendOpen = !fbPendOpen; renderFeedback(); });
  const more = wrap.querySelector('.fb-pendmore');
  if (more) more.addEventListener('click', () => { fbPendAll = !fbPendAll; renderFeedback(); });
  wrap.querySelectorAll('.fb-range').forEach((b) => b.addEventListener('click', () => {
    fbDays = Number(b.dataset.days) || 365; fbPage = 0; renderFeedback();
  }));
  wrap.querySelectorAll('.fb-srow').forEach((r) => r.addEventListener('click', () => {
    fbStaff = fbStaff === r.dataset.staff ? null : r.dataset.staff; fbPage = 0; renderFeedback();
  }));
  // 많이 간 곳 더보기 — 줄 전체를 누르면 작가가 걸리므로 여기서 멈춘다 (2026-08-25)
  wrap.querySelectorAll('.fb-svn-btn').forEach((b) => b.addEventListener('click', (e) => {
    e.stopPropagation();
    const more = $('fbvn' + b.dataset.vn);
    if (!more) return;
    more.hidden = !more.hidden;
    b.textContent = more.hidden ? '더보기' : '접기';
  }));
  const clr = wrap.querySelector('.fb-clear');
  if (clr) clr.addEventListener('click', (e) => { e.stopPropagation(); fbStaff = null; fbPage = 0; renderFeedback(); });
  wrap.querySelectorAll('.fb-pg').forEach((b) => b.addEventListener('click', () => {
    if (b.disabled) return;
    fbPage = Math.max(0, Number(b.dataset.pg) || 0); renderFeedback();
  }));
}

/* ===== 예약·매출 (대표 요청 2026-08-23) =====
   매출은 예식일 기준 총액(계약금+잔금), 순이익은 거기서 작가비를 뺀 것.
   작가비 규칙은 admin_sales() 안에 있고 여기서는 받은 값을 적기만 한다. */
let salesLoaded = false;
// 달마다 표에 보여줄 기간 (대표 요청 2026-08-24) — 최근 / 1년 / 전체
let salesSpan = 'now';
const SPAN_LABEL = { now: '최근', '1y': '1년', all: '전체' };

// 만원 단위를 사람이 읽는 말로. 10754 → '1억 754만'
function manwon(n) {
  const v = Math.round(Number(n) || 0), a = Math.abs(v), sign = v < 0 ? '-' : '';
  if (a < 10000) return sign + a.toLocaleString('ko-KR') + '만';
  const rest = a % 10000;
  return sign + Math.floor(a / 10000) + '억' + (rest ? ' ' + rest.toLocaleString('ko-KR') + '만' : '');
}

// 막대 한 줄 (많이 본 페이지 목록과 같은 모양을 쓴다)
function slBar(label, sub, value, ratio) {
  return '<div class="st-row"><span class="st-row-bar" style="width:' + Math.max(2, Math.round(ratio * 100)) + '%"></span>'
    + '<span class="st-row-k">' + label + (sub ? ' <small>' + sub + '</small>' : '') + '</span>'
    + '<span class="st-row-v">' + value + '</span></div>';
}

async function renderSales() {
  const wrap = $('salesBody');
  if (!wrap) return;
  if (!salesLoaded) wrap.innerHTML = '<p class="empty">불러오는 중…</p>';
  const { data, error } = await sb.rpc('admin_sales', { p_span: salesSpan });
  if (error || !data) {
    wrap.innerHTML = '<p class="empty">불러오지 못했습니다. (' + esc(error ? error.message : '') + ')</p>';
    return;
  }
  salesLoaded = true;
  const y = data.year || {}, c = data.cost || {};
  // 예식이 없는 달이라도 그 달 앨범 발주가 있으면 보여준다 — 나간 돈은 보여야 한다
  const months = (data.months || []).filter((m) => m.n > 0 || m.album > 0);
  const left = Math.max(0, (y.n || 0) - (y.done || 0));
  const rate = y.rev ? Math.round((y.profit / y.rev) * 1000) / 10 : null;
  const card = (k, v, sub) => '<div class="st-card"><span class="st-k">' + k + '</span><strong>' + v
    + '</strong><span class="st-sub">' + (sub || '') + '</span></div>';

  const maxRev = Math.max(1, ...months.map((m) => Number(m.rev) || 0));
  const rows = months.map((m) => {
    const now = m.m === data.this_m;
    return '<div class="sl-row' + (now ? ' now' : '') + '">'
      + '<span class="sl-m">' + esc(m.m.slice(2).replace('-', '.')) + '</span>'
      + '<span class="sl-n">' + m.n + '건</span>'
      + '<span class="sl-bwrap"><i class="sl-b" style="width:' + Math.round((m.rev / maxRev) * 100) + '%"></i>'
      + '<b class="sl-rev">' + manwon(m.rev) + '</b></span>'
      + '<span class="sl-al">' + (m.album ? '-' + manwon(m.album) : '') + '</span>'
      + '<span class="sl-pf' + (m.profit < 0 ? ' minus' : '') + '">' + manwon(m.profit) + '</span>'
      + '<span class="sl-un">' + (m.unassigned ? '<em>미배정 ' + m.unassigned + '</em>' : '') + '</span>'
      + '</div>';
  }).join('');

  // 해마다 한 줄 (대표 요청 2026-08-24). 매출 크기로 막대를 그린다
  const years = data.years || [];
  const yMax = Math.max(1, ...years.map((x) => Number(x.rev) || 0));
  const yearRows = years.map((x) => {
    const now = Number(x.y) === Number(data.this_y);
    return '<div class="sl-row sl-yrow' + (now ? ' now' : '') + '">'
      + '<span class="sl-m">' + x.y + '년</span>'
      + '<span class="sl-n">' + x.n + '건' + (x.done ? '<i>치른 ' + x.done + '</i>' : '') + '</span>'
      + '<span class="sl-y-rev"><i class="sl-b" style="width:' + Math.round((x.rev / yMax) * 100) + '%"></i>'
      + '<b>' + manwon(x.rev) + '</b></span>'
      + '<span class="sl-y-cost">-' + manwon(x.cost) + '</span>'
      + '<span class="sl-al">' + (x.album ? '-' + manwon(x.album) : '') + '</span>'
      + '<span class="sl-pf' + (x.profit < 0 ? ' minus' : '') + '">' + manwon(x.profit) + '</span>'
      + '</div>';
  }).join('');

  const opts = data.options || [];
  const optMax = Math.max(1, ...opts.map((o) => Number(o.rev) || 0));
  const optRows = opts.map((o) => slBar(esc(o.name), o.n + '건', manwon(o.rev), o.rev / optMax)).join('');
  const disc = (data.discounts || []).map((d) => esc(d.name) + ' ' + d.n + '건 ' + manwon(d.rev)).join(' · ');

  const vens = data.venues || [];
  const venMax = Math.max(1, ...vens.map((v) => Number(v.n) || 0));
  const venRows = vens.length
    // 금액은 뺐다 (대표 요청 2026-08-24) — 여기서 궁금한 건 «어디를 많이 갔나» 라
    // 건수면 충분하고, 금액까지 붙으니 줄이 시끄러웠다
    ? vens.map((v) => slBar(esc(v.venue) + (v.names > 1 ? ' <em class="sl-alias">이름 ' + v.names + '가지</em>' : ''),
        '', v.n + '건', v.n / venMax)).join('')
    : '<p class="empty sm">아직 기록이 없습니다.</p>';

  const L = data.lead || {};
  const bMax = Math.max(1, ...((L.buckets || []).map((b) => Number(b.n) || 0)));
  const lead = L.n
    ? '<div class="sl-lead"><strong>' + L.median + '일 전</strong>'
      + '<span>약 ' + (Math.round((L.median / 30) * 10) / 10) + '개월 · 가운뎃값 · ' + L.n + '건 기준</span></div>'
      + (L.buckets || []).map((b) => slBar(esc(b.k), '', b.n + '건', b.n / bMax)).join('')
      + '<p class="st-note">가장 빠른 건 ' + L.min + '일 전, 가장 이른 건 ' + L.max + '일 전에 잡혔습니다. '
      + '데이터 이전으로 하루에 몰려 들어온 건은 접수일이 진짜가 아니라 뺐습니다.</p>'
    : '<p class="empty sm">아직 셀 만큼 쌓이지 않았습니다.</p>';

  const fn = data.funnel || [];
  const funnel = fn.length
    ? fn.map((f) => '<div class="sl-fn"><span class="sl-fm">' + esc(String(f.m).replace('-', '.')) + '</span>'
        + '<span class="sl-fv">방문 ' + stNum(f.visits) + '</span><span class="sl-fa">→</span>'
        + '<span class="sl-fv">예약 ' + stNum(f.bk) + '</span>'
        + '<b class="sl-fp">' + (f.pct == null ? '-' : f.pct + '%') + '</b></div>').join('')
      + '<p class="st-note">방문 기록은 2026년 8월부터 쌓기 시작했습니다. 달이 몇 번 더 지나야 오르내림이 보입니다. '
      + '카톡·전화로 바로 오신 분은 방문에 안 잡혀 실제 전환은 이보다 낮습니다.</p>'
    : '<p class="empty sm">아직 방문 기록이 없습니다.</p>';

  wrap.innerHTML =
    '<div class="st-cards">'
    + card(y.y + '년 예식', stNum(y.n) + '건', '치른 ' + stNum(y.done) + ' · 남은 ' + stNum(left))
    + card('매출', manwon(y.rev), '예식일 기준 총액')
    + card('순이익', manwon(y.profit), rate == null ? '' : '매출의 ' + rate + '% · 앨범까지 뺀 값')
    + card('한 건 평균', manwon(y.avg), '옵션까지 넣은 값')
    + '</div>'

    // 해마다 — 매출은 예식일, 앨범은 발주일 기준이라 달로 보면 어긋나지만 해로 보면 상쇄된다
    + '<div class="dash-card st-chart-card"><div class="dash-card-head"><h3>🗓 해마다</h3></div>'
    + (years.length
      ? '<div class="sl-head sl-yh"><span>해</span><span class="sl-n">예식</span>'
        + '<span class="sl-y-rev">매출</span><span class="sl-y-cost">작가비</span>'
        + '<span class="sl-al">앨범</span><span class="sl-pf">순이익</span></div>'
        + '<div class="sl-list">' + yearRows + '</div>'
        + '<p class="st-note">달로 보면 매출(예식일)과 앨범값(발주일)의 때가 어긋나 이상해 보이는 달이 생깁니다. '
        + '해로 묶으면 서로 상쇄되니 <b>이 줄이 제일 정확합니다.</b></p>'
      : '<p class="empty sm">아직 없습니다.</p>')
    + '</div>'

    + '<div class="dash-card st-chart-card"><div class="dash-card-head"><h3>📅 달마다 <small>(예식일 기준)</small></h3>'
    + '<span class="st-range sl-span">'
    + ['now', '1y', 'all'].map((k) => '<button class="btn-sm' + (salesSpan === k ? ' active' : '')
        + '" data-span="' + k + '">' + SPAN_LABEL[k] + '</button>').join('')
    + '</span></div>'
    + '<div class="sl-head"><span class="sl-m">달</span><span class="sl-n">예식</span>'
    + '<span class="sl-bwrap">매출</span><span class="sl-al">앨범</span>'
    + '<span class="sl-pf">순이익</span><span class="sl-un"></span></div>'
    + '<div class="sl-list">' + (rows || '<p class="empty sm">예식이 없습니다.</p>') + '</div>'
    + '<p class="st-note">작가비 ' + c.staff + '만 · 경기 출장 +' + c.travel + '만 · 2인 촬영 +' + c.sub + '만, '
    + esc(c.rep || '대표') + ' 작가님이 찍은 건은 전액 이익으로 잡습니다. '
    + '아직 작가가 안 정해진 건도 ' + c.staff + '만 나가는 것으로 미리 빼둡니다(보수적으로).<br>'
    + '<b>앨범값은 그 달에 넣은 발주액을 뺍니다.</b> 신부가 셀렉을 보내야 작업이 들어가서 '
    + '예식한 달과 앨범값 나가는 달이 다릅니다. 그래서 달 하나만 보면 어긋나 보일 수 있습니다 — '
    + '<b>1년 단위로 보시는 게 제일 정확합니다.</b></p></div>'

    + '<div class="dash-cards st-two">'
    + '<div class="dash-card"><div class="dash-card-head"><h3>🎁 옵션 <small>(매출의 ' + (data.opt_pct == null ? '-' : data.opt_pct + '%') + ')</small></h3></div>'
    + (optRows || '<p class="empty sm">아직 기록이 없습니다.</p>')
    + (disc ? '<p class="st-note">할인으로 나간 것 — ' + disc + '</p>' : '') + '</div>'
    + '<div class="dash-card"><div class="dash-card-head"><h3>🏛 많이 간 예식장</h3></div>'
    + venRows
    + '<p class="st-note">같은 곳인데 이름을 달리 적은 것(홀 이름·앞뒤 순서)은 하나로 묶었습니다.</p></div>'
    + '</div>'

    + '<div class="dash-cards st-two">'
    + '<div class="dash-card"><div class="dash-card-head"><h3>⏳ 언제 예약하나</h3></div>' + lead + '</div>'
    + '<div class="dash-card"><div class="dash-card-head"><h3>🔄 방문 → 예약</h3></div>' + funnel + '</div>'
    + '</div>';

  // 달마다 표에 보여줄 기간 고르기
  wrap.querySelectorAll('.sl-span button').forEach((b) => b.addEventListener('click', () => {
    if (salesSpan === b.dataset.span) return;
    salesSpan = b.dataset.span;
    renderSales();
  }));
}

/* 통계 안의 세 칸. 순서는 admin.html 의 단추 차례가 정한다 —
   대표가 순서를 바꿔달라고 할 때 화면만 고치면 되게 (2026-08-25).
   맨 앞 칸이 곧 «기본으로 열리는 칸» 이고, 그 칸만 주소가 짧다(#stats). */
const stFirst = () => {
  const b = document.querySelector('.st-tg[data-sttab]');
  return b ? b.dataset.sttab : 'feedback';
};
let stCur = '';                     // 아직 아무 칸도 안 열었다는 뜻
function stSub(sub) {
  const box = $('stToggle');
  if (!box) return;
  const btns = [].slice.call(box.querySelectorAll('button[data-sttab]'));
  let i = 0;
  btns.forEach((x, k) => { if (x.dataset.sttab === sub) i = k; });
  const cur = btns[i] ? btns[i].dataset.sttab : 'sales';
  stCur = cur;
  btns.forEach((x, k) => x.classList.toggle('active', k === i));
  box.style.setProperty('--st-i', i);                 // 표시등을 그 칸으로 밀어줌
  $('salesBody').hidden = cur !== 'sales';
  $('statsBody').hidden = cur !== 'visits';
  $('fbBody').hidden = cur !== 'feedback';
  const bar = document.querySelector('.st-bar');
  if (bar) bar.hidden = cur !== 'visits';             // 기간 버튼·바로가기는 방문 통계 전용
  setHash(cur === stFirst() ? 'stats' : 'stats/' + cur);
  if (cur === 'sales') renderSales();
  if (cur === 'visits') renderStats();
  if (cur === 'feedback') renderFeedback();
}
const stToggle = $('stToggle');
if (stToggle) {
  stToggle.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-sttab]');
    if (b) stSub(b.dataset.sttab);
  });
}

/* ===== 앨범 발주 (대표 요청 2026-08-24) =====
   쓰시던 「발주 내역 관리」를 관리자 안으로 옮긴 것.
   예약(bookings)과는 잇지 않는다 — 신부가 셀렉을 보내야 작업이 들어가서 예식과 시점이
   제각각이고(24년 촬영이 지금 들어오기도 한다), 억지로 이으면 오히려 틀린다.
   여기서 넣은 금액은 「예약·매출」의 그 달 비용으로 빠진다. */
const abWon = (n) => Number(n || 0).toLocaleString('ko-KR') + '원';
const abYmd = (d) => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0')
  + '-' + String(d.getDate()).padStart(2, '0');
const abThisMonth = () => abYmd(new Date()).slice(0, 7);

let abPrices = [];          // 살아 있는 단가 목록
let abPick = {};            // 새 발주에서 고른 것 { 단가id: 수량 }
let abExtra = [];           // 기타 항목 [{ name, unit, qty }]
let abEditId = null;        // 고치는 중이면 그 발주 id
let abListMonth = 'all';    // 내역에서 고른 달
let abStatMonth = null;     // 통계에서 보는 달 (없으면 이번 달)
let abPaid = 'all';
let abQ = '';
let abLoaded = false;

async function renderAlbum() {
  if (!$('abList')) return;
  if (!abLoaded) $('abList').innerHTML = '<p class="empty">불러오는 중…</p>';
  if (!$('abDate').value) $('abDate').value = abYmd(new Date());
  const pr = await sb.rpc('admin_album_prices');
  if (pr.error) { $('abList').innerHTML = '<p class="empty">불러오지 못했습니다. (' + esc(pr.error.message) + ')</p>'; return; }
  abPrices = Array.isArray(pr.data) ? pr.data : [];
  abLoaded = true;
  abRenderGrid();
  await Promise.all([abRenderList(), abRenderStats()]);
}

/* ── 새 발주 ── */
function abRenderGrid() {
  const box = $('abGrid');
  if (!box) return;
  box.innerHTML = abPrices.filter((p) => String(p.name || '').trim()).map((p) => {
    if (p.type === 'check') {
      const on = abPick[p.id] > 0;
      return '<button type="button" class="ab-item' + (on ? ' on' : '') + '" data-ck="' + esc(p.id) + '">'
        + '<span class="ab-nm">' + esc(p.name) + '</span>'
        + '<span class="ab-un">' + abWon(p.unit) + '</span></button>';
    }
    // 수량 칸을 단가와 같은 줄에 둔다 (대표 요청 2026-08-26 «수량 넣는 칸 올려줘
    // 그래서 박스크기 전부 동일하게»). 따로 한 줄을 쓰면 이 카드만 키가 커진다
    return '<div class="ab-item qty' + (abPick[p.id] > 0 ? ' on' : '') + '">'
      + '<span class="ab-nm">' + esc(p.name) + '</span>'
      + '<span class="ab-un">' + abWon(p.unit) + ' ×'
      + '<input type="number" min="0" step="1" class="ab-q" data-qt="' + esc(p.id) + '" value="'
      + (abPick[p.id] || '') + '" placeholder="0" /></span></div>';
  }).join('') || '<p class="empty sm">단가 항목이 없습니다. 아래 「단가 설정」에서 넣어주세요.</p>';
  abRenderExtras();
  abSum();
}

function abRenderExtras() {
  const box = $('abExtras');
  if (!box) return;
  box.innerHTML = abExtra.map((x, i) => '<div class="ab-ex" data-ex="' + i + '">'
    + '<input type="text" class="ab-ex-n" placeholder="항목 이름" value="' + esc(x.name || '') + '" />'
    + '<input type="number" class="ab-ex-u" min="0" placeholder="단가" value="' + (x.unit || '') + '" />'
    + '<span class="ab-ex-x">×</span>'
    + '<input type="number" class="ab-ex-q" min="1" placeholder="수량" value="' + (x.qty || '') + '" />'
    + '<span class="ab-ex-s">' + abWon((x.unit || 0) * (x.qty || 0)) + '</span>'
    + '<button type="button" class="ab-ex-del" data-exdel="' + i + '">✕</button></div>').join('');
}

function abSum() {
  let t = 0;
  abPrices.forEach((p) => { const q = Number(abPick[p.id]) || 0; if (q > 0) t += p.unit * q; });
  abExtra.forEach((x) => { t += (Number(x.unit) || 0) * (Number(x.qty) || 0); });
  if ($('abNewSum')) $('abNewSum').textContent = abWon(t);
  if ($('abSave')) $('abSave').textContent = abEditId ? '고쳐 저장' : '발주 저장';
  return t;
}

function abClear() {
  abPick = {}; abExtra = []; abEditId = null;
  if ($('abCust')) $('abCust').value = '';
  if ($('abDate')) $('abDate').value = abYmd(new Date());
  abRenderGrid();
}

async function abSave() {
  const cust = ($('abCust').value || '').trim();
  const date = $('abDate').value;
  if (!cust) { toast('고객 이름을 적어주세요.'); $('abCust').focus(); return; }
  if (!date) { toast('발주 날짜를 골라주세요.'); return; }
  const lines = [];
  abPrices.forEach((p) => {
    const q = Number(abPick[p.id]) || 0;
    if (q > 0) lines.push({ kind: 'item', price_item_id: p.id, qty: p.type === 'check' ? 1 : q });
  });
  abExtra.forEach((x) => {
    const q = Number(x.qty) || 0;
    if (q > 0) lines.push({ kind: 'extra', name: (x.name || '').trim() || '기타', unit: Number(x.unit) || 0, qty: q });
  });
  if (!lines.length) { toast('상품을 하나 이상 고르세요.'); return; }

  $('abSave').disabled = true;
  const { data, error } = await sb.rpc('admin_album_order_save',
    { p_id: abEditId, p_customer: cust, p_date: date, p_lines: lines });
  $('abSave').disabled = false;
  if (error) { toast('저장하지 못했습니다. ' + error.message); return; }
  toast((abEditId ? '고쳤습니다. ' : '넣었습니다. ') + abWon(data && data.total));
  abClear();
  await Promise.all([abRenderList(), abRenderStats()]);
  renderHomeStats(true);          // 순이익이 바뀌었으니 홈 숫자도 새로
  salesLoaded = false;
}

/* ── 내역 ── */
function abLineText(lines) {
  return (lines || []).map((l) => (l.kind === 'extra' ? esc(l.name) + '×' + l.qty
    : l.item_type === 'check' ? esc(l.name) : esc(l.name) + ' ' + l.qty)).join(' · ');
}

async function abRenderList() {
  const box = $('abList');
  if (!box) return;
  const { data, error } = await sb.rpc('admin_album_orders',
    { p_month: abListMonth, p_paid: abPaid, p_q: abQ || null, p_limit: 400 });
  if (error || !data) { box.innerHTML = '<p class="empty">불러오지 못했습니다.</p>'; return; }

  // 달 탭 — 올해는 달마다, 지난 해는 해로 묶는다
  const ms = data.months || [];
  const thisY = String(new Date().getFullYear());
  const years = [];
  ms.forEach((m) => { const y = m.slice(0, 4); if (y !== thisY && years.indexOf(y) < 0) years.push(y); });
  const tab = (v, label) => '<button class="ab-tab' + (abListMonth === v ? ' active' : '') + '" data-abm="'
    + esc(v) + '">' + esc(label) + '</button>';
  $('abMonths').innerHTML = tab('all', '전체')
    + ms.filter((m) => m.slice(0, 4) === thisY)
        .map((m) => tab(m, m.slice(5) + '월' + (m === abThisMonth() ? ' (이번 달)' : ''))).join('')
    + years.map((y) => tab(y, y + '년')).join('');

  $('abListSum').textContent = data.count + '건 · ' + abWon(data.total);
  const items = data.items || [];
  box.innerHTML = items.length ? items.map((x) => '<div class="ab-row' + (x.paid ? '' : ' unpaid') + '" data-ab="' + esc(x.id) + '">'
    + '<span class="ab-d">' + esc(String(x.order_date).slice(2).replace(/-/g, '.')) + '</span>'
    + '<span class="ab-c">' + esc(x.customer) + '</span>'
    + '<span class="ab-i">' + abLineText(x.lines) + '</span>'
    + '<span class="ab-t">' + abWon(x.total) + '</span>'
    + '<label class="ab-p"><input type="checkbox" data-abpaid="' + esc(x.id) + '"' + (x.paid ? ' checked' : '') + ' />'
    + '<span>' + (x.paid ? '완료' : '미결제') + '</span></label>'
    + '<span class="ab-b"><button class="btn-sm" data-abedit="' + esc(x.id) + '">수정</button>'
    + '<button class="btn-sm od-cancel" data-abdel="' + esc(x.id) + '">삭제</button></span>'
    + '</div>').join('')
    + (data.shown < data.count ? '<p class="st-note">앞의 ' + data.shown + '건만 보여드립니다. 달로 좁혀 보세요.</p>' : '')
    : '<p class="empty sm">해당하는 발주가 없습니다.</p>';
}

/* ── 통계 ── */
async function abRenderStats() {
  const box = $('abStatCards');
  if (!box) return;
  const { data, error } = await sb.rpc('admin_album_stats', { p_month: abStatMonth });
  if (error || !data) { box.innerHTML = '<p class="empty sm">불러오지 못했습니다.</p>'; return; }
  abStatMonth = data.month;
  const s = data.sum || {};
  $('abStatM').textContent = String(data.month).slice(0, 4) + '년 ' + Number(String(data.month).slice(5)) + '월';
  const card = (k, v, sub, cls) => '<div class="st-card"><span class="st-k">' + k + '</span><strong'
    + (cls ? ' class="' + cls + '"' : '') + '>' + v + '</strong><span class="st-sub">' + (sub || '') + '</span></div>';
  box.innerHTML = card('총매입', abWon(s.total))
    + card('결제완료', abWon(s.paid), '', 'ab-ok')
    + card('미결제', abWon(s.unpaid), '', Number(s.unpaid) > 0 ? 'ab-no' : '')
    + card('건수', (s.count || 0) + '건', (s.people || 0) + '명');

  const bm = data.by_month || [];
  const bmMax = Math.max(1, ...bm.map((x) => Number(x.total) || 0));
  $('abByMonth').innerHTML = bm.length ? bm.map((x) => '<div class="st-row'
    + (x.m === data.month ? ' ab-now' : '') + '" data-abstat="' + esc(x.m) + '">'
    + '<span class="st-row-bar" style="width:' + Math.round((x.total / bmMax) * 100) + '%"></span>'
    + '<span class="st-row-k">' + esc(x.m.replace('-', '.')) + ' <small>' + x.n + '건</small></span>'
    + '<span class="st-row-v">' + abWon(x.total) + '</span></div>').join('')
    : '<p class="empty sm">아직 없습니다.</p>';

  const bi = data.by_item || [];
  const biMax = Math.max(1, ...bi.map((x) => Number(x.total) || 0));
  $('abByItem').innerHTML = bi.length ? bi.map((x) => '<div class="st-row">'
    + '<span class="st-row-bar" style="width:' + Math.round((x.total / biMax) * 100) + '%"></span>'
    + '<span class="st-row-k">' + esc(x.nm) + ' <small>' + x.qty + '개</small></span>'
    + '<span class="st-row-v">' + abWon(x.total) + '</span></div>').join('')
    : '<p class="empty sm">이 달에는 발주가 없습니다.</p>';
}

/* ── 단가 설정 ── */
async function abRenderPrices() {
  const box = $('abPrices');
  if (!box) return;
  const { data, error } = await sb.rpc('admin_album_prices');
  if (error) { box.innerHTML = '<p class="empty sm">불러오지 못했습니다.</p>'; return; }
  abPrices = Array.isArray(data) ? data : [];
  box.innerHTML = abPrices.map((p, i) => '<div class="ab-pr" data-pr="' + esc(p.id) + '">'
    + '<input type="text" class="ab-pr-n" value="' + esc(p.name) + '" />'
    + '<input type="number" class="ab-pr-u" min="0" value="' + p.unit + '" />'
    + '<select class="ab-pr-t"><option value="check"' + (p.type === 'check' ? ' selected' : '') + '>체크</option>'
    + '<option value="qty"' + (p.type === 'qty' ? ' selected' : '') + '>수량</option></select>'
    + '<button class="btn-sm ab-pr-up"' + (i === 0 ? ' disabled' : '') + '>▲</button>'
    + '<button class="btn-sm ab-pr-dn"' + (i === abPrices.length - 1 ? ' disabled' : '') + '>▼</button>'
    + '<button class="btn-sm od-cancel ab-pr-del">삭제</button></div>').join('')
    || '<p class="empty sm">항목이 없습니다.</p>';
  abRenderGrid();
}

/* ── 손가락 ── */
if ($('abGrid')) {
  $('abGrid').addEventListener('click', (e) => {
    const b = e.target.closest('[data-ck]');
    if (!b) return;
    const id = b.dataset.ck;
    abPick[id] = abPick[id] > 0 ? 0 : 1;
    abRenderGrid();
  });
  $('abGrid').addEventListener('input', (e) => {
    const q = e.target.closest('[data-qt]');
    if (!q) return;
    abPick[q.dataset.qt] = Math.max(0, Number(q.value) || 0);
    q.closest('.ab-item').classList.toggle('on', abPick[q.dataset.qt] > 0);
    abSum();
  });
}
if ($('abExtras')) {
  $('abExtras').addEventListener('input', (e) => {
    const row = e.target.closest('[data-ex]');
    if (!row) return;
    const i = Number(row.dataset.ex);
    if (e.target.classList.contains('ab-ex-n')) abExtra[i].name = e.target.value;
    if (e.target.classList.contains('ab-ex-u')) abExtra[i].unit = Number(e.target.value) || 0;
    if (e.target.classList.contains('ab-ex-q')) abExtra[i].qty = Number(e.target.value) || 0;
    row.querySelector('.ab-ex-s').textContent = abWon((abExtra[i].unit || 0) * (abExtra[i].qty || 0));
    abSum();
  });
  $('abExtras').addEventListener('click', (e) => {
    const d = e.target.closest('[data-exdel]');
    if (!d) return;
    abExtra.splice(Number(d.dataset.exdel), 1);
    abRenderExtras(); abSum();
  });
}
if ($('abAddExtra')) $('abAddExtra').addEventListener('click', () => {
  abExtra.push({ name: '', unit: 0, qty: 1 }); abRenderExtras(); abSum();
});
if ($('abReset')) $('abReset').addEventListener('click', abClear);
if ($('abSave')) $('abSave').addEventListener('click', abSave);

if ($('abMonths')) $('abMonths').addEventListener('click', (e) => {
  const b = e.target.closest('[data-abm]');
  if (!b) return;
  abListMonth = b.dataset.abm; abRenderList();
});
document.querySelectorAll('.ab-paid button').forEach((b) => b.addEventListener('click', () => {
  document.querySelectorAll('.ab-paid button').forEach((x) => x.classList.toggle('active', x === b));
  abPaid = b.dataset.paid; abRenderList();
}));
if ($('abQ')) $('abQ').addEventListener('input', () => {
  clearTimeout(abQ._t);
  abQ._t = setTimeout(() => { abQ = $('abQ').value.trim(); abRenderList(); }, 300);
});

if ($('abList')) $('abList').addEventListener('click', async (e) => {
  const pd = e.target.closest('[data-abpaid]');
  if (pd) {
    const r = await sb.rpc('admin_album_order_paid', { p_id: pd.dataset.abpaid, p_paid: pd.checked });
    if (r.error) { pd.checked = !pd.checked; toast('바꾸지 못했습니다.'); return; }
    salesLoaded = false;
    await Promise.all([abRenderList(), abRenderStats()]);
    return;
  }
  const ed = e.target.closest('[data-abedit]');
  if (ed) { abLoadForEdit(ed.dataset.abedit); return; }
  const dl = e.target.closest('[data-abdel]');
  if (dl) {
    const row = dl.closest('.ab-row');
    const who = row ? (row.querySelector('.ab-c') || {}).textContent : '';
    if (!confirm(who + ' 발주를 지울까요? 되돌릴 수 없습니다.')) return;
    const r = await sb.rpc('admin_album_order_del', { p_id: dl.dataset.abdel });
    if (r.error) { toast('지우지 못했습니다.'); return; }
    toast('지웠습니다.');
    salesLoaded = false;
    await Promise.all([abRenderList(), abRenderStats()]);
    renderHomeStats(true);
  }
});

// 고칠 것을 위 폼에 올려둔다. 원본은 지우지 않는다 — 저장하면 그 자리에서 바뀐다
async function abLoadForEdit(id) {
  const { data } = await sb.rpc('admin_album_orders', { p_month: 'all', p_paid: 'all', p_q: null, p_limit: 2000 });
  const o = ((data || {}).items || []).find((x) => x.id === id);
  if (!o) { toast('그 발주를 찾지 못했습니다.'); return; }
  abEditId = id;
  abPick = {}; abExtra = [];
  (o.lines || []).forEach((l) => {
    if (l.kind === 'extra') abExtra.push({ name: l.name, unit: l.unit, qty: l.qty });
    else if (l.price_item_id) abPick[l.price_item_id] = l.qty;
  });
  $('abCust').value = o.customer;
  $('abDate').value = String(o.order_date).slice(0, 10);
  abRenderGrid();
  window.scrollTo({ top: 0, behavior: 'smooth' });
  toast('위에서 고친 뒤 [고쳐 저장]을 누르세요. 결제 여부는 그대로 남습니다.');
}

if ($('abPrev')) $('abPrev').addEventListener('click', () => { abStatMove(-1); });
if ($('abNext')) $('abNext').addEventListener('click', () => { abStatMove(1); });
if ($('abThis')) $('abThis').addEventListener('click', () => { abStatMonth = abThisMonth(); abRenderStats(); });
function abStatMove(d) {
  const [y, m] = String(abStatMonth || abThisMonth()).split('-').map(Number);
  const t = new Date(y, m - 1 + d, 1);
  abStatMonth = t.getFullYear() + '-' + String(t.getMonth() + 1).padStart(2, '0');
  abRenderStats();
}
if ($('abByMonth')) $('abByMonth').addEventListener('click', (e) => {
  const r = e.target.closest('[data-abstat]');
  if (r) { abStatMonth = r.dataset.abstat; abRenderStats(); }
});

if ($('abPriceToggle')) $('abPriceToggle').addEventListener('click', () => {
  const body = $('abPriceBody');
  const open = body.hidden;
  body.hidden = !open;
  $('abPriceToggle').setAttribute('aria-expanded', String(open));
  const caret = $('abPriceToggle').querySelector('.sv-caret');
  if (caret) caret.textContent = open ? '▴' : '▾';
  if (open) abRenderPrices();
});
if ($('abPriceAdd')) $('abPriceAdd').addEventListener('click', async () => {
  const r = await sb.rpc('admin_album_price_save',
    { p_id: null, p_name: '새 항목', p_unit: 0, p_type: 'check', p_active: true });
  if (r.error) { toast('넣지 못했습니다.'); return; }
  await abRenderPrices();
});
if ($('abPrices')) {
  // 고치는 즉시 저장한다 (원본도 그랬다). 너무 자주 부르지 않게 잠깐 기다렸다가
  const save = (row) => {
    clearTimeout(row._t);
    row._t = setTimeout(async () => {
      const r = await sb.rpc('admin_album_price_save', {
        p_id: row.dataset.pr,
        p_name: row.querySelector('.ab-pr-n').value,
        p_unit: Number(row.querySelector('.ab-pr-u').value) || 0,
        p_type: row.querySelector('.ab-pr-t').value,
        p_active: true });
      if (r.error) { toast('저장하지 못했습니다.'); return; }
      abPrices = abPrices.map((p) => (p.id === row.dataset.pr && r.data ? r.data : p));
      abRenderGrid();
      toast('저장했습니다.');
    }, 600);
  };
  $('abPrices').addEventListener('input', (e) => {
    const row = e.target.closest('[data-pr]'); if (row) save(row);
  });
  $('abPrices').addEventListener('change', (e) => {
    const row = e.target.closest('[data-pr]'); if (row) save(row);
  });
  $('abPrices').addEventListener('click', async (e) => {
    const row = e.target.closest('[data-pr]');
    if (!row) return;
    if (e.target.classList.contains('ab-pr-del')) {
      if (!confirm('이 항목을 지울까요? 과거 발주 금액은 그대로 남습니다.')) return;
      const r = await sb.rpc('admin_album_price_off', { p_id: row.dataset.pr });
      if (r.error) { toast('지우지 못했습니다.'); return; }
      toast('지웠습니다.'); await abRenderPrices(); return;
    }
    const up = e.target.classList.contains('ab-pr-up');
    const dn = e.target.classList.contains('ab-pr-dn');
    if (!up && !dn) return;
    const ids = abPrices.map((p) => p.id);
    const i = ids.indexOf(row.dataset.pr);
    const j = up ? i - 1 : i + 1;
    if (i < 0 || j < 0 || j >= ids.length) return;
    ids.splice(j, 0, ids.splice(i, 1)[0]);
    const r = await sb.rpc('admin_album_price_order', { p_ids: ids });
    if (r.error) { toast('순서를 바꾸지 못했습니다.'); return; }
    await abRenderPrices();
  });
}

/* ===== 설정 하위탭 (작가관리 · 상품·가격 · 갤러리) ===== */
let currentSubtab = 'staff';
function showSubtab(st) {
  currentSubtab = st;
  if ($('tab-staff')) $('tab-staff').hidden = st !== 'staff';
  if ($('tab-pricing')) $('tab-pricing').hidden = st !== 'pricing';
  if ($('tab-gallery')) $('tab-gallery').hidden = st !== 'gallery';
  if ($('tab-audit')) $('tab-audit').hidden = st !== 'audit';
  document.querySelectorAll('.sub-tab').forEach((b) => b.classList.toggle('active', b.dataset.subtab === st));
  setHash('settings/' + st);
  if (st === 'staff') renderStaff();
  if (st === 'pricing') renderPricing();
  if (st === 'gallery') loadGallery();
  if (st === 'audit') renderAudit();
}
const dashSubtabs = document.querySelector('.dash-subtabs');
if (dashSubtabs) dashSubtabs.addEventListener('click', (e) => {
  const t = e.target.closest('.sub-tab'); if (!t) return;
  showSubtab(t.dataset.subtab);
});

/* ===== 이벤트 (짝꿍 / 후기) ===== */
async function loadEvents() {
  const buddyList = $('evBuddyList'), reviewList = $('evReviewList');
  buddyList.innerHTML = '<p class="empty">불러오는 중…</p>';
  reviewList.innerHTML = '';
  const { data, error } = await sb.rpc('admin_event_list');
  if (error) { buddyList.innerHTML = `<p class="empty">불러오기 실패: ${esc(error.message)}</p>`; return; }
  renderBuddyList(data.buddies || []);
  renderReviewList(data.reviews || []);
  updateEventBadge(data);
}

// 이벤트는 홈 카드가 됐다 (2026-08-24). 챙길 게 없으면 카드째 접어 둔다.
// 승인된 것·처리 끝난 것 말고 «지금 손댈 게 있나» 만 센다
function updateEventBadge(data) {
  const pend = (data.buddies || []).filter((b) => b.status === 'matched').length
             + (data.reviews || []).filter((r) => r.status === 'pending').length;
  const n = $('dcEvents');
  if (n) n.textContent = pend;
  const card = $('card-events');
  if (card) card.hidden = pend === 0;
}

const EV_REWARD = (r) => (r === '앨범' ? '앨범 1권' : r === '할인' ? '1만원 할인' : (r || '-'));

function renderBuddyList(list) {
  const wrap = $('evBuddyList');
  list = (list || []).filter((b) => b.status !== 'approved'); // 승인된 건 숨김
  if (!list.length) { wrap.innerHTML = '<p class="empty">승인 대기 중인 짝꿍이 없어요.</p>'; return; }
  wrap.innerHTML = list.map((b) => {
    const pending = b.status === 'matched';
    const a = `${esc(b.a_name || '-')} <small>(${esc(fmtDate(b.a_date))})</small>`;
    const p = `${esc(b.b_name || '-')} <small>(${esc(fmtDate(b.b_date))})</small>`;
    return `
    <div class="ev-item${pending ? ' pending' : ''}">
      <div class="ev-main">
        <div class="ev-pair">${a} <span class="ev-amp">↔</span> ${p}</div>
        <div class="ev-meta">혜택 — ${esc(b.a_name || 'A')}: ${esc(EV_REWARD(b.a_reward))} / ${esc(b.b_name || 'B')}: ${esc(EV_REWARD(b.b_reward))}</div>
        <div class="ev-meta">${pending ? '<b class="ev-wait">승인 대기</b>' : '<span class="ev-done">승인 완료 ✓</span>'}</div>
      </div>
      <div class="ev-actions">
        ${pending
          ? `<button class="btn-sm ev-approve" data-kind="buddy" data-id="${b.id}">승인</button>
             <button class="btn-sm od-cancel ev-cancel" data-kind="buddy" data-id="${b.id}">취소</button>`
          : `<button class="btn-sm od-cancel ev-cancel" data-kind="buddy" data-id="${b.id}">취소</button>`}
      </div>
    </div>`;
  }).join('');
  bindEventActions();
}

function renderReviewList(list) {
  const wrap = $('evReviewList');
  list = (list || []).filter((r) => r.status !== 'approved'); // 승인된 건 숨김
  if (!list.length) { wrap.innerHTML = '<p class="empty">승인 대기 중인 후기가 없어요.</p>'; return; }
  wrap.innerHTML = list.map((r) => {
    const pending = r.status === 'pending';
    const st = r.status === 'approved' ? '<span class="ev-done">승인 완료 ✓</span>'
      : r.status === 'rejected' ? '<span class="ev-reject">반려됨</span>'
      : '<b class="ev-wait">승인 대기</b>';
    return `
    <div class="ev-item${pending ? ' pending' : ''}">
      <div class="ev-main">
        <div class="ev-pair">${esc(r.name || '-')}</div>
        <div class="ev-meta"><a href="${esc(r.link)}" target="_blank" rel="noopener" class="ev-link">${esc(r.link)}</a></div>
        <div class="ev-meta">혜택 ${esc(EV_REWARD(r.reward))} · ${st}</div>
      </div>
      <div class="ev-actions">
        ${pending
          ? `<button class="btn-sm ev-approve" data-kind="review" data-id="${r.id}">승인</button>
             <button class="btn-sm od-cancel ev-reject" data-kind="review" data-id="${r.id}">반려</button>`
          : `<button class="btn-sm ev-approve" data-kind="review" data-id="${r.id}">승인</button>`}
      </div>
    </div>`;
  }).join('');
  bindEventActions();
}

function bindEventActions() {
  document.querySelectorAll('#card-events .ev-approve').forEach((btn) =>
    btn.addEventListener('click', () => eventAction(btn.dataset.kind, btn.dataset.id, 'approve')));
  document.querySelectorAll('#card-events .ev-cancel').forEach((btn) =>
    btn.addEventListener('click', () => eventAction(btn.dataset.kind, btn.dataset.id, 'cancel')));
  document.querySelectorAll('#card-events .ev-reject').forEach((btn) =>
    btn.addEventListener('click', () => eventAction(btn.dataset.kind, btn.dataset.id, 'reject')));
}

async function eventAction(kind, id, action) {
  const rpc = kind === 'buddy' ? 'admin_buddy_set' : 'admin_review_set';
  const { error } = await sb.rpc(rpc, { p_id: id, p_action: action });
  if (error) { alert('처리 실패: ' + error.message); return; }
  const labels = { approve: '승인했어요', cancel: '취소했어요', reject: '반려했어요' };
  toast(labels[action] || '처리 완료');
  // 할인(승인된 '할인' 혜택)이 바뀔 수 있으니 갱신 후 대시보드 반영
  const dres = await sb.rpc('admin_event_discounts');
  eventDiscounts = (dres.data && typeof dres.data === 'object') ? dres.data : {};
  loadEvents();
  renderDashboard();
}

let glQueue = []; // [{ file, url }] — 하나씩 누적
const glFiles = $('glFiles');
const glDrop = document.querySelector('.gl-upload');

function renderQueue() {
  const q = $('glQueue');
  if (!q) return;
  q.innerHTML = glQueue
    .map((it, i) => `<div class="gq-item"><img src="${it.url}" alt="" /><button type="button" class="gq-x" data-i="${i}" aria-label="빼기">×</button></div>`)
    .join('');
  q.querySelectorAll('.gq-x').forEach((b) =>
    b.addEventListener('click', () => {
      const i = Number(b.dataset.i);
      URL.revokeObjectURL(glQueue[i].url);
      glQueue.splice(i, 1);
      renderQueue();
    })
  );
  $('glFileLabel').textContent = glQueue.length ? glQueue.length + '장 대기 중 · 더 추가 가능' : '사진 선택 / 드래그앤드롭';
}
function addFiles(files) {
  Array.from(files)
    .filter((f) => f.type.startsWith('image/'))
    .forEach((f) => glQueue.push({ file: f, url: URL.createObjectURL(f) }));
  renderQueue();
}
function clearQueue() {
  glQueue.forEach((it) => URL.revokeObjectURL(it.url));
  glQueue = [];
  renderQueue();
}

if (glFiles) {
  glFiles.addEventListener('change', (e) => { addFiles(e.target.files); e.target.value = ''; });
  $('glUploadBtn').addEventListener('click', uploadGallery);

  if (glDrop) {
    ['dragenter', 'dragover'].forEach((ev) =>
      glDrop.addEventListener(ev, (e) => { e.preventDefault(); glDrop.classList.add('drag'); })
    );
    glDrop.addEventListener('dragleave', (e) => { if (!glDrop.contains(e.relatedTarget)) glDrop.classList.remove('drag'); });
    glDrop.addEventListener('drop', (e) => {
      e.preventDefault();
      glDrop.classList.remove('drag');
      if (e.dataTransfer.files.length) addFiles(e.dataTransfer.files);
    });
  }
}

function setGlStatus(msg, type) {
  const s = $('glStatus');
  s.textContent = msg;
  s.className = 'gl-status' + (type ? ' ' + type : '');
}

// 클라이언트에서 리사이즈 (용량 작게)
function resizeImage(file, maxDim, quality) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      let w = img.width, h = img.height;
      if (w > maxDim || h > maxDim) {
        if (w >= h) { h = Math.round((h * maxDim) / w); w = maxDim; }
        else { w = Math.round((w * maxDim) / h); h = maxDim; }
      }
      const cv = document.createElement('canvas');
      cv.width = w; cv.height = h;
      cv.getContext('2d').drawImage(img, 0, 0, w, h);
      cv.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('이미지 변환 실패'))), 'image/jpeg', quality);
    };
    img.onerror = () => reject(new Error('이미지를 읽을 수 없습니다'));
    img.src = URL.createObjectURL(file);
  });
}

async function uploadGallery() {
  const files = glQueue.map((it) => it.file);
  const venue = $('glVenue').value.trim();
  // 올릴 때 작가도 같이 찍는다 (대표 요청 2026-08-25) — 나중에 손볼 일이 없게
  const upStaff = $('glUpStaff').value || null;
  if (!files.length) { setGlStatus('사진을 선택해 주세요.', 'err'); return; }
  const btn = $('glUploadBtn');
  btn.disabled = true;
  try {
    for (let i = 0; i < files.length; i++) {
      setGlStatus('업로드 중... (' + (i + 1) + '/' + files.length + ')');
      const blob = await resizeImage(files[i], 1400, 0.82);
      const path = Date.now() + '-' + Math.random().toString(36).slice(2, 8) + '.jpg';
      const up = await sb.storage.from('gallery').upload(path, blob, { contentType: 'image/jpeg', upsert: false });
      if (up.error) throw up.error;
      const pub = sb.storage.from('gallery').getPublicUrl(path);
      const add = await sb.rpc('admin_gallery_add', { payload: { image_path: path, image_url: pub.data.publicUrl, venue, staff_id: upStaff } });
      if (add.error) throw add.error;
    }
    const n = files.length;
    clearQueue();
    $('glFiles').value = '';
    $('glVenue').value = '';
    // 작가 고른 것은 안 지운다 — 같은 예식 사진을 이어서 올리는 경우가 많다
    setGlStatus(n + '장 업로드 완료!', 'ok');
    loadGallery();
  } catch (err) {
    setGlStatus('실패: ' + (err.message || err), 'err');
  } finally {
    btn.disabled = false;
  }
}

let glAllItems = [];
let glActiveTag = '전체';
let glSearch = '';
let glTagsOpen = false;
let glPage = 1;
const GL_PER = 20; // 4 x 5

async function loadGallery() {
  const { data, error } = await sb.rpc('gallery_list');
  if (error) { $('glGrid').innerHTML = '<p class="empty">목록 오류: ' + esc(error.message) + '</p>'; return; }
  glAllItems = data || [];
  glActiveTag = '전체';
  glSearch = '';
  glTagsOpen = false;
  glPage = 1;
  glPicked.clear();
  // 올릴 때 고를 작가 목록 (2026-08-25). 고른 것은 다시 그려도 남긴다
  const up = $('glUpStaff');
  if (up) { const keep = up.value; up.innerHTML = glStaffOptions(keep); up.value = keep; }
  renderGalleryAdmin();
}

const glVisible = () => {
  if (glSearch) {
    const t = glSearch.toLowerCase();
    return glAllItems.filter((g) => (g.venue || '').toLowerCase().includes(t));
  }
  if (glActiveTag === '전체') return glAllItems;
  // 아직 작가를 안 찍은 것만 — 689장을 훑을 때 어디까지 했는지 보려고 (2026-08-25)
  if (glActiveTag === '작가 미지정') return glAllItems.filter((g) => !g.staff_id);
  return glAllItems.filter((g) => g.venue === glActiveTag);
};

function renderGalleryAdmin() {
  renderGalleryTags();
  renderGalleryBulk();
  renderGalleryGrid();
}

/* 작가별 촬영 이력 — 몇 건 찍었고 어디를 많이 갔나 (대표 요청 2026-08-25
   «전체 촬영건수도 기록해주고 / 홀별로많이 간 순위 10위까지»).
   우리 예약(2026-06~)과 캘린더에서 읽어 넣은 지난 이력(2018~)을 합친 값이다.
   다른 업체에서 찍은 것은 안 들어간다 — 우리 스케줄로 한 것만 */
let staffShots = null;
async function loadStaffShots() {
  const { data, error } = await sb.rpc('admin_staff_shots', { p_top: 10 });
  if (!error && data) staffShots = data;
}
// 「우리가 많이 간 예식장」은 홈으로 옮겼다 (대표 요청 2026-08-25).
// 통계 안에 카드를 또 만드니 «박스 안에 박스 안에 박스» 가 됐다
function renderHomeVenues() {
  const box = $('homeVenuesBody');
  if (!box) return;
  const list = (staffShots && staffShots.venues) || [];
  if (!list.length) { box.innerHTML = '<p class="empty sm">아직 자료가 없습니다.</p>'; return; }
  const cut = (v) => esc(String(v).replace(/\s*[-/(,].*$/, '').slice(0, 18));
  box.innerHTML = list.map((v, i) =>
    '<span class="vn-item"><i>' + (i + 1) + '</i>' + cut(v.venue) + ' <b>' + v.n + '</b></span>').join('');
}

// 사진마다 「누가 찍었는지」 를 고르는 칸 (대표 요청 2026-08-25 «갤러리도 누구사진인지»).
// 자동으로는 못 붙인다 — 사진에 날짜가 없고, 같은 예식장을 여러 번 갔다
const glStaffOptions = (sel) =>
  '<option value="">작가 미지정</option>'
  + allStaff.map((s) =>
    `<option value="${esc(s.id)}"${s.id === sel ? ' selected' : ''}>${esc(s.name)}${s.active ? '' : ' (비활성)'}</option>`).join('');

// 고른 사진 (체크한 것). 쪽을 넘겨도 남아 있게 화면 바깥에 둔다
const glPicked = new Set();

// 지금 보고 있는 목록을 한꺼번에 찍는다.
// 예식장 이름을 눌렀을 때만이 아니라 **검색만 해도** 뜬다 (대표 요청 2026-08-25).
// 한 예식장에 작가가 섞여 있으면 체크해서 그것만 찍는다
function renderGalleryBulk() {
  const box = $('glBulk');
  const list = glVisible();
  // 전체를 보고 있을 때는 안 뜬다 — 689장을 통째로 찍는 건 사고다.
  // 다만 체크한 게 있으면 그것만 찍을 수 있게 띄운다
  const filtered = !!glSearch || glActiveTag !== '전체';
  const pickedHere = list.filter((g) => glPicked.has(g.id)).length;
  box.hidden = !filtered && !pickedHere;
  if (box.hidden) return;

  const empty = list.filter((g) => !g.staff_id).length;
  const what = glSearch ? '「' + esc(glSearch) + '」 검색' : esc(glActiveTag);
  box.innerHTML =
    '<span class="gl-bulk-t"><b>' + what + '</b> ' + list.length + '장'
      + (empty ? ' · <em>미지정 ' + empty + '장</em>' : ' · 전부 지정됨')
      + (pickedHere ? ' · <b class="gl-picked">체크 ' + pickedHere + '장</b>' : '') + '</span>'
    + '<label class="gl-bulk-over"><input type="checkbox" id="glPickAll"'
      + (pickedHere && pickedHere === list.length ? ' checked' : '') + ' /> 이 목록 전체 체크</label>'
    + '<select id="glBulkStaff">' + glStaffOptions('') + '</select>'
    + (pickedHere
      ? '<button class="btn-sm btn-primary-sm" id="glPickGo">체크한 ' + pickedHere + '장 지정</button>'
      : '')
    + '<label class="gl-bulk-over"><input type="checkbox" id="glBulkOver" /> 이미 찍힌 것도 덮어쓰기</label>'
    + '<button class="btn-sm" id="glBulkGo">이 목록 전부 지정</button>';

  const staffName = () => { const s = $('glBulkStaff'); return s.options[s.selectedIndex].text; };
  const after = (ids, val) => {
    glAllItems.forEach((g) => { if (ids.has(g.id)) g.staff_id = val; });
    renderGalleryAdmin();
  };

  $('glPickAll').addEventListener('change', (e) => {
    list.forEach((g) => (e.target.checked ? glPicked.add(g.id) : glPicked.delete(g.id)));
    renderGalleryAdmin();
  });

  // 체크한 것만 — 한 예식장에 여러 작가가 섞였을 때 쓴다
  const go = $('glPickGo');
  if (go) go.addEventListener('click', async () => {
    const ids = list.filter((g) => glPicked.has(g.id)).map((g) => g.id);
    const val = $('glBulkStaff').value || null;
    if (!confirm('체크한 ' + ids.length + '장을 «' + staffName() + '» 으로 찍을까요?')) return;
    const { data, error } = await sb.rpc('admin_gallery_staff_many', { p_ids: ids, p_staff_id: val });
    if (error) { alert('지정 실패: ' + error.message); return; }
    const set = new Set(ids);
    ids.forEach((id) => glPicked.delete(id));
    toast((data && data.n) + '장 지정했습니다');
    after(set, val);
  });

  // 목록 전부 — 검색 결과에도 쓸 수 있게 id 로 보낸다 (예식장 이름 하나로는 검색을 못 담는다)
  $('glBulkGo').addEventListener('click', async () => {
    const over = $('glBulkOver').checked;
    const target = over ? list : list.filter((g) => !g.staff_id);
    if (!target.length) { toast('바꿀 사진이 없습니다'); return; }
    const val = $('glBulkStaff').value || null;
    if (!confirm(what.replace(/<[^>]+>/g, '') + ' ' + target.length + '장을 «' + staffName() + '» 으로 찍을까요?')) return;
    const ids = target.map((g) => g.id);
    let n = 0;
    for (let i = 0; i < ids.length; i += 500) {          // 서버가 한 번에 500장까지 받는다
      const { data, error } = await sb.rpc('admin_gallery_staff_many',
        { p_ids: ids.slice(i, i + 500), p_staff_id: val });
      if (error) { alert('지정 실패: ' + error.message); return; }
      n += (data && data.n) || 0;
    }
    toast(n + '장 지정했습니다');
    after(new Set(ids), val);
  });
}

// 태그: 사진 많은 순 + 검색 + 한 줄 접기(더보기)
function renderGalleryTags() {
  $('glEmpty').hidden = glAllItems.length > 0;
  const counts = {};
  glAllItems.forEach((g) => { if (g.venue) counts[g.venue] = (counts[g.venue] || 0) + 1; });
  const venues = Object.keys(counts).sort((a, b) => counts[b] - counts[a]);

  // 작가를 아직 안 찍은 것 — 남은 일이 얼마나인지 보여준다 (2026-08-25)
  const noStaff = glAllItems.filter((g) => !g.staff_id).length;
  const top = `<div class="gl-tags-top">
      <button class="gl-tag${glActiveTag === '전체' && !glSearch ? ' active' : ''}" data-v="전체">전체 ${glAllItems.length}</button>
      ${noStaff ? `<button class="gl-tag gl-tag-todo${glActiveTag === '작가 미지정' && !glSearch ? ' active' : ''}" data-v="작가 미지정">작가 미지정 ${noStaff}</button>` : ''}
      <span class="gl-tag-search"><input id="glTagSearch" type="text" placeholder="예식장 검색" autocomplete="off" value="${esc(glSearch)}" /></span>
      ${venues.length ? `<button type="button" class="gl-more" id="glMore">${glTagsOpen ? '접기 ▴' : '더보기 ▾'}</button>` : ''}
    </div>`;
  const wrap = `<div class="gl-tagwrap${glTagsOpen ? ' open' : ''}" id="glTagWrap">` +
    venues.map((v) => `<button class="gl-tag${v === glActiveTag && !glSearch ? ' active' : ''}" data-v="${esc(v)}">${esc(v)} ${counts[v]}</button>`).join('') +
    `</div>`;
  $('glTags').innerHTML = top + wrap;

  const si = $('glTagSearch');
  si.addEventListener('input', () => {
    glSearch = si.value.trim();
    glActiveTag = '전체';
    glPage = 1;
    $('glTags').querySelectorAll('.gl-tag').forEach((b) => b.classList.remove('active'));
    renderGalleryGrid();
  });
  const more = $('glMore');
  if (more) more.addEventListener('click', () => {
    glTagsOpen = !glTagsOpen;
    $('glTagWrap').classList.toggle('open', glTagsOpen);
    more.textContent = glTagsOpen ? '접기 ▴' : '더보기 ▾';
  });
  $('glTags').querySelectorAll('#glTagWrap .gl-tag, .gl-tags-top .gl-tag').forEach((b) =>
    b.addEventListener('click', () => { glActiveTag = b.dataset.v; glSearch = ''; glPage = 1; renderGalleryAdmin(); })
  );
}

const imgThumb = (url, w) =>
  url && url.includes('/object/public/')
    ? url.replace('/object/public/', '/render/image/public/') + `?width=${w}&quality=82`
    : url;

function renderGalleryGrid() {
  // 그리드 (페이지네이션 20장)
  const list = glVisible();
  const start = (glPage - 1) * GL_PER;
  const grid = $('glGrid');
  grid.innerHTML = list
    .slice(start, start + GL_PER)
    .map((g) => `<div class="gl-item${glPicked.has(g.id) ? ' picked' : ''}"><label class="gl-pick"><input type="checkbox" class="gl-pick-cb" data-id="${esc(g.id)}"${glPicked.has(g.id) ? ' checked' : ''} /></label><img src="${esc(imgThumb(g.image_url, 400))}" alt="" loading="lazy" decoding="async" /><div class="gl-meta"><input class="gl-venue-edit" data-id="${esc(g.id)}" value="${esc(g.venue || '')}" placeholder="장소 태그" /><button class="gl-del" data-id="${esc(g.id)}" data-path="${esc(g.image_path)}">삭제</button></div><select class="gl-staff${g.staff_id ? '' : ' none'}" data-id="${esc(g.id)}">${glStaffOptions(g.staff_id)}</select></div>`)
    .join('');
  // 체크 — 여러 장 골라서 한 작가로 찍을 때 쓴다 (대표 요청 2026-08-25)
  grid.querySelectorAll('.gl-pick-cb').forEach((cb) => {
    cb.addEventListener('change', () => {
      if (cb.checked) glPicked.add(cb.dataset.id); else glPicked.delete(cb.dataset.id);
      cb.closest('.gl-item').classList.toggle('picked', cb.checked);
      renderGalleryBulk();          // 「체크 N장」 만 다시 그린다 (사진은 그대로 둔다)
    });
  });
  // 사진마다 작가 고르기 — 고르는 즉시 저장한다
  grid.querySelectorAll('.gl-staff').forEach((sel) => {
    sel.addEventListener('change', async () => {
      const { error } = await sb.rpc('admin_gallery_staff', {
        p_id: sel.dataset.id, p_staff_id: sel.value || null,
      });
      if (error) { alert('작가 지정 실패: ' + error.message); return; }
      const it = glAllItems.find((x) => x.id === sel.dataset.id);
      if (it) it.staff_id = sel.value || null;
      sel.classList.toggle('none', !sel.value);
      renderGalleryBulk();
      if (glActiveTag === '작가 미지정') renderGalleryAdmin();   // 지정하면 이 목록에서 빠진다
    });
  });
  grid.querySelectorAll('.gl-del').forEach((b) =>
    b.addEventListener('click', () => deleteGalleryItem(b.dataset.id, b.dataset.path))
  );
  grid.querySelectorAll('.gl-venue-edit').forEach((inp) => {
    let orig = inp.value;
    const save = async () => {
      const val = inp.value.trim();
      if (val === orig) return;
      const { error } = await sb.rpc('admin_gallery_update', { p_id: inp.dataset.id, p_venue: val });
      if (error) { alert('태그 수정 실패: ' + error.message); inp.value = orig; return; }
      orig = val;
      const it = glAllItems.find((x) => x.id === inp.dataset.id);
      if (it) it.venue = val || null;
      renderGalleryAdmin();
    };
    inp.addEventListener('blur', save);
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
  });

  // 페이저
  const pages = Math.ceil(list.length / GL_PER);
  const pg = $('glPager');
  if (pages <= 1) { pg.innerHTML = ''; return; }
  // 페이지 번호 10개씩 블록으로 끊어 표시 (화면 넘침 방지)
  const WIN = 10;
  const block = Math.floor((glPage - 1) / WIN);
  const from = block * WIN + 1;
  const to = Math.min(from + WIN - 1, pages);
  let html = `<button class="gpg nav" data-p="${glPage - 1}"${glPage === 1 ? ' disabled' : ''}>‹</button>`;
  if (from > 1) html += `<button class="gpg" data-p="${from - 1}">…</button>`;
  for (let i = from; i <= to; i++) html += `<button class="gpg${i === glPage ? ' active' : ''}" data-p="${i}">${i}</button>`;
  if (to < pages) html += `<button class="gpg" data-p="${to + 1}">…</button>`;
  html += `<button class="gpg nav" data-p="${glPage + 1}"${glPage === pages ? ' disabled' : ''}>›</button>`;
  pg.innerHTML = html;
  pg.querySelectorAll('.gpg').forEach((b) =>
    b.addEventListener('click', () => { if (b.disabled) return; glPage = Number(b.dataset.p); renderGalleryGrid(); $('glTags').scrollIntoView({ behavior: 'smooth', block: 'start' }); })
  );
}

async function deleteGalleryItem(id, path) {
  if (!confirm('이 사진을 삭제할까요?')) return;
  const { error } = await sb.rpc('admin_gallery_delete', { p_id: id });
  if (error) { alert('삭제 실패: ' + error.message); return; }
  if (path) await sb.storage.from('gallery').remove([path]);
  glAllItems = glAllItems.filter((g) => g.id !== id);
  // 현재 페이지가 비면 이전 페이지로
  const pages = Math.max(1, Math.ceil(glVisible().length / GL_PER));
  if (glPage > pages) glPage = pages;
  renderGalleryAdmin();
}

/* ===== 웹 푸시 알림 (신규 예약) ===== */
const VAPID_PUBLIC = 'BBKafqxDWhKLbQCm7VRSkiFA0NwBy7DrlXFju432bq5KMS8v5XRKBFJC4HmKEtf3WZdQsz7xqQ-3RbVkVBJw1QM';
function urlB64ToUint8(b64) {
  const pad = '='.repeat((4 - (b64.length % 4)) % 4);
  const base = (b64 + pad).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base); const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
  return arr;
}
let swReg = null;
async function initPush() {
  const btn = document.getElementById('notifyBtn');
  if (!btn) return;
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return; // 미지원
  try {
    swReg = await navigator.serviceWorker.register('sw.js', { scope: '/' });
    await navigator.serviceWorker.ready;
  } catch (e) { console.warn('SW 등록 실패', e); return; }
  let sub = await swReg.pushManager.getSubscription();
  // 기존 구독이 현재 VAPID 키와 다르면 해지(키 교체 대응) → 새로 구독 유도
  if (sub) {
    const cur = urlB64ToUint8(VAPID_PUBLIC);
    const old = new Uint8Array(sub.options && sub.options.applicationServerKey ? sub.options.applicationServerKey : []);
    const same = old.length === cur.length && old.every((v, i) => v === cur[i]);
    if (!same) { try { await sub.unsubscribe(); } catch (_) {} sub = null; }
  }
  if (sub && Notification.permission === 'granted') { await saveSub(sub); return; } // 이미 구독됨(키 일치)
  btn.hidden = false;
  btn.addEventListener('click', enablePush);
}
async function enablePush() {
  const btn = document.getElementById('notifyBtn');
  try {
    const perm = await Notification.requestPermission();
    if (perm !== 'granted') { alert('알림이 거부됐어요. 브라우저/홈화면 앱 설정에서 알림을 허용해 주세요.'); return; }
    const sub = await swReg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlB64ToUint8(VAPID_PUBLIC) });
    await saveSub(sub);
    btn.textContent = '🔔 알림 켜짐 ✓';
    setTimeout(() => { btn.hidden = true; }, 1500);
    toast('신규 예약 알림이 켜졌어요.');
  } catch (e) {
    console.error(e);
    alert('알림 켜기에 실패했어요. 아이폰은 먼저 이 페이지를 홈 화면에 추가한 뒤, 그 앱에서 켜야 해요.');
  }
}
async function saveSub(sub) {
  const j = sub.toJSON();
  await sb.rpc('save_push_subscription', {
    p_endpoint: j.endpoint,
    p_p256dh: j.keys && j.keys.p256dh,
    p_auth: j.keys && j.keys.auth,
  });
}

/* ===== 모바일 당겨서 새로고침 (pull-to-refresh, 스피너) ===== */
(function () {
  if (!('ontouchstart' in window)) return; // 터치 기기에서만
  // 브라우저 기본 당김새로고침 끄고 직접 처리 (홈화면 앱에선 기본 동작이 없어서 직접 구현 필요)
  try { document.documentElement.style.overscrollBehaviorY = 'contain'; document.body.style.overscrollBehaviorY = 'contain'; } catch (_) {}
  const st = document.createElement('style');
  st.textContent = '@keyframes otbSpin{to{transform:rotate(360deg)}}';
  document.head.appendChild(st);
  const ind = document.createElement('div');
  ind.style.cssText = 'position:fixed;top:0;left:0;right:0;display:flex;justify-content:center;align-items:flex-end;height:0;overflow:hidden;z-index:99999;transition:height .15s ease;pointer-events:none;padding-bottom:8px';
  const sp = document.createElement('div');
  sp.style.cssText = 'width:24px;height:24px;border:3px solid rgba(138,122,82,.25);border-top-color:#8a7a52;border-radius:50%;opacity:0';
  ind.appendChild(sp);
  document.body.appendChild(ind);
  const TH = 70;
  let startY = 0, pulling = false, h = 0;
  const atTop = () => (document.scrollingElement || document.documentElement).scrollTop <= 0;
  const modalOpen = () => { const m = document.getElementById('modal'); return m && !m.hidden; };
  window.addEventListener('touchstart', (e) => {
    pulling = e.touches.length === 1 && atTop() && !modalOpen();
    if (pulling) { startY = e.touches[0].clientY; h = 0; sp.style.animation = ''; }
  }, { passive: true });
  window.addEventListener('touchmove', (e) => {
    if (!pulling) return;
    const d = e.touches[0].clientY - startY;
    if (d > 0 && atTop()) {
      h = Math.min(d * 0.5, 90);
      ind.style.height = h + 'px';
      sp.style.opacity = Math.min(h / TH, 1);
      sp.style.transform = 'rotate(' + Math.round(d * 2) + 'deg)';
    } else { pulling = false; ind.style.height = '0px'; h = 0; }
  }, { passive: true });
  window.addEventListener('touchend', () => {
    if (!pulling) return;
    pulling = false;
    if (h >= TH) {
      sp.style.transform = ''; sp.style.opacity = '1';
      sp.style.animation = 'otbSpin .6s linear infinite';
      ind.style.height = '46px';
      setTimeout(() => location.reload(), 350);
    } else { ind.style.height = '0px'; }
    h = 0;
  });
})();
