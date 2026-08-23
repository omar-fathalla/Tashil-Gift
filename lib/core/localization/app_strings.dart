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
  String get appTitle => _t(ar: 'Tashil Gift', en: 'Tashil Gift', hi: 'Tashil Gift');
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
  String operationFailed(String details) => _t(
    ar: 'فشلت العملية: $details',
    en: 'Operation failed: $details',
    hi: 'ऑपरेशन विफल रहा: $details',
  );

  // ---------------------------------------------------------------------------
  // 2. Navigation & Sidebar
  // ---------------------------------------------------------------------------
  String get navEventsManagement => _t(ar: 'الحملات والإدارة', en: 'Campaigns & Events', hi: 'अभियान और प्रबंधन');
  String get navAnalytics => _t(ar: 'التقارير والتحليلات', en: 'Reports & Analytics', hi: 'रिपोर्ट और विश्लेषण');
  String get navCompanyCatalog => _t(ar: 'تكويد الشركات والمنتجات', en: 'Company & Product Catalog', hi: 'कंपनी और उत्पाद सूची');
  String get navRetailChains => _t(ar: 'السلاسل والمنافذ', en: 'Retail Chains & Outlets', hi: 'रिटेल चेन और स्टोर');
  String get navProductsIntelligence => _t(ar: 'المنتجات والأسعار', en: 'Products & Prices', hi: 'उत्पाद और मूल्य');
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
  String get deleteCampaignBtn => _t(ar: 'حذف الحملة', en: 'Delete Campaign', hi: 'अभियान हटाएं');
  String get deleteCampaignTooltip => _t(
    ar: 'حذف هذه الحملة نهائياً من النظام واسترجاع جوائزها للمخزن',
    en: 'Permanently delete this campaign and release gifts to master stock',
    hi: 'इस अभियान को हटाएं और स्टॉक वापस करें',
  );
  String get deleteCampaignConfirmTitle => _t(ar: 'حذف الحملة نهائياً', en: 'Permanently Delete Campaign', hi: 'अभियान हमेशा के लिए हटाएं');
  String get deleteCampaignConfirmBody => _t(
    ar: 'هل أنت متأكد من رغبتك في حذف هذه الحملة نهائياً؟\nسيتم إزالة الحملة وتعطيل روابطها واسترجاع أرصدة الهدايا غير المستلمة لمخزن الشركة.',
    en: 'Are you sure you want to permanently delete this campaign?\nThis will remove the campaign, deactivate links, and restore unallocated gifts to company stock.',
    hi: 'क्या आप वाकई इस अभियान को हटाना चाहते हैं?\nअभियान हटा दिया जाएगा और शेष उपहार वापस स्टॉक में आ जाएंगे।',
  );
  String get campaignDeletedSuccess => _t(
    ar: 'تم حذف الحملة بنجاح واسترجاع الأرصدة.',
    en: 'Campaign deleted successfully and stock restored.',
    hi: 'अभियान सफलतापूर्वक हटा दिया गया।',
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
  String get deleteInvoiceBtn => _t(ar: 'حذف الفاتورة', en: 'Delete Invoice', hi: 'रसीद हटाएं');
  String get deleteInvoiceTooltip => _t(ar: 'حذف الفاتورة نهائياً وإلغاء قفل البون', en: 'Permanently delete invoice & unlock receipt', hi: 'रसीद हमेशा के लिए हटाएं और अनलॉक करें');
  String get confirmDeleteInvoiceTitle => _t(ar: 'حذف الفاتورة نهائياً', en: 'Permanently Delete Invoice', hi: 'रसीद हमेशा के लिए हटाएं');
  String get confirmDeleteInvoiceMsg => _t(
    ar: 'هل أنت متأكد من حذف هذه الفاتورة نهائياً من النظام؟\nسيتم مسح سجل الفاتورة وبياناتها من السحابة بالكامل، مما يتيح إمكانية فحص وإعادة استخدام هذا البون مرة أخرى.',
    en: 'Are you sure you want to permanently delete this invoice from the system?\nAll receipt transaction data and cloud images will be purged, allowing this receipt to be scanned and used again.',
    hi: 'क्या आप वाकई इस रसीद को सिस्टम से हमेशा के लिए हटाना चाहते हैं?\nसभी रसीद डेटा और क्लाउड इमेज हटा दिए जाएंगे, जिससे इस रसीद का दोबारा उपयोग किया जा सकेगा।',
  );
  String get invoiceDeletedSuccess => _t(
    ar: 'تم حذف الفاتورة بنجاح وإلغاء قفل البون من قاعدة البيانات.',
    en: 'Invoice deleted successfully and receipt unlocked.',
    hi: 'रसीद सफलतापूर्वक हटा दी गई और अनलॉक हो गई।',
  );
  String get invoiceDeletedError => _t(
    ar: 'حدث خطأ أثناء حذف الفاتورة، يرجى المحاولة مرة أخرى.',
    en: 'Failed to delete invoice. Please try again.',
    hi: 'रसीद हटाने में त्रुटि हुई। कृपया पुनः प्रयास करें।',
  );
  String get deletingInvoiceProgress => _t(
    ar: 'جاري حذف الفاتورة وتفريغ بيانات البون...',
    en: 'Deleting invoice and unlocking receipt...',
    hi: 'रसीद हटाई जा रही है...',
  );

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
  String get directGiftCustomerCongrats => _t(
    ar: 'مبروك! استحققت الهدية الفورية',
    en: 'Congratulations! You earned the instant gift',
    hi: 'बधाई हो! आप तत्काल उपहार के हकदार हैं',
  );
  String get directGiftCustomerVerified => _t(
    ar: 'تم التحقق من الفاتورة بنجاح واستيفاء شروط العرض الترويجي.',
    en: 'Receipt verified successfully and all promotion terms met.',
    hi: 'रसीद का सफलतापूर्वक सत्यापन किया गया और प्रचार की शर्तें पूरी हुईं।',
  );
  String get directGiftCustomerHandoverNote => _t(
    ar: 'يرجى استلام هديتك المعتمدة من ممثل الشركة في الفرع.',
    en: 'Please receive your approved gift from the company representative in the branch.',
    hi: 'कृपया शाखा में कंपनी प्रतिनिधि से अपना स्वीकृत उपहार प्राप्त करें।',
  );
  String get promoterLowStockWarningSingle => _t(
    ar: '⚠️ تنبيه للبروموتر: متبقي قطعة واحدة فقط من هذا الصنف في المخزون!',
    en: '⚠️ Promoter Alert: Only 1 unit remaining in stock!',
    hi: '⚠️ प्रमोटर चेतावनी: स्टॉक में केवल 1 इकाई शेष है!',
  );
  String get promoterLowStockWarningDouble => _t(
    ar: '⚠️ تنبيه للبروموتر: متبقي قطعتان فقط من هذا الصنف في المخزون!',
    en: '⚠️ Promoter Alert: Only 2 units remaining in stock!',
    hi: '⚠️ प्रमोटر चेतावनी: स्टॉक में केवल 2 इकाइयां शेष हैं!',
  );
  String get directGiftOutOfStock => _t(
    ar: 'تم نفاد مخزون هذه الهدية بالفرع، يرجى مراجعة المشرف.',
    en: 'This gift is currently out of stock at the branch. Please check with supervisor.',
    hi: 'यह उपहार वर्तमान में शाखा में समाप्त हो गया है। कृपया पर्यवेक्षक से संपर्क करें।',
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
  // 14.1 Prizes & Stock Balance System (منظومة رصيد وجرد الهدايا والمخزون)
  // ---------------------------------------------------------------------------
  String get prizesStockTitle => _t(
    ar: 'رصيد وجرد الهدايا',
    en: 'Prizes & Stock Balance',
    hi: 'उपहार और स्टॉक शेष',
  );
  String get prizesStockSubtitle => _t(
    ar: 'مراقبة لحظية شاملة لرصيد الهدايا المخصصة، المسحوبة، والمتبقية في الفروع',
    en: 'Comprehensive real-time monitoring of allocated, claimed, and remaining branch prize stock',
    hi: 'शाखाओं में आवंटित, वितरित और शेष उपहार स्टॉक की रीयल-टाइम निगरानी',
  );
  String get totalAllocatedGifts => _t(
    ar: 'إجمالي الهدايا المخصصة',
    en: 'Total Allocated Stock',
    hi: 'कुल आवंटित उपहार',
  );
  String get awardedGiftsCount => _t(
    ar: 'الهدايا المصروفة والمسحوبة',
    en: 'Awarded & Claimed Prizes',
    hi: 'वितरित एवं जीते गए उपहार',
  );
  String get remainingStockBalance => _t(
    ar: 'الرصيد المتبقي الفعلي',
    en: 'Live Remaining Stock',
    hi: 'वास्तविक शेष स्टॉक',
  );
  String get coveredOutletsCount => _t(
    ar: 'الفروع والمنافذ المغطاة',
    en: 'Covered Outlets & Branches',
    hi: 'शामिल शाखाएं और आउटलेट',
  );
  String get depletionRateLabel => _t(
    ar: 'نسبة السحب والصرف',
    en: 'Depletion Rate',
    hi: 'निकासी दर',
  );
  String get itemizedGiftsTab => _t(
    ar: 'جرد الأصناف والهدايا',
    en: 'Itemized SKU Inventory',
    hi: 'उपहार वार सूची',
  );
  String get branchBreakdownTab => _t(
    ar: 'الأرصدة حسب الفروع',
    en: 'Branch-by-Branch Stock',
    hi: 'शाखा वार स्टॉक',
  );
  String get campaignBreakdownTab => _t(
    ar: 'الأرصدة حسب الفعاليات',
    en: 'Campaign Stock Breakdown',
    hi: 'अभियान वार स्टॉक',
  );
  String get dailyTargetRateLabel => _t(
    ar: 'المعدل اليومي',
    en: 'Daily Rate',
    hi: 'दैनिक दर',
  );
  String get todayDisbursedLabel => _t(
    ar: 'صرف اليوم',
    en: 'Today Disbursed',
    hi: 'आज का वितरण',
  );
  String get dailyBranchTargetLabel => _t(
    ar: 'المستهدف اليومي للفرع',
    en: 'Branch Daily Target',
    hi: 'शाखा का दैनिक लक्ष्य',
  );
  String get dailyCampaignTargetLabel => _t(
    ar: 'المستهدف اليومي للحملة',
    en: 'Campaign Daily Target',
    hi: 'अभियान का दैनिक लक्ष्य',
  );
  String get campaignDurationLabel => _t(
    ar: 'مدة الفعالية',
    en: 'Campaign Duration',
    hi: 'अभियान की अवधि',
  );
  String get perDayUnit => _t(
    ar: 'يومياً',
    en: '/ day',
    hi: '/ दिन',
  );
  String get filterAllStock => _t(ar: 'كافة الحالات', en: 'All Statuses', hi: 'सभी स्थितियां');
  String get filterAvailableStock => _t(ar: 'متوفر 🟢', en: 'In Stock 🟢', hi: 'उपलब्ध 🟢');
  String get filterLowStock => _t(ar: 'رصيد منخفض 🟡', en: 'Low Stock 🟡', hi: 'कम स्टॉक 🟡');
  String get filterOutOfStock => _t(ar: 'نفد الرصيد 🔴', en: 'Out of Stock 🔴', hi: 'स्टॉक खत्म 🔴');
  String get searchGiftsPlaceholder => _t(
    ar: 'ابحث باسم الهدية، كود الصنف، أو اسم الفرع...',
    en: 'Search gift name, SKU code, or branch name...',
    hi: 'उपहार का नाम, एसकेयू कोड, या शाखा खोजें...',
  );
  String get exportStockReportCsv => _t(
    ar: 'تصدير تقرير الجرد (CSV)',
    en: 'Export Stock Report (CSV)',
    hi: 'स्टॉक रिपोर्ट निर्यात करें (CSV)',
  );
  String get allBranchesOption => _t(
    ar: 'كافة الفروع والمنافذ',
    en: 'All Branches & Outlets',
    hi: 'सभी शाखाएं और आउटलेट',
  );
  String get allCampaignsOption => _t(
    ar: 'كافة الفعاليات والحملات',
    en: 'All Campaigns & Events',
    hi: 'सभी अभियान और कार्यक्रम',
  );
  String get stockHealthyBadge => _t(ar: 'متوفر', en: 'Healthy Stock', hi: 'पर्याप्त स्टॉक');
  String get stockLowBadge => _t(ar: 'منخفض', en: 'Low Stock', hi: 'कम स्टॉक');
  String get stockDepletedBadge => _t(ar: 'نفد بالكامل', en: 'Depleted', hi: 'समाप्त');
  String get noGiftsFoundMsg => _t(
    ar: 'لا توجد هدايا أو أرصدة مطابقة لمعايير البحث الحالية.',
    en: 'No gifts or stock records match your current filter criteria.',
    hi: 'वर्तमान खोज मानदंडों से कोई उपहार या स्टॉक रिकॉर्ड मेल नहीं खाता।',
  );
  String get giftSkuLabel => _t(ar: 'كود الهدية', en: 'Gift SKU', hi: 'उपहार कोड');
  String get branchDistributionLabel => _t(
    ar: 'توزيع الأرصدة على الفروع المعتمدة',
    en: 'Stock Distribution Across Authorized Branches',
    hi: 'अधिकृत शाखाओं में स्टॉक वितरण',
  );
  String get remainingInBranch => _t(ar: 'متبقي بالفرع', en: 'Remaining in Branch', hi: 'शाखा में शेष');
  String get dragToReorder => _t(
    ar: 'اسحب لتغيير الترتيب',
    en: 'Drag to reorder',
    hi: 'पुनः व्यवस्थित करने के लिए खींचें',
  );
  String get dragToReorderHint => _t(
    ar: 'اضغط مطولاً على أي كارت لسحبه وتغيير ترتيبه في المخزون',
    en: 'Long press and drag any card to reorder in inventory',
    hi: 'स्टॉक में पुनः व्यवस्थित करने के लिए किसी भी कार्ड को दबाकर खींचें',
  );
  String get orderUpdatedSuccess => _t(
    ar: 'تم حفظ ترتيب الهدايا والكروت بنجاح ↕️',
    en: 'Gift and voucher order saved successfully ↕️',
    hi: 'उपहार और वाउचर का क्रम सफलतापूर्वक सहेजा गया ↕️',
  );
  String get reorderBadge => _t(
    ar: 'ترتيب حر باللمس ↕️',
    en: 'Touch Reorder ↕️',
    hi: 'टच रीऑर्डर ↕️',
  );
  String voucherValueText(dynamic amount) => _t(
    ar: 'بقيمة $amount ج.م',
    en: 'Value: $amount EGP',
    hi: 'मूल्य: $amount EGP',
  );
  String get certifiedVoucher => _t(
    ar: 'قسيمة مشتريات معتمدة 🎫',
    en: 'Certified Shopping Voucher 🎫',
    hi: 'प्रमाणित शॉपिंग वाउचर 🎫',
  );
  String get validForImmediateUse => _t(
    ar: 'صالحة للاستخدام الفوري لدى الكاشير',
    en: 'Valid for immediate redemption at cashier',
    hi: 'कैशियर पर तुरंत उपयोग के लिए मान्य',
  );
  String get voucherIntelligenceTitle => _t(
    ar: 'منظومة قسائم المشتريات والفواتشر',
    en: 'Voucher Intelligence & Budget',
    hi: 'वाउचर इंटेलिजेंस और बजट',
  );
  String get voucherIntelligenceSubtitle => _t(
    ar: 'متابعة تفصيلية لأرصدة وفئات القسائم (25، 50 ج.م) والميزانيات المالية المرصودة والمصروفة والمتبقية',
    en: 'Live tracking of voucher denominations (25, 50 EGP), allocated budgets, claimed, and branch stock',
    hi: 'वाउचर श्रेणियों (25, 50 EGP), बजट, वितरण और शाखा स्टॉक की लाइव ट्रैकिंग',
  );
  String get totalVouchersAllocated => _t(
    ar: 'إجمالي قسائم المشتريات',
    en: 'Total Vouchers Allocated',
    hi: 'कुल आवंटित वाउचर',
  );
  String get totalVouchersBudget => _t(
    ar: 'الميزانية المالية المرصودة',
    en: 'Total Financial Budget',
    hi: 'कुल वित्तीय बजट',
  );
  String get claimedVouchersValue => _t(
    ar: 'قيمة القسائم المصروفة',
    en: 'Disbursed Voucher Value',
    hi: 'वितरित वाउचर मूल्य',
  );
  String get remainingVouchersValue => _t(
    ar: 'الرصيد المالي المتبقي',
    en: 'Remaining Balance Value',
    hi: 'शेष वित्तीय शेष',
  );
  String get voucherDenominationsLabel => _t(
    ar: 'فئات القسائم المعتمدة',
    en: 'Voucher Denominations',
    hi: 'वाउचर श्रेणियां',
  );
  String get viewBranchVoucherMatrix => _t(
    ar: 'كشف توزيع القسائم على الفروع',
    en: 'Branch Voucher Matrix',
    hi: 'शाखा वाउचर आवंटन विवरण',
  );
  String get generalGiftsStockTitle => _t(
    ar: 'إجمالي حركة كافة الهدايا والأصناف',
    en: 'General Gifts & Inventory Overview',
    hi: 'सामान्य उपहार और इन्वेंटरी अवलोकन',
  );
  String get scopedToBranchNotice => _t(
    ar: 'بيانات مخصصة لـ',
    en: 'Scoped to',
    hi: 'के लिए विशेष',
  );
  String get allBranchesScopeNotice => _t(
    ar: 'شامل كافة الفروع والمنافذ',
    en: 'All Branches & Outlets',
    hi: 'सभी शाखाएं और आउटलेट',
  );
  String get voucherMatrixDialogTitle => _t(
    ar: 'كشف توزيع قسائم المشتريات على الفروع والفئات',
    en: 'Vouchers Allocation Matrix per Branch & Denomination',
    hi: 'शाखा और श्रेणी अनुसार वाउचर आवंटन मैट्रिक्स',
  );
  String get voucherMatrixDialogSubtitle => _t(
    ar: 'بيان تفصيلي بالأرصدة المخصصة، المصروفة، والمتبقية لكل فئة (25، 50 ج.م) والميزانيات المالية لكل فرع',
    en: 'Itemized breakdown of allocated, claimed, and remaining units per denomination (25, 50 EGP) and budget per branch',
    hi: 'प्रत्येक श्रेणी (25, 50 EGP) और शाखा के अनुसार आवंटित, वितरित और शेष वाउचर और बजट का विवरण',
  );
  String get filterToBranchBtn => _t(
    ar: 'تصفية لهذا الفرع',
    en: 'Filter Branch',
    hi: 'शाखा फ़िल्टर करें',
  );
  String get activeDenominationsCount => _t(
    ar: 'فئات نشطة',
    en: 'Active Denominations',
    hi: 'सक्रिय श्रेणियां',
  );
  String get vouchersCountUnit => _t(
    ar: 'قسيمة مشتريات',
    en: 'Voucher Cards',
    hi: 'वाउचर कार्ड',
  );
  String get allVoucherDenominations => _t(
    ar: 'كافة الفئات (إجمالي عام)',
    en: 'All Denominations (Combined)',
    hi: 'सभी श्रेणियां (संयुक्त)',
  );
  String get denominationBreakdownSection => _t(
    ar: 'بطاقات التحليل التفصيلي لفئات القسائم',
    en: 'Voucher Denominations Detailed Breakdown',
    hi: 'वाउचर श्रेणियों का विस्तृत विवरण',
  );
  String get denominationMasterStock => _t(
    ar: 'رصيد المخزون الكلي',
    en: 'Total Inventory Stock',
    hi: 'कुल इन्वेंटरी स्टॉक',
  );
  String get denominationCardsAllocated => _t(
    ar: 'الكروت المخصصة',
    en: 'Allocated Cards',
    hi: 'आवंटित कार्ड',
  );
  String get denominationCardsClaimed => _t(
    ar: 'الكروت المصروفة',
    en: 'Claimed Cards',
    hi: 'वितरित कार्ड',
  );
  String get denominationCardsRemaining => _t(
    ar: 'الكروت المتبقية',
    en: 'Remaining Cards',
    hi: 'शेष कार्ड',
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
  String get linkedCompanyGiftLabel => _t(
    ar: '🎁 الهدية المربوطة من مخزون الشركة:',
    en: '🎁 Linked Gift from Company Inventory:',
    hi: '🎁 कंपनी इन्वेंट्री से जुड़ा उपहार:',
  );
  String get unlinkedGiftOption => _t(
    ar: '➕ (غير مربوط بهدية محددة من المخزون)',
    en: '➕ (Not linked to specific inventory gift)',
    hi: '➕ (विशिष्ट इन्वेंट्री उपहार से जुड़ा नहीं है)',
  );
  String get ruleLinkedBadge => _t(
    ar: 'مربوط بالمخزون',
    en: 'Linked to Inventory',
    hi: 'इन्वेंट्री से जुड़ा हुआ',
  );
  String get ruleUnlinkedBadge => _t(
    ar: 'بحاجة لاختيار هدية',
    en: 'Gift Unlinked',
    hi: 'उपहार लिंक नहीं है',
  );
  String get deleteRuleTooltip => _t(
    ar: 'حذف / إلغاء هذه القاعدة',
    en: 'Delete / Remove this rule',
    hi: 'इस नियम को हटाएं',
  );
  String get autoDecomposeLabel => _t(
    ar: '⚡ تفكيك تلقائي للمبلغ',
    en: '⚡ Auto-Decompose Amount',
    hi: '⚡ स्वचालित राशि विभाजन',
  );
  String get addGiftToRule => _t(
    ar: '+ إضافة هدية / كارت للمكافأة',
    en: '+ Add Gift / Card to Reward',
    hi: '+ इनाम में उपहार/कार्ड जोड़ें',
  );
  String get cardsBreakdownTitle => _t(
    ar: 'بطاقات وكروت التسليم المعتمدة:',
    en: 'Approved Voucher Breakdown:',
    hi: 'स्वीकृत वाउचर कार्ड विवरण:',
  );
  String get totalCardsValueLabel => _t(
    ar: 'إجمالي قيمة الكروت المربوطة:',
    en: 'Total Linked Cards Value:',
    hi: 'कुल जुड़े कार्डों का मूल्य:',
  );
  String get syncPromptFromRulesBtn => _t(
    ar: '🔄 تنسيق وتحديث البرومبت تلقائياً من القواعد المعتمدة',
    en: '🔄 Auto-Format & Sync Prompt from Rules',
    hi: '🔄 नियमों से प्रॉम्प्ट को स्वतः प्रारूपित और समन्वयित करें',
  );
  String get syncPromptSuccessMsg => _t(
    ar: 'تم تحديث وتنسيق برومبت الفحص بنجاح بناءً على القواعد والمخزون',
    en: 'Audit prompt formatted and synced successfully from rules & inventory',
    hi: 'प्रॉम्प्ट नियमों और इन्वेंट्री के आधार पर सफलतापूर्वक समन्वयित किया गया',
  );
  String get addCustomRuleBtn => _t(
    ar: '+ إضافة شرط / قاعدة ترويجية جديدة',
    en: '+ Add New Promotional Rule',
    hi: '+ नया प्रचार नियम जोड़ें',
  );
  String get editRuleTitle => _t(
    ar: 'تعديل القاعدة الترويجية',
    en: 'Edit Promotional Rule',
    hi: 'प्रचार नियम संपादित करें',
  );
  String get ruleTitleLabel => _t(
    ar: 'عنوان القاعدة الترويجية',
    en: 'Rule Title',
    hi: 'نियम का शीर्षक',
  );
  String get triggerProductLabel => _t(
    ar: 'المنتج / الأصناف المشروطة (الكلمات المفتاحية)',
    en: 'Trigger Product / Required Keywords',
    hi: 'शर्त वाले उत्पाद/कीवर्ड',
  );
  String get minQuantityLabel => _t(
    ar: 'الكمية المشروطة الدنيا',
    en: 'Minimum Required Quantity',
    hi: 'न्यूनतम आवश्यक मात्रा',
  );
  String get rewardTypeLabel => _t(
    ar: 'نوع المكافأة',
    en: 'Reward Type',
    hi: 'इनाम का प्रकार',
  );
  String get chooseInventoryGiftLabel => _t(
    ar: 'اختر الهدية من مخزون هدايا الشركة',
    en: 'Choose Gift from Company Inventory',
    hi: 'कंपनी इन्वेंट्री से उपहार चुनें',
  );
  String get presetRulesDropdownHint => _t(
    ar: '📋 نماذج عروض وقواعد شائعة جاهزة...',
    en: '📋 Quick Preset Offer Templates...',
    hi: '📋 त्वरित पूर्व निर्धारित ऑफ़र टेम्पलेट...',
  );
  String get presetIdeasHeader => _t(
    ar: '💡 نماذج مقترحة لصياغة الأفكار (انقر للإضافة للبرومبت):',
    en: '💡 Template Inspiration Chips (Tap to add to prompt):',
    hi: '💡 टेम्पलेट प्रेरणा चिप्स (प्रॉम्प्ट में जोड़ने के लिए टैप करें):',
  );
  String get dynamicInventoryChipsHeader => _t(
    ar: '📦 هدايا مخزون الشركة المتاحة للعرض:',
    en: '📦 Available Company Inventory Gifts:',
    hi: '📦 उपलब्ध कंपनी इन्वेंट्री उपहार:',
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
  String get unauthorizedError => _t(
    ar: 'غير مصرح لك بتنفيذ هذه العملية. يتطلب صلاحيات مسؤول النظام.',
    en: 'You are not authorized to perform this operation. Admin permissions required.',
    hi: 'आप इस ऑपरेशन को करने के लिए अधिकृत नहीं हैं। व्यवस्थापक अनुमतियां आवश्यक हैं।',
  );
  String get adminProfileTooltip => _t(
    ar: 'الملف الشخصي والحساب',
    en: 'Admin Profile & Account',
    hi: 'व्यवस्थापक प्रोफ़ाइल और खाता',
  );
  String get systemAdminRole => _t(
    ar: 'مسؤول النظام',
    en: 'System Admin',
    hi: 'सिस्टम प्रशासक',
  );
  String get activeSessionLabel => _t(
    ar: 'جلسة إدارية نشطة',
    en: 'Active Admin Session',
    hi: 'सक्रिय प्रशासनिक सत्र',
  );

  // Promoter Gift Inventory & Branch Balance
  String get promoterGiftsBalanceTooltip => _t(
    ar: 'استعراض رصيد ومخزون الهدايا المتبقي بالفروع',
    en: 'View Remaining Gifts & Branch Inventory Balance',
    hi: 'शेष उपहार और शाखा स्टॉक बैलेंस देखें',
  );
  String get promoterGiftsBalanceTitle => _t(
    ar: 'رصيد ومخزون الهدايا المتبقي',
    en: 'Remaining Gifts & Stock Balance',
    hi: 'शेष उपहार और स्टॉक बैलेंस',
  );
  String get promoterGiftsBalanceSubtitle => _t(
    ar: 'متابعة حية ولحظية للكميات المتبقية والمخصصة لكل فرع بالحملة',
    en: 'Real-time monitoring of remaining & allocated quantities per branch',
    hi: 'प्रत्येक शाखा के लिए शेष और आवंटित मात्रा की रीयल-टाइम निगरानी',
  );
  String get campaignBranchesTitle => _t(
    ar: 'فروع الحملة الترويجية',
    en: 'Campaign Branches',
    hi: 'अभियान की शाखाएं',
  );
  String get allBranchesScope => _t(
    ar: 'كافة فروع السلسلة (مخزون مركزي للحملة)',
    en: 'All Chain Branches (Central Campaign Stock)',
    hi: 'सभी शाखाएं (केंद्रीय अभियान स्टॉक)',
  );
  String get selectBranchToViewStock => _t(
    ar: 'اختر الفرع لعرض تفاصيل الهدايا المتبقية فيه:',
    en: 'Select a branch to view remaining gift inventory:',
    hi: 'उपहार स्टॉक देखने के लिए शाखा चुनें:',
  );
  String get remainingOutOfTotal => _t(
    ar: 'متبقي',
    en: 'Remaining',
    hi: 'शेष',
  );
  String get outOfLabel => _t(
    ar: 'من إجمالي',
    en: 'of total',
    hi: 'कुल में से',
  );
  String get giftStatusAvailable => _t(
    ar: 'متوفر',
    en: 'In Stock',
    hi: 'उपलब्ध',
  );
  String get giftStatusLow => _t(
    ar: 'متبقي قليل',
    en: 'Low Stock',
    hi: 'कम स्टॉक',
  );
  String get giftStatusEmpty => _t(
    ar: 'نفد المخزون',
    en: 'Out of Stock',
    hi: 'स्टॉक समाप्त',
  );
  String get noGiftsAllocatedForBranch => _t(
    ar: 'لا توجد هدايا مخصصة لهذا الفرع حالياً',
    en: 'No gifts allocated for this branch currently',
    hi: 'वर्तमान में इस शाखा के लिए कोई उपहार आवंटित नहीं है',
  );
  String get totalBranchStock => _t(
    ar: 'إجمالي رصيد الفرع',
    en: 'Total Branch Stock',
    hi: 'कुल शाखा स्टॉक',
  );
  String get closeInventoryDialog => _t(
    ar: 'إغلاق نافذة الرصيد',
    en: 'Close Inventory',
    hi: 'विंडो बंद करें',
  );
  String get branchGiftsCountLabel => _t(
    ar: 'أنواع هدايا',
    en: 'Gift Types',
    hi: 'उपहार प्रकार',
  );
  String get promoterDailyDisbursalTab => _t(
    ar: 'حركة السحب والتوزيع اليومي',
    en: 'Daily Handover & Disbursals',
    hi: 'दैनिक वितरण और हैंडओवर',
  );
  String get promoterStockBalanceTab => _t(
    ar: 'رصيد ومخزون الهدايا',
    en: 'Gifts & Stock Balance',
    hi: 'उपहार और स्टॉक बैलेंस',
  );
  String get promoterDailyDisbursalTitle => _t(
    ar: 'سجل السحب والتوزيع اليومي للهدايا',
    en: 'Daily Gifts Handover & Disbursal Log',
    hi: 'दैनिक उपहार वितरण लॉग',
  );
  String get disbursedOnDateLabel => _t(
    ar: 'المنصرف في هذا اليوم',
    en: 'Disbursed on this date',
    hi: 'इस तिथि पर वितरित',
  );
  String get totalDisbursedCountLabel => _t(
    ar: 'إجمالي الهدايا المنصرفة',
    en: 'Total Disbursed Gifts',
    hi: 'कुल वितरित उपहार',
  );
  String get totalDisbursedVouchersLabel => _t(
    ar: 'إجمالي الفواتشرات المنصرفة',
    en: 'Total Disbursed Vouchers',
    hi: 'कुल वितरित वाउचर',
  );
  String get disbursedInvoicesCountLabel => _t(
    ar: 'عدد الفواتير المنفذة',
    en: 'Processed Invoices',
    hi: 'संसाधित बिल',
  );
  String get todayShortcut => _t(
    ar: 'اليوم',
    en: 'Today',
    hi: 'आज',
  );
  String get allTimeShortcut => _t(
    ar: 'إجمالي الحملة',
    en: 'All-Time Total',
    hi: 'कुल अभियान',
  );
  String get previousDayTooltip => _t(
    ar: 'اليوم السابق',
    en: 'Previous Day',
    hi: 'पिछला दिन',
  );
  String get nextDayTooltip => _t(
    ar: 'اليوم التالي',
    en: 'Next Day',
    hi: 'अगला दिन',
  );
  String get selectDateTooltip => _t(
    ar: 'اختيار تاريخ محدد',
    en: 'Select Specific Date',
    hi: 'विशिष्ट तिथि चुनें',
  );
  String get noDisbursalsOnDate => _t(
    ar: 'لم يتم تسجيل أي عمليات صرف هدايا في هذا التاريخ',
    en: 'No gift disbursements recorded on this date',
    hi: 'इस तिथि पर कोई उपहार वितरण दर्ज नहीं किया गया',
  );
  String get branchRemainingStockLabel => _t(
    ar: 'الرصيد المتبقي بالفرع',
    en: 'Branch Remaining Stock',
    hi: 'शाखा में शेष स्टॉक',
  );
  String get disbursedVoucherAmountLabel => _t(
    ar: 'إجمالي قيمة الفواتشر المنصرفة',
    en: 'Disbursed Vouchers Value',
    hi: 'वितरित वाउचर मूल्य',
  );

  // ---------------------------------------------------------------------------
  // 30.5 Voucher Serial Numbers Tracking & Admin Reset System
  // ---------------------------------------------------------------------------
  String get voucherSerialsSectionTitle => _t(
    ar: 'أرقام بطاقات الفواتشرات المستحقة (إلزامي)',
    en: 'Voucher Card Serial Numbers (Mandatory)',
    hi: 'वाउचर कार्ड सीरियल नंबर (अनिवार्य)',
  );
  String get voucherSerialsSectionTitleOptional => _t(
    ar: 'أرقام بطاقات الفواتشرات المستحقة (اختياري)',
    en: 'Voucher Card Serial Numbers (Optional)',
    hi: 'वाउचर कार्ड सीरियल नंबर (वैकल्पिक)',
  );
  String get voucherSerialsSectionSubtitle => _t(
    ar: 'يرجى تسجيل الأرقام التسلسلية المطبوعة على بطاقات الفواتشرات لتأكيد الصرف والمطابقة مع العهدة',
    en: 'Please enter the serial numbers printed on physical voucher cards for inventory audit',
    hi: 'ऑडिट के लिए भौतिक वाउचर कार्ड पर मुद्रित सीरियल नंबर दर्ज करें',
  );
  String get voucherSerialsSectionSubtitleOptional => _t(
    ar: 'يمكنك تسجيل الأرقام التسلسلية المطبوعة على بطاقات الفواتشرات لمطابقة العهدة (اختياري)',
    en: 'You can record physical voucher card serial numbers for stock verification (optional)',
    hi: 'स्टॉक सत्यापन के लिए भौतिक वाउचर कार्ड सीरियल नंबर दर्ज कर सकते हैं (वैकल्पिक)',
  );
  String get campaignVoucherSerialsSettingTitle => _t(
    ar: 'تسجيل أرقام كروت الفواتشرات',
    en: 'Voucher Card Serial Numbers',
    hi: 'वाउचर कार्ड सीरियल नंबर',
  );
  String get campaignVoucherSerialsSettingSubtitle => _t(
    ar: 'تحديد ما إذا كان إدخال الأرقام التسلسلية لكروت الفواتشرات إلزامياً للبروموتر عند تسليم الهدية أو اختيارياً (الافتراضي: اختياري)',
    en: 'Determine whether entering voucher serial numbers is mandatory or optional for promoters upon gift handover (Default: Optional)',
    hi: 'निर्धारित करें कि उपहार सौंपते समय प्रमोटरों के लिए वाउचर सीरियल दर्ज करना अनिवार्य है या वैकल्पिक (डिफ़ॉल्ट: वैकल्पिक)',
  );
  String get voucherSerialsMandatoryBadge => _t(
    ar: 'إلزامي للبروموتر',
    en: 'Mandatory for Promoter',
    hi: 'प्रमोटर के लिए अनिवार्य',
  );
  String get voucherSerialsOptionalBadge => _t(
    ar: 'اختياري (الافتراضي)',
    en: 'Optional (Default)',
    hi: 'वैकल्पिक (डिफ़ॉल्ट)',
  );
  String get voucherSerialInputLabel => _t(
    ar: 'رقم كارت الفواتشر',
    en: 'Voucher Serial Number',
    hi: 'वाउचर सीरियल नंबर',
  );
  String get voucherSerialInputHint => _t(
    ar: 'مثال: 2789241/1',
    en: 'e.g. 2789241/1',
    hi: 'उदा. 2789241/1',
  );
  String get voucherSerialRequiredError => _t(
    ar: 'يرجى إدخال رقم كارت الفواتشر',
    en: 'Please enter the voucher serial number',
    hi: 'कृपया वाउचर सीरियल नंबर दर्ज करें',
  );
  String get voucherSerialDuplicateInTxError => _t(
    ar: 'تم إدخال هذا الرقم لكارت آخر في نفس المعاملة',
    en: 'This serial number was entered for another card in this transaction',
    hi: 'यह सीरियल नंबर इस लेनदेन में दूसरे कार्ड के लिए दर्ज किया गया है',
  );
  String get voucherSerialAlreadyClaimedError => _t(
    ar: 'هذا الكارت مسجل كمنصرف مسبقاً في الحملة',
    en: 'This voucher card is already recorded as claimed in this campaign',
    hi: 'यह वाउचर कार्ड इस अभियान में पहले से दावा किया गया है',
  );
  String get voucherSerialsManagementTitle => _t(
    ar: 'إدارة وسجل أرقام بطاقات الفواتشرات',
    en: 'Voucher Cards Registry & Reset',
    hi: 'वाउचर कार्ड रजिस्ट्री और रीसेट',
  );
  String get voucherSerialsManagementSubtitle => _t(
    ar: 'استعلام وبحث أرقام كروت الفواتشرات المسلمة وإعادة تعيينها لإعادة الاستخدام في حملات جديدة',
    en: 'Search claimed voucher card serials and reset them for future campaign cycles',
    hi: 'दावा किए गए वाउचर सीरियल खोजें और नए अभियान के लिए रीसेट करें',
  );
  String get resetVoucherSerialsBtn => _t(
    ar: 'إعادة تعيين أرقام الفواتشرات لإعادة الاستخدام',
    en: 'Reset Voucher Serials for Reuse',
    hi: 'पुनः उपयोग के लिए वाउचर रीसेट करें',
  );
  String get resetVoucherSerialsConfirmTitle => _t(
    ar: 'تأكيد إعادة تعيين أرقام الفواتشرات',
    en: 'Confirm Voucher Serials Reset',
    hi: 'वाउचर सीरियल रीसेट की पुष्टि करें',
  );
  String get resetVoucherSerialsConfirmMsg => _t(
    ar: 'سيتم فك حظر الأرقام التسلسلية السابقة والسماح بإعادة استخدام نفس البطاقات البلاستيكية في دورات وحملات جديدة، مع بقاء كافة سجلات الفواتير التاريخية محفوظة بالكامل.',
    en: 'Previous serial numbers will be released for reuse in new campaigns while all historical transaction records remain completely intact.',
    hi: 'पिछले सीरियल नंबर नए अभियानों में पुनः उपयोग के लिए अनलॉक हो जाएंगे जबकि सभी पिछले रिकॉर्ड सुरक्षित रहेंगे।',
  );
  String get voucherSerialsResetSuccess => _t(
    ar: 'تمت إعادة تعيين سجل أرقام الفواتشرات بنجاح وإتاحة استخدامها مجدداً',
    en: 'Voucher serial numbers registry reset successfully for reuse',
    hi: 'वाउचर सीरियल रजिस्ट्री सफलतापूर्वक रीसेट हो गई',
  );
  String get totalClaimedVoucherCards => _t(
    ar: 'إجمالي كروت الفواتشرات المسجلة',
    en: 'Total Registered Voucher Cards',
    hi: 'कुल पंजीकृत वाउचर कार्ड',
  );
  String get searchVoucherSerialPlaceholder => _t(
    ar: 'بحث برقم كارت الفواتشر (مثال: 2789241/1)...',
    en: 'Search by voucher serial (e.g. 2789241/1)...',
    hi: 'वाउचर नंबर से खोजें (उदा. 2789241/1)...',
  );
  String get noVouchersClaimedYet => _t(
    ar: 'لم يتم تسجيل أي كروت فواتشرات مسلمة حتى الآن',
    en: 'No claimed voucher cards recorded yet',
    hi: 'अभी तक कोई वाउचर कार्ड रिकॉर्ड नहीं हुआ है',
  );

  // ---------------------------------------------------------------------------
  // 31. Promoter & Client Portal: Campaign Brief & Offer Rules Dialog
  // ---------------------------------------------------------------------------
  String get promoterCampaignBriefTooltip => _t(
    ar: 'فكرة وشروط العرض الترويجي (Campaign Brief)',
    en: 'Campaign Brief & Promotional Conditions',
    hi: 'अभियान का संक्षिप्त विवरण और शर्तें',
  );
  String get campaignBriefTitle => _t(
    ar: 'فكرة وشروط العرض الترويجي',
    en: 'Campaign Brief & Offer Rules',
    hi: 'प्रचार अभियान के नियम और विवरण',
  );
  String get campaignBriefSubtitle => _t(
    ar: 'دليل بنود العرض الترويجي وشروط استحقاق الهدايا والقسائم المعتمدة',
    en: 'Guide to promotional rules, eligibility conditions, and certified rewards',
    hi: 'प्रचार नियमों, पात्रता शर्तों और प्रमाणित पुरस्कारों की गाइड',
  );
  String get promotionalConditionsListTitle => _t(
    ar: 'بنود وشروط العروض الترويجية المعتمدة',
    en: 'Approved Promotional Conditions & Rules',
    hi: 'स्वीकृत प्रचार नियम और शर्तें',
  );
  String get campaignIdeaSummaryTitle => _t(
    ar: 'ملخص فكرة المهرجان والعرض',
    en: 'Campaign Overview & Concept',
    hi: 'अभियान की मुख्य अवधारणा',
  );
  String get ruleConditionBuy => _t(
    ar: 'الشرط: شراء',
    en: 'Condition: Buy',
    hi: 'शर्त: खरीदें',
  );
  String get ruleConditionGet => _t(
    ar: 'المكافأة المستحقة',
    en: 'Earned Reward',
    hi: 'पात्र इनाम',
  );
  String get ruleMultiplierAllowed => _t(
    ar: 'مضاعفة الهدايا مع زيادة الكمية',
    en: 'Multipliers allowed with increased quantity',
    hi: 'मात्रा बढ़ने पर इनाम कई गुना',
  );
  String get campaignValidityPeriod => _t(
    ar: 'فترة سريان العرض',
    en: 'Validity Period',
    hi: 'वैधता अवधि',
  );
  String get noSpecificPromotionalRules => _t(
    ar: 'لا توجد شروط خاصة للأصناف، يتم الفوز وفقاً للحد الأدنى للشراء.',
    en: 'No specific item rules; eligibility based on minimum purchase amount.',
    hi: 'कोई विशेष आइटम नियम नहीं, न्यूनतम खरीद राशि पर लागू।',
  );
  String get closeBriefDialog => _t(
    ar: 'إغلاق الدليل',
    en: 'Close Guide',
    hi: 'गाइड बंद करें',
  );
  String get campaignGeneralConditions => _t(
    ar: 'الشروط العامة للحملة',
    en: 'General Campaign Conditions',
    hi: 'अभियान की सामान्य शर्तें',
  );

  // ---------------------------------------------------------------------------
  // 21. Granular Portal Status Controls & Suspended Campaign Screens
  // ---------------------------------------------------------------------------
  String get promoterPortalLabel => _t(
    ar: 'بوابة البروموتر والعميل',
    en: 'Promoter & Client Portal',
    hi: 'प्रमोटर और ग्राहक पोर्टल',
  );
  String get managerPortalLabel => _t(
    ar: 'بوابة مدير الشركة',
    en: 'Company Manager Portal',
    hi: 'कंपनी प्रबंधक पोर्टल',
  );
  String get portalStatusActive => _t(
    ar: 'مفعلة',
    en: 'Active',
    hi: 'सक्रिय',
  );
  String get portalStatusPaused => _t(
    ar: 'متوقفة',
    en: 'Paused',
    hi: 'रुकी हुई',
  );
  String get promoterPortalToggleTooltipActive => _t(
    ar: 'بوابة البروموتر والعميل مفعلة حالياً - اضغط لإيقاف استقبال الفواتير',
    en: 'Promoter portal is active - tap to pause receipt submission',
    hi: 'प्रमोटर पोर्टल सक्रिय है - रसीद सबमिशन रोकने के लिए टैप करें',
  );
  String get promoterPortalToggleTooltipPaused => _t(
    ar: 'بوابة البروموتر والعميل متوقفة - اضغط لإعادة تفعيلها فورياً',
    en: 'Promoter portal is paused - tap to reactivate immediately',
    hi: 'प्रमोटर पोर्टल रुका हुआ है - तुरंत पुनः सक्रिय करने के लिए टैप करें',
  );
  String get managerPortalToggleTooltipActive => _t(
    ar: 'بوابة مدير الشركة مفعلة حالياً - اضغط لتعليق صلاحية الوصول',
    en: 'Manager portal is active - tap to suspend dashboard access',
    hi: 'प्रबंधक पोर्टल सक्रिय है - डैशबोर्ड पहुंच निलंबित करने के लिए टैप करें',
  );
  String get managerPortalToggleTooltipPaused => _t(
    ar: 'بوابة مدير الشركة متوقفة - اضغط لإعادة فتح البوابة فورياً',
    en: 'Manager portal is paused - tap to reopen portal immediately',
    hi: 'प्रबंधक पोर्टल रुका हुआ है - पोर्टल तुरंत पुनः खोलने के लिए टैप करें',
  );
  String get promoterSuspendedTitle => _t(
    ar: 'تم إيقاف هذه الحملة الترويجية مؤقتاً',
    en: 'Promotion Temporarily Suspended',
    hi: 'अभियान अस्थायी रूप से निलंबित है',
  );
  String get promoterSuspendedMessage => _t(
    ar: 'نحيطكم علماً بأن استقبال الفواتير والمشاركة في هذه الحملة متوقف حالياً من قِبل إدارة النظام. إذا كنت أحد ممثلي الترويج المعتمدين، يرجى مراجعة مشرفك أو التواصل مع الإدارة.',
    en: 'Receipt submission and promotion participation are currently paused by system administration. If you are an authorized promoter, please check with your supervisor or contact administration.',
    hi: 'सिस्टम प्रशासन द्वारा रसीद सबमिशन और अभियान भागीदारी वर्तमान में रोक दी गई है। यदि आप एक अधिकृत प्रमोटर हैं, तो कृपया अपने पर्यवेक्षक से संपर्क करें या प्रशासन से संपर्क करें।',
  );
  String get managerSuspendedTitle => _t(
    ar: 'تم تعليق صلاحية الوصول لبوابة الإدارة',
    en: 'Manager Dashboard Access Suspended',
    hi: 'प्रबंधक डैशबोर्ड का उपयोग निलंबित है',
  );
  String get managerSuspendedMessage => _t(
    ar: 'تم إيقاف صلاحية استعراض التقارير وسجل الفواتير لهذه الحملة مؤقتاً. يرجى التواصل مع إدارة النظام المركزية لإعادة تفعيل الصلاحية.',
    en: 'Access to analytics and invoice logs for this campaign is temporarily paused. Please contact central system administration for reactivation.',
    hi: 'इस अभियान के लिए एनालिटिक्स और रसीद ऑडिट तक पहुंच अस्थायी रूप से रोक दी गई है। कृपया पुनः सक्रियण के लिए केंद्रीय प्रशासन से संपर्क करें।',
  );
  String get contactAdminBtn => _t(
    ar: 'تواصل مع الإدارة',
    en: 'Contact Administration',
    hi: 'प्रशासन से संपर्क करें',
  );
  String get refreshStatusBtn => _t(
    ar: 'تحديث وفحص الحالة',
    en: 'Refresh & Check Status',
    hi: 'रीफ्रेश करें और स्थिति जांचें',
  );
  String get contactAdminCopied => _t(
    ar: 'تم نسخ بيانات التواصل مع الإدارة للحافظة',
    en: 'Admin contact details copied to clipboard',
    hi: 'व्यवस्थापक संपर्क विवरण क्लिपबोर्ड पर कॉपी किया गया',
  );
  String get supportTeamNotice => _t(
    ar: 'فريق دعم وإدارة المنصة متاح للمساعدة.',
    en: 'Platform support and administration team is available to assist.',
    hi: 'प्लेटफ़ॉर्म सहायता और प्रशासन टीम सहायता के लिए उपलब्ध है।',
  );

  // ---------------------------------------------------------------------------
  // 22. Enhanced Duplicate & Already Drawn Receipt Messages
  // ---------------------------------------------------------------------------
  String get duplicateReceiptAlreadyDrawnTitle => _t(
    ar: 'تم السحب على هذه الفاتورة من قبل (مسجلة مسبقاً)',
    en: 'Receipt Already Participated / Drawn',
    hi: 'रसीद पहले ही ड्रा में भाग ले चुकी है',
  );
  String get duplicateReceiptAlreadyDrawnSubtitle => _t(
    ar: 'عفواً، هذه الفاتورة تم استخدامها ودخول السحب واستلام الجائزة مسبقاً، ولا يمكن تكرار المشاركة بنفس الفاتورة.',
    en: 'This receipt was previously submitted, entered the draw, and claimed a prize. Duplicate participation is not permitted.',
    hi: 'यह रसीद पहले सबमिट की गई थी, ड्रा में प्रवेश किया था, और पुरस्कार प्राप्त किया था। पुनः भागीदारी की अनुमति नहीं है।',
  );
  String get duplicateReceiptConditionTitle => _t(
    ar: 'حالة الفاتورة: مستخدمة مسبقاً',
    en: 'Receipt Status: Previously Used',
    hi: 'रसीद स्थिति: पहले से उपयोग की गई',
  );
  String get duplicateReceiptConditionDesc => _t(
    ar: 'رقم الفاتورة مسجل بالنظام وتمت المشاركة بها من قبل. تم تحديث بيانات الإيصال في السجلات مع الحفاظ على الجائزة المسجلة.',
    en: 'Receipt number is already recorded in the system with a claimed prize. Receipt data was updated in the audit logs.',
    hi: 'रसीद संख्या पहले से ही सिस्टम में दर्ज है। ऑडिट लॉग में रसीद डेटा अपडेट कर दिया गया है।',
  );
  String get duplicateReceiptBadge => _t(
    ar: 'تم السحب مسبقاً',
    en: 'Already Drawn',
    hi: 'पहले ही ड्रा हुआ',
  );

  // ---------------------------------------------------------------------------
  // 23. Promoter Invoices Log & Branch History
  // ---------------------------------------------------------------------------
  String get promoterInvoicesLogTooltip => _t(
    ar: 'سجل الفواتير والمدخلات للفروع',
    en: 'Campaign & Branch Invoices Log',
    hi: 'अभियान और शाखा रसीदें',
  );
  String get promoterInvoicesDialogTitle => _t(
    ar: 'سجل فواتير الحملة ومدخلات الفروع',
    en: 'Campaign & Branch Invoices Log',
    hi: 'अभियान और शाखा रसीदें',
  );
  String get promoterInvoicesDialogSubtitle => _t(
    ar: 'مرجع كامل لجميع الفواتير المدخلة مع تصفية وتثبيت الفرع',
    en: 'Complete reference of submitted invoices with branch filtering & pinning',
    hi: 'शाखा फ़िल्टरिंग और पिनिंग के साथ प्रस्तुत रसीदों का पूरा संदर्भ',
  );
  String get promoterAllBranchesOption => _t(
    ar: 'جميع الفروع',
    en: 'All Branches',
    hi: 'सभी शाखाएं',
  );
  String get pinMyBranchTooltip => _t(
    ar: 'تثبيت كفرعي الافتراضي',
    en: 'Pin as my default branch',
    hi: 'मेरी डिफ़ॉल्ट शाखा के रूप में पिन करें',
  );
  String get unpinBranchTooltip => _t(
    ar: 'إلغاء تثبيت الفرع',
    en: 'Unpin branch',
    hi: 'शाखा अनपिन करें',
  );
  String get pinnedBranchBadge => _t(
    ar: 'فرعي المثبت 📌',
    en: 'Pinned Branch 📌',
    hi: 'पिन की गई शाखा 📌',
  );
  String get branchPinnedSuccess => _t(
    ar: 'تم تثبيت هذا الفرع كفرعك الافتراضي بنجاح',
    en: 'Branch pinned as your default branch successfully',
    hi: 'शाखा को आपकी डिफ़ॉल्ट शाखा के रूप में सफलतापूर्वक पिन किया गया',
  );
  String get branchUnpinnedSuccess => _t(
    ar: 'تم إلغاء تثبيت الفرع الافتراضي',
    en: 'Default branch unpinned',
    hi: 'डिफ़ॉल्ट शाखा अनपिन की गई',
  );
  String get searchInvoicesPlaceholder => _t(
    ar: 'بحث برقم الفاتورة، هاتف العميل، التاريخ، أو اسم العميل...',
    en: 'Search by receipt #, customer phone, date, or name...',
    hi: 'रसीद #, ग्राहक फोन, तारीख, या नाम से खोजें...',
  );
  String get totalInvoicesCountLabel => _t(
    ar: 'إجمالي الفواتير',
    en: 'Total Invoices',
    hi: 'कुल रसीदें',
  );
  String get totalInvoicesValueLabel => _t(
    ar: 'إجمالي القيمة',
    en: 'Total Value',
    hi: 'कुल मूल्य',
  );
  String get noInvoicesForBranch => _t(
    ar: 'لا توجد فواتير مسجلة لهذا الفرع حتى الآن.',
    en: 'No invoices recorded for this branch yet.',
    hi: 'इस शाखा के लिए अभी तक कोई रसीद दर्ज नहीं है।',
  );
  String get noInvoicesFoundSearch => _t(
    ar: 'لا توجد فواتير مطابقة لمعايير البحث.',
    en: 'No invoices matching search criteria.',
    hi: 'खोज मानदंडों से मेल खाने वाली कोई रसीद नहीं मिली।',
  );
  String get viewReceiptDetails => _t(
    ar: 'تفاصيل الفاتورة',
    en: 'Receipt Details',
    hi: 'रसीद विवरण',
  );
  String get receiptZoomImage => _t(
    ar: 'معاينة صورة الفاتورة',
    en: 'Preview Receipt Image',
    hi: 'रसीद छवि पूर्वावलोकन',
  );

  // ---------------------------------------------------------------------------
  // 24. Branch Prize Allocation & Supply Management (Manager Portal)
  // ---------------------------------------------------------------------------
  String get adjustBranchAllocationTitle => _t(
    ar: 'تعديل وتزويد حصة الفرع',
    en: 'Adjust & Supply Branch Allocation',
    hi: 'शाखा कोटा संशोधित और आपूर्ति करें',
  );
  String get adjustBranchAllocationSubtitle => _t(
    ar: 'زيادة أو تعديل رصيد الهدايا المخصص لهذا الفرع في الفعالية',
    en: 'Increase or adjust the allocated prize quantity for this branch in the campaign',
    hi: 'इस अभियान में इस शाखा के लिए आवंटित उपहार मात्रा बढ़ाएं या समायोजित करें',
  );
  String get quickSupplyBranchBtn => _t(
    ar: 'تزويد رصيد الفرع',
    en: 'Supply Branch Stock',
    hi: 'शाखा स्टॉक आपूर्ति करें',
  );
  String get availableMasterStockLabel => _t(
    ar: 'الرصيد المتاح للشركة بالمخزن',
    en: 'Available Company Master Stock',
    hi: 'कंपनी मास्टर स्टॉक उपलब्ध',
  );
  String get currentBranchAllocation => _t(
    ar: 'الحصة الحالية للفرع',
    en: 'Current Branch Allocation',
    hi: 'वर्तमान शाखा आवंटन',
  );
  String get currentBranchRemaining => _t(
    ar: 'المتبقي الحالي بالفرع',
    en: 'Current Left in Branch',
    hi: 'शाखा में शेष वर्तमान',
  );
  String get currentBranchClaimed => _t(
    ar: 'المصروف / المسلّم للعملاء',
    en: 'Awarded to Shoppers',
    hi: 'ग्राहकों को दिया गया',
  );
  String get addQuantityLabel => _t(
    ar: 'الكمية الإضافية المراد تزويدها (+)',
    en: 'Additional Quantity to Supply (+)',
    hi: 'आपूर्ति के लिए अतिरिक्त मात्रा (+)',
  );
  String get newTotalBranchAllocation => _t(
    ar: 'إجمالي الحصة الجديد بعد التزويد',
    en: 'New Total Branch Allocation',
    hi: 'आपूर्ति के बाद नया कुल शाखा आवंटन',
  );
  String get branchAllocationSuccessMsg => _t(
    ar: 'تم تحديث وتزويد حصة الفرع بنجاح وتفعيلها في السحب',
    en: 'Branch prize allocation updated & activated successfully',
    hi: 'शाखा उपहार आवंटन सफलतापूर्वक अपडेट और सक्रिय किया गया',
  );
  String get cannotReduceBelowClaimedError => _t(
    ar: 'لا يمكن تقليل حصة الفرع عن عدد الهدايا التي تم صرفها بالفعل للعملاء',
    en: 'Cannot reduce branch allocation below already awarded/claimed prizes',
    hi: 'शाखा आवंटन को पहले से दिए गए उपहारों से कम नहीं किया जा सकता',
  );
  String get supplyReasonOptionalLabel => _t(
    ar: 'ملاحظات / سبب التزويد (اختياري)',
    en: 'Notes / Supply Reason (Optional)',
    hi: 'टिप्पणियाँ / आपूर्ति का कारण (वैकल्पिक)',
  );
  String get saveBranchAllocationBtn => _t(
    ar: 'حفظ وتحديث حصة الفرع',
    en: 'Save & Update Branch Quota',
    hi: 'शाखा कोटा सहेजें और अपडेट करें',
  );
  String get editBranchAllocationBtn => _t(
    ar: 'تعديل الحصة',
    en: 'Edit Quota',
    hi: 'कोटा संपादित करें',
  );
  String get zeroAllocationBtn => _t(
    ar: 'تصفير الحصة (0)',
    en: 'Zero Out (0)',
    hi: 'शून्य करें (0)',
  );
  String get zeroAllAllocationsBtn => _t(
    ar: 'تصفير حصص جميع الفروع (0)',
    en: 'Zero All Branches (0)',
    hi: 'सभी शाखा कोटा शून्य करें (0)',
  );
  String get setAllocationDirectlyLabel => _t(
    ar: 'المخصص الإجمالي للفرع',
    en: 'Total Branch Allocation',
    hi: 'कुल शाखा आवंटन',
  );
  String get editGiftAllocationsTitle => _t(
    ar: 'تعديل وتصفير مخصصات الفروع',
    en: 'Edit & Zero Branch Allocations',
    hi: 'शाखा आवंटन संशोधित और शून्य करें',
  );
  String get editGiftAllocationsSubtitle => _t(
    ar: 'تعديل أو تصفير حصة كل فرع من هذا الصنف وإرجاع الفائض للمخزن المركزي',
    en: 'Adjust or zero out each branch quota for this gift & return surplus to master stock',
    hi: 'इस उपहार के लिए प्रत्येक शाखा कोटा समायोजित या शून्य करें',
  );
  String get saveAllAllocationsBtn => _t(
    ar: 'حفظ وتحديث كافة المخصصات',
    en: 'Save & Update All Allocations',
    hi: 'सभी आवंटन सहेजें और अपडेट करें',
  );
  String get allocationsSavedSuccess => _t(
    ar: 'تم تحديث مخصصات الفروع بنجاح ومزامنة المخزن المركزي',
    en: 'Branch allocations updated successfully & master stock synchronized',
    hi: 'शाखा आवंटन सफलतापूर्वक अपडेट और मास्टर स्टॉक सिंक किया गया',
  );

  // ---------------------------------------------------------------------------
  // 26. Chain Products & Price Intelligence (رصد ومقارنة أسعار المنتجات عبر السلاسل)
  // ---------------------------------------------------------------------------
  String get productsIntelligenceTitle => _t(
    ar: 'رصد ومراقبة أسعار المنتجات عبر السلاسل',
    en: 'Cross-Chain Products & Price Intelligence',
    hi: 'क्रॉस-चेन उत्पाद और मूल्य खुफिया',
  );
  String get productsIntelligenceSubtitle => _t(
    ar: 'مراقبة حية وشاملة لأسعار وتخفيضات وتاريخ تعديل المنتجات عبر كافة السلاسل والمتاجر',
    en: 'Real-time comprehensive tracking of product prices, promotions & modification history across all retail chains',
    hi: 'सभी खुदरा श्रृंखलाओं में उत्पाद की कीमतों, प्रचारों और संशोधन इतिहास की रीयल-टाइम ट्रैकिंग',
  );
  String get allChainsTab => _t(
    ar: 'جميع السلاسل (مقارنة شاملة)',
    en: 'All Chains (Matrix)',
    hi: 'सभी श्रृंखलाएं (तुलना)',
  );
  String get metricTotalSkus => _t(
    ar: 'إجمالي الأصناف المرصودة',
    en: 'Tracked SKUs',
    hi: 'ट्रैक किए गए उत्पाद',
  );
  String get metricActiveChains => _t(
    ar: 'السلاسل النشطة',
    en: 'Active Chains',
    hi: 'सक्रिय खुदरा श्रृंखलाएं',
  );
  String get metricPromotedItems => _t(
    ar: 'أصناف العروض والخصومات',
    en: 'Promotions Detected',
    hi: 'पहचाने गए प्रचार',
  );
  String get metricPriceFluctuations => _t(
    ar: 'تنبيهات تغير الأسعار',
    en: 'Price Change Alerts',
    hi: 'मूल्य परिवर्तन अलर्ट',
  );
  String get searchProductPlaceholder => _t(
    ar: 'ابحث باسم المنتج، الباركود، أو البراند...',
    en: 'Search by product name, barcode, or brand...',
    hi: 'उत्पाद नाम, बारकोड या ब्रांड द्वारा खोजें...',
  );
  String get viewModeCards => _t(
    ar: 'بطاقات المنتجات',
    en: 'Cards View',
    hi: 'कार्ड दृश्य',
  );
  String get viewModeMatrix => _t(
    ar: 'جدول المقارنة السعرية',
    en: 'Price Matrix Table',
    hi: 'मूल्य मैट्रिक्स तालिका',
  );
  String get cheapestStoreBadge => _t(
    ar: 'الأرخص سعراً',
    en: 'Cheapest Store',
    hi: 'सबसे सस्ता स्टोर',
  );
  String get highestPriceStoreBadge => _t(
    ar: 'الأعلى سعراً',
    en: 'Highest Price',
    hi: 'उच्चतम मूल्य',
  );
  String get priceDifferenceLabel => _t(
    ar: 'فارق السعر:',
    en: 'Price Gap:',
    hi: 'मूल्य अंतर:',
  );
  String get priceHistoryTitle => _t(
    ar: 'سجل وتاريخ تغير الأسعار',
    en: 'Price History & Audit Log',
    hi: 'मूल्य इतिहास और ऑडिट लॉग',
  );
  String get priceHistorySubtitle => _t(
    ar: 'تتبع زمني لكافة الأسعار والخصومات المرصودة لهذا الصنف بالفواتير',
    en: 'Chronological timeline of all observed prices & discounts on receipts for this SKU',
    hi: 'इस उत्पाद के लिए सभी देखी गई कीमतों का कालानुक्रमिक इतिहास',
  );
  String get noProductsFound => _t(
    ar: 'لم يتم العثور على منتجات مطابقة للبحث أو الفلتر الحالي.',
    en: 'No products match your search or filter criteria.',
    hi: 'कोई उत्पाद आपके खोज मानदंड से मेल नहीं खाता।',
  );
  String get noProductsInDatabase => _t(
    ar: 'لم يتم رصد أي منتجات من الفواتير بعد.',
    en: 'No products detected from receipts yet.',
    hi: 'अभी तक रसीदों से कोई उत्पाद नहीं मिला है।',
  );
  String get lastObservedDateLabel => _t(
    ar: 'آخر رصد:',
    en: 'Last Observed:',
    hi: 'अंतिम देखा गया:',
  );
  String get barcodeLabel => _t(
    ar: 'الباركود:',
    en: 'Barcode:',
    hi: 'बारकोड:',
  );
  String get brandLabel => _t(
    ar: 'العلامة التجارية:',
    en: 'Brand:',
    hi: 'ब्रांड:',
  );
  String get categoryLabel => _t(
    ar: 'التصنيف:',
    en: 'Category:',
    hi: 'श्रेणी:',
  );
  String get scansCountLabel => _t(
    ar: 'مرات الرصد بالفواتير:',
    en: 'Total Receipt Scans:',
    hi: 'कुल रसीद स्कैन:',
  );
  String get quantitySoldLabel => _t(
    ar: 'الكمية الإجمالية بالفواتير:',
    en: 'Total Qty in Invoices:',
    hi: 'रसीदों में कुल मात्रा:',
  );
  String get originalPriceLabel => _t(
    ar: 'السعر قبل الخصم:',
    en: 'Original Price:',
    hi: 'छूट से पहले मूल्य:',
  );
  String get discountAmountLabel => _t(
    ar: 'قيمة الخصم:',
    en: 'Discount Amount:',
    hi: 'छूट राशि:',
  );
  String get netPriceLabel => _t(
    ar: 'السعر الصافي:',
    en: 'Net Price:',
    hi: 'शुद्ध मूल्य:',
  );
  String get exportPriceIntelligenceCsv => _t(
    ar: 'تصدير تقرير الأسعار (Excel/CSV)',
    en: 'Export Price Report (Excel/CSV)',
    hi: 'मूल्य रिपोर्ट निर्यात करें',
  );
  String get filterByBrand => _t(
    ar: 'تصفية حسب البراند',
    en: 'Filter by Brand',
    hi: 'ब्रांड द्वारा फ़िल्टर करें',
  );
  String get filterByPromotionsOnly => _t(
    ar: 'الأصناف المخفضة فقط',
    en: 'Discounted Only',
    hi: 'केवल छूट वाले',
  );
  String get sortByLatest => _t(
    ar: 'الأحدث رصداً',
    en: 'Recently Observed',
    hi: 'हाल ही में देखा गया',
  );
  String get sortByPriceLow => _t(
    ar: 'السعر: من الأقل للأعلى',
    en: 'Price: Low to High',
    hi: 'मूल्य: कम से अधिक',
  );
  String get sortByPriceHigh => _t(
    ar: 'السعر: من الأعلى للأقل',
    en: 'Price: High to Low',
    hi: 'मूल्य: अधिक से कम',
  );
  String get sortByVariance => _t(
    ar: 'الأعلى تفاوتاً في السعر',
    en: 'Highest Price Variance',
    hi: 'उच्चतम मूल्य भिन्नता',
  );
  String get viewReceiptPhoto => _t(
    ar: 'معاينة صورة الفاتورة',
    en: 'View Receipt Image',
    hi: 'रसीद छवि देखें',
  );

  // ---------------------------------------------------------------------------
  // AI Product Discovery & Company Products Filter
  // ---------------------------------------------------------------------------
  String get aiProductDiscoveryTitle => _t(
    ar: 'استكشاف الأصناف الجديدة بالذكاء الاصطناعي',
    en: 'AI Product Discovery from Invoices',
    hi: 'रसीदों से एआई उत्पाद खोज',
  );
  String get aiProductDiscoverySubtitle => _t(
    ar: 'تحليل الفواتير واكتشاف الأصناف التابعة للشركة وغير المسجلة بالداتابيز واعتمادها فوراً',
    en: 'Scan invoices with AI to discover uncataloged company products and save to Firebase',
    hi: 'एआई के साथ रसीदों को स्कैन करें और नए उत्पादों को डेटाबेस में सहेजें',
  );
  String get aiDiscoveredBannerTitle => _t(
    ar: 'تم اكتشاف أصناف جديدة غير مسجلة عبر الفواتير!',
    en: 'New uncataloged products discovered from invoices!',
    hi: 'रसीदों से नए असूचीबद्ध उत्पाद खोजे गए!',
  );
  String aiDiscoveredBannerSubtitle(int count, String company) => _t(
    ar: 'رصد الذكاء الاصطناعي ($count) أصناف جديدة تابعة لشركة $company. يمكنك مراجعتها واعتمادها لحفظها بقاعدة البيانات.',
    en: 'AI detected $count new items for $company. Review and approve them to save into database.',
    hi: 'एआई ने $company के लिए $count नए आइटम खोजे। डेटाबेस में सहेजने के लिए समीक्षा करें।',
  );
  String get reviewDiscoveredProducts => _t(
    ar: 'فحص واعتماد الأصناف (AI Review)',
    en: 'Review & Approve Products (AI)',
    hi: 'उत्पादों की समीक्षा और अनुमोदन (AI)',
  );
  String get discoverFromInvoicesBtn => _t(
    ar: 'استكشاف من الفواتير بالـ AI',
    en: 'AI Discover from Invoices',
    hi: 'रसीदों से एआई खोज',
  );
  String get approveAndSaveToCatalog => _t(
    ar: 'موافقة وحفظ في كتالوج الشركة (Firebase)',
    en: 'Approve & Save to Company Catalog (Firebase)',
    hi: 'स्वीकार करें और कंपनी सूची में सहेजें (Firebase)',
  );
  String get selectAllProducts => _t(
    ar: 'تحديد الكل',
    en: 'Select All',
    hi: 'सभी चुनें',
  );
  String get deselectAllProducts => _t(
    ar: 'إلغاء تحديد الكل',
    en: 'Deselect All',
    hi: 'सभी अचयनित करें',
  );
  String get appearedInInvoices => _t(
    ar: 'ظهر في الفواتير',
    en: 'Appeared in Invoices',
    hi: 'रसीदों में दिखाई दिया',
  );
  String get aiConfidenceHigh => _t(
    ar: 'مطابقة مؤكدة',
    en: 'High Confidence',
    hi: 'उच्च विश्वास',
  );
  String get companyProductsOnlyFilter => _t(
    ar: 'أصناف الشركة فقط',
    en: 'Company Products Only',
    hi: 'केवल कंपनी के उत्पाद',
  );
  String get allInvoiceProductsFilter => _t(
    ar: 'كافة أصناف الفواتير',
    en: 'All Invoice Products',
    hi: 'सभी रसीद उत्पाद',
  );
  String get noNewProductsDiscovered => _t(
    ar: 'جميع أصناف الفواتير مسجلة مسبقاً في كتالوج الشركة أو لا توجد أصناف جديدة غير مسجلة.',
    en: 'All invoice items are already in catalog, or no new uncataloged products were found.',
    hi: 'सभी रसीद आइटम पहले से ही कैटलॉग में हैं, या कोई नया उत्पाद नहीं मिला।',
  );
  String productsSavedSuccess(int count, String company) => _t(
    ar: 'تمت الموافقة بنجاح! تم حفظ ($count) صنف جديد في قاعدة بيانات $company بالفايربيز.',
    en: 'Successfully approved! Saved $count new products to $company catalog in Firebase.',
    hi: 'सफलतापूर्वक स्वीकृत! $company के लिए $count नए उत्पाद Firebase में सहेजे गए।',
  );
  String get compactTableDensity => _t(
    ar: 'عرض مدمج فائق الكثافة',
    en: 'Compact High-Density',
    hi: 'सघन उच्च-घनत्व',
  );
  String get standardTableDensity => _t(
    ar: 'عرض عادي مريح',
    en: 'Comfortable Standard',
    hi: 'आरामदायक मानक',
  );
  String get densityToggleTooltip => _t(
    ar: 'تبديل كثافة وحجم صفوف الجدول',
    en: 'Toggle table row density',
    hi: 'तालिका पंक्ति घनत्व बदलें',
  );
  String get discoveredProductsPendingApproval => _t(
    ar: 'أصناف جديدة مكتشفة من الفواتير بانتظار المراجعة والاعتماد',
    en: 'Discovered Products Pending Review & Approval',
    hi: 'समीक्षा और अनुमोदन के लिए लंबित नए उत्पाद',
  );
  String get discoveredProductsPendingSubtitle => _t(
    ar: 'تم استخراج هذه الأصناف تلقائياً من فواتير المشتريات ولم تسجل بعد في قاعدة البيانات. راجعها واضغط موافقة لاعتمادها.',
    en: 'These products were extracted from invoices and are not yet in database. Review and click approve to catalog them.',
    hi: 'ये उत्पाद रसीदों से निकाले गए हैं और अभी तक डेटाबेस में नहीं हैं। समीक्षा करें और अनुमोदित करें।',
  );
  String get barcodeAutoLinkedFromInvoices => _t(
    ar: 'تم ربط الباركود تلقائياً من الفواتير',
    en: 'Barcode auto-linked from invoices',
    hi: 'रसीदों से बारकोड स्वतः लिंक किया गया',
  );
  String get barcodeMissingInAllInvoices => _t(
    ar: 'لا يوجد باركود بالفواتير',
    en: 'No barcode in invoices',
    hi: 'रसीदों में कोई बारकोड नहीं',
  );
  String get approveAndCommitSelected => _t(
    ar: 'اعتماد وإضافة الأصناف المحددة لقاعدة البيانات',
    en: 'Approve & Save Selected to Database',
    hi: 'चयनित को डेटाबेस में स्वीकृत और सहेजें',
  );
  String get reviewDiscoveredProductsBtn => _t(
    ar: 'مراجعة الأصناف الجديدة',
    en: 'Review New Products',
    hi: 'नए उत्पादों की समीक्षा करें',
  );
  String get rowsPerPageLabel => _t(
    ar: 'عدد الصفوف:',
    en: 'Rows per page:',
    hi: 'प्रति पृष्ठ पंक्तियाँ:',
  );
}



