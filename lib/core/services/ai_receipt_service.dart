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
        final rulesListFormatted = promotionalRules.map((r) {
          final multText = r.allowMultipliers ? ' (تتضاعف الهدايا مع زيادة الكمية)' : '';
          return '• ${r.ruleTitle}: عند شراء ${r.minQuantity} من [${r.triggerProduct}] -> المكافأة المستحقة: [${r.rewardValue}]$multText';
        }).join('\n');

        promotionalRulesCondition = '''
- قواعد وهدايا المهرجان الخاصة (Promotional Rules):
$rulesListFormatted
المطلوب: تحقق من مطابقة أصناف الفاتورة والكميات مع هذه القواعد المحددة، واذكر في تقرير الفحص (message) تفاصيل الجوائز أو القسائم المستحقة بدقة.
''';
      }

      String branchSignaturesText = '';
      final branchesWithSignatures = registeredBranches
          .where((b) => b.receiptSignature != null && b.receiptSignature!.hasSignature)
          .toList();
      if (branchesWithSignatures.isNotEmpty) {
        final sigsList = branchesWithSignatures.map((b) {
          final s = b.receiptSignature!;
          return '  * فرع "${b.branchName}" (${b.retailChainName}): [Store ID: "${s.storeId}", كود: "${b.branchCode}", نسق الفاتورة/الباركود: "${s.receiptPattern}", نسق الـ POS: "${s.posNumberPattern}", الرقم الضريبي: "${s.taxNumber}", الهاتف/الخط الساخن: "${s.hotline}", كلمات الرأس: ${s.headerKeywords.join("/")}]';
        }).join('\n');
        branchSignaturesText = '''
- البصمات الهيكلية المعتمدة لنقاط البيع (Store POS Receipt Signatures):
$sigsList
استخدم هذه البصمات والأكواد لمطابقة الفرع والسلسلة بدقة قاطعة 100% حتى لو كان الشعار باهتاً أو الاسم مختصراً.
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
        finalPromptText = customPrompt
            .replaceAll('{TARGET_COMPANY}', targetCompany)
            .replaceAll('{MIN_SPEND}', minimumSpend.toString())
            .replaceAll('{REQUIRED_PRODUCTS}', requiredProducts.join(", "))
            .replaceAll('{RETAIL_CHAIN}', retailChainName)
            .replaceAll('{BRANCHES}', allowedBranches.join(", "));
        
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
        if (result.isValid && minimumSpend > 0 && result.targetCompanyTotal >= minimumSpend) {
          if (allowMultipleChances) {
            final computed = (result.targetCompanyTotal / minimumSpend).floor();
            calculatedChances = computed > 0 ? computed : 1;
            if (maxChancesPerReceipt > 0 && calculatedChances > maxChancesPerReceipt) {
              calculatedChances = maxChancesPerReceipt;
            }
          } else {
            calculatedChances = 1;
          }
        } else if (!result.isValid) {
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

    return {
      'isValid': isValidMatch?.group(1)?.toLowerCase() == 'true',
      'receiptNumber': receiptNumMatch?.group(1) ?? '',
      'targetCompanyTotal': double.tryParse(totalMatch?.group(1) ?? '') ?? 0.0,
      'receiptDate': dateMatch?.group(1) ?? '',
      'storeChainDetected': storeMatch?.group(1) ?? '',
      'branchDetected': branchMatch?.group(1) ?? '',
      'isBranchMatched': branchMatchedMatch?.group(1)?.toLowerCase() != 'false',
      'message': messageMatch?.group(1) ?? (isValidMatch?.group(1)?.toLowerCase() == 'true' ? 'تمت قراءة الفاتورة بنجاح' : 'الفاتورة غير مطابقة للشروط'),
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

