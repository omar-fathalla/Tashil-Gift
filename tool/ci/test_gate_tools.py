"""Self-tests for the TAG-82 gate tools. Run: python3 -m unittest discover -s tool/ci -p 'test_*.py'"""
import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

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


if __name__ == "__main__":
    unittest.main()
