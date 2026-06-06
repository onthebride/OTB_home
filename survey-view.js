/* ===== 작가용 설문 읽기 전용 보기 ===== */
const sb =
  window.supabase && window.OTB_CONFIG
    ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
    : null;

const $ = (id) => document.getElementById(id);
const bookingId = new URLSearchParams(location.search).get('b');
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
  const n = name || '-';
  return phone ? `${n} (${phone})` : n;
}

function renderWeddingInfo(d) {
  const opts = [];
  if (d.option_reception) opts.push('연회장 인사촬영');
  if (d.option_pyebaek) opts.push('폐백촬영');
  if (d.option_part2) opts.push('2부 촬영');
  if (d.option_album) opts.push('앨범 1권 추가');
  if (d.photographer && d.photographer !== '기본') opts.push(d.photographer);
  if (d.travel_fee) opts.push('출장');
  const optText = opts.length ? opts.join(', ') : '없음';

  $('weddingInfo').innerHTML = `
    <h2>📷 촬영 정보</h2>
    <ul>
      <li><b>예식 날짜</b> ${esc(fmtDate(d.wedding_date))}${d.wedding_time ? ' ' + esc(kTime(d.wedding_time)) : ''}</li>
      <li><b>예식 장소</b> ${esc(d.wedding_venue || '-')}</li>
      <li><b>신랑</b> ${esc(person(d.groom_name, d.groom_phone))}</li>
      <li><b>신부</b> ${esc(person(d.bride_name, d.bride_phone))}</li>
      <li><b>촬영 옵션</b> ${esc(optText)}</li>
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

async function init() {
  if (!sb || !bookingId || !uuidRe.test(bookingId)) { show($('errCard')); return; }
  const { data, error } = await sb.rpc('survey_view', { p_booking_id: bookingId });
  if (error || !data) { show($('errCard')); return; }
  renderWeddingInfo(data);
  if (data.has_survey) {
    renderSurvey(data);
  } else {
    $('surveyBody').innerHTML = `<section class="sv-sec" style="border-bottom:none"><p class="sv-sub">아직 신부님이 설문을 작성하지 않았어요.</p></section>`;
  }
  show($('viewCard'));
}

init();
