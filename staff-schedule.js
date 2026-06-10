/* ===== 작가 예식 전 스케줄 확인 ===== */
const sb = window.supabase && window.OTB_CONFIG
  ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
  : null;

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const staffId = params.get('s');
const bookingId = params.get('b');
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
      <div><b>예식장</b> ${esc(w.wedding_venue || '-')}</div>
      <div><b>신랑</b> ${esc(w.groom_name || '-')} ${esc(w.groom_phone || '')}</div>
      <div><b>신부</b> ${esc(w.bride_name || '-')} ${esc(w.bride_phone || '')}</div>
      ${o.length ? `<div><b>옵션</b> ${esc(o.join(', '))}</div>` : ''}
      ${w.photographer && w.photographer !== '기본' ? `<div><b>촬영</b> ${esc(w.photographer)}</div>` : ''}
    </div>
    <div class="ss-checks">
      <label class="ss-chk"><input type="checkbox" data-k="attend" ${c.attend ? 'checked' : ''} /> <span>참석 / 스케줄 확정</span></label>
      <label class="ss-chk"><input type="checkbox" data-k="arrival" ${c.arrival ? 'checked' : ''} /> <span>도착 시간 숙지 (예식 1시간 30분 전)</span></label>
      <label class="ss-chk"><input type="checkbox" data-k="options" ${c.options ? 'checked' : ''} /> <span>옵션 · 요청사항 숙지</span></label>
    </div>
    <textarea class="ss-note" placeholder="변경/문제 사항이 있으면 적어주세요 (선택)">${esc(c.note || '')}</textarea>
    <div class="ss-foot">
      <button class="ss-submit" type="button">${done ? '다시 확인' : '확인 완료'}</button>
      <span class="ss-status">${c.checked_at ? '최근 확인: ' + new Date(c.checked_at).toLocaleString('ko-KR') : ''}</span>
    </div>
  </div>`;
}

async function init() {
  if (!sb || !staffId || !uuidRe.test(staffId)) { show($('errCard')); return; }
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
      btn.disabled = true;
      const { error } = await sb.rpc('submit_assignment_check', {
        payload: { booking_id: bid, staff_id: staffId, attend: get('attend'), arrival: get('arrival'), options: get('options'), note: el.querySelector('.ss-note').value.trim() },
      });
      btn.disabled = false;
      if (error) { alert('저장 실패: 잠시 후 다시 시도해 주세요.'); return; }
      const done = get('attend') && get('arrival') && get('options');
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
