"""Self-tests for the TAG-82 gate tools. Run: python3 -m unittest discover -s tool/ci -p 'test_*.py'"""
import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import emulator_log_check  # noqa: E402
import gate_buckets  # noqa: E402
import static_guards  # noqa: E402

FAKE_KEY = "AIza" + "B" * 35  # built at runtime so this file holds no key literal


def guard(files: dict[str, str], allow: str = "") -> int:
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        for rel, text in files.items():
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text(text, encoding="utf-8")
        al = root / "allow.txt"
        al.write_text(allow, encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            return static_guards.run(root, al, sorted(files))


class StaticGuardsTest(unittest.TestCase):
    # The three planted cases from the TAG-82 review.
    def test_firebase_deploy_without_project_fails(self):
        self.assertEqual(guard({"tool/dev/x.sh": "firebase deploy --only hosting\n"}), 1)

    def test_prod_project_in_seed_script_fails(self):
        self.assertEqual(guard({"tool/seed_x.js": 'initializeApp({ projectId: "tashil-gift" });\n'}), 1)

    def test_fake_api_key_fails(self):
        self.assertEqual(guard({"lib/core/services/x.dart": f"const k = '{FAKE_KEY}';\n"}), 1)

    def test_api_key_in_firebase_options_is_allowed(self):
        self.assertEqual(guard({"lib/firebase_options_dev.dart": f"apiKey: '{FAKE_KEY}',\n"}), 0)

    def test_dev_and_demo_projects_pass(self):
        files = {
            "tool/a.sh": "firebase deploy --project tashil-gift-dev --only hosting\n",
            "tool/b.sh": 'npx -y "firebase-tools@15.37.0" emulators:exec --project demo-tashil "x"\n',
            "rules-tests/package.json": '{"scripts":{"test":"firebase emulators:exec --project demo-tashil-gift x"}}\n',
        }
        self.assertEqual(guard(files), 0)

    def test_multiline_command_and_variable(self):
        ok = 'PROJECT=tashil-gift-dev\nnpx -y "firebase-tools@${V}" deploy \\\n  --project "$PROJECT" \\\n  --only hosting\n'
        self.assertEqual(guard({"tool/dev/d.sh": ok}), 0)
        bad = 'PROJECT="${1:-tashil-gift}"\nfirebase deploy --project "$PROJECT"\n'
        self.assertEqual(guard({"tool/dev/d.sh": bad}), 1)
        unset = 'firebase deploy --project "$WHO"\n'
        self.assertEqual(guard({"tool/dev/d.sh": unset}), 1)

    def test_comments_and_step_names_are_ignored(self):
        files = {
            "tool/a.sh": "# firebase deploy to tashil-gift happens elsewhere\n",
            ".github/workflows/w.yml": "      - name: firebase deploy (hosting)\n",
        }
        self.assertEqual(guard(files), 0)

    def test_dev_url_is_not_prod(self):
        self.assertEqual(guard({"tool/a.py": 'u = "https://tashil-gift-dev.web.app"\n'}), 0)

    def test_allowlist(self):
        files = {"tool/seed_x.js": 'initializeApp({ projectId: "tashil-gift" });\n'}
        rule = 'prod-project | tool/seed_x.js | projectId: "tashil-gift" | test reason\n'
        self.assertEqual(guard(files, rule), 0)
        other = 'prod-project | tool/other.js | * | wrong file\n'
        self.assertEqual(guard(files, other), 1)

    def test_e2e_flow_on_prod_url_fails(self):
        # PR 3 (Maestro) and Patrol flows are scanned too.
        flow = "appId: web\nurl: https://tashil-gift.web.app\n---\n- launchApp\n"
        self.assertEqual(guard({"maestro/login.yaml": flow}), 1)
        self.assertEqual(guard({"patrol_test/x_test.dart": "const u = 'https://tashil-gift.web.app';\n"}), 1)

    def test_new_prod_line_in_render_script_fails(self):
        # The allowlist names the exact lines, so a new prod line is caught.
        root = Path(__file__).resolve().parents[2]
        rel = "tool/dev/render_firebase_dev_json.py"
        text = (root / rel).read_text(encoding="utf-8") + 'EXTRA = "https://tashil-gift.web.app"\n'
        allow = (root / "tool/ci/guards_allowlist.txt").read_text(encoding="utf-8")
        self.assertEqual(guard({rel: text}, allow), 1)
        self.assertEqual(guard({rel: (root / rel).read_text(encoding="utf-8")}, allow), 0)

    def test_app_code_may_name_prod(self):
        # lib/ and test/ hold the real prod Firebase options and URLs.
        self.assertEqual(guard({"lib/app_env.dart": "const id = 'tashil-gift';\n"}), 0)

    def test_repo_is_clean(self):
        root = Path(__file__).resolve().parents[2]
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = static_guards.run(root, root / "tool/ci/guards_allowlist.txt", None)
        self.assertEqual(rc, 0, buf.getvalue())


class BucketsTest(unittest.TestCase):
    def tools(self, *files):
        return gate_buckets.classify(list(files))[1]

    def test_docs_only_runs_nothing(self):
        self.assertEqual(self.tools("docs/README.md", "AGENTS.md", "docs/07-dev-setup.md"), [])

    def test_rules_runs_tool_4_rules(self):
        self.assertEqual(self.tools("firestore.rules"), ["rules", "patrol"])
        self.assertNotIn("analyze", self.tools("storage.rules"))

    def test_functions(self):
        self.assertEqual(self.tools("functions/index.js"), ["functions"])

    def test_screen_change_runs_e2e(self):
        t = self.tools("lib/features/admin/presentation/screens/x.dart")
        self.assertEqual(t, ["analyze", "flutter_test", "patrol", "maestro"])

    def test_plain_dart(self):
        self.assertEqual(self.tools("lib/core/utils/x.dart"), ["analyze", "flutter_test"])

    def test_main_services_firebase_json_are_ui(self):
        for f in ("lib/main.dart", "lib/core/services/a.dart", "firebase.json", "assets/x.png", "web/index.html"):
            self.assertIn("patrol", self.tools(f), f)
        self.assertIn("guards", self.tools("firebase.json"))

    def test_toolchain(self):
        for f in ("pubspec.yaml", "pubspec.lock", ".fvmrc", "analysis_options.yaml", "tool/ci/known_failing_tests.txt"):
            t = self.tools(f)
            self.assertIn("analyze", t, f)
            self.assertIn("flutter_test", t, f)

    def test_rules_tests_folder_is_rules(self):
        self.assertIn("rules", self.tools("rules-tests/firestore-storage.test.js"))

    def test_scripts_run_guards(self):
        self.assertEqual(self.tools(".github/workflows/gate.yml"), ["guards"])

    def test_unclassified_runs_1_to_4(self):
        self.assertEqual(self.tools("android/app/build.gradle"), gate_buckets.ALL_FAST)


class EmulatorLogCheckTest(unittest.TestCase):
    def test_clean_log_passes(self):
        log = 'i  functions: Beginning execution of "us-central1-checkReceiptDuplicate"\n'
        self.assertEqual(emulator_log_check.scan(log), [])

    def test_gemini_call_fails(self):
        log = 'i  functions: Beginning execution of "us-central1-geminiGenerate"\n'
        self.assertEqual(len(emulator_log_check.scan(log)), 1)

    def test_whatsapp_call_fails(self):
        for fn in ("sendWinnerWhatsApp", "wahaProxy", "analyzeReceipt"):
            log = f'i  functions: Beginning execution of "us-central1-{fn}"\n'
            self.assertEqual(len(emulator_log_check.scan(log)), 1, fn)

    def test_forbidden_host_fails(self):
        self.assertEqual(len(emulator_log_check.scan("POST https://waha.sw-point.com/api/sendText\n")), 1)
        self.assertEqual(len(emulator_log_check.scan("generativelanguage.googleapis.com timeout\n")), 1)

    def test_patrol_files_run_patrol(self):
        for f in ("firebase.patrol.json", "functions/.env.demo-tashil-branch", "tool/ci/patrol_web.sh"):
            self.assertIn("patrol", gate_buckets.classify([f])[1], f)


class MaestroBucketsTest(unittest.TestCase):
    def test_maestro_files_run_maestro(self):
        for f in ("maestro/emulator/admin_open_campaign.yaml", "maestro/dev/admin_open_campaign.yaml",
                  "maestro/support/seed_emulator.mjs", "tool/ci/maestro_web.sh", "tool/ci/e2e_safety.sh"):
            self.assertIn("maestro", gate_buckets.classify([f])[1], f)

    def test_e2e_safety_runs_patrol_too(self):
        self.assertIn("patrol", gate_buckets.classify(["tool/ci/e2e_safety.sh"])[1])


REPO = Path(__file__).resolve().parents[2]


class E2eRefusalTest(unittest.TestCase):
    """patrol_web.sh and maestro_web.sh stop before any build or emulator when
    the functions emulator could load real Gemini/WAHA settings."""

    def run_script(self, script: str, planted: str | None, waha: str = "http://127.0.0.1:9", args=()):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "tool/ci").mkdir(parents=True)
            for f in ("e2e_safety.sh", script):
                shutil.copy(REPO / "tool/ci" / f, root / "tool/ci" / f)
            (root / "functions").mkdir()
            (root / "functions/.env.demo-tashil-branch").write_text(f"WAHA_BACKEND_URL={waha}\n")
            if planted:
                (root / "functions" / planted).write_text("X=1\n")
            env = {k: v for k, v in os.environ.items() if k != "CI"}
            env["PATH"] = "/usr/bin:/bin"  # no flutter, patrol, maestro or npx
            p = subprocess.run(["bash", f"tool/ci/{script}", *args], cwd=root, env=env,
                               capture_output=True, text=True, timeout=60)
            return p.returncode, p.stdout + p.stderr

    def test_secret_local_is_refused(self):
        for script in ("patrol_web.sh", "maestro_web.sh"):
            rc, out = self.run_script(script, ".secret.local")
            self.assertEqual(rc, 1, out)
            self.assertIn(".secret.local exists", out)

    def test_env_local_is_refused(self):
        for script in ("patrol_web.sh", "maestro_web.sh"):
            rc, out = self.run_script(script, ".env.local")
            self.assertEqual(rc, 1, out)
            self.assertIn(".env.local exists", out)

    def test_real_waha_url_is_refused(self):
        rc, out = self.run_script("maestro_web.sh", None, waha="https://waha.example")
        self.assertEqual(rc, 1, out)
        self.assertIn("WAHA_BACKEND_URL", out)

    def test_maestro_off_the_mac_is_not_set_up(self):
        # Clean tree: the safety checks pass, then Maestro reports "not set up"
        # (exit 3) on Linux or when it is not installed. It never installs it.
        rc, out = self.run_script("maestro_web.sh", None)
        self.assertEqual(rc, 3, out)

    def test_maestro_dev_needs_local_account(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "tool/ci").mkdir(parents=True)
            shutil.copy(REPO / "tool/ci/maestro_web.sh", root / "tool/ci/maestro_web.sh")
            shutil.copytree(REPO / "maestro/dev", root / "maestro/dev")
            env = {k: v for k, v in os.environ.items() if not k.startswith("MAESTRO_DEV_") and k != "CI"}
            p = subprocess.run(["bash", "tool/ci/maestro_web.sh", "dev"], cwd=root, env=env,
                               capture_output=True, text=True, timeout=60)
            self.assertEqual(p.returncode, 1, p.stderr)
            self.assertIn("MAESTRO_DEV_ADMIN_EMAIL", p.stderr)
            # A dev flow that opens another site, or takes a screenshot, is refused.
            flow = root / "maestro/dev/admin_open_campaign.yaml"
            flow.write_text(flow.read_text().replace("tashil-gift-dev.web.app", "example.com"))
            p = subprocess.run(["bash", "tool/ci/maestro_web.sh", "dev"], cwd=root, env=env,
                               capture_output=True, text=True, timeout=60)
            self.assertEqual(p.returncode, 1, p.stderr)
            self.assertIn("must open", p.stderr)


if __name__ == "__main__":
    unittest.main()
