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

/* 화면을 덮는 창을 띄우는 동안 뒤가 안 움직이게.
   ⚠ 셈은 config.js 한 곳에 있다 — 같은 확대창이 네 군데에 복사돼 있어서,
     여기에도 두면 한쪽만 고쳐진다 (대표 2026-09-06 «작가 설문에서 ... 뒷배경 스크롤»).
   ⚠ config.js 는 모든 화면이 함께 읽고 no-cache 라 고치면 바로 퍼진다 */
const lockScroll = () => window.otbLockScroll();
const unlockScroll = () => window.otbUnlockScroll();


/* 이야기 「계속 보기」 (대표 2026-09-04
     «전문 이야기도 짧지 않을글 입니다까지 하고 접자 계속보기 누르면 다 보이는걸로»)
   ⚠ main.js 는 /booking 과 같이 쓴다. 거기엔 이 단추가 없으므로 반드시 확인하고 건다.
   ⚠ 화살표는 «누르면 벌어질 일»을 가리킨다 — 접혀 있으면 ∨, 펴져 있으면 ∧.
   ⚠ 한 번 펴면 다시 접을 수 있어야 한다. 다 읽고 아래로 못 내려가면 갇힌 느낌이다.
     접을 때는 이야기 첫머리로 데려다 놓는다 — 안 그러면 갑자기 저 아래에 서 있게 된다 */
const storyToggle = document.getElementById('storyToggle');
const storyMore = document.getElementById('storyMore');
if (storyToggle && storyMore) {
  storyToggle.addEventListener('click', () => {
    const open = storyMore.classList.toggle('open');
    storyToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    storyToggle.innerHTML = open ? '접기 <i>∧</i>' : '계속 보기 <i>∨</i>';
    if (!open) storyToggle.scrollIntoView({ behavior: 'smooth', block: 'center' });
  });
}

// Header background on scroll
/* ⚠⚠ 윗줄은 **시험이 잘라오는 표지**다 (storyfold.test.mjs 가 여기까지 잘라 돌린다).
     글자를 바꾸면 자를 데를 못 찾아 main.js 를 통째로 돌리다 터진다 — 한 번 그랬다.
   ⚠ 기본 머리말은 홈의 **어두운 히어로 위에** 얹히라고 흰 글씨·흰 로고다.
     히어로가 없는 화면(예약 폼)에서는 흰 바탕에 흰 글씨가 되어 **아무것도 안 보인다**
     (대표 2026-09-16 «예약하기 누르니까 헤더가 안보임»).
     그런 화면은 <header ... data-solid> 를 달아 **늘 진하게** 둔다.
   ⚠ HTML 에 class="scrolled" 만 적어두면 소용없다 — 여기서 맨 위(scrollY 0)일 때 도로 뗀다.
     그래서 표시를 보고 끄지 않는다 */
const header = document.querySelector('.site-header');
const solidHeader = !!(header && header.hasAttribute('data-solid'));
const toTop = document.getElementById('toTop');
const onScroll = () => {
  header.classList.toggle('scrolled', solidHeader || window.scrollY > 40);
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

// 앵커 진입 보정 (#event 등)
// 위쪽 갤러리(비동기 DB 렌더)·인스타 임베드가 뒤늦게 커지면서 목표 섹션이
// 아래로 밀려, 직접 링크로 들어오면 "그 위 섹션"이 보이는 문제를 보정한다.
// 콘텐츠가 자리잡을 때까지 여러 번 다시 정렬하되, 사용자가 스크롤을 시작하면 멈춘다.
const hashRealign = (() => {
  const id = decodeURIComponent((location.hash || '').replace(/^#/, ''));
  let stopped = !id;
  if (!stopped) {
    const evs = ['wheel', 'touchmove', 'keydown', 'mousedown'];
    const stop = () => { stopped = true; };
    evs.forEach((e) => window.addEventListener(e, stop, { passive: true }));
    setTimeout(() => evs.forEach((e) => window.removeEventListener(e, stop)), 2500);
  }
  return () => {
    if (stopped) return;
    const el = document.getElementById(id);
    if (el) el.scrollIntoView({ behavior: 'instant', block: 'start' });
  };
})();
window.addEventListener('load', () => { hashRealign(); [250, 600, 1200].forEach((t) => setTimeout(hashRealign, t)); });

// Rules modal (규정 전문)
// 규정 원문은 /rules 페이지 한 곳에만 존재한다. 모달은 열릴 때 그 페이지에서
// .rules-content 를 그대로 가져와 붙인다 — 두 곳에 같은 약관을 복사해두고
// 한쪽만 고치는 사고를 막기 위함.
const rulesModal = document.getElementById('rulesModal');
if (rulesModal) {
  const openBtn = document.getElementById('rulesOpen');
  const closeBtn = document.getElementById('rulesClose');
  const backdrop = document.getElementById('rulesBackdrop');
  const content = document.getElementById('rulesContent');
  let loaded = false;

  const loadRules = async () => {
    if (loaded || !content) return;
    try {
      const res = await fetch('/rules', { cache: 'no-cache' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const doc = new DOMParser().parseFromString(await res.text(), 'text/html');
      const src = doc.getElementById('rulesSource');
      if (!src) throw new Error('no rulesSource');
      content.innerHTML = src.innerHTML;
      loaded = true;
    } catch (err) {
      content.innerHTML =
        '<p class="rules-loading">규정을 불러오지 못했습니다.<br />' +
        '<a href="/rules" target="_blank" rel="noopener" class="rules-openpage">규정 전문 페이지에서 보기 ↗</a></p>';
    }
  };

  const open = () => {
    rulesModal.hidden = false;
    lockScroll();
    loadRules();
  };
  const close = () => {
    rulesModal.hidden = true;
    unlockScroll();
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
    /* ⚠ flatpickr 는 값을 **코드로** 넣는다 — 그러면 change 이벤트가 안 난다.
       예식날짜가 바뀌면 지정 목록(그날 되는 분)이 달라지므로 여기서 직접 알려준다
       (대표 2026-09-16 «그날 안 되는 작가는 빼야지») */
    onChange: () => { if (typeof pkOnDate === 'function') pkOnDate(); },
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

// 앨범 추가: 체크박스가 아닌 수량 스테퍼 — 단가 × 수량으로 합산
const albumQty = () => { const el = document.getElementById('f_album_qty'); return el ? Math.max(0, parseInt(el.value, 10) || 0) : 0; };
const albumUnit = () => { const el = document.getElementById('f_option_album'); return el ? (Number(el.dataset.price) || 0) : 0; };
const albumName = () => { const el = document.getElementById('f_option_album'); const li = el && el.closest('li'); const n = li && li.querySelector('.opt-name'); return (n && n.textContent.trim()) || '앨범 추가'; };

/* ===== 작가 우선순위 · 작가 지정 (대표 2026-09-17 «예약 폼 넣자») =====

   우선순위 — 무료. 세 분까지 차례대로. **약속이 아니다**
     («가능한 맞춰드립니다 다만 당일 작가님 지정이 있거나 스케줄 상 어려울 수 있어요»).
   지정 — 한 분. 그 작가님 금액이 합계에 붙는다. 안 정하신 분은 기본 5만원.

   ⚠ 둘은 같이 못 고른다. 하나를 켜면 다른 하나가 꺼지고 골라둔 것도 지운다.
     남겨두면 다시 켰을 때 «내가 언제 이걸 골랐지» 가 된다. 서버 표에도 같은 제약이 있다.
   ⚠ **지정은 예식날짜를 먼저 받아야 한다** — 그날 안 되는 분을 보여주면 안 된다
     (대표 2026-09-16 «빼야지»). 날짜가 바뀌면 목록을 다시 받는다.
   ⚠ 값은 **서버가 다시 셈한다**(submit_booking_v2). 여기 숫자는 신부님께 보여드리는 것이고,
     접수될 때는 그 작가의 지금 금액으로 다시 붙는다. 그래야 꾸며 보낸 값이 안 먹는다.
   ⚠ 이 자리는 **머리 위에서 미리 그릴 수 없다** — 작가 목록이 서버에서 온다.
     그래서 calcTotal 이 부르는 pkFeeManwon 만 앞에 두고(함수 선언은 끌어올려진다),
     상태는 여기서 먼저 만든다. 안 그러면 첫 합계 셈에서 TDZ 로 터진다 */
let pkStaff = [];      // 손님이 보는 작가 목록 (public.pick_staff_list 가 준다)
let pkWish = [];       // 우선순위로 고른 작가 id (차례가 곧 1·2·3순위)
let pkPin = null;      // 지정한 작가 id (한 명)
let pkFor = null;      // 어느 날짜로 받아둔 목록인가 (날짜가 바뀌면 다시 받는다)
let pkBusy = false;
const PK_SLOTS = 3;

const pkOne = (id) => pkStaff.find((x) => x.id === id) || null;
// 합계에 더할 지정비 (만원). 고른 분이 없으면 0
function pkFeeManwon() {
  if (!pkPin || !checked('f_pick_pin')) return 0;
  const s = pkOne(pkPin);
  return s ? Math.round((Number(s.fee) || 0) / 10000) : 0;
}
const pkWon = (n) => Number(n || 0).toLocaleString('ko-KR') + '원';

function pkRecalc() {
  const t = document.getElementById('bkTotal');
  if (t) t.textContent = calcTotal().toLocaleString('ko-KR') + '만원';
}

function pkMsg(txt) {
  const el = document.getElementById('pkMsg');
  if (!el) return;
  el.hidden = !txt;
  el.innerHTML = txt || '';
}

async function pkLoad() {
  const pinOn = checked('f_pick_pin');
  const day = val('f_wedding_date') || null;
  /* 지정은 그날 되는 분만 보여야 하므로 날짜가 있어야 한다.
     우선순위는 셋 중 하나라 날짜 없이도 고르실 수 있다 */
  const key = pinOn ? (day || '') : '-';
  if (pkFor === key && pkStaff.length) { pkRender(); return; }
  if (pinOn && !day) { pkStaff = []; pkFor = key; pkRender(); return; }
  if (typeof sb === 'undefined' || !sb) { pkMsg('작가 목록을 불러오지 못했어요.'); return; }
  pkBusy = true; pkRender();
  const { data, error } = await sb.rpc('pick_staff_list', { p_wedding_date: pinOn ? day : null });
  pkBusy = false;
  if (error || !Array.isArray(data)) { pkStaff = []; pkMsg('작가 목록을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.'); pkRender(); return; }
  pkStaff = data;
  pkFor = key;
  // 목록이 바뀌면 이제 못 고르는 분은 떨어뜨린다 (그날이 찼을 수 있다)
  pkWish = pkWish.filter((id) => pkOne(id));
  if (pkPin && !(pkOne(pkPin) || {}).can_pin) pkPin = null;
  pkRender();
  pkRecalc();
}

// 예식날짜가 바뀌면 (flatpickr 가 부른다)
function pkOnDate() { pkFor = null; if (checked('f_pick_pin')) pkLoad(); }

function pkRender() {
  const box = document.getElementById('pkBox');
  if (!box) return;
  const wishOn = checked('f_pick_wish');
  const pinOn = checked('f_pick_pin');
  box.hidden = !(wishOn || pinOn);
  /* 목록은 **누른 줄 바로 아래**에 펴진다 (대표 2026-09-17
     «작가 우선순위 체크 하면 그 바로 아래 작가 목록이 떴음 하는데 작가지정 아래에 펼쳐지네»).
     상자는 하나뿐이라 자리를 옮겨 준다 — 둘로 만들면 그리는 코드도 둘이 된다.
     ⚠ 둘은 같이 못 켠다(위 손잡이가 서로 끈다). 그래서 갈 곳도 언제나 하나다 */
  if (!box.hidden) {
    const anchor = document.getElementById(pinOn ? 'pkNotePin' : 'pkNoteWish');
    if (anchor && anchor.nextElementSibling !== box) {
      anchor.parentNode.insertBefore(box, anchor.nextSibling);
    }
  }
  const slots = document.getElementById('pkSlots');
  const list = document.getElementById('pkList');
  const foot = document.getElementById('pkFoot');
  if (!box.hidden) pkMsg('');
  if (box.hidden || !slots || !list) return;

  // 「+5만원부터」 — 제일 싼 분 기준
  const from = document.getElementById('pkFrom');
  if (from && pkStaff.length) {
    const low = Math.min.apply(null, pkStaff.filter((s) => s.can_pin).map((s) => Number(s.fee) || 0));
    if (Number.isFinite(low) && low > 0) from.textContent = '+' + pkWon(low) + '부터';
  }

  if (pinOn && !val('f_wedding_date')) {
    slots.innerHTML = ''; list.innerHTML = '';
    if (foot) foot.textContent = '';
    pkMsg('먼저 <b>예식날짜</b>를 골라주세요. 그날 촬영이 가능한 작가님만 보여드립니다.');
    return;
  }
  if (pkBusy) { slots.innerHTML = ''; list.innerHTML = '<p class="pk-empty">불러오는 중…</p>'; return; }

  // 우선순위 세 자리 (지정은 한 분이라 자리가 없다)
  slots.hidden = !wishOn;
  slots.innerHTML = !wishOn ? '' : Array.from({ length: PK_SLOTS }, (_, i) => {
    const s = pkOne(pkWish[i]);
    return '<div class="pk-slot' + (s ? ' on' : '') + '"><i>' + (i + 1) + '순위</i>'
      + (s ? '<b>' + _esc(s.name) + '</b><button type="button" class="pk-x" data-pkdrop="' + _esc(s.id) + '">빼기</button>'
           : '<span class="dim">아직</span>') + '</div>';
  }).join('');

  /* ⚠ 우선순위와 지정은 고를 수 있는 분이 다르다.
     대표님은 지정으로만 고르실 수 있다 (대표 2026-09-17 «우선순위에사 나는 빼자»).
     ⚠ can_wish 가 없는 옛 자료여도 안 사라지게 !== false 로 본다 */
  let pool = pinOn ? pkStaff.filter((s) => s.can_pin) : pkStaff.filter((s) => s.can_wish !== false);
  /* 지정을 누르면 **그 분만 남긴다** (대표 2026-09-17 «지정 누르면 그 작가만 남고
     목록은 없어지는걸로 / 지금은 다 표시돠고 스크롤만 쓸데없이 길어짐»).
     ⚠ 되돌릴 길은 그대로다 — 그 분의 「지정함 — 빼기」를 누르면 목록이 다시 펴진다.
       아래 pkFoot 에 그렇게 적어 둔다 (올리기 전 점검 ③ — 누르면 어떻게 되는지 보인다).
     ⚠ 우선순위는 셋까지 고르는 것이라 안 줄인다 */
  if (pinOn && pkPin && pool.some((s) => s.id === pkPin)) pool = pool.filter((s) => s.id === pkPin);
  list.innerHTML = !pool.length
    ? '<p class="pk-empty">' + (pinOn ? '그날 지정하실 수 있는 작가님이 없어요. 우선순위로 골라주시면 최대한 맞춰드릴게요.' : '작가 목록을 불러오지 못했어요.') + '</p>'
    : pool.map((s) => {
      const at = pkWish.indexOf(s.id);
      const isPin = pkPin === s.id;
      /* ⚠ 「추천 1·2·3위」 딱지는 뺐다 (대표 2026-09-17 «추천은 빼자 / 그냥 랜덤으로 하자»).
         차례는 서버가 섞어서 준다 — **누구를 먼저 보여주느냐가 곧 미는 것**이라
         순서를 안 정하는 편이 공정하다. 점수와 건수는 그대로 보여드린다 */
      /* ⚠ 점수만 적는다. 촬영 후 설문의 「한마디」는 신부님이 우리에게 주신 글이라 안 낸다 */
      const score = s.score == null
        ? '<span class="pk-none">아직 받은 후기가 없어요</span>'
        : '<span class="pk-score">후기 ' + s.score + '점 <span class="thin">(' + s.n + '건)</span></span>';
      /* 우리와 찍은 횟수 (대표 2026-09-17 «촬영횟수 붙여줘»).
         후기는 8월에야 모으기 시작해 오래 찍으신 분도 「후기 없어요」로만 보였다.
         ⚠ 작가님이 제 캘린더에서 보시는 숫자와 같은 셈이다 (pick_eligible 과 맞춰뒀다).
         ⚠ 0 이면 아예 안 적는다 — 「촬영 0회」는 없느니만 못하다 */
      const took = Number(s.took) || 0;
      const tookTag = took > 0
        ? '<span class="pk-took">촬영 ' + took.toLocaleString('ko-KR') + '회</span>' : '';
      const shots = (s.shots || []).length
        ? '<div class="pk-shots">' + s.shots.map((u) =>
          '<img loading="lazy" src="' + _esc(u) + '" alt="' + _esc(s.name) + ' 작가 사진" />').join('') + '</div>'
        : '<p class="pk-noshot">아직 올라간 사진이 없어요</p>';
      /* ⚠ 지정은 **금액을 단추에 적는다** — 누르기 전에 합계가 얼마나 오르는지 보여야 한다 */
      const btn = pinOn
        ? '<button type="button" class="pk-take' + (isPin ? ' off' : '') + '" data-pkpin="' + _esc(s.id) + '">'
          + (isPin ? '지정함 — 빼기' : '지정하기 <b>+' + pkWon(s.fee) + '</b>') + '</button>'
        : '<button type="button" class="pk-take' + (at >= 0 ? ' off' : '') + '" data-pktake="' + _esc(s.id) + '">'
          + (at >= 0 ? (at + 1) + '순위 — 빼기' : pkWish.length >= PK_SLOTS ? '자리 다 참' : '고르기') + '</button>';
      return '<div class="pk-item' + ((pinOn ? isPin : at >= 0) ? ' chosen' : '') + '">'
        /* 대표님 이름 옆에 「(대표)」 (대표 2026-09-18 «작가 지정에만 내이름 옆에 (대표) 라고 적어줘»).
           ⚠ 우선순위 목록에는 대표님이 안 나오니 이 표시는 지정에서만 보인다 */
        + '<div class="pk-head"><span class="pk-name">' + _esc(s.name)
        + (s.is_rep ? '<em class="pk-rep">(대표)</em>' : '') + '</span>'
        + tookTag + score + btn + '</div>'
        + shots + '</div>';
    }).join('');

  if (foot) {
    const pinS = pkPin && pkOne(pkPin);
    foot.textContent = pinOn
      ? (pinS ? pinS.name + ' 작가님으로 지정하셨어요. 그 작가님이 촬영합니다. 다른 분을 보시려면 「지정함 — 빼기」를 눌러주세요.' : '한 분을 골라주세요.')
      : pkWish.length === 0 ? '세 분까지 고르실 수 있어요.'
        : pkWish.length < PK_SLOTS ? pkWish.length + '분 고르셨어요. ' + (PK_SLOTS - pkWish.length) + '자리 남았습니다.'
          : '세 분 다 고르셨어요. 가능한 맞춰드릴게요.';
  }

  box.querySelectorAll('[data-pktake]').forEach((b) => b.addEventListener('click', () => {
    const id = b.dataset.pktake;
    const at = pkWish.indexOf(id);
    if (at >= 0) pkWish.splice(at, 1);
    else if (pkWish.length < PK_SLOTS) pkWish.push(id);
    pkRender();
  }));
  box.querySelectorAll('[data-pkdrop]').forEach((b) => b.addEventListener('click', () => {
    const at = pkWish.indexOf(b.dataset.pkdrop);
    if (at >= 0) pkWish.splice(at, 1);
    pkRender();
  }));
  box.querySelectorAll('[data-pkpin]').forEach((b) => b.addEventListener('click', () => {
    // 지정은 한 분. 다른 분을 누르면 갈아탄다 (앞의 분을 먼저 빼게 하지 않는다)
    pkPin = pkPin === b.dataset.pkpin ? null : b.dataset.pkpin;
    pkRender();
    pkRecalc();
  }));
}

const calcTotal = () => {
  let sum = 0;
  bookingForm
    .querySelectorAll('input[data-price]:checked')
    .forEach((el) => { if (el.id !== 'f_option_album') sum += Number(el.dataset.price) || 0; });
  sum += albumUnit() * albumQty(); // 앨범 추가: 체크박스는 위에서 제외, 단가 × 수량으로 합산
  // 2인 촬영이면 출장비는 1인당 적용 → +5 (출장비 10만원)
  const tv = bookingForm.querySelector('#f_travel');
  const two = (bookingForm.querySelector('input[name="photographer"]:checked') || {}).value === '2인 촬영';
  if (tv && tv.checked && two) sum += 5;
  // 작가 지정은 고르신 분마다 값이 달라 data-price 로는 셈이 안 된다. 따로 더한다
  sum += pkFeeManwon();
  return sum;
};
if (bookingForm) {
  const totalEl = document.getElementById('bkTotal');
  const recalc = () => {
    totalEl.textContent = calcTotal().toLocaleString('ko-KR') + '만원';
  };
  bookingForm.addEventListener('change', recalc);
  recalc();

  /* 우선순위·지정 두 칸 (대표 2026-09-17).
     ⚠ 둘은 같이 못 고른다 — 한쪽을 켜면 다른 쪽이 꺼지고, 꺼진 쪽이 고른 것도 지운다.
       한쪽을 먼저 끄고 다른 쪽을 켜게 하면 두 번 눌러야 한다 */
  const wishEl = document.getElementById('f_pick_wish');
  const pinEl = document.getElementById('f_pick_pin');
  if (wishEl && pinEl) {
    wishEl.addEventListener('change', () => {
      if (wishEl.checked) { pinEl.checked = false; pkPin = null; } else pkWish = [];
      pkLoad(); pkRecalc();
    });
    pinEl.addEventListener('change', () => {
      if (pinEl.checked) { wishEl.checked = false; pkWish = []; } else pkPin = null;
      pkLoad(); pkRecalc();
    });
  }
}

// 수량 스테퍼(−/＋) 배선 — 값 변경 시 폼 change 이벤트로 합계 재계산
const setStepperVal = (input, v) => {
  const min = Number(input.min) || 0;
  const max = input.max === '' ? Infinity : Number(input.max);
  input.value = Math.max(min, Math.min(max, v));
  const st = input.closest('.qty-stepper');
  if (st) st.classList.toggle('on', (parseInt(input.value, 10) || 0) > 0);
};
// 앨범: 체크박스 ↔ 수량 연동 (수량>0이면 체크, 체크 해제면 0권)
const albumCheckboxSync = () => { const cb = document.getElementById('f_option_album'); const qi = document.getElementById('f_album_qty'); if (cb && qi) cb.checked = (parseInt(qi.value, 10) || 0) > 0; };
if (bookingForm) {
  bookingForm.querySelectorAll('.qty-stepper').forEach((st) => {
    const input = st.querySelector('.qty-input');
    if (!input) return;
    setStepperVal(input, parseInt(input.value, 10) || 0);
    st.querySelectorAll('.qty-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        setStepperVal(input, (parseInt(input.value, 10) || 0) + (Number(btn.dataset.step) || 0));
        if (input.id === 'f_album_qty') albumCheckboxSync();
        input.dispatchEvent(new Event('change', { bubbles: true }));
      });
    });
  });
  const albumCb = document.getElementById('f_option_album');
  if (albumCb) albumCb.addEventListener('change', () => {
    const qi = document.getElementById('f_album_qty');
    if (qi) setStepperVal(qi, albumCb.checked ? Math.max(1, parseInt(qi.value, 10) || 0) : 0);
  });
}
const resetSteppers = () => { if (bookingForm) bookingForm.querySelectorAll('.qty-input').forEach((i) => setStepperVal(i, 0)); };

// Supabase client
const sb =
  window.supabase && window.OTB_CONFIG
    ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
    : null;

// ===== 상품·옵션 단가 동적 적용 (관리자 '상품관리' 설정 반영) =====
const _esc = (s) => (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const CODE_INPUT = { basic: 'f_basic', travel: 'f_travel', album: 'f_option_album', reception: 'f_option_reception', pyebaek: 'f_option_pyebaek', part2: 'f_option_part2', rep: 'f_rep' };
const _show = (el, on) => { if (el) el.style.display = on ? '' : 'none'; };
async function applyPricing() {
  if (!sb) return;
  let data;
  try { data = (await sb.rpc('pricing_public')).data; } catch (_) { return; }
  if (!Array.isArray(data)) return;
  const P = {}; data.forEach((p) => { P[p.code] = p; });
  window.__OTB_PRICING = P;
  // 예약 폼: 단가·이름·노출
  Object.entries(CODE_INPUT).forEach(([code, id]) => {
    const p = P[code], input = document.getElementById(id);
    if (!p || !input) return;
    input.dataset.price = p.price;
    const li = input.closest('li'); if (!li) return;
    const pe = li.querySelector('.opt-price'); if (pe) pe.textContent = (p.kind === 'product' ? '' : '+') + p.price + '만원';
    if (code !== 'basic') { if (code !== 'album') { const ne = li.querySelector('.opt-name'); if (ne) ne.textContent = p.name; } _show(li, p.active); }
  });
  // 2인 촬영(라디오)
  const twoR = bookingForm && bookingForm.querySelector('input[name="photographer"][value="2인 촬영"]');
  if (twoR && P.photographer_2p) { twoR.dataset.price = P.photographer_2p.price; const li = twoR.closest('li'); const pe = li && li.querySelector('.opt-price'); if (pe) pe.textContent = '+' + P.photographer_2p.price + '만원'; }
  // 홈 가격표(데이터-코드)
  document.querySelectorAll('[data-code]').forEach((el) => {
    const p = P[el.dataset.code]; if (!p) return;
    const num = el.querySelector('.price-num'); if (num) num.textContent = (p.price * 10000).toLocaleString('ko-KR');
    const won = el.querySelector('.opt-won'); if (won) { won.textContent = (p.price * 10000).toLocaleString('ko-KR') + '원'; _show(el, p.active); }
  });
  // 추가 옵션(손님용, is_core=false) 예약폼에 동적 체크박스로 노출
  const extraWrap = document.getElementById('extraOptions');
  if (extraWrap) {
    const extras = data.filter((p) => !p.is_core && p.active && p.kind === 'option');
    extraWrap.innerHTML = extras.map((p) => `<li class="opt"><label class="check"><input type="checkbox" class="f-extra" data-code="${_esc(p.code)}" data-name="${_esc(p.name)}" data-price="${p.price}" /> <span class="opt-name">${_esc(p.name)}</span></label><span class="opt-price">+${p.price}만원</span></li>`).join('');
  }
  if (bookingForm) { const t = document.getElementById('bkTotal'); if (t) t.textContent = calcTotal().toLocaleString('ko-KR') + '만원'; }
}
applyPricing();

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

// 폼 선택 → 단가 스냅샷 line_items (DOM data-price 기준 → 화면 총액과 항상 일치)
const _price = (id) => { const el = document.getElementById(id); return el ? (Number(el.dataset.price) || 0) : 0; };
const _optName = (id, fb) => { const el = document.getElementById(id); const li = el && el.closest('li'); const n = li && li.querySelector('.opt-name'); return n ? n.textContent.trim() : fb; };
function buildLineItems() {
  const items = [];
  const two = radioVal('photographer') === '2인 촬영';
  if (checked('f_basic')) items.push({ group: '상품', name: '베이직', price: _price('f_basic') });
  if (checked('f_travel')) items.push({ group: '상품', name: '출장비', price: _price('f_travel') + (two ? 5 : 0) });
  if (albumQty() > 0) items.push({ group: '옵션', name: `${albumName()} ${albumQty()}권`, price: albumUnit() * albumQty(), qty: albumQty() });
  if (checked('f_option_reception')) items.push({ group: '옵션', name: _optName('f_option_reception', '연회장 인사촬영'), price: _price('f_option_reception') });
  if (checked('f_option_pyebaek')) items.push({ group: '옵션', name: _optName('f_option_pyebaek', '폐백촬영'), price: _price('f_option_pyebaek') });
  if (checked('f_option_part2')) items.push({ group: '옵션', name: _optName('f_option_part2', '2부 촬영'), price: _price('f_option_part2') });
  if (two) { const r = bookingForm.querySelector('input[name="photographer"][value="2인 촬영"]'); items.push({ group: '옵션', name: '2인 촬영', price: r ? (Number(r.dataset.price) || 0) : 25 }); }
  // ⚠ 대표지정 줄은 2026-09-17 에 화면에서 내렸다. 옛 예약에는 남아 있으니 셈은 남겨둔다
  if (checked('f_rep')) items.push({ group: '옵션', name: _optName('f_rep', '대표지정'), price: _price('f_rep') });
  /* 작가 지정 — 고르신 분마다 값이 다르다.
     ⚠ 이 줄은 신부님께 보여드리는 것이고, 접수될 때 **서버가 그 작가의 지금 금액으로 다시 만든다**
       (submit_booking_v2). 꾸며 보낸 값은 안 먹는다 */
  if (checked('f_pick_pin') && pkPin) {
    const s = pkOne(pkPin);
    if (s) items.push({ group: '옵션', name: '작가 지정 · ' + s.name, price: Math.round((Number(s.fee) || 0) / 10000) });
  }
  document.querySelectorAll('#extraOptions input.f-extra:checked').forEach((el) => {
    items.push({ group: '옵션', name: el.dataset.name, price: Number(el.dataset.price) || 0 });
  });
  return items;
}

// Booking — submit to Supabase
if (bookingForm) {
  const statusEl = document.getElementById('bkStatus');
  const submitBtn = bookingForm.querySelector('.bk-submit');
  const anywayBtn = document.getElementById('bkAnyway');
  const KAKAO_CHAT = 'http://pf.kakao.com/_pxeNAn/chat';
  let bookingDone = false; // 1차 제출 완료 여부
  /* 같은 번호·같은 예식일로 이미 들어온 신청이 있다고 알린 상태 (대표 2026-09-10
       «새벽에 예약신청하고 내가 응답이 없어서 다시 예약신청하는 경우 있는데 이거 막을 수 없나?»).
     이때 제출 단추는 「카카오톡 채팅 열기」가 되고, 그 아래 「그래도 새로 신청하기」가 나온다
     — 대표 «빠져나갈길 두자». 진짜 다른 건일 때와 대표가 시험 삼아 넣어보실 때 이 길로 지난다 */
  let dupPending = false;

  const setStatus = (msg, type) => {
    statusEl.textContent = msg;
    statusEl.className = 'bk-status' + (type ? ' ' + type : '');
  };

  const submitBooking = async (force) => {
    // 2차: 이미 접수됐거나 이미 들어온 게 있다고 알린 뒤면 카카오톡 채팅창으로 바로 연결
    if (!force && (bookingDone || dupPending)) {
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
    if (!checked('f_agree_available') || !checked('f_agree_terms') || !checked('f_agree_privacy')) {
      setStatus('확인사항 3개 항목(예약 가능 확인 · 규정 동의 · 개인정보 수집·이용 동의)에 모두 체크해 주세요.', 'error');
      return;
    }
    if (!sb) {
      setStatus('연결 설정 오류입니다. 잠시 후 다시 시도해 주세요.', 'error');
      return;
    }

    const lineItems = buildLineItems();
    const extraSel = Array.from(document.querySelectorAll('#extraOptions input.f-extra:checked')).map((el) => ({ name: el.dataset.name, price: Number(el.dataset.price) || 0 }));
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
      option_album: albumQty() > 0,
      option_album_qty: albumQty(),
      option_reception: checked('f_option_reception'),
      option_pyebaek: checked('f_option_pyebaek'),
      option_part2: checked('f_option_part2'),
      photographer: radioVal('photographer') || '기본',
      rep_designation: checked('f_rep'),
      // 우선순위는 셋까지, 지정은 한 분. 둘은 같이 못 고른다 — 서버도 같은 것을 본다
      pick_wish: checked('f_pick_wish') ? pkWish.slice(0, PK_SLOTS) : [],
      pick_pin: checked('f_pick_pin') ? pkPin : null,
      photo_usage_agree: radioVal('usage') === 'yes',
      total_price: calcTotal(),
      line_items: lineItems,
      custom_options: extraSel,
    };

    if (force) row.force = true;   // 「그래도 새로 신청하기」 — 서버에서 중복 검사를 건너뛴다

    submitBtn.disabled = true;
    setStatus('접수 중입니다...', '');

    /* ⚠ 옛 submit_booking 이 아니라 _v2 다. 이미 들어온 것이 있으면 줄을 만들지 않고
       언제 들어왔는지를 돌려준다. 옛 함수도 DB 에 그대로 살아 있다 —
       손님 브라우저에 이미 받아둔 옛 main.js 가 그걸 부르고 있어서, 지우면 그 신청이 조용히 죽는다 */
    const { data, error } = await sb.rpc('submit_booking_v2', { payload: row });

    submitBtn.disabled = false;
    if (error) {
      console.error(error);
      setStatus('접수 중 오류가 발생했어요. 다시 시도하시거나 onthebride@naver.com 으로 연락 주세요.', 'error');
      return;
    }

    /* 폼을 채우시는 사이에 지정한 작가님이 그날 차버렸다 (대표 2026-09-17).
       ⚠ 돈을 받는 자리라 **조용히 넘기지 않는다.** 그대로 접수되면 약속이 어긋난다.
         폼은 그대로 두고 그 작가님만 떨어뜨린 뒤 다시 고르시게 한다 */
    if (data && data.ok === false && (data.reason === 'pin_taken' || data.reason === 'pin_gone')) {
      pkPin = null;
      pkFor = null;                 // 목록을 다시 받는다 — 그 사이에 또 달라졌을 수 있다
      await pkLoad();
      pkRecalc();
      setStatus(data.reason === 'pin_taken'
        ? [(data.name ? data.name + ' 작가님이 ' : '') + '그 사이 예식날에 다른 일정이 잡혔어요.',
          '아래에서 다른 작가님을 골라주시거나, 우선순위로 바꿔주세요.'].join('\n')
        : '고르신 작가님을 지금은 지정하실 수 없어요. 아래에서 다시 골라주세요.', 'warn');
      return;
    }

    /* 이미 들어온 신청이 있다 — 폼은 그대로 두고 알리기만 한다.
       「그래도 새로 신청하기」를 누르면 채운 그대로 다시 보낸다 (처음부터 다시 채우게 하지 않는다) */
    if (data && data.ok === false) {
      dupPending = true;
      submitBtn.textContent = '카카오톡 채팅 열기 →';
      if (anywayBtn) anywayBtn.hidden = false;
      setStatus([
        '이미 접수된 신청이 있어요.',
        (data.at_txt ? data.at_txt + '에 ' : '') + '같은 연락처·같은 예식일로 들어와 있습니다.',
        '순서대로 확인해서 연락드리고 있으니 조금만 기다려 주세요.',
        '바꾸실 내용이 생기면 새로 신청하지 마시고 카카오톡으로 말씀해 주세요.',
      ].join('\n'), 'warn');
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
      // 계약안내 메일 항목 = 실제 스냅샷 단가 기준
      const items = lineItems.map((it) => `${it.name} (${it.price})`);

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
    resetSteppers();
    if (fpDate) fpDate.clear();
    tpReset();
    document.getElementById('bkTotal').textContent = calcTotal().toLocaleString('ko-KR') + '만원';
    bookingDone = true;
    dupPending = false;
    if (anywayBtn) anywayBtn.hidden = true;
    submitBtn.textContent = '카카오톡 채팅 열기 →';
    /* 답이 늦어도 다시 넣지 마시라는 말을 여기서 한다 (대표 2026-09-10).
       새벽에 넣고 답이 없으면 다시 넣으신다 — 그렇게 두 건이 된다 */
    setStatus([
      '예약 신청이 접수되었습니다! 🤍',
      '카카오톡 채팅으로 예식 날짜와 성함을 보내주세요. 확인하셨으면 아래 버튼을 한 번 더 눌러주세요.',
      '확인 후 순서대로 연락드립니다. 답이 늦어도 다시 신청하지 마세요 — 두 번 들어오면 확인이 더 늦어집니다.',
      '바꾸실 내용은 새로 신청하지 마시고 카카오톡으로 말씀해 주세요.',
    ].join('\n'), 'success');
  };

  bookingForm.addEventListener('submit', (e) => { e.preventDefault(); submitBooking(false); });

  /* 「그래도 새로 신청하기」 — 채운 그대로 다시 보낸다.
     단추 글자는 «누르면 벌어질 일»을 말한다 (지금 상태가 아니라) */
  if (anywayBtn) {
    anywayBtn.addEventListener('click', () => {
      dupPending = false;
      anywayBtn.hidden = true;
      submitBtn.textContent = '제출하기';
      submitBooking(true);
    });
  }
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

// 화면에 가까워질 때까지 기다린다. 안 내려가는 손님은 아예 안 받는다.
// 다만 갤러리를 곧장 보러 온 손님(?g=예식장, #gallery)은 기다리지 않는다.
function whenNear(el, margin) {
  return new Promise((go) => {
    if (!el || !('IntersectionObserver' in window)) return go();
    if (new URLSearchParams(location.search).get('g') || location.hash === '#gallery') return go();
    const io = new IntersectionObserver((es) => {
      if (es.some((e) => e.isIntersecting)) { io.disconnect(); go(); }
    }, { rootMargin: margin || '1200px' });
    io.observe(el);
  });
}

// ===== Gallery (custom: 태그 필터 + 라이트박스) =====
(async function initGallery() {
  const grid = document.getElementById('galleryGrid');
  const tagsEl = document.getElementById('galleryTags');
  const emptyEl = document.getElementById('galleryEmpty');
  if (!grid || typeof sb === 'undefined' || !sb) return;
  const esc = (s) => (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  await whenNear(document.getElementById('gallery'), '1200px');

  // 홈은 사진 주소와 예식장만 있으면 된다. 관리자용 gallery_list 는 지우기에 쓸
  // 파일 경로까지 실어 오는데, 671장이면 그것만 40KB 다.
  const { data, error } = await sb.rpc('gallery_public');
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
  // 썸네일: Supabase 이미지 변환으로 폭 지정 리사이즈 (원본 1400px)
  const thumb = (url, w) =>
    url && url.includes('/object/public/')
      ? url.replace('/object/public/', '/render/image/public/') + `?width=${w}&quality=82`
      : url;
  // 그리드 한 칸은 PC 285px, 폰 45vw(=약 175px). 폭 1000 을 받고 있었는데 3배 이상 과했다.
  // 몇 가지 크기를 알려주고 화면 해상도에 맞는 것을 브라우저가 고르게 한다.
  const TW = [300, 600, 900];
  const srcset = (url) => TW.map((w) => `${thumb(url, w)} ${w}w`).join(', ');
  const SIZES = '(max-width: 860px) 45vw, 285px';
  const renderGrid = () => {
    const list = visible();
    const start = (page - 1) * PER;
    grid.innerHTML = list
      .slice(start, start + PER)
      .map((p, i) => `<button class="gthumb" data-i="${start + i}"><img src="${esc(thumb(p.image_url, 600))}" srcset="${esc(srcset(p.image_url))}" sizes="${SIZES}" alt="${esc(p.venue || '')}" loading="lazy" decoding="async" /></button>`)
      .join('');
    renderPager(list.length);
  };
  // 블로그 등에서 ?g=<예식장> 으로 들어오면 그 예식장으로 검색된 채 갤러리 표시
  const urlG = new URLSearchParams(location.search).get('g');
  if (urlG) { searchTerm = urlG; activeTag = '전체'; }
  renderTags();
  renderGrid();
  hashRealign(); // 갤러리가 채워져 높이가 커진 직후 목표 앵커로 다시 정렬
  if (urlG) {
    const gs = document.getElementById('gallery');
    if (gs) setTimeout(() => gs.scrollIntoView({ behavior: 'smooth', block: 'start' }), 150);
  }

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
  /* 넘어갈 때 살짝 움직여 준다 (대표 2026-09-04 «이거 약간 넘어가는 모션 줄 수 없나?»).
     ⚠ 확대보기는 원본(고화질)이라 곧바로 바꾸면 잠깐 빈 자리가 보인다.
       **다 받아온 뒤에** 바꾼다 — 그 전까지는 보던 사진이 그대로 있다.
     ⚠ 빨리 여러 번 넘기면 늦게 온 것이 나중에 덮어쓴다. 번호를 매겨 마지막 것만 그린다.
     ⚠ 방향을 준다. 왼쪽으로 밀었으면 다음 장이 오른쪽에서 들어와야 손과 맞는다. */
  let showSeq = 0;
  const show = (i, dir) => {
    curIdx = (i + curList.length) % curList.length;
    const p = curList[curIdx];
    const mine = ++showSeq;
    const paint = () => {
      if (mine !== showSeq) return;              // 그 사이 또 넘겼다
      lbImg.classList.remove('lb-in');
      lbImg.style.setProperty('--lb-from', (dir > 0 ? 28 : dir < 0 ? -28 : 0) + 'px');
      lbImg.src = p.image_url;
      void lbImg.offsetWidth;                    // 애니메이션을 다시 시작시킨다
      lbImg.classList.add('lb-in');
      // 누가 찍었는지 같이 보여준다 (대표 요청 2026-08-25 — 작가를 보고 고르시라고).
      // 아직 작가를 안 찍은 사진은 예식장만 나온다
      lbVenue.textContent = [p.venue, p.staff_name ? p.staff_name + ' 작가' : ''].filter(Boolean).join(' · ');
    };
    const pre = new Image();
    pre.src = p.image_url;
    if (pre.decode) pre.decode().then(paint, paint);
    else if (pre.complete) paint();
    else { pre.onload = paint; pre.onerror = paint; }
  };
  const open = (i) => { curList = visible(); show(i, 0); lb.hidden = false; lockScroll(); };
  const close = () => { lb.hidden = true; unlockScroll(); };
  grid.addEventListener('click', (e) => {
    if (Date.now() - swipeGuard < 350) return; // 스와이프 직후 클릭 무시
    const t = e.target.closest('.gthumb');
    if (t) open(Number(t.dataset.i));
  });
  document.getElementById('lbClose').addEventListener('click', close);
  document.getElementById('lbBackdrop').addEventListener('click', close);
  document.getElementById('lbPrev').addEventListener('click', () => show(curIdx - 1, -1));
  document.getElementById('lbNext').addEventListener('click', () => show(curIdx + 1, 1));
  // 모바일: 라이트박스 좌우 스와이프로 이전/다음 사진
  let lbTx = 0, lbTy = 0;
  lb.addEventListener('touchstart', (e) => { lbTx = e.changedTouches[0].clientX; lbTy = e.changedTouches[0].clientY; }, { passive: true });
  lb.addEventListener('touchend', (e) => {
    const dx = e.changedTouches[0].clientX - lbTx;
    const dy = e.changedTouches[0].clientY - lbTy;
    if (Math.abs(dx) < 50 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
    if (dx < 0) show(curIdx + 1, 1); else show(curIdx - 1, -1);
  }, { passive: true });
  document.addEventListener('keydown', (e) => {
    if (lb.hidden) return;
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowLeft') show(curIdx - 1, -1);
    else if (e.key === 'ArrowRight') show(curIdx + 1, 1);
  });
})();


// 인스타 위젯(snapwidget)은 22KB 에 468ms 나 걸린다. 갤러리 맨 아래에 있으니
// 거기까지 내려왔을 때 부른다. 첫 화면에는 아무 영향도 주지 않는다.
(async function initIgStrip() {
  const strip = document.querySelector('.ig-strip');
  if (!strip) return;
  await whenNear(strip, '600px');
  const f = strip.querySelector('iframe');
  if (f && f.dataset.src && !f.src) f.src = f.dataset.src;
  if (!document.querySelector('script[data-snapwidget]')) {
    const s = document.createElement('script');
    s.src = 'https://snapwidget.com/js/snapwidget.js';
    s.async = true;
    s.dataset.snapwidget = '1';
    document.body.appendChild(s);
  }
})();
