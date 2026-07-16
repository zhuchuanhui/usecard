import assert from "node:assert/strict";
import test from "node:test";
import type { CardCatalog } from "../src/schema.js";
import { CatalogValidationError, validateCatalog } from "../src/validation.js";

const validCatalog = (): CardCatalog => ({
  schemaVersion: 1,
  version: "test",
  generatedAt: "2026-07-16T00:00:00Z",
  products: [
    {
      id: "example",
      issuerID: "issuer",
      issuerName: "Issuer",
      name: "Example Card",
      networks: ["visa"],
      annualFeeYen: 0,
      applicationStatus: "open",
      applicationURL: "https://example.com/card",
      eligibilityNote: "",
      pointProgramID: "example-point",
      benefitRules: [
        {
          id: "example-base",
          title: "Base",
          stackingGroup: "base",
          conditions: { merchantIDs: [], categoryIDs: [], paymentMethods: [], channels: [], eligibleDaysOfMonth: [] },
          reward: {
            kind: "pointsPerUnit",
            unitAmountYen: 200,
            pointsPerUnit: 1,
            pointProgramID: "example-point",
            defaultPointValueYen: 1
          },
          source: {
            url: "https://example.com/card",
            observedAt: "2026-07-16T00:00:00Z",
            contentHash: "hash",
            freshness: "fresh"
          }
        }
      ],
      sources: [
        {
          url: "https://example.com/card",
          observedAt: "2026-07-16T00:00:00Z",
          contentHash: "hash",
          freshness: "fresh"
        }
      ]
    }
  ]
});

test("valid catalog passes", () => {
  assert.doesNotThrow(() => validateCatalog(validCatalog()));
});

test("duplicate product IDs are rejected", () => {
  const catalog = validCatalog();
  catalog.products.push(structuredClone(catalog.products[0]!));
  assert.throws(() => validateCatalog(catalog), CatalogValidationError);
});

test("implausible reward rate is rejected", () => {
  const catalog = validCatalog();
  catalog.products[0]!.benefitRules[0]!.reward = {
    kind: "cashbackRate",
    ratePercent: 100
  };
  assert.throws(() => validateCatalog(catalog), /cashback rate/);
});
