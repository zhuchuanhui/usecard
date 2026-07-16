import * as cheerio from "cheerio";
import { fetchOfficialPage, slugifyCompany } from "./fetching.js";
import type { IssuerRegistryEntry } from "./schema.js";

export const JCCA_MEMBER_URL = "https://www.jcca-office.gr.jp/about/member/";

export async function fetchJCCAIssuerRegistry(trackedIssuerNames: Set<string>): Promise<IssuerRegistryEntry[]> {
  const page = await fetchOfficialPage(JCCA_MEMBER_URL);
  return parseJCCAIssuerRegistry(page.html, page.fetchedAt, trackedIssuerNames);
}

export function parseJCCAIssuerRegistry(
  html: string,
  discoveredAt: string,
  trackedIssuerNames: Set<string> = new Set()
): IssuerRegistryEntry[] {
  const $ = cheerio.load(html);
  const entries: IssuerRegistryEntry[] = [];

  $("tbody tr").each((_, row) => {
    const header = $(row).find("th").first();
    const name = header.text().replace(/\s+/g, " ").trim();
    if (!name) return;
    const officialURL = header.find("a[href]").attr("href")?.trim();
    const tracked = [...trackedIssuerNames].some((trackedName) => name.includes(trackedName) || trackedName.includes(name));
    entries.push({
      id: `jcca-${slugifyCompany(name)}`,
      name,
      ...(officialURL ? { officialURL } : {}),
      status: tracked ? "tracked" : "needsProductAdapter",
      discoveredAt
    });
  });

  return entries.sort((a, b) => a.name.localeCompare(b.name, "ja"));
}
