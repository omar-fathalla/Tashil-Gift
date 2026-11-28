# 04 — رحلة الفاتورة: من التصوير لحد صرف الهدية

ده أهم flow في المنتج، وأغلب البلاجات في Linear بتيجي منه. الكود الأساسي في `ClientReceiptUploadScreen._submitAndValidateReceiptImpl` (`features/client_portal/presentation/client_receipt_upload_screen.dart`).

## الخطوات (`ReceiptSaveStep`)

1. **الجلسة (`session`)**: التأكد إن التاب لسه فيه جلسة anonymous للمندوب (`_restoreRepSession`)، وإن الحملة جوه مواعيدها (`receipt_date_window.dart`، أيام كاملة بتوقيت القاهرة).
2. **تجهيز الصورة**: `receipt_image_calibrator.dart` (تباين الفواتير الحرارية) وتصغير الصورة على الويب. الفاتورة ممكن تبقى أكتر من جزء (parts).
3. **البحث (`lookup`)**: تحميل كتالوج باركودات الشركة وتوقيعات الفروع بالتوازي، ومنتجات/برومبت الحملة من `events/{id}/content` (TAG-62) عن طريق `CampaignContentRepository`.
4. **الـ AI (`ai`)**: `AiReceiptService.analyzeReceiptImage` ← `GeminiCloudModel` ← callable `geminiGenerate`. بيرجّع رقم الفاتورة، التاريخ، الفرع، السطور (سعر الوحدة)، الإجمالي، و`isValid`. لو سطر سعره بعيد عن الكتالوج بيتعمل re-read مركّز مرة واحدة.
5. **قواعد العروض**: `PromotionalRuleMatcher.matchAllWithMultipliers` (في `ai_receipt_service.dart`) بيحسب الهدايا النهائية. لو الحملة ليها قواعد ومفيش قاعدة اتحققت، الفاتورة **بتترفض** بسبب واضح (`getUnfulfilledPromotionReasons`) ومفيش هدية بديلة. الفاتورة المرفوضة بتتسجّل للمراجعة (`_recordRejectedReceipt`).
6. **منع التكرار (`dupCheck`)**: `ReceiptDeduplicationHelper.checkReceiptDuplicate` ← callable `checkReceiptDuplicate` (السيرفر بس يقدر يشوف فواتير مستخدمين تانيين). الـ ID ثابت: `rcpt_{campaignId}_{receiptNo}`. الفاتورة المعتمدة مقفولة لغير الأدمن؛ إعادة الرفع بتعدي على `replaceReceipt`.
7. **الرفع (`storage`)**: الصورة على `receipts/{companySlug}/...` (create-only).
8. **الحفظ**: مستند في `receipts_transactions` بشروط `validAnonymousReceipt`. لو فشل الحفظ بيتسجّل عن طريق `logReceiptSaveFailure`.
9. **أعمال جانبية async**: تجميع منتجات جديدة لـ `discovered_products_inbox`، تحديث أسعار السلاسل، تجهيز بيانات فروع جديدة للمراجعة.
10. **تحديد الفرع**: `SmartBranchMatcherService` و `canonical_branch_resolver` و `store_code_branch_resolver` (كود الفرع من رقم الفاتورة). ممنوع نخمّن «أول فرع».
11. **اللعبة**: حسب `gameType` الخاص بالقاعدة أو الحملة:
    * `directGift` ← `DirectGiftClaimScreen`
    * `chooseGift` أو حملة `consuming` ← `ChooseGiftScreen`
    * `scratch` (أو إجمالي ≥ 500 لو مفيش نوع) ← `ScratchCardScreen`
    * غير كده ← `SpinTheWheelScreen`
    * وفيه `MysteryBoxScreen`، و`WinnerCelebrationDialog` في الآخر.
12. **صرف الهدية**: `CompanyGiftsService.decrementCampaignPrize` ← callable `decrementCampaignPrize` (`functions/security_functions.js` → `applyCampaignPrizeClaim`).

## اللي بيحصل على السيرفر وقت الصرف

`applyCampaignPrizeClaim` جوه transaction:

1. App Check + لازم يكون مسجّل.
2. **إعادة التحقق من الأهلية** (`campaign_eligibility.js`): الحملة نشطة، الفاتورة جوه المواعيد، المنتجات المطلوبة موجودة، الحد الأدنى للإنفاق محسوب على منتجات الحملة بس (مش إجمالي الفاتورة ولا براندات تانية لنفس الشركة — TAG-67)، وعدد الهدايا المستحقة (`serverUnits`). لو مش أهل بيرمي error بـ reason code من غير ما يكتب أي حاجة.
3. **الشرائح**: `exclusive_spend_ladder.js` (أعلى شريحة + الباقي يشتري شريحة أقل مرة واحدة) أو `consuming_spend_ladder.js` (كل شريحة بتستهلك من المبلغ).
4. **اختيار صف المخزون**: `resolveLadderStockRow` / `resolvePrizeIndexForDecrement` حسب الفرع (من كود الفرع في رقم الفاتورة) والهدية والقيمة. فيه shared pool اختياري.
5. الخصم مرة واحدة بس لكل فاتورة (claim ledger)، وتقليم الكميات للحد المسموح (`trimDecrementsToLimit`).
6. تحديث الفاتورة بالهدايا المصروفة والعدادات الموزّعة (`recordShards`).
7. لو فشل بيتسجّل `recordClaimFailure`. العميل عنده retry و resume (`claim_retry.dart`, `claim_ledger_resume.dart`, `claim_callable_fallback.dart`).

بعد الصرف: إشعار WhatsApp للفائز (`sendWinnerWhatsApp`) لو `enableWhatsAppWinnerNotification`.

## قواعد لازم تفضل صح (invariants)

* الكميات في `linkedGifts` نهائية؛ ممنوع تتضرب في عدد الفرص تاني.
* مفيش هدية بديلة لو القواعد ما اتحققتش.
* سعر الوحدة = صافي السطر ÷ الكمية.
* الـ AI بيرفض الفاتورة المش واضحة بدل ما يخمّن (`temperature: 0`).
* الفلترة بالفرع بالمساواة على `canonical_branch` وبس فروع الحملة.
* العميل بيحسب للعرض بس؛ السيرفر هو المرجع في الأهلية والمخزون.

## مسارات تانية لنفس الفكرة

* **تعدد الحملات**: لو الرابط بتاع شركة وفيها أكتر من حملة، `MultiCampaignReceiptEvaluator.evaluateAll` بيقيّم الفاتورة على كل الحملات و`UnifiedMultiCampaignClaimScreen` بيصرف.
* **التحقق اليدوي**: `InvoicesLogScreen` (الأدمن والشريك ops) بيعيد التحليل ويعدّل.
* **WhatsApp**: `wahaWebhook` بيستقبل صورة فاتورة ويستخدم نفس `verifyReceiptImage`.
* **جرّب على فاتورة** (C-05): `dryRunCampaignEligibility` بيشغّل الأهلية على حملة لسه ما اتحفظتش.
