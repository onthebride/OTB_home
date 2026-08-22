/* ===== 작가용 설문 읽기 전용 보기 ===== */
const sb =
  window.supabase && window.OTB_CONFIG
    ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
    : null;

const $ = (id) => document.getElementById(id);
const qs = new URLSearchParams(location.search);
const bookingId = qs.get('b');
const staffId = qs.get('s');   // 작가 번호가 실려 있으면 «확인했습니다» 단추가 붙는다
const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const esc = (s) =>
  (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const show = (el) => ['errCard', 'loadCard', 'viewCard'].forEach((id) => ($(id).hidden = $(id) !== el));

const fmtDate = (s) => (s ? String(s).slice(0, 10) : '-');
const kTime = (t) => {
  if (!t) return '-';
  const [hh, mm] = String(t).split(':').map(Number);
  return (hh < 12 ? '오전' : '오후') + ' ' + (hh % 12 === 0 ? 12 : hh % 12) + ':' + String(mm).padStart(2, '0');
};

function person(name, phone) {
  const n = esc(name || '-');
  if (!phone) return n;
  const dial = String(phone).replace(/[^0-9+]/g, '');
  return `${n} (<a class="sv-tel" href="tel:${esc(dial)}">${esc(phone)}</a>)`;
}

function renderWeddingInfo(d) {
  // 현장 진행에 필요한 것만. 앨범·출장 같은 판매/정산 항목은 빼서 중요한 게 묻히지 않게 한다.
  const opts = [];
  if (d.option_reception) opts.push('연회장 인사촬영');
  if (d.option_pyebaek) opts.push('폐백촬영');
  if (d.option_part2) opts.push('2부 촬영');
  if (d.photographer === '2인 촬영') opts.push('2인 촬영');
  const optHtml = opts.length
    ? `<div class="ss-opts">${opts.map((x) => `<span class="ss-opt${x === '2인 촬영' ? ' two' : ''}">${esc(x)}</span>`).join('')}</div>`
    : '<span class="sv-none">없음</span>';

  $('weddingInfo').innerHTML = `
    <h2>📷 촬영 정보</h2>
    <ul>
      <li><b>예식 날짜</b> ${esc(fmtDate(d.wedding_date))}${d.wedding_time ? ' ' + esc(kTime(d.wedding_time)) : ''}</li>
      <li><b>예식 장소</b> ${esc(d.wedding_venue || '-')}</li>
      <li><b>신랑</b> ${person(d.groom_name, d.groom_phone)}</li>
      <li><b>신부</b> ${person(d.bride_name, d.bride_phone)}</li>
      ${d.rep_designation ? '<li><b>촬영</b> 대표지정</li>' : ''}
      <li><b>촬영 옵션</b> ${optHtml}</li>
    </ul>`;
}

function row(label, value) {
  return value
    ? `<div class="sv-vrow"><span class="sv-vl">${esc(label)}</span><span class="sv-vv">${esc(value)}</span></div>`
    : '';
}

function renderSurvey(d) {
  const yn = (v) => (v ? '예' : '');
  const prog = Array.isArray(d.prog_items) ? d.prog_items.join(', ') : '';
  const refs = Array.isArray(d.refs) ? d.refs : [];
  const refHtml = refs.length
    ? `<div class="sv-vrow col"><span class="sv-vl">레퍼런스 (${refs.length})</span>
        <div class="sv-vrefs">${refs.map((u) => `<img src="${esc(u)}" alt="레퍼런스" loading="lazy" />`).join('')}</div></div>`
    : '';
  $('surveyBody').innerHTML = `
    <section class="sv-sec" style="border-bottom:none">
      <h2 class="sv-h">📝 설문 답변</h2>
      <div class="sv-vlist">
        ${row('촬영 우선순위', d.priority)}
        ${row('반지·청첩장 소품', yn(d.prop_ring))}
        ${row('신부대기실 요청', d.bride_room_req)}
        ${row('본식 진행항목', prog)}
        ${row('본식 중점', d.bridal_focus)}
        ${row('원판 선진행', yn(d.wonpan_first))}
        ${row('원판 조명', d.wonpan_light)}
        ${row('추가 요청', d.extra_req)}
        ${row('기타 요청', d.etc_req)}
        ${refHtml}
      </div>
    </section>`;

  // 레퍼런스 라이트박스
  $('surveyBody').addEventListener('click', (e) => {
    const im = e.target.closest('.sv-vrefs img');
    if (!im) return;
    const lb = document.createElement('div');
    lb.className = 'sv-lb';
    lb.innerHTML = `<img src="${im.src}" alt="" />`;
    lb.addEventListener('click', () => lb.remove());
    document.body.appendChild(lb);
  });
}

/* ── 작가가 «봤다» 고 남기는 자리 ──────────────────────────
   예식 하루 전쯤 대표가 이 링크를 보내면, 작가가 읽고 아래 단추를 누른다.
   링크에 작가 번호(&s=)가 실려 있을 때만 나온다 — 대표가 그냥 열어보면 안 나온다. */
const fmtAck = (iso) => {
  const d = new Date(iso);
  if (isNaN(d)) return '';
  return `${d.getMonth() + 1}월 ${d.getDate()}일 ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
};

function renderAck(d) {
  const box = $('ackBox');
  if (!d.can_ack) return;
  box.hidden = false;
  const draw = (at) => {
    box.innerHTML = at
      ? `<p class="sv-ack-done">✓ 확인하셨습니다 <span>${esc(fmtAck(at))}</span></p>`
      : `<p class="sv-ack-lead">${esc(d.staff_name || '')} 작가님, 위 내용을 확인하셨으면 눌러주세요.</p>`
        + '<button type="button" class="sv-ack-btn" id="ackBtn">확인했습니다</button>';
    const btn = $('ackBtn');
    if (!btn) return;
    btn.addEventListener('click', async () => {
      btn.disabled = true;
      btn.textContent = '저장 중…';
      const { data, error } = await sb.rpc('survey_ack', { p_booking_id: bookingId, p_staff_id: staffId });
      if (error || !data) {
        btn.disabled = false;
        btn.textContent = '확인했습니다';
        alert('저장하지 못했어요. 잠시 후 다시 눌러주세요.');
        return;
      }
      draw(data.at);
    });
  };
  draw(d.ack_at);
}

async function init() {
  if (!sb || !bookingId || !uuidRe.test(bookingId)) { show($('errCard')); return; }
  const { data, error } = await sb.rpc('survey_view', {
    p_booking_id: bookingId,
    p_staff_id: staffId && uuidRe.test(staffId) ? staffId : null,
  });
  if (error || !data) { show($('errCard')); return; }
  renderWeddingInfo(data);
  if (data.has_survey) {
    renderSurvey(data);
  } else {
    $('surveyBody').innerHTML = `<section class="sv-sec" style="border-bottom:none"><p class="sv-sub">아직 신부님이 설문을 작성하지 않았어요.</p></section>`;
  }
  renderAck(data);
  show($('viewCard'));
}

init();
