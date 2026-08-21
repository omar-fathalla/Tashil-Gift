# GEMINI.md — Tashil Gift Workspace Guidelines

## 🛑 MANDATORY RULES

### 1. Deployment & Git Push Permission Rule
- **NEVER autonomously push to GitHub or deploy to Firebase**:
  - The agent MUST NEVER execute `git push` or `firebase deploy` (`npx -y firebase-tools@latest deploy ...`) automatically or as an unprompted final step of a task.
  - Verification with `flutter analyze` and `flutter test` can and should be done locally.
  - Remote publishing / deployments to Firebase or pushing to GitHub are **STRICTLY FORBIDDEN** unless the user gives an explicit affirmative instruction in the active chat turn (e.g., *"ارفع على جيت هب"*, *"اعمل deploy"*, *"ارفع للفايربيز"*, *"انشر التحديث"*).

### 2. Automated Version & Build Counter Increment Rule
- Whenever the user explicitly authorizes a deployment/push:
  - The agent MUST automatically increment the `patch` version (e.g. `2.0.1` -> `2.0.2`) and `buildNumber` (e.g. `56` -> `57`) in [app_version_config.dart](file:///Users/fathalla/Development/Tashil%20Gift/lib/core/constants/app_version_config.dart).
  - The agent MUST synchronize [pubspec.yaml](file:///Users/fathalla/Development/Tashil%20Gift/pubspec.yaml) `version: <major>.<minor>.<patch>+<buildNumber>`.
  - The Header badge (`SwitchPointHeader`) will automatically reflect the new version across mobile and desktop.

### 3. Firebase Admin Console Link Requirement
- In every response following an authorized deployment to Firebase or push to GitHub, the agent MUST ALWAYS include:
  - 📦 **Current Version & Build**: e.g. `v2.0.1 (Build #56)`
  - 🔗 **Firebase Admin Console**: `https://console.firebase.google.com/project/tashil-gift/overview`
  - 🌐 **Live Web Application**: `https://tashil-gift.web.app`

### 4. Retail Price Intelligence & Unit Economics Rule (استخراج الأسعار ومقارنة السلاسل)
- **Single Unit Economics**: Whenever processing receipt items where `quantity >= 2`, `price` MUST strictly be the net selling price per single piece (`netLineTotal / quantity`), `originalPrice` MUST strictly be the gross regular price per single piece (`grossLineTotal / quantity`), and `discountAmount` MUST be the unit discount (`lineDiscount / quantity`). Never store or present line totals as unit prices.
- **Enterprise Chain Consolidation**: Supermarket branches must resolve to their canonical parent Retail Chain (`normalizeRetailChain`: `أسواق فتح الله`, `جملة ماركت`, `بيت الجملة`, `كارفور`, `خير زمان`, `سبينس`, إلخ). Comparisons in tables, KPI cards, and dialogs must strictly be between Enterprise Chains.
- Full details and auto-healing specifications are documented in [.agents/skills/retail-price-intelligence-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/retail-price-intelligence-standard/SKILL.md).
