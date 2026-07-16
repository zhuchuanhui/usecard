import * as cheerio from "cheerio";
import type { ProductPageCandidate } from "./discovery.js";
import { fetchOfficialPage, slugifyCompany } from "./fetching.js";
import type {
  BenefitRule,
  CardNetwork,
  CardProduct,
  RewardFormula,
  SourceEvidence
} from "./schema.js";
import { emptyConditions } from "./schema.js";
import type { FetchedPage } from "./fetching.js";

export interface PromotionReport {
  candidateCount: number;
  fetchedCount: number;
  promotedCount: number;
  skippedCount: number;
  failedDomainCount: number;
}

export interface PromotionResult {
  products: CardProduct[];
  report: PromotionReport;
}

const EXCLUDED_PRODUCT = /(?:法人|ビジネス|コーポレート|Business|Corporate|デビット|プリペイド|ローン|キャッシング|ギフト|リボ払い専用|会員証|メンバーズ(?:カード)?|同窓会)/i;
const CLOSED_APPLICATION = /(?:新規.{0,8}申込.{0,8}終了|募集.{0,4}終了|申込受付.{0,4}終了|現在.{0,8}お申し込みいただけません)/;
const APPLICATION_SIGNAL = /(?:新規入会|入会申込|お申し込み|お申込み|申し込む|申込む|カードをつくる)/;
const GENERIC_NAME = /^(?:クレジットカード|カード一覧|カードラインアップ|カードを選ぶ|カードを探す|個人のお客さま|カードについて|カードのご案内)$/;
const NON_PRODUCT_NAME = /(?:【公式】|とは[?？]|を解説|おすすめ|選び方|作り方|活用術|カード一覧|申し込みはこちら|お申し込みはこちら|カードをつくる|カードを探す|キャンペーン|クレカ積立|新社会人|学生の初めて|が登場|登場[!！])/;
const NON_PRODUCT_PATH = /(?:\/magazine\/|\/mycard\/|\/column\/|\/campaign\/|\/lineup\/|\/apply\/index\.(?:html?|jsp)$|\/card\/list\/?$|\/card\/about\/?$|\/card\/firsttime\/?$)/i;

export function extractGenericProduct(
  page: FetchedPage,
  candidate: ProductPageCandidate
): CardProduct | undefined {
  if (NON_PRODUCT_PATH.test(new URL(page.url).pathname)) return undefined;
  if (EXCLUDED_PRODUCT.test(page.text) && EXCLUDED_PRODUCT.test(extractHeading(page.html))) return undefined;
  if (CLOSED_APPLICATION.test(page.text) || !APPLICATION_SIGNAL.test(page.text)) return undefined;

  const name = extractProductName(page.html, candidate.issuerName);
  if (!name || EXCLUDED_PRODUCT.test(name) || NON_PRODUCT_NAME.test(name)) return undefined;
  const annualFeeYen = extractAnnualFee(page.html, page.text);
  if (annualFeeYen === undefined) return undefined;
  const reward = extractReward(page.text, candidate.issuerName);
  if (!reward) return undefined;
  const networks = extractNetworks(page.html, page.text, page.url);
  if (networks.length === 0) return undefined;

  const source: SourceEvidence = {
    url: page.url,
    observedAt: page.fetchedAt,
    contentHash: page.hash,
    freshness: page.freshness
  };
  const rule: BenefitRule = {
    id: `${candidate.issuerID}-${slugifyCompany(name)}-base`,
    title: "通常還元（公式記載）",
    stackingGroup: "base",
    conditions: emptyConditions(),
    reward,
    source
  };
  const pointProgramID = reward.pointProgramID;

  return {
    id: `${candidate.issuerID}-${slugifyCompany(name)}`,
    issuerID: candidate.issuerID,
    issuerName: candidate.issuerName,
    name,
    networks,
    annualFeeYen,
    applicationStatus: "open",
    applicationURL: page.url,
    eligibilityNote: extractEligibility(page.text),
    ...(pointProgramID ? { pointProgramID } : {}),
    benefitRules: [rule],
    sources: [source]
  };
}

export async function promoteCandidates(
  candidates: ProductPageCandidate[],
  concurrency = 6
): Promise<PromotionResult> {
  const byDomain = new Map<string, ProductPageCandidate[]>();
  for (const candidate of candidates) {
    try {
      const hostname = new URL(candidate.url).hostname;
      const values = byDomain.get(hostname) ?? [];
      values.push(candidate);
      byDomain.set(hostname, values);
    } catch {
      // Invalid URLs stay out of the promotion set.
    }
  }

  const groups = [...byDomain.values()];
  const promoted: CardProduct[] = [];
  let fetchedCount = 0;
  let failedDomainCount = 0;
  let cursor = 0;

  async function worker(): Promise<void> {
    while (cursor < groups.length) {
      const group = groups[cursor++];
      if (!group) continue;
      let consecutiveFailures = 0;
      let fetchedOnDomain = 0;
      for (const candidate of group) {
        try {
          const page = await fetchOfficialPage(candidate.url);
          fetchedCount += 1;
          fetchedOnDomain += 1;
          consecutiveFailures = 0;
          const product = extractGenericProduct(page, candidate);
          if (product) promoted.push(product);
        } catch {
          consecutiveFailures += 1;
          if (consecutiveFailures >= 2) break;
        }
        await new Promise((resolve) => setTimeout(resolve, 75));
      }
      if (fetchedOnDomain === 0) failedDomainCount += 1;
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, groups.length) }, worker));
  const products = deduplicateProducts(promoted);
  return {
    products,
    report: {
      candidateCount: candidates.length,
      fetchedCount,
      promotedCount: products.length,
      skippedCount: candidates.length - products.length,
      failedDomainCount
    }
  };
}

export function mergePromotedProducts(
  priorVerified: CardProduct[],
  newlyPromoted: CardProduct[]
): CardProduct[] {
  const freshIDs = new Set(newlyPromoted.map((product) => product.id));
  const freshIdentities = new Set(newlyPromoted.map(productIdentity));
  const freshURLs = new Set(newlyPromoted.map((product) => product.applicationURL));
  const retained = priorVerified.filter((product) =>
    !freshIDs.has(product.id)
      && !freshIdentities.has(productIdentity(product))
      && !freshURLs.has(product.applicationURL)
  );
  return deduplicateProducts([...newlyPromoted, ...retained]);
}

export async function refreshGenericProducts(
  snapshots: CardProduct[],
  concurrency = 8
): Promise<CardProduct[]> {
  let cursor = 0;
  const refreshed: CardProduct[] = [];

  async function worker(): Promise<void> {
    while (cursor < snapshots.length) {
      const snapshot = snapshots[cursor++];
      if (!snapshot) continue;
      const candidate: ProductPageCandidate = {
        issuerID: snapshot.issuerID,
        issuerName: snapshot.issuerName,
        url: snapshot.applicationURL,
        discoveredAt: snapshot.sources[0]?.observedAt ?? new Date().toISOString(),
        evidence: "homepage"
      };
      try {
        const page = await fetchOfficialPage(snapshot.applicationURL);
        const product = extractGenericProduct(page, candidate);
        refreshed.push(product ? { ...product, id: snapshot.id } : unavailable(snapshot));
      } catch {
        refreshed.push(unavailable(snapshot));
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, Math.max(snapshots.length, 1)) }, worker));
  return refreshed.sort((a, b) => a.name.localeCompare(b.name, "ja"));
}

function unavailable(snapshot: CardProduct): CardProduct {
  const observedAt = new Date().toISOString();
  const sources = snapshot.sources.map((source) => ({ ...source, observedAt, freshness: "unavailable" as const }));
  const sourceByURL = new Map(sources.map((source) => [source.url, source]));
  return {
    ...snapshot,
    sources,
    benefitRules: snapshot.benefitRules.map((rule) => ({
      ...rule,
      source: sourceByURL.get(rule.source.url) ?? { ...rule.source, observedAt, freshness: "unavailable" }
    }))
  };
}

function extractProductName(html: string, issuerName: string): string | undefined {
  const $ = cheerio.load(html);
  const values = [
    $("h1").first().text(),
    $('meta[property="og:title"]').attr("content") ?? "",
    $("title").text()
  ];

  for (const value of values) {
    const cleaned = value
      .normalize("NFKC")
      .replace(/\s+/g, " ")
      .split(/\s*[|｜]\s*/)[0]!
      .replace(new RegExp(`\\s*[-–—:]?\\s*${escapeRegExp(issuerName)}.*$`), "")
      .replace(/\s+(?:年会費|初年度|ポイント還元|キャッシュバック|特典|おトク).*/u, "")
      .trim();
    if (cleaned.length < 3 || cleaned.length > 90) continue;
    if (GENERIC_NAME.test(cleaned)) continue;
    if (!/(?:カード|Card|VISA|Visa|Mastercard|JCB|AMEX|アメリカン)/i.test(cleaned)) continue;
    return cleaned;
  }
  return undefined;
}

function extractHeading(html: string): string {
  const $ = cheerio.load(html);
  return $("h1").first().text().normalize("NFKC").replace(/\s+/g, " ").trim();
}

function extractAnnualFee(html: string, text: string): number | undefined {
  const $ = cheerio.load(html);
  const structured: string[] = [];
  $("th,dt").each((_, element) => {
    const label = $(element).text().normalize("NFKC").replace(/\s+/g, " ").trim();
    if (!/^年会費/.test(label)) return;
    const sibling = $(element).next("td,dd").text();
    const parent = $(element).parent().text();
    structured.push((sibling || parent).normalize("NFKC").replace(/\s+/g, " ").trim());
  });
  for (const value of structured) {
    const primary = value.split(/\[?家族会員\]?|家族カード|ETCカード/)[0] ?? value;
    const fee = parseFee(primary);
    if (fee !== undefined) return fee;
  }

  const snippets = [...text.matchAll(/年会費(.{0,180})/g)].map((match) => match[0]);
  for (const snippet of snippets) {
    const fee = parseFee(snippet);
    if (fee !== undefined) return fee;
  }
  return undefined;
}

function parseFee(value: string): number | undefined {
  if (/初年度.{0,12}無料/.test(value)) {
    const continuingFee = /(?:2年目以降|次年度以降|翌年度以降|通常年会費).{0,40}?([0-9][0-9,]*)円/.exec(value)?.[1];
    if (continuingFee) return Number(continuingFee.replaceAll(",", ""));
  }
  const memberAmount = /(?:本人会員|本会員).{0,40}?([0-9][0-9,]*)円/.exec(value)?.[1];
  if (memberAmount) return Number(memberAmount.replaceAll(",", ""));
  if (/永年.{0,4}無料/.test(value)) return 0;
  const amount = /([0-9][0-9,]*)円/.exec(value)?.[1];
  if (amount) return Number(amount.replaceAll(",", ""));
  if (/(?:本人会員|本会員|年会費)?.{0,20}無料/.test(value) && !/初年度/.test(value)) return 0;
  return undefined;
}

function extractReward(text: string, issuerName: string): RewardFormula | undefined {
  const ratePatterns = [
    /(?:通常|基本)(?:ポイント)?還元率.{0,24}?([0-9]+(?:\.[0-9]+)?)%/,
    /(?:通常|基本).{0,20}?([0-9]+(?:\.[0-9]+)?)%還元/
  ];
  for (const pattern of ratePatterns) {
    const rate = Number(pattern.exec(text)?.[1]);
    if (Number.isFinite(rate) && rate > 0 && rate <= 10) {
      return { kind: "cashbackRate", ratePercent: rate };
    }
  }

  const program = pointProgram(text, issuerName);
  if (!program) return undefined;
  const pointPattern = /([0-9][0-9,]*)円(?:\(税込\))?.{0,24}?(?:につき|ごとに).{0,24}?([0-9]+(?:\.[0-9]+)?)(?:ポイント|POINT)/gi;
  const matches = [...text.matchAll(pointPattern)]
    .filter((match) => match[1] && match[2] && match.index !== undefined)
    .map((match) => {
      const unit = Number(match[1]!.replaceAll(",", ""));
      const points = Number(match[2]);
      const context = text.slice(Math.max(0, match.index! - 160), Math.min(text.length, match.index! + match[0].length + 80));
      let score = 0;
      if (/(?:通常|基本)/.test(context)) score += 6;
      if (/(?:ショッピングのご利用|毎日のショッピング|国内外でのご利用|日常のお買い物)/.test(context)) score += 4;
      if (/(?:ショップ|予約|対象店舗|加盟店|特約店|優待店|ボーナス)/.test(context)) score -= 5;
      const effectiveRate = unit > 0 ? points * program.valueYen / unit : Number.POSITIVE_INFINITY;
      return { unit, points, score, effectiveRate };
    })
    .filter((match) => match.unit > 0 && match.points > 0 && match.score >= 0 && match.effectiveRate <= 0.03)
    .sort((a, b) => b.score - a.score || a.effectiveRate - b.effectiveRate);
  const unitMatch = matches[0];
  if (!unitMatch) return undefined;
  return {
    kind: "pointsPerUnit",
    unitAmountYen: unitMatch.unit,
    pointsPerUnit: unitMatch.points,
    pointProgramID: program.id,
    defaultPointValueYen: program.valueYen
  };
}

function pointProgram(text: string, issuerName: string): { id: string; valueYen: number } | undefined {
  const programs: Array<[RegExp, string, number]> = [
    [/Vポイント/, "v-point", 1],
    [/WAON POINT/i, "waon-point", 1],
    [/J-POINT/i, "j-point", 1],
    [/楽天ポイント/, "rakuten-point", 1],
    [/dポイント/i, "d-point", 1],
    [/PayPayポイント/i, "paypay-point", 1],
    [/エポスポイント/, "epos-point", 1],
    [/Pontaポイント/i, "ponta-point", 1],
    [/nanacoポイント/i, "nanaco-point", 1]
  ];
  for (const [pattern, id, valueYen] of programs) {
    if (pattern.test(text)) return { id, valueYen };
  }
  const explicitValue = /1ポイント.{0,16}?([0-9]+(?:\.[0-9]+)?)円(?:相当)?/.exec(text)?.[1];
  if (explicitValue) {
    const valueYen = Number(explicitValue);
    if (valueYen > 0 && valueYen <= 10) {
      return { id: `${slugifyCompany(issuerName)}-point`, valueYen };
    }
  }
  return undefined;
}

function extractNetworks(html: string, text: string, url: string): CardNetwork[] {
  const target = `${url} ${html.slice(0, 250_000)} ${text.slice(0, 25_000)}`;
  const networks: CardNetwork[] = [];
  if (/\bVisa\b|\/visa\//i.test(target)) networks.push("visa");
  if (/Mastercard|Master Card|マスターカード/i.test(target)) networks.push("mastercard");
  if (/\bJCB\b|\/jcb\//i.test(target)) networks.push("jcb");
  if (/American Express|アメリカン・?エキスプレス|\bAMEX\b/i.test(target)) networks.push("americanExpress");
  if (/Diners Club|ダイナースクラブ/i.test(target)) networks.push("dinersClub");
  return [...new Set(networks)];
}

function extractEligibility(text: string): string {
  const match = /(?:お申し込み対象|お申込対象|申込資格|入会資格)(.{0,140})/.exec(text)?.[1];
  return match?.replace(/\s+/g, " ").trim() || "申込条件は公式サイトで確認してください";
}

function deduplicateProducts(products: CardProduct[]): CardProduct[] {
  const values = new Map<string, CardProduct>();
  for (const product of products) {
    const key = productIdentity(product);
    const current = values.get(key);
    if (!current || preferred(product, current)) values.set(key, product);
  }
  return [...values.values()].sort((a, b) => a.name.localeCompare(b.name, "ja"));
}

function productIdentity(product: CardProduct): string {
  return `${product.issuerID}:${product.name.normalize("NFKC").replace(/\s+/g, "").toLowerCase()}`;
}

function preferred(candidate: CardProduct, current: CardProduct): boolean {
  const candidateHTTPS = candidate.applicationURL.startsWith("https://");
  const currentHTTPS = current.applicationURL.startsWith("https://");
  if (candidateHTTPS !== currentHTTPS) return candidateHTTPS;
  return candidate.applicationURL.length < current.applicationURL.length;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
