/* ===== 예식 전 설문 ===== */
const sb =
  window.supabase && window.OTB_CONFIG
    ? window.supabase.createClient(window.OTB_CONFIG.SUPABASE_URL, window.OTB_CONFIG.SUPABASE_KEY)
    : null;

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const bookingId = params.get('b');

const loadCard = $('loadCard');
const errCard = $('errCard');
const doneCard = $('doneCard');
const form = $('surveyForm');

const show = (el) => {
  [loadCard, errCard, doneCard, form].forEach((x) => (x.hidden = x !== el));
};

const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/* ===== 레퍼런스 사진 (base64, 최대 5장) ===== */
const MAX_REFS = 5;
let refs = []; // [{ url: objectURL(미리보기), blob }]

function resizeToBlob(file, maxDim, quality) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      let w = img.width, h = img.height;
      if (w > maxDim || h > maxDim) {
        if (w >= h) { h = Math.round((h * maxDim) / w); w = maxDim; }
        else { w = Math.round((w * maxDim) / h); h = maxDim; }
      }
      const cv = document.createElement('canvas');
      cv.width = w; cv.height = h;
      cv.getContext('2d').drawImage(img, 0, 0, w, h);
      cv.toBlob((b) => (b ? resolve(b) : reject(new Error('이미지 변환 실패'))), 'image/jpeg', quality);
    };
    img.onerror = () => reject(new Error('이미지를 읽을 수 없습니다'));
    img.src = URL.createObjectURL(file);
  });
}

function renderRefs() {
  const grid = $('refPreview');
  grid.innerHTML = refs
    .map((r, i) => `<div class="sv-ref"><img src="${r.url}" alt="" /><button type="button" class="sv-ref-x" data-i="${i}" aria-label="삭제">×</button></div>`)
    .join('');
  grid.querySelectorAll('.sv-ref-x').forEach((b) =>
    b.addEventListener('click', () => {
      const i = Number(b.dataset.i);
      URL.revokeObjectURL(refs[i].url);
      refs.splice(i, 1);
      renderRefs();
    })
  );
  grid.querySelectorAll('.sv-ref img').forEach((im, i) =>
    im.addEventListener('click', () => openLb(refs[i].url))
  );
  $('refLabel').textContent = refs.length
    ? `${refs.length}/${MAX_REFS}장 · ${refs.length < MAX_REFS ? '더 추가 가능' : '최대'}`
    : '사진 선택 / 드래그앤드롭';
}

async function addRefFiles(files) {
  const imgs = Array.from(files).filter((f) => f.type.startsWith('image/'));
  for (const f of imgs) {
    if (refs.length >= MAX_REFS) { setStatus(`레퍼런스는 최대 ${MAX_REFS}장까지 올릴 수 있어요.`, 'error'); break; }
    try { const blob = await resizeToBlob(f, 1000, 0.7); refs.push({ url: URL.createObjectURL(blob), blob }); }
    catch (_) {}
  }
  renderRefs();
}

// 레퍼런스를 Storage에 업로드하고 공개 URL 배열 반환
async function uploadRefs() {
  const urls = [];
  for (let i = 0; i < refs.length; i++) {
    const path = `refs/${bookingId}/${Date.now()}-${i}-${Math.random().toString(36).slice(2, 7)}.jpg`;
    const up = await sb.storage.from('gallery').upload(path, refs[i].blob, { contentType: 'image/jpeg', upsert: false });
    if (up.error) throw up.error;
    urls.push(sb.storage.from('gallery').getPublicUrl(path).data.publicUrl);
  }
  return urls;
}

function openLb(src) {
  const lb = document.createElement('div');
  lb.className = 'sv-lb';
  lb.innerHTML = `<img src="${src}" alt="" />`;
  lb.addEventListener('click', () => lb.remove());
  document.body.appendChild(lb);
}

/* ===== status ===== */
function setStatus(msg, type) {
  const s = $('s_status');
  s.textContent = msg;
  s.className = 'sv-status' + (type ? ' ' + type : '');
}

/* ===== 값 수집 ===== */
const val = (id) => ($(id) ? $(id).value.trim() : '');
const ck = (id) => ($(id) ? $(id).checked : false);

function init() {
  if (!sb) { show(errCard); return; }
  if (!bookingId || !uuidRe.test(bookingId)) { show(errCard); return; }

  // 레퍼런스 입력 핸들러
  const refInput = $('s_refs');
  const drop = $('refDrop');
  refInput.addEventListener('change', (e) => { addRefFiles(e.target.files); e.target.value = ''; });
  ['dragenter', 'dragover'].forEach((ev) =>
    drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add('drag'); })
  );
  drop.addEventListener('dragleave', (e) => { if (!drop.contains(e.relatedTarget)) drop.classList.remove('drag'); });
  drop.addEventListener('drop', (e) => {
    e.preventDefault(); drop.classList.remove('drag');
    if (e.dataTransfer.files.length) addRefFiles(e.dataTransfer.files);
  });

  $('reopenBtn').addEventListener('click', () => { show(form); setStatus(''); });

  loadBooking();
}

async function loadBooking() {
  const { data, error } = await sb.rpc('survey_booking_info', { p_booking_id: bookingId });
  if (error || !data) { show(errCard); return; }

  // prefill
  if (data.contractor_name) {
    $('s_name').value = data.contractor_name;
    $('greet').innerHTML = `<b>${escapeHtml(data.contractor_name)}</b>님, 예식 전 설문을 작성해 주세요.`;
  }
  if (data.wedding_date) $('s_date').value = String(data.wedding_date).slice(0, 10);
  if (data.wedding_venue) $('s_venue').value = data.wedding_venue;
  if (data.contractor_email) $('s_email').value = data.contractor_email;
  if (data.already) $('reNote').hidden = false;

  show(form);
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

/* ===== 제출 ===== */
form.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!ck('s_agree')) {
    setStatus('촬영 안내사항 확인에 체크해 주세요.', 'error');
    const c = document.querySelector('.sv-confirm');
    c.classList.remove('flash'); void c.offsetWidth; c.classList.add('flash');
    c.scrollIntoView({ behavior: 'smooth', block: 'center' });
    return;
  }
  if (!val('s_name')) { setStatus('성함을 입력해 주세요.', 'error'); return; }

  const prog = Array.from(document.querySelectorAll('input[name="prog"]:checked')).map((x) => x.value);
  const priority = (document.querySelector('input[name="priority"]:checked') || {}).value || '';
  const light = ck('s_wonpan_nolight') ? '미사용' : '사용';

  const btn = $('s_submit');
  btn.disabled = true;

  let refUrls = [];
  try {
    if (refs.length) setStatus('사진 업로드 중입니다…', '');
    refUrls = await uploadRefs();
  } catch (err) {
    console.error(err);
    btn.disabled = false;
    setStatus('사진 업로드 중 오류가 발생했어요. 잠시 후 다시 시도해 주세요.', 'error');
    return;
  }

  const payload = {
    booking_id: bookingId,
    agree_check: ck('s_agree'),
    name: val('s_name'),
    wedding_date: val('s_date') || null,
    wedding_venue: val('s_venue'),
    email: val('s_email'),
    priority,
    prop_ring: ck('s_prop_ring'),
    bride_room_req: val('s_bride_room'),
    prog_items: prog,
    bridal_focus: val('s_focus'),
    wonpan_first: ck('s_wonpan_first'),
    wonpan_light: light,
    extra_req: val('s_extra'),
    etc_req: val('s_etc'),
    refs: refUrls,
  };

  setStatus('제출 중입니다…', '');
  const { error } = await sb.rpc('submit_survey', { payload });
  btn.disabled = false;
  if (error) {
    console.error(error);
    setStatus('제출 중 오류가 발생했어요. 잠시 후 다시 시도해 주세요.', 'error');
    return;
  }
  show(doneCard);
  window.scrollTo({ top: 0, behavior: 'smooth' });
});

init();
