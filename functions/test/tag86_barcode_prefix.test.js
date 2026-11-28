// TAG-86: a truncated catalog barcode must not prefix-match other companies' barcodes.
const test = require("node:test");
const assert = require("node:assert/strict");
const { explicitMember, barcodePrefixVariant } = require("../consuming_spend_ladder");

const knorrRule = { selectedBarcodes: ["622115510", "6221155146656"], selectedProductNames: [], requiredBrands: [] };

test("9-digit catalog code does not swallow a Dove barcode", () => {
  assert.equal(explicitMember({ barcode: "6221155101204", name: "دوف كريم بيوتي" }, knorrRule), false);
});

test("exact barcode still matches", () => {
  assert.equal(explicitMember({ barcode: "6221155146656", name: "x" }, knorrRule), true);
});

test("12/13-digit POS variation still matches", () => {
  assert.equal(barcodePrefixVariant("622300066001", "6223000660010"), true);
  assert.equal(barcodePrefixVariant("6223000660010", "622300066001"), true);
});

test("short or far-apart codes never prefix-match", () => {
  assert.equal(barcodePrefixVariant("6221155101204", "622115510"), false);
  assert.equal(barcodePrefixVariant("62211551012", "6221155101204"), false);
  assert.equal(barcodePrefixVariant("", "6221155101204"), false);
});
