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
  render();
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

  const rows = allBookings.filter((b) => filter === '전체' || b.status === filter);
  $('emptyMsg').hidden = rows.length > 0;

  $('bkRows').innerHTML = rows
    .map(
      (b) => `<tr data-id="${b.id}">
        <td>${esc(fmtDateTime(b.created_at))}</td>
        <td>${esc(b.contractor_name || '-')}</td>
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

function openDetail(id) {
  const b = allBookings.find((x) => x.id === id);
  if (!b) return;
  const v = (s) => esc(s == null ? '' : s);
  const dval = (s) => (s ? esc(String(s).slice(0, 10)) : '');
  const ck = (c) => (c ? 'checked' : '');
  const sl = (a, bb) => (a === bb ? 'selected' : '');

  $('modalCard').innerHTML = `
    <button class="modal-close" id="modalClose">&times;</button>
    <p class="modal-title">예약 상세 · 수정</p>
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
      <button class="btn-primary" id="mSave">저장</button>
      <button class="btn-kakao" id="mKakao" disabled>카카오 전송</button>
    </div>
    <p class="kakao-hint">※ 카카오 알림톡은 비즈니스 인증·템플릿 승인 후 연결됩니다.</p>
    <p class="save-msg" id="mMsg"></p>`;

  $('modal').hidden = false;

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
  msg.className = 'save-msg ok';
  msg.textContent = '저장되었습니다.';
}
