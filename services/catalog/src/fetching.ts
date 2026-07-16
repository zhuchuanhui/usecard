import { createHash } from "node:crypto";
import * as cheerio from "cheerio";
import type { FreshnessStatus } from "./schema.js";

const USER_AGENT = "UseCardCatalogBot/1.0 (+https://github.com/zhuchuanhui/usecard; official-card-spec-monitor)";
const ROBOT_NAME = "usecardcatalogbot";
const robotsCache = new Map<string, Promise<string>>();
const originQueues = new Map<string, Promise<void>>();

export interface FetchedPage {
  url: string;
  html: string;
  text: string;
  hash: string;
  fetchedAt: string;
  freshness: FreshnessStatus;
}

export async function fetchOfficialPage(url: string): Promise<FetchedPage> {
  const target = new URL(url);
  await requireRobotsPermission(target);
  await waitForOrigin(target.origin);
  const response = await fetch(url, {
    headers: {
      "user-agent": USER_AGENT,
      accept: "text/html,application/xhtml+xml"
    },
    redirect: "follow",
    signal: AbortSignal.timeout(30_000)
  });
  if (!response.ok) throw new Error(`Failed to fetch ${url}: HTTP ${response.status}`);
  const html = decodeHTML(new Uint8Array(await response.arrayBuffer()), response.headers.get("content-type"));
  if (html.length < 500) throw new Error(`Fetched page is unexpectedly small: ${url}`);
  const $ = cheerio.load(html);
  $("script,style,noscript,svg").remove();
  const text = $.root().text().normalize("NFKC").replace(/\s+/g, " ").trim();
  return {
    url: response.url,
    html,
    text,
    hash: createHash("sha256").update(html).digest("hex"),
    fetchedAt: new Date().toISOString(),
    freshness: "fresh"
  };
}

export function decodeHTML(bytes: Uint8Array, contentType: string | null = null): string {
  const charset = detectCharset(bytes, contentType);
  try {
    return new TextDecoder(charset).decode(bytes);
  } catch {
    return new TextDecoder("utf-8").decode(bytes);
  }
}

function detectCharset(bytes: Uint8Array, contentType: string | null): string {
  const fromHeader = /charset\s*=\s*["']?([^\s;"']+)/i.exec(contentType ?? "")?.[1];
  const head = String.fromCharCode(...bytes.slice(0, 8_192));
  const fromDocument = /charset\s*=\s*["']?([^\s;"'>/]+)/i.exec(head)?.[1];
  const value = (fromHeader ?? fromDocument ?? "utf-8").trim().toLowerCase();
  if (["shift-jis", "shift_jis", "sjis", "windows-31j", "ms932", "cp932"].includes(value)) {
    return "shift_jis";
  }
  if (["euc-jp", "euc_jp"].includes(value)) return "euc-jp";
  if (["utf8", "utf-8"].includes(value)) return "utf-8";
  return value;
}

export function isAllowedByRobots(content: string, path: string, robotName = ROBOT_NAME): boolean {
  const groups: Array<{ agents: string[]; rules: Array<{ allow: boolean; path: string }> }> = [];
  let current: { agents: string[]; rules: Array<{ allow: boolean; path: string }> } | undefined;

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.replace(/#.*/, "").trim();
    if (!line) continue;
    const separator = line.indexOf(":");
    if (separator < 0) continue;
    const key = line.slice(0, separator).trim().toLowerCase();
    const value = line.slice(separator + 1).trim();
    if (key === "user-agent") {
      if (!current || current.rules.length > 0) {
        current = { agents: [], rules: [] };
        groups.push(current);
      }
      current.agents.push(value.toLowerCase());
    } else if ((key === "allow" || key === "disallow") && current && value) {
      current.rules.push({ allow: key === "allow", path: value });
    }
  }

  const exact = groups.filter((group) => group.agents.includes(robotName.toLowerCase()));
  const selected = exact.length > 0 ? exact : groups.filter((group) => group.agents.includes("*"));
  const matches = selected
    .flatMap((group) => group.rules)
    .filter((rule) => path.startsWith(rule.path))
    .sort((a, b) => b.path.length - a.path.length || Number(b.allow) - Number(a.allow));
  return matches[0]?.allow ?? true;
}

async function requireRobotsPermission(url: URL): Promise<void> {
  const robotsURL = new URL("/robots.txt", url.origin);
  let promise = robotsCache.get(url.origin);
  if (!promise) {
    promise = fetch(robotsURL, {
      headers: { "user-agent": USER_AGENT, accept: "text/plain" },
      signal: AbortSignal.timeout(10_000)
    }).then(async (response) => response.ok ? response.text() : "").catch(() => "");
    robotsCache.set(url.origin, promise);
  }
  const content = await promise;
  if (!isAllowedByRobots(content, `${url.pathname}${url.search}`)) {
    throw new Error(`robots.txt disallows catalog access: ${url.href}`);
  }
}

async function waitForOrigin(origin: string): Promise<void> {
  const previous = originQueues.get(origin) ?? Promise.resolve();
  const next = previous.then(() => new Promise<void>((resolve) => setTimeout(resolve, 400)));
  originQueues.set(origin, next);
  await previous;
}

export function slugifyCompany(name: string): string {
  const ascii = name
    .normalize("NFKC")
    .toLowerCase()
    .replace(/株式会社|有限会社|一般社団法人|カード|クレジット/g, "")
    .replace(/[^a-z0-9\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}]+/gu, "-")
    .replace(/^-|-$/g, "");
  return ascii || createHash("sha1").update(name).digest("hex").slice(0, 12);
}
