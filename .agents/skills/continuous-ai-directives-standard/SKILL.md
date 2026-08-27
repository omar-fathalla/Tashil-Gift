---
name: continuous-ai-directives-standard
description: Mandatory standard for continuous registration of AI heuristics, POS receipt learning, twin-bundle resolutions, unit economics rules, and zero-hallucination governance into the AI Brain Directives repository.
---

# Continuous AI Brain Directives & Heuristics Registration Standard

## 🎯 Core Objectives & Mandatory Lifecycle

Whenever an issue or edge case is resolved in receipt extraction, promotional rule matching, or retail heuristics (e.g. twin-pack bundles, combo packs, phonetic variations, store signatures, or zero-fallback prize qualification):

1. **Immediate AI Directive Registration (`AIR-XX`)**:
   - The agent MUST create/register a new formal directive entry in [ai_directives_seed_data.dart](file:///Users/fathalla/Development/Tashil%20Gift/lib/features/admin/domain/ai_directives_seed_data.dart).
   - The directive MUST include:
     - `id`: Sequential identifier (e.g. `AIR-20`, `AIR-21`, etc.).
     - `code`: UPPERCASE_SNAKE_CASE code descriptor.
     - `titleAr` & `titleEn`: Clean, descriptive titles without decorative emojis in titles.
     - `descriptionAr` & `descriptionEn`: Detailed problem statement and rationale.
     - `logicAr` & `logicEn`: Step-by-step programmatic algorithm / heuristic steps.
     - `exampleInput`: Concrete real-world receipt line or transaction scenario.
     - `exampleOutput`: Exact expected system outcome and prize resolution.
     - `tags`: Indexed searchable metadata tags.

2. **Automated Firestore Cloud Sync**:
   - The directive is synchronized to Cloud Firestore (`ai_brain_directives` collection) via `AiDirectivesService.seedDirectivesIfEmpty()`.
   - It appears immediately in the real-time AI Brain Rules screen (`AiBrainRulesScreen`) for admins, managers, and auditors.

3. **Continuous Knowledge Expansion**:
   - Every single POS anomaly, retailer printing quirk, and FMCG campaign rule taught to the system is preserved as a permanent asset in the AI knowledge base.
