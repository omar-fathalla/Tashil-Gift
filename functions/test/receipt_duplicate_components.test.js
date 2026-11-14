const test = require("node:test");
const assert = require("node:assert");
const {
  checkReceiptDuplicateHandler,
  componentReceiptNumbers,
  storedComponents,
} = require("../receipt_duplicate_check");

function match(d, [field, op, value]) {
  const v = d[field];
  if (op === "==") return v === value;
  if (op === "in") return value.includes(v);
  if (op === ">") return typeof v === "number" && v > value;
  if (op === "array-contains-any") return Array.isArray(v) && v.some((x) => value.includes(x));
  throw new Error(`unsupported op ${op}`);
}

function fakeDb(receipts, event = { companySlug: "583", allowComplementaryReceipts: true }) {
  const query = (filters) => ({
    where: (f, op, v) => query(filters.concat([[f, op, v]])),
    limit: () => query(filters),
    get: async () => ({
      docs: Object.entries(receipts)
        .filter(([, d]) => filters.every((f) => match(d, f)))
        .map(([id, d]) => ({ id, data: () => d })),
    }),
  });
  return {
    collection: (name) => {
      if (name === "events") return { doc: () => ({ get: async () => ({ exists: true, data: () => event }) }) };
      if (name === "rateLimits") return { doc: () => ({}) };
      return {
        doc: (id) => ({ get: async () => ({ exists: !!receipts[id], data: () => receipts[id] }) }),
        ...query([]),
      };
    },
    runTransaction: async (fn) => fn({ get: async () => ({ exists: false }), set: () => {} }),
  };
}

const accepted = (extra) => Object.assign({ status: "accepted", is_valid: true, campaignId: "E", companySlug: "583" }, extra);
const req = (receiptNumber) => ({
  app: {}, auth: { uid: "u" }, rawRequest: { headers: {} },
  data: { receiptNumber, companySlug: "583", campaignId: "E" },
});

test("componentReceiptNumbers splits combined uploads and strips spaces", () => {
  assert.deepStrictEqual(componentReceiptNumbers("64/6/241/250926 + 109/8/241/250926"), ["64/6/241/250926", "109/8/241/250926"]);
  assert.deepStrictEqual(componentReceiptNumbers("64/6/241/250926"), ["64/6/241/250926"]);
  assert.deepStrictEqual(componentReceiptNumbers(""), []);
});

test("storedComponents prefers the array and falls back to the joined string", () => {
  assert.deepStrictEqual(storedComponents({ receipt_number: "A + B", component_receipt_numbers: ["A", "B"] }), ["A", "B"]);
  assert.deepStrictEqual(storedComponents({ receipt_number: "A + B" }), ["A", "B"]);
  assert.deepStrictEqual(storedComponents({ receipt_number: "A + B", component_receipt_numbers: [] }), ["A", "B"]);
});

test("combined first, then one of its receipts alone -> duplicate", async () => {
  const db = fakeDb({ c1: accepted({ receipt_number: "64/6/241 + 109/8/241", component_receipt_numbers: ["64/6/241", "109/8/241"], parts_count: 2 }) });
  const r = await checkReceiptDuplicateHandler(db, req("109/8/241"));
  assert.strictEqual(r.duplicate, true);
});

test("single first, then a combined upload containing it -> duplicate", async () => {
  const db = fakeDb({ s1: accepted({ receipt_number: "64/6/241", component_receipt_numbers: ["64/6/241"] }) });
  const r = await checkReceiptDuplicateHandler(db, req("77/1/241 + 64/6/241"));
  assert.strictEqual(r.duplicate, true);
});

test("legacy single record without the array still blocks a combined upload", async () => {
  const db = fakeDb({ s1: accepted({ receipt_number: "64/6/241" }) });
  const r = await checkReceiptDuplicateHandler(db, req("64/6/241 + 77/1/241"));
  assert.strictEqual(r.duplicate, true);
});

test("legacy combined record (joined string only) blocks each of its receipts", async () => {
  const db = fakeDb({ c1: accepted({ receipt_number: "64/6/241 + 109/8/241", parts_count: 2 }) });
  assert.strictEqual((await checkReceiptDuplicateHandler(db, req("64/6/241"))).duplicate, true);
  assert.strictEqual((await checkReceiptDuplicateHandler(db, req("109/8/241"))).duplicate, true);
  assert.strictEqual((await checkReceiptDuplicateHandler(db, req("109/8/241 + 5/5/241"))).duplicate, true);
  assert.strictEqual((await checkReceiptDuplicateHandler(db, req("5/5/241"))).duplicate, false);
});

test("legacy combined scan is skipped where combining was never allowed", async () => {
  const db = fakeDb({ c1: accepted({ receipt_number: "64/6/241 + 109/8/241", parts_count: 2 }) },
    { companySlug: "583", allowComplementaryReceipts: false });
  assert.strictEqual((await checkReceiptDuplicateHandler(db, req("64/6/241"))).duplicate, false);
});

test("rejected and other-campaign records do not block", async () => {
  const db = fakeDb({
    r1: { status: "rejected", is_valid: false, campaignId: "E", companySlug: "583", receipt_number: "64/6/241", component_receipt_numbers: ["64/6/241"] },
    o1: accepted({ campaignId: "OTHER", receipt_number: "109/8/241", component_receipt_numbers: ["109/8/241"] }),
  });
  assert.strictEqual((await checkReceiptDuplicateHandler(db, req("64/6/241 + 109/8/241"))).duplicate, false);
});

test("unrelated receipts are not duplicates", async () => {
  const db = fakeDb({ s1: accepted({ receipt_number: "64/6/241", component_receipt_numbers: ["64/6/241"] }) });
  assert.strictEqual((await checkReceiptDuplicateHandler(db, req("65/6/241 + 66/6/241"))).duplicate, false);
});
