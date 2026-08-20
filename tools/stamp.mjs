/* 자산 주소에 내용 도장을 찍는다.
 *
 * 왜 필요한가
 *   지금까지 모든 js·css 를 '매번 서버에 물어보기(no-cache)' 로 내보내고 있었다.
 *   주소에 ?v= 가 붙어 있는데도 그랬다. 손으로 적은 버전이라 믿을 수 없었기 때문이다 —
 *   실제로 styles.css 는 페이지마다 20260720a / 20260810a / 20260821a 세 가지로 달랐고,
 *   survey.css·portal.js 같은 건 아예 버전이 없었다.
 *
 *   이 도구는 파일 내용을 그대로 해시해서 ?v= 를 찍는다. 내용이 바뀌면 주소가 바뀌고,
 *   안 바뀌면 주소도 그대로다. 그래서 브라우저에 '1년간 다시 묻지 마라' 고 말해도 안전하다.
 *
 * 쓰는 법
 *   node tools/stamp.mjs          찍는다 (배포 전에 실행)
 *   node tools/stamp.mjs --check  안 맞는 게 있으면 알려주고 실패로 끝낸다
 *
 * 건드리지 않는 것
 *   config.js — 설정이라 언제든 손으로 고칠 수 있어야 한다. 그대로 매번 물어본다.
 *   sw.js     — 서비스워커. 낡은 것이 남으면 곤란하므로 매번 물어본다.
 */
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, '$1'), '..');
const SKIP = ['config.js', 'sw.js'];
const check = process.argv.includes('--check');

const htmlFiles = () => {
  const out = fs.readdirSync(ROOT).filter((f) => f.endsWith('.html')).map((f) => path.join(ROOT, f));
  const blog = path.join(ROOT, 'blog');
  if (fs.existsSync(blog)) {
    for (const f of fs.readdirSync(blog)) if (f.endsWith('.html')) out.push(path.join(blog, f));
    const posts = path.join(blog, 'posts');
    if (fs.existsSync(posts)) for (const f of fs.readdirSync(posts)) if (f.endsWith('.html')) out.push(path.join(posts, f));
  }
  return out;
};

const hashes = {};
export function stampOf(file) {
  if (hashes[file] !== undefined) return hashes[file];
  const p = path.join(ROOT, file);
  hashes[file] = fs.existsSync(p)
    ? crypto.createHash('sha1').update(fs.readFileSync(p)).digest('hex').slice(0, 10)
    : null;
  return hashes[file];
}

// src="main.js?v=…" / href="/styles.css" 같은 것을 찾아 ?v= 를 내용 도장으로 바꾼다.
// 바깥 주소(//cdn…)는 건드리지 않는다.
const RE = /\b(src|href)="(\/?)([A-Za-z0-9._-]+\.(?:js|css))(\?[^"]*)?"/g;

export function restamp(html) {
  const missing = [];
  const out = html.replace(RE, (m, attr, slash, file, q) => {
    if (SKIP.includes(file)) return `${attr}="${slash}${file}"`;   // 설정·서비스워커는 버전 없이
    const h = stampOf(file);
    if (!h) { missing.push(file); return m; }
    return `${attr}="${slash}${file}?v=${h}"`;
  });
  return { out, missing };
}

let changed = 0, bad = 0, missingAll = new Set();
for (const f of htmlFiles()) {
  const before = fs.readFileSync(f, 'utf8');
  const { out, missing } = restamp(before);
  missing.forEach((x) => missingAll.add(x));
  if (out !== before) {
    changed++;
    if (check) { bad++; console.log('  안 맞음: ' + path.relative(ROOT, f)); }
    else fs.writeFileSync(f, out);
  }
}

if (missingAll.size) console.log('  파일이 없어 건너뜀: ' + [...missingAll].join(', '));
if (check) {
  if (bad) { console.log(`도장이 ${bad}개 파일에서 안 맞습니다. node tools/stamp.mjs 를 돌리세요.`); process.exit(1); }
  console.log('도장 전부 맞습니다.');
} else {
  console.log(changed ? `도장 다시 찍음: HTML ${changed}개` : '이미 다 맞습니다.');
}
