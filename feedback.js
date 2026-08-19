/* ===== 촬영 후 설문 (작가 현장 진행 평가) =====
   링크: /f?b=<예약ID>  — 예식 다음날 오전 10시 알림톡(G)으로 발송.
   저장은 feedback_submit RPC. 응답은 관리자만 열람한다. */
const sb = window.supabase && window.OTB_CONFIG
  ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
  : null;

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const bookingId = params.get('b');
const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const esc = (s) => (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const show = (el) => ['errCard', 'loadCard', 'mainCard', 'doneCard', 'thanksCard'].forEach((id) => ($(id).hidden = $(id) !== el));

// 1~10점. 5점일 때보다 가운데를 고를 자리가 넓어진다.
const STAR_TXT = ['', '많이 아쉬웠어요', '많이 아쉬웠어요', '아쉬웠어요', '아쉬웠어요',
  '보통이었어요', '보통이었어요', '좋았어요', '좋았어요', '정말 좋았어요', '더할 나위 없었어요'];
const STAR_N = 10;
const scores = {};   // { overall: 5, kindness: 4, ... }

// 별점 10개를 버튼으로 그린다 (한 줄에 고르게 나눠 터치가 쉽게, 고르면 점수와 문구를 같이 표시)
function buildStars() {
  document.querySelectorAll('.fb-stars').forEach((wrap) => {
    const k = wrap.dataset.k;
    wrap.innerHTML =
      '<div class="fb-star-row">'
      + Array.from({ length: STAR_N }, (_, i) => i + 1).map((n) =>
        `<button type="button" class="fb-star" data-n="${n}" aria-label="${n}점" role="radio" aria-checked="false">★</button>`).join('')
      + '</div><div class="fb-scale"><span>1 아쉬움</span><span>10 최고</span></div>'
      + '<span class="fb-star-txt"></span>';
    wrap.addEventListener('click', (e) => {
      const btn = e.target.closest('.fb-star');
      if (!btn) return;
      const n = Number(btn.dataset.n);
      scores[k] = n;
      wrap.querySelectorAll('.fb-star').forEach((b) => {
        const on = Number(b.dataset.n) <= n;
        b.classList.toggle('on', on);
        b.setAttribute('aria-checked', String(Number(b.dataset.n) === n));
      });
      wrap.querySelector('.fb-star-txt').textContent = n + '점 · ' + STAR_TXT[n];
      wrap.classList.remove('miss');
    });
  });
}

async function load() {
  if (!sb || !bookingId || !uuidRe.test(bookingId)) { show($('errCard')); return; }
  const { data, error } = await sb.rpc('feedback_ctx', { p_booking_id: bookingId });
  if (error || !data) { show($('errCard')); return; }
  if (data.cancelled) { show($('errCard')); return; }
  if (data.done) { show($('doneCard')); return; }

  $('fbName').textContent = data.contractor_name || '고객';
  $('fbStaff').textContent = data.staff_name || '담당';
  const d = data.wedding_date ? String(data.wedding_date).slice(0, 10).replace(/-/g, '. ') : '';
  $('fbMeta').textContent = [d, data.wedding_venue].filter(Boolean).join(' · ');
  buildStars();
  show($('mainCard'));
}

// '있었어요' 고르면 입력칸 열기
document.addEventListener('change', (e) => {
  if (e.target.name === 'issue') $('issueBox').hidden = e.target.value !== '1';
});

$('fbSubmit').addEventListener('click', async () => {
  const btn = $('fbSubmit');
  const st = $('fbStatus');
  const arrival = document.querySelector('input[name="arrival"]:checked');
  const issueEl = document.querySelector('input[name="issue"]:checked');

  // 빠뜨린 항목 표시 후 그 자리로 이동
  let firstMiss = null;
  document.querySelectorAll('.fb-stars').forEach((w) => {
    const bad = !scores[w.dataset.k];
    w.classList.toggle('miss', bad);
    if (bad && !firstMiss) firstMiss = w;
  });
  [['arrivalWrap', !arrival], ['issueWrap', !issueEl]].forEach(([id, bad]) => {
    $(id).classList.toggle('miss', bad);
    if (bad && !firstMiss) firstMiss = $(id);
  });
  if (firstMiss) {
    st.className = 'fb-status err';
    st.textContent = '별표가 비어 있는 항목이 있어요.';
    firstMiss.scrollIntoView({ behavior: 'smooth', block: 'center' });
    return;
  }

  btn.disabled = true;
  st.className = 'fb-status';
  st.textContent = '보내는 중…';
  const payload = {
    overall: scores.overall,
    arrival: arrival.value,
    kindness: scores.kindness,
    requests: scores.requests,
    flow: scores.flow,
    issue: issueEl.value === '1',
    issue_text: issueEl.value === '1' ? $('f_issue_text').value.trim() : '',
    message: $('f_message').value.trim(),
  };
  const { data, error } = await sb.rpc('feedback_submit', { p_booking_id: bookingId, payload });
  if (error) {
    btn.disabled = false;
    st.className = 'fb-status err';
    st.textContent = '전송에 실패했어요. 잠시 후 다시 시도해 주세요. (' + esc(error.message) + ')';
    return;
  }
  show(data && data.already ? $('doneCard') : $('thanksCard'));
  window.scrollTo({ top: 0 });
});

load();
