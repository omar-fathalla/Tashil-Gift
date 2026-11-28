import 'package:al_mraay/core/config/ai_config.dart';
import 'package:al_mraay/core/constants/ai_models.dart';
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
  String get exportExcelCsv => _t(ar: 'تصدير تقرير Excel', en: 'Export Excel Report', hi: 'Excel रिपोर्ट निर्यात करें');
  String get exportExcelBtn => _t(ar: 'تصدير إلى Excel', en: 'Export to Excel', hi: 'Excel में निर्यात करें');
  String get excelBtn => _t(ar: 'Excel', en: 'Excel', hi: 'Excel');
  String get csvBtn => _t(ar: 'CSV', en: 'CSV', hi: 'CSV');
  String get selectDay => _t(ar: 'اختر اليوم', en: 'Select Day', hi: 'दिन चुनें');
  String get totalLabel => _t(ar: 'الإجمالي', en: 'Total', hi: 'कुल');
  String get daysLabel => _t(ar: 'أيام', en: 'Days', hi: 'दिन');
  String get filterByDay => _t(ar: 'فلترة باليوم', en: 'Filter by Day', hi: 'दिन अनुसार फ़िल्टर');
  String get allDays => _t(ar: 'كافة الأيام', en: 'All Days', hi: 'सभी दिन');
  String get allDaysTotal => _t(ar: 'كافة الأيام (إجمالي الحملة)', en: 'All Days (Campaign Total)', hi: 'सभी दिन (कुल अभियान)');
  String get previousDay => _t(ar: 'اليوم السابق', en: 'Previous Day', hi: 'पिछला दिन');
  String get nextDay => _t(ar: 'اليوم التالي', en: 'Next Day', hi: 'अगला दिन');
  String get pickCustomDate => _t(ar: 'تحديد يوم مخصص', en: 'Pick Specific Date', hi: 'विशिष्ट तिथि चुनें');
  String operationFailed(String details) => _t(
    ar: 'فشلت العملية: $details',
    en: 'Operation failed: $details',
    hi: 'ऑपरेशन विफल रहा: $details',
  );

  // ---------------------------------------------------------------------------
  // 2. Navigation & Sidebar (M3 Concise Standard)
  // ---------------------------------------------------------------------------
  String get navEventsManagement => _t(ar: 'الحملات', en: 'Campaigns', hi: 'अभियान');
  String get navAnalytics => _t(ar: 'التقارير', en: 'Reports', hi: 'रिपोर्ट');
  String get navCompanyCatalog => _t(ar: 'التكويد', en: 'Catalog', hi: 'सूची');
  String get navRetailChains => _t(ar: 'السلاسل', en: 'Chains', hi: 'चेन');
  String get navProductsIntelligence => _t(ar: 'المنتجات', en: 'Products', hi: 'उत्पाद');
  String get navInvoicesAudit => _t(ar: 'الفواتير', en: 'Invoices', hi: 'रसीदें');
  String get navCreateCampaign => _t(ar: 'إنشاء حملة جديدة', en: 'Create New Campaign', hi: 'नया अभियान बनाएं');
  String get createCampaignTitle => _t(ar: 'إنشاء حملة ترويجية جديدة', en: 'Create New Promotional Campaign', hi: 'नया प्रचार अभियान बनाएं');
  String get navCompanyGifts => _t(ar: 'الهدايا', en: 'Gifts', hi: 'उपहार');
  String get navGameTypes => _t(ar: 'الألعاب', en: 'Games', hi: 'खेल');
  String get navAiSpeedBenchmark => _t(ar: 'AI KPI', en: 'AI KPI', hi: 'एआई केपीआई');
  String get navAiBrainRules => _t(ar: 'AI', en: 'AI', hi: 'एआई');
  String get navAiProductDiscovery => _t(ar: 'الأصناف', en: 'Products', hi: 'उत्पाद');
  String get navWhatsAppMarketing => _t(ar: 'واتساب', en: 'WhatsApp', hi: 'व्हाट्सएप');
  String get previewClientApp => _t(ar: 'معاينة تطبيق العميل / المندوب', en: 'Preview Client / Promoter App', hi: 'ग्राहक ऐप का पूर्वावलोकन');
  String get collapseMenu => _t(ar: 'إخفاء العناوين', en: 'Hide Labels', hi: 'लेबल छुपाएं');
  String get expandMenu => _t(ar: 'إظهار العناوين', en: 'Show Labels', hi: 'लेबल दिखाएं');

  // Partner / Company Portal Navigation (M3 Concise Standard)
  String get partnerNavAnalytics => _t(ar: 'المؤشرات والتحاليل', en: 'Analytics', hi: 'एनालिटिक्स');
  String get partnerNavComparison => _t(ar: 'مقارنة التحاليل', en: 'Comparisons', hi: 'تुलना');
  String get partnerNavInvoices => _t(ar: 'الفواتير', en: 'Invoices', hi: 'रसीदें');
  String get partnerNavSales => _t(ar: 'المبيعات', en: 'Sales', hi: 'बिक्री');
  String get partnerNavBalances => _t(ar: 'الأرصدة', en: 'Balances', hi: 'बैलेंस');
  String get partnerNavVouchers => _t(ar: 'Voucher', en: 'Voucher', hi: 'Voucher');
  String get partnerNavPromoter => _t(ar: 'Promoter', en: 'Promoter', hi: 'Promoter');

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
  String get analyticsTitle => _t(ar: 'منظومة التقارير والتحليلات', en: 'Reports & Analytics', hi: 'रिपोर्ट और विश्लेषण प्रणाली');
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
    en: 'Deleting invoice and clearing receipt data...',
    hi: 'रसीद हटाई जा रही है और डेटा खाली किया जा रहा है...',
  );
  String get stepAiSettings => _t(ar: '5. إعدادات الذكاء الاصطناعي (AI Prompt & OCR)', en: '5. AI Prompt & Verification Settings', hi: '5. एआई प्रॉम्ट और सत्यापन सेटिंग्स');
  String get campaignNameField => _t(ar: 'اسم الحملة (مثال: مهرجان المراعي)', en: 'Campaign Name (e.g. Almarai Fest)', hi: 'अभियान का नाम (उदा. अलमराई फेस्ट)');
  String get targetCompanyField => _t(ar: 'الشركة الراعية المستهدفة', en: 'Target Sponsor Company', hi: 'लक्षित प्रायोजक कंपनी');
  String get minSpendField => _t(ar: 'الحد الأدنى للشراء المؤهل', en: 'Minimum Spend Requirement', hi: 'न्यूनतम खरीदारी राशि');
  String get selectGameTypeField => _t(ar: 'نوع اللعبة التفاعلية', en: 'Interactive Game Type', hi: 'गेम का प्रकार');
  String get submitCreateCampaignBtn => _t(ar: 'حفظ وتفعيل الحملة فوراً', en: 'Save & Launch Campaign', hi: 'अभियाن सहेजें और शुरू करें');

  // ---------------------------------------------------------------------------
  // 10. Agent 7: Company Gifts & Stock (هدايا الشركات)
  // ---------------------------------------------------------------------------
  String get giftsTitle => _t(ar: 'كتالوج هدايا وجوائز الشركات', en: 'Company Master Gifts Catalog', hi: 'कंपनी मास्टर उपहार कैटलॉग');
  String get giftsSubtitle => _t(
    ar: 'تعريف وتوحيد مسميات الهدايا والجوائز وقسائم المشتريات المعتمدة لكل شركة',
    en: 'Define and standardize official company gifts, physical products, and vouchers',
    hi: 'कंपनी उपहारों, उत्पादों और वाउचर को परिभाषित और मानकीकृत करें',
  );
  String get addGiftCardTitle => _t(ar: 'إضافة هدية أو فواتشر للكتالوج المعتمد', en: 'Add Gift or Voucher to Master Catalog', hi: 'मास्टर कैटलॉग में उपहार या वाउचर जोड़ें');
  String get registeredGiftsTableTitle => _t(ar: 'كتالوج الهدايا والجوائز المعتمدة للشركة', en: 'Approved Gifts Catalog for Company', hi: 'कंपनी के लिए स्वीकृत उपहार सूची');
  String get giftNameField => _t(ar: 'اسم الهدية / المنتج', en: 'Gift / Product Name', hi: 'उपहार / उत्पाद का नाम');
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
  String get gameChooseGiftTitle => _t(ar: 'اختر هديتك (شبكة الاختيارات)', en: 'Choose Your Gift (Choice Grid)', hi: 'अपना उपहार चुनें (Choose Your Gift)');
  String get gameChooseGiftSubtitle => _t(
    ar: 'حرية اختيار الهدية المفضلة من بين مجموعة هدايا تفاعلية معتمدة',
    en: 'Freedom to pick the preferred gift from a curated interactive gift grid',
    hi: 'सत्यापित उपहारों के ग्रिड से अपना पसंदीदा उपहार चुनने की स्वतंत्रता',
  );
  String get gameChooseGiftDesc => _t(
    ar: 'تظهر للعميل بطاقات ومربعات تفاعلية بكافة الهدايا المتوفرة في الحملة والفرع، ليختار بنفسه الهدية التي تناسبه بلمسة واحدة وتأكيد فوري دون اعتماد على الحظ.',
    en: 'Customer is presented with a responsive grid of available campaign gifts to freely pick and confirm their favorite reward with a single tap.',
    hi: 'ग्राहक को उपलब्ध अभियान उपहारों का एक इंटरैक्टिव ग्रिड दिखाया जाता है ताकि वह बिना किसी भाग्य पर निर्भर हुए एक स्पर्श में अपना पसंदीदा उपहार चुन सके।',
  );
  String get chooseYourGiftPrompt => _t(ar: 'انقر على هديتك المفضلة للاختيار', en: 'Tap your favorite gift to select', hi: 'चुनने के लिए अपने पसंदीदा उपहार पर टैप करें');
  String get confirmGiftSelection => _t(ar: 'تأكيد اختيار الهدية', en: 'Confirm Gift Selection', hi: 'उपहार चयन की पुष्टि करें');
  String get selectGiftForChance => _t(ar: 'اختر الهدية للفرصة رقم', en: 'Select gift for chance #', hi: 'अवसर # के लिए उपहार चुनें');
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
  
  // ---------------------------------------------------------------------------
  // 14.0 Branch Stock Balances System (منظومة تغذية وتوزيع أرصدة الفروع)
  // ---------------------------------------------------------------------------
  String get branchBalancesNavTitle => _t(
    ar: 'الأرصدة',
    en: 'Branch Balances',
    hi: 'शाखा शेष',
  );
  // Gift stock report tab (TAG-79). Arabic & English only: `hi` falls back to English.
  String get partnerNavGiftStock => _t(ar: 'مخزون الهدايا', en: 'Gift Stock', hi: 'Gift Stock');
  String get giftStockNavSubtitle => _t(
    ar: 'رصيد الهدايا لكل فرع ودفعات التوريد وسجل الحركات',
    en: 'Gift balances per branch, supply batches & movements',
    hi: 'Gift balances per branch, supply batches & movements',
  );
  String get giftStockNavTooltip => _t(
    ar: 'تقرير للعرض فقط لمخزون الهدايا وحركاته',
    en: 'Read-only report of gift stock and its movements',
    hi: 'Read-only report of gift stock and its movements',
  );
  String get branchBalancesNavSubtitle => _t(
    ar: 'تغذية وتوزيع أرصدة الهدايا والقسائم على الفروع',
    en: 'Direct gift & voucher quota allocation across branches',
    hi: 'शाखाओं में प्रत्यक्ष उपहार और वाउचर कोटा आवंटन',
  );
  String get branchBalancesNavTooltip => _t(
    ar: 'المكان المركزي لتغذية وتحديد أرصدة الهدايا لكافة الفروع ومتابعة السحب',
    en: 'Central hub for feeding branch gift quotas and tracking live claims',
    hi: 'शाखा उपहार कोटा खिलाने और वास्तविक समय के दावों को ट्रैक करने का केंद्रीय केंद्र',
  );
  String get saveAllBalancesBtn => _t(
    ar: 'حفظ وتثبيت كافة الأرصدة',
    en: 'Save & Sync All Balances',
    hi: 'सभी शेष राशि सहेजें',
  );
  String get bulkDistributeTitle => _t(
    ar: 'شريط التوزيع الموحد السريع',
    en: 'Quick Bulk Distribution',
    hi: 'त्वरित थोक वितरण',
  );
  String get applyToAllBranchesBtn => _t(
    ar: 'تطبيق موحد على كافة الفروع',
    en: 'Apply to All Branches',
    hi: 'सभी शाखाओं पर लागू करें',
  );
  String get matrixGridView => _t(
    ar: 'كشف مصفوفة الفروع',
    en: 'Branch Matrix Grid',
    hi: 'शाखा मैट्रिक्स ग्रिड',
  );
  String get branchCardsView => _t(
    ar: 'بطاقات الفروع',
    en: 'Branch Cards',
    hi: 'शाखा कार्ड',
  );

  // ---------------------------------------------------------------------------
  // 15.0 Daily Branch Sales & Disbursals System (منظومة المبيعات وسحب الهدايا اليومي)
  // ---------------------------------------------------------------------------
  String get dailyBranchSalesNavTitle => _t(
    ar: 'المبيعات اليومية',
    en: 'Daily Sales & Gifts',
    hi: 'दैनिक बिक्री और उपहार',
  );
  String get dailyBranchSalesNavSubtitle => _t(
    ar: 'متابعة المبيعات والهدايا المنصرفة يومياً لكل فرع',
    en: 'Daily sales revenue and gift disbursals per branch',
    hi: 'प्रत्येक शाखा में दैनिक बिक्री और उपहार वितरण',
  );
  String get dailyBranchSalesNavTooltip => _t(
    ar: 'كشف تحليلي مفصل للمبيعات اليومية وتوزيع الهدايا والقسائم عبر أيام الفعالية',
    en: 'Detailed daily sales breakdown & gift disbursals across campaign days',
    hi: 'अभियान के दिनों में विस्तृत दैनिक बिक्री और उपहार वितरण विवरण',
  );
  String get syncAndBackfillDailySalesBtn => _t(
    ar: 'مزامنة وترميم السجلات',
    en: 'Sync & Backfill Daily Logs',
    hi: 'दैनिक लॉग सिंक और रीफ्रेश करें',
  );
  String get dailySalesTotalKpi => _t(
    ar: 'إجمالي مبيعات اليوم',
    en: 'Today\'s Total Sales',
    hi: 'आज की कुल बिक्री',
  );
  String get dailyInvoicesCountKpi => _t(
    ar: 'عدد الفواتير المنفذة',
    en: 'Invoices Processed',
    hi: 'संसाधित चालान',
  );
  String get dailyGiftsDisbursedKpi => _t(
    ar: 'إجمالي الهدايا المنصرفة',
    en: 'Gifts Handed Over',
    hi: 'वितरित कुल उपहार',
  );
  String get dailyVouchersValueKpi => _t(
    ar: 'قيمة الفواتشرات المنصرفة',
    en: 'Vouchers Disbursed',
    hi: 'वितरित वाउचर मूल्य',
  );
  String get prevDayBtn => _t(
    ar: 'اليوم السابق',
    en: 'Previous Day',
    hi: 'पिछला दिन',
  );
  String get nextDayBtn => _t(
    ar: 'اليوم التالي',
    en: 'Next Day',
    hi: 'अगला दिन',
  );
  String get todayBtn => _t(
    ar: 'اليوم الحالي',
    en: 'Today',
    hi: 'आज',
  );
  String get allCampaignDaysBtn => _t(
    ar: 'إجمالي أيام الحملة',
    en: 'All Campaign Days',
    hi: 'अभियान के सभी दिन',
  );
  String get branchSalesShareCol => _t(
    ar: 'نسبة مساهمة الفرع',
    en: 'Branch Share',
    hi: 'शाखा योगदान',
  );
  String get topProductsDailyTitle => _t(
    ar: 'أكثر المنتجات مبيعاً اليوم',
    en: 'Top Selling Products Today',
    hi: 'आज के सबसे अधिक बिकने वाले उत्पाद',
  );
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
    ar: '⚠️ تنبيه للمندوب: متبقي قطعة واحدة فقط من هذا الصنف في المخزون!',
    en: '⚠️ Promoter Alert: Only 1 unit remaining in stock!',
    hi: '⚠️ प्रमोटर चेतावनी: स्टॉक में केवल 1 इकाई शेष है!',
  );
  String get promoterLowStockWarningDouble => _t(
    ar: '⚠️ تنبيه للمندوب: متبقي قطعتان فقط من هذا الصنف في المخزون!',
    en: '⚠️ Promoter Alert: Only 2 units remaining in stock!',
    hi: '⚠️ प्रमोटر चेतावनी: स्टॉक में केवल 2 इकाइयां शेष हैं!',
  );
  String get directGiftOutOfStock => _t(
    ar: 'تم نفاد مخزون هذه الهدية بالفرع، يرجى مراجعة المشرف.',
    en: 'This gift is currently out of stock at the branch. Please check with supervisor.',
    hi: 'यह उपहार वर्तमान में शाखा में समाप्त हो गया है। कृपया पर्यवेक्षक से संपर्क करें।',
  );
  String directGiftOutOfStockAtBranch(String branchName) => _t(
    ar: 'تم نفاد مخزون هذه الهدية من ($branchName)، يرجى مراجعة المشرف.',
    en: 'This gift is out of stock at ($branchName). Please check with supervisor.',
    hi: '($branchName) में यह उपहार समाप्त हो गया है। कृपया पर्यवेक्षक से संपर्क करें।',
  );

  // ---------------------------------------------------------------------------
  // 12. Client Portal / Promoter Flow
  // ---------------------------------------------------------------------------
  String get clientWelcomeTitle => _t(ar: 'أهلاً بك في العرض الترويجي', en: 'Welcome to the Promotion', hi: 'प्रचार अभियान में आपका स्वागत है');
  String get uploadReceiptPrompt => _t(ar: 'التقط صورة الفاتورة للمشاركة في السحب', en: 'Take a photo of your receipt to participate', hi: 'भाग लेने के लिए अपनी रसीद की फोटो लें');
  String get scanReceiptBtn => _t(ar: 'تصوير الفاتورة الآن', en: 'Scan Receipt Now', hi: 'रसीद स्कैन करें');
  String get analyzingReceiptMsg => _t(ar: 'جاري فحص الفاتورة والتحقق بالذكاء الاصطناعي...', en: 'AI is analyzing and verifying your receipt...', hi: 'एआई आपकी रसीद का सत्यापन कर रहा है...');
  String get congratulationsWon => _t(ar: 'مبروك! لقد فزت بجائزة قيمة!', en: 'Congratulations! You won a prize!', hi: 'बधाई हो! आपने एक शानदार उपहार जीता है!');
  String get claimPrizeBtn => _t(ar: 'استلام الجائزة من المندوب', en: 'Claim Prize from Promoter', hi: 'प्रमोटर से पुरस्कार प्राप्त करें');

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
  String get exportCsvBtn => _t(ar: 'CSV', en: 'CSV', hi: 'CSV');
  String get productNameCol => _t(ar: 'اسم المنتج', en: 'Product Name', hi: 'उत्पाद का नाम');
  String get barcodeCol => _t(ar: 'الباركود', en: 'Barcode', hi: 'बारकोड');
  String get quantityCol => _t(ar: 'الكمية', en: 'Qty', hi: 'मात्रा');
  String get unitPriceCol => _t(ar: 'السعر', en: 'Price', hi: 'मूल्य');
  String get totalPriceCol => _t(ar: 'الإجمالي', en: 'Total', hi: 'कुल');
  String get itemCategoryCol => _t(ar: 'حالة الصنف', en: 'Item Status', hi: 'उत्पाद स्थिति');
  String get includedInPromo => _t(ar: 'مشمول بالعرض', en: 'Promo Target', hi: 'प्रचार में शामिल');
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

  // Rejection reasons & Smart Re-verification actions
  String get recheckInvoiceAction => _t(ar: 'إعادة الفحص', en: 'Re-verify', hi: 'पुنः जाँचें');
  String get recheckInvoiceTooltip => _t(
    ar: 'إعادة فحص الفاتورة ومطابقتها لشروط الحملة المحدثة',
    en: 'Re-verify receipt against updated campaign conditions',
    hi: 'अद्यतन अभियान शर्तों के विरुद्ध रसीद की पुनः जाँच करें',
  );
  String get rejectionReasonLabel => _t(ar: 'سبب الرفض:', en: 'Rejection Reason:', hi: 'अस्वीकृति का कारण:');
  String get recheckSuccessTitle => _t(
    ar: 'تم قبول الفاتورة بنجاح!',
    en: 'Receipt Approved Successfully!',
    hi: 'रसीद सफलतापूर्वक स्वीकृत!',
  );
  String get recheckSuccessMessage => _t(
    ar: 'أصبحت الفاتورة مطابقة لكافة الشروط والأحكام المعتمدة.',
    en: 'The receipt now meets all campaign terms and rules.',
    hi: 'रसीद अब सभी अभियान नियमों और शर्तों को पूरा करती है।',
  );
  String get recheckStillRejectedMessage => _t(
    ar: 'لا تزال الفاتورة غير مستوفية لشروط الحملة',
    en: 'Receipt still does not satisfy campaign requirements',
    hi: 'रसीद अभी भी अभियान आवश्यकताओं को पूरा नहीं करती है',
  );
  String get quickRecheckTitle => _t(
    ar: 'فحص سريع للقواعد الحالية',
    en: 'Quick Rule Re-Match',
    hi: 'त्वरित नियम मिलान',
  );
  String get quickRecheckSubtitle => _t(
    ar: 'إعادة تدقيق الأصناف والفرع ضد شروط الحملة المحدثة (لحظي)',
    en: 'Re-audit extracted items and branch against updated rules (Instant)',
    hi: 'अद्यतन नियमों के विरुद्ध निकाले गए उत्पादों और शाखा का पुनः ऑडिट (त्वरित)',
  );
  String get fullAiRecheckTitle => _t(
    ar: 'إعادة المسح الشامل بالذكاء الاصطناعي',
    en: 'Full AI Re-Scan (${AiConfig.fastTierModel})',
    hi: 'पूर्ण एआई पुनः स्कैन (${AiConfig.fastTierModel})',
  );
  String get fullAiRecheckSubtitle => _t(
    ar: 'إعادة قراءة صورة الفاتورة الأصلية بأحدث كتالوج وتوجيهات للذكاء الاصطناعي',
    en: 'Re-read original receipt image with updated catalog barcodes & directives',
    hi: 'अद्यतन कैटलॉग बारकोड और निर्देशों के साथ मूल रसीद छवि को फिर से पढ़ें',
  );
  String get recheckingReceiptLoading => _t(
    ar: 'جاري إعادة فحص الفاتورة...',
    en: 'Re-verifying receipt...',
    hi: 'रसीद की पुनः जाँच की जा रही है...',
  );

  // Promoter Invoices Dialog Date & Status filter strings
  String get pickDateOrRangeTitle => _t(
    ar: 'تحديد تاريخ أو فترة زمنية',
    en: 'Select Date or Range',
    hi: 'तारीख या अवधि चुनें',
  );
  String get singleDayOption => _t(
    ar: 'اختيار يوم محدد',
    en: 'Specific Single Day',
    hi: 'एक विशिष्ट दिन',
  );
  String get singleDaySubtitle => _t(
    ar: 'عرض فواتير يوم بعينه بالتقويم',
    en: 'View receipts for a specific day',
    hi: 'विशिष्ट दिन की रसीदें देखें',
  );
  String get dateRangeOption => _t(
    ar: 'اختيار فترة زمنية (من - إلى)',
    en: 'Date Range (From - To)',
    hi: 'तिथि सीमा (से - तक)',
  );
  String get dateRangeSubtitle => _t(
    ar: 'تحديد نطاق أيام مرن مع أنيميشن التحديد',
    en: 'Flexible range selection with animated highlight',
    hi: 'एनिमेटेड हाइलाइट के साथ लचीली रेंज',
  );
  String get filterAcceptedInvoices => _t(
    ar: 'المعتمدة',
    en: 'Approved',
    hi: 'स्वीकृत',
  );
  String get filterRejectedInvoices => _t(
    ar: 'المرفوضة',
    en: 'Rejected',
    hi: 'अस्वीकृत',
  );
  String get clearCustomDate => _t(
    ar: 'إلغاء التاريخ المخصص',
    en: 'Clear Custom Date',
    hi: 'कस्टम तारीख हटाएं',
  );

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
    ar: 'نسخ رابط العميل / المندوب',
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
    ar: 'تم نسخ رابط المندوب والعميل بنجاح',
    en: 'Promoter & Client link copied successfully',
    hi: 'प्रमोटر और ग्राहक लिंक सफलतापूर्वक कॉपी किया गया',
  );
  String get managerPortalLinkCopied => _t(
    ar: 'تم نسخ رابط بوابة مدير الشركة بنجاح',
    en: 'Company Manager Portal link copied successfully',
    hi: 'कंपनी प्रबंधक पोर्टल लिंक सफलतापूर्वक कॉपी किया गया',
  );
  String get partnerPortalBadge => _t(
    ar: 'بوابة الشريك',
    en: 'Partner Portal',
    hi: 'भागीदार पोर्टल',
  );
  String get analyticsSubtitle => _t(
    ar: 'التحليلات والمؤشرات والأداء',
    en: 'Analytics, KPIs & Performance',
    hi: 'एनालिटिक्स, केपीआई और प्रदर्शन',
  );
  String get invoicesSubtitle => _t(
    ar: 'التدقيق المباشر وتصدير البيانات',
    en: 'Live Audit & Data Export',
    hi: 'लाइव ऑडिट और डेटा निर्यात',
  );
  String get collapseSidebar => _t(
    ar: 'تصغير القائمة',
    en: 'Collapse Menu',
    hi: 'मेनू छोटा करें',
  );
  String get expandSidebar => _t(
    ar: 'توسيع القائمة',
    en: 'Expand Menu',
    hi: 'मेनू बड़ा करें',
  );

  // ---------------------------------------------------------------------------
  // 14.1 Prizes & Stock Balance System (منظومة رصيد وجرد الهدايا والمخزون)
  // ---------------------------------------------------------------------------
  String get prizesStockTitle => _t(
    ar: 'الهدايا',
    en: 'Gifts & Stock',
    hi: 'उपहार और स्टॉक',
  );
  String get prizesStockSubtitle => _t(
    ar: 'جرد وأرصدة الهدايا المباشرة بالفروع ومتابعة المسحوبات اللحظية',
    en: 'Real-time branch gift stock balances, allocations, and customer claims',
    hi: 'शाखा उपहार स्टॉक शेष, आवंटन और वास्तविक समय के दावे',
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
  String get vouchersNavTitle => _t(
    ar: 'قسائم المشتريات',
    en: 'Vouchers & Gift Cards',
    hi: 'शॉपिंग वाउचर',
  );
  String get vouchersNavSubtitle => _t(
    ar: 'أرصدة وفئات القسائم وتوزيع الميزانيات بالفروع',
    en: 'Voucher Denominations, Budgets & Branch Matrix',
    hi: 'वाउचर श्रेणियां, बजट और शाखा वितरण',
  );
  String get vouchersNavTooltip => _t(
    ar: 'منظومة تفصيلية لإدارة ومتابعة قسائم المشتريات والفواتشر والميزانيات المالية',
    en: 'Comprehensive Voucher & Purchasing Gift Cards Intelligence System',
    hi: 'व्यापक वाउचर और गिफ्ट कार्ड प्रबंधन प्रणाली',
  );
  String get exportVouchersExcel => _t(
    ar: 'تصدير تقرير القسائم Excel',
    en: 'Export Vouchers Excel',
    hi: 'वाउचर एक्सेल रिपोर्ट निर्यात करें',
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

  // Hero Platform Showcase & System Pillars
  String get heroBrandHeadline => _t(
    ar: 'منظومة سويتش بوينت الذكية',
    en: 'Switch Point Smart Platform',
    hi: 'स्विच पॉइंट स्मार्ट प्लेटफॉर्म',
  );
  String get heroPlatformTagline => _t(
    ar: 'المنظومة الذكية الرائدة لإدارة الحملات الترويجية والتحقق الفوري من الفواتير بالذكاء الاصطناعي',
    en: 'The Leading AI-Powered Platform for Promotional Campaigns & Smart Receipt Verification',
    hi: 'प्रचार अभियानों और स्मार्ट रसीद सत्यापन के लिए अग्रणी एआई-संचालित मंच',
  );
  String get heroGeminiModelBadge => _t(
    ar: 'مدعوم بمحرك ${AiModels.defaultPrimaryLabel}',
    en: 'Powered by ${AiModels.defaultPrimaryLabel}',
    hi: '${AiModels.defaultPrimaryLabel} द्वारा संचालित',
  );
  String get heroAntiFraudBadge => _t(
    ar: 'حوكمة وحماية من الاحتيال 100%',
    en: '100% Anti-Fraud & Single-Resolution',
    hi: '100% धोखाधड़ी-रोधी और एकल-समाधान',
  );
  String get heroPillar1Title => _t(
    ar: 'إدارة الحملات والفعاليات الترويجية',
    en: 'Promotional Campaigns & Events Engine',
    hi: 'प्रचार अभियान और कार्यक्रम इंजन',
  );
  String get heroPillar1Desc => _t(
    ar: 'إطلاق وتخصيص عروض الهايبرماركت والشركات: خصومات مباشرة، سحوبات، فوتشرات، وعجلة الحظ.',
    en: 'Launch & manage retail & brand events: direct discounts, digital raffles, instant vouchers & lucky wheels.',
    hi: 'खुदरा और ब्रांड इवेंट लॉन्च और प्रबंधित करें: सीधी छूट, डिजिटल रैफ़ल, तत्काल वाउचर और भाग्य का पहिया।',
  );
  String get heroPillar2Title => _t(
    ar: 'فحص الفواتير والأسعار بالذكاء الاصطناعي',
    en: 'AI Receipt OCR & Price Intelligence',
    hi: 'एआई रसीद ओसीआर और मूल्य खुफिया',
  );
  String get heroPillar2Desc => _t(
    ar: 'تدقيق فوري لفواتير الكاشير، استخراج دقيق للأصناف، حساب اقتصاديات القطعة، ومقارنة الأسعار لحظياً.',
    en: 'Instant POS receipt OCR, exact item extraction, single unit economics & real-time price comparison.',
    hi: 'तत्काल पीओएस रसीद ओसीआर, सटीक वस्तु निष्कर्षण, एकल इकाई अर्थशास्त्र और वास्तविक समय मूल्य तुलना।',
  );
  String get heroPillar3Title => _t(
    ar: 'حوكمة الجوائز والمخزون اللحظي',
    en: 'Gift Governance & Live Inventory',
    hi: 'उपहार शासन और लाइव इन्वेंटरी',
  );
  String get heroPillar3Desc => _t(
    ar: 'احتساب عادل للجوائز المكتسبة، إيصالات رقمية ورموز QR/OTP مؤمنة، ومزامنة حية مع أرصدة الفروع.',
    en: 'Zero duplicate allocation, tamper-proof QR/OTP digital receipts, and live sync with branch stock.',
    hi: 'शून्य दोहराव आवंटन, छेड़छाड़-रोधी क्यूआर/ओटीपी डिजिटल रसीदें, और शाखा स्टॉक के साथ लाइव सिंक।',
  );
  String get heroPillar4Title => _t(
    ar: 'بوابات وتقارير إدارية متعددة الشركات',
    en: 'Multi-Tenant Portals & Live Analytics',
    hi: 'मल्टी-टेनेंट पोर्टल और लाइव एनालिटिक्स',
  );
  String get heroPillar4Desc => _t(
    ar: 'لوحات تحكم للإدارة والشركات والمحققين، مؤشرات أداء تفاعلية (KPIs)، وقياس عائد الاستثمار الترويجي.',
    en: 'Role-based portals for Admins, Brands & Cashiers, live KPIs, branch sales logs & campaign ROI.',
    hi: 'एडमिन, ब्रांड और कैशियर के लिए भूमिका-आधारित पोर्टल, लाइव केपीआई, शाखा बिक्री लॉग और अभियान आरओआई।',
  );
  String get heroStatSpeed => _t(
    ar: '< 1.8 ث',
    en: '< 1.8s',
    hi: '< 1.8s',
  );
  String get heroStatSpeedLabel => _t(
    ar: 'سرعة التحقق والمعالجة',
    en: 'Avg AI OCR Speed',
    hi: 'औसत एआई ओसीआर गति',
  );
  String get heroStatAccuracy => _t(
    ar: '99.8%',
    en: '99.8%',
    hi: '99.8%',
  );
  String get heroStatAccuracyLabel => _t(
    ar: 'دقة استخراج البيانات',
    en: 'Extraction Accuracy',
    hi: 'निष्कर्षण सटीकता',
  );
  String get heroStatGovernance => _t(
    ar: '100%',
    en: '100%',
    hi: '100%',
  );
  String get heroStatGovernanceLabel => _t(
    ar: 'انضباط حوكمة الجوائز',
    en: 'Gift Allocation Integrity',
    hi: 'उपहार आवंटन अखंडता',
  );
  String get heroEnterpriseSecurityNote => _t(
    ar: 'منظومة مؤمنة بتشفير سحابي عالي ومطابقة لمعايير أمن المعلومات المؤسسية',
    en: 'Enterprise-grade cloud encryption and secure zero-trust session management',
    hi: 'एंटरप्राइज-ग्रेड क्लाउड एन्क्रिप्शन और सुरक्षित शून्य-विश्वास सत्र प्रबंधन',
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
  String get addNextReceiptPartBtn => _t(
    ar: 'إضافة جزء (فاتورة طويلة)',
    en: 'Add Part (Long Receipt)',
    hi: 'भाग जोड़ें (लंबी रसीद)',
  );
  String get longReceiptTip => _t(
    ar: 'للفواتير الطويلة التي لا تتسع لكادر واحد، التقط صور أجزاء نفس الفاتورة من الأعلى للأسفل لدمج البنود بدقة 100%.',
    en: 'For long receipts exceeding a single camera frame, capture consecutive parts of the same receipt top-to-bottom for 100% accurate stitching.',
    hi: 'एक फ्रेम में न आने वाली लंबी रसीदों के लिए, 100% सटीक मिलान के लिए एक ही रसीद के लगातार भागों को ऊपर से नीचे तक कैप्चर करें।',
  );
  String partIndexLabel(int index) => _t(
    ar: 'جزء $index',
    en: 'Part $index',
    hi: 'भाग $index',
  );
  String get deletePartTooltip => _t(
    ar: 'حذف هذا الجزء',
    en: 'Delete this part',
    hi: 'इस भाग को हटाएं',
  );
  String analyzeMultiPartsBtn(int count) => _t(
    ar: 'فحص الفاتورة بالذكاء الاصطناعي ($count أجزاء) 🎁',
    en: 'Audit Receipt with AI ($count parts) 🎁',
    hi: 'एआई से रसीद जांचें ($count भाग) 🎁',
  );
  String get clearAllPartsBtn => _t(
    ar: 'مسح الكل',
    en: 'Clear All',
    hi: 'सभी साफ़ करें',
  );
  String get maxPartsReachedAlert => _t(
    ar: 'الحد الأقصى لأجزاء الفاتورة الواحدة هو 4 أجزاء متتالية.',
    en: 'Maximum number of parts for a single receipt is 4 consecutive images.',
    hi: 'एक रसीद के लिए अधिकतम भागों की संख्या 4 है।',
  );
  String get pickNextPartGallery => _t(
    ar: 'اختيار جزء من الاستوديو',
    en: 'Pick part from Gallery',
    hi: 'गैलरी से भाग चुनें',
  );
  String get captureNextPartCamera => _t(
    ar: 'تصوير الجزء بالكاميرا',
    en: 'Capture part with Camera',
    hi: 'कैمरे से भाग लें',
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
    ar: 'بوابة التحقق الذكي للعملاء والمندوب',
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
    ar: 'فحص الفاتورة بالذكاء الاصطناعي',
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
    ar: '🔄 تنسيق وتحديث تعليمات قراءة الفواتير تلقائياً من القواعد المعتمدة',
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
    ar: 'تحديد ما إذا كان إدخال الأرقام التسلسلية لكروت الفواتشرات إلزامياً للمندوب عند تسليم الهدية أو اختيارياً (الافتراضي: اختياري)',
    en: 'Determine whether entering voucher serial numbers is mandatory or optional for promoters upon gift handover (Default: Optional)',
    hi: 'निर्धारित करें कि उपहार सौंपते समय प्रमोटरों के लिए वाउचर सीरियल दर्ज करना अनिवार्य है या वैकल्पिक (डिफ़ॉल्ट: वैकल्पिक)',
  );
  String get voucherSerialsMandatoryBadge => _t(
    ar: 'إلزامي للمندوب',
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
    ar: 'بوابة المندوب والعميل',
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
    ar: 'بوابة المندوب والعميل مفعلة حالياً - اضغط لإيقاف استقبال الفواتير',
    en: 'Promoter portal is active - tap to pause receipt submission',
    hi: 'प्रमोटर पोर्टल सक्रिय है - रसीद सबमिशन रोकने के लिए टैप करें',
  );
  String get promoterPortalToggleTooltipPaused => _t(
    ar: 'بوابة المندوب والعميل متوقفة - اضغط لإعادة تفعيلها فورياً',
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
    ar: 'فرعي المثبت',
    en: 'Pinned Branch',
    hi: 'पिन की गई शाखा',
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
  // 26. Chain Products & Price Intelligence (رادار حماية ودفاع أسعار أسواق فتح الله)
  // ---------------------------------------------------------------------------
  String get productsIntelligenceTitle => _t(
    ar: 'رادار مراقبة وحماية الأسعار عبر السلاسل',
    en: 'Cross-Chain Price Defense & Intelligence',
    hi: 'क्रॉस-चेन मूल्य रक्षा और खुफिया',
  );
  String get productsIntelligenceSubtitle => _t(
    ar: 'رصد فوري لأسعار المنافسين، إنذار مبكر لكسر الأسعار، ومقارنة حية لأسواق فتح الله',
    en: 'Real-time competitor price tracking, threat alerts & live comparison against Fathalla Markets',
    hi: 'रीयल-टाइम प्रतियोगी मूल्य ट्रैकिंग, खतरा अलर्ट और फथल्ला मार्केट्स के खिलाफ लाइव तुलना',
  );
  String get fathallaBaselineTag => _t(
    ar: 'المرجع الأساسي: أسواق فتح الله',
    en: 'Baseline Chain: Fathalla Markets',
    hi: 'आधारभूत श्रृंखला: फथल्ला मार्केट्स',
  );
  String get metricPriceThreats => _t(
    ar: 'تنبيهات كسر الأسعار (المنافس أرخص)',
    en: 'Price Threat Alerts (Competitor Cheaper)',
    hi: 'मूल्य खतरा अलर्ट (प्रतियोगी सस्ता)',
  );
  String get metricCompetitorPromosNotAtFathalla => _t(
    ar: 'عروض غير متوفرة بفتح الله (فرص جديدة)',
    en: 'Competitor Promos not at Fathalla (Opportunities)',
    hi: 'प्रतियोगी ऑफर जो फथल्ला में नहीं हैं',
  );
  String get metricCompetitorPromosNotAtFathallaSubtitle => _t(
    ar: 'فرص إضافة وتوفير أصناف جديدة',
    en: 'New SKU Sourcing Opportunities',
    hi: 'नए उत्पाद सोर्सिंग अवसर',
  );
  String get metricAllCompetitorPromotions => _t(
    ar: 'كافة عروض وخصومات المنافسين',
    en: 'All Competitor Active Promos',
    hi: 'सभी प्रतियोगी सक्रिय ऑफर',
  );
  String get metricThreatsWithPromo => _t(
    ar: 'كسر أسعار مقترن بعروض ترويجية',
    en: 'Threats with Promo Discount',
    hi: 'प्रमोशन के साथ मूल्य खतरे',
  );
  String get headToHeadModeLabel => _t(
    ar: 'مقارنة مباشرة بين سلسلتين',
    en: 'Head-to-Head Chain Comparison',
    hi: 'आमने-सामने श्रृंखला तुलना',
  );
  String get omniRadarModeLabel => _t(
    ar: 'رادار مراقبة السوق الشامل',
    en: 'Omni-Chain Market Radar',
    hi: 'सर्वव्यापी बाजार रडार',
  );
  String get chain1SelectorLabel => _t(
    ar: 'السلسلة الأولى (المرجع)',
    en: 'First Chain (Anchor)',
    hi: 'पहली श्रृंखला (आधार)',
  );
  String get chain2SelectorLabel => _t(
    ar: 'السلسلة الثانية (المنافس)',
    en: 'Second Chain (Competitor)',
    hi: 'दूसरी श्रृंखला (प्रतियोगी)',
  );
  String get metricFathallaWinning => _t(
    ar: 'أصناف تفوق فتح الله (أنت الأرخص 🏆)',
    en: 'Fathalla Best Price (Winning 🏆)',
    hi: 'फथल्ला सर्वोत्तम मूल्य (विजेता 🏆)',
  );
  String get metricSharedSkus => _t(
    ar: 'الأصناف المشتركة بالمقارنة',
    en: 'Shared Compared SKUs',
    hi: 'तुलना किए गए उत्पाद',
  );
  String get metricArchivedSkus => _t(
    ar: 'كافة الأصناف بالأرشيف',
    en: 'All Archived SKUs',
    hi: 'सभी संग्रहीत उत्पाद',
  );
  String get filterSegmentThreatsOnly => _t(
    ar: 'الأصناف الأرخص عند المنافسين',
    en: 'Cheaper at Competitors',
    hi: 'प्रतियोगियों पर सस्ता',
  );
  String get filterSegmentFathallaWinning => _t(
    ar: 'أصناف تفوق فتح الله 🏆',
    en: 'Fathalla Best Price 🏆',
    hi: 'फथल्ला सर्वोत्तम मूल्य 🏆',
  );
  String get filterSegmentSharedOnly => _t(
    ar: 'الأصناف المشتركة (سلسلتين فأكثر) 📊',
    en: 'Shared SKUs (2+ Chains) 📊',
    hi: 'साझा उत्पाद (2+ श्रृंखलाएं) 📊',
  );
  String get filterSegmentAllArchive => _t(
    ar: 'جميع الأصناف بالأرشيف',
    en: 'All Archived SKUs (Full Search)',
    hi: 'संग्रह में सभी उत्पाद (पूर्ण खोज)',
  );
  String get fathallaMarketPositionLabel => _t(
    ar: 'موقف فتح الله التنافسي',
    en: 'Fathalla Market Position',
    hi: 'फथल्ला बाजार स्थिति',
  );
  String get competitorCheaperWarningBadge => _t(
    ar: 'المنافس أرخص منك',
    en: 'Competitor Cheaper',
    hi: 'प्रतियोगी सस्ता है',
  );
  String get fathallaBestInMarketBadge => _t(
    ar: 'فتح الله الأرخص في السوق 🌟',
    en: 'Fathalla Best in Market 🌟',
    hi: 'बाजार में फथल्ला सबसे सस्ता 🌟',
  );
  String get marketPricesMatchedBadge => _t(
    ar: 'سعر متطابق مع المنافسين ⚪',
    en: 'Matched Competitor Price ⚪',
    hi: 'प्रतियोगी के समान मूल्य ⚪',
  );
  String get fathallaPriceMissingBadge => _t(
    ar: 'غير مسجل بفتح الله 🏷️',
    en: 'Not in Fathalla 🏷️',
    hi: 'फथल्ला में नहीं 🏷️',
  );
  String get proofOfReceiptLabel => _t(
    ar: 'معاينة البون والإثبات',
    en: 'Proof of Receipt',
    hi: 'रसीद का प्रमाण',
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
  String get sortByThreatDiff => _t(
    ar: 'فارق كسر السعر (الأكبر أولاً)',
    en: 'Price Threat Gap (Highest First)',
    hi: 'मूल्य अंतर (सबसे अधिक पहले)',
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
    ar: 'موافقة وحفظ في كتالوج الشركة',
    en: 'Approve & Save to Company Catalog',
    hi: 'स्वीकार करें और कंपनी सूची में सहेजें',
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
  String get discoveryHubTitle => _t(
    ar: 'مركز استكشاف وتحديث أصناف الشركات بالذكاء الاصطناعي',
    en: 'AI Product Discovery & Catalog Enrichment Hub',
    hi: 'एआई उत्पाद खोज और कैटलॉग संवर्धन केंद्र',
  );
  String get discoveryHubSubtitle => _t(
    ar: 'الحصاد التلقائي للأصناف والباركودات الجديدة من واقع فواتير المبيعات واعتمادها في كتالوج الشركات',
    en: 'Automated harvesting of new products and barcodes from real sales receipts and syncing to catalogs',
    hi: 'बिक्री रसीदों से नए उत्पादों और बारकोड का स्वचालित संकलन और कैटलॉग में सिंक',
  );
  String get pendingTabLabel => _t(ar: 'بانتظار الاعتماد', en: 'Pending Review', hi: 'समीक्षा लंबित');
  String get approvedTabLabel => _t(ar: 'المعتمدة بالكتالوج', en: 'Approved & Synced', hi: 'स्वीकृत और सिंक');
  String get rejectedTabLabel => _t(ar: 'المستبعدة', en: 'Dismissed', hi: 'खारिज');
  String get allCompaniesFilter => _t(ar: 'كافة الشركات', en: 'All Companies', hi: 'सभी कंपनियां');
  String get cleanInboxCriteriaAction => _t(ar: 'تطبيق المعايير وتنظيف الصندوق', en: 'Apply Criteria & Clean Inbox', hi: 'मानदंड लागू करें और इनबॉक्स साफ़ करें');
  String get criteriaCompliantBadge => _t(ar: 'مطابق 5/5 معايير', en: '5/5 Compliant', hi: '5/5 अनुरूप');
  String get scanPastInvoicesAction => _t(ar: 'فحص واستكشاف الفواتير السابقة', en: 'Deep Scan Historical Invoices', hi: 'पिछली रसीदें स्कैन करें');
  String get approveAllPendingAction => _t(ar: 'اعتماد الكل وإضافتها للكتالوج', en: 'Approve All & Sync to Catalog', hi: 'सभी को स्वीकार और सिंक करें');
  String get approveSingleItemAction => _t(ar: 'اعتماد', en: 'Approve', hi: 'स्वीकार करें');
  String get rejectSingleItemAction => _t(ar: 'استبعاد', en: 'Dismiss', hi: 'खारिज करें');
  String get editItemTitle => _t(ar: 'تعديل بيانات الصنف قبل الاعتماد', en: 'Edit Product Details Before Approval', hi: 'अनुमोदन से पहले विवरण संपादित करें');
  String get canonicalNameField => _t(ar: 'الاسم المعتمد للصنف', en: 'Canonical Product Name', hi: 'मानक उत्पाद का नाम');
  String get brandField => _t(ar: 'العلامة التجارية', en: 'Brand', hi: 'ब्रांड');
  String get discoveryCategoryField => _t(ar: 'القسم والتصنيف', en: 'Category', hi: 'श्रेणी');
  String get unitSizeField => _t(ar: 'الحجم / العبوة', en: 'Unit Size', hi: 'इकाई आकार');
  String get discoveryBarcodeField => _t(ar: 'الباركود الدولي', en: 'Barcode', hi: 'बारकोड');
  String get averagePriceField => _t(ar: 'متوسط السعر', en: 'Average Price', hi: 'औसत मूल्य');
  String get retailChainsObserved => _t(ar: 'السلاسل التي رُصد بها', en: 'Observed Retail Chains', hi: 'देखी गई रिटेल चेन');
  String get frequencyCount => _t(ar: 'مرات الظهور', en: 'Frequency', hi: 'बारंबारता');
  String get confidenceMetric => _t(ar: 'مؤشر الثقة', en: 'Confidence', hi: 'विश्वास सूचकांक');
  String get emptyDiscoveryStateTitle => _t(ar: 'لا توجد أصناف جديدة بانتظار الاعتماد', en: 'No Pending Products to Review', hi: 'समीक्षा के लिए कोई नया उत्पाद नहीं');
  String get emptyDiscoveryStateSubtitle => _t(
    ar: 'جميع أصناف فواتير المبيعات الحالية مسجلة مسبقاً في الكتالوج، وسيقوم الذكاء الاصطناعي بحصاد أي صنف جديد تلقائياً عند فحص الفواتير.',
    en: 'All current sales receipt items are already cataloged. AI will automatically harvest any new item during future scans.',
    hi: 'सभी वर्तमान रसीद उत्पाद पहले से ही कैटलॉग में हैं। भविष्य के स्कैन में एआई स्वतः नए आइटम एकत्र करेगा।',
  );
  String get rowsPerPageLabel => _t(
    ar: 'عدد الصفوف:',
    en: 'Rows per page:',
    hi: 'प्रति पृष्ठ पंक्तियाँ:',
  );

  // ---------------------------------------------------------------------------
  // Branch & Chain Distribution Charts Localization
  // ---------------------------------------------------------------------------
  String get chartViewDonut => _t(
    ar: 'مخطط دائري تفاعلي',
    en: 'Interactive Donut',
    hi: 'डोनट चार्ट',
  );
  String get chartViewBar => _t(
    ar: 'مخطط أعمدة مقارن',
    en: 'Bar Chart',
    hi: 'बार चार्ट',
  );
  String get chartViewList => _t(
    ar: 'ترتيب وبطاقات الأداء',
    en: 'Leaderboard Cards',
    hi: 'रैंकिंग कार्ड',
  );
  String get aggregationBranches => _t(
    ar: 'فروع ومنافذ البيع',
    en: 'Individual Outlets',
    hi: 'शाखाएं और आउटलेट',
  );
  String get aggregationChains => _t(
    ar: 'السلاسل والماركت',
    en: 'Retail Chains',
    hi: 'रिटेल चेन',
  );
  String get metricRevenue => _t(
    ar: 'حجم المبيعات المالية',
    en: 'Sales Revenue',
    hi: 'बिक्री राजस्व',
  );
  String get metricReceiptsCount => _t(
    ar: 'عدد الفواتير',
    en: 'Receipts Count',
    hi: 'रसीदों की संख्या',
  );
  String get branchPerformanceBreakdown => _t(
    ar: 'توزيع وتحليلات أداء الفروع والسلاسل التجارية',
    en: 'Branch & Retail Chain Performance Intelligence',
    hi: 'शाखा और रिटेल चेन प्रदर्शन विश्लेषण',
  );
  String get avgTicketValue => _t(
    ar: 'متوسط الفاتورة',
    en: 'Avg Receipt',
    hi: 'औसत रसीद',
  );
  String get totalActiveBranches => _t(
    ar: 'المنافذ النشطة',
    en: 'Active Outlets',
    hi: 'सक्रिय आउटलेट',
  );
  String get topPerformingBranch => _t(
    ar: 'الأعلى مبيعاً',
    en: 'Top Performer',
    hi: 'शीर्ष प्रदर्शनकर्ता',
  );
  String get allChainsShare => _t(
    ar: 'الحصة السوقية للسلاسل',
    en: 'Chain Market Share',
    hi: 'चेन बाजार हिस्सेदारी',
  );
  String get allBranchesShare => _t(
    ar: 'توزيع مبيعات الفروع',
    en: 'Branch Sales Share',
    hi: 'शाखा बिक्री शेयर',
  );

  // ---------------------------------------------------------------------------
  // 17. AI Brain & Knowledge Base Directives
  // ---------------------------------------------------------------------------
  String get aiBrainTitle => _t(
    ar: 'مركز حوكمة وتعليم الذكاء الاصطناعي لفحص الفواتير والعروض',
    en: 'AI Receipt & Promotional Intelligence Knowledge Base',
    hi: 'एआई रसीद और प्रचार नियम ज्ञानकोष',
  );
  String get aiBrainSubtitle => _t(
    ar: 'السجل الشامل للقواعد والخوارزميات والمعايير الذكية التي تم تدريب نموذج الذكاء الاصطناعي عليها لتطبيقها تلقائياً عبر كافة الحملات',
    en: 'The comprehensive registry of intelligent heuristics, algorithms, and rules taught to the AI engine, applied automatically across all campaigns',
    hi: 'एआई इंजन को सिखाए गए नियमों और एल्गोरिदम की व्यापक निर्देशिका, जो सभी अभियानों में स्वचालित रूप से लागू होती है',
  );
  String get totalAiDirectivesCount => _t(
    ar: 'إجمالي بنود وقواعد الذكاء المعتمدة',
    en: 'Total Intelligence Directives',
    hi: 'कुल स्वीकृत एआई निर्देश',
  );
  String get activeAiModelPrimary => _t(
    ar: 'النموذج القياسي الأساسي',
    en: 'Primary AI Architecture',
    hi: 'प्राथमिक एआई मॉडल',
  );
  String get overallAiAccuracyScore => _t(
    ar: 'معدل دقة استخراج وفحص البونات',
    en: 'POS Accuracy Score',
    hi: 'रसीद सत्यापन सटीकता',
  );
  String get filterAllDirectives => _t(ar: 'كافة البنود (الكل)', en: 'All Directives', hi: 'सभी निर्देश');
  String get searchDirectivesPlaceholder => _t(
    ar: 'بحث في قواعد وخوارزميات الذكاء الاصطناعي...',
    en: 'Search AI directives, rules, or algorithms...',
    hi: 'एआई नियमों या एल्गोरिदम में खोजें...',
  );
  String get directiveStatusActive => _t(
    ar: 'مفعل عالمياً على كافة الحملات',
    en: 'Globally Active across All Campaigns',
    hi: 'सभी अभियानों पर सक्रिय',
  );
  String get directiveStatusInactive => _t(
    ar: 'معطل مؤقتاً',
    en: 'Temporarily Disabled',
    hi: 'अस्थायी रूप से अक्षम',
  );
  String get directiveLogicHeader => _t(ar: 'المنطق والخوارزمية البرمجية:', en: 'Logic & Algorithm:', hi: 'तर्क और एल्गोरिदम:');
  String get directiveExampleHeader => _t(ar: 'مثال عملي حي من واقع البونات:', en: 'Real-world Receipt Example:', hi: 'वास्तविक रसीद उदाहरण:');
  String get addNewDirectiveBtn => _t(ar: 'توثيق وإضافة بند تدريبي جديد', en: 'Teach AI / Add New Directive', hi: 'नया एआई निर्देश जोड़ें');
  String get resetToDefaultsBtn => _t(ar: 'استعادة البنود المعيارية الأساسية', en: 'Restore Default Directives', hi: 'डिफ़ॉल्ट निर्देश पुनर्स्थापित करें');
  String get directiveDetailsTitle => _t(ar: 'تفاصيل البند المعياري الذكي', en: 'Directive Specifications', hi: 'निर्देश विवरण');
  String get directiveSavedSuccess => _t(ar: 'تم حفظ وتوثيق البند بنجاح في عقل الذكاء الاصطناعي', en: 'Directive successfully recorded in AI Brain', hi: 'निर्देश सफलतापूर्वक एआई में दर्ज किया गया');
  String get directiveDeletedSuccess => _t(ar: 'تم حذف البند بنجاح', en: 'Directive deleted successfully', hi: 'निर्देश सफलतापूर्वक हटा दिया गया');
  String get aiBrainCatalogTab => _t(
    ar: 'سجل القواعد المعتمدة (AIR Catalog)',
    en: 'Approved Directives Catalog',
    hi: 'स्वीकृत निर्देश सूची',
  );
  String get aiBrainStudioTab => _t(
    ar: 'استوديو الشات والتدريب التفاعلي (AI Co-Pilot)',
    en: 'Interactive AI Co-Pilot Studio',
    hi: 'इंटरएक्टिव एआई को-पायलट स्टूडियो',
  );
  String get askAiBrainAboutReceipt => _t(
    ar: 'تشخيص البون في عقل الذكاء الاصطناعي',
    en: 'Diagnose in AI Brain',
    hi: 'एआई ब्रेन से रसीद का विश्लेषण करें',
  );
  String get aiBrainQuickDiagnoseTooltip => _t(
    ar: 'فتح استوديو الذكاء الاصطناعي التفاعلي لفحص وتشخيص سبب رفض البون وتدريب الذكاء فوراً',
    en: 'Open AI Co-Pilot Studio to diagnose rejection reasons and teach the AI',
    hi: 'रसीद अस्वीकृति के कारणों का विश्लेषण करने के लिए एआई स्टूडियो खोलें',
  );
  String get voiceRecordTooltip => _t(
    ar: 'التحدث بالصوت / تسجيل ملاحظة صوتية (Voice Note)',
    en: 'Voice Note / Speak to AI Co-Pilot',
    hi: 'वॉयस नोट / एआई को-पायलट से बात करें',
  );
  String get recordingVoiceNow => _t(
    ar: 'جاري تسجيل الصوت... تحدث بوضوح',
    en: 'Recording voice... Speak clearly',
    hi: 'ऑडियो रिकॉर्ड हो रहा है... स्पष्ट बोलें',
  );
  String get cancelRecording => _t(ar: 'إلغاء التسجيل', en: 'Cancel Recording', hi: 'रिकॉर्डिंग रद्द करें');
  String get sendVoiceNote => _t(ar: 'إرسال التسجيل الصوتي', en: 'Send Voice Note', hi: 'वॉयस नोट भेजें');
  String get dictateToText => _t(ar: 'تحويل الصوت إلى نص', en: 'Transcribe to Text', hi: 'टेक्स्ट में बदलें');
  String get transcribingAudio => _t(
    ar: 'جاري الاستماع وتفريغ الصوت عبر ${AiModels.helperServicesLabel}...',
    en: 'Transcribing and analyzing voice with ${AiModels.helperServicesLabel}...',
    hi: 'मिथुन के साथ ऑडियो का विश्लेषण हो रहा है...',
  );
  String get voiceTranscriptionHeader => _t(
    ar: '🎙️ تفريغ الصوت المنطوق (Voice Transcription):',
    en: '🎙️ Spoken Voice Transcription:',
    hi: '🎙️ वॉयस ट्रांसक्रिप्शन:',
  );
  String get voiceNoteLabel => _t(ar: 'رسالة صوتية', en: 'Voice Note', hi: 'वॉयस नोट');
  String get micPermissionDenied => _t(
    ar: 'تعذر الوصول للميكروفون، يرجى السماح بالوصول في إعدادات المتصفح أو الجهاز',
    en: 'Microphone permission denied, please allow access in browser or device settings',
    hi: 'माइक्रोफ़ोन एक्सेस अस्वीकृत, कृपया अनुमतियां जांचें',
  );
  String get recordingTooShort => _t(
    ar: 'التسجيل الصوتي قصير جداً (أقل من ثانية)',
    en: 'Recording is too short (under 1 second)',
    hi: 'रिकॉर्डिंग बहुत छोटी है',
  );
  String get pasteImageSuccess => _t(
    ar: 'تم لصق صورة البون من الحافظة (Clipboard) بنجاح 📋🖼️',
    en: 'Receipt image pasted from clipboard! 📋🖼️',
    hi: 'क्लिपबोर्ड से रसीद کی छवि सफलतापूर्वक चिपकाई गई! 📋🖼️',
  );
  String get stopAndKeepDraft => _t(
    ar: 'إيقاف وحفظ التسجيل (كمرفق)',
    en: 'Stop & Keep Voice Note (as attachment)',
    hi: 'रिकॉर्डिंग रोकें और रखें (संलग्नक के रूप में)',
  );
  String get draftVoiceNoteLabel => _t(
    ar: 'تسجيل صوتي مرفق (جاهز للإرسال)',
    en: 'Attached Voice Note (Ready to send)',
    hi: 'संलग्न वॉयस नोट (भेजने के लिए तैयार)',
  );
  String get removeDraftVoiceNote => _t(
    ar: 'حذف التسجيل الصوتي المرفق',
    en: 'Remove attached voice note',
    hi: 'संलग्न वॉयस नोट हटाएं',
  );

  // ---------------------------------------------------------------------------
  // 18. Spend Conditions, Combo Bundles & Catalog Selection
  // ---------------------------------------------------------------------------
  String get conditionTypeLabel => _t(ar: 'نوع شرط العرض:', en: 'Condition Type:', hi: 'शर्त का प्रकार:');
  String get byQuantityCondition => _t(ar: 'حسب الكمية (عدد القطع)', en: 'By Quantity (Piece Count)', hi: 'मात्रा के अनुसार (टुकड़ों की संख्या)');
  String get bySpendCondition => _t(ar: 'حسب القيمة (إجمالي المبلغ)', en: 'By Spend (Total EGP)', hi: 'खर्च के अनुसार (कुल राशि)');
  String get comboSpendCondition => _t(ar: 'حزمة كومبو (شراء علامات معاً بقيمة محددة)', en: 'Combo Bundle (Brands Together for Target Spend)', hi: 'कॉम्बो बंडल (लक्षित खर्च के लिए एक साथ ब्रांड)');
  String get minSpendLabel => _t(ar: 'الحد الأدنى لقيمة المشتريات (ج.م):', en: 'Minimum Spend Amount (EGP):', hi: 'न्यूनतम खरीद राशि (EGP):');
  String get minSpendRangeLabel => _t(ar: 'الحد الأدنى للنطاق (من ج.م):', en: 'Min Spend (From EGP):', hi: 'न्यूनतम खर्च (EGP से):');
  String get maxSpendRangeLabel => _t(ar: 'الحد الأقصى للنطاق (إلى ج.م - اختياري):', en: 'Max Spend (To EGP - Optional):', hi: 'अधिकतम खर्च (EGP तक - वैकल्पिक):');
  String get discountToleranceLabel => _t(ar: 'سماحية خصومات الكاشير (ج.م):', en: 'Discount Tolerance (EGP):', hi: 'छूट सहनशीलता (EGP):');
  String get discountToleranceHint => _t(
    ar: 'مثال: 5 ج.م لسماح الفواتير التي تبلغ 95 ج.م بدلاً من 100 ج.م بسبب الخصم',
    en: 'e.g. 5 EGP tolerance allows 95 EGP receipts instead of 100 EGP due to discounts',
    hi: 'उदा. 5 EGP छूट के कारण 100 EGP के बजाय 95 EGP रसीद की अनुमति देता है',
  );
  String get oralBundleToleranceTitle => _t(
    ar: '🦷 حزم العناية بالفم بنطاق الأسعار والخصومات (95-140-190 ج.م)',
    en: '🦷 Oral Care Bundles with Discount Ranges (95-140-190 EGP)',
    hi: '🦷 मौखिक देखभाल बंडल मूल्य सीमा के साथ (95-140-190 EGP)',
  );
  String get requiredBrandsLabel => _t(ar: 'العلامات التجارية المشروطة معاً في الفاتورة:', en: 'Required Brands Together in Receipt:', hi: 'रसीद में एक साथ आवश्यक ब्रांड:');
  String get selectFromCatalogBtn => _t(ar: 'اختيار من الكتالوج', en: 'Select from Catalog', hi: 'कैटलॉग से चुनें');
  String get chooseProductsFromCatalogTitle => _t(ar: 'اختيار الأصناف والباركودات المعتمدة من كتالوج الشركة', en: 'Select Approved Products & Barcodes from Catalog', hi: 'कैटलॉग से स्वीकृत उत्पाद और बारकोड चुनें');
  String get searchCatalogProductsHint => _t(ar: 'بحث باسم الصنف أو الباركود...', en: 'Search by product name or barcode...', hi: 'उत्पाद के नाम या बारकोड से खोजें...');
  String get selectAll => _t(ar: 'تحديد الكل', en: 'Select All', hi: 'सभी चुनें');
  String get deselectAll => _t(ar: 'إلغاء التحديد', en: 'Deselect All', hi: 'अचयनित करें');

  // ---------------------------------------------------------------------------
  // 19. Customer Marketing & WhatsApp Gateway
  // ---------------------------------------------------------------------------
  String get customersMarketingNavTitle => _t(ar: 'تسويق وواتساب العملاء', en: 'Customer Marketing & WhatsApp', hi: 'ग्राहक विपणन और व्हाट्सएप');
  String get customersMarketingTitle => _t(ar: 'تسويق وتواصل العملاء (WhatsApp Marketing)', en: 'Customer Marketing & WhatsApp Outreach', hi: 'ग्राहक विपणन और आउटरीच');
  String get customersMarketingSubtitle => _t(
    ar: 'استعراض قاعدة بيانات عملاء الحملات، وتصفية المتسوقين والـ VIP، وإرسال رسائل وعروض ترويجية مخصصة عبر واتساب',
    en: 'Manage customer database, segment shoppers and VIPs, and broadcast personalized WhatsApp marketing campaigns',
    hi: 'अभियान ग्राहकों का डेटाबेस प्रबंधित करें और वैयक्तिकृत व्हाट्सएप अभियान भेजें',
  );
  String get noCustomersFound => _t(ar: 'لا يوجد عملاء مطابقون لمعايير البحث الحالية', en: 'No customers found matching search criteria', hi: 'कोई ग्राहक नहीं मिला');
  String get totalCustomersKpi => _t(ar: 'إجمالي العملاء', en: 'Total Shoppers', hi: 'कुल ग्राहक');
  String get totalCustomerSpendKpi => _t(ar: 'مشتريات العملاء', en: 'Total Sales Spend', hi: 'कुल ग्राहक खर्च');
  String get totalPrizesWonKpi => _t(ar: 'الجوائز المسلمة', en: 'Claimed Rewards', hi: 'वितरित पुरस्कार');
  String get testPhonePlaceholder => _t(ar: 'رقم الهاتف للتجربة (مثال: 01012345678)...', en: 'Test phone number (e.g. 01012345678)...', hi: 'परीक्षण फ़ोन नंबर...');
  String get testCustomerNameOptional => _t(ar: 'اسم العميل التجريبي (اختياري)', en: 'Test customer name (optional)', hi: 'परीक्षण ग्राहक का नाम');
  String get sendTestWhatsApp => _t(ar: 'إرسال رسالة الاختبار', en: 'Send Test WhatsApp', hi: 'परीक्षण संदेश भेजें');
  String get testMessageSentSuccess => _t(ar: 'تم تجهيز وفتح رسالة الاختبار بنجاح', en: 'Test message prepared successfully', hi: 'परीक्षण संदेश सफलतापूर्वक तैयार किया गया');
  String get addCustomRecipient => _t(ar: 'إضافة مستلم مخصص', en: 'Add Custom Recipient', hi: 'कस्टम प्राप्तकर्ता जोड़ें');

  String get repeatShoppersKpi => _t(ar: 'العملاء المتكررون', en: 'Repeat Shoppers', hi: 'बार-बार आने वाले ग्राहक');
  String get composeWhatsAppCampaign => _t(ar: 'صياغة رسالة حملة الواتساب', en: 'Compose WhatsApp Campaign', hi: 'व्हाट्सएप अभियान संदेश लिखें');
  String get launchWhatsAppQueue => _t(ar: 'إطلاق طابور الإرسال للعملاء', en: 'Launch WhatsApp Queue', hi: 'व्हाट्सएप प्रेषण कतार शुरू करें');
  String get presetTemplatesTitle => _t(ar: 'نماذج ورسائل جاهزة سريعة:', en: 'Quick Ready Templates:', hi: 'त्वरित तैयार संदेश:');
  String get templateNewEvent => _t(ar: 'حملة جديدة', en: 'New Campaign', hi: 'नया अभियान');
  String get templateRewardVoucher => _t(ar: 'استلام قسيمة', en: 'Claim Voucher', hi: 'वाउचर प्राप्त करें');
  String get templateWeekendOffer => _t(ar: 'عروض الويك إند', en: 'Weekend Offers', hi: 'सप्ताहांत के ऑफ़र');
  String get messageTemplatePlaceholder => _t(
    ar: 'اكتب نص الرسالة التسويقية هنا...',
    en: 'Write marketing message text here...',
    hi: 'यहाँ विपणन संदेश लिखें...',
  );
  String get insertVariable => _t(ar: 'إدراج متغير', en: 'Insert Variable', hi: 'वेरिएबल डालें');
  String get sendTestMessage => _t(ar: 'إرسال رسالة تجريبية', en: 'Send Test Message', hi: 'परीक्षण संदेश भेजें');
  String get testMessageNotice => _t(
    ar: 'سيتم إرسال الرسالة إلى رقم هاتفك المسجل للاختبار والمعاينة قبل الإرسال للجمهور.',
    en: 'A preview test message will be sent to your number before sending to customers.',
    hi: 'ग्राहकों को भेजने से पहले आपके नंबर पर एक परीक्षण संदेश भेजा जाएगा।',
  );
  String get quickTestSend => _t(ar: 'إرسال تجريبي سريع', en: 'Quick Test Send', hi: 'त्वरित परीक्षण भेजें');
  String get filterSegmentAll => _t(ar: 'كافة العملاء', en: 'All Customers', hi: 'सभी ग्राहक');
  String get filterSegmentWinners => _t(ar: 'الفائزون بجوائز', en: 'Prize Winners', hi: 'विजेता ग्राहक');
  String get filterSegmentTopSpenders => _t(ar: 'الأعلى إنفاقاً (VIP)', en: 'Top Spenders (VIP)', hi: 'शीर्ष खरीदार (वीआईपी)');
  String get filterSegmentRepeat => _t(ar: 'المتسوقون المتكررون', en: 'Repeat Shoppers', hi: 'बार-बार आने वाले ग्राहक');
  String get filterSegmentCompanySupervisors => _t(
    ar: 'مشرفين الشركات',
    en: 'Company Supervisors',
    hi: 'कंपनी पर्यवेक्षक',
  );
  String get companySupervisorName => _t(ar: 'اسم الشخص', en: 'Name', hi: 'नाम');
  String get companySupervisorMobile => _t(ar: 'رقم الموبايل', en: 'Mobile', hi: 'मोबाइल');
  String get companySupervisorAlternate => _t(ar: 'اسم بديل', en: 'Alternate name', hi: 'वैकल्पिक नाम');
  String get companySupervisorSearchPlaceholder => _t(
    ar: 'بحث بالاسم أو رقم الموبايل...',
    en: 'Search by name or mobile...',
    hi: 'नाम या मोबाइल से खोजें...',
  );
  String get companySupervisorsEmpty => _t(
    ar: 'لا يوجد مشرفون مطابقون. يمكن تحديث القائمة من ملف Excel.',
    en: 'No matching supervisors. Update the list from an Excel file.',
    hi: 'कोई मेल खाता पर्यवेक्षक नहीं। सूची को एक्सेल से अपडेट करें।',
  );
  String get companySupervisorsLoading => _t(
    ar: 'جاري تحميل مشرفين الشركات',
    en: 'Loading company supervisors',
    hi: 'कंपनी पर्यवेक्षक लोड हो रहे हैं',
  );
  String get companySupervisorsLoadError => _t(
    ar: 'تعذر تحميل قائمة مشرفين الشركات',
    en: 'Could not load company supervisors',
    hi: 'कंपनी पर्यवेक्षकों की सूची लोड नहीं हो सकी',
  );
  String get importCompanySupervisors => _t(
    ar: 'تحديث قائمة المشرفين',
    en: 'Update supervisor list',
    hi: 'पर्यवेक्षक सूची अपडेट करें',
  );
  String get importCompanySupervisorsHelp => _t(
    ar: 'ارفع ملف Excel بعمودي رقم الموبايل واسم الشخص. الرقم المكرر يُحفظ مرة واحدة، ويُحفظ الاسم الأطول كاسم أساسي والاسم الآخر كاسم بديل.',
    en: 'Upload an Excel file with mobile and name columns. A repeated mobile is stored once: the longer name is kept and the other name is stored as an alternate.',
    hi: 'मोबाइल और नाम कॉलम वाली एक्सेल फ़ाइल अपलोड करें। दोहराया मोबाइल एक बार रखा जाता है: लंबा नाम मुख्य रहता है और दूसरा नाम वैकल्पिक रहता है।',
  );
  String companySupervisorsImportSummary(int rows, int unique, int duplicates) => _t(
    ar: 'صفوف الملف: $rows • أرقام فريدة: $unique • صفوف مكررة دُمجت: $duplicates',
    en: 'File rows: $rows • Unique mobiles: $unique • Duplicate rows merged: $duplicates',
    hi: 'फ़ाइल पंक्तियाँ: $rows • अद्वितीय मोबाइल: $unique • मिली हुई दोहराई पंक्तियाँ: $duplicates',
  );
  String companySupervisorsInvalidRows(int count) => _t(
    ar: 'صفوف غير صالحة تم تجاهلها: $count',
    en: 'Invalid rows skipped: $count',
    hi: 'अमान्य पंक्तियाँ छोड़ी गईं: $count',
  );
  String get companySupervisorsDuplicateTitle => _t(
    ar: 'الأرقام المكررة والاسم المحفوظ',
    en: 'Duplicate mobiles and the kept name',
    hi: 'दोहराए मोबाइल और रखा गया नाम',
  );
  String get companySupervisorsReplaceMissing => _t(
    ar: 'حذف الأرقام غير الموجودة في هذا الملف',
    en: 'Delete mobiles that are not in this file',
    hi: 'इस फ़ाइल में न होने वाले मोबाइल हटाएँ',
  );
  String get companySupervisorsSaveList => _t(ar: 'حفظ القائمة', en: 'Save list', hi: 'सूची सहेजें');
  String get companySupervisorsSaveFailed => _t(
    ar: 'تعذر حفظ قائمة المشرفين',
    en: 'Could not save the supervisor list',
    hi: 'पर्यवेक्षक सूची सहेजी नहीं जा सकी',
  );
  String selectedSupervisorsCount(int count) => _t(
    ar: 'تم تحديد $count مشرف',
    en: '$count supervisors selected',
    hi: '$count पर्यवेक्षक चयनित',
  );
  String companySupervisorsSaved(int count) => _t(
    ar: 'تم حفظ $count مشرف في القائمة',
    en: 'Saved $count supervisors',
    hi: '$count पर्यवेक्षक सहेजे गए',
  );
  String showingSupervisorsRange(int start, int end, int total) => _t(
    ar: 'عرض $start إلى $end من إجمالي $total مشرف',
    en: 'Showing $start to $end of $total supervisors',
    hi: 'कुल $total में से $start से $end पर्यवेक्षक दिखाए जा रहे हैं',
  );
  String get pdfAttachmentHint => _t(
    ar: 'رابط ينتهي بـ PDF يُرسل كمستند مرفق مع نص الرسالة',
    en: 'A link ending in PDF is sent as a document attachment with the message',
    hi: 'PDF पर समाप्त होने वाला लिंक संदेश के साथ दस्तावेज़ अनुलग्नक के रूप में भेजा जाता है',
  );
  String get pdfAttachmentReady => _t(
    ar: 'سيتم إرسال ملف PDF كمرفق',
    en: 'The PDF will be sent as an attachment',
    hi: 'PDF अनुलग्नक के रूप में भेजा जाएगा',
  );
  String get campaignMediaPickFile => _t(
    ar: 'اختيار ملف من الجهاز',
    en: 'Choose a file from this device',
    hi: 'इस डिवाइस से फ़ाइल चुनें',
  );
  String get campaignMediaPickHint => _t(
    ar: 'ارفع ملف PDF أو صورة JPG أو PNG أو WEBP. يُحفظ الملف ثم يُرسل مع الرسالة.',
    en: 'Upload a PDF or a JPG, PNG, or WEBP image. The file is saved, then sent with the message.',
    hi: 'PDF या JPG, PNG, WEBP छवि अपलोड करें। फ़ाइल सहेजी जाती है, फिर संदेश के साथ भेजी जाती है।',
  );
  String get campaignMediaReplace => _t(
    ar: 'استبدال الملف',
    en: 'Replace file',
    hi: 'फ़ाइल बदलें',
  );
  String get campaignMediaClear => _t(
    ar: 'إزالة الملف',
    en: 'Remove file',
    hi: 'फ़ाइल हटाएँ',
  );
  String get campaignMediaReady => _t(
    ar: 'الملف جاهز للإرسال',
    en: 'The file is ready to send',
    hi: 'फ़ाइल भेजने के लिए तैयार है',
  );
  String get campaignMediaUploading => _t(
    ar: 'جاري حفظ الملف',
    en: 'Saving the file',
    hi: 'फ़ाइल सहेजी जा रही है',
  );
  String get campaignMediaUploadFailed => _t(
    ar: 'تعذر حفظ الملف. حاول مرة أخرى.',
    en: 'Could not save the file. Try again.',
    hi: 'फ़ाइल सहेजी नहीं जा सकी। फिर कोशिश करें।',
  );
  String get campaignMediaReadFailed => _t(
    ar: 'تعذر قراءة الملف من الجهاز',
    en: 'Could not read the file from this device',
    hi: 'इस डिवाइस से फ़ाइल नहीं पढ़ी जा सकी',
  );
  String get campaignMediaTypeRejected => _t(
    ar: 'يُقبل فقط ملف PDF أو صورة JPG أو PNG أو WEBP',
    en: 'Only a PDF or a JPG, PNG, or WEBP image is accepted',
    hi: 'केवल PDF या JPG, PNG, WEBP छवि स्वीकार है',
  );
  String get campaignMediaUnauthorized => _t(
    ar: 'رفع الملف متاح لمدير النظام فقط',
    en: 'Only a system admin can upload this file',
    hi: 'यह फ़ाइल केवल सिस्टम व्यवस्थापक अपलोड कर सकता है',
  );
  String get campaignMediaEmpty => _t(
    ar: 'الملف فارغ',
    en: 'The file is empty',
    hi: 'फ़ाइल खाली है',
  );
  String get campaignMediaTooLarge => _t(
    ar: 'حجم الملف أكبر من 20 ميجابايت',
    en: 'The file is larger than 20 MB',
    hi: 'फ़ाइल 20 एमबी से बड़ी है',
  );
  String get campaignMediaUrlFallback => _t(
    ar: 'أو الصق رابط ملف جاهز إن كان محفوظاً في مكان آخر',
    en: 'Or paste a link to a file you already have',
    hi: 'या किसी तैयार फ़ाइल का लिंक चिपकाएँ',
  );
  String get campaignMediaRequired => _t(
    ar: 'أضف ملفاً أو رابط بوستر أولاً',
    en: 'Add a file or a poster link first',
    hi: 'पहले एक फ़ाइल या पोस्टर लिंक जोड़ें',
  );
  String get campaignMediaUploadedWins => _t(
    ar: 'سيُرسل الملف المرفوع مع الرسالة. الرابط يُستخدم فقط بعد إزالة الملف.',
    en: 'The uploaded file is sent with the message. The link is used only after you remove the file.',
    hi: 'अपलोड की गई फ़ाइल संदेश के साथ भेजी जाती है। लिंक तभी उपयोग होता है जब फ़ाइल हटा दी जाए।',
  );
  String get searchCustomerPlaceholder => _t(ar: 'بحث بالاسم أو رقم الهاتف أو الفرع...', en: 'Search by name, phone, or branch...', hi: 'नाम, फोन या शाखा द्वारा खोजें...');
  String get deselectAllCustomers => _t(ar: 'إلغاء تحديد الكل', en: 'Deselect All', hi: 'सभी अचयनित करें');
  String get selectAllCustomers => _t(ar: 'تحديد كافة العملاء', en: 'Select All Customers', hi: 'सभी ग्राहकों का चयन करें');
  String selectedCustomersCount(int count) => _t(
    ar: 'تم تحديد $count عميل',
    en: '$count customers selected',
    hi: '$count ग्राहक चयनित',
  );
  String get exportContactsExcel => _t(ar: 'تصدير Excel', en: 'Export Excel', hi: 'एक्सेल निर्यात करें');
  String get exportVcfContacts => _t(ar: 'تصدير جهات اتصال (VCF)', en: 'Export Contacts (VCF)', hi: 'संपर्क निर्यात करें (वीसीएफ)');
  String get totalReceiptsCountCol => _t(ar: 'عدد الفواتير', en: 'Receipts Count', hi: 'रसीद संख्या');
  String get totalSpendAmountCol => _t(ar: 'إجمالي المشتريات', en: 'Total Spend', hi: 'कुल खरीद');
  String get prizesWonCol => _t(ar: 'الجوائز المستلمة', en: 'Prizes Claimed', hi: 'प्राप्त पुरस्कार');
  String get branchesCol => _t(ar: 'الفروع التي زارها', en: 'Visited Outlets', hi: 'देखी गई शाखाएं');
  String get lastVisitCol => _t(ar: 'آخر زيارة', en: 'Last Visit', hi: 'अंतिम यात्रा');
  String get sendDirectWhatsApp => _t(ar: 'إرسال واتساب مباشر', en: 'Direct WhatsApp', hi: 'सीधा व्हाट्सएप भेजें');
  String get callCustomerPhone => _t(ar: 'اتصال هاتفي', en: 'Call Phone', hi: 'फ़ोन कॉल करें');

  String showingCustomersRange(int start, int end, int total) => _t(
    ar: 'عرض $start إلى $end من إجمالي $total عميل',
    en: 'Showing $start to $end of $total customers',
    hi: 'कुल $total में से $start से $end ग्राहक दिखाए जा रहे हैं',
  );
  String get allRowsOption => _t(ar: 'الكل', en: 'All', hi: 'सभी');
  String get previousCustomer => _t(ar: 'العميل السابق', en: 'Previous Customer', hi: 'पिछला ग्राहक');
  String get nextCustomer => _t(ar: 'العميل التالي', en: 'Next Customer', hi: 'अगला ग्राहक');
  String pageOfTotal(int page, int totalPages) => _t(
    ar: 'صفحة $page من $totalPages',
    en: 'Page $page of $totalPages',
    hi: 'पृष्ठ $page का $totalPages',
  );
  String get whatsappGatewayTitle => _t(
    ar: 'بوابة إرسال واتساب للعملاء',
    en: 'WhatsApp Customer Gateway',
    hi: 'व्हाट्सएप ग्राहक गेटवे',
  );
  String get whatsappGatewaySubtitle => _t(
    ar: 'إعدادات سيرفر الواتساب للإرسال التلقائي للرسائل والعروض الترويجية',
    en: 'Configure Private WhatsApp Server (WAHA) or Custom Gateway for automated promotions with zero fees',
    hi: 'स्वचालित संदेशों के लिए अल्ट्रा-मैसेज या वासापी गेटवे सेटिंग्स',
  );
  String get gatewayProviderLabel => _t(ar: 'مزود الخدمة', en: 'Service Provider', hi: 'सेवा प्रदाता');
  String get instanceIdLabel => _t(ar: 'معرف النسخة (Instance ID)', en: 'Instance ID', hi: 'इंस्टेंस आईडी');
  String get apiTokenLabel => _t(ar: 'رمز المصادقة (API Token)', en: 'API Token', hi: 'एपीआई टोकन');
  String get customEndpointLabel => _t(ar: 'رابط البوابة المخصصة (Webhook/API Endpoint)', en: 'Custom API Endpoint', hi: 'कस्टम एपीआई यूआरएल');
  String get delayBetweenMessagesLabel => _t(ar: 'الفاصل الزمني بين كل رسالة (ثواني)', en: 'Delay Between Messages (seconds)', hi: 'संदेशों के बीच का समय (सेकंड)');
  String get gatewayConnectedBadge => _t(ar: 'متصل وجاهز', en: 'Connected & Ready', hi: 'सक्रिय और तैयार');
  String get gatewayDisconnectedBadge => _t(ar: 'غير متصل', en: 'Not Configured', hi: 'कॉन्फ़िगर नहीं किया गया');
  String get testGatewayConnection => _t(ar: 'اختبار الاتصال', en: 'Test Connection', hi: 'कनेक्शन का परीक्षण करें');
  String get saveGatewaySettings => _t(ar: 'حفظ الإعدادات', en: 'Save Settings', hi: 'सेटिंग्स सहेजें');
  String get autoGatewayDispatchMode => _t(ar: 'إرسال آلي عبر سيرفر الواتساب (WAHA)', en: 'Auto Dispatch via WhatsApp Server (WAHA)', hi: 'गेटवे के माध्यम से स्वचालित प्रेषण');
  String get manualDispatchMode => _t(ar: 'إرسال يدوي فردي (WhatsApp Web / App)', en: 'Manual One-by-One Dispatch (WhatsApp Web / App)', hi: 'मैन्युअल एक-एक करके प्रेषण');
  String get autoAdvanceToggle => _t(ar: 'الانتقال التلقائي للعميل التالي بعد الإرسال', en: 'Auto-advance to next customer after dispatch', hi: 'भेजने के बाद स्वचालित रूप से अगले ग्राहक पर जाएं');
  String get gatewayNotConfiguredBadge => _t(ar: 'البوابة غير مهيأة', en: 'Gateway Not Configured', hi: 'गेटवे कॉन्फ़िगर नहीं किया गया');
  String get autoDispatchTitle => _t(ar: 'حملة الإرسال التلقائي', en: 'Automated Campaign Dispatcher', hi: 'स्वचालित अभियान प्रेषण');
  String get autoDispatchNotice => _t(ar: 'سيتم إرسال الرسائل المخصصة لكل عميل تباعاً عبر البوابة مع مراعاة الفاصل الزمني لتجنب حظر الأرقام.', en: 'Customized messages will be sent sequentially via the gateway with safety delays to prevent number banning.', hi: 'सुरक्षा देरी के साथ गेटवे के माध्यम से संदेश स्वचालित रूप से भेजे जाएंगे।');
  String get startAutoDispatch => _t(ar: 'بدء الإرسال الآلي الآن', en: 'Start Auto Dispatch Now', hi: 'अब स्वचालित प्रेषण शुरू करें');
  String get resendToAllNow => _t(
    ar: 'إعادة الإرسال الآلي للجميع الآن',
    en: 'Resend to All Contacts Now',
    hi: 'अब सभी संपर्कों को पुनः प्रेषित करें',
  );
  String get resetContactStatuses => _t(
    ar: 'إعادة تعيين الحالة (قيد الانتظار)',
    en: 'Reset Statuses (Pending)',
    hi: 'स्थिति रीसेट करें',
  );
  String get pollRequiresTwoOptions => _t(
    ar: 'يتطلب استطلاع الرأي خيارين على الأقل للتصويت',
    en: 'Poll requires at least 2 voting options',
    hi: 'मतदान के लिए कम से कम 2 विकल्पों की आवश्यकता है',
  );
  String get pollQuestionRequired => _t(
    ar: 'يرجى إدخال سؤال الاستطلاع قبل الإرسال',
    en: 'Please enter poll question before dispatching',
    hi: 'कृपया भेजने से पहले मतदान प्रश्न दर्ज करें',
  );
  String get pollPreviewTitle => _t(
    ar: 'استطلاع رأي تفاعلي (WhatsApp Poll)',
    en: 'Interactive WhatsApp Poll',
    hi: 'इंटरएक्टिव व्हाट्सएप पोल',
  );
  String get resumeDispatch => _t(ar: 'استئناف الإرسال', en: 'Resume Dispatch', hi: 'प्रेषण फिर से शुरू करें');
  String get pauseDispatch => _t(ar: 'إيقاف مؤقت', en: 'Pause Dispatch', hi: 'प्रेषण रोकें');
  String get cancelDispatch => _t(ar: 'إلغاء الحملة', en: 'Cancel Dispatch', hi: 'अभियान रद्द करें');
  String get customerQueueProgress => _t(ar: 'قائمة انتظار العملاء وحالة الإرسال', en: 'Customer Queue & Progress', hi: 'ग्राहक कतार और स्थिति');
  String get liveMessagePreview => _t(ar: 'معاينة حية للرسالة المخصصة للعميل الحالي', en: 'Live Customer Message Preview', hi: 'ग्राहक संदेश का पूर्वावलोकन');
  String get sendAndOpenWhatsApp => _t(ar: 'إرسال وفتح واتساب', en: 'Send & Open WhatsApp', hi: 'व्हाट्सएप भेजें और खोलें');
  String get skipToNextCustomer => _t(ar: 'تخطي للعميل التالي', en: 'Skip to Next Customer', hi: 'अगले ग्राहक पर जाएं');
  String get dispatchCompleted => _t(ar: 'اكتمل إرسال الحملة بنجاح لكافة العملاء المحددِين!', en: 'Campaign dispatch completed successfully for all targeted customers!', hi: 'सभी लक्षित ग्राहकों के लिए अभियान सफलतापूर्वक पूरा हुआ!');

  // WhatsApp Winner Automatic Notification
  String get enableWhatsAppWinnerNotificationTitle => _t(
    ar: 'إرسال التهنئة التلقائي للفائزين عبر الواتساب',
    en: 'Auto WhatsApp Winner Greetings',
    hi: 'विजेताओं को स्वचालित व्हाट्सएप बधाई',
  );
  String get enableWhatsAppWinnerNotificationDesc => _t(
    ar: 'إرسال رسالة تهنئة احتفالية رسمية برقم الفاتورة وبيانات الهدية لهاتف العميل عبر الواتساب فور تأكيد تسليم الجائزة.',
    en: 'Automatically dispatch official celebratory WhatsApp greetings with receipt and prize details to winners upon gift handover.',
    hi: 'उपहार सौंपने पर विजेताओं को रसीद और पुरस्कार विवरण के साथ स्वचालित उत्सव व्हाट्सएप संदेश भेजें।',
  );
  String get enableWhatsAppWinnerNotificationActive => _t(
    ar: 'إرسال تلقائي مفعل',
    en: 'Auto-send Active',
    hi: 'स्वचालित प्रेषण सक्रिय',
  );
  String get enableWhatsAppWinnerNotificationDisabled => _t(
    ar: 'إرسال متوقف',
    en: 'Auto-send Paused',
    hi: 'स्वचालित प्रेषण रुका हुआ',
  );
  String get campaignWhatsAppWinnerTileTitle => _t(
    ar: 'تهنئة الفائزين عبر الواتساب',
    en: 'WhatsApp Winner Greetings',
    hi: 'व्हाट्सएप विजेता बधाई',
  );
  String get campaignWhatsAppWinnerTileSubtitle => _t(
    ar: 'إرسال فوري فور تسليم الهدية',
    en: 'Instant send on gift handover',
    hi: 'उपहार सौंपने पर तुरंत भेजें',
  );

  // ---------------------------------------------------------------------------
  // 22. 3-Tier Enterprise Portal Hierarchy (منظومة البوابات الثلاثية)
  // ---------------------------------------------------------------------------
  String get agencyOpsPortalLabel => _t(
    ar: 'بوابة شركة الدعاية والعمليات',
    en: 'Agency Operations Portal',
    hi: 'एजेंसी ऑपरेशन्स पोर्टल',
  );
  String get brandExecutivePortalLabel => _t(
    ar: 'البوابة التنفيذية للعلامة التجارية',
    en: 'Brand Executive Master Portal',
    hi: 'ब्रांड एक्जीक्यूटिव मास्टर पोर्टल',
  );
  String get agencyOpsPortalToggleTooltipActive => _t(
    ar: 'بوابة شركة الدعاية والعمليات مفعلة حالياً - اضغط لتعليق صلاحية الوصول',
    en: 'Agency operations portal is active - tap to pause access',
    hi: 'एजेंसी पोर्टल सक्रिय है - पहुंच रोकने के लिए टैप करें',
  );
  String get agencyOpsPortalToggleTooltipPaused => _t(
    ar: 'بوابة شركة الدعاية والعمليات متوقفة - اضغط لإعادة تفعيلها فورياً',
    en: 'Agency operations portal is paused - tap to reactivate immediately',
    hi: 'एजेंसी पोर्टल रुका हुआ है - तुरंत सक्रिय करने के लिए टैप करें',
  );
  String get copyAgencyOpsLink => _t(
    ar: 'نسخ رابط بوابة شركة الدعاية',
    en: 'Copy Agency Ops Link',
    hi: 'एजेंसी पोर्टल लिंक कॉपी करें',
  );
  String get copyBrandExecutiveLink => _t(
    ar: 'نسخ رابط مدير الشركة الدائم',
    en: 'Copy Brand Executive Link',
    hi: 'ब्रांड एक्जीक्यूटिव लिंक कॉपी करें',
  );
  String get previewAgencyOpsPortal => _t(
    ar: 'معاينة بوابة الدعاية والعمليات',
    en: 'Preview Agency Ops Portal',
    hi: 'एजेंसी पोर्टल पूर्वावलोकन',
  );
  String get previewBrandExecutivePortal => _t(
    ar: 'معاينة البوابة التنفيذية للشركة',
    en: 'Preview Brand Executive Portal',
    hi: 'ब्रांड मास्टर पोर्टल पूर्वावलोकन',
  );
  String get livePromoterSimulationNavTitle => _t(
    ar: 'محاكاة تطبيق المندوب الميداني',
    en: 'Live Promoter In-Store Simulation',
    hi: 'लाइव प्रमोटर सिमुलेशन',
  );
  String get livePromoterSimulationNavSubtitle => _t(
    ar: 'معاينة حية لتجربة المتسوق والمندوب في رفع الفواتير واستلام الجوائز',
    en: 'Live preview of in-store customer & promoter receipt scanning flow',
    hi: 'इन-स्टोर प्रमोटर रसीद स्कैनिंग का लाइव पूर्वावलोकन',
  );
  String get livePromoterSimulationNavTooltip => _t(
    ar: 'تجربة ومعاينة رحلة المندوب والعميل في السوبرماركت مباشرة داخل البوابة',
    en: 'Experience in-store customer scanning journey directly inside executive portal',
    hi: 'कार्यकारी पोर्टल के अंदर इन-स्टोर प्रमोटर यात्रा का अनुभव करें',
  );
  String get agencyOpsLinkCopied => _t(
    ar: 'تم نسخ رابط بوابة شركة الدعاية والعمليات الميدانية بنجاح',
    en: 'Agency Field Operations Portal link copied successfully',
    hi: 'एजेंसी ऑपरेशन्स पोर्टल लिंक कॉपी किया गया',
  );
  String get brandExecutiveLinkCopied => _t(
    ar: 'تم نسخ الرابط التنفيذي لمدير الشركة (الدائم لجميع الحملات) بنجاح',
    en: 'Brand Executive Master Portal link (Permanent across all campaigns) copied',
    hi: 'ब्रांड एक्जीक्यूटिव मास्टर पोर्टल लिंक कॉपी किया गया',
  );
  String get managerPortalArchiveNotice => _t(
    ar: 'وضع المراجعة وقراءة التقارير والأرشيف • الحملات متوقفة حالياً في الفروع',
    en: 'Historical Audit & Reporting Mode • Campaigns are currently paused in stores',
    hi: 'ऐतिहासिक ऑडिट और रिपोर्टिंग मोड • अभियान वर्तमान में स्टोर्स में रोके गए हैं',
  );
  String get promoterPortalTooltip => _t(
    ar: 'نسخ رابط العميل والمندوب المباشر لرفع الفواتير وتجربة الألعاب واستلام الجوائز',
    en: 'Copy direct Promoter / Client submission link to scan receipts & play games',
    hi: 'रसीद स्कैन करने और गेम खेलने के लिए प्रमोटर लिंक कॉपी करें',
  );
  String get agencyOpsPortalTooltip => _t(
    ar: 'نسخ رابط بوابة شركة الدعاية والعمليات (متابعة الأرصدة وسجل الفواتير وقسائم الشراء)',
    en: 'Copy Agency Operations Portal link (Stock, Vouchers & Invoices Audit)',
    hi: 'एजेंसी ऑपरेशन्स पोर्टल लिंक कॉपी करें',
  );
  String get brandExecutivePortalTooltip => _t(
    ar: 'نسخ رابط البوابة التنفيذية للعلامة التجارية (مؤشرات الـ ROI وتحليلات جميع الحملات)',
    en: 'Copy Brand Executive Master Portal link (ROI KPIs & All Campaigns Analytics)',
    hi: 'ब्रांड मास्टर पोर्टल लिंक कॉपी करें',
  );

  // ---------------------------------------------------------------------------
  // 23. Campaigns Comparison & Intelligence Analytics (مقارنة وتحليلات الحملات)
  // ---------------------------------------------------------------------------
  String get campaignsComparisonNavTitle => _t(
    ar: 'مقارنة وتحليلات الحملات',
    en: 'Campaigns Comparison & Benchmarks',
    hi: 'अभियान तुलना और बेंचमार्क',
  );
  String get campaignsComparisonNavSubtitle => _t(
    ar: 'مقارنة المبيعات، الفواتير، والعملاء بين حملات الشركة',
    en: 'Benchmark revenue, receipts & shoppers across brand campaigns',
    hi: 'ब्रांड अभियानों में राजस्व, रसीदों और ग्राहकों की तुलना करें',
  );
  String get campaignsComparisonNavTooltip => _t(
    ar: 'مقارنة أداء حملات الشركة المختلفة وتحليل نسب النمو والفرق',
    en: 'Compare company campaigns performance, growth rates and ROI deltas',
    hi: 'कंपनी के अभियानों के प्रदर्शन और विकास दर की तुलना करें',
  );
  String get campaignComparisonScreenTitle => _t(
    ar: 'مقارنة وتحليلات أداء الحملات الترويجية',
    en: 'Campaigns Benchmark & Intelligence Analytics',
    hi: 'प्रचार अभियान तुलनात्मक बुद्धिमत्ता और विश्लेषण',
  );
  String get campaignComparisonScreenSubtitle => _t(
    ar: 'تحليل مقارن تفصيلي للإيرادات، الفواتير، عدد المنتجات المباعة، والمتسوقين الفريدين',
    en: 'Detailed comparative intelligence of sales, invoices, units sold and unique customers',
    hi: 'बिक्री, इनवॉइस, बेची गई इकाइयों और ग्राहकों का विस्तृत तुलनात्मक विश्लेषण',
  );
  String get headToHeadComparisonTab => _t(
    ar: 'مقارنة حملتين',
    en: 'Compare 2',
    hi: 'दो अभियान',
  );
  String get allCampaignsPortfolioTab => _t(
    ar: 'المصفوفة',
    en: 'Matrix',
    hi: 'मैट्रिक्स',
  );
  String get selectCampaignA => _t(
    ar: 'الحملة الأولى (A)',
    en: 'Primary Campaign (A)',
    hi: 'पहला अभियान (A)',
  );
  String get selectCampaignB => _t(
    ar: 'الحملة المقارنة (B)',
    en: 'Benchmark Campaign (B)',
    hi: 'तुलनात्मक अभियान (B)',
  );
  String get sameCampaignWarning => _t(
    ar: 'يرجى اختيار حملتين مختلفتين لمشاهدة نسب المقارنة والفروق بدقة',
    en: 'Please select two different campaigns for accurate benchmark analysis',
    hi: 'सटीक बेंचमार्क विश्लेषण के लिए कृपया दो अलग-अलग अभियानों का चयन करें',
  );
  String get needAtLeastTwoCampaigns => _t(
    ar: 'تتطلب صفحة المقارنة وجود حملتين ترويجيتين على الأقل للشركة',
    en: 'At least two company campaigns are required for benchmark comparisons',
    hi: 'तुलनात्मक विश्लेषण के लिए कम से कम दो अभियानों की आवश्यकता है',
  );
  String get metricDifferenceLabel => _t(
    ar: 'الفارق / نسبة النمو',
    en: 'Delta / Variance',
    hi: 'अंतर / परिवर्तन दर',
  );
  String get winningCampaignTag => _t(
    ar: 'الحملة المتفوقة',
    en: 'Leading Campaign',
    hi: 'अग्रणी अभियान',
  );
  String get tiedCampaignsTag => _t(
    ar: 'أداء متماثل / تعادل',
    en: 'Even / Tied Performance',
    hi: 'समान प्रदर्शन',
  );
  String get uniqueShoppersLabel => _t(
    ar: 'المتسوقون والعملاء الفريدون',
    en: 'Unique Shoppers & Customers',
    hi: 'अद्वितीय खरीदार और ग्राहक',
  );
  String get avgBasketSpendLabel => _t(
    ar: 'متوسط قيمة سلة المشتريات',
    en: 'Average Basket Spend',
    hi: 'औसत बास्केट खर्च',
  );
  String get totalProductsSoldLabel => _t(
    ar: 'إجمالي المنتجات والقطع المباعة',
    en: 'Total Units Sold',
    hi: 'कुल बेची गई इकाइयाँ',
  );
  String get totalRevenueLabel => _t(
    ar: 'إجمالي المبيعات المحققة',
    en: 'Total Promo Sales Revenue',
    hi: 'कुल प्रचार बिक्री राजस्व',
  );
  String get disbursedPrizesValueLabel => _t(
    ar: 'قيمة الجوائز وقسائم الشراء',
    en: 'Claimed Rewards & Vouchers Value',
    hi: 'वितरित पुरस्कार और वाउचर मूल्य',
  );
  String get exportComparisonExcel => _t(
    ar: 'تصدير التقرير المقارن Excel',
    en: 'Export Benchmark Excel',
    hi: 'तुलनात्मक एक्सेल निर्यात करें',
  );
  String get exportComparisonCsv => _t(
    ar: 'CSV',
    en: 'CSV',
    hi: 'CSV',
  );
  String get comparisonBarChartTitle => _t(
    ar: 'المقارنة البيانية المزدوجة لأداء الحملتين',
    en: 'Dual Grouped Benchmark Bar Chart',
    hi: 'दोहरा समूहीकृत बार चार्ट',
  );
  String get comparisonDimensionRevenue => _t(
    ar: 'المبيعات المالية',
    en: 'Revenue',
    hi: 'राजस्व',
  );
  String get comparisonDimensionInvoices => _t(
    ar: 'عدد الفواتير',
    en: 'Invoices Count',
    hi: 'इनवॉइस संख्या',
  );
  String get comparisonDimensionProducts => _t(
    ar: 'عدد المنتجات',
    en: 'Products Sold',
    hi: 'उत्पाद मात्रा',
  );
  String get comparisonDimensionShoppers => _t(
    ar: 'عدد العملاء',
    en: 'Unique Shoppers',
    hi: 'ग्राहक संख्या',
  );
  String get intraCampaignWeekendTab => _t(
    ar: 'مقارنة ويك إند',
    en: 'Weekend Waves',
    hi: 'सप्ताहांत तुलना',
  );
  String get selectTargetCampaignToAnalyze => _t(
    ar: 'اختر الحملة المراد تحليل فتراتها',
    en: 'Select Campaign to Analyze',
    hi: 'विश्लेषण के लिए अभियान चुनें',
  );
  String get periodComparisonModeAuto => _t(
    ar: 'دورات الويك إند',
    en: 'Weekend Cycles',
    hi: 'सप्ताहांत चक्र',
  );
  String get periodComparisonModeCustom => _t(
    ar: 'تحديد فترة',
    en: 'Custom Period',
    hi: 'कस्टम अवधि',
  );
  String get weekendPeriodA => _t(
    ar: 'الويك إند / الفترة الأولى (A)',
    en: 'Primary Weekend / Period (A)',
    hi: 'पहला सप्ताहांत / अवधि (A)',
  );
  String get weekendPeriodB => _t(
    ar: 'الويك إند / الفترة المقارنة (B)',
    en: 'Benchmark Weekend / Period (B)',
    hi: 'तुलनात्मक सप्ताहांत / अवधि (B)',
  );
  String get allWeekendsProgressionView => _t(
    ar: 'مسار الويك إند',
    en: 'Weekend Progression',
    hi: 'सप्ताहांत प्रगति',
  );
  String get weekendHeadToHeadView => _t(
    ar: 'مقارنة بين فترتين',
    en: 'Period vs Period',
    hi: 'अवधि बनाम अवधि',
  );
  String get dailySalesVelocityLabel => _t(
    ar: 'كثافة المبيعات اليومية',
    en: 'Daily Sales Velocity',
    hi: 'दैनिक बिक्री गति',
  );
  String get peakWeekendBadge => _t(
    ar: 'الويك إند الذهبي الأفضل أداءً',
    en: 'Peak Performance Weekend',
    hi: 'सर्वश्रेष्ठ سप्ताहांत',
  );
  String get noWeekendsFoundNotice => _t(
    ar: 'لم يتم العثور على دورات تفعيل أو فواتير مسجلة لهذه الحملة حتى الآن',
    en: 'No recorded invoices or weekend cycles found for this campaign yet',
    hi: 'इस अभियान के लिए अभी तक कोई सप्ताहांत चक्र नहीं मिला',
  );
  String get selectCustomDateRange => _t(
    ar: 'اختر نطاق التاريخ',
    en: 'Select Date Range',
    hi: 'तिथि सीमा चुनें',
  );
  String get winningPeriodTag => _t(
    ar: 'الفترة المتفوقة',
    en: 'Leading Period',
    hi: 'अग्रणी अवधि',
  );
  String get weekendWavePrefix => _t(
    ar: 'الويك إند',
    en: 'Weekend',
    hi: 'सप्ताहांत',
  );
  String get activeDaysLabel => _t(
    ar: 'أيام التفعيل',
    en: 'Active Days',
    hi: 'सक्रिय दिन',
  );
  String get comparisonDimensionDailyVelocity => _t(
    ar: 'كثافة المبيعات اليومية',
    en: 'Daily Velocity',
    hi: 'दैनिक गति',
  );
  String get weekendProgressionChartTitle => _t(
    ar: 'تطور ومسار أداء الحملة عبر الويك إندات المتعاقبة',
    en: 'Campaign Performance Progression across Sequential Weekends',
    hi: 'क्रमिक सप्ताहांतों में अभियान प्रदर्शन प्रगति',
  );
  String get visualPerformanceComparisonTitle => _t(
    ar: 'التقرير والتحليل البياني الشامل للأداء',
    en: 'Comprehensive Visual Performance Benchmark & Report',
    hi: 'व्यापक दृश्य प्रदर्शन बेंचमार्क और रिपोर्ट',
  );
  String get visualPerformanceComparisonSubtitle => _t(
    ar: 'أعمدة بيانية تفاعلية ونسب تفوق ومخططات شارت لكافة مؤشرات الأداء',
    en: 'Interactive visual columns, proportional bars and growth charts across all KPIs',
    hi: 'सभी संकेतकों पर दृश्य कॉलम, आनुपातिक बार और चार्ट',
  );
  String get visualViewModeBars => _t(
    ar: 'أعمدة الحصص والتفوق',
    en: 'Proportional Columns & Shares',
    hi: 'आनुपातिक कॉलम और हिस्सेदारी',
  );
  String get visualViewModeChart => _t(
    ar: 'مخطط الأعمدة المقارن',
    en: 'Multi-Metric Grouped Columns',
    hi: 'मल्टी-मीट्रिक समूहीकृत कॉलम',
  );
  String get visualViewModeCombined => _t(
    ar: 'التقرير المتكامل',
    en: 'Combined Report',
    hi: 'संयुक्त रिपोर्ट',
  );
  String get leadingWinnerTag => _t(
    ar: 'متفوقة بـ',
    en: 'Leading by',
    hi: 'से आगे',
  );
  String get performanceDifferenceDelta => _t(
    ar: 'فارق الأداء',
    en: 'Delta Difference',
    hi: 'प्रदर्शन अंतर',
  );
  String get metricTiedPerformance => _t(
    ar: 'أداء متكافئ متعادل',
    en: 'Tied Performance',
    hi: 'समान प्रदर्शन',
  );

  // ---------------------------------------------------------------------------
  // 24. Customer Management & Excel Import (إدارة واستيراد العملاء)
  // ---------------------------------------------------------------------------
  String get addCustomerOrImportExcel => _t(ar: 'إضافة عملاء / استيراد إكسيل', en: 'Add Customers / Excel Import', hi: 'ग्राहक जोड़ें / एक्सेल आयात');
  String get addOrImportCustomers => addCustomerOrImportExcel;
  String get addSingleCustomer => _t(ar: 'إضافة عميل يدوي', en: 'Add Manual Customer', hi: 'मैन्युअल ग्राहक जोड़ें');
  String get importExcelBulk => _t(ar: 'استيراد جماعي من Excel', en: 'Bulk Excel/CSV Import', hi: 'एक्सेल/सीएसवी से थोक आयात');
  String get downloadExcelTemplate => _t(ar: 'تحميل نموذج Excel جاهز للتعبئة', en: 'Download Excel Template', hi: 'एक्सेल टेम्पलेट डाउनलोड करें');
  String get customerImportTitle => _t(ar: 'إدارة وإضافة عملاء الحملات', en: 'Campaign Customer Management', hi: 'अभियान ग्राहक प्रबंधन');
  String get customerImportSubtitle => _t(ar: 'إدخال عملاء جدد يدوياً أو رفع ملف Excel/CSV لإرسال رسائل وحملات الواتساب', en: 'Enter new customers manually or upload Excel/CSV to send WhatsApp campaigns', hi: 'व्हाट्सएप अभियान भेजने के लिए मैन्युअल रूप से ग्राहक जोड़ें या एक्सेल अपलोड करें');
  String get selectExcelOrCsvFile => _t(ar: 'اختر ملف Excel (.xlsx) أو CSV', en: 'Select Excel (.xlsx) or CSV File', hi: 'एक्सेल या सीएसवी फ़ाइल चुनें');
  String get fileParsedSuccessfully => _t(ar: 'تم فحص الملف واستخراج العملاء بنجاح', en: 'File analyzed & customers extracted successfully', hi: 'फ़ाइल का विश्लेषण किया गया और ग्राहक सफलतापूर्वक निकाले गए');
  String get confirmImportCustomers => _t(ar: 'تأكيد وحفظ العملاء في النظام', en: 'Confirm & Save Customers', hi: 'पुष्टि करें और ग्राहकों को सहेजें');
  String get importedFromExcelBadge => _t(ar: 'استيراد إكسيل', en: 'Excel Import', hi: 'एक्सेल आयात');
  String get excelSourceTag => importedFromExcelBadge;
  String get manuallyAddedBadge => _t(ar: 'إدخال يدوي', en: 'Manual Entry', hi: 'मैन्युअल प्रविष्टि');
  String get manualSourceTag => manuallyAddedBadge;
  String get customerAddedSuccess => _t(ar: 'تمت إضافة العميل وحفظه في قاعدة البيانات بنجاح', en: 'Customer added and saved successfully', hi: 'ग्राहक सफलतापूर्वक जोड़ा और सहेजा गया');
  String get customersImportedSuccess => _t(ar: 'تم استيراد وحفظ العملاء بنجاح في قاعدة البيانات', en: 'Customers imported and saved successfully', hi: 'ग्राहक सफलतापूर्वक आयात और सहेजे गए');
  String get validNumbersCount => _t(ar: 'أرقام صالحة', en: 'Valid Numbers', hi: 'मान्य नंबर');
  String get invalidNumbersCount => _t(ar: 'أرقام غير صالحة', en: 'Invalid Numbers', hi: 'अमान्य नंबर');
  String get duplicateNumbersCount => _t(ar: 'أرقام مكررة تم استبعادها', en: 'Duplicates Filtered', hi: 'डुप्लिकेट हटाए गए');
  String get branchNameCol => _t(ar: 'الفرع أو المدينة', en: 'Branch / City', hi: 'शाखा या शहर');

  // ---------------------------------------------------------------------------
  // 25. Advanced WhatsApp WAHA Server Features (ميزات سيرفر الواتساب المتقدمة)
  // ---------------------------------------------------------------------------
  String get liveScreenshotBtn => _t(ar: 'شاشة واتساب الحية', en: 'Live WhatsApp Screen', hi: 'लाइव व्हाट्सएप स्क्रीन');
  String get liveScreenshotTooltip => _t(ar: 'عرض لقطة شاشة مباشرة لشاشة واتساب ويب داخل السيرفر', en: 'View live screenshot of server WhatsApp Web session', hi: 'सर्वर व्हाट्सएप वेब स्क्रीन का लाइव स्क्रीनशॉट देखें');
  String get verifyActiveWhatsAppNumbers => _t(ar: 'فحص أرقام الواتساب النشطة', en: 'Verify Active WhatsApp Numbers', hi: 'सक्रिय व्हाट्सएप नंबर सत्यापित करें');
  String get verifyingNumbers => _t(ar: 'جارٍ فحص أرقام الواتساب للعملاء...', en: 'Verifying customer WhatsApp numbers...', hi: 'ग्राहक व्हाट्सएप नंबर सत्यापित कर रहे हैं...');
  String get activeWhatsAppOnlyFilter => _t(ar: 'أرقام واتساب نشطة فقط', en: 'Active WhatsApp Only', hi: 'केवल सक्रिय व्हाट्सएप');
  String get activeWhatsAppBadge => _t(ar: 'واتساب نشط', en: 'WhatsApp Active', hi: 'व्हाट्सएप सक्रिय');
  String get unregisteredWhatsAppBadge => _t(ar: 'غير مسجل بالواتساب', en: 'No WhatsApp', hi: 'व्हाट्सएप नहीं है');
  String get mediaMessageTab => _t(ar: 'إرفاق بوستر العرض', en: 'Attach Offer Poster', hi: 'ऑफ़र पोस्टर संलग्न करें');
  String get textMessageTab => _t(ar: 'رسالة نصية', en: 'Text Message', hi: 'टेक्स्ट संदेश');
  String get pollMessageTab => _t(ar: 'استطلاع رأي تفاعلي', en: 'Interactive Poll', hi: 'इंटरएक्टिव पोल');
  String get mediaUrlHint => _t(ar: 'رابط صورة أو بوستر العرض (URL)', en: 'Poster/Image URL', hi: 'छवि यूआरएल');
  String get pollQuestionLabel => _t(ar: 'سؤال استطلاع الرأي', en: 'Poll Question', hi: 'पोल प्रश्न');
  String get pollOptionLabel => _t(ar: 'خيار الإجابة', en: 'Option', hi: 'विकल्प');
  String get addPollOptionBtn => _t(ar: 'إضافة خيار', en: 'Add Option', hi: 'विकल्प जोड़ें');
  String get typingSimulatorLabel => _t(ar: 'محاكاة الكتابة الحقيقية (Typing Simulator)', en: 'Typing Simulator', hi: 'टाइपिंग सिम्युलेटर');
  String get typingSimulatorDesc => _t(ar: 'تشغيل إشارة "يكتب الآن..." قبل الإرسال لمحاكاة السلوك البشري الطبيعي وحماية الرقم من الحظر.', en: 'Display "Typing..." indicator before sending to mimic natural human messaging and protect number.', hi: 'मानव व्यवहार की नकल करने के लिए टाइपिंग दिखाएं।');
  String get aiAutoReplyLabel => _t(ar: 'المجيب الآلي الذكي (AI Auto-Reply Bot)', en: 'AI Auto-Reply Bot', hi: 'एआई ऑटो-रिप्लाई बॉट');
  String get aiAutoReplyDesc => _t(ar: 'الرد الفوري والذكي على ردود واستفسارات العملاء على الواتساب بذكاء ${AiModels.helperServicesLabel}.', en: 'Instant intelligent replies to incoming customer queries using ${AiModels.helperServicesLabel}.', hi: '${AiModels.helperServicesLabel} के साथ स्वचालित उत्तर।');
  String get qrPairingTitle => _t(ar: 'ربط الواتساب بالهاتف (QR Code)', en: 'Link WhatsApp via QR Code', hi: 'व्हाट्सएप क्यूआर लिंक');
  String get qrPairingSubtitle => _t(ar: 'امسح رمز الاستجابة السريعة بكاميرا الواتساب لربط رقم الهاتف فوراً بالسيرفر', en: 'Scan QR code with your WhatsApp camera to link your phone number to the server', hi: 'अपने फोन को जोड़ने के लिए क्यूआर कोड स्कैन करें');
  String get scanQrTab => _t(ar: 'مسح كود QR', en: 'Scan QR Code', hi: 'क्यूआर स्कैन');
  String get pairingCodeTab => _t(ar: 'كود الاقتران بالرقم', en: 'Pairing Code', hi: 'पेयरिंग कोड');
  String get enterPhoneToGetCode => _t(ar: 'أدخل رقم الهاتف لطلب كود الاقتران المكون من 8 خانات:', en: 'Enter phone number to generate 8-character pairing code:', hi: 'पेयरिंग कोड प्राप्त करने के लिए फोन नंबर दर्ज करें:');
  String get requestPairingCodeBtn => _t(ar: 'طلب كود الاقتران', en: 'Request Pairing Code', hi: 'कोड का अनुरोध करें');
  String get enterPairingCodeInWhatsApp => _t(ar: 'افتح واتساب > الأجهزة المرتبطة > ربط برقم الهاتف وأدخل الكود التالي:', en: 'Open WhatsApp > Linked Devices > Link with phone number and enter this code:', hi: 'व्हाट्सएप में यह कोड दर्ज करें:');
  String get unlinkAndChangeNumber => _t(ar: 'فك الارتباط وتغيير الرقم', en: 'Unlink & Change Number', hi: 'नंबर बदलें और अनलिंक करें');
  String get unlinkConfirmTitle => _t(ar: 'تأكيد فك الارتباط من هذا الرقم', en: 'Confirm Unlinking Current Phone', hi: 'अनलिंक की पुष्टि करें');
  String get unlinkConfirmDesc => _t(ar: 'سيتم تسجيل الخروج من جلسة الواتساب الحالية على السيرفر لتتمكن من ربط رقم هاتف جديد. هل ترغب بالاستمرار؟', en: 'This will log out the active WhatsApp session on the server to allow linking a new number. Continue?', hi: 'यह वर्तमान सत्र को लॉग आउट करेगा। क्या आप जारी रखना चाहते हैं?');
  String get pairingSuccessTitle => _t(ar: 'تم ربط رقم الهاتف بنجاح!', en: 'WhatsApp Linked Successfully!', hi: 'व्हाट्सएप सफलतापूर्वक लिंक हो गया!');
  String get restartSessionBtn => _t(ar: 'إعادة تشغيل الجلسة', en: 'Restart Session', hi: 'सत्र पुनरारंभ करें');
  String get linkNewWhatsAppNumber => _t(ar: 'ربط رقم واتساب جديد', en: 'Link New WhatsApp Number', hi: 'नया नंबर लिंक करें');
  String get linkViaQrOrCode => _t(ar: 'مسح كود QR أو كود الاقتران', en: 'Scan QR or Pairing Code', hi: 'क्यूआर या कोड स्कैन करें');
  String get sessionStatusStarting => _t(ar: 'جارٍ بدء تشغيل محرك الواتساب بالسيرفر...', en: 'Starting WhatsApp engine on server...', hi: 'सर्वर पर व्हाट्सएप शुरू हो रहा है...');
  String get sessionStatusScanQr => _t(ar: 'بانتظار مسح رمز الـ QR من هاتفك...', en: 'Waiting for QR scan from your phone...', hi: 'क्यूआर स्कैन की प्रतीक्षा है...');
  String get sessionStatusWorking => _t(ar: 'الجلسة متصلة وتعمل بنجاح', en: 'Session connected & active', hi: 'सत्र सक्रिय है');
  String get sessionStatusFailed => _t(ar: 'تعطلت الجلسة، يرجى إعادة التشغيل', en: 'Session failed, please restart', hi: 'सत्र विफल रहा, पुनः प्रयास करें');

  // ---------------------------------------------------------------------------
  // 26. Branch Invoices Distribution & Analytics (بيان إحصائي لتوزيع فواتير الفروع)
  // ---------------------------------------------------------------------------
  String get branchInvoicesChartTitle => _t(
    ar: 'توزيع فواتير الفروع',
    en: 'Branch Invoices Distribution',
    hi: 'शाखा चालान वितरण',
  );
  String get branchInvoicesChartSubtitle => _t(
    ar: 'رسم بياني يوضح عدد الفواتير ومبيعات العرض لكل فرع حسب الفترة المحددة',
    en: 'Graphical distribution of invoice counts and sales per branch for the selected period',
    hi: 'चयनित अवधि के लिए प्रति शाखा चालान संख्या और बिक्री का ग्राफिकल वितरण',
  );
  String get invoicesCountMetric => _t(ar: 'عدد الفواتير', en: 'Invoices Count', hi: 'चालान संख्या');
  String get promoSalesMetric => _t(ar: 'مبيعات العرض', en: 'Promo Sales', hi: 'प्रचार बिक्री');
  String get branchSharePercentage => _t(ar: 'نسبة الحصة', en: 'Share %', hi: 'हिस्सा %');
  String get filterByThisBranchTooltip => _t(
    ar: 'اضغط لحصر الفواتير على هذا الفرع فقط',
    en: 'Click to filter invoices strictly for this branch',
    hi: 'केवल इस शाखा के लिए चालान फ़िल्टर करने के लिए क्लिक करें',
  );
  String get showAllBranchesBtn => _t(ar: 'كافة الفروع', en: 'All Branches', hi: 'सभी शाखाएं');
  String get noInvoicesForSelectedPeriod => _t(
    ar: 'لا توجد فواتير مسجلة في الفروع للفترة الزمنية المحددة',
    en: 'No invoices recorded across branches for the selected time period',
    hi: 'चयनित समय अवधि के लिए शाखाओं में कोई चालान दर्ज नहीं है',
  );
  String get activeBranchIndicator => _t(ar: 'الفرع المحدد حالياً', en: 'Currently Selected Branch', hi: 'वर्तमान में चयनित शाखा');

  // ---------------------------------------------------------------------------
  // 27. WhatsApp webhook control (لوحة تحكم وبّهوك واتساب)
  // ---------------------------------------------------------------------------
  String get webhookInboxTab => _t(ar: 'وارد الويب هوك', en: 'Webhook Inbox', hi: 'वेबहुक इनबॉक्स');
  String get webhookStaffOnly => _t(
    ar: 'إدارة وبّهوك واتساب متاحة للمشرف الأعلى ومدير الشركة فقط.',
    en: 'WhatsApp webhook controls are available to the super admin and company admin only.',
    hi: 'व्हाट्सएप वेबहुक नियंत्रण केवल सुपर एडमिन और कंपनी एडमिन के लिए है।',
  );
  String get webhookTabControl => _t(ar: 'التحكم', en: 'Control', hi: 'नियंत्रण');
  String get webhookTabInbox => _t(ar: 'الفواتير الواردة', en: 'Incoming invoices', hi: 'आने वाले चालान');
  String get webhookTabReplies => _t(ar: 'الردود', en: 'Replies', hi: 'उत्तर');
  String get webhookTabNumbers => _t(ar: 'الأرقام المسموحة', en: 'Allowed numbers', hi: 'अनुमत नंबर');
  String get webhookTabInvites => _t(ar: 'روابط الدعوة', en: 'Invite links', hi: 'आमंत्रण लिंक');
  String get webhookEnabled => _t(ar: 'تشغيل استقبال الويب هوك', en: 'Webhook receiving', hi: 'वेबहुक प्राप्त करना');
  String get webhookEnabledHint => _t(
    ar: 'عند الإيقاف يُؤكد الخادم الاستلام ويتجاهل الرسائل دون منح هدايا.',
    en: 'When off, the server acknowledges the call and ignores messages without awarding gifts.',
    hi: 'बंद होने पर सर्वर कॉल स्वीकार करता है और संदेशों को अनदेखा करता है।',
  );
  String get webhookAutoReplies => _t(ar: 'الردود التلقائية', en: 'Auto replies', hi: 'स्वचालित उत्तर');
  String get webhookAutoRepliesHint => _t(
    ar: 'إرسال رد واتساب بعد التحقق أو الرفض أو التسجيل.',
    en: 'Send a WhatsApp reply after verification, rejection, or registration.',
    hi: 'सत्यापन, अस्वीकृति या पंजीकरण के बाद व्हाट्सएप उत्तर भेजें।',
  );
  String get webhookAllowListOnly => _t(ar: 'القائمة المسموحة فقط', en: 'Allow-list only', hi: 'केवल अनुमति सूची');
  String get webhookAllowListOnlyHint => _t(
    ar: 'الأرقام غير المسجلة تُرفض برسالة «غير مسموح» بدل المراجعة.',
    en: 'Unregistered numbers are rejected with the not-allowed reply instead of pending review.',
    hi: 'अपंजीकृत नंबर समीक्षा के बजाय अस्वीकृत उत्तर पाते हैं।',
  );
  String get webhookHealth => _t(ar: 'حالة الويب هوك', en: 'Webhook health', hi: 'वेबहुक स्थिति');
  String get webhookNoEventsYet => _t(ar: 'لم يصل أي حدث بعد.', en: 'No events yet.', hi: 'अभी कोई इवेंट नहीं।');
  String webhookLastEvent(String name, String time) => _t(
    ar: 'آخر حدث: $name · $time',
    en: 'Last event: $name · $time',
    hi: 'अंतिम इवेंट: $name · $time',
  );
  String get webhookSessionUnknown => _t(ar: 'حالة الجلسة غير معروفة', en: 'Session status unknown', hi: 'सत्र स्थिति अज्ञात');
  String get webhookAckCounts => _t(ar: 'حالات التسليم', en: 'Delivery statuses', hi: 'डिलीवरी स्थिति');
  String get webhookBusinessNumber => _t(ar: 'رقم واتساب المسجّل', en: 'Registered WhatsApp number', hi: 'पंजीकृत व्हाट्सएप नंबर');
  String get webhookBusinessNumberHint => _t(
    ar: 'الرقم الظاهر للعملاء في رابط الدعوة. رقم الجلسة الحي يظهر في الشارة أعلاه.',
    en: 'The number customers see on the invite link. The live session number is the chip above.',
    hi: 'आमंत्रण लिंक पर ग्राहकों को दिखने वाला नंबर। लाइव सत्र नंबर ऊपर चिप में है।',
  );
  String get webhookDisplayName => _t(ar: 'اسم العرض', en: 'Display name', hi: 'प्रदर्शित नाम');
  String get webhookSearchPhone => _t(ar: 'بحث برقم الهاتف', en: 'Search by phone', hi: 'फ़ोन से खोजें');
  String get webhookInboxEmpty => _t(ar: 'لا توجد رسائل مطابقة.', en: 'No matching messages.', hi: 'कोई मेल खाता संदेश नहीं।');
  String get webhookDetailTitle => _t(ar: 'تفاصيل الرسالة', en: 'Message detail', hi: 'संदेश विवरण');
  String get webhookPhone => _t(ar: 'الهاتف', en: 'Phone', hi: 'फ़ोन');
  String get webhookReceipt => _t(ar: 'رقم الفاتورة', en: 'Receipt number', hi: 'रसीद संख्या');
  String get webhookPrize => _t(ar: 'الجائزة', en: 'Prize', hi: 'पुरस्कार');
  String get webhookPrizeOptional => _t(ar: 'الجائزة (اختياري)', en: 'Prize (optional)', hi: 'पुरस्कार (वैकल्पिक)');
  String get webhookCampaign => _t(ar: 'الحملة', en: 'Campaign', hi: 'अभियान');
  String get webhookAnalysis => _t(ar: 'نتيجة التحليل', en: 'Analysis result', hi: 'विश्लेषण परिणाम');
  String get webhookVerdict => _t(ar: 'الحكم', en: 'Verdict', hi: 'निर्णय');
  String get webhookConfidence => _t(ar: 'درجة الثقة', en: 'Confidence', hi: 'विश्वास');
  String get webhookReply => _t(ar: 'الرد التلقائي', en: 'Auto reply', hi: 'स्वचालित उत्तर');
  String get webhookNoReply => _t(ar: 'لم يُنشأ رد.', en: 'No reply was generated.', hi: 'कोई उत्तर नहीं बना।');
  String get webhookTemplateHint => _t(
    ar: 'المتغيرات: {name} {prize} {receipt} {campaign}',
    en: 'Placeholders: {name} {prize} {receipt} {campaign}',
    hi: 'प्लेसहोल्डर: {name} {prize} {receipt} {campaign}',
  );
  String webhookTemplateLabel(String key) {
    switch (key) {
      case 'verified':
        return _t(ar: 'تم التحقق ومنح الجائزة', en: 'Verified with prize', hi: 'पुरस्कार के साथ सत्यापित');
      case 'pendingReview':
        return _t(ar: 'قيد المراجعة', en: 'Pending review', hi: 'समीक्षा लंबित');
      case 'rejected':
        return _t(ar: 'مرفوضة', en: 'Rejected', hi: 'अस्वीकृत');
      case 'notAllowed':
        return _t(ar: 'رقم غير مسموح', en: 'Number not allowed', hi: 'नंबर अनुमत नहीं');
      case 'registered':
        return _t(ar: 'تم التسجيل بكود الدعوة', en: 'Registered with invite code', hi: 'आमंत्रण कोड से पंजीकृत');
      default:
        return key;
    }
  }

  String webhookStatusLabel(String key) {
    switch (key) {
      case 'all':
        return all;
      case 'verified':
        return _t(ar: 'تم التحقق', en: 'Verified', hi: 'सत्यापित');
      case 'pending_review':
        return _t(ar: 'قيد المراجعة', en: 'Pending review', hi: 'समीक्षा लंबित');
      case 'rejected':
        return _t(ar: 'مرفوضة', en: 'Rejected', hi: 'अस्वीकृत');
      case 'verified_without_prize':
        return _t(ar: 'تحققت بدون جائزة', en: 'Verified without prize', hi: 'पुरस्कार के बिना सत्यापित');
      case 'not_allowed':
        return _t(ar: 'غير مسموح', en: 'Not allowed', hi: 'अनुमत नहीं');
      case 'registered':
        return _t(ar: 'تم التسجيل', en: 'Registered', hi: 'पंजीकृत');
      case 'stored':
        return _t(ar: 'نص محفوظ', en: 'Stored text', hi: 'सहेजा पाठ');
      case 'ignored':
        return _t(ar: 'تم التجاهل', en: 'Ignored', hi: 'अनदेखा');
      case 'error':
        return _t(ar: 'خطأ', en: 'Error', hi: 'त्रुटि');
      default:
        return key;
    }
  }

  String get webhookCustomerName => _t(ar: 'اسم العميل', en: 'Customer name', hi: 'ग्राहक का नाम');
  String get webhookNumberActive => _t(ar: 'نشط', en: 'Active', hi: 'सक्रिय');
  String get webhookNumberInactive => _t(ar: 'موقوف', en: 'Inactive', hi: 'निष्क्रिय');
  String get webhookNoNumbers => _t(ar: 'لا توجد أرقام مسجّلة.', en: 'No registered numbers.', hi: 'कोई पंजीकृत नंबर नहीं।');
  String get webhookNoCampaigns => _t(ar: 'لا توجد حملات ظاهرة في هذا النطاق.', en: 'No campaigns are visible in this scope.', hi: 'इस दायरे में कोई अभियान नहीं है।');
  String get webhookInviteHelp => _t(
    ar: 'رابط wa.me يفتح محادثة مع رقم النشاط ورسالة تحتوي كود الانضمام. إذا كان التسجيل الذاتي مفعلاً، يُسجَّل الرقم تلقائياً على الحملة.',
    en: 'The wa.me link opens a chat with the business number and a prefilled join code. When self-registration is on, that number is linked to the campaign.',
    hi: 'wa.me लिंक व्यवसाय नंबर पर जुड़ने का कोड भरकर चैट खोलता है। स्वयं-पंजीकरण चालू होने पर नंबर अभियान से जुड़ जाता है।',
  );
  String get webhookSelfRegistration => _t(ar: 'تسجيل ذاتي لهذه الحملة', en: 'Self-registration for this campaign', hi: 'इस अभियान के लिए स्वयं-पंजीकरण');
  String get webhookSelfRegistrationHint => _t(
    ar: 'رسالة تحتوي كوداً صالحاً من رقم غير مسجل تُنشئ ربطاً تلقائياً.',
    en: 'A message with a valid code from an unknown number creates the sender link.',
    hi: 'अज्ञात नंबर से मान्य कोड वाला संदेश लिंक बनाता है।',
  );
  String get webhookJoinCode => _t(ar: 'كود الانضمام', en: 'Join code', hi: 'जुड़ने का कोड');
  String get webhookGenerateCode => _t(ar: 'توليد كود', en: 'Generate code', hi: 'कोड बनाएँ');
  String get webhookInviteNeedsNumber => _t(
    ar: 'احفظ رقم النشاط وكود الانضمام ليظهر الرابط ورمز QR.',
    en: 'Save the business number and a join code to show the link and QR code.',
    hi: 'लिंक और क्यूआर दिखाने के लिए व्यवसाय नंबर और जुड़ने का कोड सहेजें।',
  );
  String get webhookShareLink => _t(ar: 'فتح الرابط', en: 'Open link', hi: 'लिंक खोलें');
}



