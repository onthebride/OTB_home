/* ===== 신부님 후기 모아보기 (/reviews) — 대표 요청 2026-08-27
   «후기 모아보기같은것도 홈페이지에 게시되면 좋겠어»

   두 갈래를 한 자리에 놓는다:
     · 촬영 후기  — 우리 설문에 남겨주신 글 (본문을 그대로 싣는다)
     · 블로그·카페 — 신부님이 밖에 올리신 글 (남의 사이트라 **링크만** 건다)

   ⚠ 여기서 부르는 `reviews_public()` 은 **실은 것만, 가린 이름으로만** 낸다.
   이 화면은 feedback·bookings 를 아예 안 건드린다 — 실수로도 고객 정보가 샐 길이 없게. */
const sb = window.supabase && window.OTB_CONFIG
  ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
  : null;

const $ = (id) => document.getElementById(id);
const esc = (s) => (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

let all = [];
let kind = 'all';

function meta(r) {
  // 예식장·날짜는 있는 것만 붙인다. 없다고 「-」를 늘어놓으면 지저분하다
  const bits = [];
  if (r.venue) bits.push(esc(r.venue));
  if (r.ym) bits.push(esc(r.ym));
  return bits.length ? `<p class="rv-meta">${bits.join(' · ')}</p>` : '';
}

function card(r) {
  const who = esc(r.who || '신부님');
  if (r.kind === 'survey') {
    return `
    <article class="rv-card rv-survey">
      <p class="rv-body">${esc(r.body || '')}</p>
      <p class="rv-who">${who} 님</p>
      ${meta(r)}
    </article>`;
  }
  // 밖에 올리신 글 — 본문을 옮겨오지 않는다. 남의 사이트 글이다
  return `
  <article class="rv-card rv-link">
    <p class="rv-site">${esc(r.site || '블로그')}</p>
    <p class="rv-who">${who} 님</p>
    ${meta(r)}
    <a class="rv-go" href="${esc(r.url)}" target="_blank" rel="noopener nofollow">후기 보러 가기 →</a>
  </article>`;
}

function render() {
  const rows = kind === 'all' ? all : all.filter((r) => r.kind === kind);
  const body = $('rvBody');
  if (!rows.length) { body.innerHTML = '<p class="rv-empty">아직 올라온 후기가 없습니다.</p>'; return; }
  body.innerHTML = `<div class="rv-grid">${rows.map(card).join('')}</div>`;
}

function tabs() {
  const box = $('rvTabs');
  const has = (k) => all.some((r) => r.kind === k);
  // 한 갈래밖에 없으면 고르는 칸이 필요 없다
  if (!has('survey') || !has('link')) return;
  box.hidden = false;
  box.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-rvk]');
    if (!b) return;
    kind = b.dataset.rvk;
    box.querySelectorAll('button[data-rvk]').forEach((x) => x.classList.toggle('active', x === b));
    render();
  });
}

(async function load() {
  const body = $('rvBody');
  if (!sb) { body.innerHTML = '<p class="rv-empty">후기를 불러오지 못했습니다.</p>'; return; }
  const { data, error } = await sb.rpc('reviews_public');
  if (error || !Array.isArray(data)) {
    body.innerHTML = '<p class="rv-empty">후기를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.</p>';
    return;
  }
  all = data;
  if (!all.length) { render(); return; }
  tabs();
  render();
  $('rvNote').hidden = false;
})();
