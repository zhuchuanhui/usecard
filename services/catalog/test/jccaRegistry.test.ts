import assert from "node:assert/strict";
import test from "node:test";
import { parseJCCAIssuerRegistry } from "../src/jccaRegistry.js";

test("JCCA rows become issuer coverage records", () => {
  const html = `
    <table><tbody>
      <tr><th><a href="https://example.com/">株式会社サンプルカード</a></th><td>東京都</td></tr>
      <tr><th>リンクなしカード株式会社</th><td>大阪府</td></tr>
    </tbody></table>`;
  const registry = parseJCCAIssuerRegistry(
    html,
    "2026-07-16T00:00:00Z",
    new Set(["株式会社サンプルカード"])
  );

  assert.equal(registry.length, 2);
  assert.equal(registry.find((entry) => entry.name.includes("サンプル"))?.status, "tracked");
  assert.equal(registry.find((entry) => entry.name.includes("リンクなし"))?.status, "needsProductAdapter");
});
