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
  return h + ':' + pad(m);
};
const todayStr = ymd(new Date());

let view = new Date();               // 보고 있는 달
let data = { bookings: [], busy: [] };
let openDay = null;
// 지금 열어둔 입력칸의 종류 — 'busy'(다른 촬영) | 'personal'(개인 일정) | null(안 열림)
let formKind = null;
let editId = null;                   // 수정 중인 일정 (없으면 새로 등록)

const KIND_NAME = { busy: '다른 촬영', personal: '개인 일정' };

// 여러 날짜리 개인 일정이면 "8/25~8/28 (4일)" 처럼 보여준다
const mdy = (s) => { const [, m, d] = String(s).slice(0, 10).split('-'); return Number(m) + '/' + Number(d); };
const spanText = (x) => (x.group_id && x.g_n > 1 ? mdy(x.g_from) + '~' + mdy(x.g_to) + ' (' + x.g_n + '일)' : '');

// 달력 한 칸에 들어갈 짧은 이름. 좁으니 제목이 있으면 제목만.
const cellTag = (x) => (x.title ? x.title
  : (x.kind === 'personal' ? '개인' : (x.all_day ? '종일' : kTime(x.at_time))));
let slideDir = '';                   // 달을 넘긴 방향(넘어온 티가 나게 살짝 밀어 넣는다)
let multi = false;                   // 여러 날 고르는 중
let picked = new Set();              // 고른 날짜들 (yyyy-mm-dd)

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
  $('greet').innerHTML = `<b>${esc(res.staff_name || '')}</b> 작가님의 캘린더`;
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
    // 개인일정도 그날 촬영은 못 하는 것으로 본다(대표 방침) — 칸도 같이 막힌 것처럼 보인다
    const blocked = off || it.busy.some((x) => x.kind === 'personal');
    const past = key < todayStr;
    // 고르는 중에는 '이미 불가'거나 '배정된 예식이 있는' 날은 고를 수 없다(서버도 거부한다)
    const lockedForPick = multi && (blocked || it.bk.length > 0);
    const cls = ['sc-cell'];
    if (past) cls.push('past');
    if (blocked) cls.push('off');
    if (key === todayStr) cls.push('today');
    if (!multi && key === openDay) cls.push('sel');
    if (multi && picked.has(key)) cls.push('picked');
    if (lockedForPick) cls.push('nopick');
    html += `<button type="button" class="${cls.join(' ')}" data-d="${key}"${past || lockedForPick ? ' disabled' : ''}>
      <span class="sc-d">${d}</span>
      ${it.bk.map((b) => `<span class="sc-tag bk">${esc(kTime(b.wedding_time) || '예식')}</span>`).join('')}
      ${it.busy.filter((x) => x.kind === 'busy').map((x) => `<span class="sc-tag busy">${esc(cellTag(x))}</span>`).join('')}
      ${it.busy.filter((x) => x.kind === 'personal').map((x) => `<span class="sc-tag pers">${esc(cellTag(x))}</span>`).join('')}
      ${off ? '<span class="sc-tag off">불가</span>' : ''}
    </button>`;
  }
  const g = $('grid');
  g.innerHTML = html;
  if (slideDir) {
    g.classList.remove('sc-in-l', 'sc-in-r');
    void g.offsetWidth;                        // 같은 애니메이션을 다시 태우려면 한 번 끊어줘야 한다
    g.classList.add(slideDir === 'next' ? 'sc-in-r' : 'sc-in-l');
    slideDir = '';
  }
  g.querySelectorAll('.sc-cell[data-d]').forEach((el) =>
    el.addEventListener('click', () => {
      const d = el.dataset.d;
      if (multi) {
        if (picked.has(d)) picked.delete(d); else picked.add(d);
        render();
        return;
      }
      openDay = d; formKind = null; editId = null; render(); renderPanel();
    }));
  renderPickBar();
  if (!multi && openDay) renderPanel();
}

// 여러 날 고르기 — 켜고 끄는 버튼과, 고른 개수·저장 막대
function renderPickBar() {
  const bar = $('pickBar');
  if (!bar) return;
  if (!multi) { bar.hidden = true; bar.innerHTML = ''; return; }
  bar.hidden = false;
  const n = picked.size;
  bar.innerHTML = `
    <p class="pk-hint">촬영이 안 되는 날을 눌러서 고르세요. 배정된 예식이 있는 날은 고를 수 없습니다.</p>
    <div class="pk-row">
      <span class="pk-n">${n ? n + '일 선택' : '고른 날 없음'}</span>
      <button type="button" class="btn-sm primary pk-save"${n ? '' : ' disabled'}>촬영 불가로 저장</button>
      <button type="button" class="btn-sm pk-cancel">취소</button>
    </div>
    <p class="sc-status" id="pkStatus"></p>`;
  const save = bar.querySelector('.pk-save');
  if (save) save.addEventListener('click', savePicked);
  const cancel = bar.querySelector('.pk-cancel');
  if (cancel) cancel.addEventListener('click', () => { multi = false; picked.clear(); render(); });
}

async function savePicked() {
  const st = $('pkStatus');
  const dates = [...picked].sort();
  if (!dates.length) return;
  if (st) st.textContent = '저장 중…';
  const { data, error } = await sb.rpc('staff_busy_add_many', { p_staff_id: staffId, p_dates: dates });
  if (error) { if (st) st.textContent = error.message || '저장하지 못했습니다.'; return; }
  const skipped = (data && data.skipped) || [];
  multi = false; picked.clear();
  await load();
  if (skipped.length) {
    const days = skipped.map((x) => String(x.d).slice(5).replace('-', '/')).join(', ');
    alert(`${(data && data.ok) || 0}일 등록했습니다.\n\n${skipped.length}일은 등록하지 못했습니다 (${days})\n배정된 예식이 있거나 지난 날짜입니다.`);
  }
}

function renderPanel() {
  const p = $('dayPanel');
  if (multi || !openDay) { p.hidden = true; return; }
  const bk = data.bookings.filter((b) => dayKey(b.wedding_date) === openDay);
  const busy = data.busy.filter((x) => dayKey(x.the_date) === openDay);
  const off = busy.find((x) => x.kind === 'off');
  const [y, m, d] = openDay.split('-').map(Number);

  const bkHtml = bk.map((b) => {
    const o = opts(b);
    return `<div class="sc-item bk">
      <div class="sc-item-h"><b>${esc(kTime(b.wedding_time) || '시간 미정')}</b> · ${esc(b.wedding_venue || '-')}
        <span class="sc-role ${b.role === '서브' ? 'sub' : 'main'}">${esc(b.role)}</span></div>
      <div class="sc-item-b">
        <span class="sc-who">신랑 ${esc(b.groom_name || '-')}${b.groom_phone ? ' 📞 ' + esc(b.groom_phone) : ''}</span>
        <span class="sc-who">신부 ${esc(b.bride_name || '-')}${b.bride_phone ? ' 📞 ' + esc(b.bride_phone) : ''}</span>
      </div>
      ${o.length ? `<div class="ss-opts">${o.map((x) => `<span class="ss-opt${x === '2인 촬영' ? ' two' : ''}">${esc(x)}</span>`).join('')}</div>` : ''}
      ${b.rep_designation ? '<div class="sc-item-b">촬영 : 대표지정</div>' : ''}
    </div>`;
  }).join('');

  const evHtml = busy.filter((x) => x.kind === 'busy' || x.kind === 'personal').map((x) => `
    <div class="sc-item ${x.kind === 'personal' ? 'pers' : 'busy'}">
      <div class="sc-item-h">
        <b>${esc(x.all_day ? '종일' : (kTime(x.at_time) || '시간 미정'))}</b>
        ${x.title ? '<span class="sc-title">' + esc(x.title) + '</span>' : ''}
        ${x.place ? '<span class="sc-place">' + esc(x.place) + '</span>' : ''}
        ${spanText(x) ? '<span class="sc-span">' + esc(spanText(x)) + '</span>' : ''}
        <span class="sc-kind ${x.kind}">${KIND_NAME[x.kind]}</span>
      </div>
      ${x.note ? '<div class="sc-item-b sc-memo">' + esc(x.note) + '</div>' : ''}
      <div class="sc-item-btns">
        <button type="button" class="btn-sm sc-edit" data-id="${x.id}">수정</button>
        <button type="button" class="btn-sm sc-del" data-id="${x.id}"
          data-group="${x.group_id && x.g_n > 1 ? x.group_id : ''}">${x.group_id && x.g_n > 1 ? '전부 지우기' : '지우기'}</button>
      </div>
    </div>`).join('');
  const editing = editId ? busy.find((x) => String(x.id) === String(editId)) : null;

  p.hidden = false;
  p.innerHTML = `
    <div class="sc-panel">
      <h3>${y}년 ${m}월 ${d}일</h3>
      ${bkHtml || ''}
      ${evHtml || ''}
      ${off ? `<div class="sc-item off"><div class="sc-item-h"><b>이 날은 촬영 불가</b><span class="sc-mine">내가 등록</span></div>
                 <button type="button" class="btn-sm sc-del" data-id="${off.id}">해제</button></div>` : ''}
      ${bk.length ? '<p class="sc-hint">배정된 예식이 있는 날입니다.<br />촬영이 어려우시면 <b>대표에게 연락</b>해 주세요.</p>' : ''}
      <div class="sc-add">
        <div class="sc-add-btns">
          ${off || bk.length ? '' : '<button type="button" class="btn-sm sc-off">촬영불가</button>'}
          ${off || formKind ? '' : '<button type="button" class="btn-sm sc-openbusy">다른촬영등록</button>'}
          ${off || formKind || bk.length ? '' : '<button type="button" class="btn-sm sc-openpers">개인일정등록</button>'}
          ${off && !bk.length ? '<button type="button" class="btn-sm primary sc-multi">다른 날짜 같이 선택하기</button>' : ''}
        </div>
        ${formKind ? `<div class="sc-busy-form">
          <button type="button" class="sc-close" aria-label="닫기" title="닫기">×</button>
          <p class="sc-form-t">${KIND_NAME[formKind]} ${editing ? '수정' : '등록'}</p>
          <label class="sc-f"><span>할 일</span><input type="text" id="bTitle"
            placeholder="${formKind === 'personal' ? '예: 병원 / 가족모임 / 휴가' : '예: OO웨딩홀 본식'}"
            value="${editing ? esc(editing.title || '') : ''}" /></label>
          ${formKind === 'personal' && !editing
            ? '<label class="sc-f"><span>언제까지</span>'
              + '<input type="date" id="bUntil" value="' + openDay + '" min="' + openDay + '" /></label>'
              + '<p class="sc-hint-row">하루면 그대로 두세요</p>'
            : ''}
          <label class="sc-f sc-check"><span>종일</span><input type="checkbox" id="bAllDay"${editing && editing.all_day ? ' checked' : ''} /></label>
          <label class="sc-f" id="bTimeRow"><span>시간</span>
            <span class="sc-time">
              <select id="bH">${['<option value="">시</option>']
                .concat(Array.from({ length: 24 }, (_, i) =>
                  `<option value="${pad(i)}"${editing && String(editing.at_time || '').slice(0, 2) === pad(i) ? ' selected' : ''}>${pad(i)}</option>`)).join('')}</select>
              <b>:</b>
              <select id="bM">${Array.from({ length: 12 }, (_, i) =>
                `<option value="${pad(i * 5)}"${editing && String(editing.at_time || '').slice(3, 5) === pad(i * 5) ? ' selected' : ''}>${pad(i * 5)}</option>`).join('')}</select>
            </span>
          </label>
          <label class="sc-f"><span>장소</span><input type="text" id="bPlace" placeholder="예: 아펠가모 광화문"
            value="${editing ? esc(editing.place || '') : ''}" /></label>
          <label class="sc-f"><span>메모</span><textarea id="bNote" rows="2" placeholder="여러 줄로 적으셔도 됩니다">${editing ? esc(editing.note || '') : ''}</textarea></label>
          <div class="sc-form-btns">
            <button type="button" class="btn-sm primary sc-addbusy">${editing ? '수정' : '저장'}</button>
            <button type="button" class="btn-sm sc-cancelbusy">취소</button>
          </div>
          <p class="sc-note">${formKind === 'personal'
            ? '대표님께는 <b>«개인 일정»</b> 이라고만 보입니다. 무슨 일인지·몇 시인지는 안 보입니다.<br />그날은 <b>촬영 불가</b>로 처리됩니다.'
            : '대표님께는 <b>시간과 장소</b>만 보입니다. 메모는 안 보입니다.<br />우리 예식과 <b>4시간 이상</b> 벌어지면 그날도 배정될 수 있습니다.'}</p>
        </div>` : ''}
      </div>
      <p class="sc-status" id="scStatus"></p>
    </div>`;

  p.querySelectorAll('.sc-del').forEach((btn) =>
    btn.addEventListener('click', () => del(btn.dataset.id, btn.dataset.group)));
  const offBtn = p.querySelector('.sc-off');
  if (offBtn) offBtn.addEventListener('click', () => add('off'));
  const multiBtn = p.querySelector('.sc-multi');
  // 이 버튼은 이미 불가로 찍은 날에만 나온다 → 그 날은 담을 필요가 없으니 빈 상태로 시작
  if (multiBtn) multiBtn.addEventListener('click', () => {
    multi = true;
    picked.clear();
    render();
  });
  const openBusy = p.querySelector('.sc-openbusy');
  if (openBusy) openBusy.addEventListener('click', () => { formKind = 'busy'; editId = null; renderPanel(); });
  const openPers = p.querySelector('.sc-openpers');
  if (openPers) openPers.addEventListener('click', () => { formKind = 'personal'; editId = null; renderPanel(); });
  const shut = () => { formKind = null; editId = null; renderPanel(); };
  const cancelBusy = p.querySelector('.sc-cancelbusy');
  if (cancelBusy) cancelBusy.addEventListener('click', shut);
  const closeBtn = p.querySelector('.sc-close');
  if (closeBtn) closeBtn.addEventListener('click', shut);
  const addBtn = p.querySelector('.sc-addbusy');
  if (addBtn) addBtn.addEventListener('click', () => add(formKind));
  p.querySelectorAll('.sc-edit').forEach((btn) => btn.addEventListener('click', () => {
    const it = busy.find((x) => String(x.id) === String(btn.dataset.id));
    editId = btn.dataset.id; formKind = (it && it.kind) || 'busy'; renderPanel();
  }));
  // 메모는 줄이 늘면 칸이 같이 늘어난다 — 스크롤이 생기면 적어둔 게 안 보인다
  const note = p.querySelector('#bNote');
  if (note) {
    const grow = () => { note.style.height = 'auto'; note.style.height = (note.scrollHeight + 2) + 'px'; };
    note.addEventListener('input', grow);
    grow();
  }
  // 종일이면 시간 고를 일이 없다
  const allDay = p.querySelector('#bAllDay');
  const timeRow = p.querySelector('#bTimeRow');
  if (allDay && timeRow) {
    const sync = () => { timeRow.hidden = allDay.checked; };
    allDay.addEventListener('change', sync);
    sync();
  }
}

async function add(kind) {
  const st = $('scStatus');
  const body = { p_staff_id: staffId, p_date: openDay, p_kind: kind };
  if (kind === 'busy' || kind === 'personal') {
    const allDay = !!($('bAllDay') && $('bAllDay').checked);
    const h = $('bH') ? $('bH').value : '';
    const m = $('bM') ? $('bM').value : '00';
    // 다른 촬영은 시간을 알아야 겹치는지 볼 수 있다. 개인일정은 어차피 그날을 막으니 없어도 된다.
    if (kind === 'busy' && !allDay && !h) {
      st.textContent = '시간을 골라 주세요. (하루 종일이면 [종일] 을 켜주세요)'; return;
    }
    body.p_time = (allDay || !h) ? null : h + ':' + m;
    body.p_place = $('bPlace') ? $('bPlace').value.trim() : '';
    body.p_note = $('bNote') ? $('bNote').value.trim() : '';
    body.p_title = $('bTitle') ? $('bTitle').value.trim() : '';
    body.p_all_day = allDay || (kind === 'personal' && !h);
  }
  st.textContent = '저장 중…';
  const cur = editId ? (data.busy || []).find((x) => String(x.id) === String(editId)) : null;
  const until = $('bUntil') ? $('bUntil').value : '';
  let res;
  if (editId && cur && cur.group_id && cur.g_n > 1) {
    // 여러 날짜리는 묶음 통째로 고친다
    res = await sb.rpc('staff_busy_upd_group', {
      p_staff_id: staffId, p_group: cur.group_id,
      p_title: body.p_title, p_note: body.p_note,
      p_time: body.p_time, p_place: body.p_place, p_all_day: body.p_all_day });
  } else if (editId) {
    res = await sb.rpc('staff_busy_upd', {
      p_staff_id: staffId, p_id: Number(editId),
      p_time: body.p_time, p_place: body.p_place, p_note: body.p_note,
      p_title: body.p_title, p_all_day: body.p_all_day });
  } else if (kind === 'personal' && until && until > openDay) {
    res = await sb.rpc('staff_busy_add_range', {
      p_staff_id: staffId, p_from: openDay, p_to: until,
      p_title: body.p_title, p_note: body.p_note,
      p_time: body.p_time, p_place: body.p_place, p_all_day: body.p_all_day });
  } else {
    res = await sb.rpc('staff_busy_add', body);
  }
  if (res.error) { st.textContent = res.error.message || '저장하지 못했습니다.'; return; }
  const skipped = (res.data && res.data.skipped) || [];
  if (skipped.length) {
    alert(((res.data && res.data.n) || 0) + '일 등록했습니다.\n\n'
      + skipped.length + '일은 등록하지 못했습니다 ('
      + skipped.map((x) => String(x.d).slice(5).replace('-', '/')).join(', ') + ')\n'
      + '배정된 예식이 있거나 지난 날짜입니다.');
  }
  st.textContent = '';
  formKind = null;
  editId = null;
  await load();
  renderPanel();
}

async function del(id, group) {
  // 여러 날짜리면 통째로 지운다 — 하루씩 지우게 하면 번거롭다
  if (group) {
    if (!confirm('이 일정이 걸린 날을 전부 지울까요?')) return;
    const { error } = await sb.rpc('staff_busy_del_group', { p_staff_id: staffId, p_group: group });
    if (error) { alert('삭제 실패: ' + error.message); return; }
  } else {
    const { error } = await sb.rpc('staff_busy_del', { p_staff_id: staffId, p_id: Number(id) });
    if (error) { alert('삭제 실패: ' + error.message); return; }
  }
  await load();
  renderPanel();
}

// ── 홈 화면에 추가 ──
(function a2hs() {
  const btn = $('a2hs'), modal = $('a2hsModal');
  if (!btn || !modal) return;
  const ua = navigator.userAgent || '';
  const inApp = /KAKAOTALK|NAVER|Instagram|FBAN|FBAV|Line\//i.test(ua);
  const iOS = /iPhone|iPad|iPod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const android = /Android/i.test(ua);
  const installed = (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || navigator.standalone === true;
  if (installed) { btn.hidden = true; return; }   // 이미 홈 화면에서 연 경우

  const steps = inApp
    ? `<p class="a2-warn">지금은 <b>카카오톡 안</b>에서 보고 계십니다. 여기서는 홈 화면에 추가할 수 없어요.</p>
       <ol><li>화면 오른쪽 <b>⋮ (또는 ···) 메뉴</b></li>
           <li><b>다른 브라우저로 열기</b> ${iOS ? '(Safari)' : '(Chrome)'}</li>
           <li>브라우저에서 이 버튼을 다시 눌러주세요</li></ol>`
    : iOS
    ? `<ol><li>화면 아래 <b>공유 버튼</b> <span class="a2-ic">⬆︎</span></li>
           <li>목록에서 <b>홈 화면에 추가</b></li>
           <li>오른쪽 위 <b>추가</b></li></ol>`
    : android
    ? `<ol><li>화면 오른쪽 위 <b>⋮ 메뉴</b></li>
           <li><b>홈 화면에 추가</b> (또는 앱 설치)</li>
           <li><b>추가</b></li></ol>`
    : `<ol><li>브라우저 메뉴를 엽니다</li>
           <li><b>바로가기 만들기</b> 또는 <b>홈 화면에 추가</b></li></ol>
       <p class="a2-warn">휴대폰에서 열면 더 간단합니다.</p>`;

  $('a2hsSteps').innerHTML = steps + '<p class="a2-note">추가해두시면 카톡을 찾지 않아도 바로 열 수 있습니다.</p>';
  const open = () => { modal.hidden = false; };
  const close = () => { modal.hidden = true; };
  btn.addEventListener('click', open);
  $('a2hsClose').addEventListener('click', close);
  modal.addEventListener('click', (e) => { if (e.target === modal) close(); });
})();

function goMonth(step) {
  view = new Date(view.getFullYear(), view.getMonth() + step, 1);
  openDay = null;
  formKind = null;
  editId = null;
  picked.clear();               // 달마다 따로 고른다 — 넘기면 비운다
  $('dayPanel').hidden = true;
  slideDir = step > 0 ? 'next' : 'prev';
  load();
}
$('prevM').addEventListener('click', () => goMonth(-1));
$('nextM').addEventListener('click', () => goMonth(1));

// ── 좌우로 밀어 달 넘기기(폰) ──
// 세로로 스크롤하려는 손짓과 헷갈리면 안 된다. 처음 움직인 방향으로 가로/세로를 정하고,
// 가로로 정해졌을 때만 넘긴다. 날짜 상세 칸은 대상에서 빼서 글자 선택을 방해하지 않는다.
(function swipeMonth() {
  const el = $('calWrap');
  if (!el) return;
  const MIN = 45;                    // 이만큼은 밀어야 넘어간다
  let x0 = null, y0 = null, axis = null;
  el.addEventListener('touchstart', (e) => {
    if (e.touches.length !== 1) { x0 = null; return; }
    x0 = e.touches[0].clientX; y0 = e.touches[0].clientY; axis = null;
  }, { passive: true });
  el.addEventListener('touchmove', (e) => {
    if (x0 === null || e.touches.length !== 1) return;
    const dx = e.touches[0].clientX - x0;
    const dy = e.touches[0].clientY - y0;
    if (axis === null && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
      axis = Math.abs(dx) > Math.abs(dy) ? 'x' : 'y';
    }
  }, { passive: true });
  el.addEventListener('touchend', (e) => {
    if (x0 === null || axis !== 'x') { x0 = null; return; }
    const dx = (e.changedTouches[0] || {}).clientX - x0;
    x0 = null;
    if (Math.abs(dx) < MIN) return;
    goMonth(dx < 0 ? 1 : -1);        // 왼쪽으로 밀면 다음 달
  }, { passive: true });
  el.addEventListener('touchcancel', () => { x0 = null; }, { passive: true });
})();

load();

// 사용안내는 처음엔 펼쳐 둔다. 한 번 접으면 그 기기에서는 계속 접혀 있다.
(function helpFold() {
  const el = $('scHelp');
  if (!el) return;
  const KEY = 'otb_sc_help';
  try { if (localStorage.getItem(KEY) === 'shut') el.open = false; } catch (e) { /* 저장이 막힌 기기 */ }
  el.addEventListener('toggle', () => {
    try { localStorage.setItem(KEY, el.open ? 'open' : 'shut'); } catch (e) { /* 무시 */ }
  });
})();
