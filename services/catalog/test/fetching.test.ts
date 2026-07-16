import assert from "node:assert/strict";
import test from "node:test";
import { decodeHTML } from "../src/fetching.js";

test("HTML declared as Shift_JIS is decoded before extraction", () => {
  const bytes = new Uint8Array([
    ...Buffer.from('<meta charset="Shift_JIS"><title>', "ascii"),
    0x83, 0x65, 0x83, 0x58, 0x83, 0x67,
    ...Buffer.from("</title>", "ascii")
  ]);

  assert.equal(decodeHTML(bytes, "text/html"), '<meta charset="Shift_JIS"><title>テスト</title>');
});

test("HTTP charset has priority over a missing document declaration", () => {
  const bytes = new TextEncoder().encode("楽天カード");
  assert.equal(decodeHTML(bytes, "text/html; charset=utf-8"), "楽天カード");
});
