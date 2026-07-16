import assert from "node:assert/strict";
import test from "node:test";
import { isAllowedByRobots } from "../src/fetching.js";

test("robots policy uses the most specific matching rule", () => {
  const robots = `
    User-agent: *
    Disallow: /private/
    Allow: /private/public/
  `;
  assert.equal(isAllowedByRobots(robots, "/cards/basic"), true);
  assert.equal(isAllowedByRobots(robots, "/private/card"), false);
  assert.equal(isAllowedByRobots(robots, "/private/public/card"), true);
});

test("named bot policy takes precedence over wildcard", () => {
  const robots = `
    User-agent: *
    Allow: /

    User-agent: UseCardCatalogBot
    Disallow: /blocked/
  `;
  assert.equal(isAllowedByRobots(robots, "/blocked/card"), false);
});
