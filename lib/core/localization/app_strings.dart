import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'locale_provider.dart';

/// Centralized Trilingual Dictionary (Arabic, English, Hindi) for Switch Point / Tashil Gift
class AppStrings {
  final String languageCode;

  AppStrings(this.languageCode);

  bool get isAr => languageCode == 'ar';
  bool get isEn => languageCode == 'en';
  bool get isHi => languageCode == 'hi';

  factory AppStrings.of(WidgetRef ref) {
    return AppStrings(ref.watch(localeProvider).languageCode);
  }

  factory AppStrings.fromLocale(String languageCode) {
    return AppStrings(languageCode);
  }

  /// Helper to return appropriate string based on current language
  String _t({required String ar, required String en, required String hi}) {
    if (isAr) return ar;
    if (isHi) return hi;
    return en;
  }

  // ---------------------------------------------------------------------------
  // 1. Common / Shared Actions
  // ---------------------------------------------------------------------------
  String get appTitle => _t(ar: 'تسهيل جيفت', en: 'Tashil Gift', hi: 'तशहील गिफ्ट');
  String get brandSubtitle => _t(
    ar: 'حلول الترويج والتحقق الذكي متعدد الشركات',
    en: 'Smart Multi-Company Promotion & AI Verification',
    hi: 'स्मार्ट मल्टी-कंपनी प्रचार और एआई सत्यापन',
  );
  String get save => _t(ar: 'حفظ', en: 'Save', hi: 'सहेजें');
  String get cancel => _t(ar: 'إلغاء', en: 'Cancel', hi: 'रद्द करें');
  String get delete => _t(ar: 'حذف', en: 'Delete', hi: 'हटाएं');
  String get edit => _t(ar: 'تعديل', en: 'Edit', hi: 'संपादित करें');
  String get add => _t(ar: 'إضافة', en: 'Add', hi: 'जोड़ें');
  String get search => _t(ar: 'بحث', en: 'Search', hi: 'खोजें');
  String get filter => _t(ar: 'تصفية', en: 'Filter', hi: 'फ़िल्टर');
  String get all => _t(ar: 'الكل', en: 'All', hi: 'सभी');
  String get close => _t(ar: 'إغلاق', en: 'Close', hi: 'बंद करें');
  String get back => _t(ar: 'رجوع', en: 'Back', hi: 'पीछे जाएं');
  String get cancelBtn => cancel;
  String get backBtn => back;
  String get copyCodeBtn => copy;
  String get closeBtn => close;
  String get loading => _t(ar: 'جاري التحميل...', en: 'Loading...', hi: 'लोड हो रहा है...');
  String get error => _t(ar: 'حدث خطأ', en: 'An error occurred', hi: 'एक त्रुटि हुई');
  String get success => _t(ar: 'تم بنجاح', en: 'Success', hi: 'सफलतापूर्वक संपन्न');
  String get confirm => _t(ar: 'تأكيد', en: 'Confirm', hi: 'पुष्टि करें');
  String get actions => _t(ar: 'الإجراءات', en: 'Actions', hi: 'कार्रवाई');
  String get copy => _t(ar: 'نسخ', en: 'Copy', hi: 'कॉपी करें');
  String get copyLink => _t(ar: 'نسخ الرابط', en: 'Copy Link', hi: 'लिंक कॉपी करें');
  String get linkCopied => _t(ar: 'تم نسخ الرابط بنجاح', en: 'Link copied successfully', hi: 'लिंक सफलतापूर्वक कॉपी किया गया');
  String get noData => _t(ar: 'لا توجد بيانات متاحة', en: 'No data available', hi: 'कोई डेटा उपलब्ध नहीं है');
  String get requiredField => _t(ar: 'هذا الحقل مطلوب', en: 'This field is required', hi: 'यह फ़ील्ड आवश्यक है');
  String get viewAll => _t(ar: 'عرض الكل', en: 'View All', hi: 'सभी देखें');
  String get exportExcelCsv => _t(ar: 'تصدير CSV / Excel', en: 'Export CSV / Excel', hi: 'CSV / Excel निर्यात करें');

  // ---------------------------------------------------------------------------
  // 2. Navigation & Sidebar
  // ---------------------------------------------------------------------------
  String get navEventsManagement => _t(ar: 'الحملات والإدارة', en: 'Campaigns & Events', hi: 'अभियान और प्रबंधन');
  String get navAnalytics => _t(ar: 'التقارير والتحليلات', en: 'Reports & Analytics', hi: 'रिपोर्ट और विश्लेषण');
  String get navCompanyCatalog => _t(ar: 'تكويد الشركات والمنتجات', en: 'Company & Product Catalog', hi: 'कंपनी और उत्पाद सूची');
  String get navRetailChains => _t(ar: 'السلاسل والمنافذ', en: 'Retail Chains & Outlets', hi: 'रिटेल चेन और स्टोर');
  String get navInvoicesAudit => _t(ar: 'سجل الفواتير والتدقيق', en: 'Invoices Audit & Logs', hi: 'रसीद ऑडिट और लॉग');
  String get navCreateCampaign => _t(ar: 'إنشاء حملة جديدة', en: 'Create New Campaign', hi: 'नया अभियान बनाएं');
  String get navCompanyGifts => _t(ar: 'هدايا الشركات', en: 'Company Gifts', hi: 'कंपनी उपहार');
  String get navGameTypes => _t(ar: 'أنواع الألعاب', en: 'Game Types', hi: 'खेल के प्रकार');
  String get navAiSpeedBenchmark => _t(ar: 'اختبار سرعة الـ AI (KPI) ⚡', en: 'AI Latency & Speed KPI ⚡', hi: 'एआई स्पीड टेस्ट ⚡');
  String get previewClientApp => _t(ar: 'معاينة تطبيق العميل / البروموتر', en: 'Preview Client / Promoter App', hi: 'ग्राहक ऐप का पूर्वावलोकन');
  String get collapseMenu => _t(ar: 'طي القائمة (أيقونات فقط)', en: 'Collapse Menu (Icons Only)', hi: 'मेनू संक्षिप्त करें');
  String get expandMenu => _t(ar: 'توسيع القائمة (أيقونات ونص)', en: 'Expand Menu (Icons & Text)', hi: 'मेनू विस्तृत करें');

  // ---------------------------------------------------------------------------
  // 3. Header & Theme & Country
  // ---------------------------------------------------------------------------
  String get switchToLightMode => _t(ar: 'التحويل للوضع الفاتح (Light Mode)', en: 'Switch to Light Mode', hi: 'लाइट मोड में बदलें');
  String get switchToDarkMode => _t(ar: 'التحويل للوضع الداكن (Dark Mode)', en: 'Switch to Dark Mode', hi: 'डार्क मोड में बदलें');
  String get languageToggleTooltip => _t(ar: 'تغيير لغة النظام', en: 'Change System Language', hi: 'सिस्टम की भाषा बदलें');
  String get activeCountryTooltip => _t(ar: 'الدولة والعملة النشطة', en: 'Active Country & Currency', hi: 'सक्रिय देश और मुद्रा');

  // ---------------------------------------------------------------------------
  // 4. Agent 1: Events Management (الحملات والإدارة)
  // ---------------------------------------------------------------------------
  String get eventsTitle => _t(ar: 'إدارة الحملات والفعاليات النشطة', en: 'Campaigns & Active Events Management', hi: 'सक्रिय अभियानों का प्रबंधन');
  String get eventsSubtitle => _t(
    ar: 'متابعة وإدارة كافة الحملات الترويجية والتحقق الذكي',
    en: 'Monitor and manage all promotional campaigns and smart verification',
    hi: 'सभी प्रचार अभियानों और स्मार्ट सत्यापन की निगरानी करें',
  );
  String get totalActiveEvents => _t(ar: 'إجمالي الحملات النشطة', en: 'Total Active Campaigns', hi: 'कुल सक्रिय अभियान');
  String get totalVerifiedReceipts => _t(ar: 'إجمالي الفواتير المفحوصة', en: 'Total Verified Receipts', hi: 'कुल सत्यापित रसीदें');
  String get totalCompaniesRegistered => _t(ar: 'الشركات المسجلة', en: 'Registered Companies', hi: 'पंजीकृत कंपनियां');
  String get eventNameHeader => _t(ar: 'اسم الحملة', en: 'Campaign Name', hi: 'अभियान का नाम');
  String get targetCompanyHeader => _t(ar: 'الشركة المستهدفة', en: 'Target Company', hi: 'लक्षित कंपनी');
  String get retailChainHeader => _t(ar: 'السلسلة / الفرع', en: 'Retail Chain / Branch', hi: 'रिटेल चेन / शाखा');
  String get gameTypeHeader => _t(ar: 'نوع اللعبة', en: 'Game Type', hi: 'खेल का प्रकार');
  String get minSpendHeader => _t(ar: 'الحد الأدنى', en: 'Min Spend', hi: 'न्यूनतम खर्च');
  String get statusHeader => _t(ar: 'الحالة', en: 'Status', hi: 'स्थिति');
  String get activeStatus => _t(ar: 'نشطة', en: 'Active', hi: 'सक्रिय');
  String get expiredStatus => _t(ar: 'منتهية', en: 'Expired', hi: 'समाप्त');
  String get openClientLink => _t(ar: 'فتح رابط العميل', en: 'Open Client Link', hi: 'ग्राहक लिंक खोलें');
  String get viewReports => _t(ar: 'عرض التقارير والتحليلات', en: 'View Reports & Analytics', hi: 'रिपोर्ट और विश्लेषण देखें');
  String get deleteEventConfirmTitle => _t(ar: 'تأكيد حذف الحملة', en: 'Confirm Campaign Deletion', hi: 'अभियान हटाने की पुष्टि करें');
  String get deleteEventConfirmMsg => _t(
    ar: 'هل أنت متأكد من رغبتك في حذف هذه الحملة نهائياً؟',
    en: 'Are you sure you want to permanently delete this campaign?',
    hi: 'क्या आप वाकई इस अभियान को हमेशा के लिए हटाना चाहते हैं?',
  );
  String get noEventsFound => _t(
    ar: 'لا توجد حملات مسجلة حالياً. يمكنك إنشاء أول حملة ترويجية الآن.',
    en: 'No campaigns registered yet. You can create the first promotional campaign now.',
    hi: 'अभी तक कोई अभियान पंजीकृत नहीं है। आप नया अभियान बना सकते हैं।',
  );

  // ---------------------------------------------------------------------------
  // 5. Agent 2: Reports & Analytics (التقارير والتحليلات)
  // ---------------------------------------------------------------------------
  String get analyticsTitle => _t(ar: 'منظومة التقارير والتحليلات الشاملة', en: 'Comprehensive Reports & Analytics', hi: 'व्यापक रिपोर्ट और विश्लेषण प्रणाली');
  String get tabOverviewMetrics => _t(ar: 'نظرة عامة والمؤشرات', en: 'Overview & Key Metrics', hi: 'अवलोकन और मुख्य मेट्रिक्स');
  String get tabInvoicesBreakdown => _t(ar: 'تفاصيل الفواتير والعمليات', en: 'Invoices & Transactions Log', hi: 'रसीदें और लेनदेन विवरण');
  String get metricTotalScans => _t(ar: 'إجمالي عمليات المسح', en: 'Total Scans', hi: 'कुल स्कैन');
  String get metricAcceptedInvoices => _t(ar: 'الفواتير المقبولة', en: 'Accepted Invoices', hi: 'स्वीकृत रसीदें');
  String get metricRejectedInvoices => _t(ar: 'الفواتير المرفوضة', en: 'Rejected Invoices', hi: 'अस्वीकृत रसीदें');
  String get metricTotalPromotionalSales => _t(ar: 'إجمالي مبيعات الحملة', en: 'Total Campaign Sales', hi: 'कुल अभियान बिक्री');
  String get metricTotalSalesVolume => _t(ar: 'إجمالي قيمة المبيعات', en: 'Total Sales Volume', hi: 'कुल बिक्री राशि');
  String get topSellingProductsTitle => _t(ar: 'المنتجات الأكثر مبيعاً في الحملة', en: 'Top Selling Campaign Products', hi: 'सबसे अधिक बिकने वाले उत्पाद');
  String get retailChainsBreakdownTitle => _t(ar: 'توزيع المبيعات حسب السلاسل والفروع', en: 'Sales Breakdown by Retail Chains & Branches', hi: 'रिटेल चेन और स्टोर अनुसार बिक्री');
  String get filterByCompany => _t(ar: 'تصفية حسب الشركة:', en: 'Filter by Company:', hi: 'कंपनी द्वारा फ़िल्टर करें:');
  String get filterByChain => _t(ar: 'تصفية حسب السلسلة:', en: 'Filter by Retail Chain:', hi: 'रिटेल चेन द्वारा फ़िल्टर करें:');
  String get searchReceiptHint => _t(ar: 'البحث برقم الفاتورة أو الفرع أو التاريخ...', en: 'Search by receipt #, branch, or date...', hi: 'रसीद संख्या, शाखा या तिथि द्वारा खोजें...');
  String get receiptNumberCol => _t(ar: 'رقم الفاتورة', en: 'Receipt #', hi: 'रसीद सं.');
  String get receiptDateCol => _t(ar: 'التاريخ والوقت', en: 'Date & Time', hi: 'दिनांक और समय');
  String get receiptAmountCol => _t(ar: 'قيمة المشتريات', en: 'Amount', hi: 'राशि');
  String get receiptStatusCol => _t(ar: 'النتيجة / الحالة', en: 'Status', hi: 'स्थिति');
  String get receiptStoreCol => _t(ar: 'الفرع / المتجر', en: 'Branch / Store', hi: 'शाखा / स्टोर');

  // ---------------------------------------------------------------------------
  // 6. Agent 3: Company & Products Catalog (تكويد الشركات والمنتجات)
  // ---------------------------------------------------------------------------
  String get catalogTitle => _t(ar: 'تكويد الشركات والمنتجات بالباركود (M3 Catalog)', en: 'Company & Product Barcode Catalog (M3)', hi: 'कंपनी और उत्पाद बारकोड सूची (M3)');
  String get catalogSubtitle => _t(
    ar: 'إدارة كتالوج الشركات والمنتجات السحابية الموحدة وتعيين الأكواد والباركودات',
    en: 'Manage cloud product catalogs, assign unique company codes & barcodes',
    hi: 'क्लाउड उत्पाद सूची प्रबंधित करें, कंपनी कोड और बारकोड असाइन करें',
  );
  String get card1CompanyRegTitle => _t(ar: '١. تسجيل وتكويد شركة جديدة', en: '1. Register New Company', hi: '1. नई कंपनी पंजीकृत करें');
  String get card2AddProductsTitle => _t(ar: '٢. إضافة وتكويد منتجات الشركات', en: '2. Add & Manage Products', hi: '2. उत्पाद जोड़ें और प्रबंधित करें');
  String get card3CatalogBrowserTitle => _t(ar: '٣. دليل الشركات والمنتجات المعتمدة', en: '3. Approved Companies & Products Directory', hi: '3. स्वीकृत कंपनियों और उत्पादों की सूची');
  String get tabManualAdd => _t(ar: 'إضافة يدوية', en: 'Manual Add', hi: 'मैन्युअल जोड़ें');
  String get tabSmartAiUpload => _t(ar: 'استيراد ذكي (Excel/CSV بالذكاء الاصطناعي)', en: 'Smart Import (AI Excel/CSV)', hi: 'स्मार्ट आयात (AI Excel/CSV)');
  String get tabLiveCatalog => _t(ar: 'الكتالوج المعتمد', en: 'Active Catalog', hi: 'सक्रिय सूची');
  String get companyNameField => _t(ar: 'اسم الشركة', en: 'Company Name', hi: 'कंपनी का नाम');
  String get companySlugField => _t(ar: 'كود الشركة الرقمي (Slug)', en: 'Company Numeric Code (Slug)', hi: 'कंपनी कोड (Slug)');
  String get productNameField => _t(ar: 'اسم المنتج', en: 'Product Name', hi: 'उत्पाद का नाम');
  String get barcodeField => _t(ar: 'الباركود (Barcode)', en: 'Barcode', hi: 'बारकोड');
  String get categoryField => _t(ar: 'التصنيف / الفئة', en: 'Category', hi: 'श्रेणी');
  String get priceField => _t(ar: 'السعر التقديري', en: 'Estimated Price', hi: 'अनुमानित मूल्य');
  String get saveCompanyBtn => _t(ar: 'تسجيل الشركة', en: 'Register Company', hi: 'कंपनी पंजीकृत करें');
  String get saveProductBtn => _t(ar: 'إضافة المنتج', en: 'Add Product', hi: 'उत्पाद जोड़ें');
  String get aiUploadHeading => _t(ar: 'التحليل والاستيراد الذكي لملفات الإكسيل', en: 'AI Smart Excel & CSV Ingestion', hi: 'एआई स्मार्ट एक्सेल/CSV विश्लेषण');
  String get aiUploadDesc => _t(
    ar: 'يقوم الذكاء الاصطناعي بالتعرف التلقائي على أعمدة اسم الصنف، الباركود، الفئة، والمجموعة الفرعية دون التقيد بترتيب محدد.',
    en: 'AI automatically detects columns for item names, barcodes, categories, and subcategories regardless of column order.',
    hi: 'एआई स्वचालित रूप से कॉलम के क्रम की परवाह किए बिना उत्पाद के नाम, बारकोड और श्रेणी का पता लगाता है।',
  );
  String get selectExcelFileBtn => _t(ar: 'اختيار ملف Excel أو CSV', en: 'Select Excel or CSV File', hi: 'Excel या CSV फ़ाइल चुनें');
  String get saveStagedProductsBtn => _t(ar: 'حفظ المنتجات في قاعدة البيانات', en: 'Save Products to Database', hi: 'उत्पादों को डेटाबेस में सहेजें');

  // ---------------------------------------------------------------------------
  // 7. Agent 4: Retail Chains & Branches (السلاسل والمنافذ)
  // ---------------------------------------------------------------------------
  String get retailChainsTitle => _t(ar: 'إدارة السلاسل والمنافذ (Retailers & Branches)', en: 'Retail Chains & Branches Management', hi: 'रिटेल चेन और स्टोर प्रबंधन');
  String get retailChainsSubtitle => _t(
    ar: 'تكويد سلاسل الهايبر ماركت (فتح الله، كارفور، سبينس...) وفروعها لربطها بالحملات والتقارير بدقة',
    en: 'Register hypermarket chains and branches to link them accurately to campaigns and AI verification',
    hi: 'हाइपरमार्केट चेन और शाखाओं को पंजीकृत करें ताकि उन्हें अभियानों और एआई सत्यापन से जोड़ा जा सके',
  );
  String get cardChainRegTitle => _t(ar: '١. تكويد سلسلة تجارية جديدة', en: '1. Register Retail Chain', hi: '1. नई रिटेल चेन पंजीकृत करें');
  String get cardBranchRegTitle => _t(ar: '٢. إضافة فرع للسلسلة', en: '2. Add Branch to Chain', hi: '2. चेन में नई शाखा जोड़ें');
  String get cardDirectoryTitle => _t(ar: 'دليل السلاسل والفروع المسجلة', en: 'Registered Chains & Branches Directory', hi: 'पंजीकृत चेन और शाखाओं की सूची');
  String get chainNameField => _t(ar: 'اسم السلسلة (مثال: كارفور مصر)', en: 'Chain Name (e.g. Carrefour)', hi: 'चेन का नाम (उदा. कैरेफोर)');
  String get chainSlugField => _t(ar: 'كود السلسلة (Slug)', en: 'Chain Code (Slug)', hi: 'चेन कोड (Slug)');
  String get branchNameField => _t(ar: 'اسم الفرع (مثال: فرع سيتي سنتر)', en: 'Branch Name (e.g. City Centre)', hi: 'शाखा का नाम (उदा. सिटी सेंटर)');
  String get branchCodeField => _t(ar: 'كود الفرع', en: 'Branch Code', hi: 'शाखा कोड');
  String get branchCityField => _t(ar: 'المدينة / المنطقة', en: 'City / Region', hi: 'शहर / क्षेत्र');
  String get branchAddressField => _t(ar: 'العنوان التفصيلي', en: 'Detailed Address', hi: 'विस्तृत पता');
  String get totalChainsCount => _t(ar: 'إجمالي السلاسل:', en: 'Total Chains:', hi: 'कुल चेन:');
  String get totalBranchesCount => _t(ar: 'إجمالي الفروع:', en: 'Total Branches:', hi: 'कुल शाखाएं:');

  // ---------------------------------------------------------------------------
  // 8. Agent 5: Invoices Log & Audit (سجل الفواتير والتدقيق)
  // ---------------------------------------------------------------------------
  String get invoicesAuditTitle => _t(ar: 'سجل الفواتير والتدقيق (Invoices Log)', en: 'Invoices Audit & Real-time Logs', hi: 'रसीद ऑडिट और रीयल-टाइम लॉग');
  String get invoicesAuditSubtitle => _t(
    ar: 'مراقبة وتدقيق كافة عمليات فحص الفواتير التي تمت عبر الذكاء الاصطناعي',
    en: 'Real-time monitoring and auditing of all AI-verified customer receipts',
    hi: 'एआई-सत्यापित ग्राहक रसीदों की रीयल-टाइम निगरानी और ऑडिटिंग',
  );
  String get ocrDetectedTextTitle => _t(ar: 'النص المقروء من الفاتورة (OCR Text)', en: 'Extracted OCR Receipt Text', hi: 'रसीद से निकाला गया OCR टेक्स्ट');
  String get approveInvoiceBtn => _t(ar: 'قبول يدوي واعتماد الفوز', en: 'Manual Approve & Grant Prize', hi: 'मैन्युअल स्वीकृति और पुरस्कार दें');
  String get rejectInvoiceBtn => _t(ar: 'رفض الفاتورة', en: 'Reject Invoice', hi: 'रसीद अस्वीकार करें');
  String get filterAccepted => _t(ar: 'المقبولة', en: 'Accepted', hi: 'स्वीकृत');
  String get filterRejected => _t(ar: 'المرفوضة', en: 'Rejected', hi: 'अस्वीकृत');
  String get filterPending => _t(ar: 'قيد المراجعة', en: 'Pending Review', hi: 'समीक्षाधीन');

  // ---------------------------------------------------------------------------
  // 9. Agent 6: Create & Edit Campaign (إنشاء حملة جديدة)
  // ---------------------------------------------------------------------------
  String get createCampaignTitle => _t(ar: 'إنشاء وتخصيص حملة ترويجية جديدة', en: 'Create & Configure Promotional Campaign', hi: 'नया प्रचार अभियान बनाएं और कॉन्फ़िगर करें');
  String get editCampaignTitle => _t(ar: 'تعديل بيانات الحملة وتخصيص الـ AI', en: 'Edit Campaign & AI Configuration', hi: 'अभियान और एआई सेटिंग्स संपादित करें');
  String get card1BasicInfoTitle => _t(ar: '١. البيانات الأساسية للحملة', en: '1. Basic Campaign Information', hi: '1. बुनियादी अभियान जानकारी');
  String get card1BasicInfoSubtitle => _t(ar: 'حدد اسم الحملة، الشركة المستهدفة، وشروط الإنفاق', en: 'Set campaign title, target sponsor, and spend requirements', hi: 'अभियान का नाम, कंपनी और न्यूनतम खर्च निर्धारित करें');
  String get card2ProductsScopeTitle => _t(ar: '٢. نطاق المنتجات المستهدفة', en: '2. Target Products & Scope', hi: '2. लक्षित उत्पाद और दायरा');
  String get card3RetailChainsTitle => _t(ar: '٣. السلاسل والمنافذ المعتمدة', en: '3. Authorized Retail Chains & Branches', hi: '3. अधिकृत रिटेल चेन और स्टोर');
  String get card4GiftsGameTitle => _t(ar: '٤. الهدايا ونوع اللعبة', en: '4. Prizes & Game Mechanics', hi: '4. उपहार और खेल का प्रकार');
  String get card5AiCustomizationTitle => _t(ar: '٥. تخصيص الذكاء الاصطناعي (AI Prompt & OCR)', en: '5. AI Prompt & Verification Settings', hi: '5. एआई प्रॉम्ट और सत्यापन सेटिंग्स');
  String get campaignNameField => _t(ar: 'اسم الحملة (مثال: مهرجان المراعي)', en: 'Campaign Name (e.g. Almarai Fest)', hi: 'अभियान का नाम (उदा. अलमराई फेस्ट)');
  String get targetCompanyField => _t(ar: 'الشركة الراعية المستهدفة', en: 'Target Sponsor Company', hi: 'लक्षित प्रायोजक कंपनी');
  String get minSpendField => _t(ar: 'الحد الأدنى للشراء المؤهل', en: 'Minimum Spend Requirement', hi: 'न्यूनतम खरीदारी राशि');
  String get selectGameTypeField => _t(ar: 'نوع اللعبة التفاعلية', en: 'Interactive Game Type', hi: 'गेम का प्रकार');
  String get submitCreateCampaignBtn => _t(ar: 'حفظ وتفعيل الحملة فوراً', en: 'Save & Launch Campaign', hi: 'अभियाن सहेजें और शुरू करें');

  // ---------------------------------------------------------------------------
  // 10. Agent 7: Company Gifts & Stock (هدايا الشركات)
  // ---------------------------------------------------------------------------
  String get giftsTitle => _t(ar: 'مخزون هدايا الشركات والجوائز', en: 'Company Prize Inventory & Stock', hi: 'कंपनी उपहार और पुरस्कार सूची');
  String get giftsSubtitle => _t(
    ar: 'إضافة وإدارة الهدايا والجوائز المتاحة لكل شركة وتحديد أوزان ونسب الفوز',
    en: 'Manage company promotional gift stocks and winning probability weights',
    hi: 'कंपनी उपहार स्टॉक और जीतने की संभावना प्रबंधित करें',
  );
  String get addGiftCardTitle => _t(ar: 'إضافة جائزة / هدية جديدة', en: 'Add New Gift / Reward', hi: 'नया उपहार / पुरस्कार जोड़ें');
  String get registeredGiftsTableTitle => _t(ar: 'قائمة الهدايا المسجلة للشركة', en: 'Registered Gifts for Company', hi: 'कंपनी के लिए पंजीकृत उपहार');
  String get giftNameField => _t(ar: 'اسم الهدية / الجائزة', en: 'Gift Name / Reward', hi: 'उपहार का नाम');
  String get giftQuantityField => _t(ar: 'الكمية المتاحة (المخزون)', en: 'Available Quantity (Stock)', hi: 'उपलब्ध मात्रा (स्टॉक)');
  String get giftWinProbabilityField => _t(ar: 'وزن / نسبة الفوز (Probability Weight)', en: 'Winning Probability Weight', hi: 'जीतने की संभावना (वेट)');
  String get giftDescriptionField => _t(ar: 'وصف الهدية وكيفية الاستلام', en: 'Reward Description & Redemption Terms', hi: 'उपहार का विवरण');

  // ---------------------------------------------------------------------------
  // 11. Agent 8: Game Types & Mechanics (أنواع الألعاب)
  // ---------------------------------------------------------------------------
  String get gameTypesTitle => _t(ar: 'أنواع الألعاب والمسابقات التفاعلية', en: 'Interactive Game Types & Mechanics', hi: 'इंटरैक्टिव खेल और प्रतियोगिताएं');
  String get gameTypesSubtitle => _t(
    ar: 'استعراض أنواع الألعاب المتاحة في المنظومة وطريقة عمل كل منها وتجربة العميل',
    en: 'Explore available gamification mechanics, prize animations, and customer flow',
    hi: 'उपलब्ध खेलों, पुरस्कार एनिमेशन और ग्राहक अनुभव का अन्वेषण करें',
  );
  String get gameWheelTitle => _t(ar: 'عجلة الحظ الدائرية', en: 'Spin the Wheel', hi: 'भाग्य का पहिया (Spin the Wheel)');
  String get gameWheelDesc => _t(
    ar: 'يقوم العميل بتدوير عجلة تحتوي على الهدايا المخصصة للحملة. تتوقف العجلة عشوائياً على إحدى الهدايا المتاحة ويفوز بها فوراً.',
    en: 'Customer spins an interactive wheel loaded with campaign gifts, landing on a winning reward.',
    hi: 'ग्राहक अभियान उपहारों से भरा एक पहिया घुमाता है और जीतने वाले पुरस्कार पर रुकता है।',
  );
  String get gameScratchTitle => _t(ar: 'امسح واربح الرقمية', en: 'Scratch & Win', hi: 'स्क्रैच करें और जीतें (Scratch & Win)');
  String get gameScratchDesc => _t(
    ar: 'يقوم العميل بخدش بطاقة رقمية تفاعلية لكشف الهدية المخفية تحتها بحركات السحب السلسة.',
    en: 'Customer rubs a digital scratch card with touch gestures to reveal the hidden reward.',
    hi: 'ग्राहक छिपे हुए पुरस्कार को उजागर करने के लिए डिजिटल कार्ड को स्क्रैच करता है।',
  );
  String get gameBoxTitle => _t(ar: 'الصندوق الغامض', en: 'Mystery Box', hi: 'रहस्यमयी बॉक्स (Mystery Box)');
  String get gameBoxDesc => _t(
    ar: 'يختار العميل أحد الصناديق الثلاثة المغلقة ليفتح الصندوق مع تأثيرات بصرية وصوتية مبهجة.',
    en: 'Customer picks one of three mystery gift boxes to unveil the surprise gift.',
    hi: 'ग्राहक सरप्राइज गिफ्ट पाने के लिए तीन रहस्यमयी बॉक्सों में से एक चुनता है।',
  );
  String get gameDirectGiftTitle => _t(ar: 'الهدية الفورية المباشرة', en: 'Direct Instant Gift', hi: 'प्रत्यक्ष तत्काल उपहार (Direct Instant Gift)');
  String get gameDirectGiftSubtitle => _t(
    ar: 'هدية ترويجية ثابتة ومضمونة لكل متسوق مستوفٍ للشروط',
    en: 'Guaranteed designated promotional gift for every qualified shopper',
    hi: 'प्रत्येक योग्य खरीदार के लिए गारंटीकृत प्रचार उपहार',
  );
  String get gameDirectGiftDesc => _t(
    ar: 'يحصل العميل على هدية ترويجية محددة فور التحقق من استيفاء الفاتورة للشروط دون الحاجة للدخول في قرعة أو سحب عشوائي.',
    en: 'Customer instantly receives a designated promotional gift upon receipt verification without any random draw or chance game.',
    hi: 'रसीद सत्यापन के बाद ग्राहक को बिना किसी यादृच्छिक ड्रॉ के तुरंत एक निर्दिष्ट उपहार मिलता है।',
  );
  String get claimDirectGift => _t(ar: 'تسليم الهدية للعميل', en: 'Handover Gift to Customer', hi: 'ग्राहक को उपहार सौंपें');
  String get directGiftQuantity => _t(ar: 'الكمية المستحقة', en: 'Claim Quantity', hi: 'हकदार मात्रा');
  String get testGameAction => _t(ar: 'تجربة اللعبة (ديمو تفاعلي)', en: 'Play Game (Live Demo)', hi: 'गेम टेस्ट करें (लाइव डेमो)');
  String get demoModeBannerTitle => _t(ar: 'وضع المحاكاة والتجربة الحية (Demo Simulation)', en: 'Live Interactive Simulation (Demo Mode)', hi: 'लाइव इंटरैक्टिव सिमुलेशन (डेमो मोड)');
  String get demoModeBannerDesc => _t(
    ar: 'هذه محاكاة حية لطريقة ظهور وتفاعل اللعبة مع العميل دون التأثير على رصيد المخزون الفعلي.',
    en: 'This is a live simulation of the customer gameplay experience without affecting live prize inventory.',
    hi: 'यह वास्तविक स्टॉक को प्रभावित किए बिना ग्राहक अनुभव का एक लाइव सिमुलेशन है।',
  );
  String get demoExitBtn => _t(ar: 'إنهاء الديمو والعودة', en: 'Exit Demo', hi: 'डेमो समाप्त करें');
  String get playAgainDemo => _t(ar: 'تجربة مرة أخرى 🔄', en: 'Try Again 🔄', hi: 'पुनः प्रयास करें 🔄');
  String get mysteryBoxInstruction => _t(
    ar: 'المس أحد الصناديق الثلاثة لفتحه واكتشاف هديتك المفاجئة!',
    en: 'Tap one of the three mystery gift boxes to open it and reveal your surprise reward!',
    hi: 'अपना सरप्राइज उपहार प्रकट करने के लिए तीन में से किसी एक बॉक्स पर टैप करें!',
  );
  String get mysteryBoxSubtitle => _t(
    ar: 'الصندوق الغامض — اختر واكشف جائزتك',
    en: 'Mystery Box — Choose & Reveal Reward',
    hi: 'रहस्यमयी बॉक्स — चुनें और जीतें',
  );
  String get directGiftDemoSuccess => _t(
    ar: 'تمت محاكاة تسليم الهدية بنجاح!',
    en: 'Gift handover simulated successfully!',
    hi: 'उपहार सौंपने का सिमुलेशन सफल रहा!',
  );

  // ---------------------------------------------------------------------------
  // 12. Client Portal / Promoter Flow
  // ---------------------------------------------------------------------------
  String get clientWelcomeTitle => _t(ar: 'أهلاً بك في العرض الترويجي', en: 'Welcome to the Promotion', hi: 'प्रचार अभियान में आपका स्वागत है');
  String get uploadReceiptPrompt => _t(ar: 'التقط صورة الفاتورة للمشاركة في السحب', en: 'Take a photo of your receipt to participate', hi: 'भाग लेने के लिए अपनी रसीद की फोटो लें');
  String get scanReceiptBtn => _t(ar: 'تصوير الفاتورة الآن', en: 'Scan Receipt Now', hi: 'रसीद स्कैन करें');
  String get analyzingReceiptMsg => _t(ar: 'جاري فحص الفاتورة والتحقق بالذكاء الاصطناعي...', en: 'AI is analyzing and verifying your receipt...', hi: 'एआई आपकी रसीद का सत्यापन कर रहा है...');
  String get congratulationsWon => _t(ar: 'مبروك! لقد فزت بجائزة قيمة!', en: 'Congratulations! You won a prize!', hi: 'बधाई हो! आपने एक शानदार उपहार जीता है!');
  String get claimPrizeBtn => _t(ar: 'استلام الجائزة من البروموتر', en: 'Claim Prize from Promoter', hi: 'प्रमोटर से पुरस्कार प्राप्त करें');

  // ---------------------------------------------------------------------------
  // 13. Enterprise Invoices Log & Audit (سجل الفواتير وتدقيق المنتجات)
  // ---------------------------------------------------------------------------
  String get allCampaigns => _t(ar: 'كافة الحملات', en: 'All Campaigns', hi: 'सभी अभियान');
  String get filterByCampaign => _t(ar: 'تصفية حسب الحملة / الفعالية', en: 'Filter by Campaign / Event', hi: 'अभियान / इवेंट द्वारा फ़िल्टर करें');
  String get filterByDate => _t(ar: 'نطاق التاريخ', en: 'Date Range', hi: 'दिनांक सीमा');
  String get filterToday => _t(ar: 'اليوم', en: 'Today', hi: 'आज');
  String get filterLast7Days => _t(ar: 'آخر 7 أيام', en: 'Last 7 Days', hi: 'पिछले 7 दिन');
  String get filterThisMonth => _t(ar: 'هذا الشهر', en: 'This Month', hi: 'इस महीने');
  String get filterCustomDate => _t(ar: 'مخصص...', en: 'Custom...', hi: 'कस्टम...');
  String get searchReceiptPlaceholder => _t(
    ar: 'ابحث برقم الفاتورة، اسم العميل، الهاتف، أو الفرع...',
    en: 'Search by receipt #, customer, phone, or branch...',
    hi: 'रसीद संख्या, ग्राहक, फोन या शाखा द्वारा खोजें...',
  );
  String get totalReceiptsCount => _t(ar: 'إجمالي الفواتير المفحوصة', en: 'Total Invoices Audited', hi: 'कुल ऑडिट की गई रसीदें');
  String get totalPromotionalSales => _t(ar: 'إجمالي مبيعات منتجات العرض', en: 'Total Promotional Sales', hi: 'कुल प्रचार बिक्री');
  String get totalItemsPurchased => _t(ar: 'إجمالي الأصناف المستخرجة', en: 'Total Items Extracted', hi: 'कुल निकाले गए उत्पाद');
  String get avgAiSpeed => _t(ar: 'متوسط سرعة الفحص (AI)', en: 'Avg AI Verification Speed', hi: 'औसत एआई सत्यापन गति');
  String get viewReceiptProducts => _t(ar: 'عرض الأصناف والباركود', en: 'View Items & Barcodes', hi: 'उत्पाद और बारकोड देखें');
  String get viewOriginalPhoto => _t(ar: 'معاينة صورة الفاتورة', en: 'View Receipt Photo', hi: 'रसीद फोटो देखें');
  String get exportCsvBtn => _t(ar: 'تصدير البيانات (CSV)', en: 'Export Data (CSV)', hi: 'डेटा निर्यात करें (CSV)');
  String get productNameCol => _t(ar: 'اسم المنتج', en: 'Product Name', hi: 'उत्पाद का नाम');
  String get barcodeCol => _t(ar: 'الباركود', en: 'Barcode', hi: 'बारकोड');
  String get quantityCol => _t(ar: 'الكمية', en: 'Qty', hi: 'मात्रा');
  String get unitPriceCol => _t(ar: 'السعر', en: 'Price', hi: 'मूल्य');
  String get totalPriceCol => _t(ar: 'الإجمالي', en: 'Total', hi: 'कुल');
  String get itemCategoryCol => _t(ar: 'حالة الصنف', en: 'Item Status', hi: 'उत्पाद स्थिति');
  String get includedInPromo => _t(ar: 'مشمول بالعرض 🎯', en: 'Promo Target 🎯', hi: 'प्रचार में शामिल 🎯');
  String get generalItem => _t(ar: 'صنف عام 🛒', en: 'General Item 🛒', hi: 'सामान्य उत्पाद 🛒');
  String get noBarcodesAvailable => _t(ar: 'غير مسجل بالكتالوج', en: 'Not In Catalog', hi: 'कैटलॉग में नहीं');
  String get receiptDetailsTitle => _t(ar: 'تفاصيل الفاتورة والأصناف', en: 'Receipt Details & Items', hi: 'रसीद विवरण और उत्पाद');
  String get receiptImageDialogTitle => _t(ar: 'صورة الفاتورة المرفوعة', en: 'Uploaded Receipt Photo', hi: 'अपलोड की गई रसीद फोटो');
  String get copyReceiptNumber => _t(ar: 'نسخ رقم الفاتورة', en: 'Copy Receipt Number', hi: 'रसीद संख्या कॉपी करें');
  String get receiptNumberCopied => _t(ar: 'تم نسخ رقم الفاتورة بنجاح', en: 'Receipt number copied', hi: 'रसीद संख्या कॉपी की गई');
  String get itemsCountLabel => _t(ar: 'أصناف', en: 'items', hi: 'उत्पाद');
  String get clearFiltersBtn => _t(ar: 'مسح الفلاتر', en: 'Clear Filters', hi: 'फ़िल्टर साफ़ करें');
  String get noMatchingInvoices => _t(ar: 'لا توجد فواتير مطابقة لمعايير البحث الحالية.', en: 'No invoices match your current filter criteria.', hi: 'आपके वर्तमान फ़िल्टर मानदंडों से कोई रसीद मेल नहीं खाती।');
  String get companyField => _t(ar: 'الشركة', en: 'Company', hi: 'कंपनी');
  String get retailChainField => _t(ar: 'السلسلة التجارية', en: 'Retail Chain', hi: 'रिटेल चेन');
  String get branchField => _t(ar: 'الفرع', en: 'Branch', hi: 'शाखा');
  String get customerNameField => _t(ar: 'اسم العميل', en: 'Customer Name', hi: 'ग्राहक का नाम');
  String get customerPhoneField => _t(ar: 'رقم الهاتف', en: 'Phone Number', hi: 'फ़ोन नंबर');

  // ---------------------------------------------------------------------------
  // Sound & Audio Effects (Material 3 & Google Sound System)
  // ---------------------------------------------------------------------------
  String get soundEffects => _t(ar: 'المؤثرات الصوتية', en: 'Sound Effects', hi: 'ध्वनि प्रभाव');
  String get soundEnabled => _t(ar: 'الأصوات مفعلة', en: 'Sound On', hi: 'ध्वनि चालू');
  String get soundMuted => _t(ar: 'كتم الأصوات', en: 'Mute Sound', hi: 'ध्वनि बंद');
  String get previewSound => _t(ar: 'معاينة الصوت', en: 'Preview Sound', hi: 'ध्वनि पूर्वावलोकन');
  String get volumeLevel => _t(ar: 'مستوى الصوت', en: 'Volume Level', hi: 'ध्वनि स्तर');
  String get gameSoundSettings => _t(ar: 'إعدادات صوتيات الألعاب', en: 'Game Audio Settings', hi: 'गेम ऑडियो सेटिंग्स');

  // ---------------------------------------------------------------------------
  // 14. Dual Links & Company Manager Portal
  // ---------------------------------------------------------------------------
  String get copyPromoterLink => _t(
    ar: 'نسخ رابط العميل / البروموتر',
    en: 'Copy Promoter/Client Link',
    hi: 'प्रमोटر / ग्राहक लिंक कॉपी करें',
  );
  String get copyManagerPortalLink => _t(
    ar: 'نسخ رابط بوابة مدير الشركة',
    en: 'Copy Company Manager Link',
    hi: 'कंपनी प्रबंधक पोर्टल लिंक कॉपी करें',
  );
  String get previewManagerPortal => _t(
    ar: 'معاينة بوابة المدير',
    en: 'Preview Manager Portal',
    hi: 'प्रबंधक पोर्टल पूर्वावलोकन',
  );
  String get companyManagerPortalTitle => _t(
    ar: 'بوابة مدير وشريك الشركة',
    en: 'Company Manager & Partner Portal',
    hi: 'कंपनी प्रबंधक और भागीदार पोर्टल',
  );
  String get companyPortalSubtitle => _t(
    ar: 'لوحة المتابعة التنفيذية للتقارير والتحليلات وسجل الفواتير',
    en: 'Executive Dashboard for Analytics, Reports & Audited Invoices',
    hi: 'एनालिटिक्स, रिपोर्ट और ऑडिट किए गए चालानों के लिए कार्यकारी डैशबोर्ड',
  );
  String get companyScopeBanner => _t(
    ar: 'عرض تنفيذي مخصص ومحصور لحملات وفواتير شركتكم فقط',
    en: 'Dedicated executive view scoped exclusively to your company campaigns & invoices',
    hi: 'विशेष रूप से केवल आपकी कंपनी के अभियानों और चालानों के लिए समर्पित कार्यकारी दृश्य',
  );
  String get companyAllCampaigns => _t(
    ar: 'جميع حملات وفعاليات الشركة',
    en: 'All Company Campaigns & Events',
    hi: 'कंपनी के सभी अभियान और कार्यक्रम',
  );
  String get promoterLinkCopied => _t(
    ar: 'تم نسخ رابط البروموتر والعميل بنجاح',
    en: 'Promoter & Client link copied successfully',
    hi: 'प्रमोटر और ग्राहक लिंक सफलतापूर्वक कॉपी किया गया',
  );
  String get managerPortalLinkCopied => _t(
    ar: 'تم نسخ رابط بوابة مدير الشركة بنجاح',
    en: 'Company Manager Portal link copied successfully',
    hi: 'कंपनी प्रबंधक पोर्टल लिंक सफलतापूर्वक कॉपी किया गया',
  );

  // ---------------------------------------------------------------------------
  // 15. Authentication & System Sign In (تسجيل الدخول والنظام)
  // ---------------------------------------------------------------------------
  String get authPortalSubtitle => _t(
    ar: 'بوابة تسجيل دخول مسؤولي ومروجي النظام',
    en: 'System Administrators & Promoters Portal',
    hi: 'सिस्टम व्यवस्थापक और प्रमोटर पोर्टल',
  );
  String get authSignInTitle => _t(
    ar: 'تسجيل الدخول للنظام',
    en: 'System Sign In',
    hi: 'सिस्टम में लॉगिन करें',
  );
  String get authSignInSubtitle => _t(
    ar: 'منظومة Switch Point الذكية للترويج والتحقق',
    en: 'Switch Point Intelligent Promotion & AI Verification Platform',
    hi: 'स्विच पॉइंट स्मार्ट प्रचार और एआई सत्यापन मंच',
  );
  String get authEmailLabel => _t(
    ar: 'البريد الإلكتروني',
    en: 'Email Address',
    hi: 'ईमेल पता',
  );
  String get authEmailValidation => _t(
    ar: 'يرجى إدخال البريد الإلكتروني',
    en: 'Please enter your email address',
    hi: 'कृपया अपना ईमेल पता दर्ज करें',
  );
  String get authPasswordLabel => _t(
    ar: 'كلمة المرور',
    en: 'Password',
    hi: 'पासवर्ड',
  );
  String get authPasswordValidation => _t(
    ar: 'يرجى إدخال كلمة المرور',
    en: 'Please enter your password',
    hi: 'कृपया अपना पासवर्ड दर्ज करें',
  );
  String get authSignInBtn => _t(
    ar: 'دخول الحساب',
    en: 'Sign In',
    hi: 'साइन इन करें',
  );
  String get authQuickDemoBtn => _t(
    ar: 'دخول تجريبي سريع (تخطي التحقق)',
    en: 'Quick Demo Sign In (Bypass Auth)',
    hi: 'त्वरित डेमो लॉगिन (सत्यापन छोड़ें)',
  );
  String get authSuperAdminBtn => _t(
    ar: 'لوحة تحكم المشرف (Admin)',
    en: 'Super Admin Dashboard',
    hi: 'सुपर व्यवस्थापक डैशबोर्ड (Admin)',
  );
  String get authSuperAdminTooltip => _t(
    ar: 'لوحة التحكم الفائقة للمشرفين',
    en: 'Super Administrator Control Panel',
    hi: 'सुपर व्यवस्थापक नियंत्रण कक्ष',
  );
  String get authFailedMsg => _t(
    ar: 'فشل تسجيل الدخول، يرجى التحقق من صحة البيانات',
    en: 'Authentication failed. Please verify your credentials.',
    hi: 'प्रमाणीकरण विफल रहा। कृपया अपने क्रेडेंशियल्स की जांच करें।',
  );

  // ---------------------------------------------------------------------------
  // 16. AI Receipt Validation Screen & Operations
  // ---------------------------------------------------------------------------
  String get validationScreenSubtitle => _t(
    ar: 'شاشة فحص وتدقيق الفواتير بالذكاء الاصطناعي',
    en: 'AI Receipt Audit & Intelligent Verification Screen',
    hi: 'एआई रसीद ऑडिट और स्मार्ट सत्यापन स्क्रीन',
  );
  String get invoicesLogTooltip => _t(
    ar: 'سجل الفواتير والتدقيق',
    en: 'Invoices Audit Log',
    hi: 'रसीद ऑडिट लॉग',
  );
  String get signOutTooltip => _t(
    ar: 'تسجيل الخروج',
    en: 'Sign Out',
    hi: 'लॉग आउट करें',
  );
  String get receiptAuditTitle => _t(
    ar: 'فحص وتدقيق الفاتورة',
    en: 'Receipt Audit & Verification',
    hi: 'रसीद ऑडिट और सत्यापन',
  );
  String get receiptAuditSubtitle => _t(
    ar: 'التقط الفاتورة وسيقوم الذكاء الاصطناعي بالتحقق الفوري',
    en: 'Capture the receipt; AI will instantly verify terms and products',
    hi: 'रसीद की तस्वीर लें; एआई तुरंत शर्तों की पुष्टि करेगा',
  );
  String get captureReceiptBtn => _t(
    ar: 'التقاط صورة الفاتورة بالكاميرا',
    en: 'Capture Receipt Photo with Camera',
    hi: 'कैमरे से रसीद की तस्वीर लें',
  );
  String get auditingAndStartingGame => _t(
    ar: 'تدقيق الفاتورة وبدء اللعبة 🎁',
    en: 'Audit Receipt & Launch Game 🎁',
    hi: 'रसीद ऑडिट करें और खेल शुरू करें 🎁',
  );
  String get auditingProgressText => _t(
    ar: 'جاري التحليل والتدقيق الذكي...',
    en: 'AI analyzing and verifying receipt...',
    hi: 'एआई रसीद का विश्लेषण और सत्यापन कर रहा है...',
  );
  String get noActiveEventError => _t(
    ar: 'لا يوجد أي حملة (Event) مفعلة حالياً.',
    en: 'No active promotional campaign found at this moment.',
    hi: 'वर्तमान में कोई सक्रिय प्रचार अभियान नहीं मिला।',
  );
  String get systemNoticeAlert => _t(
    ar: 'تنبيه النظام',
    en: 'System Notice',
    hi: 'सिस्टम सूचना',
  );
  String get processReceiptError => _t(
    ar: 'حدث خطأ أثناء معالجة الفاتورة',
    en: 'An error occurred while processing the receipt',
    hi: 'रसीद संसाधित करते समय एक त्रुटि हुई',
  );

  // ---------------------------------------------------------------------------
  // 17. Receipt Validation Dialog & Unmet Conditions
  // ---------------------------------------------------------------------------
  String get dialogAuditedReceiptDetails => _t(
    ar: 'بيانات الفاتورة المفحوصة:',
    en: 'Audited Receipt Details:',
    hi: 'जांच की गई रसीद का विवरण:',
  );
  String get dialogReceiptNumberLabel => _t(
    ar: 'رقم الفاتورة:',
    en: 'Receipt #:',
    hi: 'रसीद संख्या:',
  );
  String get dialogStoreChainLabel => _t(
    ar: 'المتجر:',
    en: 'Store Outlet:',
    hi: 'स्टोर आउटलेट:',
  );
  String get dialogDateLabel => _t(
    ar: 'التاريخ:',
    en: 'Date:',
    hi: 'तारीख:',
  );
  String get dialogQualifyingSpendLabel => _t(
    ar: 'قيمة منتجات العرض:',
    en: 'Qualifying Spend:',
    hi: 'पात्र खरीद मूल्य:',
  );
  String get dialogUnmetConditionsTitle => _t(
    ar: 'قائمة الشروط غير المستوفاة',
    en: 'Unmet Conditions List',
    hi: 'अधूरी शर्तें सूची',
  );
  String get dialogCloseBtn => _t(
    ar: 'حسناً / إغلاق الفاتورة',
    en: 'OK / Dismiss Receipt',
    hi: 'ठीक है / बंद करें',
  );
  String get dialogConditionUnmet => _t(
    ar: 'شرط غير مستوفى',
    en: 'Condition Not Met',
    hi: 'शर्त पूरी नहीं हुई',
  );
  String get dialogSpendConditionTitle => _t(
    ar: 'الحد الأدنى لقيمة المشتريات',
    en: 'Minimum Spend Requirement',
    hi: 'न्यूनतम खरीद आवश्यकता',
  );
  String get dialogChainConditionTitle => _t(
    ar: 'السلسلة التجارية والفرع المعتمد',
    en: 'Authorized Retail Chain & Branch',
    hi: 'अधिकृत रिटेल चेन और शाखा',
  );
  String get dialogProductsConditionTitle => _t(
    ar: 'المنتجات المؤهلة للعرض',
    en: 'Eligible Campaign Products',
    hi: 'पात्र अभियान उत्पाद',
  );
  String get dialogDateConditionTitle => _t(
    ar: 'تاريخ الشراء وفترة الحملة',
    en: 'Purchase Date & Campaign Period',
    hi: 'खरीद तिथि और अभियान अवधि',
  );
  String get dialogAuditResultTitle => _t(
    ar: 'نتيجة التدقيق والتحقق',
    en: 'Audit & Verification Result',
    hi: 'ऑडिट और सत्यापन परिणाम',
  );
  String get dialogAuditResultFallback => _t(
    ar: 'الفاتورة غير مطابقة للشروط والأحكام الخاصة بالعرض.',
    en: 'The receipt does not meet the terms and conditions of this promotion.',
    hi: 'रसीद इस प्रचार के नियमों और शर्तों को पूरा नहीं करती है।',
  );

  // ---------------------------------------------------------------------------
  // 18. Client & Promoter Customer Submission Portal
  // ---------------------------------------------------------------------------
  String get clientPortalSubtitle => _t(
    ar: 'بوابة التحقق الذكي للعملاء والبروموتر',
    en: 'Intelligent Verification Portal for Customers & Promoters',
    hi: 'ग्राहकों और प्रमोटरों के लिए स्मार्ट सत्यापन पोर्टल',
  );
  String get campaignOffersTitle => _t(
    ar: 'عروض وحملات الشركات',
    en: 'Company Campaigns & Special Offers',
    hi: 'कंपनी अभियान और विशेष ऑफ़र',
  );
  String get customerNameOptional => _t(
    ar: 'اسم العميل (اختياري)',
    en: 'Customer Name (Optional)',
    hi: 'ग्राहक का नाम (वैकल्पिक)',
  );
  String get customerPhoneLabel => _t(
    ar: 'رقم هاتف العميل (للتواصل واستلام الجائزة)',
    en: 'Customer Phone Number (For prize claim)',
    hi: 'ग्राहक का फ़ोन नंबर (पुरस्कार प्राप्त करने के लिए)',
  );
  String get captureReceiptAction => _t(
    ar: 'التقاط صورة الفاتورة (كاميرا)',
    en: 'Capture Receipt Photo (Camera)',
    hi: 'रसीद की फोटो खींचें (कैमरा)',
  );
  String get pickFromGalleryAction => _t(
    ar: 'رفع من المعرض (الملفات)',
    en: 'Upload from Gallery (Files)',
    hi: 'गैलरी से अपलोड करें (फ़ाइलें)',
  );
  String get auditReceiptActionBtn => _t(
    ar: 'فحص وتدقيق الفاتورة بالذكاء الاصطناعي',
    en: 'Verify Receipt with AI',
    hi: 'एआई के साथ रसीद सत्यापित करें',
  );
  String get participationTermsTitle => _t(
    ar: 'شروط المشاركة في العرض',
    en: 'Terms & Conditions of Participation',
    hi: 'भागीदारी के नियम और शर्तें',
  );
  String get loadingCampaignData => _t(
    ar: 'جاري تحميل بيانات الحملة...',
    en: 'Loading campaign data...',
    hi: 'अभियान डेटा लोड हो रहा है...',
  );
  String get allBranchesAllowed => _t(
    ar: 'كافة الفروع معتمدة',
    en: 'All branches authorized',
    hi: 'सभी शाखाएं अधिकृत हैं',
  );
  String get minSpendPrefix => _t(
    ar: 'الحد الأدنى للمشاركة:',
    en: 'Minimum spend:',
    hi: 'न्यूनतम खरीद:',
  );
  String get uploadReceiptInstruction => _t(
    ar: 'قم برفع صورة فاتورة الشراء للحصول على فرص فوز فورية بأحد جوائزنا!',
    en: 'Upload your purchase receipt photo for instant chances to win exciting prizes!',
    hi: 'रोमांचक पुरस्कार जीतने के त्वरित अवसरों के लिए अपनी खरीद रसीद फोटो अपलोड करें!',
  );

  // ---------------------------------------------------------------------------
  // 19. AI Campaign Prompt & Rules Assistant (مساعد الذكاء الاصطناعي للحملات)
  // ---------------------------------------------------------------------------
  String get aiCampaignAssistantTitle => _t(
    ar: 'مساعد الذكاء الاصطناعي لصياغة شروط المهرجان',
    en: 'AI Campaign Idea & Rules Assistant',
    hi: 'एआई अभियान विचार और नियम सहायक',
  );
  String get aiCampaignAssistantSubtitle => _t(
    ar: 'اكتب فكرة العرض بحرية وسيقوم الذكاء الاصطناعي بهيكلة قواعد التدقيق فورياً',
    en: 'Type your promotional offer freely in natural language; AI will format audit rules instantly',
    hi: 'अपनी प्रचार पेशकश को स्वाभाविक भाषा में लिखें; एआई तुरंत ऑडिट नियम तैयार करेगा',
  );
  String get aiCampaignIdeaHint => _t(
    ar: 'اكتب فكرة المهرجان أو شروط العرض هنا بحرية... مثال: عند شراء أي عبوة اسبراي ريكسونا أو أكس يحصل العميل على قسيمة 50 ج.م، وعند شراء كلير 360 مل يحصل على كلير 90 مل هدية، وإذا اشترى قطعتين تريزمي يحصل على عبوة تريزمي 250 مل هدية...',
    en: 'Write your promotional campaign idea or conditions here freely... e.g., Buy 1 Rexona/Axe spray get 50 EGP voucher, Buy Clear 360ml get Clear 90ml free gift, Buy 2 Tresemme get Tresemme 250ml free...',
    hi: 'अपने प्रचार अभियान का विचार या शर्तें यहां स्वतंत्र रूप से लिखें... जैसे, 1 रेक्सोना/एक्स स्प्रे खरीदें और 50 ईजीपी वाउचर पाएं, क्लीयर 360 मिली खरीदें और क्लीयर 90 मिली मुफ़्त उपहार पाएं...',
  );
  String get aiGenerateRulesBtn => _t(
    ar: 'توليد وتنسيق قواعد الفحص بالذكاء الاصطناعي',
    en: 'Generate & Structure Rules with AI',
    hi: 'एआई के साथ नियम बनाएं और व्यवस्थित करें',
  );
  String get aiGeneratingRulesLoading => _t(
    ar: 'جاري صياغة وهيكلة شروط العرض بالذكاء الاصطناعي...',
    en: 'Analyzing campaign idea and structuring rules with AI...',
    hi: 'एआई के साथ अभियान विचार का विश्लेषण और नियमों की संरचना की जा रही है...',
  );
  String get aiValidationSummaryHeader => _t(
    ar: '📋 ملخص منطق التدقيق الذي سيطبقه الذكاء الاصطناعي على الفواتير',
    en: '📋 AI Receipt Audit Logic & Rules Summary',
    hi: '📋 एआई रसीद ऑडिट तर्क और नियम सारांश',
  );
  String get aiPromotionalRulesListTitle => _t(
    ar: 'قواعد العروض والجوائز المستخلصة',
    en: 'Extracted Promotional Rules & Rewards',
    hi: 'निकाले गए प्रचार नियम और पुरस्कार',
  );
  String get voucherRewardLabel => _t(
    ar: 'قسيمة مشتريات',
    en: 'Shopping Voucher',
    hi: 'शॉपिंग वाउचर',
  );
  String get freeProductRewardLabel => _t(
    ar: 'هدية عينية مجانية',
    en: 'Free Gift Item',
    hi: 'मुफ़्त उपहार वस्तु',
  );
  String get gameSpinRewardLabel => _t(
    ar: 'دورة سحب / لعبة',
    en: 'Game Spin Chance',
    hi: 'गेम स्पिन का अवसर',
  );
  String get multipliersAllowedLabel => _t(
    ar: 'مضاعفة الهدايا مع زيادة الكمية',
    en: 'Multipliers active (more qty = more gifts)',
    hi: 'गुणक सक्रिय (अधिक मात्रा = अधिक उपहार)',
  );
  String get clearAiSummaryBtn => _t(
    ar: 'إعادة الصياغة / مسح',
    en: 'Reset / Clear',
    hi: 'रीसेट / साफ़ करें',
  );
  String get presetIdea1 => _t(
    ar: '🎁 اشتري عبوة كبيرة واحصل على عبوة صغيرة هدية',
    en: '🎁 Buy large pack, get small pack free',
    hi: '🎁 बड़ा पैक खरीदें, छोटा पैक मुफ़्त पाएं',
  );
  String get presetIdea2 => _t(
    ar: '🎟️ اشتري أي اسبراي واحصل على قسيمة 50 ج.م',
    en: '🎟️ Buy any spray, get 50 EGP voucher',
    hi: '🎟️ कोई भी स्प्रे खरीदें, 50 ईजीपी वाउचर पाएं',
  );
  String get presetIdea3 => _t(
    ar: '✨ اشتري قطعتين واحصل على قطعة ثالثة مجاناً',
    en: '✨ Buy 2 items, get 3rd item free',
    hi: '✨ 2 वस्तुएं खरीदें, तीसरी वस्तु मुफ़्त पाएं',
  );
  String get presetIdea4 => _t(
    ar: '🎟️ عرض الفاوتشر المتدرج (اسبراي ورول أون)',
    en: '🎟️ Tiered Voucher Offer (Sprays & Roll-ons)',
    hi: '🎟️ स्तरीय वाउचर ऑफ़र (स्प्रे और रोल-ऑन)',
  );
  String get aiScanReceiptTemplate => _t(
    ar: 'استخراج بصمة البونة والفرع بالذكاء الاصطناعي',
    en: 'AI Scan Receipt & Extract Branch Signature',
    hi: 'एआई रसीद स्कैन और शाखा हस्ताक्षर निकालें',
  );
  String get aiScanReceiptTemplateSub => _t(
    ar: 'قم برفع أو تصوير بونة الفاتورة لاستخراج السلسلة والفرع وكود المتجر ونمط الباركود آلياً',
    en: 'Upload or snap a sample receipt to auto-extract chain, branch, store code, and barcode pattern',
    hi: 'श्रृंखला, शाखा, स्टोर कोड और बारकोड पैटर्न को स्वतः निकालने के लिए रसीद अपलोड करें',
  );
  String get uploadReceiptSampleBtn => _t(
    ar: 'رفع صورة بونة الفاتورة',
    en: 'Upload Sample Receipt',
    hi: 'नमूना रसीद अपलोड करें',
  );
  String get analyzingReceiptSignature => _t(
    ar: 'جاري تحليل بصمة البونة ونظام الكاشير POS بالذكاء الاصطناعي...',
    en: 'Analyzing receipt signature & POS cashier system via AI...',
    hi: 'एआई के माध्यम से रसीद हस्ताक्षर और पीओएस कैशियर सिस्टम का विश्लेषण...',
  );
  String get signatureExtractedSuccess => _t(
    ar: 'تم استخراج بصمة البونة والفرع بنجاح',
    en: 'Receipt & Branch Signature Extracted Successfully',
    hi: 'रसीद और शाखा हस्ताक्षर सफलतापूर्वक निकाला गया',
  );
  String get saveChainAndBranchWithSignature => _t(
    ar: '💾 حفظ واعتماد السلسلة والفرع بالبصمة الذكية',
    en: '💾 Save & Verify Chain & Branch with Smart Signature',
    hi: '💾 स्मार्ट हस्ताक्षर के साथ श्रृंखला और शाखा सहेजें और सत्यापित करें',
  );
  String get posStoreId => _t(
    ar: 'كود المتجر في الـ POS',
    en: 'POS Store ID',
    hi: 'पीओएस स्टोर आईडी',
  );
  String get receiptBarcodePattern => _t(
    ar: 'نمط وهيكل رقم الفاتورة والباركود',
    en: 'Receipt & Barcode Pattern',
    hi: 'रसीद और बारकोड पैटर्न',
  );
  String get headerKeywordsLabel => _t(
    ar: 'الكلمات الدلالية لرأس البونة',
    en: 'Header Keywords',
    hi: 'शीर्षक कीवर्ड',
  );
  String get hasSmartSignatureBadge => _t(
    ar: 'بصمة ذكية معتمدة',
    en: 'Verified Smart Signature',
    hi: 'सत्यापित स्मार्ट हस्ताक्षर',
  );
  String get linkWithExistingChain => _t(
    ar: 'ربط بسلسلة تجارية مسجلة',
    en: 'Link to Existing Retail Chain',
    hi: 'मौजूदा खुदरा श्रृंखला से लिंक करें',
  );
  String get createNewChain => _t(
    ar: 'إنشاء سلسلة تجارية جديدة',
    en: 'Create New Retail Chain',
    hi: 'नई खुदरा श्रृंखला बनाएं',
  );
  String get confidenceScoreLabel => _t(
    ar: 'نسبة الدقة',
    en: 'Confidence',
    hi: 'सटीकता',
  );

  // Admin Auth & Security
  String get rememberMe => _t(
    ar: 'تذكر بيانات الدخول',
    en: 'Remember Me',
    hi: 'मुझे याद रखें',
  );
  String get signOutBtn => _t(
    ar: 'تسجيل الخروج',
    en: 'Sign Out',
    hi: 'साइन आउट',
  );
  String get confirmSignOutTitle => _t(
    ar: 'تأكيد تسجيل الخروج',
    en: 'Confirm Sign Out',
    hi: 'साइन आउट की पुष्टि करें',
  );
  String get confirmSignOutMsg => _t(
    ar: 'هل أنت متأكد من رغبتك في تسجيل الخروج وقفل الجلسة الإدارية؟',
    en: 'Are you sure you want to sign out and lock the administrative session?',
    hi: 'क्या आप वाकई साइन आउट करना चाहते हैं और व्यवस्थापकीय सत्र लॉक करना चाहते हैं?',
  );
  String get unauthorizedAccessTitle => _t(
    ar: 'وصول غير مصرح به',
    en: 'Unauthorized Access',
    hi: 'अनधिकृत पहुंच',
  );
  String get unauthorizedAccessMsg => _t(
    ar: 'يرجى تسجيل الدخول بحساب الإدارة المعتمد للوصول إلى لوحة التحكم.',
    en: 'Please sign in with the authorized admin account to access the dashboard.',
    hi: 'डैशबोर्ड तक पहुंचने के लिए कृपया अधिकृत व्यवस्थापक खाते से साइन इन करें।',
  );
  String get secureAdminPortalBadge => _t(
    ar: 'بوابة الإدارة الآمنة (Protected)',
    en: 'Secure Admin Portal (Protected)',
    hi: 'सुरक्षित व्यवस्थापक पोर्टल (संरक्षित)',
  );
  String get invalidAdminCredentialsMsg => _t(
    ar: 'بيانات الدخول غير صحيحة أو الحساب غير مصرح له كمسؤول نظام.',
    en: 'Invalid credentials or account is not authorized as system admin.',
    hi: 'अमान्य क्रेडेंशियल या खाता सिस्टम व्यवस्थापक के रूप में अधिकृत नहीं है।',
  );
}

