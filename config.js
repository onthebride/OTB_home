// Supabase 공개 설정 (publishable 키는 프론트 노출용 — 안전)
window.OTB_CONFIG = {
  SUPABASE_URL: 'https://cthpxcgesorvtgjdgrtu.supabase.co',
  SUPABASE_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN0aHB4Y2dlc29ydnRnamRncnR1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM5ODc3MDYsImV4cCI6MjA5OTU2MzcwNn0.nZmNgmpqoc2pe6swnER-SiH_1_PFibsXVuFCql1mQGA',
  WEB3FORMS_KEY: '37d02bd9-c51d-48a0-8386-02e22d43c22e',
};

/* ===== 화면을 덮는 창을 띄우는 동안 뒤가 안 움직이게 =====
   대표 2026-09-04 «갤러리 사진 보려고 누르면 일단 뒷배경이 움직여»
   대표 2026-09-06 «작가 설문에서 레퍼런스 사진 볼때 뒷배경 스크롤 안되게해줘»

   ⚠ 같은 사진 확대창이 **네 군데**에 복사돼 있다 — 홈 갤러리, 작가가 보는 설문,
     관리자 예약 상세, 손님이 쓰는 설문. 한 곳만 고치면 나머지에서 또 걸린다.
     그래서 셈을 여기 한 곳에 둔다. config.js 는 모든 화면이 함께 읽고,
     vercel.json 에서 no-cache 라 고치면 바로 퍼진다 (도장 안 찍어도 된다).

   ⚠ `body { overflow: hidden }` 만으로는 **폰에서 안 잠긴다.**
     아이폰 사파리는 그대로 밀리고, 어떤 브라우저는 맨 위로 튀어 오른다.
     자리를 적어두고 body 를 통째로 고정한 뒤, 닫을 때 그 자리로 돌려놓는다.
   ⚠ `html { scroll-behavior: smooth }` 가 걸린 화면이 있어 그냥 되돌리면
     스르륵 움직이는 게 보인다. 되돌리는 동안만 끈다.
   ⚠ 창이 겹칠 수 있으니 몇 겹인지 센다 — 하나 닫았다고 풀리면 뒤엣것이 움직인다.
   ⚠ 손가락 동작(touch-action)은 막지 않는다. 막으면 두 손가락으로 사진을
     키워 보는 것까지 막힌다. */
window.otbScrollLockN = 0;
window.otbScrollLockY = 0;
window.otbLockScroll = function otbLockScroll() {
  if (window.otbScrollLockN++ > 0) return;
  window.otbScrollLockY = window.scrollY || document.documentElement.scrollTop || 0;
  var b = document.body.style;
  b.position = 'fixed';
  b.top = -window.otbScrollLockY + 'px';
  b.left = '0';
  b.right = '0';
  b.width = '100%';
  // 폰에서 아래로 당기면 브라우저가 새로고침을 한다 — 사진 보다가 화면이 날아간다
  document.documentElement.classList.add('no-pull');
};
window.otbUnlockScroll = function otbUnlockScroll() {
  if (window.otbScrollLockN === 0 || --window.otbScrollLockN > 0) return;
  document.documentElement.classList.remove('no-pull');
  var b = document.body.style;
  b.position = ''; b.top = ''; b.left = ''; b.right = ''; b.width = '';
  var h = document.documentElement.style;
  var had = h.scrollBehavior;
  h.scrollBehavior = 'auto';          // 되돌리는 것은 «움직임» 이 아니라 «제자리»
  window.scrollTo(0, window.otbScrollLockY);
  h.scrollBehavior = had;
};
