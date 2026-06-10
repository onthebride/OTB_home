/* ===== 작가 예식 전 스케줄 확인 ===== */
const sb = window.supabase && window.OTB_CONFIG
  ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
  : null;

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
let staffId = params.get('s');
let bookingId = params.get('b');
const shortCode = params.get('k');
const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const esc = (s) => (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const show = (el) => ['errCard', 'loadCard', 'mainCard'].forEach((id) => ($(id).hidden = $(id) !== el));

const WD = ['일', '월', '화', '수', '목', '금', '토'];
function fmt(d) {
  if (!d) return '-';
  const dt = new Date(String(d).slice(0, 10) + 'T00:00:00');
  return `${dt.getFullYear()}.${dt.getMonth() + 1}.${dt.getDate()} (${WD[dt.getDay()]})`;
}
function opts(w) {
  const o = [];
  if (w.option_reception) o.push('연회장 인사촬영');
  if (w.option_pyebaek) o.push('폐백촬영');
  if (w.option_part2) o.push('2부 촬영');
  if (w.option_album) o.push('앨범 1권 추가');
  (Array.isArray(w.custom_options) ? w.custom_options : []).forEach((c) => { if (c && c.name) o.push(c.name); });
  return o;
}

function card(w) {
  const c = w.chk || {};
  const done = c.attend && c.arrival && c.options;
  const o = opts(w);
  return `
  <div class="ss-card${done ? ' done' : ''}" data-bid="${w.booking_id}">
    <div class="ss-head">
      <span class="ss-date">${esc(fmt(w.wedding_date))} ${esc(w.wedding_time || '')}</span>
      <span class="ss-role ${w.role === '서브' ? 'sub' : 'main'}">${esc(w.role)}작가</span>
      ${done ? '<span class="ss-doneflag">확인완료 ✓</span>' : ''}
    </div>
    <div class="ss-info">
      <div class="ss-grp">
        <div class="ss-row"><b>예식장</b> : ${esc(w.wedding_venue || '-')}</div>
      </div>
      <div class="ss-grp">
        <div class="ss-row"><b>신랑</b> : ${esc(w.groom_name || '-')}${w.groom_phone ? ' 📞 ' + esc(w.groom_phone) : ''}</div>
        <div class="ss-row"><b>신부</b> : ${esc(w.bride_name || '-')}${w.bride_phone ? ' 📞 ' + esc(w.bride_phone) : ''}</div>
      </div>
      ${o.length ? `<div class="ss-grp"><div class="ss-row"><b>옵션</b> : ${esc(o.join(', '))}</div></div>` : ''}
      ${(w.photographer === '2인 촬영' || w.rep_designation) ? `<div class="ss-grp"><div class="ss-row"><b>촬영</b> : ${esc([w.photographer === '2인 촬영' ? '2인 촬영' : '', w.rep_designation ? '대표지정' : ''].filter(Boolean).join(', '))}</div></div>` : ''}
    </div>
    <div class="ss-checks">
      <label class="ss-chk"><input type="checkbox" data-k="attend" ${c.attend ? 'checked' : ''} /> <span>참석 / 스케줄 확정 <em>*</em></span></label>
      <label class="ss-chk"><input type="checkbox" data-k="arrival" ${c.arrival ? 'checked' : ''} /> <span>도착 시간 숙지 (예식 1시간 30분 전) <em>*</em></span></label>
      <label class="ss-chk"><input type="checkbox" data-k="options" ${c.options ? 'checked' : ''} /> <span>옵션 · 요청사항 숙지 <em>*</em></span></label>
    </div>
    <div class="ss-foot">
      <span class="ss-status">${c.checked_at ? '최근 확인: ' + new Date(c.checked_at).toLocaleString('ko-KR') : ''}</span>
      <button class="ss-submit" type="button">${done ? '다시 확인' : '확인 완료'}</button>
    </div>
  </div>`;
}

async function init() {
  if (!sb) { show($('errCard')); return; }
  // 단축 코드면 먼저 풀어서 staffId/bookingId 채우기
  if (shortCode && !staffId) {
    const { data } = await sb.rpc('resolve_link', { p_code: shortCode });
    if (!data || !data.staff_id) { show($('errCard')); return; }
    staffId = data.staff_id;
    bookingId = data.booking_id;
  }
  if (!staffId || !uuidRe.test(staffId)) { show($('errCard')); return; }
  const single = bookingId && uuidRe.test(bookingId);
  const { data, error } = single
    ? await sb.rpc('staff_one', { p_booking_id: bookingId, p_staff_id: staffId })
    : await sb.rpc('staff_schedule', { p_staff_id: staffId });
  if (error || !data) { show($('errCard')); return; }
  $('greet').innerHTML = `<b>${esc(data.staff_name || '')}</b> 작가님, ${single ? '아래 예식을 확인해 주세요.' : '배정된 예식입니다.'}`;
  const list = Array.isArray(data.schedule) ? data.schedule : [];
  $('emptyMsg').hidden = list.length > 0;
  $('schedule').innerHTML = list.map(card).join('');
  bind();
  show($('mainCard'));
}

function bind() {
  document.querySelectorAll('.ss-card').forEach((el) => {
    el.querySelector('.ss-submit').addEventListener('click', async (e) => {
      const btn = e.currentTarget;
      const bid = el.dataset.bid;
      const get = (k) => el.querySelector(`input[data-k="${k}"]`).checked;
      if (!(get('attend') && get('arrival') && get('options'))) {
        alert('3가지 항목을 모두 체크해야 확인이 완료됩니다.');
        return;
      }
      btn.disabled = true;
      const { error } = await sb.rpc('submit_assignment_check', {
        payload: { booking_id: bid, staff_id: staffId, attend: true, arrival: true, options: true },
      });
      btn.disabled = false;
      if (error) { alert('저장 실패: 잠시 후 다시 시도해 주세요.'); return; }
      const done = true;
      el.classList.toggle('done', done);
      el.querySelector('.ss-status').textContent = '방금 확인됨';
      btn.textContent = done ? '다시 확인' : '확인 완료';
      const hf = el.querySelector('.ss-head');
      let flag = hf.querySelector('.ss-doneflag');
      if (done && !flag) { hf.insertAdjacentHTML('beforeend', '<span class="ss-doneflag">확인완료 ✓</span>'); }
      else if (!done && flag) { flag.remove(); }
    });
  });
}

init();
