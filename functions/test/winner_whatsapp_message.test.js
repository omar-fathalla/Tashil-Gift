const test = require("node:test");
const assert = require("node:assert");
const { buildMessage, DEFAULT_TEMPLATE } = require("../winner_whatsapp");

const f = { customerName: "أحمد", phone: "01000000000", chain: "باندا", branch: "المعادي",
  company: "شركة", campaign: "حملة", prize: "كوبون 50 جنيه", serials: [], receipt: "123", claimDate: "2026/10/31" };

test("default message has no prize name and congratulates by name", () => {
  const m = buildMessage("", f);
  assert.ok(!m.includes("كوبون 50 جنيه"));
  assert.ok(!m.includes("{prize_name}"));
  assert.ok(m.includes("ألف مبروك يا أحمد! كسبت معانا"));
  assert.ok(!DEFAULT_TEMPLATE.includes("{prize_name}"));
});

test("old saved template (Firestore) still never shows the prize", () => {
  const old = "🎉 ألف مبروك يا {customer_name}!\nتهنئتكم بالفوز بـ:\n✨ {prize_name} ✨\nجائزتك: {prize_name}\n• رقم الفاتورة: {receipt_number}";
  const m = buildMessage(old, f);
  assert.ok(!m.includes("كوبون"));
  assert.ok(!m.includes("✨  ✨"));
  assert.ok(m.includes("تهنئتكم بالفوز معانا! 🎉"));
  assert.ok(m.includes("رقم الفاتورة: 123"));
});
