import type { CardCatalog, CardProduct, BenefitRule } from "./schema.js";

export class CatalogValidationError extends Error {
  constructor(public readonly issues: string[]) {
    super(`Catalog validation failed:\n${issues.map((issue) => `- ${issue}`).join("\n")}`);
  }
}

export function validateCatalog(catalog: CardCatalog): void {
  const issues: string[] = [];
  if (catalog.schemaVersion !== 1) issues.push("schemaVersion must be 1");
  if (!catalog.version) issues.push("version is required");
  if (!catalog.generatedAt) issues.push("generatedAt is required");
  if (catalog.products.length === 0) issues.push("at least one product is required");

  const productIDs = new Set<string>();
  for (const product of catalog.products) {
    if (productIDs.has(product.id)) issues.push(`duplicate product id: ${product.id}`);
    productIDs.add(product.id);
    validateProduct(product, issues);
  }

  if (issues.length > 0) throw new CatalogValidationError(issues);
}

function validateProduct(product: CardProduct, issues: string[]): void {
  const prefix = `product ${product.id}`;
  if (!product.id || !product.name || !product.issuerName) issues.push(`${prefix}: identity fields are required`);
  if (product.annualFeeYen < 0 || !Number.isFinite(product.annualFeeYen)) issues.push(`${prefix}: annualFeeYen is invalid`);
  if (product.networks.length === 0) issues.push(`${prefix}: at least one network is required`);
  if (product.sources.length === 0) issues.push(`${prefix}: official source is required`);
  if (product.benefitRules.length === 0) issues.push(`${prefix}: at least one benefit rule is required`);
  assertOfficialWebURL(product.applicationURL, `${prefix}: applicationURL`, issues);

  const ruleIDs = new Set<string>();
  for (const rule of product.benefitRules) {
    if (ruleIDs.has(rule.id)) issues.push(`${prefix}: duplicate rule id ${rule.id}`);
    ruleIDs.add(rule.id);
    validateRule(product, rule, issues);
  }
}

function validateRule(product: CardProduct, rule: BenefitRule, issues: string[]): void {
  const prefix = `rule ${product.id}/${rule.id}`;
  if (!rule.title || !rule.stackingGroup) issues.push(`${prefix}: title and stackingGroup are required`);
  assertOfficialWebURL(rule.source.url, `${prefix}: source`, issues);

  const reward = rule.reward;
  switch (reward.kind) {
    case "cashbackRate":
      if (reward.ratePercent === undefined || reward.ratePercent < 0 || reward.ratePercent > 30) {
        issues.push(`${prefix}: cashback rate must be between 0 and 30`);
      }
      break;
    case "pointsPerUnit":
      if (!reward.unitAmountYen || reward.unitAmountYen <= 0) issues.push(`${prefix}: unitAmountYen must be positive`);
      if (!reward.pointsPerUnit || reward.pointsPerUnit <= 0) issues.push(`${prefix}: pointsPerUnit must be positive`);
      if (!reward.pointProgramID) issues.push(`${prefix}: pointProgramID is required`);
      if (!reward.defaultPointValueYen || reward.defaultPointValueYen <= 0 || reward.defaultPointValueYen > 10) {
        issues.push(`${prefix}: defaultPointValueYen is invalid`);
      }
      break;
    case "fixedYen":
      if (reward.fixedYen === undefined || reward.fixedYen < 0) issues.push(`${prefix}: fixedYen is invalid`);
      break;
  }

  const { activeFrom, activeUntil } = rule.conditions;
  if (activeFrom && activeUntil && activeFrom > activeUntil) issues.push(`${prefix}: active date range is inverted`);
}

function assertOfficialWebURL(value: string, label: string, issues: string[]): void {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" && url.protocol !== "http:") {
      issues.push(`${label} must use HTTP or HTTPS`);
    }
  } catch {
    issues.push(`${label} is not a valid URL`);
  }
}
