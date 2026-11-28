const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const { deadLinks } = require("../scripts/audit_linked_gifts");

test("finds links to missing gifts and says which a save re-points by name", () => {
  const event = { promotionalRules: [
    { id: "r1", linkedGifts: [{ giftId: "v25", giftName: "فواتشر 25" }, { giftId: "old50", giftName: "فواتشر 50" }, { giftId: "gone", giftName: "شنطة" }] },
    { id: "r2", linkedGiftId: "gone2", linkedGiftName: "x" },
  ] };
  const dead = deadLinks(event, new Set(["v25", "v50"]), new Map([["فواتشر 25", 1], ["فواتشر 50", 1]]));
  assert.deepStrictEqual(dead.map((d) => [d.giftId, d.fixableByName]), [["old50", true], ["gone", false], ["gone2", false]]);
});

test("the audit script never writes", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "scripts", "audit_linked_gifts.js"), "utf8");
  // Map#set on the two in-memory maps is the only .set( allowed.
  const code = src.replace(/\b(names|giftsBySlug)\.set\(/g, "");
  assert.doesNotMatch(code, /\.(set|update|delete|create|add|batch|runTransaction|bulkWriter)\(/);
});
