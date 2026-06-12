/* ===== 예약 전용 포털 (내 예약 확인하기) ===== */
const sb =
  window.supabase && window.OTB_CONFIG
    ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
    : null;

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const bookingId = params.get('b');
const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const ACCOUNT = { bank: '카카오뱅크', number: '3333-01-3327565', holder: '김병훈' };

// 상품/옵션 설명 카탈로그 (상품 변경 시 여기만 고치면 됨)
const PRODUCT_DESC = {
  '베이직': ['예식 1시간 30분 전, 신부대기실부터 원판촬영까지', '40장 디테일 보정', '원본 제공'],
  '스페셜': ['예식 1시간 30분 전, 신부대기실부터 원판촬영까지', '40장 디테일 보정', '원본 제공', '앨범 1권 포함'],
};
const OPTION_DESC = {
  '폐백촬영': '환복 후 기념사진 · 폐백 진행 장면 촬영',
  '연회장 인사촬영': '연회장에서 하객 인사 촬영 (최대 30분)',
  '2부 촬영': '2부 행사 현장 촬영',
  '2인 촬영': '작가 2명이 동시에 촬영',
  '대표지정': '대표 작가 지정 촬영',
  '앨범 1권 추가': '추가 앨범 제작 1권',
  '출장비': '촬영 출장 비용',
};
const productDesc = (name) => {
  const key = Object.keys(PRODUCT_DESC).find((k) => String(name).startsWith(k));
  return key ? PRODUCT_DESC[key] : [];
};

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
  items: [
    { group: '상품', name: '베이직', price: 55 },
    { group: '옵션', name: '폐백촬영', price: 10 },
    { group: '옵션', name: '2인 촬영', price: 25 },
  ],
  total_price: 90, effective_total: 89, discount: 1,
  event_rewards: [{ type: '짝꿍', reward: '할인' }, { type: '후기', reward: '앨범' }],
  deposit: 10, balance: 79, deposit_paid: true, balance_paid: true,
  download_ready: true, download_link: 'https://example.com/download',
  status: '확정', survey_done: true,
  photographer: { reveal: true, main_name: '김병훈', main_phone: '010-1234-5678', sub_name: '양재훈', sub_phone: '010-8765-4321' },
  buddy: { state: 'approved', partner_name: '김철수', reward: '할인', my_role: 'requester', id: 'demo' },
  review: { link: 'https://blog.naver.com/example', reward: '앨범', status: 'approved' },
};

const rewardSelect = (id, val) => `<select id="${id}" class="pt-reward-sel">
  <option value="할인"${val === '할인' ? ' selected' : ''}>1만원 할인</option>
  <option value="앨범"${val === '앨범' ? ' selected' : ''}>앨범 1권</option>
</select>`;

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
  // 담당 작가 (예식 일주일 전부터 공개)
  const ph = info.photographer || {};
  let photogHtml;
  const photogLine = (role, name, phone) =>
    `<span class="pt-photog-line"><b>${role}</b> ${esc(name)}${phone ? ` <a class="pt-photog-tel" href="tel:${esc(phone)}">${esc(phone)}</a>` : ''}</span>`;
  if (!ph.reveal) {
    photogHtml = '<span class="pt-photog-soon">예식 일주일 전 공개</span>';
  } else if (ph.main_name) {
    photogHtml = photogLine('메인', ph.main_name, ph.main_phone)
      + (ph.sub_name ? photogLine('서브', ph.sub_name, ph.sub_phone) : '');
  } else {
    photogHtml = '<span class="pt-photog-soon">배정 중</span>';
  }
  $('infoList').innerHTML = `
    <dt>예식일</dt><dd>${esc(fmtDate(info.wedding_date))}</dd>
    <dt>예식시간</dt><dd>${esc(info.wedding_time || '-')}</dd>
    <dt>예식장</dt><dd>${esc(info.wedding_venue || '-')}</dd>
    <dt>담당작가</dt><dd>${photogHtml}</dd>
    <dt>예약상태</dt><dd>${statusBadge}</dd>`;

  // 상품 / 옵션 (구조화)
  const items = Array.isArray(info.items) ? info.items : [];
  const products = items.filter((it) => it.group === '상품');
  const options = items.filter((it) => it.group === '옵션');
  const mainName = (products[0] && products[0].name) || info.package || '상품';
  const descLis = productDesc(mainName).map((d) => `<li>${esc(d)}</li>`).join('');
  // 베이직/스페셜 본상품 + (출장비 등 '상품'그룹 부가)
  const productExtra = products.slice(1).map((p) =>
    `<div class="pt-opt-row"><div class="pt-opt-info"><span class="nm">${esc(p.name)}</span></div><span class="pt-opt-price">${won(p.price)}</span></div>`).join('');
  $('productBox').innerHTML = `
    <div class="pt-product">
      <div class="pt-product-top"><span class="pt-product-name">${esc(mainName)}</span><span class="pt-product-price">${won(products[0] ? products[0].price : null)}</span></div>
      ${descLis ? `<ul class="pt-product-desc">${descLis}</ul>` : ''}
    </div>
    ${productExtra ? `<div class="pt-optgroup-label">포함</div>${productExtra}` : ''}`;
  const optRows = options.map((o) => {
    const ds = OPTION_DESC[o.name] ? `<span class="ds">${esc(OPTION_DESC[o.name])}</span>` : '';
    return `<div class="pt-opt-row"><div class="pt-opt-info"><span class="nm">${esc(o.name)}</span>${ds}</div><span class="pt-opt-price">${won(o.price)}</span></div>`;
  }).join('');
  // 승인된 이벤트 혜택을 옵션처럼 표시 (할인=−n만원, 앨범=무료)
  const rewards = Array.isArray(info.event_rewards) ? info.event_rewards : [];
  const rewardRows = rewards.map((r) => {
    const isDc = r.reward === '할인';
    const nm = `${esc(r.type)} 이벤트 ${isDc ? '할인' : '앨범 1권'}`;
    const price = isDc ? '−1만원' : '무료';
    return `<div class="pt-opt-row"><div class="pt-opt-info"><span class="nm">🎉 ${nm}</span></div><span class="pt-opt-price ${isDc ? 'minus' : 'free'}">${price}</span></div>`;
  }).join('');
  $('optionsWrap').innerHTML =
    (options.length ? `<div class="pt-optgroup-label">추가 옵션</div>${optRows}` : '') +
    (rewardRows ? `<div class="pt-optgroup-label">이벤트 혜택</div>${rewardRows}` : '');

  const depBadge = info.deposit_paid ? '<span class="pt-badge ok">입금완료</span>' : '<span class="pt-badge wait">입금 전</span>';
  const balBadge = info.balance_paid ? '<span class="pt-badge ok">입금완료</span>' : '<span class="pt-badge wait">입금 전</span>';
  const discount = info.discount || 0;
  $('amountBox').innerHTML = `
    <div class="pt-amount-row"><span class="lbl">계약금</span><span>${won(info.deposit)} ${depBadge}</span></div>
    <div class="pt-amount-row"><span class="lbl">잔금</span><span>${won(info.balance)} ${balBadge}</span></div>
    ${discount > 0 ? `<div class="pt-amount-row"><span class="lbl">이벤트 할인</span><span class="pt-discount">−${discount}만원</span></div>` : ''}
    <div class="pt-amount-row total"><span class="lbl">총 금액</span><span>${won(info.effective_total != null ? info.effective_total : info.total_price)}</span></div>`;

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
    ['예식 전 스케줄 확인 · 잔금', '예식 일주일 전 최종 스케줄 체크 안내를 보내드립니다. 확인 후 잔금 결제 해주시면 됩니다.'],
    ['예식 당일 촬영', '담당 작가가 예식 1시간 30분 전 도착해 촬영합니다.'],
    ['셀렉 · 보정 · 데이터 전달', '촬영 후 약 일주일 내 다운로드 링크를 보내드립니다.'],
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

  renderDownload();
  renderBuddy();
  renderReview();
}

/* ===== 원본파일 다운로드 (잔금 입금 확인 시 활성화) ===== */
function renderDownload() {
  const box = $('downloadBox');
  const notes = `<ul class="pt-dl-notes">
    <li>링크는 <b>4주간</b> 유효합니다.</li>
    <li>원본은 <b>1회 더</b> 재공유해 드립니다.</li>
    <li>다운로드가 안 되시면 USB 구매로 받으셔야 합니다! (10만원)</li>
    <li>원본은 작업 여부와 상관없이 <b>14개월 이후</b> 사전 안내 없이 서버에서 삭제됩니다.</li>
  </ul>`;
  const selectLink = `<a class="pt-btn ghost full" href="select-guide" target="_blank" rel="noopener" style="margin-top:10px">📖 셀렉 안내 보기</a>`;
  const ready = !!(info.download_ready && info.download_link);
  if (ready) {
    box.innerHTML = `
      <p class="pt-sub">촬영본 원본파일이 준비됐어요! 아래에서 다운로드하세요. 🤍</p>
      <a class="pt-btn full" href="${esc(info.download_link)}" target="_blank" rel="noopener">원본파일 다운로드</a>
      ${notes}${selectLink}`;
  } else if (info.balance_paid) {
    box.innerHTML = `<div class="pt-locked">
      <span class="pt-lock-ico">🎞️</span>
      <p>촬영 후 원본이 준비되면<br>이곳에서 바로 받으실 수 있어요.</p></div>${selectLink}`;
  } else {
    box.innerHTML = `<div class="pt-locked">
      <span class="pt-lock-ico">🔒</span>
      <p><b>잔금 입금이 확인되면</b> 원본 다운로드가 열려요.</p></div>${selectLink}`;
  }
  // 링크 올라오면 다운로드 박스를 최상단으로
  const card = document.getElementById('downloadCard');
  if (card) card.classList.toggle('dl-top', ready);
}

/* ===== 짝꿍 ===== */
function renderBuddy() {
  const b = info.buddy || { state: 'none' };
  const box = $('buddyBody');
  // 내 혜택 선택 줄 (승인 후에도 변경 가능)
  const rewardRow = `<div class="pt-reward-row"><span class="pt-reward-lbl">내 혜택</span>${rewardSelect('bd_reward_sel', b.reward)}</div>`;
  if (b.state === 'sent_waiting') {
    box.innerHTML = `<div class="pt-state wait"><b>${esc(b.partner_name || '상대')}</b>님께 짝꿍 신청을 보냈어요.<br>상대가 확인하면 매칭됩니다.</div>${rewardRow}`;
    bindBuddyReward();
  } else if (b.state === 'incoming_confirm') {
    box.innerHTML = `
      <div class="pt-state"><b>${esc(b.partner_name || '상대')}</b>님이 회원님을 짝꿍으로 등록했어요!<br>맞으면 받을 혜택을 고르고 확인해 주세요.</div>
      <div class="pt-reward-row"><span class="pt-reward-lbl">받을 혜택</span>${rewardSelect('bd_confirm_reward', b.reward)}</div>
      <div class="pt-confirm-actions">
        <button type="button" class="pt-btn" id="buddyYes">맞아요, 확인</button>
        <button type="button" class="pt-btn ghost" id="buddyNo">아니에요</button>
      </div>
      <p class="pt-status" id="buddyConfirmStatus"></p>`;
    $('buddyYes').addEventListener('click', () => confirmBuddy(b.id, true, $('bd_confirm_reward').value));
    $('buddyNo').addEventListener('click', () => confirmBuddy(b.id, false));
  } else if (b.state === 'matched') {
    box.innerHTML = `<div class="pt-state wait">짝꿍 매칭 완료! <b>관리자 승인</b>을 기다리고 있어요.</div>${rewardRow}`;
    bindBuddyReward();
  } else if (b.state === 'approved') {
    box.innerHTML = `<div class="pt-state good">🎉 짝꿍 이벤트 참여 완료!</div>${rewardRow}`;
    bindBuddyReward();
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

function bindBuddyReward() {
  const sel = $('bd_reward_sel');
  if (sel) sel.addEventListener('change', () => setBuddyReward(sel.value));
}

async function setBuddyReward(reward) {
  const { error } = await sb.rpc('buddy_set_reward', { p_booking: bookingId, p_reward: reward });
  if (error) { alert('혜택 변경 실패: ' + error.message); return; }
  await reload();
}

async function confirmBuddy(id, accept, reward) {
  const st = $('buddyConfirmStatus');
  st.className = 'pt-status'; st.textContent = '처리 중…';
  const { error } = await sb.rpc('buddy_confirm', { p_buddy_id: id, p_booking: bookingId, p_accept: accept, p_reward: reward || null });
  if (error) { st.className = 'pt-status err'; st.textContent = error.message.replace(/^.*?:\s*/, ''); return; }
  await reload();
}

/* ===== 후기 ===== */
function renderReview() {
  const r = info.review;
  const box = $('reviewBody');
  if (r && r.status === 'approved') {
    box.innerHTML = `<div class="pt-state good">🎉 후기 이벤트 참여 완료!</div>
      <div class="pt-reward-row"><span class="pt-reward-lbl">내 혜택</span>${rewardSelect('rv_reward_sel', r.reward)}</div>`;
    $('rv_reward_sel').addEventListener('change', () => setReviewReward($('rv_reward_sel').value));
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

async function setReviewReward(reward) {
  const { error } = await sb.rpc('review_set_reward', { p_booking: bookingId, p_reward: reward });
  if (error) { alert('혜택 변경 실패: ' + error.message); return; }
  await reload();
}

async function reload() {
  const { data } = await sb.rpc('portal_booking_info', { p_booking_id: bookingId });
  if (data) { info = data; render(); }
}

load();
