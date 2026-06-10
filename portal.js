/* ===== 예약 전용 포털 (내 예약 확인하기) ===== */
const sb =
  window.supabase && window.OTB_CONFIG
    ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
    : null;

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const bookingId = params.get('b');
const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// TODO: 실제 입금 계좌로 교체 (관리자 확인 후)
const ACCOUNT = { bank: '국민은행', number: '000000-00-000000', holder: '온더브라이드' };

const loadCard = $('loadCard');
const errCard = $('errCard');
const portalMain = $('portalMain');
const show = (el) => { [loadCard, errCard, portalMain].forEach((x) => (x.hidden = x !== el)); };

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const won = (n) => (n == null ? '-' : Number(n).toLocaleString('ko-KR') + '만원');
const fmtDate = (d) => {
  if (!d) return '-';
  const dt = new Date(d + 'T00:00:00');
  if (isNaN(dt)) return d;
  const wd = ['일', '월', '화', '수', '목', '금', '토'][dt.getDay()];
  return `${dt.getFullYear()}. ${dt.getMonth() + 1}. ${dt.getDate()}. (${wd})`;
};

let info = null;
const isDemo = params.get('demo') === '1';

const DEMO_INFO = {
  contractor_name: '홍길동', wedding_date: '2026-09-12', wedding_time: '오후 1:30',
  wedding_venue: '아펠가모 선릉', package: '베이직(데이터형)',
  options_text: '베이직 (55)\n\n옵션1\n폐백촬영 (10)\n\n옵션2\n2인 촬영 (25)',
  total_price: 90, deposit: 10, balance: 80, deposit_paid: false, balance_paid: false,
  status: '신규', survey_done: false, buddy: { state: 'none' }, review: null,
};

async function load() {
  if (isDemo) { info = DEMO_INFO; render(); show(portalMain); return; }
  if (!sb || !bookingId || !uuidRe.test(bookingId)) { show(errCard); return; }
  const { data, error } = await sb.rpc('portal_booking_info', { p_booking_id: bookingId });
  if (error || !data) { show(errCard); return; }
  info = data;
  render();
  show(portalMain);
}

function render() {
  $('greet').innerHTML = `<b>${esc(info.contractor_name || '')}</b>님, 예약 내용을 확인하세요.`;

  // 예약 정보
  const statusBadge = info.status === '확정'
    ? '<span class="pt-badge ok">확정</span>'
    : `<span class="pt-badge wait">${esc(info.status || '신규')}</span>`;
  $('infoList').innerHTML = `
    <dt>예식일</dt><dd>${esc(fmtDate(info.wedding_date))}</dd>
    <dt>예식시간</dt><dd>${esc(info.wedding_time || '-')}</dd>
    <dt>예식장</dt><dd>${esc(info.wedding_venue || '-')}</dd>
    <dt>예약상태</dt><dd>${statusBadge}</dd>`;

  // 상품 / 옵션
  $('optionsBox').textContent = info.options_text || (info.package || '-');
  const depBadge = info.deposit_paid ? '<span class="pt-badge ok">입금완료</span>' : '<span class="pt-badge wait">입금 전</span>';
  const balBadge = info.balance_paid ? '<span class="pt-badge ok">입금완료</span>' : '<span class="pt-badge wait">입금 전</span>';
  $('amountBox').innerHTML = `
    <div class="pt-amount-row"><span class="lbl">계약금</span><span>${won(info.deposit)} ${depBadge}</span></div>
    <div class="pt-amount-row"><span class="lbl">잔금</span><span>${won(info.balance)} ${balBadge}</span></div>
    <div class="pt-amount-row total"><span class="lbl">총 금액</span><span>${won(info.total_price)}</span></div>`;

  // 계좌
  $('accountBox').innerHTML = `
    <p class="bank">${esc(ACCOUNT.bank)}</p>
    <p class="acc">${esc(ACCOUNT.number)}</p>
    <p class="holder">예금주 ${esc(ACCOUNT.holder)}</p>
    <button type="button" class="pt-copy" id="copyAcc">계좌번호 복사</button>`;
  $('copyAcc').addEventListener('click', () => {
    navigator.clipboard?.writeText(ACCOUNT.number.replace(/[^0-9]/g, ''));
    $('copyAcc').textContent = '복사됐어요 ✓';
    setTimeout(() => ($('copyAcc').textContent = '계좌번호 복사'), 1500);
  });

  // 진행 안내
  const steps = [
    ['계약금 입금', '안내드린 계좌로 계약금을 입금하시면 예약이 확정됩니다.'],
    ['예식 전 설문 작성', '촬영 전 원하시는 장면·요청사항을 미리 알려주세요.'],
    ['예식 주 스케줄 확인 · 잔금', '예식이 있는 주에 담당 작가와 스케줄을 확인하고 잔금을 입금합니다.'],
    ['예식 당일 촬영', '담당 작가가 예식 1시간 30분 전 도착해 촬영합니다.'],
    ['셀렉 · 보정 · 데이터 전달', '촬영 후 약 일주일 내 다운로드 링크를 보내드립니다. (앨범 신청 시 별도 제작)'],
  ];
  $('stepsBox').innerHTML = steps.map(([t, d]) => `<li><span class="st">${t}</span><span class="sd">${d}</span></li>`).join('');

  // 설문
  const surveyBtn = $('surveyBtn');
  surveyBtn.href = `survey?b=${bookingId}`;
  if (info.survey_done) {
    $('surveyDesc').innerHTML = '설문을 작성해 주셔서 감사합니다 🤍 내용은 언제든 수정할 수 있어요.';
    surveyBtn.textContent = '설문 수정하기';
    surveyBtn.classList.add('ghost');
  }

  renderBuddy();
  renderReview();
}

/* ===== 짝꿍 ===== */
function renderBuddy() {
  const b = info.buddy || { state: 'none' };
  const box = $('buddyBody');
  if (b.state === 'sent_waiting') {
    box.innerHTML = `<div class="pt-state wait"><b>${esc(b.partner_name || '상대')}</b>님께 짝꿍 신청을 보냈어요.<br>상대가 확인하면 매칭됩니다.</div>`;
  } else if (b.state === 'incoming_confirm') {
    box.innerHTML = `
      <div class="pt-state"><b>${esc(b.partner_name || '상대')}</b>님이 회원님을 짝꿍으로 등록했어요!<br>맞으면 아래에서 확인해 주세요.</div>
      <div class="pt-confirm-actions">
        <button type="button" class="pt-btn" id="buddyYes">맞아요, 확인</button>
        <button type="button" class="pt-btn ghost" id="buddyNo">아니에요</button>
      </div>
      <p class="pt-status" id="buddyConfirmStatus"></p>`;
    $('buddyYes').addEventListener('click', () => confirmBuddy(b.id, true));
    $('buddyNo').addEventListener('click', () => confirmBuddy(b.id, false));
  } else if (b.state === 'matched') {
    box.innerHTML = `<div class="pt-state wait">짝꿍 매칭 완료! <b>관리자 승인</b>을 기다리고 있어요.</div>`;
  } else if (b.state === 'approved') {
    box.innerHTML = `<div class="pt-state good">🎉 짝꿍 이벤트 참여 완료! (${esc(b.reward || '보상 선택')})</div>`;
  } else {
    // none → 등록 폼
    box.innerHTML = `
      <div class="pt-form">
        <div class="pt-row2">
          <div class="pt-field"><label>상대 예식일</label><input type="date" id="bd_date" /></div>
          <div class="pt-field"><label>상대 계약자명</label><input type="text" id="bd_name" placeholder="예) 홍길동" /></div>
        </div>
        <div class="pt-field"><label>받을 혜택</label>
          <select id="bd_reward"><option value="할인">1만원 할인</option><option value="앨범">앨범 1권 추가</option></select>
        </div>
        <button type="button" class="pt-btn full" id="bd_submit">짝꿍 등록하기</button>
        <p class="pt-status" id="bd_status"></p>
      </div>`;
    $('bd_submit').addEventListener('click', registerBuddy);
  }
}

async function registerBuddy() {
  const date = $('bd_date').value;
  const name = $('bd_name').value.trim();
  const reward = $('bd_reward').value;
  const st = $('bd_status');
  st.className = 'pt-status';
  if (!date || !name) { st.className = 'pt-status err'; st.textContent = '상대 예식일과 계약자명을 입력해주세요.'; return; }
  $('bd_submit').disabled = true; st.textContent = '등록 중…';
  const { error } = await sb.rpc('buddy_register', { p_requester: bookingId, p_partner_name: name, p_partner_date: date, p_reward: reward });
  if (error) { st.className = 'pt-status err'; st.textContent = error.message.replace(/^.*?:\s*/, ''); $('bd_submit').disabled = false; return; }
  await reload();
}

async function confirmBuddy(id, accept) {
  const st = $('buddyConfirmStatus');
  st.className = 'pt-status'; st.textContent = '처리 중…';
  const { error } = await sb.rpc('buddy_confirm', { p_buddy_id: id, p_booking: bookingId, p_accept: accept });
  if (error) { st.className = 'pt-status err'; st.textContent = error.message.replace(/^.*?:\s*/, ''); return; }
  await reload();
}

/* ===== 후기 ===== */
function renderReview() {
  const r = info.review;
  const box = $('reviewBody');
  if (r && r.status === 'approved') {
    box.innerHTML = `<div class="pt-state good">🎉 후기 이벤트 참여 완료! (${esc(r.reward || '보상 선택')})</div>`;
    return;
  }
  const pending = r && r.status === 'pending';
  const rejected = r && r.status === 'rejected';
  box.innerHTML = `
    ${pending ? '<div class="pt-state wait">후기를 접수했어요. <b>관리자 확인</b> 후 적용됩니다. 아래에서 수정할 수 있어요.</div>' : ''}
    ${rejected ? '<div class="pt-state wait">후기가 반려되었어요. 링크를 확인 후 다시 등록해 주세요.</div>' : ''}
    <div class="pt-form" style="margin-top:${pending || rejected ? '10px' : '0'}">
      <div class="pt-field"><label>후기 링크</label><input type="url" id="rv_link" placeholder="https://..." value="${esc(r?.link || '')}" /></div>
      <div class="pt-field"><label>받을 혜택</label>
        <select id="rv_reward">
          <option value="할인"${r?.reward === '할인' ? ' selected' : ''}>1만원 할인</option>
          <option value="앨범"${r?.reward === '앨범' ? ' selected' : ''}>앨범 1권 추가</option>
        </select>
      </div>
      <button type="button" class="pt-btn full" id="rv_submit">${pending ? '후기 수정하기' : '후기 등록하기'}</button>
      <p class="pt-status" id="rv_status"></p>
    </div>`;
  $('rv_submit').addEventListener('click', registerReview);
}

async function registerReview() {
  const link = $('rv_link').value.trim();
  const reward = $('rv_reward').value;
  const st = $('rv_status');
  st.className = 'pt-status';
  if (!link) { st.className = 'pt-status err'; st.textContent = '후기 링크를 입력해주세요.'; return; }
  $('rv_submit').disabled = true; st.textContent = '등록 중…';
  const { error } = await sb.rpc('review_register', { p_booking: bookingId, p_link: link, p_reward: reward });
  if (error) { st.className = 'pt-status err'; st.textContent = error.message.replace(/^.*?:\s*/, ''); $('rv_submit').disabled = false; return; }
  await reload();
}

async function reload() {
  const { data } = await sb.rpc('portal_booking_info', { p_booking_id: bookingId });
  if (data) { info = data; render(); }
}

load();
