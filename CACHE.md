# 자산 캐시 규칙

`vercel.json` 은 JSON 이라 주석을 못 단다. 설명을 여기 남긴다.

## 왜 이렇게 하나

예전에는 모든 js·css 를 `no-cache` 로 내보냈다. 주소에 `?v=` 가 붙어 있는데도
그랬는데, 손으로 적은 버전이라 믿을 수 없었기 때문이다. 실제로 어긋나 있었다.

- `styles.css` 가 페이지마다 `20260720a` / `20260810a` / `20260821a` 세 가지
- `survey.css`(7곳), `portal.js`, `portal.css`, `survey.js`, `guide.css` 일부는 버전 자체가 없었다

지금은 `tools/stamp.mjs` 가 **파일 내용을 해시해서** `?v=` 를 찍는다.
내용이 바뀌면 주소가 바뀌고, 안 바뀌면 그대로다. 그래서 브라우저에
"1년간 다시 묻지 마라"(`max-age=31536000, immutable`) 라고 말해도 안전하다.

## 규칙

| 파일 | 캐시 | 이유 |
|---|---|---|
| js·css (`vercel.json` 에 적힌 것) | 1년, immutable | 주소에 내용 도장이 찍힌다 |
| `config.js` | `no-cache` | 설정이라 언제든 손으로 고칠 수 있어야 한다 |
| `sw.js` | `no-cache` | 낡은 서비스워커가 남으면 곤란하다 |
| HTML | Vercel 기본(매번 확인) | 여기서 새 도장을 알려줘야 한다 |

`vercel.json` 에 파일을 하나하나 적은 이유: `/(.*).js` 처럼 모아서 걸면
`config.js`·`sw.js` 까지 덮어쓴다. 새 파일을 넣고 여기 안 적으면 Vercel 기본값
(매번 확인)이 된다 — 안전한 쪽으로 실패한다.

## 배포 전에 할 일

```
node tools/stamp.mjs          # 도장 다시 찍기
node tools/stamp.mjs --check  # 안 맞으면 실패로 끝냄
```

깜빡해도 `stamp.test.mjs` 가 잡는다. HTML 의 모든 자산 참조를 훑어서
도장이 있는지, 지금 파일 내용과 맞는지, 같은 파일이 페이지마다 같은 주소인지 본다.
