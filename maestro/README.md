# Maestro web flows (gate tool 5, TAG-82 PR 3)

Mac only. [Maestro web](https://docs.maestro.dev/get-started/supported-platform/web-browser)
is still Beta: Chromium only, locale fixed to `en-US`. It is **not installed**
on the Mac yet: installing it is Mohamed's decision, and
`tool/ci/maestro_web.sh` never installs it. Until then the gate reports tool 5
as "not set up here", which is not a pass.

| Folder | Where | What |
| --- | --- | --- |
| `emulator/` | local emulators (`demo-tashil-branch`) | The fixture admin signs in, sees the seeded campaign and opens its edit screen. |
| `dev/` | `https://tashil-gift-dev.web.app` | The same, read-only: sign in and open a campaign. No receipt, no gift, no save. |
| `support/seed_emulator.mjs` | local emulators | Seeds the fixture admin and campaign (127.0.0.1 only). |

The customer flow (synthetic receipt, a gift per chance, the receipt image in
Storage) is covered by Patrol in `patrol_test/` (tool 6), which also runs in CI.

## Run

```bash
bash tool/ci/maestro_web.sh emulator     # or: bash tool/ci/run_gate.sh --only maestro
bash tool/ci/maestro_web.sh dev          # by hand only, never in CI or the gate
```

`emulator` builds the app with `FIREBASE_EMULATOR=true`,
`SYNTHETIC_RECEIPT_FIXTURE=true` and `E2E_SEMANTICS=true`, serves it on
`127.0.0.1:7360`, and runs `maestro/emulator/` inside `emulators:exec` with
`firebase.patrol.json`. Needs Java 21, Node 22 and the Flutter version in
`.fvmrc`.

`dev` needs the account in the Mac's local environment, for example from a
file outside the repo that you `source` first:

```bash
export MAESTRO_DEV_ADMIN_EMAIL=...      # never in a flow, never committed
export MAESTRO_DEV_ADMIN_PASSWORD=...
```

## Safety

- `emulator` uses the same server-side lock as Patrol
  (`tool/ci/e2e_safety.sh`): `demo-*` only, no Google credentials, refuses to
  run while `functions/.secret.local` or `functions/.env.local` exists,
  `WAHA_BACKEND_URL` on `127.0.0.1`. After the run
  `tool/ci/emulator_log_check.py` fails it on any Gemini or WAHA call.
- `dev` checks that every flow in `dev/` opens `tashil-gift-dev.web.app` and
  takes no screenshot or recording. Maestro reads the `MAESTRO_*` account
  itself, the output is redacted, and Maestro's screenshots and logs go to a
  temp folder that is deleted after the run, because they show the login
  screen. Never upload them.
- The static guards (tool 3) scan `maestro/**`: a flow that opens
  `tashil-gift.web.app` (prod) fails the gate.

## Selectors

Select by `Semantics(identifier: ...)` (`id:` in a flow), not by Arabic text:
the ids are in `E2eIds` (`lib/core/services/e2e_semantics.dart`). Each flow
asserts `دخول الحساب` once, to prove the UI still opens in Arabic under
Maestro's `en-US` locale.

`E2E_SEMANTICS=true` calls `SemanticsBinding.instance.ensureSemantics()` in
`main()`, so Flutter builds the accessibility tree Maestro reads. Prod and dev
builds never set it. The hosted dev build is a normal build, so the `dev` flow
first presses Flutter's "Enable accessibility" button.

## Not verified yet

Maestro has not run on the Mac (not installed), so these are written against
the docs and still need a first run:

- that Maestro web matches `id:` to Flutter's `Semantics.identifier`
  (`flt-semantics-identifier` in the DOM);
- that the `dev` flow can press the hidden "Enable accessibility" button.
