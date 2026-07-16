import * as cheerio from "cheerio";
import type { IssuerRegistryEntry } from "./schema.js";
import { decodeHTML } from "./fetching.js";

export interface ProductPageCandidate {
  issuerID: string;
  issuerName: string;
  url: string;
  discoveredAt: string;
  evidence: "sitemap" | "homepage";
}

const INCLUDE = /(?:card|credit|nyukai|apply|entry|クレジット|カード|入会)/i;
const EXCLUDE = /(?:company|corporate|business|bizcard|recruit|news|press|rule|kiyaku|terms|privacy|login|member|gift|cashing|cardloan|加盟店|法人|ビジネス|採用|お知らせ|ギフト|キャッシング|ローン)/i;

export async function discoverProductPages(
  registry: IssuerRegistryEntry[],
  concurrency = 4
): Promise<ProductPageCandidate[]> {
  const issuers = registry.filter((entry) => entry.officialURL && entry.status === "needsProductAdapter");
  const candidates: ProductPageCandidate[] = [];

  for (let index = 0; index < issuers.length; index += concurrency) {
    const batch = issuers.slice(index, index + concurrency);
    const results = await Promise.allSettled(batch.map(discoverForIssuer));
    for (const result of results) {
      if (result.status === "fulfilled") candidates.push(...result.value);
    }
  }

  const unique = new Map(candidates.map((candidate) => [candidate.url, candidate]));
  return [...unique.values()].sort((a, b) => a.url.localeCompare(b.url));
}

async function discoverForIssuer(issuer: IssuerRegistryEntry): Promise<ProductPageCandidate[]> {
  const officialURL = issuer.officialURL;
  if (!officialURL) return [];
  const base = new URL(officialURL);
  const discoveredAt = new Date().toISOString();

  const sitemapCandidates = await discoverFromSitemaps(base, issuer, discoveredAt);
  if (sitemapCandidates.length > 0) return sitemapCandidates.slice(0, 500);
  return discoverFromHomepage(base, issuer, discoveredAt);
}

async function discoverFromSitemaps(
  base: URL,
  issuer: IssuerRegistryEntry,
  discoveredAt: string
): Promise<ProductPageCandidate[]> {
  const locations = new Set<string>();
  for (const path of ["/sitemap.xml", "/sitemap_index.xml"]) {
    try {
      const xml = await fetchText(new URL(path, base).href, "application/xml,text/xml");
      const $ = cheerio.load(xml, { xmlMode: true });
      $("loc").each((_, element) => {
        const value = $(element).text().trim();
        if (value) locations.add(value);
      });
    } catch {
      // A missing sitemap is expected; the homepage fallback handles it.
    }
  }

  return [...locations]
    .filter((url) => isCandidateURL(url, base))
    .map((url) => ({
      issuerID: issuer.id,
      issuerName: issuer.name,
      url,
      discoveredAt,
      evidence: "sitemap" as const
    }));
}

async function discoverFromHomepage(
  base: URL,
  issuer: IssuerRegistryEntry,
  discoveredAt: string
): Promise<ProductPageCandidate[]> {
  const html = await fetchText(base.href, "text/html");
  const $ = cheerio.load(html);
  const values = new Set<string>();
  $("a[href]").each((_, element) => {
    const href = $(element).attr("href");
    const label = $(element).text().replace(/\s+/g, " ").trim();
    if (!href || (!INCLUDE.test(href) && !INCLUDE.test(label))) return;
    try {
      const url = new URL(href, base).href;
      if (isCandidateURL(url, base)) values.add(url);
    } catch {
      // Ignore malformed links from the source page.
    }
  });

  return [...values].slice(0, 200).map((url) => ({
    issuerID: issuer.id,
    issuerName: issuer.name,
    url,
    discoveredAt,
    evidence: "homepage" as const
  }));
}

function isCandidateURL(value: string, base: URL): boolean {
  try {
    const url = new URL(value);
    if (url.hostname !== base.hostname) return false;
    const target = `${url.pathname}${url.search}`;
    return INCLUDE.test(target) && !EXCLUDE.test(target) && !/\.(?:pdf|jpg|jpeg|png|gif|zip)$/i.test(url.pathname);
  } catch {
    return false;
  }
}

async function fetchText(url: string, accept: string): Promise<string> {
  const response = await fetch(url, {
    headers: {
      accept,
      "user-agent": "UseCardCatalogBot/1.0 (+official-card-spec-monitor)"
    },
    redirect: "follow",
    signal: AbortSignal.timeout(20_000)
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${url}`);
  return decodeHTML(new Uint8Array(await response.arrayBuffer()), response.headers.get("content-type"));
}
