# Deployment, Git Push & Firebase Authorization Standard

## 🛑 MANDATORY PERMISSION RULE
1. **NEVER autonomously push to GitHub or deploy to Firebase**:
   - The agent MUST NEVER execute `git push` or `firebase deploy` (`npx -y firebase-tools@latest deploy ...`) automatically or as an unprompted final step of a task.
   - Code edits, builds (`flutter build`), and tests (`flutter test`) may be run autonomously to verify correctness, but **REMOTE PUBLISHING / DEPLOYING IS STRICTLY PROHIBITED** without explicit, affirmative authorization from the user in the active chat turn (e.g. "ارفع على جيت هب", "اعمل deploy", "ارفع للفايربيز", "انشر التحديث").

2. **AUTOMATED VERSION & BUILD INCREMENT ON DEPLOY**:
   - Whenever the user explicitly authorizes/requests a deployment or push:
     - Increment `patch` and `buildNumber` in `lib/core/constants/app_version_config.dart`.
     - Update `pubspec.yaml` `version: <major>.<minor>.<patch>+<buildNumber>`.
     - Update `releaseDate` in `app_version_config.dart`.
     - Build release (`flutter build web --release`).

3. **MANDATORY Firebase Admin Console Link Output**:
   - Whenever the user explicitly authorizes/requests a deployment or push to Firebase/GitHub, the agent MUST ALWAYS provide:
     - 📦 **New Release**: `vX.Y.Z (Build #N)`
     - 🔗 **Firebase Admin Console**: `https://console.firebase.google.com/project/tashil-gift/overview`
     - 🌐 **Live Web Application**: `https://tashil-gift.web.app`
