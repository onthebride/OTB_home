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
let calMonth = null; // 캘린더 현재 월 {y, m}
let dayOvKey = null; // 캘린더 날짜 팝업 열린 날 {y, m, d}
let unpaidTab = 'deposit'; // 미입금 탭: deposit | balance
let allStaff = [];
let staffMap = {};
const ATK_TPLS = [['A', '계약안내'], ['B', '한달 전'], ['C', '잔금안내'], ['D', '최종안내'], ['E', '링크안내'], ['F', '입금확인']];
const notCancelled = (b) => b.status !== '취소';
const phBadge = (b) =>
  (b.rep_designation ? ' <span class="ph-badge rep">대표지정</span>' : '')
  + (b.photographer === '2인 촬영' ? ' <span class="ph-badge two">2인촬영</span>' : '');
const STAFF_COLORS = ['#b08d57', '#6b8e9b', '#9b6b8e', '#7d9b6b', '#9b7d6b', '#6b6b9b', '#b5727a', '#5fa3a3', '#a38b5f', '#8a6ba3'];
function staffColor(id) {
  if (!id) return null;
  let h = 0;
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
const SAVED_PW_KEY = 'otb_admin_pw';
const showLogin = () => {
  $('loginView').hidden = false;
  $('dashView').hidden = true;
  // 저장된 아이디/비밀번호 자동 입력 ('저장' 체크돼 있었으면)
  let savedEmail = '', savedPw = '';
  try {
    savedEmail = localStorage.getItem(SAVED_EMAIL_KEY) || '';
    savedPw = localStorage.getItem(SAVED_PW_KEY) || '';
  } catch {}
  if (savedEmail) $('email').value = savedEmail;
  if (savedPw) { try { $('password').value = decodeURIComponent(atob(savedPw)); } catch (_) {} }
  if ($('saveCreds')) $('saveCreds').checked = !!(savedEmail && savedPw);
  // 아이디만 저장됐으면 비번 칸으로 포커스
  const pw = $('password');
  if (savedEmail && !savedPw && pw) setTimeout(() => pw.focus(), 0);
};
const showDash = (email) => {
  $('loginView').hidden = true;
  $('dashView').hidden = false;
  $('dashUser').textContent = email || '';
  loadBookings();
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
    // 로그인 성공 시: '저장' 체크 ON이면 아이디·비밀번호 저장, OFF면 삭제
    try {
      if ($('saveCreds') && $('saveCreds').checked) {
        localStorage.setItem(SAVED_EMAIL_KEY, email);
        localStorage.setItem(SAVED_PW_KEY, btoa(encodeURIComponent($('password').value)));
      } else {
        localStorage.removeItem(SAVED_EMAIL_KEY);
        localStorage.removeItem(SAVED_PW_KEY);
      }
    } catch (_) {}
  }
});

$('logoutBtn').addEventListener('click', () => sb.auth.signOut());
$('refreshBtn').addEventListener('click', () => loadBookings());

/* ===== Load + render ===== */
async function loadBookings() {
  // 모든 조회는 서로 독립적이라 한 번에 병렬로 — 순차 대기 제거(체감 속도 개선)
  const [res, sres, ures, dres, fres] = await Promise.all([
    sb.rpc('admin_list_bookings'),    // 예약 목록
    sb.rpc('admin_survey_ids'),       // 설문 제출 여부
    sb.rpc('admin_unconfirmed'),      // 작가 미확인
    sb.rpc('admin_event_discounts'),  // 이벤트 할인
    sb.rpc('admin_alimtalk_log'),     // 알림톡 발송 내역
    loadStaff(),                      // 작가 목록
  ]);
  const { data, error } = res;
  if (error) {
    console.error(error);
    $('bkRows').innerHTML =
      '<tr><td colspan="7" style="padding:40px;text-align:center;color:#c0392b">목록을 불러오지 못했습니다. (' +
      esc(error.message) + ')</td></tr>';
    return;
  }
  allBookings = data || [];
  surveyIds = new Set(Array.isArray(sres.data) ? sres.data : []);
  allUnconfirmed = Array.isArray(ures.data) ? ures.data : [];
  eventDiscounts = (dres.data && typeof dres.data === 'object') ? dres.data : {};
  alimtalkFails = Array.isArray(fres.data) ? fres.data : [];
  render();
  renderDashboard();
  refreshEventBadge();
}

// 시작 시(및 변경 후) 이벤트 승인대기 배지 갱신
async function refreshEventBadge() {
  const { data, error } = await sb.rpc('admin_event_list');
  if (!error && data) updateEventBadge(data);
}

async function loadStaff() {
  const { data } = await sb.rpc('admin_staff_list');
  allStaff = data || [];
  staffMap = {};
  allStaff.forEach((s) => { staffMap[s.id] = s; });
  populateAssigneeSelects();
}
const staffName = (id) => (id && staffMap[id] ? staffMap[id].name : '');
function assigneeOptions(selId) {
  return '<option value="">미배정</option>' +
    allStaff.map((s) => `<option value="${s.id}"${s.id === selId ? ' selected' : ''}>${esc(s.name)}${s.active ? '' : ' (비활성)'}</option>`).join('');
}
function populateAssigneeSelects() {
  const sa = $('schedAssignee');
  if (sa) sa.innerHTML = '<option value="">담당자 선택…</option>' +
    allStaff.filter((s) => s.active).map((s) => `<option value="${s.id}">${esc(s.name)}</option>`).join('');
}

function render() {
  const counts = { 전체: allBookings.length, 신규: 0, 확정: 0, 취소: 0 };
  allBookings.forEach((b) => {
    if (counts[b.status] != null) counts[b.status]++;
  });
  $('c_all').textContent = counts['전체'];
  $('c_new').textContent = counts['신규'];
  if ($('c_confirm')) $('c_confirm').textContent = counts['확정'];
  if ($('c_cancel')) $('c_cancel').textContent = counts['취소'];

  if (!bkMonth) { const t = new Date(); bkMonth = { y: t.getFullYear(), m: t.getMonth() }; }
  const term = bkSearchTerm.toLowerCase();
  const searching = !!term;

  let rows = allBookings.filter((b) => {
    if (filter !== '전체' && b.status !== filter) return false;
    if (!term) return true;
    return [b.contractor_name, b.wedding_venue, b.contractor_phone, b.groom_name, b.bride_name]
      .some((v) => (v || '').toLowerCase().includes(term));
  });

  if (searching) {
    if ($('bkMonthNav')) $('bkMonthNav').hidden = true;
    rows.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  } else {
    if ($('bkMonthNav')) $('bkMonthNav').hidden = false;
    rows = rows.filter((b) => { const d = wDate(b); return d && d.getFullYear() === bkMonth.y && d.getMonth() === bkMonth.m; });
    rows.sort((a, b) => (wDate(a) - wDate(b)) || (a.wedding_time || '').localeCompare(b.wedding_time || ''));
    if ($('bkMonthLabel')) $('bkMonthLabel').textContent = `${bkMonth.y}년 ${bkMonth.m + 1}월 · ${rows.length}건`;
  }
  $('emptyMsg').hidden = rows.length > 0;

  $('bkRows').innerHTML = rows
    .map((b) => {
      const opts = bookingOpts(b);
      return `<tr data-id="${b.id}">
        <td data-label="접수일">${esc(fmtDateShort(b.created_at))}</td>
        <td data-label="계약자">${esc(b.contractor_name || '-')}${phBadge(b)}${surveyIds.has(b.id) ? ' <span class="survey-badge" title="설문 제출됨">📝</span>' : ''}</td>
        <td data-label="예식일">${esc(fmtDateShort(b.wedding_date))}</td>
        <td data-label="예식장">${esc(b.wedding_venue || '-')}</td>
        <td data-label="작가">${esc(staffName(b.assignee_id) || '-')}</td>
        <td data-label="옵션">${opts.length ? opts.map((o) => `<span class="bk-opt">${esc(o)}</span>`).join('') : '<span class="muted">-</span>'}</td>
        <td data-label="상태"><span class="badge ${esc(b.status)}">${esc(b.status)}</span></td>
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
  render();
});

if ($('bkSearch')) {
  $('bkSearch').addEventListener('input', (e) => { bkSearchTerm = e.target.value.trim(); render(); });
}
if ($('bkPrev')) {
  $('bkPrev').addEventListener('click', () => { if (!bkMonth) return; bkMonth.m--; if (bkMonth.m < 0) { bkMonth.m = 11; bkMonth.y--; } render(); });
  $('bkNext').addEventListener('click', () => { if (!bkMonth) return; bkMonth.m++; if (bkMonth.m > 11) { bkMonth.m = 0; bkMonth.y++; } render(); });
}

/* ===== Detail modal ===== */
// 상품 + 옵션을 한 카테고리로 (가격 분리표시)
function productOptions(b) {
  const rows = [];
  const base = b.package === '베이직(구)' ? 50 : 55;
  if (b.package) rows.push({ name: String(b.package).replace('(데이터형)', ''), price: base });
  if (b.travel_fee) rows.push({ name: '출장비', price: b.photographer === '2인 촬영' ? 10 : 5 });
  if (b.option_album) rows.push({ name: '앨범 1권 추가', price: 5 });
  if (b.option_reception) rows.push({ name: '연회장 인사촬영', price: 5 });
  if (b.option_pyebaek) rows.push({ name: '폐백촬영', price: 10 });
  if (b.option_part2) rows.push({ name: '2부 촬영', price: 10 });
  (Array.isArray(b.custom_options) ? b.custom_options : []).forEach((o) => { if (o && o.name) rows.push({ name: o.name, price: Number(o.price) || 0 }); });
  if (b.photographer === '2인 촬영') rows.push({ name: '2인 촬영', price: 25 });
  if (b.rep_designation) rows.push({ name: '대표지정', price: 35 });
  return rows;
}
function productOptionsHtml(b) {
  const rows = productOptions(b);
  if (!rows.length) return '<span class="dv">없음</span>';
  return '<div class="po-list">' + rows.map((r) =>
    `<div class="po-row"><span class="po-nm">${esc(r.name)}</span><span class="po-pr">${won(r.price)}</span></div>`).join('') + '</div>';
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
    const ok = c && c.attend && c.arrival && c.options;
    const items = c ? `참석 ${c.attend ? '✓' : '✕'} · 도착 ${c.arrival ? '✓' : '✕'} · 옵션 ${c.options ? '✓' : '✕'}` : '';
    const st = c ? (ok ? '✔ 확인완료' : '△ 일부확인') : '미확인';
    return `<div class="chk-line ${ok ? 'ok' : c ? 'partial' : 'none'}">
      <div class="chk-head">
        <span class="chk-role">${esc(role)} · ${esc(name)}</span>
        <span class="chk-st">${st}${c && c.checked_at ? ' <small>' + esc(fmtDateTime(c.checked_at)) + '</small>' : ''}</span>
        <button class="btn-sm chk-link" data-bid="${esc(b.id)}" data-staff="${esc(sid)}" data-role="${esc(role)}">${ok ? '재전송' : '체크 링크'}</button>
      </div>
      ${items ? `<div class="chk-items">${esc(items)}</div>` : ''}
      ${c && c.note ? `<div class="chk-note">📝 ${esc(c.note)}</div>` : ''}
    </div>`;
  };
  return `<div class="chk-box"><p class="chk-title">🧑‍🎨 작가 예식 전 확인</p>${line(b.assignee_id, '메인작가')}${b.sub_assignee_id ? line(b.sub_assignee_id, '서브작가') : ''}</div>`;
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
  const shareUrl = location.origin + '/survey-view?b=' + bid;
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
      <select id="mAssignee" class="md-sel">${assigneeOptions(b.assignee_id)}</select>
      ${b.photographer === '2인 촬영' ? `<span class="md-asg-label">서브작가</span><select id="mSubAssignee" class="md-sel">${assigneeOptions(b.sub_assignee_id)}</select>` : ''}
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
      ${b.photo_usage_agree ? field('촬영본 사용동의', 'YES') : ''}
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
           ${b.download_link ? `<a class="dl-open-d" href="${esc(b.download_link)}" target="_blank" rel="noopener">현재 링크 열기 ↗</a>` : '<span class="dl-empty-hint">아직 등록된 링크가 없어요</span>'}`
        : `<span class="dl-blocked-msg">🔒 잔금 입금 확인 후 입력 가능</span>`}
    </div>

    <div class="atk-prog">
      <p class="dl">알림톡 발송 <small>([발송]=실제 전송 · 배지=보냄 수동표시(클릭 토글))</small></p>
      <div class="atk-rows">
        ${ATK_TPLS.map(([k, label]) => {
          const on = b.alimtalk_sent && b.alimtalk_sent[k];
          return `<div class="atk-row">
            <button class="atk-send" data-send-atk="${k}">발송</button>
            <button class="atk-badge${on ? ' on' : ''}" data-atk="${k}">${esc(k)}. ${esc(label)}${on ? ' ✓' : ''}</button>
          </div>`;
        }).join('')}
      </div>
    </div>

    <div class="modal-btns">
      <button class="btn-primary" id="mEdit">수정</button>
      <button class="btn-outline" id="mCancelBk">${b.status === '취소' ? '취소 해제' : '예약 취소'}</button>
      <button class="btn-del" id="mDelete">삭제</button>
    </div>`;

  $('modalClose').addEventListener('click', closeModal);
  $('mEdit').addEventListener('click', () => renderEdit(b));
  $('mDelete').addEventListener('click', () => deleteBooking(b.id));
  $('mCancelBk').addEventListener('click', () => cancelBooking(b.id));
  const saveAssignees = async () => {
    const main = $('mAssignee').value || null;
    const sub = $('mSubAssignee') ? ($('mSubAssignee').value || null) : (b.sub_assignee_id || null);
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
      render();
      renderDashboard();
      renderView(data || b);
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

  // 레퍼런스 사진 클릭 → 크게 보기
  $('modalCard').addEventListener('click', (e) => {
    const im = e.target.closest('.sv-refs img');
    if (!im) return;
    const lb = document.createElement('div');
    lb.className = 'sv-lb';
    lb.innerHTML = `<img src="${im.src}" alt="" />`;
    lb.addEventListener('click', () => lb.remove());
    document.body.appendChild(lb);
  });
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

  $('modalCard').innerHTML = `
    <button class="modal-close" id="modalClose">&times;</button>
    <p class="modal-title">예약 수정</p>
    <p class="modal-sub">접수 ${esc(fmtDateTime(b.created_at))}</p>

    <h5 class="eg">계약자 정보</h5>
    <div class="edit-grid">
      <div class="field"><label>계약자 성함</label><input id="e_contractor_name" value="${v(b.contractor_name)}" /></div>
      <div class="field"><label>연락처</label><input id="e_contractor_phone" value="${v(b.contractor_phone)}" /></div>
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
      <div class="field"><label>신랑 연락처</label><input id="e_groom_phone" value="${v(b.groom_phone)}" /></div>
      <div class="field"><label>신부 성함</label><input id="e_bride_name" value="${v(b.bride_name)}" /></div>
      <div class="field"><label>신부 연락처</label><input id="e_bride_phone" value="${v(b.bride_phone)}" /></div>
    </div>

    <h5 class="eg">상품 · 옵션 <small>(체크 시 합계 자동 변경)</small></h5>
    <div class="field" style="margin-bottom:10px">
      <label>상품</label>
      <select id="e_package">
        <option value="베이직(데이터형)" data-price="55" ${sl(b.package, '베이직(데이터형)')}>베이직 (데이터형) · 55만원</option>
        <option value="스페셜" data-price="55" ${sl(b.package, '스페셜')}>스페셜 · 55만원 (구상품)</option>
        <option value="베이직(구)" data-price="50" ${sl(b.package, '베이직(구)')}>베이직(구) · 50만원 (구상품)</option>
      </select>
    </div>
    <div class="edit-opts">
      <label class="eopt"><input type="checkbox" id="e_travel" data-price="5" ${ck(b.travel_fee)} /><span>출장비</span><b>5만원</b></label>
      <label class="eopt"><input type="checkbox" id="e_option_album" data-price="5" ${ck(b.option_album)} /><span>앨범 1권 추가</span><b>+5만원</b></label>
      <label class="eopt"><input type="checkbox" id="e_option_reception" data-price="5" ${ck(b.option_reception)} /><span>연회장 인사촬영</span><b>+5만원</b></label>
      <label class="eopt"><input type="checkbox" id="e_option_pyebaek" data-price="10" ${ck(b.option_pyebaek)} /><span>폐백촬영</span><b>+10만원</b></label>
      <label class="eopt"><input type="checkbox" id="e_option_part2" data-price="10" ${ck(b.option_part2)} /><span>2부 촬영</span><b>+10만원</b></label>
    </div>
    <div class="field" style="margin-top:10px">
      <label>작가 선택</label>
      <select id="e_photographer">
        <option value="기본" data-price="0" ${sl(b.photographer, '기본')}>기본 (1인 촬영)</option>
        <option value="2인 촬영" data-price="25" ${sl(b.photographer, '2인 촬영')}>2인 촬영 (+25만원)</option>
      </select>
    </div>
    <label class="eopt" style="margin-top:8px"><input type="checkbox" id="e_rep" data-price="35" ${ck(b.rep_designation)} /><span>대표지정</span><b>+35만원</b></label>
    <label class="eopt" style="margin-top:8px"><input type="checkbox" id="e_usage" data-price="-1" ${ck(b.photo_usage_agree)} /><span>촬영본 사용동의 (YES)</span><b>-1만원</b></label>

    <h5 class="eg">커스텀 옵션 <small>(예전·비표준 옵션)</small></h5>
    <div id="customOpts" class="custom-opts"></div>
    <button type="button" class="btn-sm" id="addCustom" style="margin-top:8px">+ 옵션 추가</button>

    <h5 class="eg">작가 배정 · 입금</h5>
    <div class="edit-grid">
      <div class="field"><label>메인작가</label><select id="e_assignee">${assigneeOptions(b.assignee_id)}</select></div>
      ${b.photographer === '2인 촬영' ? `<div class="field"><label>서브작가</label><select id="e_sub_assignee">${assigneeOptions(b.sub_assignee_id)}</select></div>` : ''}
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
    const pk = $('e_package') && $('e_package').selectedOptions[0];
    if (pk) sum += Number(pk.dataset.price) || 0;
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
  $('modalCard').addEventListener('input', (e) => { if (e.target.classList.contains('co-price')) recalcEdit(); });
  recalcEdit();

  $('modalClose').addEventListener('click', closeModal);
  $('mCancel').addEventListener('click', () => renderView(b));
  $('mSave').addEventListener('click', () => saveDetail(b.id, recalcEdit));
}

function closeModal() {
  $('modal').hidden = true;
}
$('modalBackdrop').addEventListener('click', closeModal);

async function deleteBooking(id) {
  if (!confirm('이 예약을 완전히 삭제할까요?\n설문·레퍼런스도 함께 삭제되며 되돌릴 수 없습니다.')) return;
  const { error } = await sb.rpc('admin_delete_booking', { p_id: id });
  if (error) { alert('삭제 실패: ' + error.message); return; }
  allBookings = allBookings.filter((b) => b.id !== id);
  closeModal();
  render();
  renderDashboard();
  toast('예약을 삭제했어요.');
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
    option_album: cc('e_option_album'),
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
  if ($('e_sub_assignee')) payload.sub_assignee_id = $('e_sub_assignee').value;
  payload.custom_options = Array.from(document.querySelectorAll('#customOpts .co-row'))
    .map((r) => ({ name: r.querySelector('.co-name').value.trim(), price: Number(r.querySelector('.co-price').value) || 0 }))
    .filter((o) => o.name);
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
const ATK_NAME = { A: '계약안내', B: '한달전', C: '잔금안내', D: '최종안내', E: '링크안내', F: '입금확인' };
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
  const url = location.origin + '/survey-view?b=' + id;
  const head = b ? `${fmtDate(b.wedding_date)} ${b.contractor_name || ''}`.trim() + ' 예식 설문' : '';
  const text = head ? `${head}\n${url}` : url;
  if (navigator.clipboard) navigator.clipboard.writeText(text);
  toast(surveyIds.has(id) ? '작가 공유용 설문 링크를 복사했어요 📋 (날짜·성함 포함)' : '설문 링크 복사 — 아직 고객이 설문 미작성 상태예요');
}

const ATK_FAIL_NAME = { A: '계약안내', B: '한달전', C: '일주일전·잔금', D: '전날', E: '촬영본 안내', F: '입금확인' };
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

function renderDashboard() {
  if (!$('tab-dashboard')) return;
  renderAtkFail();
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

  // 📅 다가오는 예식 (오늘 ~ 2주)
  const in14 = new Date(today); in14.setDate(in14.getDate() + 14);
  const upcoming = allBookings.filter((b) => { const d = wDate(b); return d && d >= today && d <= in14 && b.status === '확정'; })
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
      const asgBadge = b.assignee_id
        ? `<span class="dl-asg" style="color:${staffColor(b.assignee_id)}">● ${esc(staffName(b.assignee_id))}</span>`
        : '<span class="dl-asg none">미배정</span>';
      const mainSent = !!b.check_sent_at;
      const subSent = !!b.sub_check_sent_at;
      const needsSub = !!b.sub_assignee_id;
      const conf = confMap[b.id];
      const mainOk = !!(conf && conf.main_ok);
      const subOk = !!(conf && conf.sub_ok);
      const roleFlag = (sent, ok, role) => ok
        ? `<span class="chk-confirmed">${role} 확인 ✓</span>`
        : (sent ? '<span class="chk-sentflag">보냄 ✓</span>' : '');
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
               </div>
               ${needsSub ? `<div class="chk-rolerow">
                 <button class="btn-sm chk-send" data-id="${b.id}" data-staff="${b.sub_assignee_id}" data-role="서브">${subSent ? '서브 재전송' : '서브 체크'}</button>
                 <button class="btn-sm btn-kakao-sm chk-share" data-id="${b.id}" data-staff="${b.sub_assignee_id}" data-role="서브" title="카톡으로 공유">공유</button>
                 ${roleFlag(subSent, subOk, '서브')}
               </div>` : ''}`
            : '<span class="dl-na">작가 미배정</span>'}
          <button class="btn-sm sv-copy${surveyIds.has(b.id) ? '' : ' muted'}" data-id="${b.id}">${surveyIds.has(b.id) ? '설문 복사' : '설문 복사(미작성)'}</button>
        </div>
      </div>`;
    })
    : '<p class="dash-empty">2주 내 예식이 없어요.</p>';

  // 💳 미입금 (계약금 / 잔금)
  const byDate = (a, b) => (wDate(a) || 0) - (wDate(b) || 0);
  // 계약금 미입금: 계약안내(A) 보낸 뒤 ~ 입금 확인 전
  const depUnpaid = allBookings.filter((b) => b.alimtalk_sent && b.alimtalk_sent.A && !b.deposit_paid && notCancelled(b)).sort(byDate);
  // 잔금 미입금: 잔금안내(C) 보낸 뒤 ~ 입금 확인 전
  const balUnpaid = allBookings.filter((b) => b.alimtalk_sent && b.alimtalk_sent.C && !b.balance_paid && notCancelled(b)).sort(byDate);
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
        ${overdue ? `<button class="btn-sm od-cancel" data-id="${b.id}">예약 취소</button>` : ''}
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
  const needDl = allBookings.filter((b) => { const d = wDate(b); return d && d <= endToday && !(b.alimtalk_sent && b.alimtalk_sent.E) && notCancelled(b); })
    .sort((a, b) => wDate(b) - wDate(a));
  $('dcDownload').textContent = needDl.length;
  $('listDownload').innerHTML = needDl.length
    ? groupByDate(needDl.slice(0, 40), (b) => {
        const dlrow = b.balance_paid
          ? `<div class="dl-dlrow">
               <input type="text" class="dl-link" data-id="${b.id}" placeholder="다운로드 링크 붙여넣기" value="${esc(b.download_link || '')}" />
               <button class="btn-sm dl-save" data-id="${b.id}">저장</button>
               <button class="btn-sm btn-kakao-sm" data-send="${b.id}" data-tpl="E">카톡 전송</button>
             </div>`
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
  if (b.option_album) o.push('앨범');
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
        const bg = assigned ? ` style="background:${tint(staffColor(b.assignee_id), 0.16)}"` : '';
        return `
        <div class="sched-row${assigned ? ' assigned' : ''}" data-id="${b.id}"${bg}>
          <input type="checkbox" class="sched-cb" value="${b.id}" />
          <span class="sched-time">${esc(kTimeShort(b.wedding_time)) || '-'}</span>
          <span class="sched-name">${esc(b.contractor_name || '-')}</span>
          <div class="sched-mid">
            <span class="sched-venue">${esc(b.wedding_venue || '-')}</span>
            ${opts.length ? `<span class="sched-opts">${opts.map((o) => `<span class="sched-optag">${esc(o)}</span>`).join('')}</span>` : ''}
          </div>
          <div class="sched-asg-ctrls">
            <div class="sched-sels">
              <select class="sched-main" data-id="${b.id}" title="메인작가">${assigneeOptions(b.assignee_id)}</select>
              ${is2 ? `<select class="sched-sub" data-id="${b.id}" title="서브작가">${assigneeOptions(b.sub_assignee_id)}</select>` : ''}
            </div>
            <button type="button" class="sched-copy1" data-id="${b.id}" title="이 예식 스케줄 복사">📋</button>
          </div>
        </div>`;
      }).join('')}
    </div>`).join('');
  bindSchedule();
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
      const sub = subEl ? (subEl.value || null) : ((allBookings.find((x) => x.id === id) || {}).sub_assignee_id || null);
      const { error } = await sb.rpc('admin_set_assignees', { p_id: id, p_main: main, p_sub: sub });
      if (error) { alert('배정 실패: ' + error.message); return; }
      const b = allBookings.find((x) => x.id === id);
      if (b) { b.assignee_id = main; b.sub_assignee_id = sub; }
      renderCalendar(); renderDashboard();
      renderSchedTags(schedMonthItems());
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
  // 되돌리기용 직전 상태 스냅샷
  lastAssign = ids.map((id) => { const b = allBookings.find((x) => x.id === id) || {}; return { id, main: b.assignee_id || '', sub: b.sub_assignee_id || '' }; });
  const { error } = await sb.rpc('admin_assign_role', { p_ids: ids, p_assignee: aid, p_role: role });
  if (error) { lastAssign = null; alert('배정 실패: ' + error.message); return; }
  ids.forEach((id) => { const b = allBookings.find((x) => x.id === id); if (b) { if (role === 'sub') b.sub_assignee_id = aid; else b.assignee_id = aid; } });
  toast(`${ids.length}건 → ${staffName(aid)} ${role === 'sub' ? '서브' : '메인'} 배정 완료${skipped ? ` (배정된 ${skipped}건 제외)` : ''}`);
  updateUndoBtn();
  renderSchedule(); renderCalendar(); renderDashboard();
  if ($('schedAll')) $('schedAll').checked = false;
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
    lastAssign = null; updateUndoBtn();
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
function renderStaff() {
  if (!$('staffList')) return;
  $('staffEmpty').hidden = allStaff.length > 0;
  $('staffList').innerHTML = allStaff.map((s) => `
    <div class="staff-item${s.active ? '' : ' inactive'}" data-id="${s.id}">
      <input type="text" class="st-name" data-id="${s.id}" value="${esc(s.name || '')}" placeholder="이름" />
      <input type="text" class="st-phone" data-id="${s.id}" value="${esc(s.phone || '')}" placeholder="연락처" />
      <label class="st-active"><input type="checkbox" class="st-rep" data-id="${s.id}" ${s.is_rep ? 'checked' : ''} /> 대표</label>
      <label class="st-active"><input type="checkbox" class="st-act" data-id="${s.id}" ${s.active ? 'checked' : ''} /> 활성</label>
      <button class="btn-sm st-save" data-id="${s.id}">저장</button>
      <button class="btn-sm st-del" data-id="${s.id}">삭제</button>
    </div>`).join('');

  $('staffList').querySelectorAll('.st-save').forEach((btn) =>
    btn.addEventListener('click', async () => {
      const id = btn.dataset.id;
      const name = $('staffList').querySelector(`.st-name[data-id="${id}"]`).value.trim();
      const phone = $('staffList').querySelector(`.st-phone[data-id="${id}"]`).value.trim();
      const active = $('staffList').querySelector(`.st-act[data-id="${id}"]`).checked;
      const rep = $('staffList').querySelector(`.st-rep[data-id="${id}"]`).checked;
      if (!name) { alert('이름을 입력하세요.'); return; }
      btn.disabled = true;
      const { error } = await sb.rpc('admin_staff_update', { p_id: id, p_name: name, p_phone: phone, p_active: active, p_rep: rep });
      btn.disabled = false;
      if (error) { alert('저장 실패: ' + error.message); return; }
      await loadStaff();
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
    $('tab-staff').hidden = tab !== 'staff';
    $('tab-gallery').hidden = tab !== 'gallery';
    $('tab-events').hidden = tab !== 'events';
    if (tab === 'dashboard') renderDashboard();
    if (tab === 'calendar') { renderCalendar(); renderSchedule(); }
    if (tab === 'staff') renderStaff();
    if (tab === 'gallery') loadGallery();
    if (tab === 'events') loadEvents();
  });
}

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

function updateEventBadge(data) {
  const pend = (data.buddies || []).filter((b) => b.status === 'matched').length
             + (data.reviews || []).filter((r) => r.status === 'pending').length;
  const el = $('evBadge');
  if (!el) return;
  el.textContent = pend;
  el.hidden = pend === 0;
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
  document.querySelectorAll('#tab-events .ev-approve').forEach((btn) =>
    btn.addEventListener('click', () => eventAction(btn.dataset.kind, btn.dataset.id, 'approve')));
  document.querySelectorAll('#tab-events .ev-cancel').forEach((btn) =>
    btn.addEventListener('click', () => eventAction(btn.dataset.kind, btn.dataset.id, 'cancel')));
  document.querySelectorAll('#tab-events .ev-reject').forEach((btn) =>
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
      const add = await sb.rpc('admin_gallery_add', { payload: { image_path: path, image_url: pub.data.publicUrl, venue } });
      if (add.error) throw add.error;
    }
    const n = files.length;
    clearQueue();
    $('glFiles').value = '';
    $('glVenue').value = '';
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
  renderGalleryAdmin();
}

const glVisible = () => {
  if (glSearch) {
    const t = glSearch.toLowerCase();
    return glAllItems.filter((g) => (g.venue || '').toLowerCase().includes(t));
  }
  return glActiveTag === '전체' ? glAllItems : glAllItems.filter((g) => g.venue === glActiveTag);
};

function renderGalleryAdmin() {
  renderGalleryTags();
  renderGalleryGrid();
}

// 태그: 사진 많은 순 + 검색 + 한 줄 접기(더보기)
function renderGalleryTags() {
  $('glEmpty').hidden = glAllItems.length > 0;
  const counts = {};
  glAllItems.forEach((g) => { if (g.venue) counts[g.venue] = (counts[g.venue] || 0) + 1; });
  const venues = Object.keys(counts).sort((a, b) => counts[b] - counts[a]);

  const top = `<div class="gl-tags-top">
      <button class="gl-tag${glActiveTag === '전체' && !glSearch ? ' active' : ''}" data-v="전체">전체 ${glAllItems.length}</button>
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
    ? url.replace('/object/public/', '/render/image/public/') + `?width=${w}&quality=72`
    : url;

function renderGalleryGrid() {
  // 그리드 (페이지네이션 20장)
  const list = glVisible();
  const start = (glPage - 1) * GL_PER;
  const grid = $('glGrid');
  grid.innerHTML = list
    .slice(start, start + GL_PER)
    .map((g) => `<div class="gl-item"><img src="${esc(imgThumb(g.image_url, 400))}" alt="" loading="lazy" decoding="async" /><div class="gl-meta"><input class="gl-venue-edit" data-id="${esc(g.id)}" value="${esc(g.venue || '')}" placeholder="장소 태그" /><button class="gl-del" data-id="${esc(g.id)}" data-path="${esc(g.image_path)}">삭제</button></div></div>`)
    .join('');
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
  let html = `<button class="gpg nav" data-p="${glPage - 1}"${glPage === 1 ? ' disabled' : ''}>‹</button>`;
  for (let i = 1; i <= pages; i++) html += `<button class="gpg${i === glPage ? ' active' : ''}" data-p="${i}">${i}</button>`;
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
const VAPID_PUBLIC = 'BNgY76pnHOwm28BIYaOfPo45abDvlcw4vFQARQRMg169r8IttLfDO1jv1Ao9hQajx76DTrbonRC-gvpSogjdJcs';
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
