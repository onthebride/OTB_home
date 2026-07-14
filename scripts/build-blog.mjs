// ============================================================
//  온더브라이드 블로그 정적 생성기 (무의존 · Node 18+)
//
//  blog/content/*.md (프론트매터 + 마크다운) → 진짜 HTML 페이지로 변환.
//  AI SEO를 위해 본문이 HTML에 그대로 박히고, JSON-LD 구조화데이터
//  (BlogPosting · BreadcrumbList · FAQPage), 시맨틱 마크업, 답변-우선
//  요약 박스, sitemap.xml, robots.txt(AI 크롤러 허용)를 함께 생성한다.
//
//  실행:  node scripts/build-blog.mjs
//  설치 필요 없음(외부 패키지 0개).
// ============================================================
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');

// ---- 사이트 설정 ------------------------------------------------
// ⚠️ 실제 도메인으로 바꾸세요. canonical·OG·sitemap 절대주소에 쓰입니다.
const SITE = {
  origin: 'https://onthebride.co.kr',           // ← 실제 도메인 확정 후 수정
  brand: '온더브라이드',
  brandEn: 'ONTHEBRIDE',
  blogName: '온더브라이드 블로그',
  tagline: '본식스냅 정보와 웨딩 준비 가이드',
  logo: '/assets/logo-black.png',
  ogDefault: '/assets/logo-black.png',
  locale: 'ko_KR',
  instagram: 'https://www.instagram.com/onthebride/',
  email: 'onthebride@naver.com',
};

const CONTENT_DIR = path.join(ROOT, 'blog', 'content');
const POSTS_OUT = path.join(ROOT, 'blog', 'posts');
const BLOG_INDEX = path.join(ROOT, 'blog', 'index.html');

// ---- 유틸 -------------------------------------------------------
const esc = (s = '') => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const attr = (s = '') => esc(s).replace(/"/g, '&quot;');
const stripMd = (s = '') => String(s)
  .replace(/`([^`]+)`/g, '$1')
  .replace(/\*\*([^*]+)\*\*/g, '$1')
  .replace(/\*([^*]+)\*/g, '$1')
  .replace(/_([^_]+)_/g, '$1')
  .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
  .trim();
const abs = (p) => (p && p.startsWith('http')) ? p : SITE.origin + (p && p.startsWith('/') ? p : '/' + (p || ''));
// <script> 안 JSON-LD 안전 삽입
const ld = (obj) => JSON.stringify(obj, null, 2).replace(/</g, '\\u003c');

function fmtDateK(iso) {
  if (!iso) return '';
  const d = new Date(iso + (iso.length <= 10 ? 'T00:00:00' : ''));
  if (isNaN(d)) return iso;
  const wd = ['일', '월', '화', '수', '목', '금', '토'][d.getDay()];
  return `${d.getFullYear()}년 ${d.getMonth() + 1}월 ${d.getDate()}일 (${wd})`;
}
function readingTime(mdBody) {
  const chars = stripMd(mdBody).replace(/\s+/g, '').length;
  return Math.max(1, Math.round(chars / 500)); // 한국어 대략 분당 500자
}

// ---- 프론트매터 파서 (간단 key: value, faq는 본문에서 추출) --------
function parseFront(raw) {
  const m = raw.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (!m) return { meta: {}, body: raw };
  const meta = {};
  for (const line of m[1].split('\n')) {
    const mm = line.match(/^([a-zA-Z_]+):\s*(.*)$/);
    if (!mm) continue;
    const key = mm[1];
    let val = mm[2].trim();
    if (key === 'tags') meta.tags = val ? val.split(',').map((t) => t.trim()).filter(Boolean) : [];
    else meta[key] = val;
  }
  return { meta, body: m[2] };
}

// ---- 인라인 마크다운 -------------------------------------------
function inline(t) {
  t = esc(t);
  t = t.replace(/`([^`]+)`/g, (_, c) => `<code>${c}</code>`);
  t = t.replace(/!\[([^\]]*)\]\(([^)\s]+)\)/g, (_, a, s) => `<img src="${attr(s)}" alt="${attr(a)}" loading="lazy" />`);
  t = t.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, x, u) => {
    const ext = /^https?:\/\//.test(u) && !u.includes('onthebride');
    return `<a href="${attr(u)}"${ext ? ' target="_blank" rel="noopener"' : ''}>${x}</a>`;
  });
  t = t.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  t = t.replace(/(^|[^*])\*([^*]+)\*(?!\*)/g, '$1<em>$2</em>');
  return t;
}

// ---- 블록 마크다운 → HTML (+ FAQ 추출) --------------------------
const FAQ_TITLES = ['자주 묻는 질문', '자주하는 질문', 'faq', 'q&a', '자주 하는 질문'];
function mdToHtml(md) {
  const lines = md.replace(/\r\n/g, '\n').split('\n');
  const blocks = [];
  let i = 0;
  const special = /^(#{1,4}\s|>\s?|\d+\.\s|[-*]\s|(?:---|\*\*\*|___)\s*$)/;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) { i++; continue; }
    let m;
    if ((m = line.match(/^(#{1,4})\s+(.*)$/))) { blocks.push({ type: 'h', level: m[1].length, text: m[2].trim() }); i++; continue; }
    if (/^(?:---|\*\*\*|___)\s*$/.test(line)) { blocks.push({ type: 'hr' }); i++; continue; }
    if (/^>\s?/.test(line)) {
      const buf = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) { buf.push(lines[i].replace(/^>\s?/, '')); i++; }
      blocks.push({ type: 'quote', text: buf.join(' ') }); continue;
    }
    if (/^\d+\.\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\d+\.\s+/.test(lines[i])) { items.push(lines[i].replace(/^\d+\.\s+/, '')); i++; }
      blocks.push({ type: 'ol', items }); continue;
    }
    if (/^[-*]\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^[-*]\s+/.test(lines[i])) { items.push(lines[i].replace(/^[-*]\s+/, '')); i++; }
      blocks.push({ type: 'ul', items }); continue;
    }
    if (/^!\[[^\]]*\]\([^)]+\)\s*$/.test(line)) { blocks.push({ type: 'img', text: line.trim() }); i++; continue; }
    const buf = [line]; i++;
    while (i < lines.length && lines[i].trim() && !special.test(lines[i])) { buf.push(lines[i]); i++; }
    blocks.push({ type: 'p', text: buf.join(' '), lines: buf.slice() });
  }

  const faq = [];
  let inFaq = false, curQ = null;
  const out = [];
  for (const b of blocks) {
    if (b.type === 'h') {
      const norm = b.text.toLowerCase().replace(/\s+/g, ' ').trim();
      if (b.level === 2) inFaq = FAQ_TITLES.some((t) => norm === t || norm.includes(t));
      if (inFaq && b.level === 3) { curQ = { q: stripMd(b.text), a: '' }; faq.push(curQ); }
      out.push(`<h${b.level} id="${slugifyHeading(b.text)}">${inline(b.text)}</h${b.level}>`);
    } else if (b.type === 'p') {
      if (inFaq && curQ && !curQ.a) curQ.a = stripMd(b.text);
      // 문단 내 줄바꿈은 <br>로 보존(에세이 형식)
      out.push('<p>' + (b.lines || [b.text]).map((l) => inline(l)).join('<br>\n') + '</p>');
    } else if (b.type === 'ul') {
      out.push(`<ul>${b.items.map((x) => `<li>${inline(x)}</li>`).join('')}</ul>`);
    } else if (b.type === 'ol') {
      out.push(`<ol>${b.items.map((x) => `<li>${inline(x)}</li>`).join('')}</ol>`);
    } else if (b.type === 'quote') {
      out.push(`<blockquote>${inline(b.text)}</blockquote>`);
    } else if (b.type === 'img') {
      out.push(`<figure>${inline(b.text)}</figure>`);
    } else if (b.type === 'hr') {
      out.push('<hr />');
    }
  }
  return { html: out.join('\n'), faq };
}
function slugifyHeading(t) {
  return stripMd(t).toLowerCase().replace(/[^\w가-힣]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40);
}

// ---- 공통 헤더/푸터 --------------------------------------------
function siteHeader(active) {
  const link = (href, label, key) => `<li><a href="${href}"${active === key ? ' aria-current="page"' : ''}>${label}</a></li>`;
  return `<header class="blog-header">
    <div class="blog-header-inner">
      <a href="/" class="blog-brand"><img src="${SITE.logo}" alt="${attr(SITE.brand)}" /></a>
      <nav aria-label="주요 메뉴"><ul>
        ${link('/#about', '소개', 'about')}
        ${link('/#gallery', '갤러리', 'gallery')}
        ${link('/#pricing', '가격', 'pricing')}
        ${link('/blog', '블로그', 'blog')}
        ${link('/#booking', '예약하기', 'booking')}
      </ul></nav>
    </div>
  </header>`;
}
function siteFooter() {
  return `<footer class="blog-footer">
    <div class="blog-footer-inner">
      <p class="bf-brand">${esc(SITE.brand)} · ${esc(SITE.brandEn)}</p>
      <p class="bf-links">
        <a href="/">홈</a> · <a href="/blog">블로그</a> · <a href="/#pricing">가격</a> ·
        <a href="/#booking">예약</a> · <a href="${SITE.instagram}" target="_blank" rel="noopener">인스타그램</a>
      </p>
      <p class="bf-copy">© 2013 ${esc(SITE.brandEn)}. All rights reserved.</p>
    </div>
  </footer>`;
}
function headCommon({ title, description, canonical, image, type = 'website', published, modified }) {
  const img = abs(image || SITE.ogDefault);
  return `  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${esc(title)}</title>
  <meta name="description" content="${attr(description)}" />
  <link rel="canonical" href="${attr(canonical)}" />
  <meta name="robots" content="index, follow, max-image-preview:large" />
  <link rel="icon" type="image/png" href="/assets/favicon.png" />
  <meta property="og:type" content="${type}" />
  <meta property="og:site_name" content="${attr(SITE.blogName)}" />
  <meta property="og:locale" content="${SITE.locale}" />
  <meta property="og:title" content="${attr(title)}" />
  <meta property="og:description" content="${attr(description)}" />
  <meta property="og:url" content="${attr(canonical)}" />
  <meta property="og:image" content="${attr(img)}" />${published ? `\n  <meta property="article:published_time" content="${attr(published)}" />` : ''}${modified ? `\n  <meta property="article:modified_time" content="${attr(modified)}" />` : ''}
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${attr(title)}" />
  <meta name="twitter:description" content="${attr(description)}" />
  <meta name="twitter:image" content="${attr(img)}" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@500;600&family=Noto+Serif+KR:wght@400;500;600;700&family=Noto+Sans+KR:wght@300;400;500;700&display=swap" rel="stylesheet" />
  <link rel="stylesheet" href="/blog.css?v=1" />`;
}

// ---- 포스트 페이지 ---------------------------------------------
function renderPost(post, allPosts) {
  const canonical = `${SITE.origin}/blog/posts/${post.slug}`;
  const { html, faq } = post.rendered;
  const related = allPosts.filter((p) => p.slug !== post.slug).slice(0, 3);

  const jsonldPost = {
    '@context': 'https://schema.org',
    '@type': 'BlogPosting',
    headline: post.title,
    description: post.description,
    datePublished: post.date,
    dateModified: post.updated || post.date,
    author: { '@type': 'Organization', name: SITE.brand, url: SITE.origin },
    publisher: { '@type': 'Organization', name: SITE.brand, logo: { '@type': 'ImageObject', url: abs(SITE.logo) } },
    mainEntityOfPage: { '@type': 'WebPage', '@id': canonical },
    image: abs(post.cover || SITE.ogDefault),
    inLanguage: 'ko-KR',
    ...(post.tags && post.tags.length ? { keywords: post.tags.join(', ') } : {}),
  };
  const jsonldCrumb = {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: [
      { '@type': 'ListItem', position: 1, name: '홈', item: SITE.origin + '/' },
      { '@type': 'ListItem', position: 2, name: '블로그', item: SITE.origin + '/blog' },
      { '@type': 'ListItem', position: 3, name: post.title, item: canonical },
    ],
  };
  const jsonldFaq = faq.length ? {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: faq.map((f) => ({ '@type': 'Question', name: f.q, acceptedAnswer: { '@type': 'Answer', text: f.a } })),
  } : null;

  const tagsHtml = (post.tags || []).map((t) => `<span class="post-tag">#${esc(t)}</span>`).join('');
  const summaryBox = post.summary
    ? `<aside class="post-tldr"><p class="tldr-label">한눈에</p><p>${inline(post.summary)}</p></aside>`
    : '';
  const coverHtml = post.cover
    ? `<figure class="post-cover"><img src="${attr(post.cover)}" alt="${attr(post.title)}" /></figure>` : '';
  const relatedHtml = related.length ? `
    <section class="post-related">
      <h2>함께 보면 좋은 글</h2>
      <ul>${related.map((p) => `<li><a href="/blog/posts/${p.slug}">${esc(p.title)}</a></li>`).join('')}</ul>
    </section>` : '';
  // 하단 사진 그리드 + 갤러리(해당 예식장으로 검색된 채) 보러가기
  const galleryLink = post.venue ? `/?g=${encodeURIComponent(post.venue)}#gallery` : '/#gallery';
  const photosHtml = (post.grid && post.grid.length) ? `
      <section class="post-photos">
        <h2>${esc(post.venue || '')} 사진</h2>
        <div class="photo-grid">
          ${post.grid.map((u) => `<a class="pg-item" href="${attr(galleryLink)}"><img src="${attr(u)}" alt="${attr((post.venue ? post.venue + ' ' : '') + '본식스냅')}" loading="lazy" /></a>`).join('')}
        </div>
        <a class="photos-more" href="${attr(galleryLink)}">${esc(post.venue || '')} 사진 더 보기 →</a>
      </section>` : '';

  return `<!DOCTYPE html>
<html lang="ko">
<head>
${headCommon({ title: `${post.title} | ${SITE.blogName}`, description: post.description, canonical, image: post.cover, type: 'article', published: post.date, modified: post.updated || post.date })}
  <script type="application/ld+json">${ld(jsonldPost)}</script>
  <script type="application/ld+json">${ld(jsonldCrumb)}</script>${jsonldFaq ? `\n  <script type="application/ld+json">${ld(jsonldFaq)}</script>` : ''}
</head>
<body class="blog">
${siteHeader('blog')}
  <main class="post-wrap">
    <nav class="breadcrumb" aria-label="현재 위치">
      <a href="/">홈</a> <span>›</span> <a href="/blog">블로그</a> <span>›</span> <span aria-current="page">${esc(post.title)}</span>
    </nav>
    <article class="post">
      <header class="post-head">
        ${tagsHtml ? `<p class="post-tags">${tagsHtml}</p>` : ''}
        <h1>${esc(post.title)}</h1>
        <p class="post-meta">
          <time datetime="${attr(post.date)}">${fmtDateK(post.date)}</time>
          <span>·</span><span>${post.readingTime}분 읽기</span>
          ${post.updated && post.updated !== post.date ? `<span>·</span><span>${fmtDateK(post.updated)} 업데이트</span>` : ''}
        </p>
      </header>
      ${coverHtml}
      ${summaryBox}
      <div class="post-body">
${html}
      </div>
      ${photosHtml}
      <aside class="post-cta">
        <p class="cta-lead">본식스냅, 온더브라이드와 함께하세요</p>
        <p class="cta-sub">거품 뺀 합리적인 견적, 검증된 작가의 본식스냅.</p>
        <a class="cta-btn" href="/#booking">예약 문의하기</a>
      </aside>
    </article>
    ${relatedHtml}
  </main>
${siteFooter()}
</body>
</html>`;
}

// ---- 블로그 목록 -----------------------------------------------
function renderIndex(posts) {
  const canonical = `${SITE.origin}/blog`;
  const jsonld = {
    '@context': 'https://schema.org',
    '@type': 'Blog',
    name: SITE.blogName,
    description: SITE.tagline,
    url: canonical,
    publisher: { '@type': 'Organization', name: SITE.brand, logo: { '@type': 'ImageObject', url: abs(SITE.logo) } },
    blogPost: posts.map((p) => ({
      '@type': 'BlogPosting', headline: p.title, url: `${SITE.origin}/blog/posts/${p.slug}`,
      datePublished: p.date, dateModified: p.updated || p.date, description: p.description,
    })),
  };
  const cards = posts.map((p) => `
      <li class="blog-card no-cover">
        <a href="/blog/posts/${p.slug}">
          <span class="bc-body">
            ${(p.tags && p.tags[0]) ? `<span class="bc-tag">#${esc(p.tags[0])}</span>` : ''}
            <span class="bc-title">${esc(p.title)}</span>
            <span class="bc-desc">${esc(p.description)}</span>
            <span class="bc-date"><time datetime="${attr(p.date)}">${fmtDateK(p.date)}</time> · ${p.readingTime}분</span>
          </span>
        </a>
      </li>`).join('');

  return `<!DOCTYPE html>
<html lang="ko">
<head>
${headCommon({ title: `${SITE.blogName} — ${SITE.tagline}`, description: `${SITE.tagline}. 본식스냅 준비에 도움이 되는 정보를 온더브라이드가 정리했습니다.`, canonical })}
  <script type="application/ld+json">${ld(jsonld)}</script>
</head>
<body class="blog">
${siteHeader('blog')}
  <main class="blog-list-wrap">
    <header class="blog-hero">
      <p class="overline">${esc(SITE.brandEn)} JOURNAL</p>
      <h1>${esc(SITE.blogName)}</h1>
      <p class="blog-hero-sub">${esc(SITE.tagline)} — 본식스냅 준비에 실제로 도움이 되는 이야기를 담습니다.</p>
    </header>
    ${posts.length ? `<ul class="blog-cards">${cards}</ul>` : '<p class="blog-empty">첫 글을 준비 중이에요.</p>'}
  </main>
${siteFooter()}
</body>
</html>`;
}

// ---- llms.txt (AI에게 사이트 안내) -----------------------------
// https://llmstxt.org 제안 표준. 핵심 페이지 지도를 사람/LLM이 읽기 쉽게 정리.
function renderLlms(posts) {
  const postLines = posts.length
    ? posts.map((p) => `- [${p.title}](${SITE.origin}/blog/posts/${p.slug}): ${p.description}`).join('\n')
    : '- (준비 중)';
  return `# ${SITE.brand} (${SITE.brandEn})

> 거품을 뺀 합리적인 견적과 검증된 작가의 웨딩 본식스냅 스튜디오. 결혼식 당일(본식) 현장을 자연스럽게 기록합니다.

${SITE.brand}는 결혼식 본식 사진을 촬영하는 본식스냅 스튜디오입니다. 합리적인 가격과 정직한 운영을 지향하며, ${SITE.blogName}에서 본식스냅 준비에 도움이 되는 정보를 제공합니다.

## 주요 페이지
- [홈](${SITE.origin}/): 스튜디오 소개·갤러리·가격·이벤트·예약 안내
- [${SITE.blogName}](${SITE.origin}/blog): ${SITE.tagline}
- [예약 문의](${SITE.origin}/#booking): 본식스냅 예약·상담

## 블로그 글
${postLines}

## 문의
- 이메일: ${SITE.email}
- 인스타그램: ${SITE.instagram}
`;
}

// ---- 실행 -------------------------------------------------------
function build() {
  if (!fs.existsSync(CONTENT_DIR)) { console.error('content 폴더 없음:', CONTENT_DIR); process.exit(1); }
  fs.mkdirSync(POSTS_OUT, { recursive: true });

  const files = fs.readdirSync(CONTENT_DIR).filter((f) => f.endsWith('.md'));
  const posts = [];
  for (const f of files) {
    const raw = fs.readFileSync(path.join(CONTENT_DIR, f), 'utf8');
    const { meta, body } = parseFront(raw);
    const slug = meta.slug || f.replace(/\.md$/, '');
    if (meta.draft === 'true') { console.log('  (draft 건너뜀)', slug); continue; }
    const rendered = mdToHtml(body);
    posts.push({
      slug,
      title: meta.title || slug,
      description: meta.description || stripMd(body).slice(0, 120),
      summary: meta.summary || '',
      date: meta.date || '',
      updated: meta.updated || meta.date || '',
      cover: meta.cover || '',
      thumb: meta.thumb || '',
      venue: meta.venue || '',
      grid: (meta.grid || '').split(',').map((s) => s.trim()).filter(Boolean),
      tags: meta.tags || [],
      readingTime: readingTime(body),
      rendered,
    });
  }
  posts.sort((a, b) => (b.date || '').localeCompare(a.date || ''));

  for (const p of posts) {
    fs.writeFileSync(path.join(POSTS_OUT, `${p.slug}.html`), renderPost(p, posts));
    console.log('  ✓ post', p.slug);
  }
  fs.writeFileSync(BLOG_INDEX, renderIndex(posts));
  console.log('  ✓ blog/index.html');

  // sitemap.xml
  const urls = [
    { loc: SITE.origin + '/', pri: '1.0' },
    { loc: SITE.origin + '/blog', pri: '0.8', lastmod: posts[0] && (posts[0].updated || posts[0].date) },
    ...posts.map((p) => ({ loc: `${SITE.origin}/blog/posts/${p.slug}`, pri: '0.7', lastmod: p.updated || p.date })),
  ];
  const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map((u) => `  <url><loc>${u.loc}</loc>${u.lastmod ? `<lastmod>${u.lastmod}</lastmod>` : ''}<priority>${u.pri}</priority></url>`).join('\n')}
</urlset>
`;
  fs.writeFileSync(path.join(ROOT, 'sitemap.xml'), sitemap);
  console.log('  ✓ sitemap.xml');

  // robots.txt
  const aiBots = ['GPTBot', 'OAI-SearchBot', 'ChatGPT-User', 'PerplexityBot', 'Perplexity-User', 'Google-Extended', 'ClaudeBot', 'Claude-Web', 'anthropic-ai', 'Applebot-Extended', 'CCBot', 'Amazonbot', 'Bytespider', 'Meta-ExternalAgent'];
  const robots = `# 온더브라이드 robots.txt
User-agent: *
Allow: /
Disallow: /admin
Disallow: /portal

${aiBots.map((b) => `User-agent: ${b}\nAllow: /`).join('\n\n')}

Sitemap: ${SITE.origin}/sitemap.xml
`;
  fs.writeFileSync(path.join(ROOT, 'robots.txt'), robots);
  console.log('  ✓ robots.txt');

  // llms.txt
  fs.writeFileSync(path.join(ROOT, 'llms.txt'), renderLlms(posts));
  console.log('  ✓ llms.txt');

  console.log(`\n완료: 글 ${posts.length}편 생성 (origin=${SITE.origin})`);
}

build();
