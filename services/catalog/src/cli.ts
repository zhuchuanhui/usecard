import { resolve } from "node:path";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { discoverProductPages } from "./discovery.js";
import type { ProductPageCandidate } from "./discovery.js";
import { mergePromotedProducts, promoteCandidates } from "./genericExtractor.js";
import { validateCatalog } from "./validation.js";
import { buildCatalog } from "./pipeline.js";
import { fetchJCCAIssuerRegistry } from "./jccaRegistry.js";
import { knownCardDefinitions } from "./sourceDefinitions.js";
import type { CardProduct } from "./schema.js";

const command = process.argv[2] ?? "update";

if (command === "update") {
  const outputRoot = resolve(process.cwd(), "../../catalog/public");
  const result = await buildCatalog(outputRoot);
  console.log(
    JSON.stringify(
      {
        catalogVersion: result.manifest.catalogVersion,
        productCount: result.manifest.productCount,
        coverage: result.manifest.issuerCoverage
      },
      null,
      2
    )
  );
} else if (command === "discover") {
  const registry = await fetchJCCAIssuerRegistry(
    new Set(knownCardDefinitions.map((definition) => definition.issuerName))
  );
  if (process.argv.includes("--crawl")) {
    const candidates = await discoverProductPages(registry);
    const output = resolve(process.cwd(), "../../catalog/discovery/candidates.json");
    await mkdir(resolve(output, ".."), { recursive: true });
    await writeFile(output, `${JSON.stringify(candidates, null, 2)}\n`);
    console.log(JSON.stringify({ issuerCount: registry.length, candidateCount: candidates.length }, null, 2));
  } else {
    console.log(JSON.stringify(registry, null, 2));
  }
} else if (command === "promote") {
  const input = resolve(process.cwd(), "../../catalog/discovery/candidates.json");
  const output = resolve(process.cwd(), "../../catalog/config/generic-products.json");
  const reportOutput = resolve(process.cwd(), "../../catalog/discovery/promotion-report.json");
  const searchIndexOutput = resolve(process.cwd(), "../../catalog/discovery/card-search-index.json");
  const candidates = JSON.parse(await readFile(input, "utf8")) as ProductPageCandidate[];
  const priorVerified = await readProductSnapshots(output);
  const result = await promoteCandidates(candidates);
  const products = mergePromotedProducts(priorVerified, result.products);
  const report = {
    ...result.report,
    retainedCount: products.length - result.products.length,
    publishedProductCount: products.length
  };
  validateCatalog({
    schemaVersion: 1,
    version: "promotion-validation",
    generatedAt: new Date().toISOString(),
    products
  });
  await mkdir(resolve(output, ".."), { recursive: true });
  await writeFile(output, `${JSON.stringify(products, null, 2)}\n`);
  await writeFile(reportOutput, `${JSON.stringify(report, null, 2)}\n`);
  await writeFile(searchIndexOutput, `${JSON.stringify(result.searchIndex, null, 2)}\n`);
  console.log(JSON.stringify(report, null, 2));
} else {
  console.error(`Unknown command: ${command}`);
  process.exitCode = 2;
}

async function readProductSnapshots(path: string): Promise<CardProduct[]> {
  try {
    return JSON.parse(await readFile(path, "utf8")) as CardProduct[];
  } catch {
    return [];
  }
}
