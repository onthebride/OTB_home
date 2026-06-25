// Hero — 새로고침마다 랜덤 배경 사진
const heroBg = document.querySelector('.hero-bg');
if (heroBg) {
  const heroImgs = Array.from({ length: 12 }, (_, i) => 'assets/hero/hero' + (i + 1) + '.jpg');
  heroBg.style.backgroundImage = `url("${heroImgs[Math.floor(Math.random() * heroImgs.length)]}")`;
}

// About story — 마침표(.) 뒤 줄바꿈으로 문장마다 줄을 나눔
document.querySelectorAll('.story p').forEach((p) => {
  p.innerHTML = p.innerHTML.replace(/\.\s+/g, '.<br>');
});

// Header background on scroll
const header = document.querySelector('.site-header');
const toTop = document.getElementById('toTop');
const onScroll = () => {
  header.classList.toggle('scrolled', window.scrollY > 40);
  if (toTop) toTop.classList.toggle('show', window.scrollY > 500);
};
window.addEventListener('scroll', onScroll);
onScroll();
if (toTop) {
  toTop.addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'smooth' }));
}

// 로고 클릭 → 부드럽게 맨 위로
const brandLink = document.querySelector('.brand');
if (brandLink) brandLink.addEventListener('click', (e) => { e.preventDefault(); window.scrollTo({ top: 0, behavior: 'smooth' }); });

// Mobile menu toggle
const toggle = document.querySelector('.nav-toggle');
const menu = document.querySelector('.nav-menu');
toggle.addEventListener('click', () => menu.classList.toggle('open'));
menu.querySelectorAll('a').forEach((a) =>
  a.addEventListener('click', () => menu.classList.remove('open'))
);

// Rules modal (규정 전문)
const rulesModal = document.getElementById('rulesModal');
if (rulesModal) {
  const openBtn = document.getElementById('rulesOpen');
  const closeBtn = document.getElementById('rulesClose');
  const backdrop = document.getElementById('rulesBackdrop');
  const open = () => {
    rulesModal.hidden = false;
    document.body.style.overflow = 'hidden';
  };
  const close = () => {
    rulesModal.hidden = true;
    document.body.style.overflow = '';
  };
  if (openBtn) openBtn.addEventListener('click', open);
  closeBtn.addEventListener('click', close);
  backdrop.addEventListener('click', close);
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !rulesModal.hidden) close();
  });
}

// Booking — live price total
const bookingForm = document.querySelector('.booking-form');

// 예약신청 시작하기 → 폼 펼치기
const bookingStart = document.getElementById('bookingStart');
if (bookingStart && bookingForm) {
  bookingStart.addEventListener('click', () => {
    bookingForm.hidden = false;
    bookingStart.hidden = true;
    bookingForm.scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
}

// Pretty date picker (flatpickr)
let fpDate = null;
if (bookingForm && window.flatpickr) {
  fpDate = flatpickr('#f_wedding_date', {
    locale: 'ko',
    dateFormat: 'Y-m-d',
    altInput: true,
    altFormat: 'Y년 m월 d일',
    minDate: 'today',
    disableMobile: true,
  });
}

// Phone inputs — auto hyphen
const formatPhone = (raw) => {
  const d = raw.replace(/\D/g, '').slice(0, 11);
  if (d.startsWith('02')) {
    if (d.length < 3) return d;
    if (d.length < 6) return d.slice(0, 2) + '-' + d.slice(2);
    if (d.length < 10) return d.slice(0, 2) + '-' + d.slice(2, 5) + '-' + d.slice(5);
    return d.slice(0, 2) + '-' + d.slice(2, 6) + '-' + d.slice(6, 10);
  }
  if (d.length < 4) return d;
  if (d.length < 8) return d.slice(0, 3) + '-' + d.slice(3);
  if (d.length < 11) return d.slice(0, 3) + '-' + d.slice(3, 6) + '-' + d.slice(6);
  return d.slice(0, 3) + '-' + d.slice(3, 7) + '-' + d.slice(7, 11);
};
document.querySelectorAll('input.phone').forEach((el) => {
  el.addEventListener('input', () => {
    const pos = el.selectionStart === el.value.length;
    el.value = formatPhone(el.value);
    if (pos) el.setSelectionRange(el.value.length, el.value.length);
  });
});

// 계약자와 동일 — auto-fill 신랑/신부 from contractor
const sameAsResets = [];
const setupSameAs = (cbId, nameId, phoneId) => {
  const cb = document.getElementById(cbId);
  if (!cb) return;
  const nameEl = document.getElementById(nameId);
  const phoneEl = document.getElementById(phoneId);
  const apply = (locked) => {
    nameEl.readOnly = phoneEl.readOnly = locked;
    nameEl.classList.toggle('readonly', locked);
    phoneEl.classList.toggle('readonly', locked);
  };
  const sync = () => {
    if (!cb.checked) return;
    nameEl.value = document.getElementById('f_contractor_name').value;
    phoneEl.value = document.getElementById('f_contractor_phone').value;
  };
  cb.addEventListener('change', () => { apply(cb.checked); sync(); });
  document.getElementById('f_contractor_name').addEventListener('input', sync);
  document.getElementById('f_contractor_phone').addEventListener('input', sync);
  apply(cb.checked); // 초기/복원 상태 동기화
  sameAsResets.push(() => { cb.checked = false; apply(false); });
};
setupSameAs('f_groom_same', 'f_groom_name', 'f_groom_phone');
setupSameAs('f_bride_same', 'f_bride_name', 'f_bride_phone');
// 폼 리셋 시 신랑/신부 잠금 해제
const resetSameAs = () => sameAsResets.forEach((fn) => fn());

// Time — custom picker: 오전/오후 클릭 + 시/분 스크롤 선택
let tpReset = () => {};
const tpDisplay = document.getElementById('tpDisplay');
if (tpDisplay) {
  const tpInput = document.getElementById('f_wedding_time');
  const tpPanel = document.getElementById('tpPanel');
  const tpHours = document.getElementById('tpHours');
  const tpMins = document.getElementById('tpMins');
  const tpConfirm = document.getElementById('tpConfirm');
  const ampmBtns = Array.from(tpPanel.querySelectorAll('.tp-ampm-btn'));
  const state = { ampm: null, hour: null, min: null };

  for (let h = 1; h <= 12; h++) {
    const o = document.createElement('div');
    o.className = 'tp-opt';
    o.dataset.hour = h;
    o.textContent = h + '시';
    tpHours.appendChild(o);
  }
  for (let m = 0; m < 60; m += 5) {
    const mm = String(m).padStart(2, '0');
    const o = document.createElement('div');
    o.className = 'tp-opt';
    o.dataset.min = mm;
    o.textContent = mm + '분';
    tpMins.appendChild(o);
  }

  const updateDisplay = () => {
    if (state.ampm && state.hour != null && state.min != null) {
      tpDisplay.textContent = (state.ampm === 'AM' ? '오전' : '오후') + ' ' + state.hour + ':' + state.min;
      tpDisplay.classList.add('has-value');
      let h24 = state.hour % 12;
      if (state.ampm === 'PM') h24 += 12;
      tpInput.value = String(h24).padStart(2, '0') + ':' + state.min;
    }
  };

  ampmBtns.forEach((btn) =>
    btn.addEventListener('click', () => {
      state.ampm = btn.dataset.ampm;
      ampmBtns.forEach((x) => x.classList.toggle('active', x === btn));
      updateDisplay();
    })
  );
  tpHours.addEventListener('click', (e) => {
    const o = e.target.closest('.tp-opt');
    if (!o) return;
    state.hour = Number(o.dataset.hour);
    tpHours.querySelectorAll('.tp-opt').forEach((x) => x.classList.toggle('active', x === o));
    updateDisplay();
  });
  tpMins.addEventListener('click', (e) => {
    const o = e.target.closest('.tp-opt');
    if (!o) return;
    state.min = o.dataset.min;
    tpMins.querySelectorAll('.tp-opt').forEach((x) => x.classList.toggle('active', x === o));
    updateDisplay();
  });

  const closePanel = () => (tpPanel.hidden = true);
  tpDisplay.addEventListener('click', () => (tpPanel.hidden = !tpPanel.hidden));
  tpConfirm.addEventListener('click', closePanel);
  document.addEventListener('click', (e) => {
    if (!document.getElementById('timepicker').contains(e.target)) closePanel();
  });

  tpReset = () => {
    state.ampm = state.hour = state.min = null;
    tpInput.value = '';
    tpDisplay.textContent = '시간을 선택하세요';
    tpDisplay.classList.remove('has-value');
    ampmBtns.forEach((x) => x.classList.remove('active'));
    tpPanel.querySelectorAll('.tp-opt.active').forEach((x) => x.classList.remove('active'));
  };
}

const calcTotal = () => {
  let sum = 0;
  bookingForm
    .querySelectorAll('input[data-price]:checked')
    .forEach((el) => (sum += Number(el.dataset.price) || 0));
  // 2인 촬영이면 출장비는 1인당 적용 → +5 (출장비 10만원)
  const tv = bookingForm.querySelector('#f_travel');
  const two = (bookingForm.querySelector('input[name="photographer"]:checked') || {}).value === '2인 촬영';
  if (tv && tv.checked && two) sum += 5;
  return sum;
};
if (bookingForm) {
  const totalEl = document.getElementById('bkTotal');
  const recalc = () => {
    totalEl.textContent = calcTotal().toLocaleString('ko-KR') + '만원';
  };
  bookingForm.addEventListener('change', recalc);
  recalc();
}

// Supabase client
const sb =
  window.supabase && window.OTB_CONFIG
    ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
    : null;

const val = (id) => {
  const el = document.getElementById(id);
  return el ? el.value.trim() : '';
};
const checked = (id) => {
  const el = document.getElementById(id);
  return el ? el.checked : false;
};
const radioVal = (name) => {
  const el = bookingForm.querySelector(`input[name="${name}"]:checked`);
  return el ? el.value : null;
};

// Booking — submit to Supabase
if (bookingForm) {
  const statusEl = document.getElementById('bkStatus');
  const submitBtn = bookingForm.querySelector('.bk-submit');
  const KAKAO_CHAT = 'http://pf.kakao.com/_pxeNAn/chat';
  let bookingDone = false; // 1차 제출 완료 여부

  const setStatus = (msg, type) => {
    statusEl.textContent = msg;
    statusEl.className = 'bk-status' + (type ? ' ' + type : '');
  };

  bookingForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    // 2차: 이미 접수됐으면 카카오톡 채팅창으로 바로 연결
    if (bookingDone) {
      window.location.href = KAKAO_CHAT;
      return;
    }

    // required fields
    const required = [
      ['f_contractor_name', '계약자 성함'],
      ['f_contractor_phone', '연락처'],
      ['f_contractor_email', '이메일'],
      ['f_wedding_date', '예식날짜'],
      ['f_wedding_time', '예식시간'],
      ['f_wedding_venue', '예식장소'],
      ['f_groom_name', '신랑님 성함'],
      ['f_groom_phone', '신랑님 연락처'],
      ['f_bride_name', '신부님 성함'],
      ['f_bride_phone', '신부님 연락처'],
    ];
    const missing = required.filter(([id]) => !val(id)).map(([, label]) => label);
    if (missing.length) {
      setStatus('필수 항목을 입력해 주세요: ' + missing.join(', '), 'error');
      return;
    }
    if (!checked('f_agree_available') || !checked('f_agree_terms')) {
      setStatus('확인사항 2개 항목에 모두 체크해 주세요.', 'error');
      return;
    }
    if (!sb) {
      setStatus('연결 설정 오류입니다. 잠시 후 다시 시도해 주세요.', 'error');
      return;
    }

    const row = {
      agree_available: checked('f_agree_available'),
      agree_terms: checked('f_agree_terms'),
      contractor_name: val('f_contractor_name'),
      contractor_phone: val('f_contractor_phone'),
      contractor_email: val('f_contractor_email'),
      wedding_date: val('f_wedding_date') || null,
      wedding_time: val('f_wedding_time'),
      wedding_venue: val('f_wedding_venue'),
      groom_name: val('f_groom_name'),
      groom_phone: val('f_groom_phone'),
      bride_name: val('f_bride_name'),
      bride_phone: val('f_bride_phone'),
      basic: checked('f_basic'),
      travel_fee: checked('f_travel'),
      option_album: checked('f_option_album'),
      option_reception: checked('f_option_reception'),
      option_pyebaek: checked('f_option_pyebaek'),
      option_part2: checked('f_option_part2'),
      photographer: radioVal('photographer') || '기본',
      rep_designation: checked('f_rep'),
      photo_usage_agree: radioVal('usage') === 'yes',
      total_price: calcTotal(),
    };

    submitBtn.disabled = true;
    setStatus('접수 중입니다...', '');

    const { error } = await sb.rpc('submit_booking', { payload: row });

    submitBtn.disabled = false;
    if (error) {
      console.error(error);
      setStatus('접수 중 오류가 발생했어요. 다시 시도하시거나 onthebride@naver.com 으로 연락 주세요.', 'error');
      return;
    }

    // 예약 내용을 계약안내서 양식으로 메일 전송 (Web3Forms)
    const w3key = window.OTB_CONFIG && window.OTB_CONFIG.WEB3FORMS_KEY;
    if (w3key) {
      const kTime = (t) => {
        if (!t) return '';
        const [hh, mm] = t.split(':').map(Number);
        return (hh < 12 ? '오전' : '오후') + ' ' + (hh % 12 === 0 ? 12 : hh % 12) + ':' + String(mm).padStart(2, '0');
      };
      const items = [];
      if (row.basic) items.push('베이직(데이터형) (49)');
      if (row.travel_fee) items.push(row.photographer === '2인 촬영' ? '출장비 (10)' : '출장비 (5)');
      if (row.option_album) items.push('앨범 1권 추가 (10)');
      if (row.option_reception) items.push('연회장 인사촬영 (5)');
      if (row.option_pyebaek) items.push('폐백촬영 (10)');
      if (row.option_part2) items.push('2부 촬영 (10)');
      if (row.photographer === '2인 촬영') items.push('2인 촬영 (25)');
      if (row.rep_designation) items.push('대표지정 (35)');

      const body = [
        '* 온더브라이드 계약안내서 *',
        '',
        '이 문자는 계약서를 대신하며 채팅창은 추후 상담 내용을 기록하는 수단이니',
        '보관 부탁드립니다.',
        '',
        '* 계약자 성함 : ' + (row.contractor_name || ''),
        '* 계약자 연락처 : ' + (row.contractor_phone || ''),
        '* 이메일 주소 : ' + (row.contractor_email || ''),
        '',
        '* 예식날짜 : ' + (row.wedding_date || ''),
        '* 예식장소 : ' + (row.wedding_venue || ''),
        '* 예식시간 : ' + kTime(row.wedding_time),
        '',
        '* 신부님 성함 : ' + (row.bride_name || ''),
        '* 신부님 연락처 : ' + (row.bride_phone || ''),
        '',
        '* 신랑님 성함 : ' + (row.groom_name || ''),
        '* 신랑님 연락처 : ' + (row.groom_phone || ''),
        '',
        '* 신청하신 상품 :',
        items.join('\n'),
        '',
        '* 포스팅 여부 :',
        row.photo_usage_agree ? 'YES' : 'NO',
        '',
        '* 총금액 : ' + row.total_price + ' 만원',
        '* 계약금 : 10 만원',
        '',
        '계약금을 48시간안에 입금 하시면 계약 확정됩니다.',
        '*입금은 반드시 계약자 성함으로 부탁드립니다',
        '',
        '카카오뱅크 / 3333-01-3327565 / 김병훈',
        '',
        '진행관련한 문의는 앞으로 이 채팅방을 이용 부탁드립니다~',
        '감사합니다!',
      ].join('\n');

      const fd = new FormData();
      fd.append('access_key', w3key);
      fd.append('subject', (row.contractor_name || '') + ' / ' + (row.wedding_date || '') + ' / ' + kTime(row.wedding_time) + ' / ' + (row.photo_usage_agree ? 'YES' : 'NO'));
      fd.append('from_name', '예약신청접수');
      fd.append('replyto', 'onthebride@gmail.com');
      fd.append('email', 'onthebride@gmail.com');
      fd.append('message', body);
      fetch('https://api.web3forms.com/submit', { method: 'POST', body: fd }).catch(() => {});
    }

    bookingForm.reset();
    resetSameAs();
    if (fpDate) fpDate.clear();
    tpReset();
    document.getElementById('bkTotal').textContent = calcTotal().toLocaleString('ko-KR') + '만원';
    bookingDone = true;
    submitBtn.textContent = '카카오톡 채팅 열기 →';
    setStatus('예약 신청이 접수되었습니다! 🤍\n카카오톡 채팅으로 예식 날짜와 성함을 보내주세요. 확인하셨으면 아래 버튼을 한 번 더 눌러주세요.', 'success');
  });
}

// Inquiry form — send via Web3Forms (→ email)
const inquiryForm = document.getElementById('inquiryForm');
if (inquiryForm) {
  const statusEl = document.getElementById('inqStatus');
  const btn = document.getElementById('inqBtn');
  const setStatus = (msg, type) => {
    statusEl.textContent = msg;
    statusEl.className = 'bk-status' + (type ? ' ' + type : '');
  };

  inquiryForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = val('f_inq_name');
    const email = val('f_inq_email');
    const message = val('f_inq_message');

    if (!name || !email || !message) {
      setStatus('성함, 이메일, 문의내용을 모두 입력해 주세요.', 'error');
      return;
    }
    const key = window.OTB_CONFIG && window.OTB_CONFIG.WEB3FORMS_KEY;
    if (!key) {
      setStatus('전송 설정 오류입니다. onthebride@naver.com 으로 연락 주세요.', 'error');
      return;
    }

    btn.disabled = true;
    setStatus('전송 중입니다...', '');
    try {
      const fd = new FormData();
      fd.append('access_key', key);
      fd.append('subject', '[온더브라이드] 홈페이지 문의 - ' + name);
      fd.append('from_name', name + ' (홈페이지 문의)');
      fd.append('replyto', email);
      fd.append('name', name);
      fd.append('email', email);
      fd.append('message', message);
      const res = await fetch('https://api.web3forms.com/submit', { method: 'POST', body: fd });
      const data = await res.json();
      btn.disabled = false;
      if (data.success) {
        inquiryForm.reset();
        setStatus('문의가 정상적으로 전송되었습니다! 빠르게 답변드리겠습니다. 감사합니다 🤍', 'success');
      } else {
        setStatus('전송에 실패했어요. 잠시 후 다시 시도하시거나 onthebride@naver.com 으로 연락 주세요.', 'error');
      }
    } catch (err) {
      btn.disabled = false;
      setStatus('전송 중 오류가 발생했어요. onthebride@naver.com 으로 연락 주세요.', 'error');
    }
  });
}

// ===== Gallery (custom: 태그 필터 + 라이트박스) =====
(async function initGallery() {
  const grid = document.getElementById('galleryGrid');
  const tagsEl = document.getElementById('galleryTags');
  const emptyEl = document.getElementById('galleryEmpty');
  if (!grid || typeof sb === 'undefined' || !sb) return;
  const esc = (s) => (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const { data, error } = await sb.rpc('gallery_list');
  if (error) { console.error(error); return; }
  const photos = data || [];
  if (!photos.length) { if (emptyEl) emptyEl.hidden = false; return; }
  // 썸네일 랜덤 순서 (로드마다)
  for (let i = photos.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [photos[i], photos[j]] = [photos[j], photos[i]];
  }

  const pagerEl = document.getElementById('galleryPager');
  const PER = 16; // 4 x 4
  let activeTag = '전체';
  let searchTerm = '';
  let page = 1;

  // 예식장 태그: 사진 많은 순 정렬
  const counts = {};
  photos.forEach((p) => { if (p.venue) counts[p.venue] = (counts[p.venue] || 0) + 1; });
  const venues = Object.keys(counts).sort((a, b) => counts[b] - counts[a]);

  const visible = () => {
    if (searchTerm) {
      const t = searchTerm.toLowerCase();
      return photos.filter((p) => (p.venue || '').toLowerCase().includes(t));
    }
    return activeTag === '전체' ? photos : photos.filter((p) => p.venue === activeTag);
  };

  const renderTags = () => {
    if (!venues.length) { tagsEl.style.display = 'none'; return; }
    const allActive = activeTag === '전체' && !searchTerm ? ' active' : '';
    tagsEl.innerHTML =
      `<button class="gtag${allActive}" data-v="전체">전체</button>` +
      `<span class="gtag gtag-search"><input id="gtagSearch" type="text" placeholder="예식장 검색" autocomplete="off" /></span>` +
      venues.map((v) => `<button class="gtag${v === activeTag && !searchTerm ? ' active' : ''}" data-v="${esc(v)}">${esc(v)}</button>`).join('');
    const si = document.getElementById('gtagSearch');
    si.value = searchTerm;
    si.addEventListener('input', () => {
      searchTerm = si.value.trim();
      activeTag = '전체';
      page = 1;
      tagsEl.querySelectorAll('button.gtag').forEach((b) => b.classList.toggle('active', searchTerm === '' && b.dataset.v === '전체'));
      renderGrid();
    });
  };
  const renderPager = (total) => {
    const pages = Math.ceil(total / PER);
    if (pages <= 1) { pagerEl.innerHTML = ''; return; }
    const WIN = 2; // 현재 페이지 좌우로 보여줄 개수
    const btn = (i) => `<button class="gpg${i === page ? ' active' : ''}" data-p="${i}">${i}</button>`;
    let html = `<button class="gpg nav" data-p="${page - 1}"${page === 1 ? ' disabled' : ''}>‹</button>`;
    const from = Math.max(1, page - WIN);
    const to = Math.min(pages, page + WIN);
    if (from > 1) { html += btn(1); if (from > 2) html += '<span class="gpg-dots">…</span>'; }
    for (let i = from; i <= to; i++) html += btn(i);
    if (to < pages) { if (to < pages - 1) html += '<span class="gpg-dots">…</span>'; html += btn(pages); }
    html += `<button class="gpg nav" data-p="${page + 1}"${page === pages ? ' disabled' : ''}>›</button>`;
    pagerEl.innerHTML = html;
  };
  // 썸네일: Supabase 이미지 변환으로 작게 받아 빠르게 (원본 1400px → 폭 지정 리사이즈)
  const thumb = (url, w) =>
    url && url.includes('/object/public/')
      ? url.replace('/object/public/', '/render/image/public/') + `?width=${w}&quality=72`
      : url;
  const renderGrid = () => {
    const list = visible();
    const start = (page - 1) * PER;
    grid.innerHTML = list
      .slice(start, start + PER)
      .map((p, i) => `<button class="gthumb" data-i="${start + i}"><img src="${esc(thumb(p.image_url, 600))}" alt="${esc(p.venue || '')}" loading="lazy" decoding="async" /></button>`)
      .join('');
    renderPager(list.length);
  };
  renderTags();
  renderGrid();

  tagsEl.addEventListener('click', (e) => {
    const b = e.target.closest('button.gtag');
    if (!b) return;
    activeTag = b.dataset.v;
    searchTerm = '';
    page = 1;
    renderTags();
    renderGrid();
  });
  pagerEl.addEventListener('click', (e) => {
    const b = e.target.closest('.gpg');
    if (!b || b.disabled) return;
    page = Number(b.dataset.p);
    renderGrid();
    document.getElementById('gallery').scrollIntoView({ behavior: 'smooth', block: 'start' });
  });

  // 모바일: 좌우 스와이프로 페이지 넘김
  let swipeGuard = 0;
  let tX = 0, tY = 0;
  grid.addEventListener('touchstart', (e) => { tX = e.changedTouches[0].clientX; tY = e.changedTouches[0].clientY; }, { passive: true });
  grid.addEventListener('touchend', (e) => {
    const dx = e.changedTouches[0].clientX - tX;
    const dy = e.changedTouches[0].clientY - tY;
    if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
    const pages = Math.ceil(visible().length / PER);
    if (dx < 0 && page < pages) { page += 1; renderGrid(); }
    else if (dx > 0 && page > 1) { page -= 1; renderGrid(); }
    swipeGuard = Date.now();
  }, { passive: true });

  // lightbox
  const lb = document.getElementById('lightbox');
  const lbImg = document.getElementById('lbImg');
  const lbVenue = document.getElementById('lbVenue');
  let curList = [];
  let curIdx = 0;
  const show = (i) => {
    curIdx = (i + curList.length) % curList.length;
    lbImg.src = curList[curIdx].image_url; // 확대보기는 원본(고화질)
    lbVenue.textContent = curList[curIdx].venue || '';
  };
  const open = (i) => { curList = visible(); show(i); lb.hidden = false; document.body.style.overflow = 'hidden'; };
  const close = () => { lb.hidden = true; document.body.style.overflow = ''; };
  grid.addEventListener('click', (e) => {
    if (Date.now() - swipeGuard < 350) return; // 스와이프 직후 클릭 무시
    const t = e.target.closest('.gthumb');
    if (t) open(Number(t.dataset.i));
  });
  document.getElementById('lbClose').addEventListener('click', close);
  document.getElementById('lbBackdrop').addEventListener('click', close);
  document.getElementById('lbPrev').addEventListener('click', () => show(curIdx - 1));
  document.getElementById('lbNext').addEventListener('click', () => show(curIdx + 1));
  // 모바일: 라이트박스 좌우 스와이프로 이전/다음 사진
  let lbTx = 0, lbTy = 0;
  lb.addEventListener('touchstart', (e) => { lbTx = e.changedTouches[0].clientX; lbTy = e.changedTouches[0].clientY; }, { passive: true });
  lb.addEventListener('touchend', (e) => {
    const dx = e.changedTouches[0].clientX - lbTx;
    const dy = e.changedTouches[0].clientY - lbTy;
    if (Math.abs(dx) < 50 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
    if (dx < 0) show(curIdx + 1); else show(curIdx - 1);
  }, { passive: true });
  document.addEventListener('keydown', (e) => {
    if (lb.hidden) return;
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowLeft') show(curIdx - 1);
    else if (e.key === 'ArrowRight') show(curIdx + 1);
  });
})();
