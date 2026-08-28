/* ===== 대표가 확인하러 들어온 것은 어느 통계에도 넣지 않는다 =====
 *  대표 지시 2026-08-28 «내가 들어가는게 카운트가 되네».
 *  작가 캘린더(staff-calendar.js 의 seenMark)에 먼저 넣은 것과 같은 방식이다.
 *
 *  가려내는 법 셋 — 하나라도 걸리면 GA·클래리티·자체집계를 **전부** 건너뛴다.
 *    ① 주소에 adm=1        관리자 화면에서 여는 링크에 붙는다. 그 방문 한 번만 뺀다
 *    ② supabase 세션 열쇠   지금 관리자로 로그인돼 있는 기기
 *    ③ otb_admin_device    한 번이라도 관리자로 로그인한 기기. admin.js 가 남긴다
 *                          (로그아웃한 채 홈을 확인해도 방문으로 세면 안 되므로 남긴다)
 *
 *  ⚠ 손님 쪽에서는 아무도 로그인하지 않는다 — signInWithPassword 는 admin.js 에만 있다.
 *     그래서 ②·③ 이 신부님을 잘못 빼는 일은 없다.
 *  ⚠ 신부·작가에게 나가는 링크에 adm=1 을 붙이면 안 된다 — 붙으면 아무도 안 세어진다.
 *     그래서 adm=1 은 그 방문만 빼고, ③ 의 영구 표시는 **남기지 않는다**.
 *  ⚠ 이 파일은 supabase-js 가 없는 페이지(rules·privacy·blog)에도 실린다.
 *     그래서 클라이언트 객체를 쓰지 않고 window.localStorage 만 직접 본다.
 */
window.OTB_ADMIN_DEVICE = (function () {
  try {
    if (new URLSearchParams(location.search || '').get('adm') === '1') return true;
    var ls = window.localStorage;
    if (!ls) return false;
    if (ls.getItem('otb_admin_device') === '1') return true;
    for (var i = 0; i < ls.length; i++) {
      var k = ls.key(i);
      if (k && k.indexOf('sb-') === 0 && k.indexOf('-auth-token') > 0) return true;
    }
  } catch (_) { /* 저장소를 못 읽으면 그냥 손님으로 본다 */ }
  return false;
})();

/* ===== 방문 통계 — 손님용 공개 페이지 전용 =====
 *  구글 애널리틱스(GA4) + 마이크로소프트 클래리티(히트맵·세션 리플레이)를 함께 로드한다.
 *
 *  ⚠️ 붙이는 페이지: index.html · rules.html · privacy.html · blog(생성기)
 *  ⚠️ 절대 붙이지 말 것: admin · portal · survey · survey-view · staff-schedule · c
 *     → 손님 이름·연락처가 화면에 떠 있어 세션 리플레이에 녹화되면 안 된다.
 *     (예약폼·문의폼은 data-clarity-mask="true" 로 입력값을 가려둔다 — index.html)
 *
 *  측정 ID 는 브라우저에 그대로 노출되는 공개값이라 소스에 둬도 안전하다(비밀키 아님).
 *  값이 비어 있으면 아무것도 로드되지 않는다.
 *
 *  ⚠️ 개인정보처리방침 제9조(privacy.html)에 이 도구들이 고지돼 있어야 한다.
 *     도구를 추가·교체·제거하면 방침도 반드시 같이 고칠 것.
 */
(function () {
  var GA_ID = 'G-6HF420BN0L';  // 구글 애널리틱스 측정 ID
  var CLARITY_ID = 'y3oqg71nzu';  // 마이크로소프트 클래리티 프로젝트 ID

  if (!GA_ID && !CLARITY_ID) return;

  // 대표 기기면 아예 불러오지도 않는다 — 세션 리플레이에 대표 화면이 남을 이유도 없다
  if (window.OTB_ADMIN_DEVICE) return;

  // 실서비스 도메인에서만 수집 — Vercel 미리보기·로컬 테스트가 통계에 섞이지 않게.
  // (도메인이 바뀌면 여기도 같이 고쳐야 수집이 이어진다)
  var host = location.hostname;
  if (host !== 'onthebride.com' && host !== 'www.onthebride.com') return;

  if (GA_ID) {
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { window.dataLayer.push(arguments); };
    window.gtag('js', new Date());
    window.gtag('config', GA_ID);
    var g = document.createElement('script');
    g.async = true;
    g.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(GA_ID);
    document.head.appendChild(g);
  }

  if (CLARITY_ID) {
    (function (c, l, a, r, i, t, y) {
      c[a] = c[a] || function () { (c[a].q = c[a].q || []).push(arguments); };
      t = l.createElement(r); t.async = 1; t.src = 'https://www.clarity.ms/tag/' + i;
      y = l.getElementsByTagName(r)[0]; y.parentNode.insertBefore(t, y);
    })(window, document, 'clarity', 'script', CLARITY_ID);
  }
})();

/* ===== 자체 방문 집계 (관리자 '통계' 탭용) =====
 *  구글·클래리티와 별개로, 관리자 화면에서 바로 보기 위해 우리 DB에도 최소한만 기록한다.
 *  저장 항목: 경로(쿼리스트링 제외) · 유입 도메인 · 모바일 여부 · 브라우저 세션 난수.
 *  IP·UserAgent 원문·쿠키는 저장하지 않는다. 실패해도 화면에 영향이 없도록 전부 무시한다.
 *  ※ 위 (function) 안의 도메인 검사와 동일한 조건에서만 돌도록 여기서도 다시 확인한다.
 */
(function () {
  var host = location.hostname;
  if (host !== 'onthebride.com' && host !== 'www.onthebride.com') return;
  // 관리자 화면 홈의 「오늘 방문·최근 7일·모바일 비율」이 대표 확인으로 부풀지 않게 (2026-08-28)
  if (window.OTB_ADMIN_DEVICE) return;
  var cfg = window.OTB_CONFIG;
  if (!cfg || !cfg.SUPABASE_URL || !cfg.SUPABASE_KEY) return;

  // 브라우저 세션 동안만 유지되는 난수 — 사람을 식별하지 못하며, 방문 수와 페이지뷰를 구분하는 용도
  var sid = '';
  try {
    sid = sessionStorage.getItem('otb_sid') || '';
    if (!sid) { sid = Math.random().toString(36).slice(2) + Date.now().toString(36); sessionStorage.setItem('otb_sid', sid); }
  } catch (_) {}

  // 유입은 도메인만 남긴다(전체 주소·검색어는 저장하지 않음). 사이트 내 이동은 유입으로 치지 않음
  var ref = null;
  try {
    if (document.referrer) {
      var rh = new URL(document.referrer).hostname;
      if (rh && rh !== host && rh !== 'onthebride.com' && rh !== 'www.onthebride.com') ref = rh;
    }
  } catch (_) {}

  function send(path) {
    try {
      fetch(cfg.SUPABASE_URL + '/rest/v1/rpc/log_pageview', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: cfg.SUPABASE_KEY, Authorization: 'Bearer ' + cfg.SUPABASE_KEY },
        body: JSON.stringify({
          p_path: path,
          p_ref: ref,
          p_mobile: window.innerWidth <= 860,
          p_sid: sid,
        }),
        keepalive: true,
      }).catch(function () {});
    } catch (_) {}
  }

  send(location.pathname);

  /* 홈은 한 페이지에 소개·갤러리·가격·이벤트·문의·예약이 모두 들어 있어
     경로만 보면 전부 '/' 로만 잡힌다. 그래서 화면에 실제로 머문 구역을 따로 기록한다.
     - 구역이 절반 이상 보이는 상태가 1.5초 이상 이어질 때만 (스크롤로 스쳐 지나간 건 제외)
     - 한 번 방문에 구역당 한 번만 */
  if (window.IntersectionObserver) {
    var seen = {}, timers = {};
    var secs = document.querySelectorAll('section[id]');
    if (secs.length) {
      var io = new window.IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          var id = e.target.id;
          if (!id || seen[id]) return;
          if (e.isIntersecting && e.intersectionRatio >= 0.5) {
            if (!timers[id]) timers[id] = setTimeout(function () {
              seen[id] = 1; timers[id] = null;
              send(location.pathname + '#' + id);
            }, 1500);
          } else if (timers[id]) {
            clearTimeout(timers[id]); timers[id] = null;
          }
        });
      }, { threshold: [0.5] });
      Array.prototype.forEach.call(secs, function (s) { io.observe(s); });
    }
    // 예약신청 시작 버튼 — 가장 중요한 반응이라 따로 센다
    var bs = document.getElementById('bookingStart');
    if (bs) bs.addEventListener('click', function () {
      if (seen['__bk']) return; seen['__bk'] = 1;
      send(location.pathname + '#booking-start');
    }, { once: false });
  }
})();
