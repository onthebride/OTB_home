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

const C = window.OTB_CONFIG || {};
const sb = window.supabase && C.SUPABASE_URL ? window.supabase.createClient(C.SUPABASE_URL, C.SUPABASE_KEY) : null;

const BASE = 550000;       // 베이직 (홈 가격표와 같은 값)
const FEE = 30000;         // 우선순위 (대표 2026-09-15 «3만원 괜찮은거 같네»)
const SHOTS = 10;          // 작가마다 보여줄 사진
const SLOTS = 3;           // 1·2·3순위
const THIN = 3;            // 응답이 이만큼 아래면 「응답 적음」이라 적는다

let staff = [];            // [{id, name, score, n, shots:[url]}]
let picked = [];           // 고른 작가 id (차례 그대로)

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
      return { id: s.id, name: s.name, score, n: Number(f.n || 0), shots: (shots[s.id] || []).slice(0, SHOTS) };
    })
    // 추천 차례: 점수 높은 순. 평가 없는 분은 뒤로 (만점으로 치지 않는다)
    .sort((a, b) => (b.score == null ? -1 : b.score) - (a.score == null ? -1 : a.score)
      || a.name.localeCompare(b.name, 'ko'));

  render();
}

/* ── 그리기 ── */
function render() {
  const on = $('psOn').checked;
  $('psPick').hidden = !on;
  $('psFeeRow').hidden = !on;
  $('psSum').textContent = won(BASE + (on ? FEE : 0));

  // 고른 세 자리
  $('psPicked').innerHTML = Array.from({ length: SLOTS }, (_, i) => {
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
    const score = s.score == null
      ? '<span class="ps-none">아직 받은 후기가 없어요</span>'
      : '<span class="ps-score">후기 ' + s.score + '점'
        + (s.n < THIN ? ' <span class="thin">(' + s.n + '건 · 아직 적어요)</span>' : ' <span class="thin">(' + s.n + '건)</span>')
        + '</span>';
    const shots = s.shots.length
      ? '<div class="ps-shots">' + s.shots.map((u) =>
        '<img loading="lazy" src="' + esc(u) + '" alt="' + esc(s.name) + ' 작가 사진" data-big="' + esc(u) + '" />').join('') + '</div>'
      : '<p class="ps-noshot">아직 올라간 사진이 없어요</p>';
    return '<div class="ps-item' + (at >= 0 ? ' chosen' : '') + '">'
      + '<div class="ps-head"><span class="ps-name">' + esc(s.name) + '</span>' + rec + score
      + '<button type="button" class="ps-take' + (at >= 0 ? ' off' : '') + '" data-take="' + esc(s.id) + '">'
      + (at >= 0 ? (at + 1) + '순위 — 빼기' : picked.length >= SLOTS ? '자리 다 참' : '고르기')
      + '</button></div>'
      + shots + '</div>';
  }).join('') : '<p class="ps-empty">작가가 없습니다.</p>';

  $('psFoot').textContent = !on ? ''
    : picked.length === 0 ? '세 분까지 고르실 수 있어요.'
      : picked.length < SLOTS ? picked.length + '분 고르셨어요. ' + (SLOTS - picked.length) + '자리 남았습니다.'
        : '세 분 다 고르셨어요. 이 중 한 분이 촬영합니다.';

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
  document.querySelectorAll('[data-drop]').forEach((b) => b.addEventListener('click', () => {
    const at = picked.indexOf(b.dataset.drop);
    if (at >= 0) picked.splice(at, 1);
    render();
  }));
  document.querySelectorAll('[data-big]').forEach((im) => im.addEventListener('click', () => {
    $('psLbImg').src = im.dataset.big;
    $('psLb').hidden = false;
    if (window.otbLockScroll) window.otbLockScroll();
  }));
}

$('psOn').addEventListener('change', () => { if (!$('psOn').checked) picked = []; render(); });
$('psLb').addEventListener('click', () => {
  $('psLb').hidden = true;
  $('psLbImg').src = '';
  if (window.otbUnlockScroll) window.otbUnlockScroll();
});

render();
load();
