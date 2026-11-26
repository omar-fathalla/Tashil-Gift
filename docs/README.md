# توثيق Tashil Gift (منظومة تسهيل جفت الذكية)

الملفات دي مرجع سريع لأي حد (إنسان أو agent) هيشتغل على المشروع. اقرا الملف اللي يخص الجزء اللي هتلمسه قبل ما تبدأ.

| الملف | فيه إيه |
|---|---|
| [01-overview.md](01-overview.md) | المنتج، المستخدمين، البوابات والروابط |
| [02-architecture.md](02-architecture.md) | هيكل الكود، الـ routing، Firebase scope، الـ state |
| [03-data-model.md](03-data-model.md) | مجموعات Firestore، موديل الحملة، الصلاحيات (rules)، Storage |
| [04-receipt-and-claim-flow.md](04-receipt-and-claim-flow.md) | رحلة الفاتورة من التصوير لحد صرف الهدية |
| [05-cloud-functions.md](05-cloud-functions.md) | كل الـ Cloud Functions ووظيفة كل واحدة |
| [06-ai-engine.md](06-ai-engine.md) | Gemini، الموديلات، عقل الـ AI (directives) |
| [07-dev-setup.md](07-dev-setup.md) | تجهيز الجهاز، التشغيل، الاختبارات، الـ emulators |
| [08-ci-cd-and-release.md](08-ci-cd-and-release.md) | الفروع، GitHub Actions، رفع الإصدار، الـ rollback |
| [09-conventions.md](09-conventions.md) | قواعد الكود والتصميم المختصرة (من AGENTS.md) |
| [10-tech-debt-and-gaps.md](10-tech-debt-and-gaps.md) | النواقص والمخاطر المعروفة |
| [11-roadmap.md](11-roadmap.md) | خطة التطوير مربوطة بتيكتات Linear |

## مصادر تانية في الريبو

* `AGENTS.md` (ونسخته `GEMINI.md`): القواعد الإلزامية الكاملة للـ agents.
* `.agents/skills/*/SKILL.md`: تفاصيل كل معيار (فروع الحملات، قواعد العروض، الأداء، M3...).
* `tool/ci/README.md`: ملخص الـ CI.
* `docs/DEV_ENVIRONMENT.md`: بيئة `tashil-gift-dev` (موجود على فرع `feat/dev-environment`، لسه ما اتدمجش).
* Linear: فريق **Tashil Gift** (مفتاح `TAG`)، ومشروع **Tashil Gift — Dev Environment** (`P-TAG-16`).

## إزاي تحدّث التوثيق

* أي PR يغيّر سلوك موجود في ملف من دول يحدّث الملف في نفس الـ PR.
* الأرقام (عدد الملفات، الاختبارات، الإصدار) اتقاست يوم 2026-11-26 على `dev` عند الإصدار `2.0.191+251`.
