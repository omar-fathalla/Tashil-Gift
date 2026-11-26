# 01 — نظرة عامة على المنتج

## Tashil Gift بيعمل إيه

منصة ترويج للشركات (Unilever، Knorr، Cadbury، Edita، Almarai، ADCO/Clorox...) داخل سلاسل السوبرماركت (فتح الله، جملة ماركت، بيت الجملة، كارفور، خير زمان، سبينس...).

الفكرة: العميل بيشتري منتجات الشركة، المندوب (promoter) في الفرع بيصوّر الفاتورة، الـ AI (Gemini) بيقرا الفاتورة ويتأكد إنها مطابقة لشروط الحملة، وبعدين العميل بيكسب هدية أو فاوتشر من خلال لعبة (عجلة، كارت كشط، صندوق مفاجآت، اختيار هدية، أو هدية مباشرة). السيرفر هو اللي بيخصم من رصيد الهدايا في الفرع.

* الإنتاج: https://tashil-gift.web.app
* Firebase: مشروع `tashil-gift` (Blaze)، منطقة `us-central1`.
* المنصة: Flutter Web أساسًا (فيه مجلدات android و ios لكن النشر الفعلي web).
* اللغات: عربي (RTL، الافتراضي)، إنجليزي، وهندي.
* اسم الـ package في pubspec: `al_mraay` (اسم قديم، الـ imports كلها `package:al_mraay/...`).

## المستخدمين والأدوار

| الدور | إزاي بيدخل | بيعمل إيه |
|---|---|---|
| `super_admin` | `/admin` بإيميل وباسورد (custom claim `role`) | كل حاجة + إدارة الأدمنز وبيانات دخول البوابات |
| `admin` | `/admin` | إدارة الشركات والحملات والهدايا والسلاسل والفروع والـ AI |
| `partner` (قراية) | `/portal/<slug>` بيوزر وباسورد البوابة | مدير البراند: تقارير الحملات والمخزون والمبيعات |
| `partner` (ops) | `/ops/<slug>` أو `/ep/<eventId>` | شركة الدعاية/العمليات: نفس التقارير + تعديل فواتير شركته |
| مندوب / عميل | `/c/<slug>` أو `/e/<eventId>` (جلسة anonymous) | رفع الفاتورة واللعب وصرف الهدية |

الأدوار بتتحط كـ custom claims عن طريق الـ callable `setUserRole`، وبوابات الشركاء بتدخل بـ custom token من `partnerPortalLogin`.

## الروابط (routes)

| الرابط | الشاشة |
|---|---|
| `/` و `/admin` | `AdminAuthGuard` ← `AdminDashboardScreen` أو `AuthScreen` |
| `/login`, `/auth` | `AuthScreen` |
| `/c/<slug>`, `/client/<slug>`, `/promoter/<slug>`, `/submit` | `ClientReceiptUploadScreen` (رفع الفواتير) |
| `/e/<eventId>`, `/event/<eventId>` | `ClientReceiptUploadScreen` لحملة معيّنة |
| `/portal/<slug>`, `/p/<slug>`, `/brand/<slug>`, `/company/<slug>` | `CompanyManagerPortalScreen` (بوابة البراند) |
| `/ops/<slug>`, `/agency/<slug>`, `/operations/<slug>` | `CompanyManagerPortalScreen` بوضع العمليات |
| `/ep/<eventId>`, `/event-portal/<eventId>` | بوابة عمليات لحملة واحدة |
| `/share/<id>` وروابط البوابات | بتعدي الأول على Cloud Function `sharePreview` عشان OpenGraph |
| `/waha/**` | proxy لبوابة WhatsApp (WAHA) |

لو الحملة أو البوابة موقوفة بيظهر `CampaignSuspendedScreen`.

## الأجزاء الكبيرة في المنتج

1. **إدارة الحملات** (`create_event_screen.dart`): شروط الحملة، قواعد العروض (promotional rules)، توزيع الهدايا على الفروع، الألعاب، الشرائح (spend ladder)، المسودات، و«جرّب على فاتورة» (dry-run).
2. **رفع الفواتير والتحقق** (`client_portal`, `validation`): تصوير، قراية AI، فحص التكرار، تحديد الفرع، حفظ.
3. **الألعاب وصرف الهدايا** (`games`): العجلة، الكشط، الصندوق، اختيار الهدية، الهدية المباشرة، والاحتفال.
4. **بوابة الشركة** (`company_portal`): سجل الفواتير، أرصدة الفروع، تقرير الفواتشر، مبيعات الفروع اليومية، مقارنة الحملات، التسويق للعملاء، WhatsApp.
5. **ذكاء السلاسل والأسعار**: كتالوج منتجات الشركات، أسعار المنتجات في السلاسل، اكتشاف منتجات جديدة بالـ AI.
6. **عقل الـ AI**: قواعد (directives) `AIR-XX` بتتعلّمها الموديلات، واختيار الموديل، وقياس السرعة.
7. **WhatsApp**: إشعار الفائزين، حملات رسائل، inbox للـ webhook، ربط الأرقام (WAHA).
