# Patrol web tests (gate tool 6, TAG-82)

End-to-end tests of the Flutter web app in headless Chrome, driven by
[Patrol](https://patrol.leancode.co) 4.12 (patrol_cli 4.10.0) on the local
Firebase emulators.

| Test | What it checks |
| --- | --- |
| `admin_login_test.dart` | The fixture super admin signs in and reaches the dashboard. |
| `consuming_upload_test.dart` | A customer opens `/event/<id>`, uploads the synthetic receipt (1402 EGP), scans it, and picks a gift in each of the 3 chances of a consuming 500/350/200 ladder. The server ledger must record 3 gifts. |

## Run

```bash
dart pub global activate patrol_cli 4.10.0     # once
bash tool/ci/patrol_web.sh                     # every test here
bash tool/ci/patrol_web.sh patrol_test/admin_login_test.dart
HEADED=1 bash tool/ci/patrol_web.sh ...        # watch the browser
bash tool/ci/run_gate.sh --only patrol         # through the gate, with a summary
```

Needs Java 21 (Firestore emulator), Node 22 and the Flutter version in
`.fvmrc`. In CI the `patrol` job of `.github/workflows/gate.yml` runs this only
when the change touches the UI, the rules or these tests.

## Safety

- The app is built with `FIREBASE_EMULATOR=true` (project
  `demo-tashil-branch`, 127.0.0.1 only) and `SYNTHETIC_RECEIPT_FIXTURE=true`.
  Every test calls `assertEmulatorBuild()` first and stops on any other build.
- The receipt is the synthetic fixture, so Gemini is never called. Chrome
  also cannot resolve the Gemini hosts (`BLOCK_HOSTS` in `patrol_web.sh`).
- The campaign has WhatsApp notifications off and the emulators run with no
  Google credentials, so nothing reaches WAHA, `tashil-gift-dev` or
  `tashil-gift`.
- The fixture accounts in `support/emulator.dart` exist only inside the
  emulator. They are not secrets.

## Writing a test

- Select by the Arabic UI text. The app opens in Arabic whatever the browser
  locale is.
- Start a customer link with `startAppAt($, '/event/<id>')`, not by pushing
  a route, because the app picks the anonymous session from the address bar
  at start.
- A file picker opens only on a real click: `uploadReceipt` clicks through
  the semantics tree with Playwright and answers the chooser.
- `waitOrDump` fails with the texts on screen, which is what you need when a
  step lands on an unexpected screen.
