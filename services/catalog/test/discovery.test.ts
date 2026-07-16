import assert from "node:assert/strict";
import test from "node:test";

test("product candidate URL policy keeps likely application pages", () => {
  const include = /(?:card|credit|nyukai|apply|entry|クレジット|カード|入会)/i;
  const exclude = /(?:company|corporate|business|bizcard|recruit|news|press|rule|kiyaku|terms|privacy|login|member|gift|cashing|cardloan|加盟店|法人|ビジネス|採用|お知らせ|ギフト|キャッシング|ローン)/i;
  const candidates = [
    "/nyukai/card/basic.html",
    "/company/news/card-release.html",
    "/privacy/",
    "/credit/apply/"
  ].filter((value) => include.test(value) && !exclude.test(value));

  assert.deepEqual(candidates, ["/nyukai/card/basic.html", "/credit/apply/"]);
});
