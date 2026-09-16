/* 작가 우선순위 — 미리보기 (대표 2026-09-15 «혹시 샘플 볼 수 있나?»)

   ⚠ **아직 예약 폼에 안 붙였다.** 여기서 눌러도 아무것도 저장되지 않는다.
   ⚠ 자료는 **관리자 함수**로 받는다 — 작가 이름·후기 점수는 아직 손님에게 열 것이 아니다.
     진짜로 열 때는 손님(anon)이 부를 수 있는 함수를 따로 판다 (계획 ③).
     그래서 이 화면은 **관리자로 로그인한 기기에서만** 자료가 보인다.
   ⚠ 사진은 작가마다 **열 장**만 (대표 «사진을 10개씩만 볼 수 있게»).
     누구는 239장 누구는 9장이라 그대로 두면 장수가 광고가 된다.
   ⚠ 추천 차례는 **관리자 배정 목록과 같은 셈**이다 — 후기 점수(가중)에서 감점을 뺀 값.
     감점은 화면에 안 낸다. 평가 없는 분을 만점으로 치지 않는다(뒤로 보낸다). */

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const won = (n) => Number(n || 0).toLocaleString('ko-KR') + '원';
/* 날짜는 어디서나 한 모양 — 26.09.05 (관리자·작가 화면과 같다) */
const ymd = (v) => {
  if (!v) return '';
  const d = new Date(String(v).slice(0, 10) + 'T00:00:00');
  if (isNaN(d)) return String(v);
  const p = (x) => String(x).padStart(2, '0');
  return `${p(d.getFullYear() % 100)}.${p(d.getMonth() + 1)}.${p(d.getDate())}`;
};

const C = window.OTB_CONFIG || {};
const sb = window.supabase && C.SUPABASE_URL ? window.supabase.createClient(C.SUPABASE_URL, C.SUPABASE_KEY) : null;

const BASE = 550000;       // 베이직 (홈 가격표와 같은 값)
/* 대표 2026-09-16 «그 작가 우선순위고르는건 무료로 하자 / 지정을 원하면 이제 돈을 내고»
   → 우선순위는 **무료**. 값은 지정에만 붙는다.
   ⚠ 작가가 제 금액을 안 정했으면(또는 0으로 뒀으면) **확정값 3만원**이고 그래도 팔린다
     (대표 «금액 없으면 지정값 3만원»). 「안 팔린다」가 아니다 */
const PIN_DEFAULT = 30000;
const SHOTS = 10;          // 작가마다 보여줄 사진
const SLOTS = 3;           // 1·2·3순위
const OPEN = {};           // 후기를 펴 둔 작가 (id → true)

let staff = [];            // [{id, name, score, n, fee, shots:[url], says:[{d, overall, msg}]}]
let picked = [];           // 우선순위로 고른 작가 id (차례 그대로)
let pinned = null;         // 지정한 작가 id (한 명)

/* ── 자료 받기 ──
   후기·작가·갤러리 셋은 서로 독립이라 한 번에 부른다 */
async function load() {
  if (!sb) { $('psList').innerHTML = '<p class="ps-empty">연결 설정을 못 읽었습니다.</p>'; return; }
  const [sr, fr, pr, gr] = await Promise.all([
    sb.rpc('admin_staff_list'),
    sb.rpc('admin_feedback', { p_days: 3650 }),
    sb.rpc('admin_penalties'),
    sb.rpc('gallery_list'),
  ]);
  if (sr.error || !sr.data) {
    $('psList').innerHTML = '<p class="ps-empty">관리자로 로그인한 기기에서 열어주세요.<br />'
      + '(작가 이름·후기는 아직 손님에게 여는 자료가 아니라 관리자 함수로 받습니다)</p>';
    return;
  }
  /* 후기는 **이름으로** 온다 (admin_feedback 의 staff 묶음). 한 줄은
     { staff_name, avg_score, n, ... } — name·score 가 아니다.
     감점은 작가 번호로 온다. admin.js 의 loadStaffScores 와 같은 방식으로 붙인다 */
  const fb = {};
  ((fr.data && fr.data.staff) || []).forEach((x) => { fb[x.staff_name] = x; });
  const pen = (pr.data && pr.data.sum) || {};
  /* 신부님이 읽을 후기 글 (대표 2026-09-15 «후기를 볼 수 있나? 접었다 폈다 할 수 있고»).
     ⚠ **손님 이름은 안 낸다.** 예식일과 한마디만 — 관리자의 「작가에게 공유」와 같은 규칙이다.
     ⚠ 아쉬운 점(issue_text)도 안 낸다. 그건 우리가 고치려고 받는 것이지 광고가 아니다.
       넣을지는 대표가 정하실 일이라 여쭤둔다.
     ⚠ 한마디가 없는 응답은 읽을 것이 없으니 건너뛴다 (지금 25건 중 21건에 한마디가 있다) */
  const says = {};
  ((fr.data && fr.data.items) || []).forEach((x) => {
    const msg = x.message || x.next_req;
    if (!msg) return;
    (says[x.staff_name] = says[x.staff_name] || []).push({
      d: String(x.wedding_date || '').slice(0, 10), overall: x.overall, msg });
  });
  // 갤러리: 작가별로 최근 것부터 (gallery_list 가 이미 sort · 최신순으로 준다)
  const shots = {};
  ((gr.data) || []).forEach((g) => {
    if (!g.staff_id || !g.image_url) return;
    (shots[g.staff_id] = shots[g.staff_id] || []).push(g.image_url);
  });

  /* ⚠ 서브 전용은 뺀다 (대표 «서브는 빼고»). 활성 + 메인 가능만.
     대표도 넣는다 (대표 «나도 넣어 그냥 우선순위니까») */
  staff = (sr.data || [])
    .filter((s) => s.active && s.can_main !== false)
    .map((s) => {
      const f = fb[s.name] || {};
      const p = Number(pen[s.id] && pen[s.id].total) || 0;
      // 감점을 뺀 값으로 줄을 세운다 — 관리자 배정 목록과 같은 셈. 감점 자체는 화면에 안 낸다
      const base = f.avg_score == null ? null : Number(f.avg_score);
      const score = base == null ? null : Math.round((base - p) * 10) / 10;
      /* 지정비 — 작가가 제 캘린더에서 정한 값. 안 정했거나 0이면 확정값 3만원
         (대표 2026-09-16 «금액 없으면 지정값 3만원») */
      return { id: s.id, name: s.name, score, n: Number(f.n || 0),
        fee: Number(s.pick_fee) || PIN_DEFAULT,
        shots: (shots[s.id] || []).slice(0, SHOTS), says: says[s.name] || [] };
    })
    // 추천 차례: 점수 높은 순. 평가 없는 분은 뒤로 (만점으로 치지 않는다)
    .sort((a, b) => (b.score == null ? -1 : b.score) - (a.score == null ? -1 : a.score)
      || a.name.localeCompare(b.name, 'ko'));

  render();
}

/* ── 그리기 ── */
function render() {
  const wish = $('psOn').checked;
  const pin = $('psPin').checked;
  const on = wish || pin;
  $('psPick').hidden = !on;

  /* 값은 **지정에만** 붙는다. 우선순위는 무료다.
     지정 값은 고른 분에 따라 달라지므로, 고르기 전에는 줄을 아예 안 보여준다 */
  const pinOne = pin && pinned ? staff.find((x) => x.id === pinned) : null;
  const fee = pinOne ? pinOne.fee : 0;
  $('psFeeRow').hidden = !fee;
  if (fee) {
    $('psFeeName').textContent = '작가 지정 · ' + pinOne.name;
    $('psFeeAmt').textContent = '+' + won(fee);
  }
  $('psSum').textContent = won(BASE + fee);
  // 「+3만원부터」 — 제일 싼 분을 기준으로 적는다. 아직 못 받았으면 확정값으로
  const low = staff.length ? Math.min.apply(null, staff.map((s) => s.fee)) : PIN_DEFAULT;
  if ($('psPinPrice')) $('psPinPrice').textContent = '+' + won(low) + '부터';

  // 고른 세 자리 — 우선순위일 때만 (지정은 한 분이라 자리가 없다)
  $('psPicked').hidden = !wish;
  $('psPicked').innerHTML = !wish ? '' : Array.from({ length: SLOTS }, (_, i) => {
    const id = picked[i];
    const s = id && staff.find((x) => x.id === id);
    return '<div class="ps-slot' + (s ? ' on' : '') + '">'
      + '<i>' + (i + 1) + '순위</i>'
      + (s ? '<b>' + esc(s.name) + '</b><button type="button" class="ps-x" data-drop="' + esc(s.id) + '">빼기</button>'
           : '<span class="dim">아직</span>')
      + '</div>';
  }).join('');

  $('psList').innerHTML = staff.length ? staff.map((s, i) => {
    const at = picked.indexOf(s.id);
    const rec = i < 3 ? '<span class="ps-rec">추천 ' + (i + 1) + '위</span>' : '';
    /* ⚠ 「아직 적어요」 같은 단서는 뺐다 (대표 2026-09-15 «후기 아직 적어요 이런건 빼고»).
       신부님께는 점수와 건수만 담백하게 */
    const score = s.score == null
      ? '<span class="ps-none">아직 받은 후기가 없어요</span>'
      : '<span class="ps-score">후기 ' + s.score + '점 <span class="thin">(' + s.n + '건)</span></span>';
    const shots = s.shots.length
      ? '<div class="ps-shots">' + s.shots.map((u) =>
        '<img loading="lazy" src="' + esc(u) + '" alt="' + esc(s.name) + ' 작가 사진" data-big="' + esc(u) + '" />').join('') + '</div>'
      : '<p class="ps-noshot">아직 올라간 사진이 없어요</p>';
    /* 후기 읽기 — 접었다 폈다 (대표 2026-09-15).
       ⚠ 화살표는 **누르면 벌어질 일**을 가리킨다 — 접혀 있으면 ∨, 펴져 있으면 ∧ (CLAUDE.md) */
    const open = !!OPEN[s.id];
    const says = !s.says.length ? ''
      : '<button type="button" class="ps-more" data-says="' + esc(s.id) + '" aria-expanded="' + (open ? 'true' : 'false') + '">'
        + '후기 ' + s.says.length + '개 ' + (open ? '접기 <i>∧</i>' : '읽어보기 <i>∨</i>') + '</button>'
        + (open ? '<div class="ps-says">' + s.says.map((v) =>
          '<div class="ps-say"><p class="ps-say-m">' + esc(v.msg) + '</p>'
          + '<p class="ps-say-d">' + esc(ymd(v.d)) + (v.overall != null ? ' · ' + v.overall + '/10' : '') + '</p></div>').join('') + '</div>' : '');
    /* 누르는 것이 무엇이냐가 갈래마다 다르다.
       ⚠ 지정은 **금액을 단추에 적는다** — 누르면 합계가 얼마나 오르는지를 누르기 전에 봐야 한다 */
    const isPin = pinned === s.id;
    const btn = pin
      ? '<button type="button" class="ps-take' + (isPin ? ' off' : '') + '" data-pin="' + esc(s.id) + '">'
        + (isPin ? '지정함 — 빼기' : '지정하기 <b>+' + esc(won(s.fee)) + '</b>') + '</button>'
      : '<button type="button" class="ps-take' + (at >= 0 ? ' off' : '') + '" data-take="' + esc(s.id) + '">'
        + (at >= 0 ? (at + 1) + '순위 — 빼기' : picked.length >= SLOTS ? '자리 다 참' : '고르기')
        + '</button>';
    return '<div class="ps-item' + ((pin ? isPin : at >= 0) ? ' chosen' : '') + '">'
      + '<div class="ps-head"><span class="ps-name">' + esc(s.name) + '</span>' + rec + score
      + btn + '</div>'
      + shots + says + '</div>';
  }).join('') : '<p class="ps-empty">작가가 없습니다.</p>';

  $('psFoot').textContent = !on ? ''
    : pin ? (pinOne ? pinOne.name + ' 작가님으로 지정하셨어요. 그 작가님이 촬영합니다.'
      : '한 분을 골라주세요.')
      : picked.length === 0 ? '세 분까지 고르실 수 있어요.'
        : picked.length < SLOTS ? picked.length + '분 고르셨어요. ' + (SLOTS - picked.length) + '자리 남았습니다.'
          /* ⚠ 「이 중 한 분이 촬영합니다」 라고 쓰지 않는다 — 그건 약속이 된다 (대표 «격하»).
             위 안내와 **같은 말**로 둔다 — 한 화면에서 말이 갈리면 안 된다 */
          : '세 분 다 고르셨어요. 가능한 맞춰드릴게요.';

  bind();
}

function bind() {
  document.querySelectorAll('[data-take]').forEach((b) => b.addEventListener('click', () => {
    const id = b.dataset.take;
    const at = picked.indexOf(id);
    if (at >= 0) picked.splice(at, 1);
    else if (picked.length < SLOTS) picked.push(id);
    render();
  }));
  document.querySelectorAll('[data-pin]').forEach((b) => b.addEventListener('click', () => {
    // 지정은 **한 분**이다. 다른 분을 누르면 갈아탄다 (앞의 분을 먼저 빼게 하지 않는다)
    pinned = pinned === b.dataset.pin ? null : b.dataset.pin;
    render();
  }));
  document.querySelectorAll('[data-drop]').forEach((b) => b.addEventListener('click', () => {
    const at = picked.indexOf(b.dataset.drop);
    if (at >= 0) picked.splice(at, 1);
    render();
  }));
  document.querySelectorAll('[data-says]').forEach((b) => b.addEventListener('click', () => {
    OPEN[b.dataset.says] = !OPEN[b.dataset.says];
    render();
  }));
  document.querySelectorAll('[data-big]').forEach((im) => im.addEventListener('click', () => {
    $('psLbImg').src = im.dataset.big;
    $('psLb').hidden = false;
    if (window.otbLockScroll) window.otbLockScroll();
  }));
}

/* 둘은 같이 못 고른다 (대표 «지정이 있으면 자동으로 우선순위에서 빠진다»).
   한쪽을 켜면 다른 쪽이 꺼지고, 꺼진 쪽이 고른 것도 지운다 —
   남겨두면 다시 켰을 때 «내가 언제 이걸 골랐지» 가 된다 */
$('psOn').addEventListener('change', () => {
  if ($('psOn').checked) { $('psPin').checked = false; pinned = null; } else picked = [];
  render();
});
$('psPin').addEventListener('change', () => {
  if ($('psPin').checked) { $('psOn').checked = false; picked = []; } else pinned = null;
  render();
});
$('psLb').addEventListener('click', () => {
  $('psLb').hidden = true;
  $('psLbImg').src = '';
  if (window.otbUnlockScroll) window.otbUnlockScroll();
});

render();
load();
