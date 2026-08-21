import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';
import '../config/ai_config.dart';
import '../utils/arabic_numbers_utils.dart';

final aiReceiptServiceProvider = Provider<AiReceiptService>((ref) {
  return AiReceiptService();
});

class ExtractedProductItem {
  final String name;
  final double price;
  final int quantity;
  final bool isTargetCompany;
  final String barcode;
  final double? originalPrice;
  final double discountAmount;
  final double discountPercent;

  ExtractedProductItem({
    required this.name,
    required this.price,
    required this.quantity,
    required this.isTargetCompany,
    this.barcode = '',
    this.originalPrice,
    this.discountAmount = 0.0,
    this.discountPercent = 0.0,
  });

  double get totalPrice => price * quantity;
  bool get hasDiscount => discountAmount > 0 || discountPercent > 0 || (originalPrice != null && originalPrice! > price);

  factory ExtractedProductItem.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    int quantity = (json['quantity'] as num?)?.toInt() ?? 1;
    if (quantity <= 0) quantity = 1;

    double rawPrice = (json['price'] as num?)?.toDouble() ?? 0.0;
    double? rawOriginalPrice = (json['originalPrice'] as num?)?.toDouble();
    double rawDiscount = (json['discountAmount'] as num?)?.toDouble() ?? 0.0;
    double rawDiscountPercent = (json['discountPercent'] as num?)?.toDouble() ?? 0.0;
    final double? rawTotalLine = (json['totalPrice'] as num?)?.toDouble() ?? (json['totalLinePrice'] as num?)?.toDouble();

    // Auto-heal / enforce per-unit price:
    if (quantity > 1) {
      // 1. If rawPrice & rawOriginalPrice were both returned as total line amounts (e.g. 198 and 230 for 2 units)
      if (rawOriginalPrice != null && rawOriginalPrice > 0) {
        if ((rawPrice + rawDiscount - rawOriginalPrice).abs() < 1.5 && rawPrice > 50) {
          rawPrice = rawPrice / quantity;
          rawOriginalPrice = rawOriginalPrice / quantity;
          if (rawDiscount > 0) rawDiscount = rawDiscount / quantity;
        } else if (rawPrice >= rawOriginalPrice * 1.5) {
          rawPrice = rawPrice / quantity;
        } else if (rawOriginalPrice >= 1.8 * rawPrice && rawOriginalPrice > 50) {
          rawOriginalPrice = rawOriginalPrice / quantity;
        }
      } else if (rawTotalLine != null && rawTotalLine > 0 && (rawPrice == rawTotalLine || rawPrice >= rawTotalLine * 0.95)) {
        rawPrice = rawPrice / quantity;
      }

      // 2. If discountAmount was returned as total line discount (e.g. 32 EGP for 2 items)
      if (rawDiscount >= rawPrice && rawDiscount > 0) {
        rawDiscount = rawDiscount / quantity;
      }
    }

    if (rawOriginalPrice != null && rawOriginalPrice <= 0) {
      rawOriginalPrice = null;
    }

    return ExtractedProductItem(
      name: name,
      price: rawPrice,
      quantity: quantity,
      isTargetCompany: json['isTargetCompany'] ?? false,
      barcode: json['barcode']?.toString().trim() ?? '',
      originalPrice: rawOriginalPrice,
      discountAmount: rawDiscount,
      discountPercent: rawDiscountPercent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'price': price,
      'quantity': quantity,
      'isTargetCompany': isTargetCompany,
      'barcode': barcode,
      if (originalPrice != null) 'originalPrice': originalPrice,
      'discountAmount': discountAmount,
      'discountPercent': discountPercent,
      'totalPrice': totalPrice,
    };
  }

  ExtractedProductItem copyWith({
    String? name,
    double? price,
    int? quantity,
    bool? isTargetCompany,
    String? barcode,
    double? originalPrice,
    double? discountAmount,
    double? discountPercent,
  }) {
    return ExtractedProductItem(
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      isTargetCompany: isTargetCompany ?? this.isTargetCompany,
      barcode: barcode ?? this.barcode,
      originalPrice: originalPrice ?? this.originalPrice,
      discountAmount: discountAmount ?? this.discountAmount,
      discountPercent: discountPercent ?? this.discountPercent,
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
  final bool isHandwritten;
  final bool isThermalPosReceipt;
  final bool isTampered;
  final bool isScreenCapture;
  final int fraudRiskScore;
  final List<String> fraudReasons;

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
    this.isHandwritten = false,
    this.isThermalPosReceipt = true,
    this.isTampered = false,
    this.isScreenCapture = false,
    this.fraudRiskScore = 0,
    this.fraudReasons = const [],
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

    final bool isHandwritten = json['isHandwritten'] == true;
    final bool isThermalPosReceipt = json['isThermalPosReceipt'] ?? (!isHandwritten);
    final bool isTampered = json['isTampered'] == true;
    final bool isScreenCapture = json['isScreenCapture'] == true;
    final int fraudRiskScore = (json['fraudRiskScore'] as num?)?.toInt() ?? (isHandwritten ? 100 : 0);
    
    final fraudReasonsRaw = json['fraudReasons'];
    List<String> fraudReasonsList = [];
    if (fraudReasonsRaw is List) {
      fraudReasonsList = fraudReasonsRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    if (isHandwritten && !fraudReasonsList.any((r) => r.contains('يدوياً') || r.contains('خط اليد'))) {
      fraudReasonsList.add('فاتورة محررة يدوياً وغير مطبوعة إلكترونياً من الكاشير');
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
      isHandwritten: isHandwritten,
      isThermalPosReceipt: isThermalPosReceipt,
      isTampered: isTampered,
      isScreenCapture: isScreenCapture,
      fraudRiskScore: fraudRiskScore,
      fraudReasons: fraudReasonsList,
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
      'isHandwritten': isHandwritten,
      'isThermalPosReceipt': isThermalPosReceipt,
      'isTampered': isTampered,
      'isScreenCapture': isScreenCapture,
      'fraudRiskScore': fraudRiskScore,
      'fraudReasons': fraudReasons,
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
    bool? isHandwritten,
    bool? isThermalPosReceipt,
    bool? isTampered,
    bool? isScreenCapture,
    int? fraudRiskScore,
    List<String>? fraudReasons,
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
      isHandwritten: isHandwritten ?? this.isHandwritten,
      isThermalPosReceipt: isThermalPosReceipt ?? this.isThermalPosReceipt,
      isTampered: isTampered ?? this.isTampered,
      isScreenCapture: isScreenCapture ?? this.isScreenCapture,
      fraudRiskScore: fraudRiskScore ?? this.fraudRiskScore,
      fraudReasons: fraudReasons ?? this.fraudReasons,
    );
  }
}

class AiReceiptService {
  late final GenerativeModel _model;
  late final GenerativeModel _fallbackModel1;
  late final GenerativeModel _fallbackModel2;
  final String modelName;

  AiReceiptService({this.modelName = 'gemini-3.7-flash'}) {
    _model = _createModel(modelName);
    _fallbackModel1 = _createModel('gemini-3.6-flash');
    _fallbackModel2 = _createModel('gemini-3.6-flash');
  }

  static GenerativeModel _createModel(String name) {
    return GenerativeModel(
      model: name,
      apiKey: AiConfig.geminiApiKey,
      systemInstruction: Content.system(
        'أنت مدقق مالي وأمني فائق السرعة والدقة والصرامة في فحص وتدقيق فواتير السوبر ماركت وكشف التزوير لعروض الشركات الاستهلاكية (FMCG). '
        'مهمتك فحص صور الفواتير فورياً واستخراج البيانات الأساسية: اسم السلسلة، الفرع، رقم الفاتورة، تاريخ الشراء، '
        'وحساب إجمالي المشتريات لمنتجات الشركة الراعية فقط، وكشف أي محاولة تزوير أو كتابة يدوية أو شطب أو تصوير شاشات بدقة وبصيغة JSON.\n\n'
        '🛑 قواعد مكافحة التزوير والرفض الأمني القاطع (Zero-Tolerance Anti-Fraud Policy):\n'
        '1. يُمنع منعاً باتاً قبول أي فاتورة أو ورقة محررة أو مكتوبة بخط اليد (Handwritten Receipt / Paper Draft / Manual Note) بقلم جاف أو حبر أو رصاص.\n'
        '2. الفواتير المقبولة حصراً هي بونات الكاشير الإلكترونية المطبوعة آلياً عبر طابعات نقاط البيع الرسمية (Printed Thermal / Electronic POS Receipts).\n'
        '3. إذا كانت الفاتورة مكتوبة باليد، يجب تعيين: isHandwritten = true، isThermalPosReceipt = false، isValid = false، وإضافة "الفاتورة محررة يدوياً وغير مطبوعة إلكترونياً من الكاشير" إلى fraudReasons وقائمة unfulfilledConditions.\n'
        '4. إذا وجد أي شطب أو تعديل يدوي في أرقام الفاتورة، عيّن: isTampered = true، isValid = false.\n'
        '5. إذا كانت الصورة ملتقطة لشاشة هاتف أو حاسوب، عيّن: isScreenCapture = true، isValid = false.',
      ),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.1,
        maxOutputTokens: 4096,
        responseSchema: Schema.object(
          properties: {
            'isValid': Schema.boolean(
              description:
                  'True if this is a genuine printed supermarket POS receipt containing target company products and meeting all rules. False if invalid, fraudulent, or handwritten.',
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
            'isHandwritten': Schema.boolean(
              description:
                  'True ONLY if the receipt items/prices themselves are manually handwritten on a notebook/paper draft. Must be false for printed electronic thermal/POS cash register receipts even if there are promoter notes, endorsements (e.g. تم تسليم الهدية), or signatures on the margins.',
            ),
            'isThermalPosReceipt': Schema.boolean(
              description: 'True ONLY if this is a genuine printed electronic POS / thermal cash register receipt.',
            ),
            'isTampered': Schema.boolean(
              description:
                  'True ONLY if there is fraudulent alteration, forged/scratched-out printed numbers or prices to alter purchase values. Normal promoter notes, signatures, or endorsement checkmarks in margins do NOT count as tampering.',
            ),
            'isScreenCapture': Schema.boolean(
              description: 'True if this is a photo of a computer or phone display screen rather than a physical paper receipt.',
            ),
            'fraudRiskScore': Schema.integer(
              description: 'Fraud probability score from 0 (genuine printed receipt) to 100 (blatantly forged/handwritten).',
            ),
            'fraudReasons': Schema.array(
              description: 'List of fraud or suspicious triggers detected (e.g. فاتورة مكتوبة بخط اليد, تلاعب وشطب وتعديل بأرقام الأصناف, تصوير شاشة إلكترونية). Empty if clean.',
              items: Schema.string(),
            ),
            'extractedProducts': Schema.array(
              description: 'List of all individual items/products found on the receipt with names, strictly single unit prices, quantities, and matched barcodes.',
              items: Schema.object(
                properties: {
                  'name': Schema.string(description: 'Product name as printed on receipt.'),
                  'price': Schema.number(description: 'Net selling unit price per single piece in EGP/AED (MUST be divided by quantity if line total is shown).'),
                  'quantity': Schema.integer(description: 'Quantity purchased (e.g. 1, 2, 3).'),
                  'isTargetCompany': Schema.boolean(
                    description: 'True if this product belongs to the target company being promoted.',
                  ),
                  'barcode': Schema.string(
                    description: 'The product barcode or item code if detected or matched from company catalog. Return empty string if not found.',
                  ),
                  'originalPrice': Schema.number(
                    description: 'Original gross unit price per single piece before discount (e.g. 115.0). Null or 0 if not discounted.',
                  ),
                  'discountAmount': Schema.number(
                    description: 'Monetary discount amount per single piece (e.g. 16.0 for 32 EGP discount on 2 pieces). 0 if no discount.',
                  ),
                  'discountPercent': Schema.number(
                    description: 'Percentage discount if printed on line item (e.g. 15 for 15%). 0 if no discount.',
                  ),
                  'totalLinePrice': Schema.number(
                    description: 'Total line amount paid for this item in receipt (e.g. 198.0 for 2 pieces).',
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
            'isHandwritten',
            'isThermalPosReceipt',
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
    String multiplierBasis = 'both',
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

⚠️ تعليمات مطابقة القواعد الترويجية وحساب المضاعفات (Promotional Rules & Multiplier Instructions):
1. افحص بدقة أسماء الأصناف في الفاتورة واجمع إجمالي الكميات المشتراة من المنتج المشروط (Trigger Product Total Quantity).
2. في حال وجود أكثر من قاعدة لنفس المنتج بمستويات كميات مختلفة (مثل: شراء 1 اسبراي ريكسونا -> 50 ج.م، وشراء 2 اسبراي ريكسونا -> 125 ج.م)، يجب عليك اختيار القاعدة ذات الكمية المشروطة الأعلى التي حققها العميل (مثال: إذا اشترى 2 أو أكثر، اختر قاعدة الـ 125 ج.م).
3. [مضاعفة الجوائز والفرص]: إذا كانت القاعدة تتيح المضاعفة (تتضاعف الهدايا مع زيادة الكمية) أو كان العرض يتيح المضاعفة، وكان العميل قد اشترى مضاعفات الكمية المشروطة (مثال: اشترى 4 قطع أكس اسبراي والشرط شراء 2 قطعة للحصول على فواتشر 125 ج.م):
   - احسب عدد مرات تكرار العرض (4 ÷ 2 = 2 مرات).
   - قم بتعيين حقل (chancesEarned) بعدد مرات العرض المستحقة (مثلاً 2).
   - قم بحساب إجمالي قيمة الفواتشر/المكافأة بضرب القيمة في عدد المرات في حقل (matchedRewardAmount) (مثلاً 125 × 2 = 250.0).
   - قم بكتابة الجائزة المستحقة موضحة بالمضاعف في حقل (matchedRewardValue) (مثلاً "2 × فواتشر بقيمة 125 جنيه (إجمالي 250 جنيه)").
4. قم بتعبئة حقل (matchedRuleId) بمعرف القاعدة المطابقة (مثل "rule_4" أو "rule_1").
5. قم بتعبئة حقل (matchedRuleTitle) بعنوان القاعدة المطابقة.
6. قم بتعبئة حقل (matchedRewardType) بنوع المكافأة ("voucher" أو "free_product").
7. إذا لم تنطبق أي من هذه القواعد الخاصة، اترك حقل (matchedRuleId) فارغاً "".
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

⚠️ تعليمات وقواعد أولوية مطابقة الفرع المعتمد (Mandatory Branch Matching Rules):
1. [أولوية مطلقة رقم 1]: طابق كود المتجر ورقم الـ POS المطبوع على الفاتورة (مثل "Store: 224" أو "Store: 243" أو "POS: 224" أو رقم المتجر ضمن كود المعاملة/الباركود مثل "93/3/224/...") مع دليل أكواد وبصمات الفروع المعتمدة أعلاه.
2. [تجاهل نصوص الإعلانات والافتتاحات في التذييل]: لا تستخدم أبداً العبارات الدعائية أو الإعلانات المطبوعة في تذييل الفاتورة أو أسفلها (مثل: "تم افتتاح فرع مدينة بدر" أو "زوروا فرعنا الجديد") لتحديد الفرع؛ فهذه إعلانات تسويقية عامة لجميع الفروع وليست الفرع الذي أصدر الفاتورة. الفرع الحقيقي المصدر هو المكتوب في رأس الفاتورة والمطابق لرقم المتجر (Store Code / POS).
3. [النتيجة]: إذا تطابق كود المتجر مع أي فرع من الفروع المعتمدة في القائمة (مثال: Store 224 يطابق فرع عجمي ستار المعتمد)، فيجب تعيين (isBranchMatched = true) وتعيين (branchDetected = اسم الفرع المعتمد المطابق للكود).
''';
      }

      String branchCondition = '';
      if (retailChainName.trim().isNotEmpty) {
        if (!isAllBranches && allowedBranches.isNotEmpty) {
          branchCondition = '''
- السلسلة المعتمدة للحملة: "$retailChainName".
- الفروع المعتمدة حصراً لهذا العرض: [${allowedBranches.join("، ")}].
- المطلوب للفرع: افحص رأس الفاتورة وكود المتجر (Store ID / POS) بدقة واستخرج اسم السلسلة في (storeChainDetected) واسم الفرع أو عنوانه أو رقمه في (branchDetected). إذا كانت الفاتورة صادرة من أحد الفروع المعتمدة المذكورة أعلاه (أو يحمل كود المتجر لفرع معتمد)، حدد (isBranchMatched = true). إذا كانت من فرع آخر أو سلسلة أخرى، حدد (isBranchMatched = false) و (isValid = false) واكتب في (message) أن الفاتورة صادرة من فرع غير مشمول بالعرض.
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
      if (allowMultipleChances) {
        final maxCapText = maxChancesPerReceipt > 0 ? ' بحد أقصى $maxChancesPerReceipt بالفاتورة الواحدة' : '';
        if (multiplierBasis == 'quantity') {
          chancesCondition = '''
- مضاعفة الجوائز والفرص بناءً على كميات المنتجات: تتضاعف الجوائز والفرص طردياً مع تكرار ومضاعفة كمية المنتج المشروط بالفاتورة (مثال: شراء 1 قطعة = 1 هدية/فرصة، شراء 2 قطعة = 2 هدية/فرصتان، شراء 3 قطع = 3 هدايا/فرص)$maxCapText.
''';
        } else if (multiplierBasis == 'spend') {
          chancesCondition = '''
- مضاعفة فرص السحب واللعب بناءً على المبلغ: الحد الأدنى المطلوب هو $minimumSpend ج.م. كل مضاعف لهذا المبلغ من منتجات الشركة يمنح العميل فرصة إضافية$maxCapText.
''';
        } else {
          chancesCondition = '''
- مضاعفة الجوائز والفرص: تتضاعف الجوائز الفورية بمضاعفة كميات الأصناف المشروطة، وتتضاعف فرص السحب بمضاعفة قيمة الشراء ($minimumSpend ج.م)$maxCapText.
''';
        }
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

🛑 تعليمات مكافحة التزوير والرفض الأمني (Anti-Fraud & Genuine Receipt Policy):
- [بون الكاشير الإلكتروني]: الفواتير المقبولة فقط (isValid = true) هي بونات الكاشير الحرارية أو الإلكترونية المطبوعة آلياً من أنظمة ونقاط البيع المعتمدة (Thermal POS Receipts).
- [ملاحظات وهوامش البروموتر/الكاشير]: إذا كان أصل الفاتورة بون كاشير مطبوع إلكترونياً، وتوجد عليه كتابة يدوية في الهوامش أو الرأس مثل "تم تسليم الهدية" أو توقيع أو علامة استلام أو رقم تليفون أو علامات صح، فهذا بون كاشير أصلي معتمد وسليم (isThermalPosReceipt = true و isHandwritten = false و isTampered = false) ويجب قبوله.
- [كشف الفواتير المحررة يدوياً]: إذا كانت الفاتورة نفسها مسودة أو محررة بالكامل في دفتر يدوي وبنودها وأسعارها مكتوبة باليد، عيّن isHandwritten = true و isThermalPosReceipt = false و isValid = false واكتب رسالة رفض واضحة: "عذراً، تم رفض الفاتورة لأنها محررة بخط اليد. العرض يشترط بون كاشير مطبوع إلكترونياً من ماكينة السوبرماركت."
- [كشف الشطب والتلاعب في الأرقام]: إذا وجد شطب أو تلاعب وتعديل يدوي في أرقام وأسعار الأصناف المطبوعة لتغيير قيمتها، عيّن isTampered = true و isValid = false.
- [كشف تصوير الشاشات]: إذا كانت الصورة ملتقطة لشاشة هاتف أو حاسوب، عيّن isScreenCapture = true و isValid = false.

⚠️ تعليمات استخراج أسعار الأصناف والكميات والخصومات بدقة (Strict Unit Price & Discount Rules):
- يجب أن يحتوي حقل (price) دائماً على سعر بيع القطعة الواحدة فقط (Unit Price).
- إذا اشترى العميل كمية (quantity = 2 أو أكثر)، وكان المطبوع في الفاتورة هو إجمالي السطر (مثل 2 × 115 = 230 أو 198 بعد الخصم)، فيجب وضع سعر القطعة الصافي في (price) = 99.0 ج.م، وسعر القطعة الأصلي في (originalPrice) = 115.0 ج.م، وقيمة الخصم للقطعة الواحدة في (discountAmount) = 16.0 ج.م، وإجمالي السطر في (totalLinePrice) = 198.0 ج.م.
- إياك أن تضع إجمالي السطر كسعر للقطعة في حقل price عند وجود كمية أكبر من 1!

تأكد من إرجاع النتيجة بصيغة JSON المحتوي على الحقول المفروضة:
isValid (boolean), receiptNumber (string), targetCompanyTotal (number), receiptDate (string), storeChainDetected (string), branchDetected (string), isBranchMatched (boolean), isHandwritten (boolean), isThermalPosReceipt (boolean), isTampered (boolean), isScreenCapture (boolean), chancesEarned (integer), message (string).
''';
      } else {
        finalPromptText = '''
        أنت مساعد ذكي ومدقق مالي وأمني فائق الدقة متخصص في فحص وتدقيق فواتير السوبر ماركت وكشف التزوير لعروض "$targetCompany".
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
        
        🛑 تعليمات مكافحة التزوير والرفض الأمني (Anti-Fraud & Genuine Receipt Policy):
        - [بون الكاشير الإلكتروني]: الفواتير المقبولة فقط (isValid = true) هي بونات الكاشير الحرارية أو الإلكترونية المطبوعة آلياً من أنظمة ونقاط البيع المعتمدة (Thermal POS Receipts).
        - [ملاحظات وهوامش البروموتر/الكاشير]: إذا كان أصل الفاتورة بون كاشير مطبوع إلكترونياً، وتوجد عليه كتابة يدوية في الهوامش أو الرأس مثل "تم تسليم الهدية" أو توقيع أو علامة استلام أو رقم تليفون أو علامات صح، فهذا بون كاشير أصلي معتمد وسليم (isThermalPosReceipt = true و isHandwritten = false و isTampered = false) ويجب قبوله.
        - [كشف الفواتير المحررة يدوياً]: إذا كانت الفاتورة نفسها مسودة أو محررة بالكامل في دفتر يدوي وبنودها وأسعارها مكتوبة باليد، عيّن isHandwritten = true و isThermalPosReceipt = false و isValid = false واكتب رسالة رفض واضحة: "عذراً، تم رفض الفاتورة لأنها محررة بخط اليد. العرض يشترط بون كاشير مطبوع إلكترونياً من ماكينة السوبرماركت."
        - [كشف الشطب والتلاعب في الأرقام]: إذا وجد شطب أو تلاعب وتعديل يدوي في أرقام وأسعار الأصناف المطبوعة لتغيير قيمتها، عيّن isTampered = true و isValid = false.
        - [كشف تصوير الشاشات]: إذا كانت الصورة ملتقطة لشاشة هاتف أو حاسوب، عيّن isScreenCapture = true و isValid = false.
        
        ⚠️ تعليمات استخراج أسعار الأصناف والكميات والخصومات بدقة (Strict Unit Price & Discount Rules):
        - يجب أن يحتوي حقل (price) دائماً على سعر بيع القطعة الواحدة فقط (Unit Price).
        - إذا اشترى العميل كمية (quantity = 2 أو أكثر)، وكان المطبوع في الفاتورة هو إجمالي السطر (مثل 2 × 115 = 230 أو 198 بعد الخصم)، فيجب:
          * وضع سعر القطعة الواحدة الصافي في (price) = 99.0 ج.م (وليس 198).
          * وضع سعر القطعة الأصلي قبل الخصم في (originalPrice) = 115.0 ج.م (وليس 230).
          * وضع قيمة الخصم للقطعة الواحدة في (discountAmount) = 16.0 ج.م (وليس 32).
          * وضع إجمالي السطر المدفوع في (totalLinePrice) = 198.0 ج.م.
        - إياك أن تضع إجمالي السطر كسعر للقطعة في حقل price عند وجود كمية أكبر من 1!
        
        شروط الموافقة (isValid = true):
        - يجب أن تكون الصورة لبون كاشير إلكتروني مطبوع أصلي وحقيقي ومقروء وغير مكتوب باليد (isThermalPosReceipt = true و isHandwritten = false).
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
        ]).timeout(const Duration(seconds: 30));
      } catch (e1) {
        try {
          response = await _fallbackModel1.generateContent([
            Content.multi([prompt, imagePart]),
          ]).timeout(const Duration(seconds: 30));
        } catch (e2) {
          response = await _fallbackModel2.generateContent([
            Content.multi([prompt, imagePart]),
          ]).timeout(const Duration(seconds: 30));
        }
      }

      stopwatch.stop();
      final int durationMs = stopwatch.elapsedMilliseconds;
      final double durationSeconds = durationMs / 1000.0;

      if (response.text != null && response.text!.trim().isNotEmpty) {
        final Map<String, dynamic> jsonMap = _cleanAndParseJson(response.text!);
        var result = AiReceiptAnalysisResult.fromJson(jsonMap, durationMs: durationMs);

        // 🛑 Strict Dart Anti-Fraud Gatekeeper
        if (result.isHandwritten || !result.isThermalPosReceipt || result.isTampered || result.isScreenCapture) {
          final List<String> reasons = List<String>.from(result.unfulfilledConditions);
          String fraudMsg = '';
          if (result.isHandwritten) {
            fraudMsg = 'عذراً، تم رفض الفاتورة لأنها محررة بخط اليد. العرض يشترط حصراً بون كاشير مطبوع إلكترونياً من ماكينة السوبرماركت.';
            if (!reasons.contains('فاتورة محررة يدوياً وغير مطبوعة إلكترونياً من الكاشير')) {
              reasons.insert(0, 'فاتورة محررة يدوياً وغير مطبوعة إلكترونياً من الكاشير');
            }
          } else if (result.isTampered) {
            fraudMsg = 'عذراً، تم رفض الفاتورة لوجود اشتباه في تلاعب أو شطب وتعديل يدوي في الأرقام والأسعار.';
            if (!reasons.contains('اشتباه في تلاعب أو تعديل يدوي للأرقام')) {
              reasons.insert(0, 'اشتباه في تلاعب أو تعديل يدوي للأرقام');
            }
          } else if (result.isScreenCapture) {
            fraudMsg = 'عذراً، تم رفض الصورة لأنها ملتقطة من شاشة إلكترونية. يرجى تصوير أصل الفاتورة الورقية المطبوعة مباشرة.';
            if (!reasons.contains('صورة ملتقطة من شاشة إلكترونية')) {
              reasons.insert(0, 'صورة ملتقطة من شاشة إلكترونية');
            }
          } else if (!result.isThermalPosReceipt) {
            fraudMsg = 'عذراً، المستند المرفق ليس بون كاشير إلكتروني مطبوع معتمد.';
            if (!reasons.contains('المستند المرفق ليس بون كاشير إلكتروني معتمد')) {
              reasons.insert(0, 'المستند المرفق ليس بون كاشير إلكتروني معتمد');
            }
          }

          result = result.copyWith(
            isValid: false,
            chancesEarned: 0,
            message: fraudMsg.isNotEmpty ? fraudMsg : result.message,
            unfulfilledConditions: reasons,
          );
        }

        // Calculate / enforce chances & rewards earned based on quantity and spend multipliers
        int calculatedChances = result.chancesEarned;
        if (result.isValid) {
          int spendChances = 1;
          if (minimumSpend > 0 && result.targetCompanyTotal >= minimumSpend) {
            if (allowMultipleChances && (multiplierBasis == 'spend' || multiplierBasis == 'both')) {
              final computed = (result.targetCompanyTotal / minimumSpend).floor();
              spendChances = computed > 0 ? computed : 1;
              if (maxChancesPerReceipt > 0 && spendChances > maxChancesPerReceipt) {
                spendChances = maxChancesPerReceipt;
              }
            }
          }

          int quantityMultiplier = 1;
          if (allowMultipleChances && (multiplierBasis == 'quantity' || multiplierBasis == 'both')) {
            if (promotionalRules.isNotEmpty) {
              final matchedRule = promotionalRules.where((r) => r.id == result.matchedRuleId).firstOrNull;
              if (matchedRule != null && matchedRule.allowMultipliers) {
                final triggerTokens = PromotionalRuleMatcher._extractTokens(matchedRule.triggerProduct);
                int totalMatchedQty = 0;
                for (final p in result.extractedProducts) {
                  final pNorm = PromotionalRuleMatcher._normalize(p.name);
                  bool matches = false;
                  for (final token in triggerTokens) {
                    if (token.length >= 2 && pNorm.contains(token)) {
                      matches = true;
                      break;
                    }
                  }
                  if (matches || (triggerTokens.isEmpty && p.isTargetCompany)) {
                    totalMatchedQty += p.quantity > 0 ? p.quantity : 1;
                  }
                }
                if (totalMatchedQty > 0) {
                  final minQty = matchedRule.minQuantity > 0 ? matchedRule.minQuantity : 1;
                  final computed = (totalMatchedQty / minQty).floor();
                  quantityMultiplier = computed > 0 ? computed : 1;
                  if (maxChancesPerReceipt > 0 && quantityMultiplier > maxChancesPerReceipt) {
                    quantityMultiplier = maxChancesPerReceipt;
                  }
                }
              } else if (result.extractedProducts.isNotEmpty) {
                final targetItems = result.extractedProducts.where((p) => p.isTargetCompany).toList();
                final totalTargetQty = targetItems.fold<int>(0, (sum, p) => sum + (p.quantity > 0 ? p.quantity : 1));
                if (totalTargetQty > 1) {
                  quantityMultiplier = totalTargetQty;
                  if (maxChancesPerReceipt > 0 && quantityMultiplier > maxChancesPerReceipt) {
                    quantityMultiplier = maxChancesPerReceipt;
                  }
                }
              }
            } else if (result.extractedProducts.isNotEmpty) {
              final targetItems = result.extractedProducts.where((p) => p.isTargetCompany).toList();
              final totalTargetQty = targetItems.fold<int>(0, (sum, p) => sum + (p.quantity > 0 ? p.quantity : 1));
              if (totalTargetQty > 1) {
                quantityMultiplier = totalTargetQty;
                if (maxChancesPerReceipt > 0 && quantityMultiplier > maxChancesPerReceipt) {
                  quantityMultiplier = maxChancesPerReceipt;
                }
              }
            }
          }

          if (promotionalRules.isNotEmpty && result.matchedRuleId.isNotEmpty) {
            calculatedChances = quantityMultiplier;
          } else if (multiplierBasis == 'quantity') {
            calculatedChances = quantityMultiplier;
          } else if (multiplierBasis == 'spend') {
            calculatedChances = spendChances;
          } else {
            calculatedChances = math.max(quantityMultiplier, spendChances);
          }

          if (calculatedChances <= 0) {
            calculatedChances = result.chancesEarned > 0 ? result.chancesEarned : 1;
          }
          if (maxChancesPerReceipt > 0 && calculatedChances > maxChancesPerReceipt) {
            calculatedChances = maxChancesPerReceipt;
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

        // Deterministic POS & Store Code Reconciler in Dart
        if (registeredBranches.isNotEmpty) {
          final combinedReceiptText = '${result.receiptNumber} ${result.branchDetected} ${result.message} ${result.storeChainDetected}'.toEnglishDigits();

          BranchModel? matchedBranchByCode;

          for (final branch in registeredBranches) {
            final storeId = (branch.receiptSignature?.storeId ?? '').trim().toEnglishDigits();
            final branchCode = branch.branchCode.trim().toEnglishDigits();

            bool matches = false;

            if (storeId.isNotEmpty && storeId != '0') {
              final storeRegex = RegExp(
                r'(?:Store|المتجر|فرع|POS|Pos|pos)[\s:]*' + RegExp.escape(storeId) + r'\b|' +
                r'[\/\-_]' + RegExp.escape(storeId) + r'[\/\-_]',
                caseSensitive: false,
              );
              if (storeRegex.hasMatch(combinedReceiptText) || combinedReceiptText.contains('/$storeId/')) {
                matches = true;
              }
            }

            if (!matches && branchCode.isNotEmpty && branchCode != '0' && branchCode != 'DEF') {
              final codeRegex = RegExp(
                r'(?:Store|كود|فرع|POS|Pos|pos)[\s:]*' + RegExp.escape(branchCode) + r'\b|' +
                r'[\/\-_]' + RegExp.escape(branchCode) + r'[\/\-_]',
                caseSensitive: false,
              );
              if (codeRegex.hasMatch(combinedReceiptText) || combinedReceiptText.contains('/$branchCode/')) {
                matches = true;
              }
            }

            if (matches) {
              matchedBranchByCode = branch;
              break;
            }
          }

          if (matchedBranchByCode != null) {
            final isAllowed = isAllBranches || allowedBranches.isEmpty || allowedBranches.any((ab) {
              final cleanAb = ab.trim().toLowerCase();
              final cleanBName = matchedBranchByCode!.branchName.trim().toLowerCase();
              final cleanCity = matchedBranchByCode.city.trim().toLowerCase();
              return cleanAb.contains(cleanBName) || cleanBName.contains(cleanAb) || (cleanCity.isNotEmpty && cleanAb.contains(cleanCity));
            });

            if (isAllowed) {
              final fixedBranchName = matchedBranchByCode.branchName;
              final prevBranchName = result.branchDetected;
              final wasBranchFailure = !result.isBranchMatched;

              result = result.copyWith(
                isBranchMatched: true,
                branchDetected: fixedBranchName,
                storeChainDetected: matchedBranchByCode.retailChainName.isNotEmpty ? matchedBranchByCode.retailChainName : result.storeChainDetected,
                isValid: wasBranchFailure
                    ? (result.targetCompanyTotal >= (minimumSpend > 0 ? minimumSpend : 0) && (promotionalRules.isEmpty || result.extractedProducts.isNotEmpty || result.matchedRuleId.isNotEmpty))
                    : result.isValid,
                message: wasBranchFailure
                    ? (result.message.contains('فرع') ? 'تم التحقق من الفاتورة ومطابقة الفرع بنجاح بناءً على كود المتجر المعتمد ($fixedBranchName).' : result.message)
                    : (prevBranchName.isNotEmpty ? result.message.replaceAll(prevBranchName, fixedBranchName) : result.message),
              );
            }
          }
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
        int totalMatchedQty = 0;
        int matchedItemCount = 0;

        for (final p in effectiveProducts) {
          if (_matchesProduct(p, rule.triggerProduct)) {
            totalMatchedQty += p.quantity > 0 ? p.quantity : 1;
            matchedItemCount++;
          }
        }

        if (matchedItemCount > 0 && totalMatchedQty >= rule.minQuantity) {
          // Weight minQuantity heavily so 2-pcs tier beats 1-pc tier
          final score = (rule.minQuantity * 100) + matchedItemCount;
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

  /// Evaluates the promotional rule, and deterministically calculates the quantity multiplier
  /// and total voucher monetary value when buying multiples of the trigger products.
  static MatchedPromotionalRuleResult? matchWithMultiplier({
    AiReceiptAnalysisResult? result,
    String matchedRuleId = '',
    String matchedRuleTitle = '',
    String matchedRewardValue = '',
    List<ExtractedProductItem> extractedProducts = const [],
    required List<PromotionalRuleItem> promotionalRules,
    bool allowCampaignMultipliers = true,
  }) {
    final matchedRule = match(
      result: result,
      matchedRuleId: matchedRuleId,
      matchedRuleTitle: matchedRuleTitle,
      matchedRewardValue: matchedRewardValue,
      extractedProducts: extractedProducts,
      promotionalRules: promotionalRules,
    );

    if (matchedRule == null) return null;

    final effectiveProducts = (result != null && result.extractedProducts.isNotEmpty)
        ? result.extractedProducts
        : extractedProducts;

    // Calculate total quantity of trigger products purchased
    int totalTriggerQty = 0;
    if (effectiveProducts.isNotEmpty) {
      for (final p in effectiveProducts) {
        if (_matchesProduct(p, matchedRule.triggerProduct)) {
          totalTriggerQty += p.quantity > 0 ? p.quantity : 1;
        }
      }
    }

    // Determine multiplier strictly based on trigger product quantity
    int multiplier = 1;
    if (matchedRule.minQuantity > 0 && totalTriggerQty >= matchedRule.minQuantity) {
      if (matchedRule.allowMultipliers || allowCampaignMultipliers) {
        multiplier = totalTriggerQty ~/ matchedRule.minQuantity;
        if (multiplier < 1) multiplier = 1;
      } else {
        multiplier = 1;
      }
    } else {
      multiplier = 1;
    }

    final double baseAmount = matchedRule.totalVoucherValue > 0
        ? matchedRule.totalVoucherValue
        : (matchedRule.rewardAmount > 0 ? matchedRule.rewardAmount : (result?.matchedRewardAmount ?? 0.0));
    final double totalAmount = baseAmount * multiplier;

    final multipliedLinkedGifts = matchedRule.linkedGifts.map((g) {
      return g.copyWith(quantity: g.quantity * multiplier);
    }).toList();

    String prizeSummary;
    if (multiplier > 1) {
      if (matchedRule.rewardType == 'voucher' || baseAmount > 0) {
        final totalInt = totalAmount == totalAmount.roundToDouble() ? totalAmount.toInt() : totalAmount;
        prizeSummary = '$multiplier × ${matchedRule.rewardValue} (إجمالي $totalInt جنيه)';
      } else {
        prizeSummary = '$multiplier × ${matchedRule.rewardValue}';
      }
    } else {
      prizeSummary = matchedRule.rewardValue;
    }

    return MatchedPromotionalRuleResult(
      rule: matchedRule,
      multiplier: multiplier,
      totalTriggerQuantity: totalTriggerQty > 0 ? totalTriggerQty : matchedRule.minQuantity,
      totalRewardAmount: totalAmount,
      formattedPrizeSummary: prizeSummary,
      multipliedLinkedGifts: multipliedLinkedGifts,
    );
  }

  static const Set<String> _noiseWords = {
    'شراء', 'عرض', 'من', 'قطعة', 'قطع', 'علبة', 'عبوة', 'عدد', 'مع', 'على', 'في', 'او', 'or', 'and',
    'مل', 'ml', 'جرام', 'جم', 'g', 'gm', 'كيلو', 'كجم', 'kg'
  };

  static bool _matchesProduct(ExtractedProductItem product, String triggerProduct) {
    if (triggerProduct.trim().isEmpty) return product.isTargetCompany;

    final pNorm = _normalize(product.name);
    final parts = triggerProduct.split(RegExp(r'[,،/\+\n]|(\s+أو\s+)|(\s+or\s+)', caseSensitive: false));

    for (final part in parts) {
      final partNorm = _normalize(part);
      if (partNorm.isEmpty) continue;

      // 1. Direct substring match of whole phrase
      if (pNorm.contains(partNorm)) return true;

      // 2. Phrase matching (all non-noise words in phrase must be present)
      final phraseWords = partNorm.split(' ').where((w) => w.length >= 2 && !_noiseWords.contains(w)).toList();

      if (phraseWords.isNotEmpty) {
        if (phraseWords.every((w) => pNorm.contains(w))) return true;
      }
    }

    return false;
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
        return w.length >= 2 && !_noiseWords.contains(w);
      }).toList();
      tokens.addAll(words);
    }
    return tokens.toSet().toList();
  }
}

/// Represents the resolved promotional rule result with multiplied rewards and chances
class MatchedPromotionalRuleResult {
  final PromotionalRuleItem rule;
  final int multiplier; // e.g. 2
  final int totalTriggerQuantity; // e.g. 4
  final double totalRewardAmount; // e.g. 250.0
  final String formattedPrizeSummary; // e.g. "2 × فواتشر بقيمة 125 جنيه (إجمالي 250 جنيه)"
  final List<LinkedGiftAllocation> multipliedLinkedGifts;

  MatchedPromotionalRuleResult({
    required this.rule,
    this.multiplier = 1,
    this.totalTriggerQuantity = 1,
    this.totalRewardAmount = 0.0,
    required this.formattedPrizeSummary,
    this.multipliedLinkedGifts = const [],
  });
}


