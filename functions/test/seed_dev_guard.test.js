const test = require("node:test");
const assert = require("node:assert");
const { resolveSeedTarget, buildSeedData, assertFakeOnly, SeedRefused } = require("../../tool/seed_dev_lib");

const refused = (opts, re) => assert.throws(() => resolveSeedTarget(opts), (e) => e instanceof SeedRefused && re.test(e.message));
const EMU = { FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080", FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9099", FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9199" };

test("refuses production and any non-dev project", () => {
  refused({ argv: [] }, /Missing --project/);
  refused({ argv: ["--project", "tashil-gift", "--confirm", "tashil-gift"] }, /PRODUCTION/);
  refused({ argv: ["--project=tashil-gift"] }, /PRODUCTION/);
  refused({ argv: ["--project", "tashil-gift-prod"] }, /unknown project/);
  refused({ argv: ["--project", "my-app"] }, /unknown project/);
});

test("refuses when env or credentials point somewhere else", () => {
  refused({ argv: ["--project", "tashil-gift-dev", "--confirm", "tashil-gift-dev"], env: { GCLOUD_PROJECT: "tashil-gift" } }, /tashil-gift\./);
  refused({ argv: ["--project", "tashil-gift-dev", "--confirm", "tashil-gift-dev"], credentialsProjectId: "tashil-gift" }, /credentials point at tashil-gift/);
});

test("tashil-gift-dev needs --confirm and no emulator vars", () => {
  refused({ argv: ["--project", "tashil-gift-dev"] }, /--confirm tashil-gift-dev/);
  refused({ argv: ["--project", "tashil-gift-dev", "--confirm", "tashil-gift"] }, /--confirm tashil-gift-dev/);
  refused({ argv: ["--project", "tashil-gift-dev", "--confirm", "tashil-gift-dev"], env: EMU }, /emulator variables/);
  assert.deepStrictEqual(
    resolveSeedTarget({ argv: ["--project", "tashil-gift-dev", "--confirm", "tashil-gift-dev"], credentialsProjectId: "tashil-gift-dev" }),
    { projectId: "tashil-gift-dev", emulator: false, dryRun: false });
  assert.strictEqual(resolveSeedTarget({ argv: ["--project", "tashil-gift-dev", "--dry-run"] }).dryRun, true);
});

test("demo-* only with localhost emulators", () => {
  refused({ argv: ["--project", "demo-tashil-dev"] }, /emulator project/);
  refused({ argv: ["--project", "demo-tashil-dev"], env: { ...EMU, FIRESTORE_EMULATOR_HOST: "10.0.0.5:8080" } }, /not a localhost/);
  assert.strictEqual(resolveSeedTarget({ argv: ["--project", "demo-tashil-dev"], env: EMU }).emulator, true);
});

test("seed data is fake only and idempotent (fixed ids)", () => {
  const a = buildSeedData(1_800_000_000_000);
  const b = buildSeedData(1_800_000_000_000);
  assert.ok(assertFakeOnly(a));
  assert.deepStrictEqual(a.events.map((e) => e.id), b.events.map((e) => e.id));
  assert.ok(a.events.some((e) => e.isActive && e.startDate.getTime() < 1_800_000_000_000));
  assert.ok(a.events.some((e) => !e.isActive));
  assert.throws(() => assertFakeOnly({ ...a, users: [{ email: "someone@gmail.com" }] }), /non-example/);
  assert.throws(() => assertFakeOnly({ ...a, note: "01234567890" }), /real-looking phone/);
});
