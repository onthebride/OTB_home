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
let filter = '전체';
let bkSearchTerm = '';
let bkMonth = null; // 예약 목록 월별 페이지 {y, m}
let surveyIds = new Set(); // 설문 제출된 예약 ID
let allUnconfirmed = []; // 작가 미확인 (admin_unconfirmed)
let calMonth = null; // 캘린더 현재 월 {y, m}
let unpaidTab = 'deposit'; // 미입금 탭: deposit | balance
let allStaff = [];
let staffMap = {};
const ATK_TPLS = [['A', '계약안내'], ['B', '한달 전'], ['C', '잔금안내'], ['D', '최종안내'], ['E', '링크안내']];
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

/* ===== Auth views ===== */
const showLogin = () => {
  $('loginView').hidden = false;
  $('dashView').hidden = true;
};
const showDash = (email) => {
  $('loginView').hidden = true;
  $('dashView').hidden = false;
  $('dashUser').textContent = email || '';
  loadBookings();
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
  const { error } = await sb.auth.signInWithPassword({
    email: $('email').value.trim(),
    password: $('password').value,
  });
  btn.disabled = false;
  btn.textContent = '로그인';
  if (error) {
    msg.textContent = '로그인 실패: 이메일 또는 비밀번호를 확인해 주세요.';
  }
});

$('logoutBtn').addEventListener('click', () => sb.auth.signOut());
$('refreshBtn').addEventListener('click', () => loadBookings());

/* ===== Load + render ===== */
async function loadBookings() {
  const { data, error } = await sb.rpc('admin_list_bookings');
  if (error) {
    console.error(error);
    $('bkRows').innerHTML =
      '<tr><td colspan="7" style="padding:40px;text-align:center;color:#c0392b">목록을 불러오지 못했습니다. (' +
      esc(error.message) + ')</td></tr>';
    return;
  }
  allBookings = data || [];
  // 설문 제출 여부
  const sres = await sb.rpc('admin_survey_ids');
  surveyIds = new Set(Array.isArray(sres.data) ? sres.data : []);
  const ures = await sb.rpc('admin_unconfirmed');
  allUnconfirmed = Array.isArray(ures.data) ? ures.data : [];
  await loadStaff();
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
function optionTags(b) {
  const t = [];
  if (b.option_album) t.push('앨범 1권 추가');
  if (b.option_reception) t.push('연회장 인사촬영');
  if (b.option_pyebaek) t.push('폐백촬영');
  if (b.option_part2) t.push('2부 촬영');
  (Array.isArray(b.custom_options) ? b.custom_options : []).forEach((o) => { if (o && o.name) t.push(o.name + (o.price ? ` (${o.price}만원)` : '')); });
  if (!t.length) return '<span class="dv">없음</span>';
  return '<div class="opt-tags">' + t.map((x) => `<span class="opt-tag">${esc(x)}</span>`).join('') + '</div>';
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

async function copyCheckLink(bid, sid, roleLabel, role) {
  if (!sid) { toast('먼저 작가를 배정하세요.'); return; }
  const lr = await sb.rpc('admin_make_check_link', { p_booking_id: bid, p_staff_id: sid });
  const url = lr.data ? location.origin + '/c?k=' + lr.data : location.origin + '/staff-schedule?s=' + sid + '&b=' + bid;
  try { await navigator.clipboard.writeText(url); } catch (_) { prompt('작가 체크 링크 (복사):', url); }
  const { data } = await sb.rpc('admin_mark_check_sent', { p_id: bid, p_on: true, p_role: String(role || '').includes('서브') ? '서브' : '메인' });
  const i = allBookings.findIndex((x) => x.id === bid);
  if (i >= 0 && data) allBookings[i] = data;
  const ures = await sb.rpc('admin_unconfirmed');
  allUnconfirmed = Array.isArray(ures.data) ? ures.data : [];
  toast(`${roleLabel} 체크 링크 복사됨 · 보냄 표시`);
  renderDashboard();
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
  if (!s) {
    return `<div class="survey-box">
      <div class="survey-bar">
        <span class="survey-none">📝 설문 미작성</span>
        <button type="button" class="survey-share" data-url="${esc(customerUrl)}">고객 설문 링크 복사</button>
      </div></div>`;
  }
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
      ${field('상품', b.package)}
      ${b.travel_fee ? field('출장비', '있음 (50,000원)') : ''}
      ${b.photographer === '2인 촬영' ? field('촬영', '2인 촬영') : ''}
      ${b.rep_designation ? field('대표지정', '예') : ''}
      ${b.photo_usage_agree ? field('촬영본 사용동의', 'YES') : ''}
      ${field('합계', won(b.total_price))}
      <div><p class="dl">계약금</p><p class="dv">${won(10)} · <span class="pay-st ${b.deposit_paid ? 'paid' : ''}">${b.deposit_paid ? '입금완료 ✓' : '미입금'}</span> <button class="pay-toggle" data-pay="deposit">${b.deposit_paid ? '해제' : '입금확인'}</button></p></div>
      <div><p class="dl">잔금</p><p class="dv">${b.total_price != null ? won(b.total_price - 10) : '-'} · <span class="pay-st ${b.balance_paid ? 'paid' : ''}">${b.balance_paid ? '입금완료 ✓' : '미입금'}</span> <button class="pay-toggle" data-pay="balance">${b.balance_paid ? '해제' : '입금확인'}</button></p></div>
      <div class="full2"><p class="dl">추가 옵션</p>${optionTags(b)}</div>
      ${b.admin_note ? `<div class="full2">${field('관리자 메모', b.admin_note)}</div>` : ''}
    </div>

    ${b.assignee_id ? `<div id="checkSlot" data-bid="${esc(b.id)}"></div>` : ''}
    <div id="surveySlot" data-bid="${esc(b.id)}">${surveyIds.has(b.id) ? '<p class="survey-loading">📝 설문 불러오는 중…</p>' : ''}</div>

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

function toast(msg) {
  let el = $('toast');
  if (!el) { el = document.createElement('div'); el.id = 'toast'; el.className = 'toast'; document.body.appendChild(el); }
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => el.classList.remove('show'), 2600);
}

// 알림톡 실제 발송 (솔라피)
const ATK_NAME = { A: '계약안내', B: '한달전', C: '잔금안내', D: '최종안내', E: '링크안내' };
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

function renderDashboard() {
  if (!$('tab-dashboard')) return;
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
  $('listUpcoming').innerHTML = upcoming.length
    ? upcoming.map((b) => {
      const d = wDate(b);
      const dleft = Math.round((d - today) / 86400000);
      const dtag = dleft === 0 ? '오늘' : 'D-' + dleft;
      const asg = b.assignee_id ? ` · 담당 ${esc(staffName(b.assignee_id))}` : '';
      const mainSent = !!b.check_sent_at;
      const subSent = !!b.sub_check_sent_at;
      const needsSub = !!b.sub_assignee_id;
      const allSent = mainSent && (!needsSub || subSent);
      return `
      <div class="dl-item soon" data-id="${b.id}">
        <div class="dl-main">
          <span class="dl-name">${esc(b.contractor_name || '-')}${phBadge(b)} <span class="dday">${dtag}</span></span>
          <span class="dl-meta">${esc(fmtDate(b.wedding_date))} ${esc(kTimeShort(b.wedding_time))} · ${esc(b.wedding_venue || '-')}${asg}</span>
        </div>
        <div class="dl-actions">
          ${b.assignee_id
            ? `<button class="btn-sm chk-send" data-id="${b.id}" data-staff="${b.assignee_id}" data-role="메인">${mainSent ? '메인 재전송' : '메인 체크'}</button>
               ${needsSub ? `<button class="btn-sm chk-send" data-id="${b.id}" data-staff="${b.sub_assignee_id}" data-role="서브">${subSent ? '서브 재전송' : '서브 체크'}</button>` : ''}
               ${allSent ? '<span class="chk-sentflag">보냄 ✓</span>' : ''}`
            : '<span class="dl-na">작가 미배정</span>'}
        </div>
      </div>`;
    }).join('')
    : '<p class="dash-empty">2주 내 예식이 없어요.</p>';

  // 💳 미입금 (계약금 / 잔금)
  const byDate = (a, b) => (wDate(a) || 0) - (wDate(b) || 0);
  // 계약금 미입금: 계약안내(A) 보낸 뒤 ~ 입금 확인 전
  const depUnpaid = allBookings.filter((b) => b.alimtalk_sent && b.alimtalk_sent.A && !b.deposit_paid && notCancelled(b)).sort(byDate);
  // 잔금 미입금: 잔금안내(C) 보낸 뒤 ~ 입금 확인 전
  const balUnpaid = allBookings.filter((b) => b.alimtalk_sent && b.alimtalk_sent.C && !b.balance_paid && notCancelled(b)).sort(byDate);
  const nowMs = Date.now();
  const unpaidItem = (b, kind) => {
    const amt = kind === 'deposit' ? won(10) : (b.total_price != null ? won(b.total_price - 10) : '-');
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

  // ⬇️ 다운로드 링크 필요 (예식 지남 + E 미발송)
  const needDl = allBookings.filter((b) => { const d = wDate(b); return d && d < today && !(b.alimtalk_sent && b.alimtalk_sent.E) && notCancelled(b); })
    .sort((a, b) => wDate(b) - wDate(a));
  $('dcDownload').textContent = needDl.length;
  $('listDownload').innerHTML = needDl.length
    ? needDl.slice(0, 40).map((b) => `
      <div class="dl-item dl-download" data-id="${b.id}">
        <div class="dl-main">
          <span class="dl-name">${esc(b.contractor_name || '-')}${phBadge(b)}</span>
          <span class="dl-meta">${esc(fmtDate(b.wedding_date))} · ${esc(b.wedding_venue || '-')}</span>
        </div>
        <div class="dl-dlrow">
          <input type="text" class="dl-link" data-id="${b.id}" placeholder="다운로드 링크 붙여넣기" value="${esc(b.download_link || '')}" />
          <button class="btn-sm dl-save" data-id="${b.id}">저장</button>
          <button class="btn-sm btn-kakao-sm" data-send="${b.id}" data-tpl="E">카톡 전송</button>
        </div>
      </div>`).join('')
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
  $('calLabel').textContent = `${y}년 ${m + 1}월`;
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
  $('calendar').innerHTML = html;
  $('calendar').querySelectorAll('.cal-cell.has').forEach((c) =>
    c.addEventListener('click', () => { const d = +c.dataset.day; showDayList(`${y}년 ${m + 1}월 ${d}일`, byDay[d] || []); })
  );
}

function showDayList(label, items) {
  const old = document.getElementById('dayOv');
  if (old) old.remove();
  const sorted = items.slice().sort((a, b) => (a.wedding_time || '').localeCompare(b.wedding_time || ''));
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
  const close = () => ov.remove();
  ov.querySelector('.day-ov-bg').addEventListener('click', close);
  ov.querySelector('.day-ov-x').addEventListener('click', close);
  ov.querySelectorAll('.day-ov-item').forEach((it) => it.addEventListener('click', () => openDetail(it.dataset.id)));
}

if ($('calPrev')) {
  $('calPrev').addEventListener('click', () => { calMonth.m--; if (calMonth.m < 0) { calMonth.m = 11; calMonth.y--; } renderCalendar(); renderSchedule(); });
  $('calNext').addEventListener('click', () => { calMonth.m++; if (calMonth.m > 11) { calMonth.m = 0; calMonth.y++; } renderCalendar(); renderSchedule(); });
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

function renderSchedule() {
  const wrap = $('schedList');
  if (!wrap || !calMonth) return;
  const items = schedMonthItems();
  renderSchedTags(items);

  if (!items.length) { wrap.innerHTML = '<p class="dash-empty">이 달 예식이 없어요.</p>'; updateSchedCount(); return; }

  const groups = {};
  items.forEach((b) => { const k = fmtDate(b.wedding_date); (groups[k] = groups[k] || []).push(b); });

  wrap.innerHTML = Object.keys(groups).map((k) => `
    <div class="sched-group">
      <p class="sched-date">${esc(k)}${groups[k][0] ? ' (' + wdLabel(groups[k][0]) + ')' : ''} <span>· ${groups[k].length}건</span></p>
      ${groups[k].map((b) => {
        const opts = bookingOpts(b);
        const is2 = b.photographer === '2인 촬영';
        return `
        <div class="sched-row" data-id="${b.id}">
          <input type="checkbox" class="sched-cb" value="${b.id}" />
          <span class="sched-time">${esc(kTimeShort(b.wedding_time)) || '-'}</span>
          <span class="sched-name">${esc(b.contractor_name || '-')}</span>
          <div class="sched-mid">
            <span class="sched-venue">${esc(b.wedding_venue || '-')}</span>
            ${opts.length ? `<span class="sched-opts">${opts.map((o) => `<span class="sched-optag">${esc(o)}</span>`).join('')}</span>` : ''}
          </div>
          <div class="sched-asg-ctrls">
            <select class="sched-main" data-id="${b.id}" title="메인작가">${assigneeOptions(b.assignee_id)}</select>
            ${is2 ? `<select class="sched-sub" data-id="${b.id}" title="서브작가">${assigneeOptions(b.sub_assignee_id)}</select>` : ''}
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
  el.innerHTML = (ids.length || unassigned)
    ? '<span class="sched-tags-label">작가별 선택:</span>' +
      ids.map((id) => `<button type="button" class="sched-tag" data-staff="${id}"><i style="background:${staffColor(id)}"></i>${esc(staffName(id))} ${used[id]}</button>`).join('') +
      (unassigned ? `<button type="button" class="sched-tag none" data-staff="none">미배정 ${unassigned}</button>` : '')
    : '';
  el.querySelectorAll('.sched-tag').forEach((btn) => btn.addEventListener('click', () => selectByStaff(btn.dataset.staff)));
}

function selectByStaff(staffId) {
  const match = (b) => staffId === 'none' ? !b.assignee_id : (b.assignee_id === staffId || b.sub_assignee_id === staffId);
  document.querySelectorAll('#schedList .sched-cb').forEach((c) => {
    const b = allBookings.find((x) => x.id === c.value);
    c.checked = !!(b && match(b));
  });
  updateSchedCount();
  const n = schedChecked().length;
  toast(n ? `${n}건 선택됨 — [선택 공유] 누르세요` : '해당 작가 일정이 없어요');
}

function schedChecked() {
  return Array.from(document.querySelectorAll('#schedList .sched-cb:checked')).map((c) => c.value);
}
function updateSchedCount() {
  const n = schedChecked().length;
  if ($('schedSelCount')) $('schedSelCount').textContent = n ? `${n}건 선택` : '';
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
  updateSchedCount();
}
if ($('schedAll')) {
  $('schedAll').addEventListener('change', (e) => {
    document.querySelectorAll('#schedList .sched-cb').forEach((c) => { c.checked = e.target.checked; });
    updateSchedCount();
  });
}
if ($('schedAssign')) {
  $('schedAssign').addEventListener('click', async () => {
    const ids = schedChecked();
    const aid = $('schedAssignee').value;
    if (!ids.length) { toast('배정할 일정을 선택하세요.'); return; }
    if (!aid) { toast('담당자를 선택하세요.'); return; }
    const { error } = await sb.rpc('admin_assign', { p_ids: ids, p_assignee: aid });
    if (error) { alert('배정 실패: ' + error.message); return; }
    ids.forEach((id) => { const b = allBookings.find((x) => x.id === id); if (b) b.assignee_id = aid; });
    toast(`${ids.length}건 → ${staffName(aid)} 배정 완료`);
    renderSchedule(); renderCalendar(); renderDashboard();
    if ($('schedAll')) $('schedAll').checked = false;
  });
}
if ($('schedShare')) {
  $('schedShare').addEventListener('click', async () => {
    const ids = schedChecked();
    if (!ids.length) { toast('공유할 일정을 선택하세요.'); return; }
    const rows = ids.map((id) => allBookings.find((b) => b.id === id)).filter(Boolean)
      .sort((a, b) => (wDate(a) - wDate(b)) || (a.wedding_time || '').localeCompare(b.wedding_time || ''));
    const fmtDot = (s) => (s ? String(s).slice(0, 10).replace(/-/g, '.') : '-');
    const pkg = (b) => ((b.package || '').replace(/\s*\(.*\)\s*/, '') || '베이직');
    const text = rows.map((b) => {
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
    try { await navigator.clipboard.writeText(text); toast(`${rows.length}건 스케줄 복사됨! 작가에게 붙여넣기 하세요.`); }
    catch (_) { prompt('아래 내용을 복사하세요:', text); }
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
const dashTabs = document.querySelector('.dash-tabs');
if (dashTabs) {
  dashTabs.addEventListener('click', (e) => {
    const t = e.target.closest('.dtab');
    if (!t) return;
    document.querySelectorAll('.dtab').forEach((x) => x.classList.toggle('active', x === t));
    const tab = t.dataset.tab;
    $('tab-dashboard').hidden = tab !== 'dashboard';
    $('tab-bookings').hidden = tab !== 'bookings';
    $('tab-staff').hidden = tab !== 'staff';
    $('tab-gallery').hidden = tab !== 'gallery';
    $('tab-events').hidden = tab !== 'events';
    if (tab === 'dashboard') renderDashboard();
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
  if (!list.length) { wrap.innerHTML = '<p class="empty">짝꿍 신청이 없어요.</p>'; return; }
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
  if (!list.length) { wrap.innerHTML = '<p class="empty">후기 등록이 없어요.</p>'; return; }
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
  loadEvents();
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

function renderGalleryGrid() {
  // 그리드 (페이지네이션 20장)
  const list = glVisible();
  const start = (glPage - 1) * GL_PER;
  const grid = $('glGrid');
  grid.innerHTML = list
    .slice(start, start + GL_PER)
    .map((g) => `<div class="gl-item"><img src="${esc(g.image_url)}" alt="" /><div class="gl-meta"><input class="gl-venue-edit" data-id="${esc(g.id)}" value="${esc(g.venue || '')}" placeholder="장소 태그" /><button class="gl-del" data-id="${esc(g.id)}" data-path="${esc(g.image_path)}">삭제</button></div></div>`)
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
