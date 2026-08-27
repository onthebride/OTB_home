/* ===== 신부님 후기 모아보기 (/reviews) — 대표 요청 2026-08-27
   «후기 모아보기같은것도 홈페이지에 게시되면 좋겠어»
   «일반 후기와 설문후기로 분류해줘 / 일반 후기는 블로그나 이벤트 참여한거»
   «설문후기 » 촬영 후 설문 후기로 변경 / 신부이름대신 작가이름으로 변경»

   두 갈래를 **위아래로 갈라** 놓는다. 한 화면에서 둘 다 보인다:
     · 일반 후기        — 신부님이 블로그·카페에 올리신 글. **링크만** 건다
     · 촬영 후 설문 후기 — 우리 설문에 남겨주신 글. 본문을 그대로 싣는다

   ⚠ 이름은 갈래마다 다르다: 일반 후기는 **신부님(김○○)**, 설문 후기는 **작가**.
   신부님 이름은 **넣을 때 이미 가려서** 담긴 것만 나간다 — 원본은 표에 없다.
   이 화면은 feedback·bookings 를 아예 안 건드린다 — 실수로도 고객 정보가 샐 길이 없게. */
const sb = window.supabase && window.OTB_CONFIG
  ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
  : null;

const $ = (id) => document.getElementById(id);
const esc = (s) => (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// 폰에서 머리말 메뉴 펼치기. 홈의 main.js 는 홈 전용이라 여기서 이 한 가지만 따로 둔다
(function navInit() {
  const toggle = document.querySelector('.nav-toggle');
  const menu = document.querySelector('.nav-menu');
  if (!toggle || !menu) return;
  toggle.addEventListener('click', () => menu.classList.toggle('open'));
  menu.querySelectorAll('a').forEach((a) => a.addEventListener('click', () => menu.classList.remove('open')));
})();

/* 갈래마다 적는 이름이 다르다 (대표 지시 2026-08-27):
     · 일반 후기        = 신부님이 직접 쓰신 글 → 쓰신 분 (김○○ 님)
     · 촬영 후 설문 후기 = 작가에 대한 평      → 누구를 두고 한 말인지 (김병훈 작가)
   둘 다 없으면 그 줄을 아예 안 그린다 — 「미지정」 을 손님께 보일 필요가 없다 */
const brideLine = (r) => (r.who ? `<p class="rv-who">${esc(r.who)} 님</p>` : '');
const staffLine = (r) => (r.staff ? `<p class="rv-who">${esc(r.staff)} 작가</p>` : '');
/* 예식장만 적는다. 날짜는 뺐다 (대표 «날짜 기니까 박스가 다른거랑 크기가 달라 /
   딱히 의미가 없으니») — 예식장 이름이 길면 날짜가 다음 줄로 넘어가 카드 키가 제각각이 됐다.
   자료(ym)는 그대로 받아둔다. 나중에 다시 넣자고 하면 한 줄이면 된다 */
const metaLine = (r) => (r.venue ? `<p class="rv-meta">${esc(r.venue)}</p>` : '');

// 설문 글 — 본문이 주인공이라 위에 놓고, 누구를 두고 한 말인지는 아래에
function surveyCard(r) {
  return `
  <article class="rv-card rv-survey">
    <p class="rv-body">${esc(r.body || '')}</p>
    <div class="rv-foot">${staffLine(r)}${metaLine(r)}</div>
  </article>`;
}

/* 밖에 올리신 글 — 본문을 옮겨오지 않는다. 남의 사이트 글이다.
   대표가 그린 대로 «이름 / 홀 이름 / 후기 링크» 석 줄만.
   어디에 올린 글인지(블로그·카페) 딱지는 뺐다 — 대표 말대로 손님에겐 구분이 안 된다 */
function linkCard(r) {
  // 주소는 href 에 그대로 둔다 — 새 탭으로 열기·주소 복사·검색엔진이 다 이걸 본다.
  // 창으로 띄우는 건 그 위에 얹는 것뿐이라, 스크립트가 죽어도 링크는 살아 있다
  return `
  <a class="rv-card rv-link" href="${esc(r.url)}" target="_blank" rel="noopener nofollow"
     data-rvopen="${esc(r.url)}" data-rvwho="${esc(r.who || '')}" data-rvvenue="${esc(r.venue || '')}">
    ${brideLine(r)}
    ${metaLine(r)}
    <span class="rv-go">후기 보러 가기 ›</span>
  </a>`;
}

/* ===== 후기 글을 이 자리에서 보여주는 창 (대표 «새창 말고 팝업형식으로 가능? 좀 무겁나?»)

   무겁지 않다 — 창은 **누를 때만** 남의 글을 불러온다. 안 누르면 아무것도 안 받는다.
   다만 남의 사이트를 끼워 넣는 것이라 **안 열릴 수 있다**:
     · 네이버 카페는 헤더로 아예 막는다 (x-frame-options: SAMEORIGIN)
     · 블로그는 지금은 열리지만 언제 막힐지 모른다
   그래서 ①못 열 곳은 아예 새 탭으로 보내고 ②열다 안 되면 안내와 함께 새 탭 단추를 준다.
   어느 쪽으로 넘어져도 후기는 볼 수 있다. */
const CANT_FRAME = /cafe\.naver|cafe\.daum|instagram/i;   // 끼워 넣기를 막는 곳
let rvTimer = null;

function modalInit() {
  const box = $('rvModal'), frame = $('rvFrame'), msg = $('rvModalMsg');
  if (!box || !frame) return;

  const close = () => {
    box.hidden = true;
    frame.removeAttribute('src');            // 소리·영상이 계속 도는 것을 막는다
    document.body.style.overflow = '';
    if (rvTimer) { clearTimeout(rvTimer); rvTimer = null; }
  };
  const fail = () => {
    frame.style.visibility = 'hidden';
    msg.hidden = false;
    msg.innerHTML = '이 글은 여기서 바로 보여드릴 수 없습니다.<br />오른쪽 위 <b>새 창으로 열기</b>를 눌러주세요.';
  };

  document.body.addEventListener('click', (e) => {
    const a = e.target.closest('[data-rvopen]');
    if (!a) return;
    const url = a.dataset.rvopen;
    if (CANT_FRAME.test(url)) return;         // 막힌 곳은 손대지 않는다 — 원래대로 새 탭
    e.preventDefault();

    $('rvModalT').textContent = [a.dataset.rvwho && a.dataset.rvwho + ' 님', a.dataset.rvvenue]
      .filter(Boolean).join(' · ');
    $('rvModalOpen').href = url;
    msg.hidden = false;
    msg.textContent = '불러오는 중입니다…';
    frame.style.visibility = 'hidden';
    frame.src = url;
    box.hidden = false;
    document.body.style.overflow = 'hidden';

    // 막히면 onload 가 안 오거나 빈 화면이 온다. 기다리다 안 되면 안내로 바꾼다
    if (rvTimer) clearTimeout(rvTimer);
    rvTimer = setTimeout(fail, 6000);
  });

  frame.addEventListener('load', () => {
    if (!frame.src) return;
    if (rvTimer) { clearTimeout(rvTimer); rvTimer = null; }
    msg.hidden = true;
    frame.style.visibility = 'visible';
  });
  frame.addEventListener('error', fail);

  $('rvModalX').addEventListener('click', close);
  $('rvModalBg').addEventListener('click', close);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !box.hidden) close(); });
}
modalInit();

function section(title, desc, rows, card, cls) {
  if (!rows.length) return '';
  return `
  <section class="rv-sec ${cls}">
    <h3 class="rv-sec-t">${title} <span class="rv-sec-n">${rows.length}</span></h3>
    <p class="rv-sec-d">${desc}</p>
    <div class="rv-grid">${rows.map(card).join('')}</div>
  </section>`;
}

(async function load() {
  const body = $('rvBody');
  if (!sb) { body.innerHTML = '<p class="rv-empty">후기를 불러오지 못했습니다.</p>'; return; }
  const { data, error } = await sb.rpc('reviews_public');
  if (error || !Array.isArray(data)) {
    body.innerHTML = '<p class="rv-empty">후기를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.</p>';
    return;
  }
  if (!data.length) { body.innerHTML = '<p class="rv-empty">아직 올라온 후기가 없습니다.</p>'; return; }

  const links = data.filter((r) => r.kind === 'link');
  const surveys = data.filter((r) => r.kind === 'survey');
  body.innerHTML =
    section('일반 후기', '블로그와 웨딩카페에 직접 올려주신 글입니다. 누르시면 그 글로 이동합니다.',
      links, linkCard, 'rv-sec-link')
    + section('촬영 후 설문 후기', '촬영이 끝난 뒤 보내드린 설문에 남겨주신 글입니다. 받은 그대로 싣습니다.',
      surveys, surveyCard, 'rv-sec-survey');
  $('rvNote').hidden = false;
})();
