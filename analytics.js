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
