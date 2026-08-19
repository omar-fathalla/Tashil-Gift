import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';

/// Provide your actual Gemini API Key here or load from environment variables
const String _geminiApiKey =
    'REMOVED_SECRET';

final aiReceiptServiceProvider = Provider<AiReceiptService>((ref) {
  return AiReceiptService();
});

class ExtractedProductItem {
  final String name;
  final double price;
  final int quantity;
  final bool isTargetCompany;
  final String barcode;

  ExtractedProductItem({
    required this.name,
    required this.price,
    required this.quantity,
    required this.isTargetCompany,
    this.barcode = '',
  });

  double get totalPrice => price * quantity;

  factory ExtractedProductItem.fromJson(Map<String, dynamic> json) {
    return ExtractedProductItem(
      name: json['name']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      isTargetCompany: json['isTargetCompany'] ?? false,
      barcode: json['barcode']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'price': price,
      'quantity': quantity,
      'isTargetCompany': isTargetCompany,
      'barcode': barcode,
      'totalPrice': totalPrice,
    };
  }

  ExtractedProductItem copyWith({
    String? name,
    double? price,
    int? quantity,
    bool? isTargetCompany,
    String? barcode,
  }) {
    return ExtractedProductItem(
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      isTargetCompany: isTargetCompany ?? this.isTargetCompany,
      barcode: barcode ?? this.barcode,
    );
  }
}

class AiReceiptAnalysisResult {
  final bool isValid;
  final String receiptNumber;
  final double targetCompanyTotal;
  final String receiptDate;
  final List<ExtractedProductItem> extractedProducts;
  final String storeChainDetected;
  final String branchDetected;
  final bool isBranchMatched;
  final String message;
  final List<String> unfulfilledConditions;
  final int durationMs;
  final double durationSeconds;
  final String kpiRating;
  final String kpiColorHex;
  final int chancesEarned;
  final String matchedRuleId;
  final String matchedRuleTitle;
  final String matchedRewardValue;
  final double matchedRewardAmount;
  final String matchedRewardType;

  AiReceiptAnalysisResult({
    required this.isValid,
    required this.receiptNumber,
    required this.targetCompanyTotal,
    this.receiptDate = '',
    this.extractedProducts = const [],
    this.storeChainDetected = '',
    this.branchDetected = '',
    this.isBranchMatched = true,
    required this.message,
    this.unfulfilledConditions = const [],
    this.durationMs = 0,
    this.durationSeconds = 0.0,
    String? kpiRating,
    String? kpiColorHex,
    this.chancesEarned = 1,
    this.matchedRuleId = '',
    this.matchedRuleTitle = '',
    this.matchedRewardValue = '',
    this.matchedRewardAmount = 0.0,
    this.matchedRewardType = '',
  })  : kpiRating = kpiRating ?? calculateKpiRating(durationSeconds > 0 ? durationSeconds : (durationMs / 1000.0)),
        kpiColorHex = kpiColorHex ?? calculateKpiColor(durationSeconds > 0 ? durationSeconds : (durationMs / 1000.0));

  static String calculateKpiRating(double seconds) {
    if (seconds <= 0.0) return '⚡ فائق السرعة (Ultra Fast)';
    if (seconds < 2.0) return '⚡ فائق السرعة (Ultra Fast)';
    if (seconds <= 3.5) return '🟢 ممتاز (Excellent)';
    if (seconds <= 5.0) return '🟡 مقبول (Acceptable)';
    return '🔴 بطيء (Slow)';
  }

  static String calculateKpiColor(double seconds) {
    if (seconds <= 0.0) return '#00C853';
    if (seconds < 2.0) return '#00C853';
    if (seconds <= 3.5) return '#2E7D32';
    if (seconds <= 5.0) return '#F57F17';
    return '#D50000';
  }

  factory AiReceiptAnalysisResult.fromJson(Map<String, dynamic> json, {int durationMs = 0}) {
    final productsRaw = json['extractedProducts'];
    List<ExtractedProductItem> productsList = [];
    if (productsRaw is List) {
      productsList = productsRaw
          .map((item) => ExtractedProductItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    final unfulfilledRaw = json['unfulfilledConditions'];
    List<String> unfulfilledList = [];
    if (unfulfilledRaw is List) {
      unfulfilledList = unfulfilledRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }

    final int rawDurationMs = json['durationMs'] is num ? (json['durationMs'] as num).toInt() : durationMs;
    final double rawDurationSec = json['durationSeconds'] is num
        ? (json['durationSeconds'] as num).toDouble()
        : (rawDurationMs / 1000.0);

    return AiReceiptAnalysisResult(
      isValid: json['isValid'] ?? false,
      receiptNumber: json['receiptNumber']?.toString() ?? '',
      targetCompanyTotal: (json['targetCompanyTotal'] as num?)?.toDouble() ?? 0.0,
      receiptDate: json['receiptDate']?.toString() ?? '',
      extractedProducts: productsList,
      storeChainDetected: json['storeChainDetected']?.toString() ?? '',
      branchDetected: json['branchDetected']?.toString() ?? '',
      isBranchMatched: json['isBranchMatched'] ?? true,
      message: json['message']?.toString() ?? '',
      unfulfilledConditions: unfulfilledList,
      durationMs: rawDurationMs,
      durationSeconds: rawDurationSec,
      kpiRating: json['kpiRating']?.toString(),
      kpiColorHex: json['kpiColorHex']?.toString(),
      chancesEarned: (json['chancesEarned'] as num?)?.toInt() ?? 1,
      matchedRuleId: json['matchedRuleId']?.toString() ?? '',
      matchedRuleTitle: json['matchedRuleTitle']?.toString() ?? '',
      matchedRewardValue: json['matchedRewardValue']?.toString() ?? '',
      matchedRewardAmount: (json['matchedRewardAmount'] as num?)?.toDouble() ?? 0.0,
      matchedRewardType: json['matchedRewardType']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isValid': isValid,
      'receiptNumber': receiptNumber,
      'targetCompanyTotal': targetCompanyTotal,
      'receiptDate': receiptDate,
      'extractedProducts': extractedProducts.map((p) => p.toJson()).toList(),
      'storeChainDetected': storeChainDetected,
      'branchDetected': branchDetected,
      'isBranchMatched': isBranchMatched,
      'message': message,
      'unfulfilledConditions': unfulfilledConditions,
      'durationMs': durationMs,
      'durationSeconds': durationSeconds,
      'kpiRating': kpiRating,
      'kpiColorHex': kpiColorHex,
      'chancesEarned': chancesEarned,
      'matchedRuleId': matchedRuleId,
      'matchedRuleTitle': matchedRuleTitle,
      'matchedRewardValue': matchedRewardValue,
      'matchedRewardAmount': matchedRewardAmount,
      'matchedRewardType': matchedRewardType,
    };
  }

  AiReceiptAnalysisResult copyWith({
    bool? isValid,
    String? receiptNumber,
    double? targetCompanyTotal,
    String? receiptDate,
    List<ExtractedProductItem>? extractedProducts,
    String? storeChainDetected,
    String? branchDetected,
    bool? isBranchMatched,
    String? message,
    List<String>? unfulfilledConditions,
    int? durationMs,
    double? durationSeconds,
    String? kpiRating,
    String? kpiColorHex,
    int? chancesEarned,
    String? matchedRuleId,
    String? matchedRuleTitle,
    String? matchedRewardValue,
    double? matchedRewardAmount,
    String? matchedRewardType,
  }) {
    final double effectiveDurationSec = durationSeconds ?? this.durationSeconds;
    return AiReceiptAnalysisResult(
      isValid: isValid ?? this.isValid,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      targetCompanyTotal: targetCompanyTotal ?? this.targetCompanyTotal,
      receiptDate: receiptDate ?? this.receiptDate,
      extractedProducts: extractedProducts ?? this.extractedProducts,
      storeChainDetected: storeChainDetected ?? this.storeChainDetected,
      branchDetected: branchDetected ?? this.branchDetected,
      isBranchMatched: isBranchMatched ?? this.isBranchMatched,
      message: message ?? this.message,
      unfulfilledConditions: unfulfilledConditions ?? this.unfulfilledConditions,
      durationMs: durationMs ?? this.durationMs,
      durationSeconds: effectiveDurationSec,
      kpiRating: kpiRating ?? (durationSeconds != null ? calculateKpiRating(effectiveDurationSec) : this.kpiRating),
      kpiColorHex: kpiColorHex ?? (durationSeconds != null ? calculateKpiColor(effectiveDurationSec) : this.kpiColorHex),
      chancesEarned: chancesEarned ?? this.chancesEarned,
      matchedRuleId: matchedRuleId ?? this.matchedRuleId,
      matchedRuleTitle: matchedRuleTitle ?? this.matchedRuleTitle,
      matchedRewardValue: matchedRewardValue ?? this.matchedRewardValue,
      matchedRewardAmount: matchedRewardAmount ?? this.matchedRewardAmount,
      matchedRewardType: matchedRewardType ?? this.matchedRewardType,
    );
  }
}

class AiReceiptService {
  late final GenerativeModel _model;
  late final GenerativeModel _fallbackModel1;
  late final GenerativeModel _fallbackModel2;
  final String modelName;

  AiReceiptService({this.modelName = 'gemini-flash-latest'}) {
    _model = _createModel(modelName);
    _fallbackModel1 = _createModel('gemini-3.5-flash');
    _fallbackModel2 = _createModel('gemini-3.7-flash');
  }

  static GenerativeModel _createModel(String name) {
    return GenerativeModel(
      model: name,
      apiKey: _geminiApiKey,
      systemInstruction: Content.system(
        'أنت مدقق مالي فائق السرعة والدقة في قراءة وتحليل فواتير السوبر ماركت وتدقيق عروض الشركات الاستهلاكية (FMCG). '
        'مهمتك فحص صور الفواتير فورياً واستخراج البيانات الأساسية: اسم السلسلة، الفرع، رقم الفاتورة، تاريخ الشراء، '
        'وحساب إجمالي المشتريات لمنتجات الشركة الراعية فقط بأعلى سرعة ممكنة، وسرد أي شروط غير محققة بدقة وبصيغة JSON.',
      ),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.1,
        maxOutputTokens: 4096,
        responseSchema: Schema.object(
          properties: {
            'isValid': Schema.boolean(
              description:
                  'True if this is a valid supermarket receipt containing target company products and meeting all rules.',
            ),
            'receiptNumber': Schema.string(
              description: 'The unique receipt number or transaction ID (e.g., 295/8/211/220726). Return empty string if not found.',
            ),
            'targetCompanyTotal': Schema.number(
              description:
                  'The total sum in EGP of ONLY the target company products found on the receipt.',
            ),
            'receiptDate': Schema.string(
              description:
                  'The date of purchase extracted from receipt (e.g. 22/07/2026 or 2026-07-22). Return empty string if not found.',
            ),
            'storeChainDetected': Schema.string(
              description:
                  'The store or supermarket chain name extracted from the receipt header (e.g. أسواق فتح الله, كارفور, سبينس). Return empty string if not found.',
            ),
            'branchDetected': Schema.string(
              description:
                  'The branch name, branch location, or cashier/branch code extracted from the receipt header (e.g. فرع الهانوفيل, سموحة, المعادي, فرع 04). Return empty string if not found.',
            ),
            'isBranchMatched': Schema.boolean(
              description:
                  'True if the detected store chain and branch match the required chain and allowed branches for this campaign. False if from an unapproved store or branch.',
            ),
            'extractedProducts': Schema.array(
              description: 'List of all individual items/products found on the receipt with names, prices, quantities, and matched barcodes.',
              items: Schema.object(
                properties: {
                  'name': Schema.string(description: 'Product name as printed on receipt.'),
                  'price': Schema.number(description: 'Unit or line price in EGP/AED.'),
                  'quantity': Schema.integer(description: 'Quantity purchased.'),
                  'isTargetCompany': Schema.boolean(
                    description: 'True if this product belongs to the target company being promoted.',
                  ),
                  'barcode': Schema.string(
                    description: 'The product barcode or item code if detected or matched from company catalog. Return empty string if not found.',
                  ),
                },
                requiredProperties: ['name', 'price', 'quantity', 'isTargetCompany'],
              ),
            ),
            'chancesEarned': Schema.integer(
              description:
                  'The number of lottery/draw chances earned based on minimum spend multipliers. Default is 1 if valid, 0 if invalid.',
            ),
            'message': Schema.string(
              description:
                  'A concise report in Arabic explaining the validation result, or the exact errors if conditions fail.',
            ),
            'matchedRuleId': Schema.string(
              description:
                  'The exact ID of the matched promotional rule (e.g. rule_1, rule_2, rule_3, rule_4, rule_5), or empty string if no specific rule matched.',
            ),
            'matchedRuleTitle': Schema.string(
              description:
                  'The title of the matched promotional rule, or empty string if none.',
            ),
            'matchedRewardValue': Schema.string(
              description:
                  'The exact reward title/description earned from the matched rule (e.g. فواتشر بقيمة 125 جنيه, تريزيمي 250 مل هدية, كلير 90 مل هدية), or empty string.',
            ),
            'matchedRewardAmount': Schema.number(
              description:
                  'The total voucher or monetary amount earned from the matched rule if applicable, or 0.',
            ),
            'matchedRewardType': Schema.string(
              description:
                  'The type of reward: voucher, free_product, or game_spin. Return empty string if none.',
            ),
            'unfulfilledConditions': Schema.array(
              description:
                  'List of specific unmet conditions or errors explaining why the receipt is invalid (e.g. date out of range, minimum spend not reached, wrong store/branch, no target products found). Return empty array if all conditions are met.',
              items: Schema.string(),
            ),
          },
          requiredProperties: [
            'isValid',
            'receiptNumber',
            'targetCompanyTotal',
            'receiptDate',
            'storeChainDetected',
            'branchDetected',
            'isBranchMatched',
            'extractedProducts',
            'message',
          ],
        ),
      ),
    );
  }

  Future<AiReceiptAnalysisResult> analyzeReceiptImage(
    Uint8List imageBytes,
    String mimeType, {
    required String targetCompany,
    required double minimumSpend,
    List<String> requiredProducts = const [],
    List<String> registeredBarcodes = const [],
    Map<String, String> catalogBarcodeMap = const {},
    String retailChainName = '',
    List<String> allowedBranches = const [],
    bool isAllBranches = true,
    List<BranchModel> registeredBranches = const [],
    DateTime? startDate,
    DateTime? endDate,
    String customPrompt = '',
    bool allowMultipleChances = false,
    int maxChancesPerReceipt = 0,
    List<PromotionalRuleItem> promotionalRules = const [],
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final imagePart = DataPart(mimeType, imageBytes);
      
      final productsCondition = requiredProducts.isNotEmpty
          ? 'تنبيه خاص بالمنتجات المشروطة بالعرض: المنتجات المشمولة في هذا العرض هي فقط: [${requiredProducts.join("، ")}]. يجب أن تحتوي الفاتورة على واحد أو أكثر من هذه المنتجات المحددة، ويجب أن يتم حساب إجمالي (targetCompanyTotal) بناءً على أسعار هذه المنتجات المشترطة المحددة فقط وتجاهل أي منتجات أخرى حتى لو كانت تابعة لنفس الشركة لكنها ليست ضمن هذه القائمة.'
          : 'ابحث عن كافة الأصناف المشتراة، وقم بتصفيتها لتحديد المنتجات التابعة لشركة "$targetCompany" فقط وجمع أسعارها.';

      String catalogCondition = '';
      if (registeredBarcodes.isNotEmpty) {
        if (registeredBarcodes.length <= 25) {
          catalogCondition = 'قائمة كروت منتجات/باركودات الشركة المعتمدة: ${registeredBarcodes.join(", ")}.';
        } else {
          catalogCondition = 'العرض يشمل كافة منتجات وباركودات شركة "$targetCompany" المعتمدة (إجمالي ${registeredBarcodes.length} صنف مسجل بالكتالوج). ابحث عن أي منتج تابع للعلامة التجارية.';
        }
      }

      String promotionalRulesCondition = '';
      if (promotionalRules.isNotEmpty) {
        final rulesListFormatted = promotionalRules.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final r = entry.value;
          final id = r.id.isNotEmpty ? r.id : 'rule_$idx';
          final multText = r.allowMultipliers ? ' (تتضاعف الهدايا مع زيادة الكمية)' : '';
          final voucherVal = r.totalVoucherValue > 0 ? ' [قيمة نقدية: ${r.totalVoucherValue.toInt()} ج.م]' : (r.rewardAmount > 0 ? ' [قيمة نقدية: ${r.rewardAmount.toInt()} ج.م]' : '');
          return '$idx. [معرف ID: "$id"] "${r.ruleTitle}" ➔ الشرط: شراء (${r.minQuantity}) أو أكثر من [${r.triggerProduct}] ➔ الجائزة المستحقة: [${r.rewardValue}$voucherVal] (نوع: ${r.rewardType})$multText';
        }).join('\n');

        promotionalRulesCondition = '''
- محرك القواعد والعروض الترويجية والجوائز المعتمدة (Promotional Rules Engine):
$rulesListFormatted

تعليمات مطابقة القواعد الترويجية وتحديد الجائزة المستحقة:
1. افحص بدقة أسماء الأصناف في الفاتورة والكميات المشتراة (Quantities).
2. في حال وجود أكثر من قاعدة لنفس المنتج بمستويات كميات مختلفة (مثل: شراء 1 اسبراي ريكسونا -> 50 ج.م، وشراء 2 اسبراي ريكسونا -> 125 ج.م)، يجب عليك اختيار القاعدة ذات الكمية المشروطة الأعلى التي حققها العميل (مثال: إذا اشترى 2، اختر قاعدة الـ 125 ج.م).
3. قم بتعبئة حقل (matchedRuleId) بمعرف القاعدة المطابقة (مثل "rule_4" أو "rule_1").
4. قم بتعبئة حقل (matchedRuleTitle) بعنوان القاعدة المطابقة.
5. قم بتعبئة حقل (matchedRewardValue) بالنص الدقيق للجائزة المستحقة (مثل "فواتشر بقيمة 125 جنيه" أو "تريزيمي 250 مل هدية").
6. قم بتعبئة حقل (matchedRewardAmount) بالقيمة النقدية للمكافأة إن وجدت (مثل 125.0 أو 50.0).
7. قم بتعبئة حقل (matchedRewardType) بنوع المكافأة ("voucher" أو "free_product").
8. إذا لم تنطبق أي من هذه القواعد الخاصة، اترك حقل (matchedRuleId) فارغاً "".
''';
      }

      String branchSignaturesText = '';
      if (registeredBranches.isNotEmpty) {
        final sigsList = registeredBranches.map((b) {
          final s = b.receiptSignature;
          final codePart = b.branchCode.isNotEmpty ? 'كود: "${b.branchCode}", ' : '';
          final cityPart = b.city.isNotEmpty ? 'المدينة: "${b.city}", ' : '';
          final addrPart = b.address.isNotEmpty ? 'العنوان: "${b.address}", ' : '';
          String sigPart = '';
          if (s != null && s.hasSignature) {
            sigPart = 'Store ID: "${s.storeId}", نسق الفاتورة/الباركود: "${s.receiptPattern}", نسق الـ POS: "${s.posNumberPattern}", الرقم الضريبي: "${s.taxNumber}", الهاتف: "${s.hotline}", كلمات الرأس: ${s.headerKeywords.join("/")}';
          }
          return '  * فرع "${b.branchName}" (${b.retailChainName}): [$codePart$cityPart$addrPart$sigPart]';
        }).join('\n');
        branchSignaturesText = '''
- دليل الفروع والبصمات الهيكلية المعتمدة لنقاط البيع (Store Branches & POS Signatures):
$sigsList
استخدم هذه الأكواد والعناوين والبصمات لمطابقة الفرع والسلسلة بدقة قاطعة 100% حتى لو كان الشعار باهتاً أو الاسم مختصراً أو مذكوراً برقم الكود فقط.
''';
      }

      String branchCondition = '';
      if (retailChainName.trim().isNotEmpty) {
        if (!isAllBranches && allowedBranches.isNotEmpty) {
          branchCondition = '''
- السلسلة المعتمدة للحملة: "$retailChainName".
- الفروع المعتمدة حصراً لهذا العرض: [${allowedBranches.join("، ")}].
- المطلوب للفرع: افحص رأس الفاتورة بدقة واستخرج اسم السلسلة في (storeChainDetected) واسم الفرع أو عنوانه أو رقمه في (branchDetected). إذا كانت الفاتورة صادرة من أحد الفروع المعتمدة المذكورة أعلاه، حدد (isBranchMatched = true). إذا كانت من فرع آخر أو سلسلة أخرى، حدد (isBranchMatched = false) و (isValid = false) واكتب في (message) أن الفاتورة صادرة من فرع غير مشمول بالعرض.
$branchSignaturesText
''';
        } else {
          branchCondition = '''
- السلسلة المعتمدة للحملة: "$retailChainName" (كافة الفروع مشمولة).
- المطلوب للفرع: استخرج اسم السلسلة في (storeChainDetected) والفرع في (branchDetected)، وحدد (isBranchMatched = true) إذا كانت تابعة لـ "$retailChainName".
$branchSignaturesText
''';
        }
      } else if (branchSignaturesText.isNotEmpty) {
        branchCondition = branchSignaturesText;
      }

      String chancesCondition = '';
      if (allowMultipleChances && minimumSpend > 0) {
        chancesCondition = '''
- مضاعفة فرص السحب واللعب: الحد الأدنى المطلوب هو $minimumSpend ج.م. كل مضاعف لهذا المبلغ من منتجات الشركة يمنح العميل فرصة إضافية (المعادلة: إجمالي منتجات الشركة مقسوماً على $minimumSpend مقرباً لأقرب رقم صحيح لأسفل). احسب عدد الفرص وضعه في حقل (chancesEarned)${maxChancesPerReceipt > 0 ? ' بحد أقصى $maxChancesPerReceipt فرص' : ''}.
''';
      }

      String finalPromptText;
      if (customPrompt.trim().isNotEmpty) {
        String processedPrompt = customPrompt
            .replaceAll('{TARGET_COMPANY}', targetCompany)
            .replaceAll('{REQUIRED_PRODUCTS}', requiredProducts.join(", "))
            .replaceAll('{RETAIL_CHAIN}', retailChainName)
            .replaceAll('{BRANCHES}', allowedBranches.join(", "));
        
        if (minimumSpend > 0) {
          processedPrompt = processedPrompt.replaceAll('{MIN_SPEND}', minimumSpend.toString());
        } else {
          // If no minimum spend is configured, clean up any {MIN_SPEND} clauses gracefully
          processedPrompt = processedPrompt
              .replaceAll(RegExp(r'\n?-?\s*إجمالي المنتجات يجب أن يلبي الحد الأدنى\s*\{MIN_SPEND\}[^\n]*'), '')
              .replaceAll('{MIN_SPEND}', '0');
        }
        finalPromptText = processedPrompt;
        
        finalPromptText += '''

تنبيهات إضافية هامة جداً:
1. ابحث عن تاريخ الشراء (Date / التاريخ) بالفاتورة واستخرجه بوضوح في حقل receiptDate (مثال: 22/07/2026).
2. استخرج رقم الفاتورة أو Transaction ID بوضوح في حقل receiptNumber (مثال: 295/8/211/220726).
3. استخرج اسم السلسلة والفرع من رأس الفاتورة بدقة.
$branchCondition
$catalogCondition
$productsCondition
$promotionalRulesCondition
$chancesCondition

تأكد من إرجاع النتيجة بصيغة JSON المحتوي على الحقول المفروضة:
isValid (boolean), receiptNumber (string), targetCompanyTotal (number), receiptDate (string), storeChainDetected (string), branchDetected (string), isBranchMatched (boolean), chancesEarned (integer), message (string).
''';
      } else {
        finalPromptText = '''
        أنت مساعد ذكي فائق الدقة متخصص في فحص وتدقيق فواتير السوبر ماركت الخاصة بعروض "$targetCompany".
        قم بتحليل صورة الفاتورة المرفقة فورياً وبأقصى سرعة واستخرج البيانات التالية:
        
        1. "رأس الفاتورة والفرع": استخرج اسم سلسلة السوبرماركت في (storeChainDetected)، واسم أو رقم أو عنوان الفرع في (branchDetected).
        $branchCondition
        2. "رقم الفاتورة" (Receipt Number أو Transaction ID). قد يكون رقم البون أو التركيبة المطبوعة في الأعلى أو الأسفل (مثال: 295/8/211/220726)، ابحث عنه بدقة واستخرجه.
        3. "تاريخ الشراء" (Receipt Date). استخرج تاريخ اليوم والوقت المكتوب بالفاتورة في حقل receiptDate (مثال: 22/07/2026).
        4. $catalogCondition
        5. $productsCondition
        6. $promotionalRulesCondition
        7. احسب الإجمالي المؤهل للحملة في حقل (targetCompanyTotal).
        8. $chancesCondition
        
        شروط الموافقة (isValid = true):
        - يجب أن تكون الصورة لفاتورة حقيقية ومقروءة وواضحة الرأس.
        - يجب أن يكون "رقم الفاتورة" واضحاً وموجوداً.
        - يجب أن تكون الفاتورة سارية وتحتوي على تاريخ شراء واضح.
        - يجب أن تشتمل الفاتورة على منتجات مؤهلة للعرض من "$targetCompany" وفق الشروط المحددة أعلاه.
        - يجب أن تكون صادرة من السلسلة والفرع المعتمدين للعرض (isBranchMatched = true).
        
        في حقل الـ (message)، قم بكتابة تقرير باللغة العربية موجز ودقيق بنتيجة الفحص.
      ''';
      }

      final prompt = TextPart(finalPromptText);

      GenerateContentResponse response;
      try {
        response = await _model.generateContent([
          Content.multi([prompt, imagePart]),
        ]).timeout(const Duration(seconds: 12));
      } catch (e1) {
        try {
          response = await _fallbackModel1.generateContent([
            Content.multi([prompt, imagePart]),
          ]).timeout(const Duration(seconds: 12));
        } catch (e2) {
          response = await _fallbackModel2.generateContent([
            Content.multi([prompt, imagePart]),
          ]).timeout(const Duration(seconds: 12));
        }
      }

      stopwatch.stop();
      final int durationMs = stopwatch.elapsedMilliseconds;
      final double durationSeconds = durationMs / 1000.0;

      if (response.text != null && response.text!.trim().isNotEmpty) {
        final Map<String, dynamic> jsonMap = _cleanAndParseJson(response.text!);
        var result = AiReceiptAnalysisResult.fromJson(jsonMap, durationMs: durationMs);

        // Calculate / enforce chances earned based on spend multipliers
        int calculatedChances = result.chancesEarned;
        if (result.isValid) {
          if (minimumSpend > 0 && result.targetCompanyTotal >= minimumSpend) {
            if (allowMultipleChances) {
              final computed = (result.targetCompanyTotal / minimumSpend).floor();
              calculatedChances = computed > 0 ? computed : 1;
              if (maxChancesPerReceipt > 0 && calculatedChances > maxChancesPerReceipt) {
                calculatedChances = maxChancesPerReceipt;
              }
            } else {
              calculatedChances = 1;
            }
          } else if (minimumSpend <= 0) {
            calculatedChances = result.chancesEarned > 0 ? result.chancesEarned : 1;
          }
        } else {
          calculatedChances = 0;
        }
        result = result.copyWith(chancesEarned: calculatedChances);

        // Enrich extractedProducts with matched barcodes from catalog if missing or empty
        if (catalogBarcodeMap.isNotEmpty && result.extractedProducts.isNotEmpty) {
          final enrichedProducts = result.extractedProducts.map((item) {
            if (item.barcode.trim().isNotEmpty) return item;
            
            final itemNameLower = item.name.toLowerCase().trim();
            for (final entry in catalogBarcodeMap.entries) {
              final catName = entry.key.toLowerCase().trim();
              if (catName.isNotEmpty && (itemNameLower.contains(catName) || catName.contains(itemNameLower))) {
                return item.copyWith(barcode: entry.value);
              }
            }
            return item;
          }).toList();
          result = result.copyWith(extractedProducts: enrichedProducts);
        }

        // Branch matching fallback validation
        if (retailChainName.trim().isNotEmpty && !isAllBranches && allowedBranches.isNotEmpty) {
          if (!result.isBranchMatched) {
            final detected = result.branchDetected.trim().isNotEmpty ? result.branchDetected : "فرع غير معتمد";
            return result.copyWith(
              isValid: false,
              isBranchMatched: false,
              durationMs: durationMs,
              durationSeconds: durationSeconds,
              message: 'عذراً، الفاتورة صادرة من ($detected) بينما العرض سارٍ حصرياً في فروع: [${allowedBranches.join("، ")}].',
            );
          }
        }

        // Perform strict Dart-level Date validation if startDate and endDate are set
        if (startDate != null || endDate != null) {
          final rawDateStr = result.receiptDate.trim();
          if (rawDateStr.isNotEmpty) {
            DateTime? parsedDate = _parseReceiptDate(rawDateStr);
            if (parsedDate != null) {
              if (startDate != null && parsedDate.isBefore(startDate)) {
                final startStr = "${startDate.day}/${startDate.month}/${startDate.year}";
                return result.copyWith(
                  isValid: false,
                  durationMs: durationMs,
                  durationSeconds: durationSeconds,
                  message: 'تاريخ الشراء بالفاتورة ($rawDateStr) أقدم من تاريخ بداية الحملة ($startStr). الشراء غير مشمول بالعرض.',
                );
              }
              if (endDate != null && parsedDate.isAfter(endDate.add(const Duration(days: 1)))) {
                final endStr = "${endDate.day}/${endDate.month}/${endDate.year}";
                return result.copyWith(
                  isValid: false,
                  durationMs: durationMs,
                  durationSeconds: durationSeconds,
                  message: 'تاريخ الشراء بالفاتورة ($rawDateStr) متأخر عن تاريخ نهاية الحملة ($endStr). عذراً، انتهى العرض.',
                );
              }
            }
          }
        }

        return result;
      } else {
        throw Exception("تعذر قراءة بيانات الفاتورة من نموذج الذكاء الاصطناعي. يرجى إعادة المحاولة.");
      }
    } on GenerativeAIException catch (e) {
      stopwatch.stop();
      throw Exception("تعذر الاتصال بخدمة الذكاء الاصطناعي: ${e.message}");
    } catch (e) {
      stopwatch.stop();
      if (e is Exception) {
        rethrow;
      }
      throw Exception(e.toString());
    }
  }

  static Map<String, dynamic> _cleanAndParseJson(String raw) {
    var text = raw.trim();
    if (text.startsWith('```json')) {
      text = text.substring(7);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    text = text.trim();

    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      text = text.substring(firstBrace, lastBrace + 1);
    }

    try {
      return Map<String, dynamic>.from(jsonDecode(text));
    } catch (_) {
      final repaired = _attemptRepairJson(text);
      if (repaired != null) {
        return repaired;
      }
      return _extractFieldsViaRegex(raw);
    }
  }

  static Map<String, dynamic>? _attemptRepairJson(String text) {
    try {
      var sanitized = text.replaceAll(RegExp(r',\s*([\}\]])'), r'$1');
      int openBraces = 0;
      int openBrackets = 0;
      bool inString = false;
      bool escape = false;

      for (int i = 0; i < sanitized.length; i++) {
        final char = sanitized[i];
        if (escape) {
          escape = false;
          continue;
        }
        if (char == r'\') {
          escape = true;
          continue;
        }
        if (char == '"') {
          inString = !inString;
          continue;
        }
        if (!inString) {
          if (char == '{') openBraces++;
          if (char == '}') openBraces--;
          if (char == '[') openBrackets++;
          if (char == ']') openBrackets--;
        }
      }

      var buffer = StringBuffer(sanitized);
      if (inString) buffer.write('"');
      while (openBrackets > 0) {
        buffer.write(']');
        openBrackets--;
      }
      while (openBraces > 0) {
        buffer.write('}');
        openBraces--;
      }

      return Map<String, dynamic>.from(jsonDecode(buffer.toString()));
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _extractFieldsViaRegex(String text) {
    final isValidMatch = RegExp(r'"isValid"\s*:\s*(true|false)', caseSensitive: false).firstMatch(text);
    final receiptNumMatch = RegExp(r'"receiptNumber"\s*:\s*"([^"]*)"').firstMatch(text);
    final totalMatch = RegExp(r'"targetCompanyTotal"\s*:\s*([\d\.]+)').firstMatch(text);
    final dateMatch = RegExp(r'"receiptDate"\s*:\s*"([^"]*)"').firstMatch(text);
    final storeMatch = RegExp(r'"storeChainDetected"\s*:\s*"([^"]*)"').firstMatch(text);
    final branchMatch = RegExp(r'"branchDetected"\s*:\s*"([^"]*)"').firstMatch(text);
    final branchMatchedMatch = RegExp(r'"isBranchMatched"\s*:\s*(true|false)', caseSensitive: false).firstMatch(text);
    final messageMatch = RegExp(r'"message"\s*:\s*"([^"]*)"').firstMatch(text);
    final matchedRuleIdMatch = RegExp(r'"matchedRuleId"\s*:\s*"([^"]*)"').firstMatch(text);
    final matchedRuleTitleMatch = RegExp(r'"matchedRuleTitle"\s*:\s*"([^"]*)"').firstMatch(text);
    final matchedRewardValueMatch = RegExp(r'"matchedRewardValue"\s*:\s*"([^"]*)"').firstMatch(text);
    final matchedRewardAmountMatch = RegExp(r'"matchedRewardAmount"\s*:\s*([\d\.]+)').firstMatch(text);
    final matchedRewardTypeMatch = RegExp(r'"matchedRewardType"\s*:\s*"([^"]*)"').firstMatch(text);

    return {
      'isValid': isValidMatch?.group(1)?.toLowerCase() == 'true',
      'receiptNumber': receiptNumMatch?.group(1) ?? '',
      'targetCompanyTotal': double.tryParse(totalMatch?.group(1) ?? '') ?? 0.0,
      'receiptDate': dateMatch?.group(1) ?? '',
      'storeChainDetected': storeMatch?.group(1) ?? '',
      'branchDetected': branchMatch?.group(1) ?? '',
      'isBranchMatched': branchMatchedMatch?.group(1)?.toLowerCase() != 'false',
      'message': messageMatch?.group(1) ?? (isValidMatch?.group(1)?.toLowerCase() == 'true' ? 'تمت قراءة الفاتورة بنجاح' : 'الفاتورة غير مطابقة للشروط'),
      'matchedRuleId': matchedRuleIdMatch?.group(1) ?? '',
      'matchedRuleTitle': matchedRuleTitleMatch?.group(1) ?? '',
      'matchedRewardValue': matchedRewardValueMatch?.group(1) ?? '',
      'matchedRewardAmount': double.tryParse(matchedRewardAmountMatch?.group(1) ?? '') ?? 0.0,
      'matchedRewardType': matchedRewardTypeMatch?.group(1) ?? '',
      'extractedProducts': <Map<String, dynamic>>[],
      'unfulfilledConditions': <String>[],
    };
  }

  DateTime? _parseReceiptDate(String dateStr) {
    try {
      final clean = dateStr.replaceAll(RegExp(r'[^\d/\-]'), '');
      if (clean.contains('/')) {
        final parts = clean.split('/');
        if (parts.length >= 3) {
          int day = int.parse(parts[0]);
          int month = int.parse(parts[1]);
          int year = int.parse(parts[2]);
          if (year < 100) year += 2000;
          return DateTime(year, month, day);
        }
      } else if (clean.contains('-')) {
        final parts = clean.split('-');
        if (parts.length >= 3) {
          int year = int.parse(parts[0]);
          int month = int.parse(parts[1]);
          int day = int.parse(parts[2]);
          return DateTime(year, month, day);
        }
      }
    } catch (_) {}
    return null;
  }
}

/// Robust engine for resolving which promotional rule and gift/voucher is earned from receipt analysis.
class PromotionalRuleMatcher {
  /// Resolves the winning promotional rule for an analyzed receipt.
  /// 
  /// Priorities:
  /// 1. Direct matchedRuleId from AI analysis (if valid and found).
  /// 2. Direct matchedRuleTitle from AI analysis.
  /// 3. Direct matchedRewardValue from AI analysis.
  /// 4. Intelligent NLP tokenization and quantity-tiered matching on extracted products.
  /// 5. Single-rule campaign fallback (if the event only has 1 rule).
  /// 
  /// Returns `null` if no rule conditions are satisfied (preventing false awards).
  static PromotionalRuleItem? match({
    AiReceiptAnalysisResult? result,
    String matchedRuleId = '',
    String matchedRuleTitle = '',
    String matchedRewardValue = '',
    List<ExtractedProductItem> extractedProducts = const [],
    required List<PromotionalRuleItem> promotionalRules,
  }) {
    if (promotionalRules.isEmpty) return null;

    final effectiveRuleId = (result != null && result.matchedRuleId.isNotEmpty)
        ? result.matchedRuleId
        : matchedRuleId;
    final effectiveRuleTitle = (result != null && result.matchedRuleTitle.isNotEmpty)
        ? result.matchedRuleTitle
        : matchedRuleTitle;
    final effectiveRewardValue = (result != null && result.matchedRewardValue.isNotEmpty)
        ? result.matchedRewardValue
        : matchedRewardValue;
    final effectiveProducts = (result != null && result.extractedProducts.isNotEmpty)
        ? result.extractedProducts
        : extractedProducts;

    // 1. Direct ID match from Gemini
    if (effectiveRuleId.trim().isNotEmpty) {
      final cleanId = effectiveRuleId.trim().toLowerCase();
      final match = promotionalRules.where((r) => r.id.trim().toLowerCase() == cleanId).firstOrNull;
      if (match != null) return match;
    }

    // 2. Direct Title match from Gemini
    if (effectiveRuleTitle.trim().isNotEmpty) {
      final titleNorm = _normalize(effectiveRuleTitle);
      final match = promotionalRules.where((r) => _normalize(r.ruleTitle) == titleNorm).firstOrNull;
      if (match != null) return match;
    }

    // 3. Direct Reward Value match from Gemini
    if (effectiveRewardValue.trim().isNotEmpty) {
      final rewardNorm = _normalize(effectiveRewardValue);
      final match = promotionalRules.where((r) => _normalize(r.rewardValue) == rewardNorm).firstOrNull;
      if (match != null) return match;
    }

    // 4. Smart NLP token and quantity-tiered match on extractedProducts
    if (effectiveProducts.isNotEmpty) {
      final matchingRulesWithScores = <PromotionalRuleItem, int>{};

      for (final rule in promotionalRules) {
        final triggerTokens = _extractTokens(rule.triggerProduct);
        if (triggerTokens.isEmpty) continue;

        int totalMatchedQty = 0;
        int tokenMatches = 0;

        for (final p in effectiveProducts) {
          final pNorm = _normalize(p.name);
          bool productMatched = false;

          for (final token in triggerTokens) {
            if (token.length >= 2 && pNorm.contains(token)) {
              productMatched = true;
              tokenMatches++;
            }
          }

          if (productMatched) {
            totalMatchedQty += p.quantity > 0 ? p.quantity : 1;
          }
        }

        if (tokenMatches > 0 && totalMatchedQty >= rule.minQuantity) {
          // Weight minQuantity heavily so 2-pcs tier beats 1-pc tier
          final score = (rule.minQuantity * 100) + tokenMatches;
          matchingRulesWithScores[rule] = score;
        }
      }

      if (matchingRulesWithScores.isNotEmpty) {
        final sorted = matchingRulesWithScores.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return sorted.first.key;
      }
    }

    // 5. If only 1 rule exists in total in the campaign, fallback to it
    if (promotionalRules.length == 1) {
      return promotionalRules.first;
    }

    return null;
  }

  static String _normalize(String s) {
    var str = s.toLowerCase().trim();
    str = str.replaceAll(RegExp(r'[أإآ]'), 'ا');
    str = str.replaceAll('ى', 'ي');
    str = str.replaceAll('ة', 'ه');
    str = str.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ');
    return str.replaceAll(RegExp(r'\s+'), ' ');
  }

  static List<String> _extractTokens(String trigger) {
    final parts = trigger.split(RegExp(r'[,،/\+\n]|(\s+أو\s+)|(\s+or\s+)', caseSensitive: false));
    final tokens = <String>[];
    for (final part in parts) {
      final norm = _normalize(part);
      final words = norm.split(' ').where((w) {
        return w.length >= 2 &&
            w != 'شراء' &&
            w != 'عرض' &&
            w != 'من' &&
            w != 'قطعة' &&
            w != 'قطع' &&
            w != 'علبة' &&
            w != 'عبوة';
      }).toList();
      tokens.addAll(words);
    }
    return tokens.toSet().toList();
  }
}


