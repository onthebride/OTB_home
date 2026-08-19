/* ===== 작가 개인 캘린더 =====
   링크: /staff-calendar?s=<작가ID>
   · 배정된 예식이 날짜에 표시된다(예식일·시간·장소·신랑신부·옵션. 연락처는 예식 2주 전부터)
   · 촬영이 안 되는 날은 날짜를 눌러 '불가'로 표시
   · 다른 촬영이 있는 날은 시간·장소를 적어두면, 우리 예식과 4시간 이상 벌어질 때만 배정된다 */
const sb = window.supabase && window.OTB_CONFIG
  ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
  : null;

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const staffId = params.get('s');
const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const esc = (s) => (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const show = (el) => ['errCard', 'loadCard', 'mainCard'].forEach((id) => ($(id).hidden = $(id) !== el));

const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const dayKey = (v) => String(v).slice(0, 10);
const kTime = (t) => {
  if (!t) return '';
  const [h, m] = String(t).split(':').map(Number);
  return (h < 12 ? '오전 ' : '오후 ') + (h % 12 === 0 ? 12 : h % 12) + ':' + pad(m);
};
const todayStr = ymd(new Date());

let view = new Date();               // 보고 있는 달
let data = { bookings: [], busy: [] };
let openDay = null;

function opts(w) {
  const o = [];
  if (w.option_reception) o.push('연회장 인사촬영');
  if (w.option_pyebaek) o.push('폐백촬영');
  if (w.option_part2) o.push('2부 촬영');
  if (w.photographer === '2인 촬영') o.push('2인 촬영');
  return o;
}

async function load() {
  if (!sb || !staffId || !uuidRe.test(staffId)) { show($('errCard')); return; }
  const first = new Date(view.getFullYear(), view.getMonth(), 1);
  const last = new Date(view.getFullYear(), view.getMonth() + 1, 0);
  const { data: res, error } = await sb.rpc('staff_calendar', {
    p_staff_id: staffId, p_from: ymd(first), p_to: ymd(last),
  });
  if (error || !res) { show($('errCard')); return; }
  data = { bookings: res.bookings || [], busy: res.busy || [] };
  $('greet').innerHTML = `<b>${esc(res.staff_name || '')}</b> 작가님의 캘린더입니다.`;
  render();
  show($('mainCard'));
}

function render() {
  $('monthLabel').textContent = `${view.getFullYear()}년 ${view.getMonth() + 1}월`;
  const first = new Date(view.getFullYear(), view.getMonth(), 1);
  const days = new Date(view.getFullYear(), view.getMonth() + 1, 0).getDate();

  const byDay = {};
  data.bookings.forEach((b) => { (byDay[dayKey(b.wedding_date)] ||= { bk: [], busy: [] }).bk.push(b); });
  data.busy.forEach((x) => { (byDay[dayKey(x.the_date)] ||= { bk: [], busy: [] }).busy.push(x); });

  let html = '';
  for (let i = 0; i < first.getDay(); i++) html += '<div class="sc-cell empty"></div>';
  for (let d = 1; d <= days; d++) {
    const key = `${view.getFullYear()}-${pad(view.getMonth() + 1)}-${pad(d)}`;
    const it = byDay[key] || { bk: [], busy: [] };
    const off = it.busy.some((x) => x.kind === 'off');
    const past = key < todayStr;
    const cls = ['sc-cell'];
    if (past) cls.push('past');
    if (off) cls.push('off');
    if (key === todayStr) cls.push('today');
    if (key === openDay) cls.push('sel');
    html += `<button type="button" class="${cls.join(' ')}" data-d="${key}"${past ? ' disabled' : ''}>
      <span class="sc-d">${d}</span>
      ${it.bk.map((b) => `<span class="sc-tag bk">${esc(kTime(b.wedding_time) || '예식')}</span>`).join('')}
      ${it.busy.filter((x) => x.kind === 'busy').map((x) => `<span class="sc-tag busy">${esc(kTime(x.at_time))}</span>`).join('')}
      ${off ? '<span class="sc-tag off">불가</span>' : ''}
    </button>`;
  }
  $('grid').innerHTML = html;
  $('grid').querySelectorAll('.sc-cell[data-d]').forEach((el) =>
    el.addEventListener('click', () => { openDay = el.dataset.d; render(); renderPanel(); }));
  if (openDay) renderPanel();
}

function renderPanel() {
  const p = $('dayPanel');
  if (!openDay) { p.hidden = true; return; }
  const bk = data.bookings.filter((b) => dayKey(b.wedding_date) === openDay);
  const busy = data.busy.filter((x) => dayKey(x.the_date) === openDay);
  const off = busy.find((x) => x.kind === 'off');
  const [y, m, d] = openDay.split('-').map(Number);

  const bkHtml = bk.map((b) => {
    const o = opts(b);
    return `<div class="sc-item bk">
      <div class="sc-item-h"><b>${esc(kTime(b.wedding_time) || '시간 미정')}</b> · ${esc(b.wedding_venue || '-')}
        <span class="sc-role ${b.role === '서브' ? 'sub' : 'main'}">${esc(b.role)}</span></div>
      <div class="sc-item-b">신랑 ${esc(b.groom_name || '-')}${b.groom_phone ? ' 📞 ' + esc(b.groom_phone) : ''}
        · 신부 ${esc(b.bride_name || '-')}${b.bride_phone ? ' 📞 ' + esc(b.bride_phone) : ''}</div>
      ${o.length ? `<div class="ss-opts">${o.map((x) => `<span class="ss-opt${x === '2인 촬영' ? ' two' : ''}">${esc(x)}</span>`).join('')}</div>` : ''}
      ${b.rep_designation ? '<div class="sc-item-b">촬영 : 대표지정</div>' : ''}
    </div>`;
  }).join('');

  const busyHtml = busy.filter((x) => x.kind === 'busy').map((x) => `
    <div class="sc-item busy">
      <div class="sc-item-h"><b>${esc(kTime(x.at_time))}</b> ${esc(x.place || '')}<span class="sc-mine">내가 등록</span></div>
      <button type="button" class="btn-sm sc-del" data-id="${x.id}">지우기</button>
    </div>`).join('');

  p.hidden = false;
  p.innerHTML = `
    <div class="sc-panel">
      <h3>${y}년 ${m}월 ${d}일</h3>
      ${bkHtml || ''}
      ${busyHtml || ''}
      ${off ? `<div class="sc-item off"><div class="sc-item-h"><b>이 날은 촬영 불가</b><span class="sc-mine">내가 등록</span></div>
                 <button type="button" class="btn-sm sc-del" data-id="${off.id}">해제</button></div>` : ''}
      ${bk.length ? '<p class="sc-hint">배정된 예식이 있는 날입니다. 불가로 바꾸시려면 먼저 대표에게 알려주세요.</p>' : ''}
      <div class="sc-add">
        ${off ? '' : `<button type="button" class="btn-sm sc-off">이 날 촬영 불가</button>`}
        <div class="sc-busy-form">
          <input type="time" id="bTime" />
          <input type="text" id="bPlace" placeholder="장소 (예: 타사 촬영)" />
          <button type="button" class="btn-sm sc-addbusy">다른 일정 추가</button>
        </div>
      </div>
      <p class="sc-status" id="scStatus"></p>
    </div>`;

  p.querySelectorAll('.sc-del').forEach((btn) => btn.addEventListener('click', () => del(btn.dataset.id)));
  const offBtn = p.querySelector('.sc-off');
  if (offBtn) offBtn.addEventListener('click', () => add('off'));
  const addBtn = p.querySelector('.sc-addbusy');
  if (addBtn) addBtn.addEventListener('click', () => add('busy'));
}

async function add(kind) {
  const st = $('scStatus');
  const body = { p_staff_id: staffId, p_date: openDay, p_kind: kind };
  if (kind === 'busy') {
    const time = $('bTime').value;
    if (!time) { st.textContent = '시간을 입력해 주세요.'; return; }
    body.p_time = time;
    body.p_place = $('bPlace').value.trim();
  } else if (data.bookings.some((b) => dayKey(b.wedding_date) === openDay)) {
    if (!confirm('이 날은 이미 배정된 예식이 있습니다. 그래도 촬영 불가로 표시할까요?\n(대표에게 따로 알려주세요)')) return;
  }
  st.textContent = '저장 중…';
  const { error } = await sb.rpc('staff_busy_add', body);
  if (error) { st.textContent = '저장 실패: ' + error.message; return; }
  st.textContent = '';
  await load();
  renderPanel();
}

async function del(id) {
  const { error } = await sb.rpc('staff_busy_del', { p_staff_id: staffId, p_id: Number(id) });
  if (error) { alert('삭제 실패: ' + error.message); return; }
  await load();
  renderPanel();
}

$('prevM').addEventListener('click', () => { view = new Date(view.getFullYear(), view.getMonth() - 1, 1); openDay = null; $('dayPanel').hidden = true; load(); });
$('nextM').addEventListener('click', () => { view = new Date(view.getFullYear(), view.getMonth() + 1, 1); openDay = null; $('dayPanel').hidden = true; load(); });

load();
