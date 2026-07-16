import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { extractGenericProduct, mergePromotedProducts } from "../src/genericExtractor.js";
import type { CardProduct } from "../src/schema.js";

test("strict generic extractor promotes a complete consumer card page", () => {
  const html = `
    <html><head><title>サンプルカード | サンプルカード株式会社</title></head>
    <body><h1>サンプルカード</h1><a href="/apply">お申し込み</a>
    <p>年会費 永年無料</p><p>通常還元率 1.0%</p><p>国際ブランド Visa Mastercard</p>
    <p>お申し込み対象 18歳以上（高校生を除く）</p></body></html>`;
  const product = extractGenericProduct(
    {
      url: "https://example.com/card/basic",
      html,
      text: "サンプルカード お申し込み 年会費 永年無料 通常還元率 1.0% 国際ブランド Visa Mastercard お申し込み対象 18歳以上",
      hash: createHash("sha256").update(html).digest("hex"),
      fetchedAt: "2026-07-16T00:00:00Z",
      freshness: "fresh"
    },
    {
      issuerID: "sample",
      issuerName: "サンプルカード株式会社",
      url: "https://example.com/card/basic",
      discoveredAt: "2026-07-16T00:00:00Z",
      evidence: "homepage"
    }
  );

  assert.equal(product?.name, "サンプルカード");
  assert.equal(product?.annualFeeYen, 0);
  assert.equal(product?.benefitRules[0]?.reward.ratePercent, 1);
  assert.deepEqual(product?.networks, ["visa", "mastercard"]);
});

test("incomplete or closed pages are not promoted", () => {
  const html = `<html><body><h1>終了カード</h1><p>新規申込受付を終了しました</p></body></html>`;
  const product = extractGenericProduct(
    {
      url: "https://example.com/card/closed",
      html,
      text: "終了カード 新規申込受付を終了しました 年会費無料 通常還元率1% Visa",
      hash: "hash",
      fetchedAt: "2026-07-16T00:00:00Z",
      freshness: "fresh"
    },
    {
      issuerID: "sample",
      issuerName: "Sample",
      url: "https://example.com/card/closed",
      discoveredAt: "2026-07-16T00:00:00Z",
      evidence: "homepage"
    }
  );
  assert.equal(product, undefined);
});

test("revolving-payment-only cards are not promoted", () => {
  const html = "<html><head><title>Jizile（リボ払い専用カード）</title></head><body><h1>Jizile（リボ払い専用カード）</h1><p>年会費 永年無料</p><p>新規入会 お申し込み</p><p>1,000円につき1ポイント</p><p>1ポイント4円相当</p><p>Visa</p></body></html>";
  const product = extractGenericProduct(
    {
      url: "https://example.com/card/jizile",
      html,
      text: "Jizile リボ払い専用カード 年会費 永年無料 新規入会 お申し込み 1,000円につき1ポイント 1ポイント4円相当 Visa",
      hash: createHash("sha256").update(html).digest("hex"),
      fetchedAt: "2026-07-16T00:00:00Z",
      freshness: "fresh"
    },
    {
      issuerID: "sample",
      issuerName: "Sample",
      url: "https://example.com/card/jizile",
      discoveredAt: "2026-07-16T00:00:00Z",
      evidence: "homepage"
    }
  );

  assert.equal(product, undefined);
});

test("membership-only cards are not promoted as publicly available cards", () => {
  const html = "<html><head><title>同窓会会員証カード</title></head><body><h1>同窓会会員証カード</h1><p>年会費 永年無料</p><p>新規入会 お申し込み</p><p>1,000円につき1ポイント</p><p>1ポイント4円相当</p><p>Visa</p></body></html>";
  const product = extractGenericProduct(
    {
      url: "https://example.com/card/alumni",
      html,
      text: "同窓会会員証カード 年会費 永年無料 新規入会 お申し込み 1,000円につき1ポイント 1ポイント4円相当 Visa",
      hash: createHash("sha256").update(html).digest("hex"),
      fetchedAt: "2026-07-16T00:00:00Z",
      freshness: "fresh"
    },
    {
      issuerID: "sample",
      issuerName: "Sample",
      url: "https://example.com/card/alumni",
      discoveredAt: "2026-07-16T00:00:00Z",
      evidence: "homepage"
    }
  );

  assert.equal(product, undefined);
});

test("article pages are not promoted even when they mention complete card facts", () => {
  const html = `<html><head><title>ETCカードの作り方を解説</title></head><body><h1>ETCカードの作り方を解説</h1><p>お申し込み 年会費無料 通常還元率1% Visa</p></body></html>`;
  const product = extractGenericProduct(
    {
      url: "https://example.com/mycard/beginner/article.html",
      html,
      text: "ETCカードの作り方を解説 お申し込み 年会費無料 通常還元率1% Visa",
      hash: "hash",
      fetchedAt: "2026-07-16T00:00:00Z",
      freshness: "fresh"
    },
    {
      issuerID: "sample",
      issuerName: "Sample",
      url: "https://example.com/mycard/beginner/article.html",
      discoveredAt: "2026-07-16T00:00:00Z",
      evidence: "sitemap"
    }
  );
  assert.equal(product, undefined);
});

test("structured member fee wins over a free family-card fee", () => {
  const html = `<html><head><title>ゴールドカード</title></head><body><h1>ゴールドカード</h1><a>お申し込み</a><table><tr><th>年会費</th><td>[本人会員] 3,300円 [家族会員] 1名無料</td></tr></table><p>ショッピングのご利用で1,000円につきサンプルポイントが1ポイント。1ポイント=5円相当</p><p>Visa</p></body></html>`;
  const product = extractGenericProduct(
    {
      url: "https://example.com/card/gold",
      html,
      text: "ゴールドカード お申し込み 年会費 [本人会員] 3,300円 [家族会員] 1名無料 ショッピングのご利用で1,000円につきサンプルポイントが1ポイント 1ポイント=5円相当 Visa",
      hash: "hash",
      fetchedAt: "2026-07-16T00:00:00Z",
      freshness: "fresh"
    },
    {
      issuerID: "sample",
      issuerName: "Sample",
      url: "https://example.com/card/gold",
      discoveredAt: "2026-07-16T00:00:00Z",
      evidence: "sitemap"
    }
  );
  assert.equal(product?.annualFeeYen, 3_300);
  assert.equal(product?.benefitRules[0]?.reward.pointsPerUnit, 1);
});

test("marketing copy is removed from a product heading", () => {
  const html = `<html><head><title>八十二JCB カード S 年会費永年無料で想像以上のオトクを手にしよう</title></head><body><h1>八十二JCB カード S 年会費永年無料で想像以上のオトクを手にしよう</h1><p>年会費 永年無料</p><p>新規入会 お申し込み</p><p>ショッピングのご利用で200円につき1ポイント</p><p>J-POINT</p><p>JCB</p></body></html>`;
  const product = extractGenericProduct(
    {
      url: "https://example.com/card/jcb-s",
      html,
      text: "八十二JCB カード S 年会費永年無料で想像以上のオトクを手にしよう 年会費 永年無料 新規入会 お申し込み ショッピングのご利用で200円につき1ポイント J-POINT JCB",
      hash: createHash("sha256").update(html).digest("hex"),
      fetchedAt: "2026-07-16T00:00:00Z",
      freshness: "fresh"
    },
    {
      issuerID: "sample",
      issuerName: "Sample",
      url: "https://example.com/card/jcb-s",
      discoveredAt: "2026-07-16T00:00:00Z",
      evidence: "homepage"
    }
  );

  assert.equal(product?.name, "八十二JCB カード S");
});

test("promotion retains prior verified cards missing from a temporary crawl", () => {
  const prior = productSnapshot("prior-card", "Prior Card", "https://example.com/card/prior");
  const refreshed = productSnapshot("fresh-card", "Fresh Card", "https://example.com/card/fresh");
  const merged = mergePromotedProducts([prior], [refreshed]);

  assert.deepEqual(merged.map((product) => product.id), ["fresh-card", "prior-card"]);
});

function productSnapshot(id: string, name: string, applicationURL: string): CardProduct {
  return {
    id,
    issuerID: "sample",
    issuerName: "Sample",
    name,
    networks: ["visa"],
    annualFeeYen: 0,
    applicationStatus: "open",
    applicationURL,
    eligibilityNote: "公式サイトで確認してください",
    benefitRules: [],
    sources: []
  };
}
