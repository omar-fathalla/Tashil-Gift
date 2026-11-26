# 03 — نموذج البيانات والصلاحيات

## مجموعات Firestore

| المجموعة | فيها إيه | مين يقرا | مين يكتب |
|---|---|---|---|
| `events/{eventId}` | الحملة (`EventModel`) | الأدمن، الـ anonymous لو الحملة `isActive`، الشريك لنفس الشركة | الأدمن |
| `events/{id}/content/{docId}` | منتجات الحملة والبرومبت (`products`, `products_N`, `prompt`) — TAG-62 | زي الحملة | الأدمن |
| `events/{id}/sharded_counters/.../shards` | عدادات موزّعة للحملة | الأدمن والشريك | الأدمن |
| `receipts_transactions/{txId}` | كل فاتورة اترفعت ونتيجة الـ AI والهدايا المصروفة | الأدمن، صاحب الرفع، الشريك لنفس الشركة | anonymous بشروط `validAnonymousReceipt`، الشريك ops، الأدمن. صرف الهدايا من السيرفر |
| `companies/{id}` | الشركات (فيها بيانات دخول البوابات) | الأدمن | الأدمن |
| `company_products/{id}` | كتالوج منتجات الشركة (باركود، اسم، براند) | الأدمن (وغيره حسب القاعدة) | الأدمن |
| `company_gifts/{giftId}` | مخزون الهدايا والفواتشر (`CompanyGiftModel`، دفعات توريد) | الأدمن والشريك | الأدمن |
| `gift_stock_movements/{id}` | حركات المخزون | الأدمن والشريك | الأدمن |
| `retail_chains/{id}` | السلاسل (`RetailChainModel`) | الكل المسجّل | الأدمن |
| `branches/{id}` | الفروع (`BranchModel`، توقيع الفاتورة، كود الفرع) | الكل المسجّل | الأدمن |
| `chain_products_catalog/{id}` | أسعار المنتجات في السلاسل | الأدمن | الأدمن |
| `daily_campaign_branch_sales/{id}` | تجميعة مبيعات يومية لكل فرع | الأدمن والشريك | الأدمن |
| `campaign_stock_settlements/{id}` | تسويات مخزون الحملة | الأدمن والشريك | الأدمن |
| `company_supervisors/{id}` | مشرفين الشركة (لـ WhatsApp) | الأدمن | الأدمن (بتحقق من الشكل) |
| `marketing_contacts/{id}` | أرقام العملاء للتسويق | الأدمن والشريك | الأدمن والشريك بشروط |
| `discovered_products_inbox/{id}` | منتجات اكتشفها الـ AI ومستنية مراجعة | الأدمن | الأدمن |
| `ai_brain_directives/{id}` | قواعد عقل الـ AI (`AIR-XX`) | الأدمن | الأدمن |
| `system_settings/{id}` | إعدادات عامة (منها الموديل النشط) | الأدمن | الأدمن |
| `admins/{email}` | قائمة الأدمنز | super_admin | super_admin |
| `portal_credentials/{id}` | بيانات دخول البوابات | super_admin | super_admin |
| `portal_access_logs/{id}` | سجل دخول البوابات | الأدمن | الأدمن/الشريك create |
| `event_drafts/{id}` | مسودات الحملات (C-05) | الأدمن | الأدمن |
| `whatsapp_*` (inbound, status, outbox, sender_links, webhook_config, webhook_campaigns) | WhatsApp | الأدمن | السيرفر بس |
| `rateLimits`, `loginThrottle` | حماية من الإساءة | محدش | السيرفر بس |
| `shards`, `sharded_counters` (root) | عدادات قديمة | الأدمن | الأدمن |

أي مسار مش مذكور مقفول (`allow read, write: if false`).

ملاحظة: `firestore.indexes.json` فيه index لـ `validation_transactions` ومفيش rules ولا كود بيستخدم المجموعة دي، غالبًا بقايا.

## الصلاحيات (helpers في `firestore.rules`)

* `isAdmin()` = مسجّل ومش anonymous و `role` في الـ token يا `admin` يا `super_admin`.
* `isPartner()` = `role == 'partner'`، والشركة من `companySlug` في الـ token، و`partnerAccess == 'ops'` للعمليات.
* `validAnonymousReceipt()` = الفاتورة تبع الحملة النشطة ونفس الشركة، `submittedByUid` = المستخدم، `timestamp == request.time`، حدود على الحجم (80 حقل، 80 منتج). القاعدة صغيرة عمدًا عشان حد الـ 1000 expression.
* اختبارات الـ rules في `rules-tests/` (Jest على الـ emulator).

## Storage (`storage.rules`)

| المسار | القراية | الكتابة |
|---|---|---|
| `receipts/{companySlug}/**` | الأدمن/الشريك أو اللي رفع | create للي رافع صورة؛ update/delete للـ staff |
| `company_logos/**`, `company_gifts/**` | عام | الـ staff (صور بس) |
| `whatsapp_campaign_media/{uid}/{file}` | الـ staff (get) | الـ staff |
| أي حاجة تانية | ممنوع | ممنوع |

## موديل الحملة `EventModel` (`features/admin/domain/event_model.dart`)

أهم الحقول:

* الهوية: `id`, `eventName`, `targetCompany`, `companySlug`, `companyLogoUrl`.
* الوقت والحالة: `startDate`, `endDate`, `isActive`، وتشغيل كل بوابة: `isPromoterActive`, `isAgencyActive`, `isManagerActive`. الحملة بتتقفل تلقائي بعد يوم النهاية بتوقيت القاهرة (`autoCloseExpiredCampaigns`).
* الشروط: `minimumSpend`, `requiredProducts`, `customPrompt` (برومبت الـ AI)، `promotionalIdea`, `aiValidationSummary`.
* `promotionalRules: List<PromotionalRuleItem>`: كل قاعدة ليها `conditionType` (`by_quantity` | `by_spend` | `combo_spend`)، `minQuantity`/`minSpend`/`maxSpend`, `matchMode` (`OR`/`AND`)، `requiredBrands`, `selectedProductIds/Barcodes/Names`، `rewardType` (`voucher` | `free_product` | `game_spin`)، `allowMultipliers`، `linkedGifts: List<LinkedGiftAllocation>` (الكميات نهائية ومش بتتضرب تاني)، `gameType` خاص بالقاعدة، و`rewardOptions` (العميل يختار واحدة).
* الهدايا: `allocatedPrizes: List<AllocatedPrize>` (لكل فرع: `giftId`, `allocatedQuantity`, `remainingQuantity`, `branchId`, `giftType`, `unitValue`).
* الفروع: `retailChainId`, `branchIds`, `branchNames`, `isAllBranches`. الفروع المعتمدة بس هي اللي تظهر في الفلاتر.
* المضاعفات: `allowMultipleChances`, `multiplierBasis`, `maxChancesPerReceipt`, `spendLadderMode` (`exclusive` الافتراضي | `consuming`).
* الفواتشر: `voucherSerialMode` (`required` | `optional` | `hidden`).
* `allowComplementaryReceipts` (تجميع أكتر من فاتورة، مقفول افتراضيًا)، `enableWhatsAppWinnerNotification`.
* بيانات دخول بوابة العمليات الخاصة بالحملة: `customAgencyUsername/Password/CredentialVersion` (نص صريح، شوف tech debt).
* `contentInfo: CampaignContentInfo`: هل المنتجات والبرومبت جوه المستند ولا في `content/` (`external`, `version`, `chunks`, `productsInline`, `promptInline`).

موديلات تانية مهمة: `CompanyModel`, `CompanyProductModel`, `CompanyGiftModel` (+ `GiftSupplyBatch`, `GiftStockMovement`)، `RetailChainModel`, `BranchModel` (+ `BranchReceiptSignature`)، `ChainProductItem`، `AiDirectiveModel`.

## الفاتورة (`receipts_transactions`)

مستند الفاتورة ID بتاعه غالبًا ثابت `rcpt_{campaignId}_{رقم الفاتورة}` (عشان منع التكرار). فيه: `campaignId`, `companySlug`, `submittedByUid`, `timestamp`, `receipt_number`, `total_value`, `extracted_products` (سعر الوحدة مش إجمالي السطر)، بيانات العميل، الفرع (`canonical_branch` بيتحسب وقت التحميل)، حالة التحقق، والهدايا المصروفة (`claimed_gifts`) اللي السيرفر بيكتبها.
