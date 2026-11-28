# 05 — Cloud Functions (`functions/`)

* Node 22، CommonJS، `firebase-functions` v7 (gen2)، `firebase-admin` v14.
* كلها في `us-central1` بـ 256MiB. الـ callables عليها `enforceAppCheck: true`.
* الأسرار (Secret Manager): `GEMINI_API_KEY`, `WAHA_API_KEY`, `WAHA_WEBHOOK_SECRET`.
* نقطة الدخول: `functions/index.js`، و`security_functions.js` بيتدمج فيه بـ `Object.assign`.

## الدوال المنشورة

| الدالة | النوع | الملف | بتعمل إيه |
|---|---|---|---|
| `geminiGenerate` | callable | `gemini_generate.js`, `gemini_gateway.js` | بوابة كل طلبات Gemini من العميل (cache + rate limit + fallback) |
| `analyzeReceipt` | callable | `receipt_verification.js` | تحليل فاتورة على السيرفر (WhatsApp / قديم، مش في مسار الويب) |
| `checkReceiptDuplicate` | callable | `receipt_duplicate_check.js` | فحص التكرار عبر كل المستخدمين، بيرجّع `{duplicate, existingStatus}` بس |
| `replaceReceipt` | callable | `receipt_replace.js` | إعادة رفع فاتورة موجودة (الفاتورة المعتمدة مقفولة لغير الـ staff) |
| `logReceiptSaveFailure` | callable | `receipt_save_failure_log.js` | تسجيل فشل حفظ الفاتورة للتشخيص |
| `listBranchReceipts` | callable | `list_branch_receipts.js` | فواتير الفرع للمندوب |
| `decrementCampaignPrize` | callable | `security_functions.js` | صرف الهدية: أهلية + شرائح + خصم مخزون في transaction |
| `setUserRole` | callable | `security_functions.js` | تعيين custom claims للأدوار |
| `dryRunCampaignEligibility` | callable | `campaign_dry_run.js` | «جرّب على فاتورة» للـ staff، من غير كتابة |
| `updateBranchAllocations` | callable | `branch_allocations.js` | حفظ أرصدة الفروع وتسوية نهاية الأسبوع |
| `sendWinnerWhatsApp` | callable | `winner_whatsapp.js` | رسالة WhatsApp للفائز |
| `partnerPortalInfo` | callable | `partner_portal.js` | اسم ولوجو الشركة وإصدارات بيانات الدخول |
| `partnerPortalLogin` | callable | `partner_portal.js` | التحقق من يوزر/باسورد البوابة وإصدار custom token (مع `login_throttle.js`) |
| `updateWhatsappWebhookConfig` | callable | `whatsapp_webhook_admin.js` | إعدادات webhook الـ WhatsApp |
| `manageWhatsappSenderLink` | callable | `whatsapp_webhook_admin.js` | ربط رقم مرسل بحملة |
| `sharePreview` | HTTP | `share_preview.js` | صفحات OpenGraph لروابط المشاركة (بتيجي من rewrites الـ hosting) |
| `wahaProxy` | HTTP | `index.js` | proxy لـ WAHA (`/waha/**`) بـ ID token + origin allowlist |
| `wahaWebhook` | HTTP (public) | `waha_webhook.js` | استقبال رسائل WhatsApp (HMAC)، تحليل الفاتورة والصرف |
| `autoCloseExpiredCampaigns` | schedule `10 0 * * *` Africa/Cairo | `auto_close_campaigns.js` | قفل الحملات اللي عدّى يوم نهايتها |

على فرع `feat/tag18-auto-activate` (TAG-18، In Review): `auto_activate_campaigns.js` للتفعيل التلقائي يوم البداية.

## موديولات مساعدة

* `campaign_eligibility.js`: نفس منطق صفحة الرفع لكن على السيرفر (المرجع).
* `exclusive_spend_ladder.js`, `consuming_spend_ladder.js`: الشرائح.
* `known_brands.js`: براندات معروفة عشان سطر يذكر براند برّه الحملة ما يتحسبش.
* `campaign_content.js`: قراية `events/{id}/content` (TAG-62).
* `rate_limit.js`, `login_throttle.js`, `waha_rate_scope.js`: حماية.
* `ai_models.js`: أسماء الموديلات على السيرفر.

## سكربتات (`functions/scripts/`)

* `bootstrap-super-admin.js` (`npm run bootstrap:super-admin`): أول super admin.
* `migrate_campaign_content.js`: نقل المنتجات/البرومبت لـ `content/` (dry-run افتراضي؛ TAG-63).
* `audit_claim_eligibility.js`, `shared_pool_report.js`: تقارير.
* `check_hosting_cache_emulator.js`, `run_hosting_cache_emulator.sh`: اختبار headers الـ cache.

## الاختبارات

* `npm test`: 29 ملف unit (`node --test`) + `gemini_gateway_test.js`. آخر تشغيل (2026-11-26): **300 نجح، 0 فشل** + 5 اختبارات gateway.
* `npm run test:emulator`: اختبارات على Firestore/Auth/Functions emulators (`*.emulator.test.js`) بمشروع `demo-tashil`.
