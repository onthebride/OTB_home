/* 갤러리 썸네일 — 얼굴 찾기와 네모로 자를 자리 정하기 (대표 2026-10-27
   «이 갤러리 섬네일이 좀 자기 맘대로넹 얼굴 위주로 되게 안되나?» → 올릴 때 바로 «1번이 나을거 같은뎅»)

   홈 갤러리 썸네일은 사진 한가운데를 네모로 자른다. 세로로 긴 사진은 머리가 잘렸다.
   사진마다 자를 자리(gallery.focus_x·focus_y, %)를 DB 에 두고 홈이 object-position 으로 쓴다.

   이 파일 하나를 두 곳이 같이 쓴다 — 규칙이 둘로 갈리면 올린 사진과 옛 사진이 다르게 잘린다:
   · 관리자 갤러리 올리기 (브라우저) — OTBFace.focusForImage(사진) → { x, y } 또는 null(못 찾음)
   · 옛 사진 한꺼번에 채우기 (.backups/face/run.mjs, node) — focusOf 만 쓴다

   얼굴 찾기는 OpenCV 의 YuNet(face_detection_yunet_2023mar, MIT) — 옛 사진 897장을 같은 모델로 봤다.
   ⚠ 원래 모델 파일은 입력이 640×640 으로 박혀 있어 onnxruntime 이 다른 크기를 거절한다.
     속은 크기와 상관없이 돈다(Reshape -1 · Resize 2배) — 입력·출력 칸만 「아무 크기」로 바꾼 것을
     assets/face/ 에 둔다. OpenCV 처럼 사진을 그대로(32 의 배수로 오른쪽·아래만 0 채움) 넣는다.
   ⚠ onnxruntime-web 은 **올릴 때만** 받는다 (약 11MB, 한 번 받으면 브라우저가 기억한다).
     관리자 화면을 여는 것만으로는 안 받는다.
   ⚠ 무엇이든 실패하면 null — 사진 올리기는 막지 않는다. 그 사진은 예전처럼 가운데로 잘린다 */
(function (root) {
  'use strict';
  var ORT = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.19.2/dist/';
  var MODEL = '/assets/face/yunet-2023mar-dyn.onnx';
  var W = 900;          // 옛 사진도 폭 900 으로 줄여서 봤다 (홈 썸네일이 받는 가장 큰 폭)
  var SCORE = 0.6, NMS = 0.3, TOPK = 5000;   // OpenCV FaceDetectorYN 에 준 값과 같다

  /* ── 자를 자리 정하기 ──
     지금은 사진 한가운데를 네모로 자른다. **얼굴이 잘릴 때만** 옮긴다 — 나머지는 작가가 잡은 그대로
     (예식장별로 고르는 갤러리라 샹들리에·홀이 보이는 게 값이다)
     · 점수 0.8 아래는 얼굴로 안 친다 — 드레스 자락·뒷머리·흐린 베일을 얼굴로 잡은 것이 0.6~0.77 이었다
     · 얼굴이 넷 이상이면 하객 사진이다 — 옮기지 않는다
     · 가장 큰 얼굴 넓이의 1/4 보다 작은 얼굴은 뺀다 (뒤쪽 사람)
     · 머리 위(올림머리·면사포·티아라)까지 얼굴로 친다 — 위로 얼굴 높이의 0.6
     · 옮길 때는 얼굴 가운데가 네모 위에서 40% 자리에 오게 (가로 사진은 한가운데)
     · 안 옮기면 null
     v = { w, h, faces: [[x, y, 폭, 높이, 점수], …] } */
  function focusOf(v) {
    if (!v || !v.faces) return null;
    var good = v.faces.filter(function (f) { return f[4] >= 0.8; });
    if (!good.length || good.length >= 4) return null;
    var w = v.w, h = v.h, s = Math.min(w, h);
    var area = function (f) { return f[2] * f[3]; };
    var big = Math.max.apply(null, good.map(area));
    var main = good.filter(function (f) { return area(f) >= big / 4; });
    var boxOf = function (fs) {
      return [Math.min.apply(null, fs.map(function (f) { return f[0] - 0.25 * f[2]; })),
        Math.min.apply(null, fs.map(function (f) { return f[1] - 0.6 * f[3]; })),
        Math.max.apply(null, fs.map(function (f) { return f[0] + 1.25 * f[2]; })),
        Math.max.apply(null, fs.map(function (f) { return f[1] + 1.25 * f[3]; }))];
    };
    var b = boxOf(main);
    if (b[2] - b[0] > s || b[3] - b[1] > s) b = boxOf(main.filter(function (f) { return area(f) === big; }).slice(0, 1));
    var clamp = function (a, lo, hi) { return Math.max(lo, Math.min(hi, a)); };
    // 얼굴 가운데 (머리 위 여유 말고 얼굴 상자 그대로)
    var cx = (Math.min.apply(null, main.map(function (f) { return f[0]; })) + Math.max.apply(null, main.map(function (f) { return f[0] + f[2]; }))) / 2;
    var cy = (Math.min.apply(null, main.map(function (f) { return f[1]; })) + Math.max.apply(null, main.map(function (f) { return f[1] + f[3]; }))) / 2;
    var mid;
    if (h - s > 2) {
      mid = (h - s) / 2;
      if (b[1] >= mid && b[3] <= mid + s) return null;
      var top = clamp(cy - 0.4 * s, b[3] - s, b[1]);
      return { x: 50, y: Math.round(clamp(top, 0, h - s) / (h - s) * 100) };
    }
    if (w - s > 2) {
      mid = (w - s) / 2;
      if (b[0] >= mid && b[2] <= mid + s) return null;
      var left = clamp(cx - 0.5 * s, b[2] - s, b[0]);
      return { x: Math.round(clamp(left, 0, w - s) / (w - s) * 100), y: 50 };
    }
    return null;
  }

  /* ── YuNet 출력 풀기 (OpenCV face_detect.cpp postProcess 그대로) ──
     out[이름] = Float32Array. 칸마다 점수 = √(cls·obj), 상자 = (칸 + 어긋남)·보폭, 폭·높이 = e^값·보폭.
     겹치는 것은 점수 높은 것부터 남긴다 (IoU 0.3 넘으면 버림 — OpenCV NMSBoxes 처럼 정수 상자로 잰다) */
  function decode(out, padW, padH) {
    var cand = [];
    [8, 16, 32].forEach(function (st) {
      var cols = padW / st, rows = padH / st;
      var cls = out['cls_' + st], obj = out['obj_' + st], bb = out['bbox_' + st];
      for (var r = 0; r < rows; r++) for (var c = 0; c < cols; c++) {
        var i = r * cols + c;
        var sc = Math.sqrt(Math.min(Math.max(cls[i], 0), 1) * Math.min(Math.max(obj[i], 0), 1));
        if (sc < SCORE) continue;
        var cx = (c + bb[i * 4]) * st, cy = (r + bb[i * 4 + 1]) * st;
        var w = Math.exp(bb[i * 4 + 2]) * st, h = Math.exp(bb[i * 4 + 3]) * st;
        cand.push({ x: cx - w / 2, y: cy - h / 2, w: w, h: h, s: sc });
      }
    });
    cand.sort(function (a, b) { return b.s - a.s; });
    cand = cand.slice(0, TOPK);
    var ir = function (a) { return { x: Math.trunc(a.x), y: Math.trunc(a.y), w: Math.trunc(a.w), h: Math.trunc(a.h) }; };
    var iou = function (a, b) {
      var x0 = Math.max(a.x, b.x), y0 = Math.max(a.y, b.y);
      var x1 = Math.min(a.x + a.w, b.x + b.w), y1 = Math.min(a.y + a.h, b.y + b.h);
      var inter = Math.max(0, x1 - x0) * Math.max(0, y1 - y0);
      var uni = a.w * a.h + b.w * b.h - inter;
      return uni > 0 ? inter / uni : 0;
    };
    var keep = [];
    cand.forEach(function (c) {
      var ci = ir(c);
      if (keep.every(function (k) { return iou(ir(k), ci) <= NMS; })) keep.push(c);
    });
    return keep.map(function (k) {
      return [Math.trunc(k.x), Math.trunc(k.y), Math.trunc(k.w), Math.trunc(k.h), Math.round(k.s * 100) / 100];
    });
  }

  /* ── 브라우저: onnxruntime-web 을 올릴 때만 받아 온다 ── */
  var ortP = null, sessP = null;
  function loadOrt() {
    if (root.ort) return Promise.resolve(root.ort);
    if (!ortP) ortP = new Promise(function (ok, no) {
      var s = document.createElement('script');
      s.src = ORT + 'ort.wasm.min.js';
      s.onload = function () { root.ort ? ok(root.ort) : no(new Error('ort 없음')); };
      s.onerror = function () { ortP = null; no(new Error('ort 못 받음')); };
      document.head.appendChild(s);
    });
    return ortP;
  }
  function session() {
    if (!sessP) sessP = loadOrt().then(function (ort) {
      ort.env.wasm.wasmPaths = ORT;
      ort.env.wasm.numThreads = 1;   // 여러 갈래는 이 사이트에서 못 쓴다(교차 출처 격리 머리글이 없다)
      return ort.InferenceSession.create(MODEL, { executionProviders: ['wasm'] });
    }).catch(function (e) { sessP = null; throw e; });
    return sessP;
  }

  // 사진(img · ImageBitmap · canvas) → { w, h, faces } — 폭 900 으로 줄여서 본다
  function detect(img) {
    return session().then(function (sess) {
      var iw = img.naturalWidth || img.width, ih = img.naturalHeight || img.height;
      var k = Math.min(1, W / iw);
      var w = Math.round(iw * k), h = Math.round(ih * k);
      var padW = Math.ceil(w / 32) * 32, padH = Math.ceil(h / 32) * 32;
      var cv = document.createElement('canvas');
      cv.width = w; cv.height = h;
      var cx = cv.getContext('2d');
      cx.drawImage(img, 0, 0, w, h);
      var px = cx.getImageData(0, 0, w, h).data;
      // OpenCV blobFromImage 처럼 B·G·R 순서, 0~255 그대로, 오른쪽·아래는 0
      var plane = padW * padH, t = new Float32Array(3 * plane);
      for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) {
        var p = (y * w + x) * 4, q = y * padW + x;
        t[q] = px[p + 2]; t[plane + q] = px[p + 1]; t[2 * plane + q] = px[p];
      }
      var ort = root.ort;
      return sess.run({ input: new ort.Tensor('float32', t, [1, 3, padH, padW]) }).then(function (res) {
        var out = {};
        Object.keys(res).forEach(function (n) { out[n] = res[n].data; });
        return { w: w, h: h, faces: decode(out, padW, padH) };
      });
    });
  }

  // 올릴 사진 하나 → 자를 자리. 찾았으면 { x, y } (안 옮기면 50·50 = 「봤다」), 실패하면 null
  // ⚠ 오래 걸리면 기다리지 않는다 — 처음 한 번은 엔진을 받느라 느리다 (폰·느린 망)
  function focusForImage(img, ms) {
    var timer;
    var late = new Promise(function (ok) { timer = setTimeout(function () { ok('late'); }, ms || 30000); });
    var work = detect(img).then(function (v) { return focusOf(v) || { x: 50, y: 50 }; });
    return Promise.race([work, late]).then(function (r) {
      clearTimeout(timer);
      return r === 'late' ? null : r;
    }, function (e) {
      clearTimeout(timer);
      if (root.console) console.warn('얼굴 찾기 실패 — 가운데로 둔다', e && e.message);
      return null;
    });
  }

  var api = { focusOf: focusOf, decode: decode, detect: detect, focusForImage: focusForImage, MODEL: MODEL, ORT: ORT };
  root.OTBFace = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
