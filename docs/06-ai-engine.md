# 06 — محرك الـ AI (Gemini)

## المسار

```
AiReceiptService / CampaignAiAssistantService / BranchSignatureAiService /
AiProductCatalogService / AiProductDiscoveryService / ChainProductsIntelligenceService
        │
        ▼
GeminiCloudModel (core/services/gemini_cloud_model.dart)
        │  httpsCallable('geminiGenerate')   + App Check
        ▼
functions/gemini_generate.js + gemini_gateway.js
        │  LRU cache (فروع/منتجات الحملة ساعة، تحليل نفس الصورة بالـ SHA-256 يوم)
        │  rate limit لكل عميل: 20/دقيقة، 200/يوم (Firestore rateLimits)
        ▼
Gemini API  (GEMINI_API_KEY في Secret Manager، مش في العميل)
```

لو الموديل رفض `thinkingConfig` بيعيد الطلب من غيره.

## الموديلات (`lib/core/constants/ai_models.dart`، و`functions/ai_models.js`)

| الاستخدام | الافتراضي |
|---|---|
| Primary (قراية الفواتير) | `gemini-3.7-flash` |
| Fallback | `gemini-3.6-flash` ثم `gemini-2.5-flash` |
| Fast tier | `gemini-3.7-flash` |
| Deep audit | `gemini-3.8-pro` |
| الخدمات المساعدة | `gemini-3.7-flash` (fallback `gemini-3.6-flash`) |

الأدمن يقدر يغيّر الموديل وقت التشغيل من `AiModelSwitcherDialog`؛ الإعداد بيتخزن في `system_settings` عن طريق `AiModelConfigService` و`AiConfig` بيحتفظ بيه في الذاكرة.

## الخدمات

| الخدمة | الدور |
|---|---|
| `AiReceiptService` (~6000 سطر) | البرومبت، قراية الفاتورة، تنظيف السطور، اقتصاديات الوحدة، `PromotionalRuleMatcher` |
| `CampaignAiAssistantService` | يقترح حملة وقواعدها من وصف حر (ويقسّم الفاوتشر لفئات المخزون) |
| `BranchSignatureAiService` | يستخرج «توقيع» الفرع من الفاتورة لتحديد الفرع |
| `AiProductCatalogService`, `AiProductDiscoveryService` | كتالوج الشركة واكتشاف منتجات جديدة من الفواتير |
| `ChainProductsIntelligenceService` | أسعار المنتجات في السلاسل والمقارنة |
| `AiBrainCopilotService` | مساعد صوتي/نصي داخل شاشة عقل الـ AI |

## عقل الـ AI (directives)

* كل قاعدة اتعلّمها النظام (POS quirk، طريقة حساب، تصحيح OCR...) بتتسجل كـ directive برقم `AIR-XX` في `lib/features/admin/domain/ai_directives_seed_data.dart` (آخر رقم حاليًا `AIR-89`).
* `AiDirectivesService` بيعمل seed/sync لمجموعة `ai_brain_directives`، وبتظهر في `AiBrainRulesScreen`.
* القاعدة (AGENTS.md #11): أي heuristic جديد لازم يتسجّل directive بوصف عربي/إنجليزي وأمثلة.

## قواعد الصرامة (AGENTS.md #10)

* `temperature: 0.0`، ممنوع التخمين.
* فاتورة مش واضحة ← `isValid = false` برسالة «صورة الفاتورة غير واضحة...».
* مفيش هدية بديلة لو القواعد ما اتحققتش.

## أدوات القياس

* `AiSpeedBenchmarkScreen` في لوحة الأدمن.
* `tool/run_12_receipts_benchmark.py` (فيه روابط فواتير مكشوفة، شوف TAG-33).
* `backups/ai_engine_backup_*.json`: نسخة من إعدادات المحرك.
