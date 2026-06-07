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
const fmtDateTime = (s) =>
  s ? new Date(s).toLocaleString('ko-KR', { dateStyle: 'medium', timeStyle: 'short' }) : '-';

let allBookings = [];
let filter = '전체';
let bkSearchTerm = '';
let surveyIds = new Set(); // 설문 제출된 예약 ID
let calMonth = null; // 캘린더 현재 월 {y, m}

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
  render();
  renderDashboard();
}

function render() {
  const counts = { 전체: allBookings.length, 신규: 0, 확인: 0, 전송완료: 0 };
  allBookings.forEach((b) => {
    if (counts[b.status] != null) counts[b.status]++;
  });
  $('c_all').textContent = counts['전체'];
  $('c_new').textContent = counts['신규'];
  $('c_ok').textContent = counts['확인'];
  $('c_sent').textContent = counts['전송완료'];

  const term = bkSearchTerm.toLowerCase();
  const rows = allBookings.filter((b) => {
    if (filter !== '전체' && b.status !== filter) return false;
    if (!term) return true;
    return [b.contractor_name, b.wedding_venue, b.contractor_phone, b.groom_name, b.bride_name]
      .some((v) => (v || '').toLowerCase().includes(term));
  });
  $('emptyMsg').hidden = rows.length > 0;

  $('bkRows').innerHTML = rows
    .map(
      (b) => `<tr data-id="${b.id}">
        <td>${esc(fmtDate(b.created_at))}</td>
        <td>${esc(b.contractor_name || '-')}${surveyIds.has(b.id) ? ' <span class="survey-badge" title="설문 제출됨">📝</span>' : ''}</td>
        <td>${esc(fmtDate(b.wedding_date))}</td>
        <td>${esc(b.wedding_venue || '-')}</td>
        <td>${esc(b.photographer || '-')}</td>
        <td>${esc(won(b.total_price))}</td>
        <td><span class="badge ${esc(b.status)}">${esc(b.status)}</span></td>
      </tr>`
    )
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

/* ===== Detail modal ===== */
function optionTags(b) {
  const t = [];
  if (b.option_album) t.push('앨범 1권 추가');
  if (b.option_reception) t.push('연회장 인사촬영');
  if (b.option_pyebaek) t.push('폐백촬영');
  if (b.option_part2) t.push('2부 촬영');
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
  // 설문이 있으면 비동기로 불러와 상세에 주입
  if (surveyIds.has(id)) {
    const { data } = await sb.rpc('admin_survey_get', { p_booking_id: id });
    // 모달이 여전히 같은 예약을 보고 있을 때만 주입
    const slot = $('surveySlot');
    if (data && slot && slot.dataset.bid === id) { slot.innerHTML = renderSurvey(data); bindSurveyControls(); }
  }
}

const PROG_ALL = ['신랑신부 동시 입장', '예물교환', '주례말씀', '축사', '축가', '예배식'];

function renderSurvey(s) {
  const row = (label, value) =>
    value ? `<div class="sv-row"><span class="sv-l">${esc(label)}</span><span class="sv-v">${esc(value)}</span></div>` : '';
  const yn = (v) => (v ? '예' : '');
  const prog = Array.isArray(s.prog_items) ? s.prog_items.join(', ') : '';
  const refs = Array.isArray(s.refs) ? s.refs : [];
  const refHtml = refs.length
    ? `<div class="sv-row col"><span class="sv-l">레퍼런스 (${refs.length})</span>
        <div class="sv-refs">${refs.map((u, i) => `<img src="${esc(u)}" data-i="${i}" alt="레퍼런스" />`).join('')}</div></div>`
    : '';
  const shareUrl = location.origin + '/survey-view?b=' + s.booking_id;
  return `
    <div class="survey-box">
      <div class="survey-bar">
        <button type="button" class="survey-toggle" id="svToggle" aria-expanded="false">
          📝 예식 전 설문 <small>${esc(fmtDateTime(s.updated_at))} 작성</small> <span class="sv-caret">▾</span>
        </button>
        <button type="button" class="survey-share" id="svShare" data-url="${esc(shareUrl)}">작가 공유 링크 복사</button>
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
  const share = $('svShare');
  if (share) {
    share.addEventListener('click', async () => {
      const url = share.dataset.url;
      try {
        await navigator.clipboard.writeText(url);
        const t = share.textContent;
        share.textContent = '복사됨! ✓';
        share.classList.add('copied');
        setTimeout(() => { share.textContent = t; share.classList.remove('copied'); }, 1600);
      } catch (_) {
        prompt('작가에게 보낼 링크를 복사하세요:', url);
      }
    });
  }
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

    <div class="detail-grid">
      ${field('연락처', b.contractor_phone)}
      ${field('이메일', b.contractor_email)}
      ${field('예식일', fmtDate(b.wedding_date))}
      ${field('예식시간', kTimeDisp(b.wedding_time))}
      <div class="full2">${field('예식장소', b.wedding_venue)}</div>
      ${field('신랑님', (b.groom_name || '') + ' / ' + (b.groom_phone || ''))}
      ${field('신부님', (b.bride_name || '') + ' / ' + (b.bride_phone || ''))}
      ${field('상품', b.package)}
      ${field('출장비', b.travel_fee ? '있음 (50,000원)' : '없음')}
      ${field('작가', b.photographer)}
      ${field('촬영본 사용동의', b.photo_usage_agree ? 'YES' : 'NO')}
      ${field('합계', won(b.total_price))}
      <div class="full2"><p class="dl">추가 옵션</p>${optionTags(b)}</div>
      ${b.admin_note ? `<div class="full2">${field('관리자 메모', b.admin_note)}</div>` : ''}
    </div>

    <div id="surveySlot" data-bid="${esc(b.id)}">${surveyIds.has(b.id) ? '<p class="survey-loading">📝 설문 불러오는 중…</p>' : ''}</div>

    <div class="modal-btns">
      <button class="btn-primary" id="mEdit">수정</button>
      <button class="btn-kakao" id="mKakao" disabled>카카오 전송</button>
    </div>
    <p class="kakao-hint">※ 카카오 알림톡은 비즈니스 인증·템플릿 승인 후 연결됩니다.</p>`;

  $('modalClose').addEventListener('click', closeModal);
  $('mEdit').addEventListener('click', () => renderEdit(b));

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
    <div class="edit-opts">
      <label class="eopt"><input type="checkbox" id="e_basic" data-price="55" ${ck(b.package)} /><span>베이직 (데이터형)</span><b>55만원</b></label>
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
        <option value="대표지정" data-price="35" ${sl(b.photographer, '대표지정')}>대표지정 (+35만원)</option>
      </select>
    </div>
    <label class="eopt" style="margin-top:8px"><input type="checkbox" id="e_usage" data-price="-1" ${ck(b.photo_usage_agree)} /><span>촬영본 사용동의 (YES)</span><b>-1만원</b></label>

    <h5 class="eg">확인사항</h5>
    <label class="eopt"><input type="checkbox" id="e_agree_available" ${ck(b.agree_available)} /><span>예약가능 답변 확인</span><b></b></label>
    <label class="eopt"><input type="checkbox" id="e_agree_terms" ${ck(b.agree_terms)} /><span>규정 동의</span><b></b></label>

    <div class="bk-total" style="margin-top:16px"><span>합계</span><strong id="eTotal">${won(b.total_price)}</strong></div>

    <div class="row-2" style="margin-top:14px">
      <div class="field"><label>상태</label>
        <select id="mStatus">
          <option value="신규" ${sl(b.status, '신규')}>신규</option>
          <option value="확인" ${sl(b.status, '확인')}>확인</option>
          <option value="전송완료" ${sl(b.status, '전송완료')}>전송완료</option>
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
    const ph = $('e_photographer').selectedOptions[0];
    if (ph) sum += Number(ph.dataset.price) || 0;
    $('eTotal').textContent = sum.toLocaleString('ko-KR') + '만원';
    return sum;
  };
  $('modalCard').addEventListener('change', recalcEdit);
  recalcEdit();

  $('modalClose').addEventListener('click', closeModal);
  $('mCancel').addEventListener('click', () => renderView(b));
  $('mSave').addEventListener('click', () => saveDetail(b.id, recalcEdit));
}

function closeModal() {
  $('modal').hidden = true;
}
$('modalBackdrop').addEventListener('click', closeModal);

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
    basic: cc('e_basic'),
    travel_fee: cc('e_travel'),
    option_album: cc('e_option_album'),
    option_reception: cc('e_option_reception'),
    option_pyebaek: cc('e_option_pyebaek'),
    option_part2: cc('e_option_part2'),
    photographer: $('e_photographer').value,
    photo_usage_agree: cc('e_usage'),
    agree_available: cc('e_agree_available'),
    agree_terms: cc('e_agree_terms'),
    total_price: recalcEdit(),
  };
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

// 알림톡 발송 (솔라피 연동 전: 안내만)
function sendAlimtalk(id, tpl) {
  toast('카카오 알림톡은 솔라피 연동(자격증명 등록) 후 실제 발송됩니다.');
}

function renderDashboard() {
  if (!$('tab-dashboard')) return;
  const today = startOfToday();

  // 🔔 신규 예약
  const news = allBookings.filter((b) => b.status === '신규')
    .sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  $('dcNew').textContent = news.length;
  $('listNew').innerHTML = news.length
    ? news.slice(0, 40).map((b) => `
      <div class="dl-item" data-id="${b.id}">
        <div class="dl-main">
          <span class="dl-name">${esc(b.contractor_name || '-')}</span>
          <span class="dl-meta">${esc(fmtDate(b.wedding_date))} · ${esc(b.wedding_venue || '-')} · ${esc(won(b.total_price))}</span>
        </div>
        <div class="dl-actions">
          <button class="btn-sm btn-kakao-sm" data-send="${b.id}" data-tpl="A">계약안내 전송</button>
        </div>
      </div>`).join('')
    : '<p class="dash-empty">새 예약이 없어요.</p>';

  // 📅 이번 주 예식 (오늘 ~ 이번 주 토요일)
  const endOfWeek = new Date(today); endOfWeek.setDate(endOfWeek.getDate() + (6 - today.getDay()));
  const thisWeek = allBookings.filter((b) => { const d = wDate(b); return d && d >= today && d <= endOfWeek; })
    .sort((a, b) => wDate(a) - wDate(b));
  $('dcUpcoming').textContent = thisWeek.length;
  $('listUpcoming').innerHTML = thisWeek.length
    ? thisWeek.map((b) => {
      const d = wDate(b);
      const dleft = Math.round((d - today) / 86400000);
      const dtag = dleft === 0 ? '오늘' : 'D-' + dleft;
      return `
      <div class="dl-item soon" data-id="${b.id}">
        <div class="dl-main">
          <span class="dl-name">${esc(b.contractor_name || '-')} <span class="dday">${dtag}</span></span>
          <span class="dl-meta">${esc(fmtDate(b.wedding_date))} ${esc(kTimeShort(b.wedding_time))} · ${esc(b.wedding_venue || '-')}</span>
        </div>
      </div>`;
    }).join('')
    : '<p class="dash-empty">이번 주 예식이 없어요.</p>';

  // ⬇️ 다운로드 링크 필요 (예식 지남 + E 미발송)
  const needDl = allBookings.filter((b) => { const d = wDate(b); return d && d < today && !(b.alimtalk_sent && b.alimtalk_sent.E); })
    .sort((a, b) => wDate(b) - wDate(a));
  $('dcDownload').textContent = needDl.length;
  $('listDownload').innerHTML = needDl.length
    ? needDl.slice(0, 40).map((b) => `
      <div class="dl-item dl-download" data-id="${b.id}">
        <div class="dl-main">
          <span class="dl-name">${esc(b.contractor_name || '-')}</span>
          <span class="dl-meta">${esc(fmtDate(b.wedding_date))} · ${esc(b.wedding_venue || '-')}</span>
        </div>
        <div class="dl-dlrow">
          <input type="text" class="dl-link" data-id="${b.id}" placeholder="다운로드 링크 붙여넣기" value="${esc(b.download_link || '')}" />
          <button class="btn-sm dl-save" data-id="${b.id}">저장</button>
          <button class="btn-sm btn-kakao-sm" data-send="${b.id}" data-tpl="E">카톡 전송</button>
        </div>
      </div>`).join('')
    : '<p class="dash-empty">모두 처리됐어요 👍</p>';

  bindDashEvents();
  renderCalendar();
}

function bindDashEvents() {
  // 항목(이름/메타) 클릭 → 상세
  document.querySelectorAll('#tab-dashboard .dl-main').forEach((m) =>
    m.addEventListener('click', () => openDetail(m.closest('.dl-item').dataset.id))
  );
  // 카톡 전송
  document.querySelectorAll('#tab-dashboard [data-send]').forEach((btn) =>
    btn.addEventListener('click', (e) => { e.stopPropagation(); sendAlimtalk(btn.dataset.send, btn.dataset.tpl); })
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
    if (d && d.getFullYear() === y && d.getMonth() === m) (byDay[d.getDate()] = byDay[d.getDate()] || []).push(b);
  });

  let html = '<div class="cal-grid">';
  ['일', '월', '화', '수', '목', '금', '토'].forEach((w) => (html += `<div class="cal-wd">${w}</div>`));
  for (let i = 0; i < startDay; i++) html += '<div class="cal-cell empty"></div>';
  for (let dnum = 1; dnum <= days; dnum++) {
    const items = (byDay[dnum] || []).sort((a, b) => (a.wedding_time || '').localeCompare(b.wedding_time || ''));
    const isToday = today.getFullYear() === y && today.getMonth() === m && today.getDate() === dnum;
    html += `<div class="cal-cell${isToday ? ' today' : ''}${items.length ? ' has' : ''}">
      <span class="cal-d">${dnum}</span>
      ${items.slice(0, 3).map((b) => `<span class="cal-ev" data-id="${b.id}" title="${esc((b.contractor_name || '') + ' ' + (b.wedding_venue || ''))}">${esc(kTimeShort(b.wedding_time))} ${esc(b.contractor_name || '')}</span>`).join('')}
      ${items.length > 3 ? `<span class="cal-more">+${items.length - 3}</span>` : ''}
    </div>`;
  }
  html += '</div>';
  $('calendar').innerHTML = html;
  $('calendar').querySelectorAll('.cal-ev').forEach((e) =>
    e.addEventListener('click', () => openDetail(e.dataset.id))
  );
}

if ($('calPrev')) {
  $('calPrev').addEventListener('click', () => { calMonth.m--; if (calMonth.m < 0) { calMonth.m = 11; calMonth.y--; } renderCalendar(); });
  $('calNext').addEventListener('click', () => { calMonth.m++; if (calMonth.m > 11) { calMonth.m = 0; calMonth.y++; } renderCalendar(); });
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
    $('tab-gallery').hidden = tab !== 'gallery';
    if (tab === 'dashboard') renderDashboard();
    if (tab === 'gallery') loadGallery();
  });
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
