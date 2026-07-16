import { createHash } from "node:crypto";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { fetchOfficialPage } from "./fetching.js";
import type { FetchedPage } from "./fetching.js";
import { fetchJCCAIssuerRegistry } from "./jccaRegistry.js";
import { knownCardDefinitions } from "./sourceDefinitions.js";
import { refreshGenericProducts } from "./genericExtractor.js";
import type {
  CardCatalog,
  CardProduct,
  CatalogManifest,
  IssuerRegistryEntry,
  SourceEvidence
} from "./schema.js";
import { emptyConditions } from "./schema.js";
import { validateCatalog } from "./validation.js";

export interface PipelineResult {
  catalog: CardCatalog;
  manifest: CatalogManifest;
  registry: IssuerRegistryEntry[];
}

export async function buildCatalog(outputRoot: string): Promise<PipelineResult> {
  const products: CardProduct[] = [];
  for (const definition of knownCardDefinitions) {
    const pages = await Promise.all(
      definition.sourceURLs.map(async (url): Promise<FetchedPage> => {
        try {
          return await fetchOfficialPage(url);
        } catch (error) {
          const fallbackText = definition.fallbackTexts?.[url];
          if (!fallbackText) throw error;
          return {
            url,
            html: "",
            text: fallbackText,
            hash: createHash("sha256").update(fallbackText).digest("hex"),
            fetchedAt: new Date().toISOString(),
            freshness: "unavailable"
          };
        }
      })
    );
    const sources: SourceEvidence[] = pages.map((page) => ({
      url: page.url,
      observedAt: page.fetchedAt,
      contentHash: page.hash,
      freshness: page.freshness
    }));
    products.push(definition.build(pages, sources));
  }

  const genericSnapshots = await loadGenericSnapshots(outputRoot);
  if (genericSnapshots.length > 0) {
    const refreshed = await refreshGenericProducts(genericSnapshots);
    const knownIDs = new Set(products.map((product) => product.id));
    const knownNames = new Set(products.map(productIdentity));
    products.push(
      ...refreshed.filter((product) => !knownIDs.has(product.id) && !knownNames.has(productIdentity(product)))
    );
  }

  const generatedAt = new Date().toISOString();
  const version = generatedAt.replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
  const catalog: CardCatalog = {
    schemaVersion: 1,
    version,
    generatedAt,
    products: products.sort((a, b) => a.name.localeCompare(b.name, "ja"))
  };
  validateCatalog(catalog);

  const trackedIssuerNames = new Set(products.map((product) => product.issuerName));
  const registry = await fetchJCCAIssuerRegistry(trackedIssuerNames);
  for (const product of products) {
    if (!registry.some((entry) => entry.status === "tracked" && entry.name.includes(product.issuerName))) {
      registry.push({
        id: `tracked-${product.issuerID}`,
        name: product.issuerName,
        officialURL: new URL(product.applicationURL).origin,
        status: "tracked",
        discoveredAt: generatedAt
      });
    }
  }
  registry.sort((a, b) => a.name.localeCompare(b.name, "ja"));

  const catalogJSON = `${JSON.stringify(catalog, null, 2)}\n`;
  const catalogFile = `catalog-${version}.json`;
  const sha256 = createHash("sha256").update(catalogJSON).digest("hex");
  const manifest: CatalogManifest = {
    schemaVersion: 1,
    catalogVersion: version,
    generatedAt,
    path: catalogFile,
    sha256,
    productCount: products.length,
    issuerCoverage: {
      registryCount: registry.length,
      trackedCount: registry.filter((entry) => entry.status === "tracked").length,
      pendingCount: registry.filter((entry) => entry.status === "needsProductAdapter").length
    }
  };

  await publishAtomically(outputRoot, catalogFile, catalogJSON, manifest, registry);
  return { catalog, manifest, registry };
}

async function loadGenericSnapshots(outputRoot: string): Promise<CardProduct[]> {
  const path = resolve(outputRoot, "../config/generic-products.json");
  try {
    return normalizeGenericSnapshots(JSON.parse(await readFile(path, "utf8")) as CardProduct[]);
  } catch {
    return [];
  }
}

function normalizeGenericSnapshots(snapshots: CardProduct[]): CardProduct[] {
  return snapshots.map((product) => ({
    ...product,
    benefitRules: product.benefitRules.map((rule) => ({
      ...rule,
      conditions: {
        ...emptyConditions(),
        ...rule.conditions,
        eligibleDaysOfMonth: rule.conditions.eligibleDaysOfMonth ?? []
      }
    }))
  }));
}

function productIdentity(product: CardProduct): string {
  return `${product.issuerID}:${product.name.normalize("NFKC").replace(/\s+/g, "").toLowerCase()}`;
}

async function publishAtomically(
  outputRoot: string,
  catalogFile: string,
  catalogJSON: string,
  manifest: CatalogManifest,
  registry: IssuerRegistryEntry[]
): Promise<void> {
  const root = resolve(outputRoot);
  const staging = join(dirname(root), ".staging", basename(root));
  await rm(staging, { recursive: true, force: true });
  await mkdir(staging, { recursive: true });

  try {
    await writeFile(join(staging, catalogFile), catalogJSON);
    await writeFile(join(staging, "latest.json"), catalogJSON);
    await writeFile(join(staging, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
    await writeFile(join(staging, "issuers.json"), `${JSON.stringify(registry, null, 2)}\n`);
    await mkdir(root, { recursive: true });
    for (const file of [catalogFile, "latest.json", "manifest.json", "issuers.json"]) {
      await rm(join(root, file), { force: true });
      await rename(join(staging, file), join(root, file));
    }
    await rm(staging, { recursive: true, force: true });
  } catch (error) {
    await rm(staging, { recursive: true, force: true });
    throw error;
  }
}
