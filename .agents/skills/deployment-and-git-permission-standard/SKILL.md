---
name: deployment-and-git-permission-standard
description: Mandatory rule and workflow governing deployments to Firebase Hosting, Cloud Functions, and git pushes to GitHub. Enforces explicit user authorization in chat before running any deploy or push command, automated version & build incrementation, and mandates outputting the Firebase Admin Console URL upon completion.
version: 1.1.0
---

# Deployment, Git Push & Firebase Authorization Standard

This skill defines the **mandatory permission protocol** for publishing code changes to remote environments (GitHub and Firebase) and maintaining the version and build counter.

Whenever building, modifying, testing, or committing code in this workspace, you **MUST** strictly adhere to this standard.

---

## 1. Core Principles

1. **Explicit Chat Authorization Only**:
   - The agent is **strictly prohibited** from running `git push` or `firebase deploy` (`npx -y firebase-tools@latest deploy ...`) automatically, autonomously, or as an unprompted final step of any implementation plan or bugfix.
   - Code edits, local builds (`flutter build web`), and unit tests (`flutter test`) may be executed autonomously to guarantee code correctness.
   - However, **remote publishing / production deployments require explicit, affirmative instructions from the user in the current chat turn** (e.g. *"ارفع على جيت هب"*, *"اعمل deploy"*, *"ارفع للفايربيز"*, *"انشر التحديث"*).

2. **Automated Version & Build Counter Increment**:
   - On every authorized deployment or push, the agent **MUST**:
     1. Increment `patch` and `buildNumber` in `lib/core/constants/app_version_config.dart`.
     2. Update `pubspec.yaml` `version: <major>.<minor>.<patch>+<buildNumber>`.
     3. Update `releaseDate` to the current date.
     4. Build the web release (`flutter build web --release`).

3. **Always Provide Firebase Admin Console Link**:
   - Whenever the user authorizes or requests a deployment or push to Firebase or GitHub, the agent **MUST ALWAYS** provide the direct Firebase Admin Console URL alongside the live production URL and version tag in its final response:
     - 📦 **Current Version**: `vX.Y.Z (Build #N)`
     - 🔗 **Firebase Admin Console**: `https://console.firebase.google.com/project/tashil-gift/overview`
     - 🌐 **Live Web Application**: `https://tashil-gift.web.app`

---

## 2. Standard Interaction Flow

### A. When completing normal tasks (without explicit deploy request from user):
1. Execute code changes.
2. Run `flutter analyze` & `flutter test` to ensure 100% test passing.
3. Inform the user that the changes have been tested and verified locally.
4. **DO NOT** run `firebase deploy` or `git push`.
5. Ask the user if they would like to deploy/push the changes.

### B. When the user explicitly requests deployment (e.g. "ارفع على الفايربيز و جيت هب"):
1. Increment version & build in `lib/core/constants/app_version_config.dart` and `pubspec.yaml`.
2. Build the production release: `flutter build web --release`.
3. Deploy to Firebase: `npx -y firebase-tools@latest deploy --only hosting`.
4. If requested, commit and push to GitHub: `git add . && git commit -m "..." && git push origin main`.
5. Output the direct links:
   - 📦 **Release Stamp**: `vX.Y.Z (Build #N)`
   - 🔗 **Firebase Console Admin**: `https://console.firebase.google.com/project/tashil-gift/overview`
   - 🌐 **Live Production URL**: `https://tashil-gift.web.app`
