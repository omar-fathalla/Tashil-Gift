# Branch identity fixture

Local emulators only. Project `demo-tashil-branch` is rejected by production Firebase. Do not deploy this build and do not point it at `tashil-gift`.

## Start

```bash
npx -y firebase-tools@latest emulators:start --project demo-tashil-branch --only auth,firestore
node tool/seed_branch_identity_emulator.mjs
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 7357 --dart-define=FIREBASE_EMULATOR=true
```

Auth is `127.0.0.1:9099`. Firestore is `127.0.0.1:8080`. The functions client is pinned to `127.0.0.1:5001` and the functions emulator is not started, so a claim cannot reach `cloudfunctions.net`. The refused local call is ignored only in this emulator build, and a signed-in staff user then writes stock on Firestore `8080`. A production `internal` error does not take that path. Storage is not required.

The header badge still says `Production (Firebase)`. That string is the version label. The red line `Running in emulator mode` is the backend. On startup the emulator build clears the browser Auth database so a saved session is not refreshed at `identitytoolkit.googleapis.com`.

Sign in as `fixture-admin@demo.local` / `fixture-pass-234`. That user exists only in the Auth emulator.

## Gift route

`http://127.0.0.1:7357/fixture-gift`

Receipt `a-code-243`, campaign `fixture-order-a`, branch id `fathalla_243`. The screen is given the short Tanta name on purpose. The id must win.

| Gift | Id | Branch | Remaining before | Remaining after one claim |
| --- | --- | --- | --- | --- |
| هدية أوتليت طنطا | `gift-outlet-243` | `fathalla_243` | 7 | 6 |
| هدية طنطا القصيرة | `gift-short-231` | `fathalla_231` | 3 | 3 |

The screen claims as soon as it opens. The gift title is `هدية أوتليت طنطا`. After one open, its remaining is 6 and the short gift stays at 3. Opening the route again decrements again. Reseed before another claim. WhatsApp is off.

Sibling id `fathalla_231`, partial name `طنطا اوت`, unknown `999`, and foreign id `gomla_418` do not select either gift. `test/branch_gift_identity_test.dart` asserts that.

## Preserved id `gomla_418`

The invoice card does not show the raw id. It shows the stored name `فرع طنطا (الغربية)` and must not change it to the outlet. The seed reads `receipts_transactions/a-foreign-id` and fails if `branch_id` is not `gomla_418`. The same check is in `test/branch_gift_identity_test.dart`.

```bash
curl -s -H 'Authorization: Bearer owner' \
  'http://127.0.0.1:8080/v1/projects/demo-tashil-branch/databases/(default)/documents/receipts_transactions/a-foreign-id'
```

`Authorization: Bearer owner` is the local emulator rules bypass, not a production credential.

## CSV and chart

These are the current semantics, already present at `39ede8ee`. This fixture does not change them.

- The invoice list and the KPI use the branch filter. Three outlet rows at 185.5 each are 556.5.
- The export button in the filter toolbar calls `_exportInvoicesToCsv(allInvoices)`. That is all 9 seeded receipts, not the filtered 3. The header export uses the filtered list.
- The branch chart ignores the selected branch. It draws one column per distinct canonical label in the campaign period. This seed has five of those labels, so the chart has five columns.

Exported branch text is the canonical label already checked on the cards.
