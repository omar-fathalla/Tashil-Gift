import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';
import '../config/ai_config.dart';
import 'gemini_cloud_model.dart';
import '../utils/arabic_numbers_utils.dart';
import 'campaign_ai_assistant_service.dart';
import 'company_gifts_service.dart';
import 'ai_model_config_service.dart';

final aiReceiptServiceProvider = Provider<AiReceiptService>((ref) {
  final config = ref.watch(aiModelConfigStreamProvider).value;
  return AiReceiptService(
    modelName: config?.effectivePrimaryModel ?? AiConfig.primaryModel,
    fastTierModelName: config?.fastTierModel ?? AiConfig.fastTierModel,
    deepAuditModelName: config?.deepAuditModel ?? AiConfig.deepAuditModel,
  );
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

  /// The actual monetary spend paid on this receipt line item.
  /// Strictly prevents artificial spend inflation from physical bundle piece counts (AIR-37).
  double get actualLineSpend {
    if (totalPrice > 0) return totalPrice;
    final q = quantity > 0 ? quantity : 1;
    final p = price > 0 ? price : (originalPrice ?? 0.0);
    return p * q;
  }

  bool get hasDiscount =>
      discountAmount > 0 ||
      discountPercent > 0 ||
      (originalPrice != null && originalPrice! > price);

  factory ExtractedProductItem.fromJson(
    Map<String, dynamic> json, {
    String? targetCompany,
    Iterable<String>? targetBrands,
  }) {
    final name = json['name']?.toString().trim() ?? '';
    int quantity = (json['quantity'] as num?)?.toInt() ?? 1;
    if (quantity <= 0) quantity = 1;

    double rawPrice = (json['price'] as num?)?.toDouble() ?? 0.0;
    double? rawOriginalPrice = (json['originalPrice'] as num?)?.toDouble();
    double rawDiscount = (json['discountAmount'] as num?)?.toDouble() ?? 0.0;
    double rawDiscountPercent =
        (json['discountPercent'] as num?)?.toDouble() ?? 0.0;
    final double? rawTotalLine =
        (json['totalPrice'] as num?)?.toDouble() ??
        (json['totalLinePrice'] as num?)?.toDouble();

    final bool isAlreadyNormalized = json['isUnitNormalized'] == true;

    // Mathematical Consistency & Vertical Column Shift Auto-Healing (AIR-26):
    // If rawTotalLine is provided and equals rawPrice (e.g. Total 134.00 and Price 134.00),
    // but quantity was extracted as > 1 (e.g. quantity = 3 due to reading row above 10.00 / 3.33 / 3):
    // The physical quantity MUST be 1 piece!
    if (quantity > 1 &&
        rawTotalLine != null &&
        rawTotalLine > 0 &&
        rawPrice > 0) {
      if ((rawTotalLine - rawPrice).abs() < 1.5 &&
          (rawOriginalPrice == null || rawOriginalPrice <= rawPrice * 1.25)) {
        quantity = 1;
      } else {
        final double ratio = rawTotalLine / rawPrice;
        final int calculatedQty = ratio.round();
        if (calculatedQty >= 1 &&
            (calculatedQty * rawPrice - rawTotalLine).abs() < 1.5 &&
            calculatedQty != quantity) {
          quantity = calculatedQty;
        }
      }
    }

    // Auto-heal / enforce per-unit price:
    if (quantity > 1 && !isAlreadyNormalized) {
      final bool isAlreadyUnitPrice =
          rawTotalLine != null &&
          rawTotalLine > 0 &&
          (rawPrice * quantity - rawTotalLine).abs() < 1.5;

      if (!isAlreadyUnitPrice) {
        // 1. If rawPrice & rawOriginalPrice were both returned as total line amounts (e.g. 198 and 230 for 2 units)
        if (rawOriginalPrice != null && rawOriginalPrice > 0) {
          if ((rawPrice + rawDiscount - rawOriginalPrice).abs() < 1.5 &&
              rawPrice > 50) {
            rawPrice = rawPrice / quantity;
            rawOriginalPrice = rawOriginalPrice / quantity;
            if (rawDiscount > 0) rawDiscount = rawDiscount / quantity;
          } else if (rawPrice >= rawOriginalPrice * 1.5) {
            rawPrice = rawPrice / quantity;
          } else if (rawOriginalPrice >= 1.8 * rawPrice &&
              rawOriginalPrice > 50) {
            rawOriginalPrice = rawOriginalPrice / quantity;
          }
        } else if (rawTotalLine != null &&
            rawTotalLine > 0 &&
            (rawPrice == rawTotalLine || rawPrice >= rawTotalLine * 0.95)) {
          rawPrice = rawPrice / quantity;
        }

        // 2. If discountAmount was returned as total line discount (e.g. 32 EGP for 2 items)
        if (rawDiscount >= rawPrice && rawDiscount > 0) {
          rawDiscount = rawDiscount / quantity;
        }
      }
    }

    if (rawOriginalPrice != null && rawOriginalPrice <= 0) {
      rawOriginalPrice = null;
    }

    final nameLower = name.toLowerCase();
    final bool hasExplicitIsTarget =
        json.containsKey('isTargetCompany') && json['isTargetCompany'] != null;
    bool isTarget = json['isTargetCompany'] == true;

    // AIR-79: Clorox is strictly excluded for ADCO (ADCO brand is Clorel / كلوريل)
    final isAdco = targetCompany != null &&
        (targetCompany.contains('ادكو') ||
            targetCompany.contains('إدكو') ||
            targetCompany.toLowerCase().contains('adco'));
    final isCloroxName = nameLower.contains('كلوركس') || nameLower.contains('clorox');
    if (isAdco && isCloroxName) {
      isTarget = false;
    }

    // AIR-80: Shoman & Al-Dorra Umbrella Brand Governance and Competitor Sauce Isolation Guard
    final isShomanTenant = targetCompany != null &&
        (targetCompany.contains('شومان') ||
            targetCompany.toLowerCase().contains('shoman') ||
            targetCompany.toLowerCase().contains('shouman'));
    final isDorraTenant = targetCompany != null &&
        (targetCompany.contains('الدرة') ||
            targetCompany.contains('الدره') ||
            targetCompany.contains('درة') ||
            targetCompany.contains('دره') ||
            targetCompany.toLowerCase().contains('dorra') ||
            targetCompany.toLowerCase().contains('durra'));
    final hasDorraBrand = RegExp(
      r'(^|\s)(الدرة|الدره|درة|دره|د\s*ر\s*[هة]|dorra|durra)(\s|$)',
      caseSensitive: false,
    ).hasMatch(nameLower);
    final hasSeyidogluBrand = nameLower.contains('سيد اوغلو') ||
        nameLower.contains('سيد أوغلو') ||
        nameLower.contains('اوغلو') ||
        nameLower.contains('seyidoglu');
    final hasShomanBrand = nameLower.contains('شومان') ||
        nameLower.contains('shoman') ||
        nameLower.contains('shouman');
    final hasAuthorizedShomanDorraBrand =
        hasShomanBrand || hasDorraBrand || hasSeyidogluBrand;

    final hasCompetitorSauceBrand = nameLower.contains('هاينز') ||
        nameLower.contains('heinz') ||
        nameLower.contains('قودي') ||
        nameLower.contains('goody') ||
        nameLower.contains('هارفست') ||
        nameLower.contains('harvest') ||
        nameLower.contains('فاين فودز') ||
        nameLower.contains('كنور') ||
        nameLower.contains('امريكانا') ||
        nameLower.contains('أمريكانا');

    final isAgriculturalCornOrSpice = nameLower.contains('شوشة') ||
        nameLower.contains('شوشه') ||
        nameLower.contains('فشار') ||
        nameLower.contains('حبوب') ||
        nameLower.contains('عطارة') ||
        nameLower.contains('عطاره') ||
        nameLower.contains('بهارات') ||
        nameLower.contains('بذور') ||
        nameLower.contains('فلفل ص') ||
        nameLower.contains('باودر') ||
        nameLower.contains('كمون') ||
        nameLower.contains('فانيليا') ||
        nameLower.contains('دريم') ||
        nameLower.contains('شوكولاتة') ||
        nameLower.contains('شوكولاته') ||
        nameLower.contains('كاكاو') ||
        (nameLower.contains('ذرة') &&
            !nameLower.contains('صلصة') &&
            !nameLower.contains('كاتشب') &&
            !nameLower.contains('صوص') &&
            !nameLower.contains('مربى') &&
            !nameLower.contains('معجون') &&
            !nameLower.contains('خل') &&
            !nameLower.contains('مايونيز') &&
            !nameLower.contains('طحينة') &&
            !nameLower.contains('حلاوة'));

    final isIndependentGrainOrRice = nameLower.contains('فراعنة') ||
        nameLower.contains('الفراعنة') ||
        nameLower.contains('الساعة') ||
        nameLower.contains('الساعه') ||
        nameLower.contains('ريحانة') ||
        nameLower.contains('ريحانه') ||
        nameLower.contains('ارز') ||
        nameLower.contains('أرز');

    if (isShomanTenant || isDorraTenant) {
      if (hasCompetitorSauceBrand || isAgriculturalCornOrSpice || isIndependentGrainOrRice) {
        isTarget = false;
      } else if (hasAuthorizedShomanDorraBrand) {
        isTarget = true;
      }
    }

    // Only auto-infer if isTargetCompany was not explicitly set to false
    if (!hasExplicitIsTarget &&
        !(isAdco && isCloroxName) &&
        !isAgriculturalCornOrSpice &&
        !isIndependentGrainOrRice) {
      if (targetCompany != null && targetCompany.trim().isNotEmpty) {
        if (nameLower.contains(targetCompany.trim().toLowerCase())) {
          isTarget = true;
        }
      }
      if (!isTarget && targetBrands != null && targetBrands.isNotEmpty) {
        for (final tb in targetBrands) {
          final tbLower = tb.trim().toLowerCase();
          if (tbLower.isNotEmpty && nameLower.contains(tbLower)) {
            isTarget = true;
            break;
          }
        }
      }
      if (!isTarget) {
        if (nameLower.contains('تريزيم') ||
            nameLower.contains('تريزم') ||
            nameLower.contains('tresem') ||
            nameLower.contains('كلير') ||
            nameLower.contains('clear') ||
            nameLower.contains('أكس') ||
            nameLower.contains('اكس') ||
            nameLower.contains('axe') ||
            nameLower.contains('ريكسونا') ||
            nameLower.contains('rexona') ||
            nameLower.contains('صنسيلك') ||
            nameLower.contains('صنسلك') ||
            nameLower.contains('sunsilk') ||
            nameLower.contains('دوف') ||
            nameLower.contains('dove') ||
            nameLower.contains('لايفبوي') ||
            nameLower.contains('lifebuoy') ||
            nameLower.contains('لوكس') ||
            nameLower.contains('lux') ||
            nameLower.contains('سيجنال') ||
            nameLower.contains('signal') ||
            nameLower.contains('كلوز اب') ||
            nameLower.contains('close up') ||
            nameLower.contains('فازلين') ||
            nameLower.contains('vaseline') ||
            nameLower.contains('المراعي') ||
            nameLower.contains('almarai') ||
            nameLower.contains('الضحى') ||
            nameLower.contains('doha')) {
          isTarget = true;
        }
      }
    }

    return ExtractedProductItem(
      name: name,
      price: rawPrice,
      quantity: quantity,
      isTargetCompany: isTarget,
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
      'isUnitNormalized': true,
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
  final List<String> matchedRuleIds;
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
  final String storeId;
  final String posNumber;
  final String taxNumber;
  final String commercialReg;
  final String hotline;
  final String branchAddress;
  final String pipelineTierUsed;
  final int aiDurationMs;
  final int dartDurationMs;

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
    this.matchedRuleIds = const [],
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
    this.storeId = '',
    this.posNumber = '',
    this.taxNumber = '',
    this.commercialReg = '',
    this.hotline = '',
    this.branchAddress = '',
    this.pipelineTierUsed = 'fast_tier',
    this.aiDurationMs = 0,
    this.dartDurationMs = 0,
  }) : kpiRating =
           kpiRating ??
           calculateKpiRating(
             durationSeconds > 0 ? durationSeconds : (durationMs / 1000.0),
           ),
       kpiColorHex =
           kpiColorHex ??
           calculateKpiColor(
             durationSeconds > 0 ? durationSeconds : (durationMs / 1000.0),
           );

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

  factory AiReceiptAnalysisResult.fromJson(
    Map<String, dynamic> json, {
    int durationMs = 0,
    String? targetCompany,
    Iterable<String>? targetBrands,
  }) {
    final productsRaw = json['extractedProducts'];
    List<ExtractedProductItem> productsList = [];
    if (productsRaw is List) {
      productsList = productsRaw
          .map(
            (item) => ExtractedProductItem.fromJson(
              Map<String, dynamic>.from(item),
              targetCompany: targetCompany,
              targetBrands: targetBrands,
            ),
          )
          .toList();
    }

    final unfulfilledRaw = json['unfulfilledConditions'];
    List<String> unfulfilledList = [];
    if (unfulfilledRaw is List) {
      unfulfilledList = unfulfilledRaw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final bool isHandwritten = json['isHandwritten'] == true;
    final bool isThermalPosReceipt =
        json['isThermalPosReceipt'] ?? (!isHandwritten);
    final bool isTampered = json['isTampered'] == true;
    final bool isScreenCapture = json['isScreenCapture'] == true;
    final int fraudRiskScore =
        (json['fraudRiskScore'] as num?)?.toInt() ?? (isHandwritten ? 100 : 0);

    final fraudReasonsRaw = json['fraudReasons'];
    List<String> fraudReasonsList = [];
    if (fraudReasonsRaw is List) {
      fraudReasonsList = fraudReasonsRaw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (isHandwritten &&
        !fraudReasonsList.any(
          (r) => r.contains('يدوياً') || r.contains('خط اليد'),
        )) {
      fraudReasonsList.add(
        'فاتورة محررة يدوياً وغير مطبوعة إلكترونياً من الكاشير',
      );
    }

    final int rawDurationMs = json['durationMs'] is num
        ? (json['durationMs'] as num).toInt()
        : durationMs;
    final double rawDurationSec = json['durationSeconds'] is num
        ? (json['durationSeconds'] as num).toDouble()
        : (rawDurationMs / 1000.0);

    final matchedIdsRaw = json['matchedRuleIds'];
    List<String> parsedRuleIds = [];
    if (matchedIdsRaw is List) {
      parsedRuleIds = matchedIdsRaw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final primaryRuleId = json['matchedRuleId']?.toString().trim() ?? '';
    if (primaryRuleId.isNotEmpty && !parsedRuleIds.contains(primaryRuleId)) {
      parsedRuleIds.insert(0, primaryRuleId);
    }

    return AiReceiptAnalysisResult(
      isValid: json['isValid'] ?? false,
      receiptNumber: json['receiptNumber']?.toString() ?? '',
      targetCompanyTotal:
          (json['targetCompanyTotal'] as num?)?.toDouble() ?? 0.0,
      receiptDate: json['receiptDate']?.toString() ?? '',
      extractedProducts: productsList,
      storeChainDetected: json['storeChainDetected']?.toString() ?? json['store_chain_detected']?.toString() ?? '',
      branchDetected: json['branchDetected']?.toString() ?? json['branch_detected']?.toString() ?? '',
      isBranchMatched: json['isBranchMatched'] ?? true,
      message: json['message']?.toString() ?? '',
      unfulfilledConditions: unfulfilledList,
      durationMs: rawDurationMs,
      durationSeconds: rawDurationSec,
      kpiRating: json['kpiRating']?.toString(),
      kpiColorHex: json['kpiColorHex']?.toString(),
      chancesEarned: (json['chancesEarned'] as num?)?.toInt() ?? 1,
      matchedRuleId: primaryRuleId,
      matchedRuleIds: parsedRuleIds,
      matchedRuleTitle: json['matchedRuleTitle']?.toString() ?? '',
      matchedRewardValue: json['matchedRewardValue']?.toString() ?? '',
      matchedRewardAmount:
          (json['matchedRewardAmount'] as num?)?.toDouble() ?? 0.0,
      matchedRewardType: json['matchedRewardType']?.toString() ?? '',
      isHandwritten: isHandwritten,
      isThermalPosReceipt: isThermalPosReceipt,
      isTampered: isTampered,
      isScreenCapture: isScreenCapture,
      fraudRiskScore: fraudRiskScore,
      fraudReasons: fraudReasonsList,
      storeId: json['storeId']?.toString() ?? json['store_id']?.toString() ?? '',
      posNumber: json['posNumber']?.toString() ?? json['pos_number']?.toString() ?? '',
      taxNumber: json['taxNumber']?.toString() ?? json['tax_number']?.toString() ?? '',
      commercialReg: json['commercialReg']?.toString() ?? json['commercial_reg']?.toString() ?? '',
      hotline: json['hotline']?.toString() ?? '',
      branchAddress: json['branchAddress']?.toString() ?? json['branch_address']?.toString() ?? '',
      pipelineTierUsed: json['pipelineTierUsed']?.toString() ?? 'fast_tier',
      aiDurationMs: (json['aiDurationMs'] as num?)?.toInt() ?? 0,
      dartDurationMs: (json['dartDurationMs'] as num?)?.toInt() ?? 0,
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
      'matchedRuleIds': matchedRuleIds,
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
      'storeId': storeId,
      'posNumber': posNumber,
      'taxNumber': taxNumber,
      'commercialReg': commercialReg,
      'hotline': hotline,
      'branchAddress': branchAddress,
      'pipelineTierUsed': pipelineTierUsed,
      'aiDurationMs': aiDurationMs,
      'dartDurationMs': dartDurationMs,
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
    List<String>? matchedRuleIds,
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
    String? storeId,
    String? posNumber,
    String? taxNumber,
    String? commercialReg,
    String? hotline,
    String? branchAddress,
    String? pipelineTierUsed,
    int? aiDurationMs,
    int? dartDurationMs,
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
      unfulfilledConditions:
          unfulfilledConditions ?? this.unfulfilledConditions,
      durationMs: durationMs ?? this.durationMs,
      durationSeconds: effectiveDurationSec,
      kpiRating:
          kpiRating ??
          (durationSeconds != null
              ? calculateKpiRating(effectiveDurationSec)
              : this.kpiRating),
      kpiColorHex:
          kpiColorHex ??
          (durationSeconds != null
              ? calculateKpiColor(effectiveDurationSec)
              : this.kpiColorHex),
      chancesEarned: chancesEarned ?? this.chancesEarned,
      matchedRuleId: matchedRuleId ?? this.matchedRuleId,
      matchedRuleIds: matchedRuleIds ?? this.matchedRuleIds,
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
      storeId: storeId ?? this.storeId,
      posNumber: posNumber ?? this.posNumber,
      taxNumber: taxNumber ?? this.taxNumber,
      commercialReg: commercialReg ?? this.commercialReg,
      hotline: hotline ?? this.hotline,
      branchAddress: branchAddress ?? this.branchAddress,
      pipelineTierUsed: pipelineTierUsed ?? this.pipelineTierUsed,
      aiDurationMs: aiDurationMs ?? this.aiDurationMs,
      dartDurationMs: dartDurationMs ?? this.dartDurationMs,
    );
  }
}

class AiReceiptService {
  late final CloudGenerativeModel _model;
  late final CloudGenerativeModel _fastModel;
  late final CloudGenerativeModel _deepAuditModel;
  late final CloudGenerativeModel _fallbackModel1;
  late final CloudGenerativeModel _fallbackModel2;
  final String modelName;
  final String fastTierModelName;
  final String deepAuditModelName;

  AiReceiptService({
    String? modelName,
    String? fastTierModelName,
    String? deepAuditModelName,
  })  : modelName = (modelName != null && modelName.isNotEmpty) ? modelName : AiConfig.primaryModel,
        fastTierModelName = (fastTierModelName != null && fastTierModelName.isNotEmpty) ? fastTierModelName : AiConfig.fastTierModel,
        deepAuditModelName = (deepAuditModelName != null && deepAuditModelName.isNotEmpty) ? deepAuditModelName : AiConfig.deepAuditModel {
    _model = _createModel(this.modelName);
    _fastModel = _createFastTierModel(this.fastTierModelName);
    _deepAuditModel = _createDeepAuditModel(this.deepAuditModelName);
    _fallbackModel1 = _createFastTierModel(AiConfig.fallbackModel);
    _fallbackModel2 = _createFastTierModel('gemini-3.6-flash');
  }

  static CloudGenerativeModel _createModel(String name) {
    return CloudGenerativeModel(
      model: name,
      systemInstruction: Content.system(
        'أنت مدقق مالي وأمني فائق السرعة والدقة والصرامة في فحص وتدقيق فواتير السوبر ماركت وكشف التزوير لعروض الشركات الاستهلاكية (FMCG). '
        'مهمتك فحص صور الفواتير فورياً واستخراج البيانات الأساسية: اسم السلسلة، الفرع، رقم الفاتورة، تاريخ الشراء، '
        'وحساب إجمالي المشتريات لمنتجات الشركة الراعية فقط، وكشف أي محاولة تزوير أو كتابة يدوية أو شطب أو تصوير شاشات بدقة وبصيغة JSON.\n\n'
        '🛑 قواعد مكافحة التزوير والرفض الأمني القاطع (Zero-Tolerance Anti-Fraud Policy):\n'
        '1. يُمنع منعاً باتاً قبول أي فاتورة أو ورقة محررة أو مكتوبة بخط اليد (Handwritten Receipt / Paper Draft / Manual Note) بقلم جاف أو حبر أو رصاص.\n'
        '2. الفواتير المقبولة حصراً هي بونات الكاشير الإلكترونية المطبوعة آلياً عبر طابعات نقاط البيع الرسمية (Printed Thermal / Electronic POS Receipts).\n'
        '3. إذا كانت الفاتورة مكتوبة باليد، يجب تعيين: isHandwritten = true، isThermalPosReceipt = false، isValid = false، وإضافة "الفاتورة محررة يدوياً وغير مطبوعة إلكترونياً من الكاشير" إلى fraudReasons وقائمة unfulfilledConditions.\n'
        '4. إذا وجد أي شطب أو تعديل يدوي في أرقام الفاتورة، عيّن: isTampered = true، isValid = false.\n'
        '5. إذا كانت الصورة ملتقطة لشاشة هاتف أو حاسوب، عيّن: isScreenCapture = true، isValid = false.\n\n'
        '🛑 معيار الصرامة الفائقة ومنع التخمين (Zero-Hallucination & Exact Extraction Policy):\n'
        '1. استخرج فقط الأسماء والأصناف والكميات المطبوعة نصاً وحرفياً في الفاتورة.\n'
        '2. يُمنع منعاً باتاً تخمين أو افتراض أي منتج أو علامة تجارية أو كمية غير ظاهرة بوضوح تام.\n'
        '3. إذا كانت الفاتورة أو سطر المنتج مطموساً أو غير واضح أو مقطوعاً أو يصعب قراءته بيقين، يجب تعيين: isValid = false، وإضافة "صورة الفاتورة غير واضحة أو اسم المنتج غير مقروء بدقة، برجاء إعادة تصوير الفاتورة بوضوح وإظهار سطر المنتج والكمية" إلى unfulfilledConditions.\n\n'
        '🛑 قاعدة تسعير أعمدة الكاشير المزدوجة (Dual-Column POS Unit Price Rule):\n'
        'في فواتير السلاسل المطبوعة بأعمدة تفصيلية (مثل: جملة ماركت، سبينس، كارفور، هايبر وان):\n'
        '- عمود "السعر" المطبوع (مثل 69.00) يمثل سعر بيع القطعة الواحدة بالفعل (Single Unit Price).\n'
        '- عمود "القيمة" المطبوع (مثل 138.00) يمثل إجمالي السطر (Line Total = السعر × الكمية).\n'
        '- يُمنع منعاً باتاً قسمة عمود "السعر" على الكمية مرة أخرى (فإذا كان السعر 69.00 والكمية 2 والقيمة 138.00، يكون price = 69.00 و totalLinePrice = 138.00 وليس 34.50).\n\n'
        '🛑 قاعدة العروض والخصومات الترويجية وسعر البيع الفعلي (Promotional Offers & Net Promo Price Rule):\n'
        'يجب أخذ العروض والخصومات الترويجية في الحسبان دائماً عند فحص الفواتير والأسعار:\n'
        '1. حقل price يمثل حتماً وبصرامة سعر بيع القطعة الواحدة الصافي الفعلي بعد تطبيق الخصم أو العرض الترويجي (Net Selling Price after Promo Discount).\n'
        '2. إذا كان الصنف مشمولاً بعرض ترويجي (مثل تخفيض سعر، عرض خاص، خصم كاشير، أو بون تخفيض)، ضع السعر الأصلي للقطعة قبل الخصم في originalPrice، ومقدار خصم القطعة الواحدة في discountAmount، ونسبة الخصم في discountPercent، ويكون price هو السعر المخفض النهائي الذي يدفعه العميل بالفعل.\n'
        '3. يُمنع منعاً باتاً تسجيل السعر الأصلي كـ price وتجاهل الخصم الترويجي، لضمان دقة رصد ومقارنة أسعار السوق الحقيقية.\n\n'
        '⚡ استراتيجية المسح السريع الفائق وتصفية الأصناف (Targeted Fast-Scan Policy):\n'
        '1. افحص رأس الفاتورة (Header) لاستخراج السلسلة، الفرع، التاريخ، ورقم الفاتورة.\n'
        '2. عند فحص بنود المشتريات: ركز حصراً على أسطر منتجات الشركة الراعية المشروطة في الحملة، وتجاوز فورياً أي أصناف غذائية أو استهلاكية عامة غير تابعة للشركة (مثل: اللحوم، الخضار، الفاكهة، المخبوزات، الأجبان، البقوليات، الشوكولاتة، المنظفات غير التابعة) دون إدراجها في قائمة extractedProducts.\n'
        '3. أدرج في قائمة extractedProducts فقط المنتجات التابعة للشركة الراعية مع أسعارها الدقيقة وكمياتها لتقليص زمن الاستجابة وزيادة السرعة لأقصى حد.\n\n'
        '🛑 قاعدة بونات التكملة المتعددة والبونات المجمعة جنباً إلى جنب (Complementary & Side-by-Side Multi-Receipt Rule - AIR-58):\n'
        '1. في حال ظهور بونين كاشير مطبوعين إلكترونياً جنباً إلى جنب في نفس الصورة، أو تم رفعهما عبر صور متعددة لنفس السلسلة والفرع في نفس اليوم وكان أحدهما بوناً تكميلياً للآخر (مثل وجود ملاحظة "تكملة الفاتورة" أو شراء صنف إضافي لنفس العميل لتكملة الحد الأدنى للعرض):\n'
        '   * [رقم الفاتورة]: استخرج رقمي الفاتورة معاً مدمجين بفاصل " + " في حقل (receiptNumber) (مثال: "64/6/241/250926 + 109/8/241/250926").\n'
        '   * [سلة المنتجات المجمعة]: اجمع كافة أصناف الشركة الراعية المؤهلة من كلا البونين في قائمة (extractedProducts) دون إسقاط أي صنف.\n'
        '   * [إجمالي الإنفاق التراكمي]: احسب (targetCompanyTotal) بجمع إجمالي منتجات الشركة المؤهلة من كلا البونين معاً (مثال: 751.00 + 55.00 = 806.00 ج.م).\n'
        '   * [استحقاق الجوائز]: طبّق القواعد الترويجية ومضاعفات الهدايا والفرص على الإجمالي التراكمي للبونين معاً.\n'
        '   * [الملاحظات اليدوية في الهوامش]: العبارات التوضيحية مثل "تكملة الفاتورة" أو "تم استلام 2 فوتشر" هي هوامش توضيحية تنظيمية معتمدة من البروموتر، وتؤكد صحة البونين ولا تُعد تشويهاً أو تحريراً يدوياً للفاتورة الأصلية طالما أن أصل البونين مطبوع إلكترونياً من الكاشير.\n\n'
        '🛑 قاعدة معالجة أسماء الماركات المحرفة أو المقصوصة في طابعات الكاشير (POS Dropped Character Rule - AIR-70):\n'
        'في بونات الكاشير لبعض السلاسل التجارية، قد تحدث أخطاء طباعية أو إسقاط حروف من أسماء العلامات الفرعية:\n'
        '- شركة أدكو (ADCO): تشمل منتجات النظافة والأرضيات والتواليت علامة "سبيد (Speed)"؛ وتطبعها بعض ماكينات الكاشير بحذف حرف الباء مثل: "سيد منظف ارضيات" أو "سيد باودر" أو "سيد 28.00" - يجب احتسابها صنفاً أصيلاً ومعتمداً لشركة أدكو (isTargetCompany = true) وإدراجها في قائمة extractedProducts وجمع قيمتها في targetCompanyTotal.\n'
        '- علامة "كلوريل (Clorel)" و "فلفيتا (Velveta)" و "ماكسيل ماجيك (Maxel Magic)" و "فيبا (Feba)" و "ديفا (Diva)" هي علامات تابعة لشركة أدكو ويجب استخراج كافة بنودها بعناية دون إسقاط أي صنف منها.\n'
        '- 🛑 معيار الحظر القطعي لأصناف كلوركس واستقلاليتها عن أدكو (AIR-79): شركة أدكو (ADCO) تنتج مبيضات وكلور الملابس تحت علامة "كلوريل (Clorel)" حصراً؛ وتتبع علامة "كلوركس (Clorox)" شركة أخرى مستقلة ومنافسة وليست تابعة لأدكو مطلقاً. يُحظر تماماً وبصرامة احتساب أي منتج باسم "كلوركس" (مثل: كلوركس ألوان، كلوركس أبيض، كلوركس جل، كلوركس منظف) كصنف تابع لأدكو (يجب حتماً تعيين isTargetCompany = false واستبعاده كلياً من targetCompanyTotal وعروض أدكو).\n'
        '- 🛑 معيار حوكمة ماركات شومان والدرة وسيد أوغلو وعزل الصلصات والسلع الزراعية المتنافسة (AIR-80 & AIR-87): شركة "شومان (Shoman)" هي الراعي والمصنع لمنتجات "الدرة (الدرة / درة / دره / د ر ه / Dorra / Durra)" و"سيد أوغلو (Seyidoglu)" في مصر. عند فحص فاتورة لحملة "شومان" أو "الدرة"، تُعد كافة أصناف الدرة وشومان وسيد أوغلو المصنعة والمعبأة (مثل: دره عرض كاتشب، د ر ه كاتشب، الدرة صوص برجر، الدرة شيلي صوص، صلصة ومعجون طماطم الدرة، مايونيز، مربى، خل، مخللات، حلاوة وطحينة، إلخ) منتجات أصيلة ومؤهلة بنسبة 100% ويجب تعيين isTargetCompany = true وجمع قيمتها فوراً في targetCompanyTotal. أما السلع والشركات المستبعدة قطعياً (isTargetCompany = false) فهي: 1) الحبوب والسلع الزراعية والعطارة والفشار (مثل: درة أم شوشة، ذرة أم شوشة، ذرة فشار، درة فشار، بهارات، عطارة، ذرة حبوب) حيث تُعد سلعاً عامة مستقلة. 2) ماركات الأرز المستقلة (مثل: الفراعنة أرز، أرز الفراعنة، الساعة، ريحانة) مع الحظر الصارم لأي هلوسة أو استبدال للماركات المطبوعة. 3) ماركات الصلصات المنافسة: هاينز (Heinz)، قودي (Goody)، هارفست (Harvest)، كنور (Knorr)، فاين فودز (Fine Foods)، أمريكانا (Americana).\n\n'
        '🛑 معيار الحظر الصارم لاحتساب أصناف الشوكولاتة والمالتي باك العامة دون علامة تجارية صريحة (AIR-71):\n'
        '- يُمنع منعاً باتاً افتراض أو تخمين تبعية أي صنف عام مطبوع على بون الكاشير تحت مسمى مبهم أو عام مثل: "مالتي باك شوكولات" أو "مالتي باك شوكولاتة" أو "شوكولاتة مشكلة" أو "بسكويت ويفر" لشركة كادبوري (Cadbury) أو مونديليز (Mondelez) ما لم يُذكر في سطر البون صراحة اسم العلامة المعتمدة التابعة للشركة (مثل: كادبوري، ديري ميلك، مورو، بابلي، أوريو، ماندولين، فليك، سي دي ام، CDM).\n'
        '- يُحظر كلياً الاستناد إلى وجود أصناف كادبوري أخرى بالفاتورة لاعتبار الصنف العام تابعاً لكادبري.\n'
        '- أي صنف عام يخلو من اسم العلامة الصريح يجب فوراً تعيينه: isTargetCompany = false واستبعاده كلياً من targetCompanyTotal ومن أي احتساب للجوائز أو مضاعفات الفواتشر.',
      ),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.0,
        maxOutputTokens: 8192,
        responseSchema: Schema.object(
          properties: {
            'isValid': Schema.boolean(
              description:
                  'True if this is a genuine printed supermarket POS receipt containing target company products and meeting all rules. False if invalid, fraudulent, or handwritten.',
            ),
            'receiptNumber': Schema.string(
              description:
                  'The unique receipt number or transaction ID (e.g., 295/8/211/220726). Return empty string if not found.',
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
            'storeId': Schema.string(
              description:
                  'Store number or branch ID code if printed (e.g. Store: 1 or فرع 224). Return empty string if not found.',
            ),
            'posNumber': Schema.string(
              description:
                  'POS terminal or register number if printed (e.g. PoS: 9 or كاشير 3). Return empty string if not found.',
            ),
            'taxNumber': Schema.string(
              description:
                  'Tax registration number or commercial register if printed on receipt. Return empty string if not found.',
            ),
            'commercialReg': Schema.string(
              description:
                  'Commercial registration number if printed on receipt. Return empty string if not found.',
            ),
            'hotline': Schema.string(
              description:
                  'Customer service hotline phone number printed on receipt. Return empty string if not found.',
            ),
            'branchAddress': Schema.string(
              description:
                  'Full branch address or location printed in receipt header or footer. Return empty string if not found.',
            ),
            'isHandwritten': Schema.boolean(
              description:
                  'True ONLY if the receipt items/prices themselves are manually handwritten on a notebook/paper draft. Must be false for printed electronic thermal/POS cash register receipts even if there are promoter notes, endorsements (e.g. تم تسليم الهدية), or signatures on the margins.',
            ),
            'isThermalPosReceipt': Schema.boolean(
              description:
                  'True ONLY if this is a genuine printed electronic POS / thermal cash register receipt.',
            ),
            'isTampered': Schema.boolean(
              description:
                  'True ONLY if there is fraudulent alteration, forged/scratched-out printed numbers or prices to alter purchase values. Normal promoter notes, signatures, or endorsement checkmarks in margins do NOT count as tampering.',
            ),
            'isScreenCapture': Schema.boolean(
              description:
                  'True if this is a photo of a computer or phone display screen rather than a physical paper receipt.',
            ),
            'fraudRiskScore': Schema.integer(
              description:
                  'Fraud probability score from 0 (genuine printed receipt) to 100 (blatantly forged/handwritten).',
            ),
            'fraudReasons': Schema.array(
              description:
                  'List of fraud or suspicious triggers detected (e.g. فاتورة مكتوبة بخط اليد, تلاعب وشطب وتعديل بأرقام الأصناف, تصوير شاشة إلكترونية). Empty if clean.',
              items: Schema.string(),
            ),
            'extractedProducts': Schema.array(
              description:
                  'List of target company promoted products found on the receipt with strictly single unit prices, quantities, and matched barcodes. Skip unrelated general grocery items to maximize response speed.',
              items: Schema.object(
                properties: {
                  'name': Schema.string(
                    description: 'Product name as printed on receipt.',
                  ),
                  'price': Schema.number(
                    description:
                        'Net actual selling unit price per single piece in EGP/AED AFTER any promotional discounts or offers. In dual-column receipts with "السعر" and "القيمة", use the "السعر" column directly without re-dividing.',
                  ),
                  'quantity': Schema.integer(
                    description: 'Quantity purchased (e.g. 1, 2, 3).',
                  ),
                  'isTargetCompany': Schema.boolean(
                    description:
                        'True if this product belongs to the target company being promoted.',
                  ),
                  'barcode': Schema.string(
                    description:
                        'The product barcode or item code if detected or matched from company catalog. Return empty string if not found.',
                  ),
                  'originalPrice': Schema.number(
                    description:
                        'Original gross unit price per single piece before discount (e.g. 115.0). Null or 0 if not discounted.',
                  ),
                  'discountAmount': Schema.number(
                    description:
                        'Monetary discount amount per single piece (e.g. 16.0 for 32 EGP discount on 2 pieces). 0 if no discount.',
                  ),
                  'discountPercent': Schema.number(
                    description:
                        'Percentage discount if printed on line item (e.g. 15 for 15%). 0 if no discount.',
                  ),
                  'totalLinePrice': Schema.number(
                    description:
                        'Total line amount paid for this item in receipt (e.g. 198.0 for 2 pieces).',
                  ),
                },
                requiredProperties: [
                  'name',
                  'price',
                  'quantity',
                  'isTargetCompany',
                ],
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
                  'The exact ID of the primary matched promotional rule (e.g. rule_1, rule_2, rule_3, rule_4, rule_5), or empty string if no specific rule matched.',
            ),
            'matchedRuleIds': Schema.array(
              description:
                  'List of ALL matched promotional rule IDs if multiple distinct products/offers matched in this receipt (e.g. ["rule_3", "rule_5"]). Return empty array if none.',
              items: Schema.string(),
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

  static final Schema _fastTierSchema = Schema.object(
    properties: {
      'isValid': Schema.boolean(
        description:
            'True if this is a genuine printed supermarket POS receipt containing target company products and meeting all rules. False if invalid, fraudulent, or handwritten.',
      ),
      'receiptNumber': Schema.string(
        description:
            'The unique receipt number or transaction ID (e.g., 295/8/211/220726). Return empty string if not found.',
      ),
      'targetCompanyTotal': Schema.number(
        description:
            'The total sum in EGP/AED of ONLY the target company products found on the receipt.',
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
      'storeId': Schema.string(
        description:
            'Store number or branch ID code if printed (e.g. Store: 1 or فرع 224). Return empty string if not found.',
      ),
      'posNumber': Schema.string(
        description:
            'POS terminal or register number if printed (e.g. PoS: 9 or كاشير 3). Return empty string if not found.',
      ),
      'taxNumber': Schema.string(
        description:
            'Tax registration number or commercial register if printed on receipt. Return empty string if not found.',
      ),
      'commercialReg': Schema.string(
        description:
            'Commercial registration number if printed on receipt. Return empty string if not found.',
      ),
      'hotline': Schema.string(
        description:
            'Customer service hotline phone number printed on receipt. Return empty string if not found.',
      ),
      'branchAddress': Schema.string(
        description:
            'Full branch address or location printed in receipt header or footer. Return empty string if not found.',
      ),
      'isHandwritten': Schema.boolean(
        description:
            'True ONLY if the receipt items/prices themselves are manually handwritten on a notebook/paper draft.',
      ),
      'isThermalPosReceipt': Schema.boolean(
        description:
            'True ONLY if this is a genuine printed electronic POS / thermal cash register receipt.',
      ),
      'isTampered': Schema.boolean(
        description:
            'True ONLY if there is fraudulent alteration, forged/scratched-out printed numbers or prices to alter purchase values.',
      ),
      'isScreenCapture': Schema.boolean(
        description:
            'True if this is a photo of a computer or phone display screen rather than a physical paper receipt.',
      ),
      'fraudRiskScore': Schema.integer(
        description:
            'Fraud probability score from 0 (genuine printed receipt) to 100 (blatantly forged/handwritten).',
      ),
      'fraudReasons': Schema.array(
        description:
            'List of fraud or suspicious triggers detected. Empty if clean.',
        items: Schema.string(),
      ),
      'extractedProducts': Schema.array(
        description:
            'List of target company promoted products found on the receipt with strictly single unit prices, quantities, and matched barcodes. Skip unrelated general grocery items.',
        items: Schema.object(
          properties: {
            'name': Schema.string(
              description: 'Product name as printed on receipt.',
            ),
            'price': Schema.number(
              description:
                  'Net actual selling unit price per single piece in EGP/AED AFTER any promotional discounts or offers.',
            ),
            'quantity': Schema.integer(
              description: 'Quantity purchased (e.g. 1, 2, 3).',
            ),
            'isTargetCompany': Schema.boolean(
              description:
                  'True if this product belongs to the target company being promoted.',
            ),
            'barcode': Schema.string(
              description:
                  'The product barcode or item code if detected. Return empty string if not found.',
            ),
            'originalPrice': Schema.number(
              description:
                  'Original gross unit price per single piece before discount. Null or 0 if not discounted.',
            ),
            'discountAmount': Schema.number(
              description:
                  'Monetary discount amount per single piece. 0 if no discount.',
            ),
            'discountPercent': Schema.number(
              description:
                  'Percentage discount if printed on line item. 0 if no discount.',
            ),
            'totalLinePrice': Schema.number(
              description:
                  'Total line amount paid for this item in receipt.',
            ),
          },
          requiredProperties: [
            'name',
            'price',
            'quantity',
            'isTargetCompany',
          ],
        ),
      ),
      'message': Schema.string(
        description:
            'A concise report in Arabic explaining the validation result, or the exact errors if conditions fail.',
      ),
      'unfulfilledConditions': Schema.array(
        description:
            'List of specific unmet conditions or errors explaining why the receipt is invalid. Return empty array if all conditions are met.',
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
  );

  static CloudGenerativeModel _createFastTierModel(String name) {
    return CloudGenerativeModel(
      model: name,
      systemInstruction: Content.system(
        'أنت فاحص ومستخرج بيانات فواتير التجزئة والسوبرماركت فائق السرعة والدقة (Gemini Ultra-Fast POS Scanner Tier).\n'
        'مهمتك: فحص صورة بون الكاشير المطبوع واستخراج البيانات الأساسية بأقصى سرعة ممكنة وبأعلى دقة OCR وبصيغة JSON نقية وموجزة.\n\n'
        '🛑 قواعد مكافحة التزوير القاطعة (Zero-Tolerance Anti-Fraud):\n'
        '1. يُمنع منعاً باتاً قبول أي ورقة أو فاتورة محررة بخط اليد (isHandwritten = true, isThermalPosReceipt = false, isValid = false).\n'
        '2. الفواتير المقبولة حصراً هي بونات الكاشير الإلكترونية المطبوعة آلياً عبر طابعات نقاط البيع (isThermalPosReceipt = true).\n'
        '3. إذا وجد أي شطب أو تعديل يدوي في أرقام الفاتورة: isTampered = true, isValid = false.\n'
        '4. إذا كانت الصورة ملتقطة لشاشة حاسوب أو هاتف: isScreenCapture = true, isValid = false.\n\n'
        '🛑 استخراج المنتجات والأسعار بدقة (Single Unit Price Rule):\n'
        '1. في حقل price: ضع سعر بيع القطعة الواحدة الصافي فقط بعد الخصم الترويجي، وليس إجمالي السطر.\n'
        '2. في فواتير الأعمدة المزدوجة (السعر / القيمة): عمود "السعر" يمثل سعر بيع القطعة الواحدة، وعمود "القيمة" يمثل إجمالي السطر.\n'
        '3. ركز حصراً على منتجات الشركة الراعية المشروطة وعلاماتها الفرعية، وتجاوز فورياً أي أصناف غذائية أو استهلاكية عامة غير تابعة للشركة لتسريع الاستجابة.\n'
        '4. استخرج رقم الفاتورة الصريح، التاريخ، اسم السلسلة، الفرع، وكود المتجر Store ID بدقة تامة.\n'
        '5. التزم التزاماً مطلقاً ببنية JSON المعرفة في responseSchema وتجنب أي نصوص خارج الهيكل.',
      ),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.0,
        maxOutputTokens: 8192,
        responseSchema: _fastTierSchema,
      ),
    );
  }

  static CloudGenerativeModel _createDeepAuditModel(String name) {
    return CloudGenerativeModel(
      model: name,
      systemInstruction: Content.system(
        'أنت كبير المدققين الجنائيين والماليين لفواتير السوبرماركت المعقدة (Gemini Deep Forensic Audit Tier).\n'
        'تُستدعى مهامك في حالات الاشتباه الأمني، وتضارب أرقام الكاشير، وفحص الفواتير المركبة أو المشكوك في تلاعبها.\n'
        'مهمتك: إجراء فحص مجهري فائق التدقيق للصورة لكشف أي تلاعب رقمي خفي، أو تعديل في الفواصل والكسور، أو عدم اتساق بين كود المتجر ورقم ماكينة الـ POS، أو تداخل غير شرعي بين بونات متعددة.\n'
        'قواعد التدقيق الجنائي:\n'
        '1. دقق في حواف الأرقام المطبوعة وخط الطابعة الحرارية للتأكد من عدم وجود تعديل أو تركيب رقمي.\n'
        '2. فحص البونات المتجاورة ومنع دمج بونات منفصلة (AIR-61).\n'
        '3. التحقق من اتساق إجمالي الفاتورة مع مجموع البنود الفردية.\n'
        '4. إرجاع تقرير جنائي تفصيلي في message وقائمة fraudReasons.',
      ),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.0,
        maxOutputTokens: 8192,
        responseSchema: _fastTierSchema,
      ),
    );
  }

  // ==========================================
  // LRU In-Memory Cache & Fingerprinting (AIR-74)
  // ==========================================
  static final Map<String, AiReceiptAnalysisResult> _receiptAnalysisLruCache = {};
  static const int _maxLruCacheEntries = 100;

  /// Computes a fast deterministic fingerprint for receipt image bytes
  static String computeBytesFingerprint(List<Uint8List> allBytesList) {
    if (allBytesList.isEmpty) return '';
    int hash = 0;
    int totalBytes = 0;
    for (final bytes in allBytesList) {
      totalBytes += bytes.length;
      final step = math.max(1, bytes.length ~/ 100);
      for (int i = 0; i < bytes.length; i += step) {
        hash = (hash * 31 + bytes[i]) & 0x7fffffff;
      }
    }
    return '${totalBytes}_$hash';
  }

  static void cacheReceiptAnalysis(String fingerprint, AiReceiptAnalysisResult result) {
    if (fingerprint.isEmpty) return;
    if (_receiptAnalysisLruCache.length >= _maxLruCacheEntries) {
      _receiptAnalysisLruCache.remove(_receiptAnalysisLruCache.keys.first);
    }
    _receiptAnalysisLruCache[fingerprint] = result;
  }

  static AiReceiptAnalysisResult? getCachedReceiptAnalysis(String fingerprint) {
    if (fingerprint.isEmpty) return null;
    return _receiptAnalysisLruCache[fingerprint];
  }

  static void clearReceiptAnalysisCache() {
    _receiptAnalysisLruCache.clear();
  }

  // ==========================================
  // Client-Side Throttling & Exponential Backoff
  // ==========================================
  static DateTime? _lastAiCallTimestamp;
  static const int _minInterRequestIntervalMs = 250;

  static Future<void> _throttleClientRequest() async {
    if (_lastAiCallTimestamp != null) {
      final elapsed = DateTime.now().difference(_lastAiCallTimestamp!).inMilliseconds;
      if (elapsed < _minInterRequestIntervalMs) {
        await Future.delayed(Duration(milliseconds: _minInterRequestIntervalMs - elapsed));
      }
    }
    _lastAiCallTimestamp = DateTime.now();
  }

  /// Executes Gemini generateContent with automatic exponential backoff retry on HTTP 429 quota errors.
  Future<CloudGenerateContentResponse> _executeWithExponentialBackoff(
    CloudGenerativeModel model,
    List<Content> contents, {
    int maxRetries = 3,
    int initialBackoffMs = 1500,
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        await _throttleClientRequest();
        return await model.generateContent(contents).timeout(const Duration(seconds: 30));
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        final isQuotaExhausted = errStr.contains('429') ||
            errStr.contains('resource_exhausted') ||
            errStr.contains('resourceexhausted') ||
            errStr.contains('quota');

        if (isQuotaExhausted && attempt <= maxRetries) {
          final backoff = (initialBackoffMs * (1 << (attempt - 1))) + math.Random().nextInt(400);
          debugPrint('⚠️ [AiReceiptService] Gemini 429 quota hit on attempt $attempt. Retrying in ${backoff}ms with exponential backoff...');
          await Future.delayed(Duration(milliseconds: backoff));
        } else {
          rethrow;
        }
      }
    }
  }

  Future<AiReceiptAnalysisResult> analyzeReceiptImage(
    Uint8List imageBytes,
    String mimeType, {
    List<Uint8List> additionalImagesBytes = const [],
    List<String> additionalMimeTypes = const [],
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
    bool allowComplementaryReceipts = false,
    bool forceDeepAudit = false,
    bool forceRefresh = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final allImagesBytesList = [imageBytes, ...additionalImagesBytes];
      final String fingerprint = computeBytesFingerprint(allImagesBytesList);

      // Check LRU In-Memory Cache for identical receipt image submissions
      if (!forceRefresh && fingerprint.isNotEmpty) {
        final cached = getCachedReceiptAnalysis(fingerprint);
        if (cached != null) {
          debugPrint('⚡ [AiReceiptService] In-Memory Cache Hit for fingerprint $fingerprint (0ms)');
          return cached.copyWith(
            pipelineTierUsed: 'lru_cache',
            aiDurationMs: 0,
            dartDurationMs: 0,
          );
        }
      }

      final Set<String> effectiveRequiredProducts = Set<String>.from(requiredProducts);
      for (final r in promotionalRules) {
        for (final sp in r.selectedProductNames) {
          if (sp.trim().isNotEmpty) effectiveRequiredProducts.add(sp.trim());
        }
        for (final rb in r.requiredBrands) {
          if (rb.trim().isNotEmpty) effectiveRequiredProducts.add(rb.trim());
        }
      }
      final resolvedRequiredProducts = effectiveRequiredProducts.toList();

      final List<Part> allImageParts = [
        DataPart(mimeType, imageBytes),
      ];
      for (int i = 0; i < additionalImagesBytes.length; i++) {
        final mType = i < additionalMimeTypes.length
            ? additionalMimeTypes[i]
            : mimeType;
        allImageParts.add(DataPart(mType, additionalImagesBytes[i]));
      }

      String multiPartInstructions = '';
      if (additionalImagesBytes.isNotEmpty) {
        final totalParts = allImageParts.length;
        if (!allowComplementaryReceipts) {
          multiPartInstructions = '''

🧩 تعليمات دمج وتدقيق الفاتورة الطويلة متعددة الأجزاء وحظر دمج الفواتير المنفصلة (Strict Single Long Receipt Stitching & Anti-Merging Policy - AIR-61):
- المرفق يحتوي على ($totalParts) صور متتالية:
  * [معيار الفاتورة الواحدة الطويلة حصراً]: يُسمح بتعدد الصور حصراً إذا كانت تمثل فاتورة فيزيائية واحدة طويلة (Single Continuous Receipt) تم تصويرها على أجزاء متتابعة من الأعلى إلى الأسفل نظراً لطولها (الجزء الأول يحتوي الترويسة والفرع ورقم الفاتورة، والجزء التالي لباقي الأصناف، والجزء الأخير يحتوي الإجمالي النهائي والباركود).
  * [مطابقة هوية الفاتورة الواحدة]: يجب أن تتطابق في كافة الأجزاء هوية الفاتورة (نفس رقم الفاتورة، نفس الفرع، نفس ماكينة الـ POS، نفس التاريخ والتوقيت، نفس نوع ورق الكاشير).
  * [منع تكرار الأسطر المتداخلة (Cross-Seam Deduplication)]: عند التقاط أجزاء متتابعة، قد يظهر السطر الأخير من الصورة الأولى في بداية الصورة الثانية نتيجة تداخل الكاميرا؛ يجب حتماً عد الصنف مرة واحدة فقط وعدم تكرار كميته أو قيمته مطلقاً.
  * [حظر دمج بونات منفصلة (Zero Tolerance for Multi-Receipt Splicing)]: إذا كانت الصور تمثل فواتير أو بونات مختلفة بأرقام بونات مختلفة أو توقيتات مختلفة أو ترويسات متعددة، فهذه مخالفة جسيمة وتزوير؛ عيّن فوراً:
    isValid = false
    status = "rejected"
    واكتب في (unfulfilledConditions): ["مخالفة معايير الأهلية: تم رصد محاولة دمج بونات شراء منفصلة ذات أرقام أو توقيتات مختلفة في معاملة واحدة. يشترط النظام استيفاء شروط العرض في فاتورة شراء واحدة مستقلة."]
    ولا تدمج أرقام الفواتير برابط "+" ولا تجمع إجماليات بونات منفصلة مطلقاً.
''';
        } else {
          multiPartInstructions = '''

🧩 تعليمات دمج وتدقيق الفواتير المقسمة أو بونات التكملة المتعددة (Multi-Part & Complementary Receipts Stitching):
- المرفق يحتوي على ($totalParts) صور متتالية:
  * [النمط 1: أجزاء فاتورة واحدة طويلة]: تم التقاطها على أجزاء متتابعة من الأعلى إلى الأسفل. قم بدمج الأجزاء ومنع تكرار الأسطر المتداخلة عند فواصل الصور (Cross-Seam Deduplication).
  * [النمط 2: بونات مشتريات متعددة / بون مكمل لنفس العميل لتكملة القيمة (Complementary Receipts)]: إذا كانت الصور تمثل بونات كاشير مطبوعة لنفس السلسلة والفرع في نفس اليوم (أحدها بون أساسي والآخر بون تكميلي مثل "تكملة الفاتورة" لزيادة القيمة والوصول للحد الأدنى للعرض):
    - ادمج أرقام الفواتير في (receiptNumber) برابط " + " (مثال: "64/6/241/250926 + 109/8/241/250926").
    - اجمع كافة المنتجات المؤهلة المشروطة للشركة الراعية الموزعة عبر جميع الأجزاء ($totalParts صور) في سلة واحدة مجمعة متكاملة في (extractedProducts).
    - احسب إجمالي (targetCompanyTotal) التراكمي المشترك لكافة البونات بدقة، وطبّق عليه قواعد الجوائز ومضاعفات الفرص.
    - الملاحظات اليدوية مثل "تكملة الفاتورة" أو "تم استلام 2 فوتشر" هي هوامش توضيحية تنظيمية معتمدة من البروموتر وليست تزويراً.
''';
        }
      }

      final productsCondition = resolvedRequiredProducts.isNotEmpty
          ? (resolvedRequiredProducts.length <= 120
              ? 'تنبيه خاص بالمنتجات المشروطة بالعرض: المنتجات المشمولة في هذا العرض هي: [${resolvedRequiredProducts.join("، ")}]. يجب أن تحتوي الفاتورة على واحد أو أكثر من هذه المنتجات المحددة، ويتم احتساب إجمالي (targetCompanyTotal) بناءً على أسعار منتجات شركة "$targetCompany" المشمولة بالعرض.'
              : 'تنبيه خاص بالمنتجات المشروطة بالعرض: العرض يشمل ${resolvedRequiredProducts.length} صنفاً معتمداً لشركة "$targetCompany" (مثل: ${resolvedRequiredProducts.take(40).join("، ")}... إلخ). ابحث عن كافة أصناف وعلامات شركة "$targetCompany" بالفاتورة واحسب إجمالي (targetCompanyTotal) بناءً على المنتجات التابعة للشركة.')
          : 'ابحث عن كافة الأصناف المشتراة، وقم بتصفيتها لتحديد المنتجات التابعة لشركة "$targetCompany" فقط وجمع أسعارها.';

      String catalogCondition = '';
      if (registeredBarcodes.isNotEmpty) {
        if (registeredBarcodes.length <= 25) {
          catalogCondition =
              'قائمة كروت منتجات/باركودات الشركة المعتمدة: ${registeredBarcodes.join(", ")}.';
        } else {
          catalogCondition =
              'العرض يشمل كافة منتجات وباركودات شركة "$targetCompany" المعتمدة (إجمالي ${registeredBarcodes.length} صنف مسجل بالكتالوج). ابحث عن أي منتج تابع للعلامة التجارية.';
        }
      }

      final resolvedSubBrands = CampaignAiAssistantService.resolveCompanySubBrands(
        targetCompany,
        productNames: resolvedRequiredProducts,
      );
      String subBrandsCondition = '';
      if (resolvedSubBrands.isNotEmpty) {
        subBrandsCondition = '''
🏷️ حوكمة تفكيك وتوريث العلامات التجارية الفرعية للشركة الراعية (Umbrella Sub-Brands Inheritance - AIR-59):
- نظراً لأن أنظمة الكاشير (POS) في السوبرماركت تطبع أسماء الماركات والعلامات الفرعية فقط دون اسم الشركة القابضة "$targetCompany":
- العلامات والماركات التجارية المعتمدة التابعة لشركة "$targetCompany" في هذه الحملة تشمل صراحةً:
  [${resolvedSubBrands.join("، ")}]
- ⚠️ إلزام قطعي لنموذج الذكاء الاصطناعي: أي صنف بالفاتورة يتبع أياً من هذه العلامات المعتمدة (مثال: صابون أو سائل أو شامبو أو مسحوق أو مناديل يحمل اسماً من القائمة أعلاه مثل: ${resolvedSubBrands.take(3).join("، ")}) هو صنف شرعي وأصيل ومعتمد لشركة "$targetCompany" بنسبة 100% (عيّن: isTargetCompany = true)، ويجب إدراجه فوراً في (extractedProducts) وجمع قيمته في (targetCompanyTotal) وتطبيق قواعد العروض الترويجية والجوائز ومضاعفات الفرص عليه دون أي استبعاد.
''';
      }

      String promotionalRulesCondition = '';
      if (promotionalRules.isNotEmpty) {
        final rulesListFormatted = promotionalRules
            .asMap()
            .entries
            .map((entry) {
              final idx = entry.key + 1;
              final r = entry.value;
              final id = r.id.isNotEmpty ? r.id : 'rule_$idx';
              final multText = r.allowMultipliers
                  ? ' (تتضاعف الهدايا مع زيادة الكمية)'
                  : '';
              final voucherVal = r.totalVoucherValue > 0
                  ? ' [قيمة نقدية: ${r.totalVoucherValue.toInt()} ج.م]'
                  : (r.rewardAmount > 0
                        ? ' [قيمة نقدية: ${r.rewardAmount.toInt()} ج.م]'
                        : '');
              String conditionDetails;
              if (r.isSpendBased) {
                final minVal = r.effectiveMinSpend > 0
                    ? r.effectiveMinSpend.toInt()
                    : r.minSpend.toInt();
                final tolText = r.discountTolerance > 0
                    ? ' (سماحية خصم ${r.discountTolerance.toInt()} ج.م، أي تقبل الفاتورة بمشتريات صافية $minVal ج.م أو أكثر)'
                    : '';
                if (r.isCombo && r.requiredBrands.isNotEmpty) {
                  conditionDetails =
                      'شراء بقيمة إجمالية ($minVal ج.م$tolText) أو أكثر تشمل منتجات (${r.requiredBrands.join(" و ")}) معاً من أصناف [${r.triggerProduct}]';
                } else if (r.hasSpendRange &&
                    r.maxSpend != null &&
                    r.maxSpend! > r.minSpend) {
                  conditionDetails =
                      'إنفاق في النطاق من ($minVal ج.م$tolText) حتى (${r.maxSpend!.toInt()} ج.م) من أصناف [${r.triggerProduct}]';
                } else {
                  conditionDetails =
                      'إنفاق بقيمة ($minVal ج.م$tolText) أو أكثر من أصناف [${r.triggerProduct}]';
                }
              } else {
                conditionDetails =
                    'شراء (${r.minQuantity}) أو أكثر من [${r.triggerProduct}]';
              }
              return '$idx. [معرف ID: "$id"] "${r.ruleTitle}" ➔ الشرط: $conditionDetails ➔ الجائزة المستحقة: [${r.rewardValue}$voucherVal] (نوع: ${r.rewardType})$multText';
            })
            .join('\n');

        final bool isUnileverOrPersonalCare = targetCompany.toLowerCase().contains('unilever') ||
            targetCompany.contains('يونيليفر') ||
            promotionalRules.any((r) =>
                r.ruleTitle.contains('ريكسونا') ||
                r.ruleTitle.contains('تريزيمي') ||
                r.ruleTitle.contains('كلير') ||
                r.ruleTitle.contains('أكس') ||
                r.ruleTitle.contains('اكس') ||
                r.ruleTitle.contains('رول') ||
                r.ruleTitle.contains('اسبراي') ||
                r.triggerProduct.contains('ريكسونا') ||
                r.triggerProduct.contains('تريزيمي') ||
                r.triggerProduct.contains('كلير') ||
                r.triggerProduct.contains('أكس') ||
                r.triggerProduct.contains('اكس'));

        String categoryPackagingGuard = '';
        if (isUnileverOrPersonalCare) {
          categoryPackagingGuard = '''
1. [حارس العزل الصارم للشكل الفيزيائي للعبوة (Physical Packaging & Form Guard)]:
   - **الرول أون (Roll-on / Stick بحجم 50 مل)**: أي صنف رول أون / روول / ستيك (مثل "ريكسونا رول اون" أو "اكس رول اون" 50 مل) يطابق **حصراً** قواعد الرول أون المعتمدة (مثل شراء 2 رول أون -> فواتشر 50 ج.م)، ويُحظر تماماً ومطلقاً مطابقته مع أي قاعدة تخص الاسبراي (مثل عروض الـ 125 ج.م للقطعتين) حتى لو تضمنت كلمات القاعدة اسم "ريكسونا" أو "أكس" أو "حريمي" أو "رجالي".
   - **الاسبراي (Aerosol Bodyspray بحجم 150 مل)**: أي صنف اسبراي / بخاخ مزيل عرق يطابق **حصراً** عروض الاسبراي (فواتشر 50 ج.م للقطعة أو 125 ج.م للقطعتين/الشرنك المزدوج)، ويُحظر من مطابقة عروض الرول أون.
   - **الشامبو والبلسم (400 مل و 360 مل)**: عبوات تريزيمي 400 مل تطابق حصراً عروض تريزيمي (2 قطعة -> هدية 250 مل). عبوات كلير 360 مل تطابق حصراً عروض كلير (1 قطعة -> هدية 90 مل).
   - **معجون الأسنان والمنتجات المستبعدة**: أي منتج معجون أسنان (مثل سنسوداين أو سيجنال غير مشروط) أو منظفات (مثل كلوركس) يُستبعد كلياً ولا يُمنح أي هدايا.
   - **حزم البندل المزدوجة والشرنك (Twin Bundles)**: إذا احتوت الفاتورة على صنف حزمة مزدوجة أو شرنك (مثل عبوة أكس 2 قطعة أو سعر 335 ج.م بصافي 270 ج.م، أو ريكسونا 150 مل 275 ج.م، أو تريزيمي شامبو+بلسم 400 مل كود 6221155612182، أو صانسيلك شامبو+بلسم 350 مل كود 6221155611154 بسعر 184 ج.م، أو أي صنف يتضمن شامبو + بلسم معاً في نفس السطر)، يُعامل الصنف كـ (2 قطعة فيزيائية) ويطابق فوراً قاعدة الـ 2 قطعة وتمنح الجائزة المقررة مباشرة حتى لو طُبعت الكمية = 1 في بون الكاشير.
   - **حظر مضاعفة العبوات الفردية الكبيرة (Single Large Bottle Invariant - AIR-63)**: العبوات الفردية الكبيرة (بحجم 600 مل، 700 مل، 900 مل، 1 لتر، مثل "تريزيمي شامبو 600مل" أو "كلير 600مل" أو "صانسيلك 700مل") هي عبوات فردية عادية تباع بسعر مرتفع بطبيعتها (200-350 ج.م للعبوة الواحدة). يُحظر تماماً معاملتها كحزم مزدوجة أو مضاعفة كميتها (quantity) بناءً على سعرها المرتفع طالما لم يذكر في سطر الصنف صراحة أنه عرض مزدوج (مثل "شامبو + بلسم" أو "عرض 2ق" أو "باندل"). شراء 1 عبوة 600 مل = 1 قطعة فقط وتمنح فرصة/هدية واحدة فقط.
''';
        } else {
          categoryPackagingGuard = '''
1. [حوكمة أصناف وسلات شركة "$targetCompany" والعزل التام]:
   - كافة الأصناف المشتراة التابعة لشركة "$targetCompany" (سواء ألبان، زبادي، حليب، أجبان، عصائر، بقوليات، إلخ) والمشمولة بشروط العرض تُدرج في (extractedProducts) وتحسب في (targetCompanyTotal).
   - في عروض الإنفاق الإجمالي (by_spend): يُحسب إجمالي صافي الإنفاق لمنتجات شركة "$targetCompany" لمقارنته بالحد الأدنى المطلوب.
''';
        }

        promotionalRulesCondition =
            '''
- محرك القواعد والعروض الترويجية والجوائز المعتمدة (Promotional Rules Engine):
$rulesListFormatted

⚠️ تعليمات مطابقة القواعد الترويجية والعزل الصارم للشركات والعلامات (Strict Dynamic Rules & Tenant Isolation):
$categoryPackagingGuard
2. افحص بدقة أسماء الأصناف في الفاتورة مع مراعاة كافة الاختلافات الإملائية والطباعية في بونات الكاشير.
3. [تجميع العروض المتزامنة (Multi-Offer Bundling)]: إذا اشترى العميل أصنافاً تحقق أكثر من عرض ترويجي مختلف في نفس الفاتورة، قم بتضمين كافة معرفات القواعد المطابقة في حقل (matchedRuleIds) كقائمة (مثل: ["rule_3", "rule_5"])، وجمع إجمالي قيمة المكافآت المستحقة في (matchedRewardAmount)، وكتابة ملخص الجوائز في (matchedRewardValue).
4. [الهدية الأعلى قيمة أولاً]: إذا انطبقت أكثر من قاعدة على نفس المنتجات أو نفس مبلغ الإنفاق، ابدأ بالقاعدة ذات الهدية الأعلى قيمة (الفواتشر بقيمته النقدية، والهدية العينية بقيمتها في الكتالوج، والهدية بدون قيمة تأتي بعدها مرتبة بالمستوى الأعلى). امنحها ثم اخصم المبلغ الذي استخدمته، ولا تُمنح القاعدة الأقل إلا من المبلغ المتبقي فقط. لا تجمع أبداً هدية أقل على نفس المبلغ (مثال: 627 ج.م مع قواعد 450 و350 و150 = فواتشر قاعدة 450 مرة واحدة + هدية قاعدة 150 مرة واحدة من الباقي 177، وليس 4 × هدية قاعدة 150).
5. [مضاعفة الجوائز والفرص]: إذا كانت القاعدة تتيح المضاعفة، احسب عدد مرات تكرار العرض من المبلغ أو الكمية المتاحة لها فقط (بعد خصم ما استخدمته القواعد الأعلى قيمة) واضرب المكافأة بعدد المرات.
6. قم بتعبئة حقل (matchedRuleId) بمعرف القاعدة المطابقة الأولى، و(matchedRuleTitle) بعنوان القاعدة، و(matchedRewardType) بنوع المكافأة.
7. [العزل الصارم للأصناف واستهلاك الكميات]: كل صنف يطابق قاعدة علامته التجارية والشركة الراعية فقط، وتُخصم الكمية المستهلكة فوراً من السلة لمنع احتساب نفس القطعة في أكثر من عرض.
8. إذا لم تنطبق أي من هذه القواعد، اترك حقل (matchedRuleId) فارغاً "" وحقل (matchedRuleIds) كقائمة فارغة [].
''';
      }

      String branchSignaturesText = '';
      if (registeredBranches.isNotEmpty) {
        final sigsList = registeredBranches
            .map((b) {
              final s = b.receiptSignature;
              final codePart = b.branchCode.isNotEmpty
                  ? 'كود: "${b.branchCode}", '
                  : '';
              final cityPart = b.city.isNotEmpty
                  ? 'المدينة: "${b.city}", '
                  : '';
              final addrPart = b.address.isNotEmpty
                  ? 'العنوان: "${b.address}", '
                  : '';
              String sigPart = '';
              if (s != null && s.hasSignature) {
                sigPart =
                    'Store ID: "${s.storeId}", نسق الفاتورة/الباركود: "${s.receiptPattern}", نسق الـ POS: "${s.posNumberPattern}", الرقم الضريبي: "${s.taxNumber}", الهاتف: "${s.hotline}", كلمات الرأس: ${s.headerKeywords.join("/")}';
              }
              return '  * فرع "${b.branchName}" (${b.retailChainName}): [$codePart$cityPart$addrPart$sigPart]';
            })
            .join('\n');
        branchSignaturesText =
            '''
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
        final chainList = retailChainName
            .split(RegExp(r'[\•\,\،\/\-\|\+]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        final chainClarification = chainList.length > 1
            ? 'تشمل أياً من السلاسل الآتية: [${chainList.join(" أو ")}] (أي فاتورة صادرة من أي سلسلة من هذه السلاسل معتمدة ومشمولة بالكامل، ويُحظر اعتبارها سلسلة غير مشمولة)'
            : '"$retailChainName"';

        if (!isAllBranches && allowedBranches.isNotEmpty) {
          branchCondition =
              '''
- السلسلة/السلاسل المعتمدة للحملة: $chainClarification.
- الفروع المعتمدة حصراً لهذا العرض: [${allowedBranches.join("، ")}].
- المطلوب للفرع والسلسلة: افحص رأس الفاتورة وكود المتجر (Store ID / POS) بدقة واستخرج اسم السلسلة في (storeChainDetected) واسم الفرع أو عنوانه أو رقمه في (branchDetected). إذا كانت الفاتورة صادرة من أحد الفروع المعتمدة المذكورة أعلاه أو تحمل كود المتجر لفرع معتمد، حدد (isBranchMatched = true). إذا كانت الفاتورة تابعة لأيٍّ من السلاسل المعتمدة المذكورة أعلاه (${chainList.join(" أو ")}), فلا تعتبرها أبداً سلسلة غير مشمولة بل حدد (isBranchMatched = true) طالما الفرع أو كود المتجر معتمد.
$branchSignaturesText
''';
        } else {
          branchCondition =
              '''
- السلسلة/السلاسل المعتمدة للحملة: $chainClarification (كافة الفروع مشمولة).
- المطلوب للفرع: استخرج اسم السلسلة في (storeChainDetected) والفرع في (branchDetected)، وحدد (isBranchMatched = true) إذا كانت تابعة لأيٍّ من هذه السلاسل المعتمدة.
$branchSignaturesText
''';
        }
      } else if (branchSignaturesText.isNotEmpty) {
        branchCondition = branchSignaturesText;
      }

      String chancesCondition = '';
      if (allowMultipleChances) {
        final maxCapText = maxChancesPerReceipt > 0
            ? ' بحد أقصى $maxChancesPerReceipt بالفاتورة الواحدة'
            : '';
        if (multiplierBasis == 'quantity') {
          chancesCondition =
              '''
- مضاعفة الجوائز والفرص بناءً على كميات المنتجات: تتضاعف الجوائز والفرص طردياً مع تكرار ومضاعفة كمية المنتج المشروط بالفاتورة (مثال: شراء 1 قطعة = 1 هدية/فرصة، شراء 2 قطعة = 2 هدية/فرصتان، شراء 3 قطع = 3 هدايا/فرص)$maxCapText.
''';
        } else if (multiplierBasis == 'spend') {
          chancesCondition =
              '''
- مضاعفة فرص السحب واللعب بناءً على المبلغ: الحد الأدنى المطلوب هو $minimumSpend ج.م. كل مضاعف لهذا المبلغ من منتجات الشركة يمنح العميل فرصة إضافية$maxCapText.
''';
        } else {
          chancesCondition =
              '''
- مضاعفة الجوائز والفرص: تتضاعف الجوائز الفورية بمضاعفة كميات الأصناف المشروطة، وتتضاعف فرص السحب بمضاعفة قيمة الشراء ($minimumSpend ج.م)$maxCapText.
''';
        }
      }

      final String antiFraudMultiReceiptRule = allowComplementaryReceipts
          ? '- [بونات التكملة المتعددة في كادر واحد جنباً إلى جنب]: إذا احتوت الصورة على بونين كاشير مطبوعين إلكترونياً جنباً إلى جنب لنفس السوبرماركت واليوم لتكملة القيمة (أحدهما بون أساسي والآخر بون تكميلي مثل مدون عليه "تكملة الفاتورة"): استخرج رقمي البونين مدمجين بفاصل " + " في (receiptNumber) (مثال: "64/6/241/250926 + 109/8/241/250926")، واجمع كافة أصناف الشركة الراعية المؤهلة من كلا البونين في (extractedProducts)، واحسب إجمالي مجموع قيمتهما المشترك في (targetCompanyTotal) (مثال: 751.00 + 55.00 = 806.00 ج.م)، وطبّق العرض ومضاعفات الجوائز على الإجمالي التراكمي.'
          : '''- [معيار نزاهة واستقلالية الفاتورة الواحدة وحظر دمج البونات المنفصلة - AIR-61]:
  * يُحظر تماماً دمج أو جمع أكثر من بون كاشير منفصل (سواء تم تصويرهما جنباً إلى جنب في كادر واحد أو تم رفعهما كأجزاء منفصلة) لتجميع القيمة أو الوصول للحد الأدنى للإنفاق.
  * كل مطالبة أو معاملة يجب أن تستند إلى [فاتورة كاشير واحدة مستقلة بذاتها] برأس واحدة ورقم فاتورة واحد وتاريخ وتوقيت واحد وإجمالي واحد.
  * إذا ظهر في الصورة أو المرفقات أكثر من بون كاشير بأرقام مختلفة أو توقيتات مختلفة: عيّن فوراً isValid = false، ولا تجمع قيمهما، ولا تضع فاصل "+" في رقم الفاتورة، واكتب في (unfulfilledConditions): ["مخالفة معايير الأهلية: تم رصد محاولة دمج بونات شراء منفصلة ذات أرقام أو توقيتات مختلفة في معاملة واحدة. يشترط النظام استيفاء شروط العرض في فاتورة شراء واحدة مستقلة."]
  * الاستثناء الوحيد للصور المتعددة هو: التقاط [أجزاء متتابعة لنفس الفاتورة الفيزيائية الواحدة الطويلة] التي لا يتسع لها كادر الكاميرا، مع التطابق التام لرقم الفاتورة والفرع والتوقيت ومنع تكرار السطور المتداخلة (Cross-Seam Deduplication).''';

      String finalPromptText;
      if (customPrompt.trim().isNotEmpty) {
        String processedPrompt = customPrompt
            .replaceAll('{TARGET_COMPANY}', targetCompany)
            .replaceAll('{REQUIRED_PRODUCTS}', requiredProducts.join(", "))
            .replaceAll('{RETAIL_CHAIN}', retailChainName)
            .replaceAll('{BRANCHES}', allowedBranches.join(", "));

        if (minimumSpend > 0) {
          processedPrompt = processedPrompt.replaceAll(
            '{MIN_SPEND}',
            minimumSpend.toString(),
          );
        } else {
          // If no minimum spend is configured, clean up any {MIN_SPEND} clauses gracefully
          processedPrompt = processedPrompt
              .replaceAll(
                RegExp(
                  r'\n?-?\s*إجمالي المنتجات يجب أن يلبي الحد الأدنى\s*\{MIN_SPEND\}[^\n]*',
                ),
                '',
              )
              .replaceAll('{MIN_SPEND}', '0');
        }
        finalPromptText = processedPrompt;

        finalPromptText +=
            '''

تنبيهات إضافية هامة جداً:
1. ابحث عن تاريخ الشراء (Date / التاريخ) بالفاتورة واستخرجه بوضوح في حقل receiptDate (مثال: 22/07/2026).
2. استخرج رقم الفاتورة أو Transaction ID أو كود العملية من رأس الفاتورة في حقل receiptNumber (مثال: TP0001000420897 أو 07611-019260005484 أو 120001000420897). إياك واستخراج رقم البطاقة الضريبية (ب.ض / Tax ID) أو السجل التجاري (س.ت / CR) كرقم للفاتورة.
3. استخرج اسم السلسلة والفرع من رأس الفاتورة بدقة.
$branchCondition
$catalogCondition
$productsCondition
$promotionalRulesCondition
$chancesCondition$multiPartInstructions

$subBrandsCondition
🛑 حوكمة العزل الحصري لعلامات الشركة الراعية والسلع الزراعية (AIR-71 & AIR-87):
- الفاتورة يتم تدقيقها حصرياً لصالح شركة: "$targetCompany".
- أي منتج بالفاتورة يتبع علامة تجارية أو شركة منافسة أو غير تابعة لـ "$targetCompany" (مثلاً: إذا كانت الشركة الراعية المراعي، فلا تحتسب منتجات جهينة أو لمار؛ وإذا كانت الراعية الدرة، فلا تحتسب هاينز أو قودي أو هارفست أو فاين فودز) يجب فوراً تعيينه: isTargetCompany = false واستبعاده كلياً من targetCompanyTotal ومن أي عرض ترويجي.
- 🛑 استبعاد الحبوب الزراعية والعطارة والفشار وأرز الشركات المستقلة (AIR-87):
  * شركة "الدرة" (Al-Durra / Dorra) هي شركة منتجات غذائية معبأة (صلصة، كاتشب، مايونيز، صصوصات، خل، مخلل، مربى، طحينة). يُحظر تماماً وبصرامة احتساب أي حبوب زراعية أو بهارات أو عطارة تحمل كلمة "ذرة" أو "درة" (مثل: "درة أم شوشة"، "ذرة أم شوشة"، "ذرة فشار"، "درة فشار"، "ذرة حب"، "فشار"، "بهارات"، "عطارة") كمنتج للدرة، ويجب تعيين isTargetCompany = false واستبعادها كلياً.
  * يُحظر تماماً على الذكاء الاصطناعي تخمين أو استبدال ماركات الأرز المطبوعة على الفاتورة (Zero-Hallucination)؛ فإذا كان الصنف المطبوع هو "الفراعنة ارز" أو "أرز الفراعنة" أو "أرز الساعة" أو "أرز ريحانة"، يجب نقله كما هو باسمه الحقيقي مع تعيين isTargetCompany = false لعدم تبعيته للدرة، ويُمنع منعاً باتاً تسميته "الدرة ارز".
- 🛑 قاعدة أصناف المالتي باك والشوكولاتة العامة (AIR-71): إذا كان الصنف يحمل اسماً عاماً مثل "مالتي باك شوكولات" أو "مالتي باك شوكولاتة" دون ذكر صريح لماركة معتمدة تابعة لـ "$targetCompany"، يُحظر كلياً اعتباره تابعاً للشركة الراعية ويجب تعيين isTargetCompany = false.
- الأصناف المشروعة في (extractedProducts) مع (isTargetCompany = true) هي فقط الأصناف التابعة لشركة "$targetCompany".

🛑 استراتيجية الفلترة الموجهة والمسح السريع الفائق (Targeted Fast-Scan Strategy):
- ركز فورياً على رأس الفاتورة (Header) لاستخراج السلسلة والفرع وتاريخ الشراء ورقم الفاتورة.
- عند قراءة أسطر المشتريات: ركز حصراً على أسطر منتجات وععلامات شركة "$targetCompany" المشروطة، وتجاهل أي أسطر عامة أخرى (كاللحوم والخضار والفاكهة والمخبوزات والمنظفات غير التابعة) ولا تدرجها في extractedProducts، وذلك لتسريع الاستجابة والتركيز على منتجات العرض فقط.

🛑 تعليمات مكافحة التزوير والرفض الأمني (Anti-Fraud & Genuine Receipt Policy):
- [بون الكاشير الإلكتروني]: الفواتير المقبولة فقط (isValid = true) هي بونات الكاشير الحرارية أو الإلكترونية المطبوعة آلياً من أنظمة ونقاط البيع المعتمدة (Thermal POS Receipts).
- [ملاحظات وهوامش البروموتر/الكاشير]: إذا كان أصل الفاتورة بون كاشير مطبوع إلكترونياً، وتوجد عليه كتابة يدوية في الهوامش أو الرأس مثل "تم تسليم الهدية" أو "تكملة الفاتورة" أو "تم استلام 2 فوتشر" أو توقيع أو علامة استلام أو رقم تليفون أو علامات صح، فهذا بون كاشير أصلي معتمد وسليم (isThermalPosReceipt = true و isHandwritten = false و isTampered = false) ويجب قبوله.
$antiFraudMultiReceiptRule
- [كشف الفواتير المحررة يدوياً]: إذا كانت الفاتورة نفسها مسودة أو محررة بالكامل في دفتر يدوي وبنودها وأسعارها مكتوبة باليد، عيّن isHandwritten = true و isThermalPosReceipt = false و isValid = false واكتب رسالة رفض واضحة: "عذراً، تم رفض الفاتورة لأنها محررة بخط اليد. العرض يشترط بون كاشير مطبوع إلكترونياً من ماكينة السوبرماركت."
- [كشف الشطب والتلاعب في الأرقام]: إذا وجد شطب أو تلاعب وتعديل يدوي في أرقام وأسعار الأصناف المطبوعة لتغيير قيمتها، عيّن isTampered = true و isValid = false.
- [كشف تصوير الشاشات]: إذا كانت الصورة ملتقطة لشاشة هاتف أو حاسوب، عيّن isScreenCapture = true و isValid = false.

⚠️ تعليمات استخراج أسعار الأصناف والكميات والخصومات بدقة (Strict Unit Price & Discount Rules):
- يجب أن يحتوي حقل (price) دائماً على سعر بيع القطعة الواحدة فقط (Unit Price).
- [محاذاة السطور والباركود والكمية الحسابية - POS Row Alignment & AIR-26]:
  * في بونات السوبرماركت (خاصة جملة ماركت وفتح الله وكارفور)، تقع الكمية وسعر الوحدة والباركود على نفس السطر الأفقي للصنف تماماً: [القيمة] [السعر] [الكمية] [الصنف والباركود].
  * احذر بشدة من قراءة كمية من السطر الذي يعلو أو يلي سطر الصنف! (مثلاً: إذا كان السطر السابق يحتوي على كمية 3 وسعر 3.33 وإجمالي 10.00، والسطر الحالي هو "(كلير شامبو رجالى 360مل (وفر JR)" بسعر 134.00 وإجمالي 134.00 وكمية 1 وباركود 6221155210517، فالكمية حتماً 1 قطعة فقط).
  * تحقق دائماً من المعادلة: الكمية = إجمالي السطر ÷ سعر الوحدة. إذا كان الإجمالي 134.00 والسعر 134.00 فالكمية = 1 وتمنح 1 هدية كلير 90 مل.
- إذا اشترى العميل كمية (quantity = 2 أو أكثر)، وكان المطبوع في الفاتورة هو إجمالي السطر (مثل 2 × 115 = 230 أو 198 بعد الخصم)، فيجب وضع سعر القطعة الصافي في (price) = 99.0 ج.م، وسعر القطعة الأصلي في (originalPrice) = 115.0 ج.م، وقيمة الخصم للقطعة الواحدة في (discountAmount) = 16.0 ج.م، وإجمالي السطر في (totalLinePrice) = 198.0 ج.م.
- إياك أن تضع إجمالي السطر كسعر للقطعة في حقل price عند وجود كمية أكبر من 1!

تأكد من إرجاع النتيجة بصيغة JSON المحتوي على الحقول المفروضة:
isValid (boolean), receiptNumber (string), targetCompanyTotal (number), receiptDate (string), storeChainDetected (string), branchDetected (string), isBranchMatched (boolean), isHandwritten (boolean), isThermalPosReceipt (boolean), isTampered (boolean), isScreenCapture (boolean), chancesEarned (integer), message (string).
''';
      } else {
        finalPromptText =
            '''
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
        8. $chancesCondition$multiPartInstructions
        
        $subBrandsCondition
        🛑 حوكمة العزل الحصري لعلامات الشركة الراعية والسلع الزراعية (AIR-71 & AIR-87):
        - الفاتورة يتم تدقيقها حصرياً لصالح شركة: "$targetCompany".
        - أي منتج بالفاتورة يتبع علامة تجارية أو شركة منافسة أو غير تابعة لـ "$targetCompany" (مثلاً: إذا كانت الشركة الراعية المراعي، فلا تحتسب منتجات جهينة أو لمار؛ وإذا كانت الراعية الدرة، فلا تحتسب هاينز أو قودي أو هارفست أو فاين فودز) يجب فوراً تعيينه: isTargetCompany = false واستبعاده كلياً من targetCompanyTotal ومن أي عرض ترويجي.
        - 🛑 استبعاد الحبوب الزراعية والعطارة والفشار وأرز الشركات المستقلة (AIR-87):
          * شركة "الدرة" (Al-Durra / Dorra) هي شركة منتجات غذائية معبأة (صلصة، كاتشب، مايونيز، صوصات، خل، مخلل، مربى، طحينة). يُحظر تماماً وبصرامة احتساب أي حبوب زراعية أو بهارات أو عطارة تحمل كلمة "ذرة" أو "درة" (مثل: "درة أم شوشة"، "ذرة أم شوشة"، "ذرة فشار"، "درة فشار"، "ذرة حب"، "فشار"، "بهارات"، "عطارة") كمنتج للدرة، ويجب تعيين isTargetCompany = false واستبعادها كلياً.
          * يُحظر تماماً على الذكاء الاصطناعي تخمين أو استبدال ماركات الأرز المطبوعة على الفاتورة (Zero-Hallucination)؛ فإذا كان الصنف المطبوع هو "الفراعنة ارز" أو "أرز الفراعنة" أو "أرز الساعة" أو "أرز ريحانة"، يجب نقله كما هو باسمه الحقيقي مع تعيين isTargetCompany = false لعدم تبعيته للدرة، ويُمنع منعاً باتاً تسميته "الدرة ارز".
        - الأصناف المشروعة في (extractedProducts) مع (isTargetCompany = true) هي فقط الأصناف التابعة لشركة "$targetCompany".

        🛑 استراتيجية الفلترة الموجهة والمسح السريع الفائق (Targeted Fast-Scan Strategy):
        - ركز فورياً على رأس الفاتورة (Header) لاستخراج السلسلة والفرع وتاريخ الشراء ورقم الفاتورة.
        - عند قراءة أسطر المشتريات: ركز حصراً على أسطر منتجات وعلامات شركة "$targetCompany" المشروطة، وتجاهل أي أسطر عامة أخرى (كاللحوم والخضار والفاكهة والمخبوزات والمنظفات غير التابعة) ولا تدرجها في extractedProducts، وذلك لتسريع الاستجابة والتركيز على منتجات العرض فقط.
        
        🛑 تعليمات مكافحة التزوير والرفض الأمني (Anti-Fraud & Genuine Receipt Policy):
        - [بون الكاشير الإلكتروني]: الفواتير المقبولة فقط (isValid = true) هي بونات الكاشير الحرارية أو الإلكترونية المطبوعة آلياً من أنظمة ونقاط البيع المعتمدة (Thermal POS Receipts).
        - [ملاحظات وهوامش البروموتر/الكاشير]: إذا كان أصل الفاتورة بون كاشير مطبوع إلكترونياً، وتوجد عليه كتابة يدوية في الهوامش أو الرأس مثل "تم تسليم الهدية" أو "تكملة الفاتورة" أو "تم استلام 2 فوتشر" أو توقيع أو علامة استلام أو رقم تليفون أو علامات صح، فهذا بون كاشير أصلي معتمد وسليم (isThermalPosReceipt = true و isHandwritten = false و isTampered = false) ويجب قبوله.
        $antiFraudMultiReceiptRule
        - [كشف الفواتير المحررة يدوياً]: إذا كانت الفاتورة نفسها مسودة أو محررة بالكامل في دفتر يدوي وبنودها وأسعارها مكتوبة باليد، عيّن isHandwritten = true و isThermalPosReceipt = false و isValid = false واكتب رسالة رفض واضحة: "عذراً، تم رفض الفاتورة لأنها محررة بخط اليد. العرض يشترط بون كاشير مطبوع إلكترونياً من ماكينة السوبرماركت."
        - [كشف الشطب والتلاعب في الأرقام]: إذا وجد شطب أو تلاعب وتعديل يدوي في أرقام وأسعار الأصناف المطبوعة لتغيير قيمتها، عيّن isTampered = true و isValid = false.
        - [كشف تصوير الشاشات]: إذا كانت الصورة ملتقطة لشاشة هاتف أو حاسوب، عيّن isScreenCapture = true و isValid = false.
        
        ⚠️ تعليمات استخراج أسعار الأصناف والكميات والخصومات بدقة (Strict Unit Price & Discount Rules):
        - يجب أن يحتوي حقل (price) دائماً على سعر بيع القطعة الواحدة فقط (Unit Price).
        - [محاذاة السطور والباركود والكمية الحسابية - POS Row Alignment & AIR-26]:
          * في بونات السوبرماركت (خاصة جملة ماركت وفتح الله وكارفور)، تقع الكمية وسعر الوحدة والباركود على نفس السطر الأفقي للصنف تماماً: [القيمة] [السعر] [الكمية] [الصنف والباركود].
          * احذر بشدة من قراءة كمية من السطر الذي يعلو أو يلي سطر الصنف! (مثلاً: إذا كان السطر السابق يحتوي على كمية 3 وسعر 3.33 وإجمالي 10.00، والسطر الحالي هو "(كلير شامبو رجالى 360مل (وفر JR)" بسعر 134.00 وإجمالي 134.00 وكمية 1 وباركود 6221155210517، فالكمية حتماً 1 قطعة فقط).
          * تحقق دائماً من المعادلة: الكمية = إجمالي السطر ÷ سعر الوحدة. إذا كان الإجمالي 134.00 والسعر 134.00 فالكمية = 1 وتمنح 1 هدية كلير 90 مل.
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

      final aiStopwatch = Stopwatch()..start();
      CloudGenerateContentResponse response;
      final targetModel = forceDeepAudit ? _deepAuditModel : _fastModel;
      final primaryFallback = forceDeepAudit ? _model : _fallbackModel1;
      final contentParts = [
        Content.multi([prompt, ...allImageParts]),
      ];

      try {
        response = await _executeWithExponentialBackoff(targetModel, contentParts);
      } catch (e1) {
        debugPrint('⚠️ [AiReceiptService] Primary model failed: $e1. Escalating to primary fallback...');
        try {
          response = await _executeWithExponentialBackoff(primaryFallback, contentParts);
        } catch (e2) {
          debugPrint('⚠️ [AiReceiptService] Primary fallback failed: $e2. Escalating to secondary fallback...');
          response = await _executeWithExponentialBackoff(_fallbackModel2, contentParts);
        }
      }
      aiStopwatch.stop();
      int aiDurationMs = aiStopwatch.elapsedMilliseconds;
      String pipelineTier = forceDeepAudit ? 'deep_reasoning_tier' : 'fast_tier';

      if (response.text != null && response.text!.trim().isNotEmpty) {
        final dartStopwatch = Stopwatch()..start();
        final Map<String, dynamic> jsonMap = _cleanAndParseJson(response.text!);
        var result = AiReceiptAnalysisResult.fromJson(
          jsonMap,
          durationMs: stopwatch.elapsedMilliseconds,
          targetCompany: targetCompany,
          targetBrands: resolvedRequiredProducts,
        );

        // 🛑 Strict Dart Anti-Fraud Gatekeeper
        if (result.isHandwritten ||
            !result.isThermalPosReceipt ||
            result.isTampered ||
            result.isScreenCapture) {
          final List<String> reasons = List<String>.from(
            result.unfulfilledConditions,
          );
          String fraudMsg = '';
          if (result.isHandwritten) {
            fraudMsg =
                'عذراً، تم رفض الفاتورة لأنها محررة بخط اليد. العرض يشترط حصراً بون كاشير مطبوع إلكترونياً من ماكينة السوبرماركت.';
            if (!reasons.contains(
              'فاتورة محررة يدوياً وغير مطبوعة إلكترونياً من الكاشير',
            )) {
              reasons.insert(
                0,
                'فاتورة محررة يدوياً وغير مطبوعة إلكترونياً من الكاشير',
              );
            }
          } else if (result.isTampered) {
            fraudMsg =
                'عذراً، تم رفض الفاتورة لوجود اشتباه في تلاعب أو شطب وتعديل يدوي في الأرقام والأسعار.';
            if (!reasons.contains('اشتباه في تلاعب أو تعديل يدوي للأرقام')) {
              reasons.insert(0, 'اشتباه في تلاعب أو تعديل يدوي للأرقام');
            }
          } else if (result.isScreenCapture) {
            fraudMsg =
                'عذراً، تم رفض الصورة لأنها ملتقطة من شاشة إلكترونية. يرجى تصوير أصل الفاتورة الورقية المطبوعة مباشرة.';
            if (!reasons.contains('صورة ملتقطة من شاشة إلكترونية')) {
              reasons.insert(0, 'صورة ملتقطة من شاشة إلكترونية');
            }
          } else if (!result.isThermalPosReceipt) {
            fraudMsg =
                'عذراً، المستند المرفق ليس بون كاشير إلكتروني مطبوع معتمد.';
            if (!reasons.contains(
              'المستند المرفق ليس بون كاشير إلكتروني معتمد',
            )) {
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

        // 🛑 Strict Dart Anti-Fraud & Single-Receipt Integrity Gatekeeper (AIR-61)
        if (!allowComplementaryReceipts) {
          final rawReceiptNum = result.receiptNumber.trim();
          final hasMultiReceiptDelimiter = rawReceiptNum.contains('+') ||
              rawReceiptNum.contains(' + ') ||
              rawReceiptNum.contains(' و ') ||
              rawReceiptNum.contains(' AND ') ||
              rawReceiptNum.contains(' and ');

          final hasMultiReceiptInMessage = result.message.contains('بونين') ||
              result.message.contains('بونات مدمجة') ||
              result.message.contains('فاتورتين') ||
              result.message.contains('بون تكميلي') ||
              result.message.contains('تكملة الفاتورة');

          final hasMultiReceiptViolation = result.unfulfilledConditions.any(
            (c) => c.contains('دمج بونات') || c.contains('بونات شراء منفصلة') || c.contains('فاتورة واحدة مستقلة'),
          );

          if (hasMultiReceiptDelimiter || (hasMultiReceiptInMessage && result.isValid) || hasMultiReceiptViolation) {
            final List<String> reasons = List<String>.from(result.unfulfilledConditions);
            const violationReason = 'مخالفة معايير الأهلية: تم رصد محاولة دمج بونات شراء منفصلة ذات أرقام أو توقيتات مختلفة في معاملة واحدة. يشترط النظام استيفاء شروط العرض في فاتورة شراء واحدة مستقلة.';
            if (!reasons.contains(violationReason)) {
              reasons.insert(0, violationReason);
            }

            result = result.copyWith(
              isValid: false,
              chancesEarned: 0,
              message: 'عذراً، تم رفض العملية: غير مسموح بدمج أو تجميع أكثر من بون شراء منفصل لاستيفاء قيمة العرض. يشترط النظام استيفاء شروط العرض في فاتورة شراء واحدة مستقلة.',
              unfulfilledConditions: reasons,
            );
          }
        }

        // Cross-seam line deduplication for genuine multi-part long receipts (AIR-39 & AIR-61)
        // When allowComplementaryReceipts is enabled, separate receipts legitimately contain repeated purchases
        // of the same product (e.g. buying another CDM chocolate to complete the required spend).
        if (!allowComplementaryReceipts && additionalImagesBytes.isNotEmpty && result.extractedProducts.isNotEmpty) {
          result = result.copyWith(
            extractedProducts: deduplicateCrossSeamProducts(result.extractedProducts),
          );
        }

        // AIR-71: Generic Multipack Brand Isolation Guard
        // If target company is Cadbury / Mondelez, generic multipacks (like "مالتي باك شوكولات")
        // without an explicit brand token must be disqualified (isTargetCompany = false).
        final isMondelezTenant = targetCompany.contains('كادبري') ||
            targetCompany.contains('كدبري') ||
            targetCompany.toLowerCase().contains('cadbury') ||
            targetCompany.contains('مونديليز') ||
            targetCompany.toLowerCase().contains('mondelez');

        if (isMondelezTenant && result.extractedProducts.isNotEmpty) {
          const mondelezTokens = [
            'كادبوري', 'كدبوري', 'cadbury',
            'ديري ميلك', 'ديرى ميلك', 'dairy milk',
            'مورو', 'moro',
            'بابلي', 'بابلى', 'bubbly',
            'اوريو', 'أوريو', 'oreo',
            'بوريو',
            'ماندولين', 'مندولين', 'mandolin',
            'فليك', 'flake',
            'سي دي ام', 'سى دى ام', 'cdm',
            'توك', 'tuc',
            'ترايدنت', 'trident',
            'كلورتس', 'clorets',
            'هولز', 'halls',
            'تانج', 'tang',
          ];

          final sanitizedProducts = result.extractedProducts.map((p) {
            final nameLower = p.name.toLowerCase();
            final isGenericMultipack = (nameLower.contains('مالتي باك') || nameLower.contains('مالتى باك')) &&
                (nameLower.contains('شوكول') || nameLower.contains('شكول') || nameLower.contains('choc'));

            if (isGenericMultipack && p.isTargetCompany) {
              final hasExplicitBrand = mondelezTokens.any((token) => nameLower.contains(token));
              if (!hasExplicitBrand) {
                return p.copyWith(isTargetCompany: false);
              }
            }
            return p;
          }).toList();

          result = result.copyWith(extractedProducts: sanitizedProducts);
        }

        // AIR-79: ADCO Tenant Guard - Strictly exclude Clorox items (Clorox is not ADCO; ADCO brand is Clorel)
        final isAdcoTenant = targetCompany.contains('ادكو') ||
            targetCompany.contains('إدكو') ||
            targetCompany.toLowerCase().contains('adco');

        if (isAdcoTenant && result.extractedProducts.isNotEmpty) {
          final sanitizedProducts = result.extractedProducts.map((p) {
            final nameLower = p.name.toLowerCase();
            final isClorox = nameLower.contains('كلوركس') || nameLower.contains('clorox');

            if (isClorox && p.isTargetCompany) {
              return p.copyWith(isTargetCompany: false);
            }
            return p;
          }).toList();

          result = result.copyWith(extractedProducts: sanitizedProducts);
        }

        // AIR-80: Shoman & Al-Dorra Umbrella Brand Governance and Competitor Sauce Isolation Guard
        final isShomanTenant = targetCompany.contains('شومان') ||
            targetCompany.toLowerCase().contains('shoman') ||
            targetCompany.toLowerCase().contains('shouman');
        final isDorraTenant = targetCompany.contains('الدرة') ||
            targetCompany.contains('الدره') ||
            targetCompany.contains('درة') ||
            targetCompany.contains('دره') ||
            targetCompany.toLowerCase().contains('dorra') ||
            targetCompany.toLowerCase().contains('durra');

        if ((isShomanTenant || isDorraTenant) && result.extractedProducts.isNotEmpty) {
          final sanitizedProducts = result.extractedProducts.map((p) {
            final nameLower = p.name.toLowerCase();
            final hasDorra = RegExp(
              r'(^|\s)(الدرة|الدره|درة|دره|د\s*ر\s*[هة]|dorra|durra)(\s|$)',
              caseSensitive: false,
            ).hasMatch(nameLower);
            final hasSeyidoglu = nameLower.contains('سيد اوغلو') ||
                nameLower.contains('سيد أوغلو') ||
                nameLower.contains('اوغلو') ||
                nameLower.contains('seyidoglu');
            final hasShoman = nameLower.contains('شومان') ||
                nameLower.contains('shoman') ||
                nameLower.contains('shouman');
            final hasAuthorizedBrand = hasShoman || hasDorra || hasSeyidoglu;

            final hasOtherCompetitor = nameLower.contains('هاينز') ||
                nameLower.contains('heinz') ||
                nameLower.contains('قودي') ||
                nameLower.contains('goody') ||
                nameLower.contains('هارفست') ||
                nameLower.contains('harvest') ||
                nameLower.contains('فاين فودز') ||
                nameLower.contains('كنور') ||
                nameLower.contains('امريكانا') ||
                nameLower.contains('أمريكانا');

            final isAgriculturalCornOrSpice = nameLower.contains('شوشة') ||
                nameLower.contains('شوشه') ||
                nameLower.contains('فشار') ||
                nameLower.contains('حبوب') ||
                nameLower.contains('عطارة') ||
                nameLower.contains('عطاره') ||
                nameLower.contains('بهارات') ||
                nameLower.contains('بذور') ||
                nameLower.contains('فلفل ص') ||
                nameLower.contains('باودر') ||
                nameLower.contains('كمون') ||
                nameLower.contains('فانيليا') ||
                nameLower.contains('دريم') ||
                nameLower.contains('شوكولاتة') ||
                nameLower.contains('شوكولاته') ||
                nameLower.contains('كاكاو') ||
                (nameLower.contains('ذرة') &&
                    !nameLower.contains('صلصة') &&
                    !nameLower.contains('كاتشب') &&
                    !nameLower.contains('صوص') &&
                    !nameLower.contains('مربى') &&
                    !nameLower.contains('معجون') &&
                    !nameLower.contains('خل') &&
                    !nameLower.contains('مايونيز') &&
                    !nameLower.contains('طحينة') &&
                    !nameLower.contains('حلاوة'));

            final isIndependentGrainOrRice = nameLower.contains('فراعنة') ||
                nameLower.contains('الفراعنة') ||
                nameLower.contains('الساعة') ||
                nameLower.contains('الساعه') ||
                nameLower.contains('ريحانة') ||
                nameLower.contains('ريحانه') ||
                nameLower.contains('ارز') ||
                nameLower.contains('أرز');

            if (hasOtherCompetitor || isAgriculturalCornOrSpice || isIndependentGrainOrRice) {
              return p.copyWith(isTargetCompany: false);
            }
            if (hasAuthorizedBrand) {
              return p.copyWith(isTargetCompany: true);
            }
            return p;
          }).toList();

          result = result.copyWith(extractedProducts: sanitizedProducts);
          if (!result.extractedProducts.any((p) => p.isTargetCompany)) {
            result = result.copyWith(
              targetCompanyTotal: 0.0,
              matchedRuleId: '',
              matchedRuleIds: const [],
              matchedRuleTitle: '',
              matchedRewardValue: '',
              matchedRewardAmount: 0.0,
            );
          }
        }

        // Auto-heal targetCompanyTotal if sum of extracted target products exceeds it (AIR-58)
        final double sumOfExtractedTarget = result.extractedProducts
            .where((p) => p.isTargetCompany)
            .fold<double>(0.0, (sum, p) => sum + (p.price * p.quantity));
        if (sumOfExtractedTarget > result.targetCompanyTotal ||
            (isMondelezTenant && sumOfExtractedTarget != result.targetCompanyTotal) ||
            (isAdcoTenant && sumOfExtractedTarget != result.targetCompanyTotal) ||
            ((isShomanTenant || isDorraTenant) && sumOfExtractedTarget != result.targetCompanyTotal)) {
          result = result.copyWith(targetCompanyTotal: sumOfExtractedTarget);
        }

        // Calculate / enforce chances & rewards earned based on quantity and spend multipliers (AIR-83)
        int calculatedChances = result.chancesEarned;
        if (result.isValid) {
          // Pre-resolve deterministic rule matches from Dart engine (AIR-83)
          final dartMatchedRules = promotionalRules.isNotEmpty
              ? PromotionalRuleMatcher.matchAllWithMultipliers(
                  result: result,
                  promotionalRules: promotionalRules,
                  allowCampaignMultipliers: allowMultipleChances,
                )
              : <MatchedPromotionalRuleResult>[];

          final hasSpendRuleMatch = dartMatchedRules.any((r) => r.rule.isSpendBased);
          final hasAnyRuleMatch = dartMatchedRules.isNotEmpty;

          if (hasSpendRuleMatch) {
            // Spend-rule quantity isolation (AIR-83): When a rule is spend-based
            // (e.g. 150 EGP with Halawa prerequisite), chances MUST strictly depend on spend.
            // Piece counts (quantity) in the basket must NEVER inflate chances!
            final ruleTotalChances = dartMatchedRules.fold<int>(0, (sum, r) => sum + r.multiplier);
            calculatedChances = ruleTotalChances > 0 ? ruleTotalChances : 1;
            if (maxChancesPerReceipt > 0 && calculatedChances > maxChancesPerReceipt) {
              calculatedChances = maxChancesPerReceipt;
            }
          } else if (hasAnyRuleMatch) {
            // Pure quantity-based rules (e.g. buy 2 get 1)
            final ruleTotalChances = dartMatchedRules.fold<int>(0, (sum, r) => sum + r.multiplier);
            calculatedChances = ruleTotalChances > 0 ? ruleTotalChances : 1;
            if (maxChancesPerReceipt > 0 && calculatedChances > maxChancesPerReceipt) {
              calculatedChances = maxChancesPerReceipt;
            }
          } else if (promotionalRules.isNotEmpty) {
            // Campaign has promotional rules, but none matched -> zero fallback prize (Rule 10)
            calculatedChances = 0;
          } else {
            // Campaign without promotional rules: evaluate based on general campaign spend & quantity settings
            int spendChances = 1;
            if (minimumSpend > 0 && result.targetCompanyTotal >= minimumSpend) {
              if (allowMultipleChances &&
                  (multiplierBasis == 'spend' || multiplierBasis == 'both')) {
                final computed = (result.targetCompanyTotal / minimumSpend).floor();
                spendChances = computed > 0 ? computed : 1;
                if (maxChancesPerReceipt > 0 && spendChances > maxChancesPerReceipt) {
                  spendChances = maxChancesPerReceipt;
                }
              }
            }

            int quantityMultiplier = 1;
            if (allowMultipleChances &&
                (multiplierBasis == 'quantity' || multiplierBasis == 'both')) {
              final targetItems = result.extractedProducts
                  .where((p) => p.isTargetCompany)
                  .toList();
              final totalTargetQty = targetItems.fold<int>(
                0,
                (sum, p) => sum + PromotionalRuleMatcher.getEffectiveProductQuantity(p),
              );
              if (totalTargetQty > 1) {
                quantityMultiplier = totalTargetQty;
                if (maxChancesPerReceipt > 0 &&
                    quantityMultiplier > maxChancesPerReceipt) {
                  quantityMultiplier = maxChancesPerReceipt;
                }
              }
            }

            if (multiplierBasis == 'quantity') {
              calculatedChances = quantityMultiplier;
            } else if (multiplierBasis == 'spend') {
              calculatedChances = spendChances;
            } else {
              calculatedChances = math.max(quantityMultiplier, spendChances);
            }

            if (calculatedChances <= 0) {
              calculatedChances = result.chancesEarned > 0
                  ? result.chancesEarned
                  : 1;
            }
            if (maxChancesPerReceipt > 0 &&
                calculatedChances > maxChancesPerReceipt) {
              calculatedChances = maxChancesPerReceipt;
            }
          }
        } else {
          calculatedChances = 0;
        }
        result = result.copyWith(chancesEarned: calculatedChances);

        // Enrich extractedProducts with matched barcodes and canonical names from catalog bidirectionally
        if (catalogBarcodeMap.isNotEmpty &&
            result.extractedProducts.isNotEmpty) {
          final enrichedProducts = result.extractedProducts.map((item) {
            final itemBarcode = item.barcode.trim();

            // 1. If barcode is present from receipt OCR, resolve canonical catalog name
            if (itemBarcode.isNotEmpty) {
              for (final entry in catalogBarcodeMap.entries) {
                final catBarcode = entry.value.trim();
                if (catBarcode == itemBarcode ||
                    (catBarcode.length >= 6 &&
                        itemBarcode.contains(catBarcode))) {
                  final canonicalName = entry.key.trim();
                  return item.copyWith(
                    name: '${item.name} $canonicalName',
                    isTargetCompany: true,
                  );
                }
              }
              return item;
            }

            // 2. If barcode is empty, match name to get barcode from catalog
            final itemNameLower = item.name.toLowerCase().trim();
            for (final entry in catalogBarcodeMap.entries) {
              final catName = entry.key.toLowerCase().trim();
              if (catName.isNotEmpty &&
                  (itemNameLower.contains(catName) ||
                      catName.contains(itemNameLower))) {
                return item.copyWith(
                  barcode: entry.value,
                  isTargetCompany: true,
                );
              }
            }
            return item;
          }).toList();
          result = result.copyWith(extractedProducts: enrichedProducts);
        }

        // Deterministic POS & Store Code Reconciler in Dart
        if (registeredBranches.isNotEmpty) {
          final combinedReceiptText =
              '${result.receiptNumber} ${result.branchDetected} ${result.message} ${result.storeChainDetected}'
                  .toEnglishDigits();

          BranchModel? matchedBranchByCode;

          for (final branch in registeredBranches) {
            final storeId = (branch.receiptSignature?.storeId ?? '')
                .trim()
                .toEnglishDigits();
            final branchCode = branch.branchCode.trim().toEnglishDigits();

            bool matches = false;

            if (storeId.isNotEmpty && storeId != '0') {
              final storeRegex = RegExp(
                r'(?:Store|المتجر|فرع|POS|Pos|pos)[\s:]*' +
                    RegExp.escape(storeId) +
                    r'\b|' +
                    r'[\/\-_]' +
                    RegExp.escape(storeId) +
                    r'[\/\-_]',
                caseSensitive: false,
              );
              if (storeRegex.hasMatch(combinedReceiptText) ||
                  combinedReceiptText.contains('/$storeId/')) {
                matches = true;
              }
            }

            if (!matches &&
                branchCode.isNotEmpty &&
                branchCode != '0' &&
                branchCode != 'DEF') {
              final codeRegex = RegExp(
                r'(?:Store|كود|فرع|POS|Pos|pos)[\s:]*' +
                    RegExp.escape(branchCode) +
                    r'\b|' +
                    r'[\/\-_]' +
                    RegExp.escape(branchCode) +
                    r'[\/\-_]',
                caseSensitive: false,
              );
              if (codeRegex.hasMatch(combinedReceiptText) ||
                  combinedReceiptText.contains('/$branchCode/')) {
                matches = true;
              }
            }

            if (matches) {
              matchedBranchByCode = branch;
              break;
            }
          }

          if (matchedBranchByCode != null) {
            String? matchedCanonicalAllowedBranch;
            final cleanBName = CompanyGiftsService.normalizeBranchToken(
              matchedBranchByCode.branchName,
            );
            for (final ab in allowedBranches) {
              final cleanAb = CompanyGiftsService.normalizeBranchToken(ab);
              if (cleanAb.isNotEmpty &&
                  cleanBName.isNotEmpty &&
                  (cleanAb == cleanBName ||
                      cleanAb.contains(cleanBName) ||
                      cleanBName.contains(cleanAb))) {
                matchedCanonicalAllowedBranch = ab;
                break;
              }
            }

            final isAllowed =
                isAllBranches ||
                allowedBranches.isEmpty ||
                matchedCanonicalAllowedBranch != null;

            final fixedBranchName =
                matchedCanonicalAllowedBranch ?? matchedBranchByCode.branchName;
            final prevBranchName = result.branchDetected;

            if (isAllowed) {
              final wasBranchFailure = !result.isBranchMatched;

              result = result.copyWith(
                isBranchMatched: true,
                branchDetected: fixedBranchName,
                storeChainDetected:
                    matchedBranchByCode.retailChainName.isNotEmpty
                    ? matchedBranchByCode.retailChainName
                    : result.storeChainDetected,
                isValid: wasBranchFailure
                    ? (result.targetCompanyTotal >=
                              (minimumSpend > 0 ? minimumSpend : 0) &&
                          (promotionalRules.isEmpty ||
                              result.extractedProducts.isNotEmpty ||
                              result.matchedRuleId.isNotEmpty))
                    : result.isValid,
                message: wasBranchFailure
                    ? (result.message.contains('فرع')
                          ? 'تم التحقق من الفاتورة ومطابقة الفرع بنجاح بناءً على كود المتجر المعتمد ($fixedBranchName).'
                          : result.message)
                    : (prevBranchName.isNotEmpty
                          ? result.message.replaceAll(
                              prevBranchName,
                              fixedBranchName,
                            )
                          : result.message),
              );
            } else {
              // Strictly reject if the POS Store Code belongs to a branch outside the campaign's allowedBranches!
              result = result.copyWith(
                isBranchMatched: false,
                isValid: false,
                branchDetected: fixedBranchName,
                storeChainDetected:
                    matchedBranchByCode.retailChainName.isNotEmpty
                    ? matchedBranchByCode.retailChainName
                    : result.storeChainDetected,
              );
            }
          }
        }

        // Auto-reconcile detected branch against allowedBranches in Dart using canonical resolution
        if (allowedBranches.isNotEmpty) {
          final detectedRaw = result.branchDetected.trim();
          final detectedClean = CompanyGiftsService.normalizeBranchToken(detectedRaw);
          bool matchedAnyAllowed = false;

          for (final ab in allowedBranches) {
            final abClean = CompanyGiftsService.normalizeBranchToken(ab);

            if (detectedClean.isNotEmpty && abClean.isNotEmpty) {
              if (detectedClean == abClean ||
                  detectedClean.contains(abClean) ||
                  abClean.contains(detectedClean) ||
                  (detectedClean.contains('عبور') &&
                      abClean.contains('عبور')) ||
                  (detectedClean.contains('رحاب') &&
                      abClean.contains('رحاب')) ||
                  (detectedClean.contains('سموحه') &&
                      abClean.contains('سموحه')) ||
                  (detectedClean.contains('ستانلي') &&
                      abClean.contains('ستانلي')) ||
                  (detectedClean.contains('جاردينيا') &&
                      abClean.contains('جاردينيا')) ||
                  (detectedClean.contains('عجمي') &&
                      abClean.contains('عجمي')) ||
                  (detectedClean.contains('محله') &&
                      abClean.contains('محله')) ||
                  (detectedClean.contains('تجمع') &&
                      abClean.contains('تجمع')) ||
                  (detectedClean.contains('اكتوبر') &&
                      abClean.contains('اكتوبر')) ||
                  (detectedClean.contains('منصوره') &&
                      abClean.contains('منصوره')) ||
                  (detectedClean.contains('شبين') &&
                      abClean.contains('شبين')) ||
                  (detectedClean.contains('منتزه') &&
                      abClean.contains('منتزه')) ||
                  (detectedClean.contains('ميامي') &&
                      abClean.contains('ميامي')) ||
                  (detectedClean.contains('جناكليس') &&
                      abClean.contains('جناكليس'))) {
                result = result.copyWith(
                  isBranchMatched: true,
                  branchDetected: ab,
                );
                matchedAnyAllowed = true;
                break;
              }
            }
          }

          if (!isAllBranches && !matchedAnyAllowed && detectedClean.isNotEmpty) {
            result = result.copyWith(
              isBranchMatched: false,
              isValid: false,
            );
          }
        }

        // Sanitize any nested or outer wrapper parentheses on branchDetected (e.g. ((المنصورة (المنصورة))) -> المنصورة (المنصورة))
        if (result.branchDetected.contains('(') || result.branchDetected.contains(')')) {
          var bNorm = result.branchDetected.trim();
          while (bNorm.startsWith('(') && bNorm.endsWith(')') && '('.allMatches(bNorm).length > 1) {
            bNorm = bNorm.substring(1, bNorm.length - 1).trim();
          }
          while (bNorm.startsWith('(') && '('.allMatches(bNorm).length > ')'.allMatches(bNorm).length) {
            bNorm = bNorm.substring(1).trim();
          }
          while (bNorm.endsWith(')') && ')'.allMatches(bNorm).length > '('.allMatches(bNorm).length) {
            bNorm = bNorm.substring(0, bNorm.length - 1).trim();
          }
          result = result.copyWith(branchDetected: bNorm);
        }

        // Multi-chain matching reconciliation
        final allowedChains = retailChainName
            .split(RegExp(r'[\•\,\،\/\-\|\+]'))
            .map((s) => s.trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toList();
        final detChainNorm = result.storeChainDetected.trim().toLowerCase();
        final isChainMatched = allowedChains.isEmpty || allowedChains.any((ac) {
          return detChainNorm.contains(ac) ||
              ac.contains(detChainNorm) ||
              (detChainNorm.contains('جملة') && ac.contains('جملة')) ||
              (detChainNorm.contains('فتح') && ac.contains('فتح')) ||
              (detChainNorm.contains('كارفور') && ac.contains('كارفور')) ||
              (detChainNorm.contains('سبينس') && ac.contains('سبينس')) ||
              (detChainNorm.contains('خير') && ac.contains('خير')) ||
              (detChainNorm.contains('بيت') && ac.contains('بيت'));
        });

        // If the branch and chain are matched, strip any spurious chain/branch rejection errors from AI unfulfilledConditions
        if (result.isBranchMatched && isChainMatched) {
          final cleanedUnfulfilled = result.unfulfilledConditions.where((c) {
            final lower = c.toLowerCase();
            final isSpuriousChainError = lower.contains('سلسلة غير مشمولة') ||
                lower.contains('سلسله غير مشموله') ||
                lower.contains('غير مشمولة بالعرض') ||
                lower.contains('غير مشموله بالعرض') ||
                (lower.contains('فرع غير مشمول') && !lower.contains('أقل من')) ||
                lower.contains('فرع غير معتمد');
            return !isSpuriousChainError;
          }).toList();

          final isStillFailed = cleanedUnfulfilled.isNotEmpty ||
              (minimumSpend > 0 && result.targetCompanyTotal < minimumSpend);

          result = result.copyWith(
            unfulfilledConditions: cleanedUnfulfilled,
            isValid: !isStillFailed,
            message: !isStillFailed && (result.message.contains('فرع غير مشمول') || result.message.contains('سلسلة غير مشمولة'))
                ? 'تم التحقق من الفاتورة ومطابقة الفرع بنجاح.'
                : result.message,
          );
        }

        // Promotional rules deterministic reconciliation in Dart
        if (promotionalRules.isNotEmpty && result.extractedProducts.isNotEmpty) {
          final dartMatches = PromotionalRuleMatcher.matchAllWithMultipliers(
            result: result,
            promotionalRules: promotionalRules,
            allowCampaignMultipliers: allowMultipleChances,
          );
          if (dartMatches.isNotEmpty) {
            final double promoMinSpendThreshold = promotionalRules
                .where((r) => r.isSpendBased)
                .map((r) => r.effectiveMinSpend)
                .fold<double>(minimumSpend, (min, s) => s > 0 && (min <= 0 || s < min) ? s : min);

            final cleanedUnfulfilled = result.unfulfilledConditions.where((c) {
              final lower = c.toLowerCase();
              final isPromoRuleComplaint = lower.contains('شرط عرض') ||
                  lower.contains('الكمية المشتراة') ||
                  lower.contains('غير مستوفى') ||
                  lower.contains('قطعة فقط') ||
                  lower.contains('قطعتين') ||
                  lower.contains('شراء 2') ||
                  lower.contains('غير مشمول');
              final isSpendComplaint = (promoMinSpendThreshold <= 0 || result.targetCompanyTotal >= promoMinSpendThreshold) &&
                  (lower.contains('الحد الأدنى') || lower.contains('أقل من'));
              return !isPromoRuleComplaint && !isSpendComplaint;
            }).toList();

            final isStillFailed = cleanedUnfulfilled.isNotEmpty ||
                (promoMinSpendThreshold > 0 && result.targetCompanyTotal < promoMinSpendThreshold) ||
                !result.isBranchMatched;

            final firstMatch = dartMatches.first;
            result = result.copyWith(
              isValid: !isStillFailed,
              unfulfilledConditions: cleanedUnfulfilled,
              matchedRuleId: firstMatch.rule.id,
              matchedRuleTitle: firstMatch.rule.ruleTitle,
              matchedRewardValue: dartMatches.map((m) => m.formattedPrizeSummary).join(' + '),
              matchedRewardAmount: dartMatches.fold<double>(0.0, (sum, m) => sum + m.totalRewardAmount),
              matchedRewardType: firstMatch.rule.rewardType,
              message: !isStillFailed
                  ? 'تم التحقق من الفاتورة ومطابقة العرض الترويجي بنجاح (${firstMatch.rule.ruleTitle}).'
                  : result.message,
            );
          }
        }

        dartStopwatch.stop();
        int dartDurationMs = dartStopwatch.elapsedMilliseconds;

        // 🛑 Conditional Escalation to Deep Reasoning Tier (AIR-72)
        if (!forceDeepAudit &&
            (result.isTampered ||
                (result.fraudRiskScore >= 40 &&
                    result.isThermalPosReceipt &&
                    !result.isHandwritten &&
                    !result.isScreenCapture))) {
          try {
            final deepAiStopwatch = Stopwatch()..start();
            final deepPrompt = TextPart(
              '⚠️ تنبيه تدقيق جنائي عميق واستدلال متقدم (Deep Forensic Audit - AIR-72):\n'
              'هذه الفاتورة تحتوي على اشتباه تلاعب في الأرقام أو درجة خطورة تزوير مرتفعة.\n'
              'يرجى إجراء فحص مجهري فائق الدقة لحواف الأرقام المطبوعة، وتطابق كود الفرع، وصحة البنود، واستخراج القرار النهائي الصارم.\n\n'
              '$finalPromptText',
            );
            final deepResponse = await _deepAuditModel
                .generateContent([
                  Content.multi([deepPrompt, ...allImageParts]),
                ])
                .timeout(const Duration(seconds: 30));
            deepAiStopwatch.stop();
            aiDurationMs += deepAiStopwatch.elapsedMilliseconds;
            pipelineTier = 'deep_reasoning_tier';

            if (deepResponse.text != null && deepResponse.text!.trim().isNotEmpty) {
              final deepJson = _cleanAndParseJson(deepResponse.text!);
              final deepResult = AiReceiptAnalysisResult.fromJson(
                deepJson,
                durationMs: stopwatch.elapsedMilliseconds,
                targetCompany: targetCompany,
                targetBrands: resolvedRequiredProducts,
              );
              result = result.copyWith(
                isTampered: deepResult.isTampered,
                fraudRiskScore: deepResult.fraudRiskScore,
                fraudReasons: deepResult.fraudReasons.isNotEmpty
                    ? deepResult.fraudReasons
                    : result.fraudReasons,
                isValid: !deepResult.isTampered && result.isValid,
              );
            }
          } catch (deepErr) {
            debugPrint('Deep Reasoning Audit Fallback gracefully ignored: $deepErr');
          }
        }

        stopwatch.stop();
        final int finalDurationMs = stopwatch.elapsedMilliseconds;
        final double finalDurationSeconds = finalDurationMs / 1000.0;

        // Branch matching fallback validation
        if (retailChainName.trim().isNotEmpty &&
            !isAllBranches &&
            allowedBranches.isNotEmpty) {
          if (!result.isBranchMatched) {
            final detected = result.branchDetected.trim().isNotEmpty
                ? result.branchDetected
                : "فرع غير معتمد";
            return result.copyWith(
              isValid: false,
              isBranchMatched: false,
              durationMs: finalDurationMs,
              durationSeconds: finalDurationSeconds,
              aiDurationMs: aiDurationMs,
              dartDurationMs: dartDurationMs,
              pipelineTierUsed: pipelineTier,
              message:
                  'عذراً، الفاتورة صادرة من ($detected) بينما العرض سارٍ حصرياً في فروع: [${allowedBranches.join("، ")}].',
            );
          }
        }

        // Perform strict Dart-level Date validation if startDate and endDate are set
        if (startDate != null || endDate != null) {
          final rawDateStr = result.receiptDate.trim();
          if (rawDateStr.isNotEmpty) {
            DateTime? parsedDate = _parseReceiptDate(
              rawDateStr,
              startDate: startDate,
              endDate: endDate,
            );
            if (parsedDate != null) {
              if (startDate != null && parsedDate.isBefore(startDate)) {
                final startStr =
                    "${startDate.day}/${startDate.month}/${startDate.year}";
                return result.copyWith(
                  isValid: false,
                  durationMs: finalDurationMs,
                  durationSeconds: finalDurationSeconds,
                  aiDurationMs: aiDurationMs,
                  dartDurationMs: dartDurationMs,
                  pipelineTierUsed: pipelineTier,
                  message:
                      'تاريخ الشراء بالفاتورة ($rawDateStr) أقدم من تاريخ بداية الحملة ($startStr). الشراء غير مشمول بالعرض.',
                );
              }
              if (endDate != null &&
                  parsedDate.isAfter(endDate.add(const Duration(days: 1)))) {
                final endStr =
                    "${endDate.day}/${endDate.month}/${endDate.year}";
                return result.copyWith(
                  isValid: false,
                  durationMs: finalDurationMs,
                  durationSeconds: finalDurationSeconds,
                  aiDurationMs: aiDurationMs,
                  dartDurationMs: dartDurationMs,
                  pipelineTierUsed: pipelineTier,
                  message:
                      'تاريخ الشراء بالفاتورة ($rawDateStr) متأخر عن تاريخ نهاية الحملة ($endStr). عذراً، انتهى العرض.',
                );
              }
              // Store normalized and auto-healed date string
              final normalizedDateStr =
                  "${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year}";
              result = result.copyWith(receiptDate: normalizedDateStr);
            }
          }
        }

        final finalResult = result.copyWith(
          durationMs: finalDurationMs,
          durationSeconds: finalDurationSeconds,
          aiDurationMs: aiDurationMs,
          dartDurationMs: dartDurationMs,
          pipelineTierUsed: pipelineTier,
        );
        if (fingerprint.isNotEmpty && finalResult.isValid) {
          cacheReceiptAnalysis(fingerprint, finalResult);
        }
        return finalResult;
      } else {
        throw Exception(
          "تعذر قراءة بيانات الفاتورة من نموذج الذكاء الاصطناعي. يرجى إعادة المحاولة.",
        );
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

  /// Performs cross-seam line deduplication for genuine multi-part long receipts (AIR-39 & AIR-61).
  /// If an item appears consecutively across the seam boundary of adjacent photos with identical
  /// name, price, and barcode, it is counted once only to prevent double counting.
  static List<ExtractedProductItem> deduplicateCrossSeamProducts(
    List<ExtractedProductItem> products,
  ) {
    if (products.length <= 1) return products;
    final List<ExtractedProductItem> deduplicated = [];
    for (int i = 0; i < products.length; i++) {
      final current = products[i];
      if (deduplicated.isNotEmpty) {
        final prev = deduplicated.last;
        final isSameName = current.name.trim().toLowerCase() ==
            prev.name.trim().toLowerCase();
        final isSamePrice = (current.price - prev.price).abs() < 0.01;
        final isSameBarcode = current.barcode.isNotEmpty &&
            current.barcode == prev.barcode;
        final isSameQuantity = current.quantity == prev.quantity;

        // If consecutive duplicate item on seam boundary, avoid double counting
        if (isSameName &&
            isSamePrice &&
            (isSameBarcode ||
                (current.barcode.isEmpty && prev.barcode.isEmpty)) &&
            isSameQuantity) {
          continue;
        }
      }
      deduplicated.add(current);
    }
    return deduplicated;
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
    final isValidMatch = RegExp(
      r'"isValid"\s*:\s*(true|false)',
      caseSensitive: false,
    ).firstMatch(text);
    final receiptNumMatch = RegExp(
      r'"receiptNumber"\s*:\s*"([^"]*)"',
    ).firstMatch(text);
    final totalMatch = RegExp(
      r'"targetCompanyTotal"\s*:\s*([\d\.]+)',
    ).firstMatch(text);
    final dateMatch = RegExp(r'"receiptDate"\s*:\s*"([^"]*)"').firstMatch(text);
    final storeMatch = RegExp(
      r'"storeChainDetected"\s*:\s*"([^"]*)"',
    ).firstMatch(text);
    final branchMatch = RegExp(
      r'"branchDetected"\s*:\s*"([^"]*)"',
    ).firstMatch(text);
    final branchMatchedMatch = RegExp(
      r'"isBranchMatched"\s*:\s*(true|false)',
      caseSensitive: false,
    ).firstMatch(text);
    final messageMatch = RegExp(r'"message"\s*:\s*"([^"]*)"').firstMatch(text);
    final matchedRuleIdMatch = RegExp(
      r'"matchedRuleId"\s*:\s*"([^"]*)"',
    ).firstMatch(text);
    final matchedRuleTitleMatch = RegExp(
      r'"matchedRuleTitle"\s*:\s*"([^"]*)"',
    ).firstMatch(text);
    final matchedRewardValueMatch = RegExp(
      r'"matchedRewardValue"\s*:\s*"([^"]*)"',
    ).firstMatch(text);
    final matchedRewardAmountMatch = RegExp(
      r'"matchedRewardAmount"\s*:\s*([\d\.]+)',
    ).firstMatch(text);
    final matchedRewardTypeMatch = RegExp(
      r'"matchedRewardType"\s*:\s*"([^"]*)"',
    ).firstMatch(text);

    return {
      'isValid': isValidMatch?.group(1)?.toLowerCase() == 'true',
      'receiptNumber': receiptNumMatch?.group(1) ?? '',
      'targetCompanyTotal': double.tryParse(totalMatch?.group(1) ?? '') ?? 0.0,
      'receiptDate': dateMatch?.group(1) ?? '',
      'storeChainDetected': storeMatch?.group(1) ?? '',
      'branchDetected': branchMatch?.group(1) ?? '',
      'isBranchMatched': branchMatchedMatch?.group(1)?.toLowerCase() != 'false',
      'message':
          messageMatch?.group(1) ??
          (isValidMatch?.group(1)?.toLowerCase() == 'true'
              ? 'تمت قراءة الفاتورة بنجاح'
              : 'الفاتورة غير مطابقة للشروط'),
      'matchedRuleId': matchedRuleIdMatch?.group(1) ?? '',
      'matchedRuleTitle': matchedRuleTitleMatch?.group(1) ?? '',
      'matchedRewardValue': matchedRewardValueMatch?.group(1) ?? '',
      'matchedRewardAmount':
          double.tryParse(matchedRewardAmountMatch?.group(1) ?? '') ?? 0.0,
      'matchedRewardType': matchedRewardTypeMatch?.group(1) ?? '',
      'extractedProducts': <Map<String, dynamic>>[],
      'unfulfilledConditions': <String>[],
    };
  }

  DateTime? _parseReceiptDate(
    String dateStr, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return parseReceiptDate(dateStr, startDate: startDate, endDate: endDate);
  }

  /// Disambiguates and parses receipt dates supporting both DD/MM/YYYY and MM/DD/YYYY formats.
  /// When ambiguous (e.g. 09/10/26), cross-references against current time and campaign window.
  static DateTime? parseReceiptDate(
    String dateStr, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    try {
      final clean = dateStr.replaceAll(RegExp(r'[^\d/\-]'), '');
      if (clean.contains('/')) {
        final parts = clean.split('/');
        if (parts.length >= 3) {
          int a = int.parse(parts[0]);
          int b = int.parse(parts[1]);
          int year = int.parse(parts[2]);
          if (year < 100) year += 2000;

          DateTime resolveHealedDate(int y, int m, int d) {
            final direct = DateTime(y, m, d);
            if (startDate != null && direct.isBefore(startDate)) {
              final healedYear = startDate.year;
              if (y != healedYear) {
                final healedDate = DateTime(healedYear, m, d);
                final startBound = DateTime(startDate.year, startDate.month, startDate.day);
                final endBound = endDate != null
                    ? DateTime(endDate.year, endDate.month, endDate.day).add(const Duration(days: 1))
                    : DateTime(2100);
                final tomorrow = DateTime.now().add(const Duration(days: 1));
                if (!healedDate.isBefore(startBound) &&
                    !healedDate.isAfter(endBound) &&
                    !healedDate.isAfter(tomorrow)) {
                  // Auto-heal thermal print digit confusion (e.g. broken loop '6' misread as '4' or '5')
                  return healedDate;
                }
              }
            }
            return direct;
          }

          // Case 1: YYYY/MM/DD format
          if (a > 1000) {
            return resolveHealedDate(a, b, year);
          }

          // Case 2: Unambiguous day/month
          if (a > 12 && b <= 12) {
            // Must be DD/MM/YYYY
            return resolveHealedDate(year, b, a);
          }
          if (b > 12 && a <= 12) {
            // Must be MM/DD/YYYY
            return resolveHealedDate(year, a, b);
          }

          // Case 3: Ambiguous (both a <= 12 and b <= 12, e.g. 09/10/26)
          // Candidate 1: DD/MM/YYYY (day=a, month=b)
          // Candidate 2: MM/DD/YYYY (month=a, day=b)
          final candidateDDMM = resolveHealedDate(year, b, a);
          final candidateMMDD = resolveHealedDate(year, a, b);

          final now = DateTime.now();
          final tomorrow = now.add(const Duration(days: 1));

          // A receipt cannot be issued in the future
          final bool ddmmInFuture = candidateDDMM.isAfter(tomorrow);
          final bool mmddInFuture = candidateMMDD.isAfter(tomorrow);

          if (ddmmInFuture && !mmddInFuture) {
            return candidateMMDD;
          }
          if (mmddInFuture && !ddmmInFuture) {
            return candidateDDMM;
          }

          // Check against campaign window [startDate, endDate]
          if (startDate != null || endDate != null) {
            final startBound = startDate != null
                ? DateTime(startDate.year, startDate.month, startDate.day)
                : DateTime(2000);
            final endBound = endDate != null
                ? DateTime(endDate.year, endDate.month, endDate.day)
                    .add(const Duration(days: 1))
                : DateTime(2100);

            final bool ddmmInWindow = !candidateDDMM.isBefore(startBound) &&
                !candidateDDMM.isAfter(endBound);
            final bool mmddInWindow = !candidateMMDD.isBefore(startBound) &&
                !candidateMMDD.isAfter(endBound);

            if (mmddInWindow && !ddmmInWindow) {
              return candidateMMDD;
            }
            if (ddmmInWindow && !mmddInWindow) {
              return candidateDDMM;
            }
          }

          // Prefer candidate closest to current date
          final diffDDMM = (now.difference(candidateDDMM).inDays).abs();
          final diffMMDD = (now.difference(candidateMMDD).inDays).abs();
          if (diffMMDD < diffDDMM && diffMMDD <= 60) {
            return candidateMMDD;
          }

          return candidateDDMM;
        }
      } else if (clean.contains('-')) {
        final parts = clean.split('-');
        if (parts.length >= 3) {
          int a = int.parse(parts[0]);
          int b = int.parse(parts[1]);
          int c = int.parse(parts[2]);

          DateTime resolveHealedDate(int y, int m, int d) {
            final direct = DateTime(y, m, d);
            if (startDate != null && direct.isBefore(startDate)) {
              final healedYear = startDate.year;
              if (y != healedYear) {
                final healedDate = DateTime(healedYear, m, d);
                final startBound = DateTime(startDate.year, startDate.month, startDate.day);
                final endBound = endDate != null
                    ? DateTime(endDate.year, endDate.month, endDate.day).add(const Duration(days: 1))
                    : DateTime(2100);
                final tomorrow = DateTime.now().add(const Duration(days: 1));
                if (!healedDate.isBefore(startBound) &&
                    !healedDate.isAfter(endBound) &&
                    !healedDate.isAfter(tomorrow)) {
                  return healedDate;
                }
              }
            }
            return direct;
          }

          if (a > 1000) {
            return resolveHealedDate(a, b, c);
          } else {
            int year = c < 100 ? c + 2000 : c;
            if (a > 12 && b <= 12) return resolveHealedDate(year, b, a);
            if (b > 12 && a <= 12) return resolveHealedDate(year, a, b);

            final candidateDDMM = resolveHealedDate(year, b, a);
            final candidateMMDD = resolveHealedDate(year, a, b);
            final now = DateTime.now();
            final tomorrow = now.add(const Duration(days: 1));

            if (candidateDDMM.isAfter(tomorrow) && !candidateMMDD.isAfter(tomorrow)) {
              return candidateMMDD;
            }
            if (candidateMMDD.isAfter(tomorrow) && !candidateDDMM.isAfter(tomorrow)) {
              return candidateDDMM;
            }

            if (startDate != null || endDate != null) {
              final startBound = startDate != null
                  ? DateTime(startDate.year, startDate.month, startDate.day)
                  : DateTime(2000);
              final endBound = endDate != null
                  ? DateTime(endDate.year, endDate.month, endDate.day)
                      .add(const Duration(days: 1))
                  : DateTime(2100);

              final bool ddmmInWindow = !candidateDDMM.isBefore(startBound) &&
                  !candidateDDMM.isAfter(endBound);
              final bool mmddInWindow = !candidateMMDD.isBefore(startBound) &&
                  !candidateMMDD.isAfter(endBound);

              if (mmddInWindow && !ddmmInWindow) return candidateMMDD;
              if (ddmmInWindow && !mmddInWindow) return candidateDDMM;
            }

            return candidateDDMM;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}

/// Robust engine for resolving which promotional rule and gift/voucher is earned from receipt analysis.
class PromotionalRuleMatcher {
  /// Extracts all candidate brand names dynamically from promotional rules
  /// (from requiredBrands, selectedProductNames, triggerProduct, ruleTitle).
  static Set<String> _extractCampaignBrands(List<PromotionalRuleItem> rules) {
    final Set<String> brands = {};
    for (final rule in rules) {
      for (final b in rule.requiredBrands) {
        if (b.trim().isNotEmpty) brands.add(b.trim());
      }
      if (rule.triggerProduct.trim().isNotEmpty) {
        brands.add(rule.triggerProduct.trim());
      }
      if (rule.ruleTitle.trim().isNotEmpty) {
        brands.add(rule.ruleTitle.trim());
      }
      for (final pName in rule.selectedProductNames) {
        final words = pName.trim().split(' ');
        if (words.isNotEmpty && words.first.length >= 3) {
          brands.add(words.first);
        }
      }
    }
    return brands;
  }

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
    final effectiveRuleTitle =
        (result != null && result.matchedRuleTitle.isNotEmpty)
        ? result.matchedRuleTitle
        : matchedRuleTitle;
    final effectiveRewardValue =
        (result != null && result.matchedRewardValue.isNotEmpty)
        ? result.matchedRewardValue
        : matchedRewardValue;
    final effectiveProducts =
        (result != null && result.extractedProducts.isNotEmpty)
        ? result.extractedProducts
        : extractedProducts;

    // 1. Direct ID match from Gemini
    if (effectiveRuleId.trim().isNotEmpty) {
      final cleanId = effectiveRuleId.trim().toLowerCase();
      final match = promotionalRules
          .where((r) => r.id.trim().toLowerCase() == cleanId)
          .firstOrNull;
      if (match != null) return match;
    }

    // 2. Direct Title match from Gemini
    if (effectiveRuleTitle.trim().isNotEmpty) {
      final titleNorm = _normalize(effectiveRuleTitle);
      final match = promotionalRules
          .where((r) => _normalize(r.ruleTitle) == titleNorm)
          .firstOrNull;
      if (match != null) return match;
    }

    // 3. Direct Reward Value match from Gemini
    if (effectiveRewardValue.trim().isNotEmpty) {
      final rewardNorm = _normalize(effectiveRewardValue);
      final match = promotionalRules
          .where((r) => _normalize(r.rewardValue) == rewardNorm)
          .firstOrNull;
      if (match != null) return match;
    }

    // 4. Smart NLP token, spend-based, and quantity-tiered match on extractedProducts
    if (effectiveProducts.isNotEmpty) {
      final matchingRulesWithScores = <PromotionalRuleItem, int>{};
      final campaignBrands = _extractCampaignBrands(promotionalRules);

      for (final rule in promotionalRules) {
        if (rule.isSpendBased) {
          // Check combo requirement if applicable
          if (rule.isCombo && rule.requiredBrands.isNotEmpty) {
            final Set<String> foundBrands = {};
            for (final p in effectiveProducts) {
              final pNorm = _normalize(p.name);
              for (final rb in rule.requiredBrands) {
                final rbNorm = _normalize(rb);
                if (pNorm.contains(rbNorm)) {
                  foundBrands.add(rb);
                }
              }
            }
            if (!rule.requiredBrands.every((rb) => foundBrands.contains(rb))) {
              continue;
            }
          }

          double totalSpend = 0.0;
          int matchedItemCount = 0;
          for (final p in effectiveProducts) {
            if (_matchesProduct(p, rule.triggerProduct, rule, campaignBrands, promotionalRules)) {
              totalSpend += p.actualLineSpend;
              matchedItemCount++;
            }
          }

          if (matchedItemCount > 0 &&
              rule.minSpend > 0 &&
              totalSpend >= rule.minSpend) {
            // Weight minSpend heavily so higher spend tier beats lower spend tier
            final score = (rule.minSpend.toInt() * 100) + matchedItemCount;
            matchingRulesWithScores[rule] = score;
          }
        } else {
          int totalMatchedQty = 0;
          int matchedItemCount = 0;

          for (final p in effectiveProducts) {
            if (_matchesProduct(p, rule.triggerProduct, rule, campaignBrands, promotionalRules)) {
              totalMatchedQty += getEffectiveProductQuantity(p);
              matchedItemCount++;
            }
          }

          if (matchedItemCount > 0 && totalMatchedQty >= rule.minQuantity) {
            // Weight minQuantity heavily so 2-pcs tier beats 1-pc tier
            final score = (rule.minQuantity * 100) + matchedItemCount;
            matchingRulesWithScores[rule] = score;
          }
        }
      }

      if (matchingRulesWithScores.isNotEmpty) {
        final sorted = matchingRulesWithScores.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return sorted.first.key;
      }
    }

    // 5. Spend-based fallback for company-wide spend promotions (e.g. spend >= 350 EGP on sponsor products)
    if (result != null && result.targetCompanyTotal > 0) {
      final eligibleSpendRules = promotionalRules
          .where((r) => r.isSpendBased && !r.isCombo && result.targetCompanyTotal >= r.effectiveMinSpend)
          .toList()
        ..sort((a, b) => b.effectiveMinSpend.compareTo(a.effectiveMinSpend));
      if (eligibleSpendRules.isNotEmpty) {
        return eligibleSpendRules.first;
      }
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

    final effectiveProducts =
        (result != null && result.extractedProducts.isNotEmpty)
        ? result.extractedProducts
        : extractedProducts;

    // Calculate total quantity & spend of trigger products purchased
    int totalTriggerQty = 0;
    double totalTriggerSpend = 0.0;
    final campaignBrands = _extractCampaignBrands(promotionalRules);
    if (effectiveProducts.isNotEmpty) {
      for (final p in effectiveProducts) {
        if (_matchesProduct(
          p,
          matchedRule.triggerProduct,
          matchedRule,
          campaignBrands,
          promotionalRules,
        )) {
          final qty = getEffectiveProductQuantity(p);
          totalTriggerQty += qty;
          totalTriggerSpend += p.actualLineSpend;
        }
      }
    } else if (result != null && result.targetCompanyTotal > 0 && matchedRule.isSpendBased) {
      totalTriggerSpend = result.targetCompanyTotal;
    }

    // Determine multiplier
    int multiplier = 1;
    if (matchedRule.isSpendBased) {
      final effectiveMin = matchedRule.effectiveMinSpend > 0
          ? matchedRule.effectiveMinSpend
          : matchedRule.minSpend;
      if (effectiveMin > 0 && totalTriggerSpend >= effectiveMin) {
        if (matchedRule.allowMultipliers || allowCampaignMultipliers) {
          final divisor = matchedRule.minSpend > 0 ? matchedRule.minSpend : effectiveMin;
          multiplier = divisor > 0 ? (totalTriggerSpend ~/ divisor) : 1;
          if (multiplier < 1) multiplier = 1;
        } else {
          multiplier = 1;
        }
      }
    } else {
      if (matchedRule.minQuantity > 0 &&
          totalTriggerQty >= matchedRule.minQuantity) {
        if (matchedRule.allowMultipliers || allowCampaignMultipliers) {
          multiplier = totalTriggerQty ~/ matchedRule.minQuantity;
          if (multiplier < 1) multiplier = 1;
        } else {
          multiplier = 1;
        }
      }
    }

    final double baseAmount = matchedRule.totalVoucherValue > 0
        ? matchedRule.totalVoucherValue
        : (matchedRule.rewardAmount > 0
              ? matchedRule.rewardAmount
              : (result?.matchedRewardAmount ?? 0.0));
    final double totalAmount = baseAmount * multiplier;

    final multipliedLinkedGifts = matchedRule.linkedGifts.map((g) {
      return g.copyWith(quantity: g.quantity * multiplier);
    }).toList();

    String prizeSummary;
    if (multiplier > 1) {
      if (matchedRule.rewardType == 'voucher' || baseAmount > 0) {
        final totalInt = totalAmount == totalAmount.roundToDouble()
            ? totalAmount.toInt()
            : totalAmount;
        prizeSummary =
            '$multiplier × ${matchedRule.rewardValue} (إجمالي $totalInt جنيه)';
      } else {
        prizeSummary = '$multiplier × ${matchedRule.rewardValue}';
      }
    } else {
      prizeSummary = matchedRule.rewardValue;
    }

    return MatchedPromotionalRuleResult(
      rule: matchedRule,
      multiplier: multiplier,
      totalTriggerQuantity: totalTriggerQty > 0
          ? totalTriggerQty
          : matchedRule.minQuantity,
      totalRewardAmount: totalAmount,
      formattedPrizeSummary: prizeSummary,
      multipliedLinkedGifts: multipliedLinkedGifts,
    );
  }

  /// Evaluates ALL promotional rules against the receipt products,
  /// grouping by unique trigger product family so higher tiers beat lower tiers,
  /// and different products purchased together in the same receipt ALL produce rewards!
  static List<MatchedPromotionalRuleResult> matchAllWithMultipliers({
    AiReceiptAnalysisResult? result,
    List<ExtractedProductItem> extractedProducts = const [],
    required List<PromotionalRuleItem> promotionalRules,
    bool allowCampaignMultipliers = true,
  }) {
    if (promotionalRules.isEmpty) return [];

    final effectiveProducts =
        (result != null && result.extractedProducts.isNotEmpty)
        ? result.extractedProducts
        : extractedProducts;

    // 1. Gather all rule IDs identified explicitly by AI
    final Set<String> aiMatchedRuleIds = {};
    if (result != null) {
      if (result.matchedRuleIds.isNotEmpty) {
        aiMatchedRuleIds.addAll(result.matchedRuleIds);
      }
      if (result.matchedRuleId.trim().isNotEmpty) {
        aiMatchedRuleIds.add(result.matchedRuleId.trim());
      }
    }

    if (effectiveProducts.isEmpty) {
      final single = matchWithMultiplier(
        result: result,
        promotionalRules: promotionalRules,
        allowCampaignMultipliers: allowCampaignMultipliers,
      );
      return single != null ? [single] : [];
    }

    // 1. Group rules by canonical product family tokens (to resolve and bundle tiers of the same product family)
    final Map<String, List<PromotionalRuleItem>> rulesByProductGroup = {};
    // Spend rules that share the exact same barcode set compete for the same
    // money, whatever their wording or detected brand family, so they must
    // always share one pool (highest-value gift first, remainder to lower).
    final Map<String, int> spendPoolCounts = {};
    for (final rule in promotionalRules) {
      final pk = _spendPoolKey(rule);
      if (pk != null) spendPoolCounts[pk] = (spendPoolCounts[pk] ?? 0) + 1;
    }
    for (final rule in promotionalRules) {
      final familyKey = _getProductGroupKey(rule);
      final poolKey = _spendPoolKey(rule);
      final bool sharedPool =
          poolKey != null && (spendPoolCounts[poolKey] ?? 0) > 1;
      // Known product families keep their grouping unless the rule shares an
      // identical barcode pool with other spend rules.
      final key = sharedPool
          ? poolKey
          : familyKey.contains('_family')
              ? familyKey
              : (poolKey ?? familyKey);
      rulesByProductGroup.putIfAbsent(key, () => []).add(rule);
    }

    final List<MatchedPromotionalRuleResult> allMatchedResults = [];
    final Set<String> matchedRuleIds = {};
    final campaignBrands = _extractCampaignBrands(promotionalRules);

    // Track remaining unconsumed quantities per product item to guarantee Zero Double-Multiplication Invariant
    final Map<int, int> remainingItemQuantities = {};
    for (int i = 0; i < effectiveProducts.length; i++) {
      remainingItemQuantities[i] = getEffectiveProductQuantity(
        effectiveProducts[i],
      );
    }

    for (final group in rulesByProductGroup.values) {
      final isSpendGroup = group.any((r) => r.isSpendBased);

      if (isSpendGroup) {
        // Highest-value gift wins: rules on the same products are ranked by
        // gift value (known values first), then by spend tier. The spend is
        // handed out greedily: the best rule takes its share and only the
        // remainder can qualify lower tiers (never stacked on the same spend).
        final sortedGroup = List<PromotionalRuleItem>.from(group)
          ..sort(compareRulesByGiftValue);
        final spendTierOrder = List<PromotionalRuleItem>.from(group)
          ..sort((a, b) => b.effectiveMinSpend.compareTo(a.effectiveMinSpend));
        double? remainingPoolSpend;
        final Set<int> poolConsumedIndices = {};

        for (final rule in sortedGroup) {
          // Check combo brand requirement (e.g. Signal AND Closeup together)
          if (rule.isCombo && rule.requiredBrands.isNotEmpty) {
            final Set<String> foundBrands = {};
            for (int i = 0; i < effectiveProducts.length; i++) {
              final p = effectiveProducts[i];
              final rem = remainingItemQuantities[i] ?? 0;
              if (rem > 0) {
                final pNorm = _normalize(p.name);
                for (final rb in rule.requiredBrands) {
                  final rbNorm = _normalize(rb);
                  final isBarcodeMatch =
                      p.barcode.isNotEmpty &&
                      rule.selectedBarcodes.contains(p.barcode.trim());
                  if (pNorm.contains(rbNorm) || isBarcodeMatch) {
                    // If matched by barcode or name contains brand root, register brand
                    if (pNorm.contains(rbNorm) ||
                        _getBrandRootsInText(pNorm, rule.requiredBrands).contains(rbNorm)) {
                      foundBrands.add(rb);
                    } else if (isBarcodeMatch) {
                      // Look up in rule's selectedProductNames for corresponding catalog brand
                      bool matchedCatalogBrand = false;
                      for (final sel in rule.selectedProductNames) {
                        if (_normalize(sel).contains(rbNorm)) {
                          foundBrands.add(rb);
                          matchedCatalogBrand = true;
                          break;
                        }
                      }
                      if (!matchedCatalogBrand &&
                          (pNorm.contains('سيج') ||
                              pNorm.contains('كلوس') ||
                              rbNorm.length <= 4)) {
                        foundBrands.add(rb);
                      }
                    }
                  }
                }
              }
            }
            final hasAllRequiredBrands = rule.requiredBrands.every(
              (rb) => foundBrands.contains(rb),
            );
            if (!hasAllRequiredBrands) {
              continue;
            }
          }

          // Gather matching product indices and calculate total eligible spend
          final matchingProductIndices = <int>[];
          double totalEligibleSpend = 0.0;
          int totalMatchedQty = 0;

          for (int i = 0; i < effectiveProducts.length; i++) {
            final p = effectiveProducts[i];
            final remaining = remainingItemQuantities[i] ?? 0;
            if (remaining > 0 &&
                _matchesProduct(p, rule.triggerProduct, rule, campaignBrands, promotionalRules)) {
              final totalEffectiveQty = getEffectiveProductQuantity(p);
              final double actualFullItemSpend = p.actualLineSpend;
              final double itemSpend = totalEffectiveQty > 0
                  ? (actualFullItemSpend * (remaining / totalEffectiveQty))
                  : actualFullItemSpend;

              totalEligibleSpend += itemSpend;
              totalMatchedQty += remaining;
              matchingProductIndices.add(i);
            }
          }

          // Strict financial guard: total eligible spend on trigger products can never exceed
          // target company total spend on the receipt (AIR-37).
          if (result != null &&
              result.targetCompanyTotal > 0 &&
              totalEligibleSpend > result.targetCompanyTotal) {
            totalEligibleSpend = result.targetCompanyTotal;
          }

          // Spend already used by a higher-value rule of this pool is not available again.
          if (remainingPoolSpend != null && totalEligibleSpend > remainingPoolSpend) {
            totalEligibleSpend = remainingPoolSpend;
          }

          final isTopTierInGroup = spendTierOrder.first.id == rule.id;
          final bool isBoundedBracket = !isTopTierInGroup &&
              rule.hasSpendRange &&
              (rule.maxSpend != null && rule.maxSpend! > rule.minSpend);
          final effectiveMin = rule.effectiveMinSpend;
          final bool qualifiesMin =
              effectiveMin > 0 && totalEligibleSpend >= effectiveMin;
          final bool qualifiesMax = isTopTierInGroup ||
              rule.maxSpend == null ||
              rule.maxSpend! <= 0 ||
              rule.maxSpend! <= rule.minSpend ||
              totalEligibleSpend <= (rule.maxSpend! + rule.discountTolerance);

          if (qualifiesMin && qualifiesMax) {
            int count = 1;
            if (isBoundedBracket) {
              // Bounded middle bracket range (e.g. 95 to 139 EGP) qualifies as 1 bracket match
              count = 1;
            } else if (rule.allowMultipliers || allowCampaignMultipliers) {
              final divisor = rule.minSpend > 0 ? rule.minSpend : effectiveMin;
              final effectiveSpendForMultiplier = totalEligibleSpend +
                  (rule.discountTolerance > 0 ? rule.discountTolerance : 0.0);
              count = divisor > 0 ? (effectiveSpendForMultiplier ~/ divisor) : 1;
              if (count < 1) count = 1;
            }

            // Spend used by this rule; the remainder stays available to lower tiers.
            final double usedSpend = isBoundedBracket
                ? totalEligibleSpend
                : (rule.minSpend > 0 ? rule.minSpend : effectiveMin) * count;
            remainingPoolSpend = (totalEligibleSpend - usedSpend).clamp(0.0, double.infinity);
            poolConsumedIndices.addAll(matchingProductIndices);

            final double baseAmount = rule.totalVoucherValue > 0
                ? rule.totalVoucherValue
                : (rule.rewardAmount > 0 ? rule.rewardAmount : 0.0);
            final double totalAmount = baseAmount * count;

            final multipliedLinkedGifts = rule.linkedGifts.map((g) {
              return g.copyWith(quantity: g.quantity * count);
            }).toList();

            String prizeSummary;
            if (count > 1) {
              if (rule.rewardType == 'voucher' || baseAmount > 0) {
                final totalInt = totalAmount == totalAmount.roundToDouble()
                    ? totalAmount.toInt()
                    : totalAmount;
                prizeSummary =
                    '$count × ${rule.rewardValue} (إجمالي $totalInt جنيه)';
              } else {
                prizeSummary = '$count × ${rule.rewardValue}';
              }
            } else {
              prizeSummary = rule.rewardValue;
            }

            matchedRuleIds.add(rule.id);
            final matchingNames = <String>[];
            for (final idx in matchingProductIndices) {
              matchingNames.add(effectiveProducts[idx].name);
            }
            allMatchedResults.add(
              MatchedPromotionalRuleResult(
                rule: rule,
                multiplier: count,
                totalTriggerQuantity: totalMatchedQty,
                totalRewardAmount: totalAmount,
                formattedPrizeSummary: prizeSummary,
                multipliedLinkedGifts: multipliedLinkedGifts,
                qualifyingProductNames: matchingNames,
                qualifyingSpend: totalEligibleSpend,
              ),
            );

            if (remainingPoolSpend <= 0) break;
          }
        }
        // Consume the pool's products once its rules are resolved (no reuse by other groups)
        for (final idx in poolConsumedIndices) {
          remainingItemQuantities[idx] = 0;
        }
      } else {
        // Quantity-based rules within the family (highest tier first: e.g. 2 pcs before 1 pc)
        final sortedGroup = List<PromotionalRuleItem>.from(group)
          ..sort((a, b) => b.minQuantity.compareTo(a.minQuantity));

        for (final rule in sortedGroup) {
          // Calculate available unconsumed quantity specifically matching this rule
          final matchingProductIndices = <int>[];
          int availableQtyForRule = 0;
          for (int i = 0; i < effectiveProducts.length; i++) {
            final p = effectiveProducts[i];
            final remaining = remainingItemQuantities[i] ?? 0;
            if (remaining > 0 &&
                _matchesProduct(p, rule.triggerProduct, rule, campaignBrands, promotionalRules)) {
              availableQtyForRule += remaining;
              matchingProductIndices.add(i);
            }
          }

          if (rule.minQuantity > 0 && availableQtyForRule >= rule.minQuantity) {
            int count = 1;
            if (rule.allowMultipliers || allowCampaignMultipliers) {
              count = availableQtyForRule ~/ rule.minQuantity;
              if (count < 1) count = 1;
            }

            final int usedQty = count * rule.minQuantity;

            // Deduct consumed quantity strictly from the matching product items for this rule
            int qtyToDeduct = usedQty;
            for (final idx in matchingProductIndices) {
              if (qtyToDeduct <= 0) break;
              final curr = remainingItemQuantities[idx] ?? 0;
              final take = math.min(curr, qtyToDeduct);
              remainingItemQuantities[idx] = curr - take;
              qtyToDeduct -= take;
            }

            final double baseAmount = rule.totalVoucherValue > 0
                ? rule.totalVoucherValue
                : (rule.rewardAmount > 0 ? rule.rewardAmount : 0.0);
            final double totalAmount = baseAmount * count;

            final multipliedLinkedGifts = rule.linkedGifts.map((g) {
              return g.copyWith(quantity: g.quantity * count);
            }).toList();

            String prizeSummary;
            if (count > 1) {
              if (rule.rewardType == 'voucher' || baseAmount > 0) {
                final totalInt = totalAmount == totalAmount.roundToDouble()
                    ? totalAmount.toInt()
                    : totalAmount;
                prizeSummary =
                    '$count × ${rule.rewardValue} (إجمالي $totalInt جنيه)';
              } else {
                prizeSummary = '$count × ${rule.rewardValue}';
              }
            } else {
              prizeSummary = rule.rewardValue;
            }

            matchedRuleIds.add(rule.id);
            final matchingNames = <String>[];
            for (final idx in matchingProductIndices) {
              matchingNames.add(effectiveProducts[idx].name);
            }
            allMatchedResults.add(
              MatchedPromotionalRuleResult(
                rule: rule,
                multiplier: count,
                totalTriggerQuantity: usedQty,
                totalRewardAmount: totalAmount,
                formattedPrizeSummary: prizeSummary,
                multipliedLinkedGifts: multipliedLinkedGifts,
                qualifyingProductNames: matchingNames,
                qualifyingSpend: 0.0,
              ),
            );
          }
        }
      }
    }

    return allMatchedResults;
  }

  /// Analyzes why a receipt did not qualify for promotional rules and returns detailed human-readable reasons
  static List<String> getUnfulfilledPromotionReasons({
    AiReceiptAnalysisResult? result,
    List<ExtractedProductItem>? extractedProducts,
    required List<PromotionalRuleItem> promotionalRules,
  }) {
    if (promotionalRules.isEmpty) return [];

    final products =
        extractedProducts ??
        result?.extractedProducts ??
        const <ExtractedProductItem>[];

    // If receipt already matches any promotional rule, there are no unfulfilled reasons
    final matches = matchAllWithMultipliers(
      result: result,
      extractedProducts: products,
      promotionalRules: promotionalRules,
    );
    if (matches.isNotEmpty) return const [];

    if (products.isEmpty) {
      if (result != null && result.targetCompanyTotal > 0) {
        final minRuleSpend = promotionalRules
            .where((r) => r.isSpendBased)
            .map((r) => r.effectiveMinSpend)
            .fold<double>(double.infinity, math.min);
        if (minRuleSpend.isFinite && result.targetCompanyTotal < minRuleSpend) {
          return [
            'إجمالي مشتريات منتجات الشركة (${result.targetCompanyTotal.toInt()} ج.م) أقل من الحد الأدنى المطلوب للعرض (${minRuleSpend.toInt()} ج.م).',
          ];
        }
      }
      return [
        'الفاتورة لا تحتوي على أي من المنتجات المؤهلة لعروض الحملة الحالية.',
      ];
    }

    final reasons = <String>[];
    final campaignBrands = _extractCampaignBrands(promotionalRules);

    // Check spend-based and combo rules
    for (final rule in promotionalRules) {
      if (rule.isSpendBased) {
        if (rule.isCombo && rule.requiredBrands.isNotEmpty) {
          final Set<String> foundBrands = {};
          double currentSpend = 0.0;
          for (final p in products) {
            final pNorm = _normalize(p.name);
            for (final rb in rule.requiredBrands) {
              final rbNorm = _normalize(rb);
              if (pNorm.contains(rbNorm)) {
                foundBrands.add(rb);
              }
            }
            if (_matchesProduct(p, rule.triggerProduct, rule, campaignBrands, promotionalRules)) {
              currentSpend += p.actualLineSpend;
            }
          }

          final missingBrands = rule.requiredBrands
              .where((b) => !foundBrands.contains(b))
              .toList();
          final effectiveMin = rule.effectiveMinSpend;
          if (missingBrands.isNotEmpty) {
            reasons.add(
              '${rule.ruleTitle}: يشترط العرض شراء منتجات (${rule.requiredBrands.join(" و ")}) معاً في نفس الفاتورة. ينقص الفاتورة منتجات من (${missingBrands.join("، ")}).',
            );
          } else if (effectiveMin > 0 && currentSpend < effectiveMin) {
            final toleranceText = rule.discountTolerance > 0
                ? ' (مع سماحية ${rule.discountTolerance.toInt()} ج.م)'
                : '';
            reasons.add(
              '${rule.ruleTitle}: إجمالي مشتريات المنتجات المشروطة (${currentSpend.toInt()} ج.م) أقل من الحد الأدنى المطلوب للعرض (${rule.minSpend.toInt()} ج.م$toleranceText).',
            );
          }
        } else {
          double currentSpend = 0.0;
          for (final p in products) {
            if (_matchesProduct(p, rule.triggerProduct, rule, campaignBrands, promotionalRules)) {
              currentSpend += p.actualLineSpend;
            }
          }
          final effectiveMin = rule.effectiveMinSpend;
          if (currentSpend > 0 &&
              effectiveMin > 0 &&
              currentSpend < effectiveMin) {
            final toleranceText = rule.discountTolerance > 0
                ? ' (مع سماحية ${rule.discountTolerance.toInt()} ج.م)'
                : '';
            reasons.add(
              '${rule.ruleTitle}: إجمالي قيمة المشتريات المؤهلة (${currentSpend.toInt()} ج.م) أقل من الحد الأدنى للعرض (${rule.minSpend.toInt()} ج.م$toleranceText).',
            );
          }
        }
      } else {
        // Quantity-based rule check
        int count = 0;
        for (final p in products) {
          if (_matchesProduct(p, rule.triggerProduct, rule, campaignBrands, promotionalRules)) {
            count += getEffectiveProductQuantity(p);
          }
        }
        if (count > 0 && count < rule.minQuantity) {
          reasons.add(
            '${rule.ruleTitle}: تم رصد ($count) قطعة في الفاتورة، والحد الأدنى المطلوب للحصول على الهدية هو (${rule.minQuantity}) قطعة.',
          );
        }
      }
    }

    if (reasons.isEmpty) {
      if (products.any((p) => p.isTargetCompany)) {
        reasons.add(
          'المنتجات المشتراة تابعة للشركة لكنها غير مشمولة في شروط العروض الترويجية الحالية.',
        );
      } else {
        reasons.add(
          'الفاتورة لا تحتوي على أي من المنتجات المؤهلة لعروض الحملة الحالية.',
        );
      }
    }

    return reasons;
  }

  /// Verified Sunsilk promo twin bundle barcodes (Shampoo 350ml + Conditioner 350ml)
  static const Set<String> _knownSunsilkTwinBundleBarcodes = {
    '6221155611154', // صانسيلك شامبو نعومة الحرير 350 مل + بلسم (حزمة ترويجية مزدوجة 2 قطعة)
    '6221155611093', // صانسيلك شامبو أسود 350 مل + بلسم 350 مل
  };

  /// Verified Tresemme promo twin bundle barcodes (Shampoo 400ml + Conditioner 400ml)
  static const Set<String> _knownTresemmeTwinBundleBarcodes = {
    '6221155612182', // تريزيمي شامبو + بلسم 400 مل جوز الهند والصبار (حزمة ترويجية مزدوجة 2 قطعة)
    '6221155612199', // تريزيمي شامبو + بلسم 400 مل بوتنكس زبدة الشيا والكركديه (حزمة ترويجية مزدوجة 2 قطعة)
    '6221155612168', // تريزيمي شامبو + بلسم 400 مل كيراتين سموث (حزمة ترويجية مزدوجة 2 قطعة)
    '6221155612175', // تريزيمي شامبو + بلسم 400 مل إصلاح وحماية (حزمة ترويجية مزدوجة 2 قطعة)
    '6221155612144', // تريزيمي شامبو 400 مل + بلسم 400 مل
  };

  /// Unified set of all known twin bundle barcodes across brands
  static const Set<String> _knownTwinBundleBarcodes = {
    ..._knownSunsilkTwinBundleBarcodes,
    ..._knownTresemmeTwinBundleBarcodes,
  };

  /// Resolves the effective physical piece count of an item, taking into account twin bundles / shrink packs
  /// where POS registers 1 quantity for a 2-piece physical promotional pack.
  static int getEffectiveProductQuantity(ExtractedProductItem p) {
    int qty = p.quantity > 0 ? p.quantity : 1;
    final nameLower = _normalize(p.name);
    final cleanBarcode = p.barcode.trim();

    // 1. Verified Promo Twin Bundle Barcodes (Tresemme 400ml Promo Boxes, Sunsilk Twin Bundles, Axe/Rexona Promo Shrinks)
    if (cleanBarcode.isNotEmpty &&
        _knownTwinBundleBarcodes.contains(cleanBarcode)) {
      return qty * 2;
    }

    // 2. Explicit keyword indicators for bundle/shrink/twin packs
    final hasBundleName = RegExp(
      r'\b(شرنك|دبل|مزدوج|باندل|بندل|توين|2\s*قطعة|2\s*قطع|2\s*ق|2x|2\*)\b',
    ).hasMatch(nameLower);

    // 3. Hair care twin combo (Shampoo + Conditioner / شامبو + بلسم)
    // E.g. "تريزيمى شامبو + بلسم 400 ملى" or "صانسيلك شامبو نعومه الحرير 350 مل + بلسم" is physically 2 bottles (Shampoo + Conditioner @ combo price)
    final bool isShampooAndConditionerCombo =
        (nameLower.contains('شامبو') || nameLower.contains('shampoo')) &&
        (nameLower.contains('بلسم') || nameLower.contains('conditioner'));

    // If item has explicit bundle name or combo in title, it is legitimately 2 pieces
    if (hasBundleName || isShampooAndConditionerCombo) {
      return qty * 2;
    }

    // 4. Single large individual bottle guard (AIR-63):
    // Large individual bottles (600ml, 700ml, 900ml, 1000ml, 1L) inherently cost 200-350+ EGP as a single piece.
    // Unless explicitly stated in item title as a combo/twin pack above,
    // they must NEVER be inflated to 2 pieces based on price heuristics alone!
    final bool isSingleLargeBottle = RegExp(
      r'(600\s*م[ل|لي]|700\s*م[ل|لي]|900\s*م[ل|لي]|1000\s*م[ل|لي]|1\s*لت?ر|600\s*ml|700\s*ml|900\s*ml|1000\s*ml|1\s*l|٦٠٠\s*مل|٧٠٠\s*مل|٩٠٠\s*مل|٦٠٠\s*م|٧٠٠\s*م|٩٠٠\s*م)',
      caseSensitive: false,
    ).hasMatch(nameLower);

    if (isSingleLargeBottle) {
      return qty;
    }

    // 5. Price heuristic for hair care / Tresemme twin bundles (400ml promo boxes)
    // In Egyptian retail, a single standalone bottle of Tresemme 400ml is ~140-165 EGP.
    // A twin bundle / promo box is 240+ EGP (e.g. 295 EGP in Gomla Market, 299 EGP in Fathalla, 378 EGP gross).
    final bool isTresemmeHairCare =
        nameLower.contains('تريزيم') || nameLower.contains('tresemme');
    final double grossPrice = p.originalPrice ?? p.price;
    final bool hasTresemmeBundlePrice =
        isTresemmeHairCare &&
        (grossPrice >= 240.0 ||
            p.price >= 240.0 ||
            (p.price >= 220.0 && p.discountAmount >= 30.0));

    // 6. Price heuristic for Sunsilk twin bundles (350ml combo packs e.g. 184 EGP in Fathalla / Gomla Market)
    final bool isSunsilkHairCare =
        nameLower.contains('صنسيلك') ||
        nameLower.contains('صانسيلك') ||
        nameLower.contains('صنسلك') ||
        nameLower.contains('sunsilk');
    final bool hasSunsilkBundlePrice =
        isSunsilkHairCare &&
        (grossPrice >= 170.0 ||
            p.price >= 170.0 ||
            (p.price >= 160.0 && p.discountAmount >= 20.0));

    // 7. Price heuristic for deodorant bodyspray twin bundles (Axe / Rexona)
    // In retail, a single 150ml can is ~140-150 EGP. A twin bundle is 240+ EGP (e.g. 275 EGP in Fathalla, 335 EGP gross in Gomla Market).
    final bool isSpray =
        nameLower.contains('اسبراي') ||
        nameLower.contains('اكس') ||
        nameLower.contains('ريكسونا');
    final bool hasSprayBundlePrice =
        isSpray &&
        (grossPrice >= 240.0 ||
            p.price >= 240.0 ||
            (p.price >= 220.0 && p.discountAmount >= 30.0));

    if (hasSprayBundlePrice ||
        hasTresemmeBundlePrice ||
        hasSunsilkBundlePrice) {
      return qty * 2;
    }

    return qty;
  }

  static const Set<String> _noiseWords = {
    'شراء',
    'عرض',
    'من',
    'قطعة',
    'قطع',
    'علبة',
    'عبوة',
    'عدد',
    'مع',
    'على',
    'في',
    'او',
    'or',
    'and',
    'مل',
    'ml',
    'جرام',
    'جم',
    'g',
    'gm',
    'كيلو',
    'كجم',
    'kg',
    'اسنان',
    'أسنان',
    'سنان',
    'معجون',
    'فرشاة',
    'عناية',
    'حريمي',
    'حريمى',
    'رجالي',
    'رجال',
    'نسائي',
    'نسائى',
    'بناتي',
    'اطفال',
    'أطفال',
    'جديد',
    'قديم',
    'شكل',
    'اون',
    'أون',
    'on',
    'مزيل',
    'عرق',
    'منتجات',
    'منتج',
    'صنف',
    'اصناف',
    'أصناف',
    'باركود',
    'بار',
  };

  static const Set<String> _brandRoots = {
    'تريزيمي',
    'ريكسونا',
    'اكس',
    'كلير',
    'صنسيلك',
    'دوف',
    'لوكس',
    'لايفبوي',
    'سيجنال',
    'فازلين',
    'كلوس اب',
    'كلوساب',
    'الضحى',
    'الضحي',
    'الصحي',
    'الصحى',
    'المراعي',
    'المراعى',
    'almarai',
    'شومان',
    'shoman',
    'shouman',
    'الدره',
    'الدرة',
    'دره',
    'درة',
    'dorra',
    'هاينز',
    'heinz',
    'قودي',
    'قودى',
    'goody',
    'هارفست',
    'harvest',
    // Nestle FMCG sub-brands & categories
    'كيت كات',
    'كيت',
    'kitkat',
    'نسكافيه جولد',
    'نسكافية جولد',
    'nescafe gold',
    'نسكافيه',
    'نسكافية',
    'nescafe',
    'جولد',
    'gold',
    'كابتشينو',
    'cappuccino',
    'اسبرسو',
    'espresso',
    'سيريلاك',
    'cerelac',
    'اس26',
    'اس-26',
    's26',
    's-26',
    'بروجرس',
    'بروميل',
    'نسكويك',
    'nesquik',
    'نستله',
    'نستلة',
    'نسله',
    'nestle',
  };

  static const Set<String> _umbrellaCompanyNames = {
    'نستله',
    'نستلة',
    'نسله',
    'nestle',
    'يونيليفر',
    'unilever',
    'الضحى',
    'المراعي',
    'almarai',
    'هاينز',
    'heinz',
  };

  /// Filters out umbrella company names when specific sub-brands are present.
  static Set<String> _isolateSubBrands(Iterable<String> brands) {
    final normalized = brands.map((b) => _normalize(b)).where((b) => b.isNotEmpty).toSet();
    final specific = normalized.where((b) => !_umbrellaCompanyNames.contains(b)).toSet();
    return specific.isNotEmpty ? specific : normalized;
  }

  static final RegExp _explicitSizeRegex = RegExp(
    r'(\d{2,4})\s*(ملل|ملى|ملي|مل|ml|جرام|g|لتر|l)\b',
  );

  static final RegExp _standaloneFmcgVolumeRegex = RegExp(
    r'\b(1000|900|750|700|650|600|550|450|400|360|350|250|220|200|190|180|150)\b',
  );

  static int? _extractSizeMl(String text) {
    var norm = _normalize(text);
    // Strip voucher amounts and currency numbers to prevent voucher/price collisions with product sizes
    norm = norm.replaceAll(
      RegExp(r'(?:فوتشر|فاوتشر|فواتشر|فاوشر|قسيمة|قسيمه|كوبون|خصم|مبلغ|voucher|كاش باك|كاش)\s*\d+'),
      '',
    );
    norm = norm.replaceAll(
      RegExp(r'\d+\s*(?:ج\.م|ج\s*\.\s*م|جنيه|جنيها|ج|egp|le)\b'),
      '',
    );

    final match = _explicitSizeRegex.firstMatch(norm);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    final standaloneMatch = _standaloneFmcgVolumeRegex.firstMatch(norm);
    if (standaloneMatch != null) {
      return int.tryParse(standaloneMatch.group(1)!);
    }
    return null;
  }

  /// Extracts the required purchase volume from a promotional rule's trigger or condition clause.
  /// Isolates the trigger condition (e.g. "اشترى قطعة كلير 600") from the reward clause
  /// (e.g. "واحصل على قطعة كلير 360"), preventing reward volumes from leaking into trigger matching.
  static int? _extractRuleRequiredSize(PromotionalRuleItem? rule, String triggerProduct) {
    // 0. Spend rules (by_spend or minSpend > 0) never have bottle size requirements!
    if (rule != null && (rule.conditionType == 'by_spend' || rule.minSpend > 0)) {
      return null;
    }

    // 1. Check clean triggerProduct (excluding catalog counts like "(52 صنف)")
    final cleanTrigger = triggerProduct.replaceAll(
      RegExp(r'\(\s*\d+\s*(?:صنف|أصناف|اصناف|باركود|منتج|منتجات)[^\)]*\)'),
      '',
    );
    final triggerSize = _extractSizeMl(cleanTrigger);
    if (triggerSize != null) return triggerSize;

    // 2. If trigger doesn't have size, extract strictly from the condition clause of ruleTitle
    if (rule != null && rule.ruleTitle.isNotEmpty) {
      // Split raw title first before normalization so arrows (->, =>, →) are not stripped by regex
      final rawParts = rule.ruleTitle.split(
        RegExp(r'(?:->|=>|→|احصل|واحصل|اكسب|واكسب|هديه|هدية|مجانا|مجاناً|قسيمة|قسيمه|فوتشر|فاوتشر|فواتشر|فاوشر|كوبون|voucher)'),
      );
      final rawCondition = rawParts.first;

      final titleNorm = _normalize(rawCondition);

      // Ensure condition clause doesn't confuse excluded sizes with required sizes
      final conditionWithoutExclusion = titleNorm.replaceAll(
        RegExp(
          r'(?:ماعدا|ما\s*عدا|معادا|مع\s*عدا|باستثناء|استثناء|بدون|غير|except|excluding)\s*(?:الـ|ال)?\s*\d{2,4}\s*(?:ملل|ملى|ملي|مل|ml)?',
        ),
        '',
      );
      return _extractSizeMl(conditionWithoutExclusion);
    }

    return null;
  }

  /// Extracts explicitly excluded sizes from a rule (e.g. "ما عدا 180 مل", "معادا الـ 180 ملل")
  static int? _extractRuleExcludedSize(PromotionalRuleItem? rule, String triggerProduct) {
    final text = '${rule?.ruleTitle ?? ''} $triggerProduct';
    final norm = _normalize(text);
    final match = RegExp(
      r'(?:ماعدا|ما\s*عدا|معادا|مع\s*عدا|باستثناء|استثناء|بدون|غير|except|excluding)\s*(?:الـ|ال)?\s*(\d{2,4})\s*(?:ملل|ملى|ملي|مل|ml)?',
    ).firstMatch(norm);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  static Set<String> _getBrandRootsInText(String text, [Iterable<String>? dynamicBrands]) {
    final norm = _normalize(text);
    final brands = <String>{};
    final allBrandRoots = (dynamicBrands != null && dynamicBrands.isNotEmpty)
        ? {..._brandRoots, ...dynamicBrands.map((b) => _normalize(b)).where((b) => b.isNotEmpty)}
        : _brandRoots;

    for (final brand in allBrandRoots) {
      final brandNorm = _normalize(brand);
      if (brandNorm.isEmpty) continue;
      if (brandNorm == 'اكس' || brandNorm == 'axe') {
        // Must match standalone word 'اكس' / 'axe', NOT Arabic words derived from root (ك-س-ب) like 'واكسب', 'اكسب', 'مكسب'
        final words = norm.split(' ');
        final hasAxe = words.any((w) => (w == 'اكس' || w == 'axe') && !w.contains('كسب'));
        if (hasAxe) brands.add(brandNorm);
      } else if (norm.contains(brandNorm)) {
        brands.add(brandNorm);
      }
    }
    return brands;
  }

  static bool _ruleHasItemScope(PromotionalRuleItem? rule) =>
      rule != null &&
      (rule.selectedBarcodes.any((b) => b.trim().isNotEmpty) ||
          rule.selectedProductNames.any((n) => n.trim().isNotEmpty) ||
          rule.requiredBrands.any((b) => b.trim().isNotEmpty));

  static bool _matchesProduct(
    ExtractedProductItem product,
    String triggerProduct, [
    PromotionalRuleItem? rule,
    Iterable<String>? dynamicBrands,
    List<PromotionalRuleItem>? siblingRules,
    bool allowCompanySpendBypass = true,
  ]) {
    // Company spend bypass: a target-company product counts toward a spend rule
    // even when its (often OCR-misspelled) name doesn't match the rule's brands.
    // Exception: if the rule has its own item scope (barcodes / names / brands)
    // and the product strictly belongs to ANOTHER scoped spend rule of the same
    // campaign, it must not leak into this rule (e.g. Dairy Milk products being
    // counted on the Oreo rules). Strict = matched without the bypass.
    bool isCompanySpendRule = allowCompanySpendBypass &&
        rule != null &&
        (rule.isSpendBased || rule.conditionType == 'by_spend') &&
        product.isTargetCompany;
    if (isCompanySpendRule &&
        _ruleHasItemScope(rule) &&
        siblingRules != null &&
        siblingRules.length > 1) {
      final belongsToOtherScopedRule = siblingRules.any((other) =>
          other.id != rule.id &&
          (other.isSpendBased || other.conditionType == 'by_spend') &&
          _ruleHasItemScope(other) &&
          _matchesProduct(product, other.triggerProduct, other, dynamicBrands,
              null, false));
      if (belongsToOtherScopedRule &&
          !_matchesProduct(
              product, triggerProduct, rule, dynamicBrands, null, false)) {
        isCompanySpendRule = false;
      }
    }

    if (!isCompanySpendRule &&
        triggerProduct.trim().isEmpty &&
        (rule == null ||
            (rule.selectedBarcodes.isEmpty &&
                rule.selectedProductNames.isEmpty &&
                rule.requiredBrands.isEmpty))) {
      return false;
    }

    // 0. Strict Multi-Tenant Brand Isolation Guard:
    // A competitor product (isTargetCompany == false) must NEVER match general promotional rules
    // unless explicitly selected by barcode or exact product name in the campaign's catalog.
    if (!product.isTargetCompany) {
      final cleanBarcode = product.barcode.trim();
      final bool isExplicitBarcodeMatch = cleanBarcode.isNotEmpty &&
          rule != null &&
          rule.selectedBarcodes.isNotEmpty &&
          (rule.selectedBarcodes.contains(cleanBarcode) ||
              (cleanBarcode.length >= 10 &&
                  rule.selectedBarcodes.any((b) =>
                      b.startsWith(cleanBarcode) ||
                      cleanBarcode.startsWith(b))));

      final bool isExplicitNameMatch = rule != null &&
          rule.selectedProductNames.isNotEmpty &&
          rule.selectedProductNames.any(
            (sel) => _normalize(sel) == _normalize(product.name),
          );

      if (!isExplicitBarcodeMatch && !isExplicitNameMatch) {
        return false;
      }
    }

    final Set<String> allDynamicBrands = {
      ...?dynamicBrands,
      if (rule != null) ...rule.requiredBrands,
    };

    // 0. Exact catalog-name match: a product whose name equals one of the
    // rule's selected product names belongs to the rule's item scope.
    if (rule != null && rule.selectedProductNames.isNotEmpty) {
      final nameNorm = _normalize(product.name);
      if (nameNorm.isNotEmpty &&
          rule.selectedProductNames.any((sel) => _normalize(sel) == nameNorm)) {
        return true;
      }
    }

    // 0. Golden Barcode Priority Match:
    // If the rule has selected barcodes from catalog, or trigger contains barcode, match immediately!
    final cleanBarcode = product.barcode.trim();
    if (cleanBarcode.isNotEmpty) {
      if (rule != null && rule.selectedBarcodes.isNotEmpty) {
        if (rule.selectedBarcodes.contains(cleanBarcode)) {
          return true;
        }
        // Handle 12-digit vs 13-digit retail POS variations (e.g. 622300066001 vs 6223000660010 in Hyper One)
        if (cleanBarcode.length >= 10) {
          final matchesCatalogPrefix = rule.selectedBarcodes.any((b) =>
              b.startsWith(cleanBarcode) || cleanBarcode.startsWith(b));
          if (matchesCatalogPrefix) {
            return true;
          }
        }
      }
      if (cleanBarcode.length >= 6 && triggerProduct.contains(cleanBarcode)) {
        return true;
      }
      if (_knownSunsilkTwinBundleBarcodes.contains(cleanBarcode) &&
          (_normalize(triggerProduct).contains('صنسيلك') ||
              _normalize(triggerProduct).contains('صانسيلك') ||
              _normalize(triggerProduct).contains('sunsilk'))) {
        return true;
      }
      if (_knownTresemmeTwinBundleBarcodes.contains(cleanBarcode) &&
          (_normalize(triggerProduct).contains('تريزيم') ||
              _normalize(triggerProduct).contains('tresemme'))) {
        return true;
      }
    }

    final pNorm = _normalize(product.name);
    final triggerNorm = _normalize(triggerProduct);
    final ruleTitleNorm = rule != null ? _normalize(rule.ruleTitle) : '';
    final fullRuleContext = '$triggerNorm $ruleTitleNorm';

    // 0.04 Strict Brand Root Anchor Guard:
    // If the rule explicitly defines requiredBrands (e.g. ['تريزيمي']), those brands MUST strictly take precedence
    // and lock the allowed brand scope, preventing broad catalog trigger strings (e.g. Unilever 497 items) from leaking foreign brands!
    final Set<String> rawTriggerBrands = <String>{};
    if (rule != null && rule.requiredBrands.isNotEmpty) {
      for (final rb in rule.requiredBrands) {
        final rbNorm = _normalize(rb);
        if (rbNorm.isNotEmpty) {
          rawTriggerBrands.add(rbNorm);
        }
        final roots = _getBrandRootsInText(rbNorm, allDynamicBrands);
        rawTriggerBrands.addAll(roots);
      }
    } else {
      rawTriggerBrands.addAll(_getBrandRootsInText(triggerProduct, allDynamicBrands));
      if (rule != null && rawTriggerBrands.isEmpty) {
        rawTriggerBrands.addAll(_getBrandRootsInText(rule.ruleTitle, allDynamicBrands));
      }
    }
    // Isolate sub-brands so umbrella parent company names (e.g. نستله / يونيليفر) don't bleed across sub-brands
    final triggerBrands = _isolateSubBrands(rawTriggerBrands);

    if (triggerBrands.isNotEmpty) {
      final Set<String> productBrands = _getBrandRootsInText(pNorm, triggerBrands);
      final bool hasMatchingBrand = triggerBrands.any(
        (tb) => productBrands.contains(tb) || pNorm.contains(tb),
      );
      // In spend rules for a company, if AI confirmed product belongs to target company, do not reject solely on brand name root
      final bool isCompanySpendAnchor =
          isCompanySpendRule && rule?.conditionType == 'by_spend';
      if (!hasMatchingBrand && !isCompanySpendAnchor) {
        return false;
      }
    }

    final int? pSize = _extractSizeMl(pNorm);

    // 0.045 Strict Volume & Pack-Size Segregation Guard (AIR-55):
    // 1. Explicit Size Exclusion (e.g. "ما عدا 180 مل", "معادا الـ 180 ملل"):
    final int? ruleExSize = _extractRuleExcludedSize(rule, triggerProduct);
    if (ruleExSize != null && pSize != null && ruleExSize == pSize) {
      return false;
    }

    // 2. Strict Required Bottle Volume Guard (e.g. 600ml vs 550ml):
    final int? ruleReqSize = _extractRuleRequiredSize(rule, triggerProduct);
    if (ruleReqSize != null && pSize != null && ruleReqSize != pSize) {
      return false;
    }

    // 0.05 Strict Product Form & Physical Category Collision Guard (حارس التصنيف الفيزيائي والفرعي للمنتج):
    // Disallows matching spray rules against roll-on products, coffee against confectionery, etc.
    final bool isProductRollOn =
        pNorm.contains('رول اون') ||
        pNorm.contains('رول') ||
        pNorm.contains('روول') ||
        pNorm.contains('ستيك') ||
        pNorm.contains('roll on') ||
        pNorm.contains('rollon') ||
        pNorm.contains('stick');
    final bool isProductSpray =
        pNorm.contains('اسبراي') ||
        pNorm.contains('بخاخ') ||
        pNorm.contains('spray') ||
        pNorm.contains('bodyspray') ||
        (pNorm.contains('150 مل') && !isProductRollOn);
    final bool isProductShampoo =
        pNorm.contains('شامبو') || pNorm.contains('shampoo');
    final bool isProductToothpaste =
        pNorm.contains('معجون') ||
        pNorm.contains('toothpaste') ||
        pNorm.contains('تسوس') ||
        pNorm.contains('سيجنال') ||
        pNorm.contains('كلوس اب') ||
        pNorm.contains('كلوساب');

    final bool isProductCoffee =
        pNorm.contains('نسكافيه') ||
        pNorm.contains('نسكافية') ||
        pNorm.contains('nescafe') ||
        pNorm.contains('جولد') ||
        pNorm.contains('كابتشينو') ||
        pNorm.contains('لاتيه') ||
        pNorm.contains('موكا') ||
        pNorm.contains('اسبرسو') ||
        pNorm.contains('قهوة') ||
        pNorm.contains('coffee');

    final bool isProductConfectionery =
        pNorm.contains('كيت') ||
        pNorm.contains('kitkat') ||
        pNorm.contains('شيكولاتة') ||
        pNorm.contains('شوكولاتة') ||
        pNorm.contains('شوكولاته') ||
        pNorm.contains('ويفر') ||
        pNorm.contains('لوتس') ||
        pNorm.contains('براوني') ||
        pNorm.contains('كراميل صنداي') ||
        pNorm.contains('شانكي') ||
        pNorm.contains('سناك');

    final bool isProductInfantFormula =
        pNorm.contains('اس26') ||
        pNorm.contains('اس 26') ||
        pNorm.contains('اس-26') ||
        pNorm.contains('s26') ||
        pNorm.contains('s-26') ||
        pNorm.contains('سيريلاك') ||
        pNorm.contains('cerelac') ||
        pNorm.contains('بروجرس') ||
        pNorm.contains('بروميل') ||
        pNorm.contains('حليب اطفال');

    final bool isTriggerRollOn =
        fullRuleContext.contains('رول') ||
        fullRuleContext.contains('roll') ||
        fullRuleContext.contains('ستيك');
    final bool isTriggerSpray =
        fullRuleContext.contains('اسبراي') ||
        fullRuleContext.contains('بخاخ') ||
        fullRuleContext.contains('spray') ||
        (fullRuleContext.contains('150 مل') && !isTriggerRollOn);
    final bool isTriggerShampoo =
        fullRuleContext.contains('شامبو') ||
        fullRuleContext.contains('shampoo') ||
        RegExp(r'\b(sh|shmp|shamp)\b').hasMatch(fullRuleContext);
    final bool isTriggerToothpaste =
        fullRuleContext.contains('معجون') ||
        fullRuleContext.contains('toothpaste') ||
        fullRuleContext.contains('فم') ||
        fullRuleContext.contains('oral') ||
        (rule != null &&
            rule.requiredBrands.any((b) => b.contains('سيجنال') || b.contains('كلوس')));

    final bool isTriggerCoffee =
        fullRuleContext.contains('نسكافيه') ||
        fullRuleContext.contains('nescafe') ||
        fullRuleContext.contains('كابتشينو') ||
        fullRuleContext.contains('اسبرسو') ||
        fullRuleContext.contains('قهوة') ||
        (fullRuleContext.contains('جولد') &&
            !fullRuleContext.contains('اس26') &&
            !fullRuleContext.contains('اس-26') &&
            !fullRuleContext.contains('سيريلاك'));

    final bool isTriggerConfectionery =
        fullRuleContext.contains('كيت') ||
        fullRuleContext.contains('kitkat') ||
        fullRuleContext.contains('شيكولاتة') ||
        fullRuleContext.contains('شوكولاتة') ||
        fullRuleContext.contains('ويفر');

    final bool isTriggerInfantFormula =
        fullRuleContext.contains('اس26') ||
        fullRuleContext.contains('اس 26') ||
        fullRuleContext.contains('اس-26') ||
        fullRuleContext.contains('s26') ||
        fullRuleContext.contains('سيريلاك') ||
        fullRuleContext.contains('حليب اطفال');

    // Reject deodorant or spray or roll-on or shampoo matching oral care / toothpaste rules (unless trigger also covers that category):
    if (isProductShampoo && isTriggerToothpaste && !isTriggerShampoo) {
      return false;
    }
    if ((isProductSpray || isProductRollOn) &&
        isTriggerToothpaste &&
        !isTriggerSpray &&
        !isTriggerRollOn) {
      return false;
    }
    // Reject roll-on products matching pure spray rules:
    if (isProductRollOn &&
        !isProductSpray &&
        isTriggerSpray &&
        !isTriggerRollOn) {
      return false;
    }
    // Reject spray products matching pure roll-on rules:
    if (isProductSpray &&
        !isProductRollOn &&
        isTriggerRollOn &&
        !isTriggerSpray) {
      return false;
    }
    // Reject shampoo matching deodorant or toothpaste rules:
    if (isProductShampoo &&
        (isTriggerSpray || isTriggerRollOn || isTriggerToothpaste) &&
        !isTriggerShampoo) {
      return false;
    }
    // Reject toothpaste matching shampoo or deodorant rules:
    if (isProductToothpaste &&
        (isTriggerShampoo || isTriggerSpray || isTriggerRollOn) &&
        !isTriggerToothpaste) {
      return false;
    }
    // Reject coffee products matching confectionery/chocolate rules:
    if (isProductCoffee && isTriggerConfectionery && !isTriggerCoffee) {
      return false;
    }
    // Reject confectionery/chocolate matching coffee rules:
    if (isProductConfectionery && isTriggerCoffee && !isTriggerConfectionery) {
      return false;
    }
    // Reject coffee matching infant nutrition:
    if (isProductCoffee && isTriggerInfantFormula && !isTriggerCoffee) {
      return false;
    }
    // Reject infant formula matching coffee or chocolate rules:
    if (isProductInfantFormula &&
        (isTriggerCoffee || isTriggerConfectionery) &&
        !isTriggerInfantFormula) {
      return false;
    }

    // 0.051 Strict Sub-Brand Segregation: Nescafe Gold vs Regular Nescafe & Infant Nutrition (AIR-84):
    // When a promotional rule specifically targets Nescafe Gold, standard/general Nescafe items
    // (such as Nescafe Classic, Red Mug, Black, 3-in-1 standard) that lack the "جولد" / "gold" descriptor
    // must NEVER match the Nescafe Gold promotional rule!
    final bool isTriggerNescafeGold =
        fullRuleContext.contains('نسكافيه جولد') ||
        fullRuleContext.contains('نسكافية جولد') ||
        fullRuleContext.contains('nescafe gold') ||
        (rule != null &&
            rule.requiredBrands.any((b) =>
                _normalize(b).contains('نسكافيه جولد') ||
                _normalize(b).contains('نسكافية جولد') ||
                _normalize(b).contains('nescafe gold')));

    final bool isProductNescafeGold =
        (pNorm.contains('نسكافيه') ||
            pNorm.contains('نسكافية') ||
            pNorm.contains('nescafe') ||
            pNorm.contains('نسله') ||
            pNorm.contains('نستله') ||
            pNorm.contains('نستلة')) &&
        (pNorm.contains('جولد') || pNorm.contains('gold'));

    if (isTriggerNescafeGold && !isProductNescafeGold) {
      return false;
    }

    // 0.06 Selected Product Names from catalog match:
    if (rule != null && rule.selectedProductNames.isNotEmpty) {
      for (final selName in rule.selectedProductNames) {
        final selNorm = _normalize(selName);
        if (pNorm == selNorm ||
            pNorm.contains(selNorm) ||
            selNorm.contains(pNorm)) {
          return true;
        }

        // Token-based matching: handles supermarket POS descriptor omissions / additions
        // (e.g. POS prints "الضحى أرز 1كجم" while catalog has "الضحى ارز مصرى 1ك")
        final pWords = pNorm
            .split(' ')
            .where((w) => w.isNotEmpty && !_noiseWords.contains(w))
            .toList();
        final selWords = selNorm
            .split(' ')
            .where((w) => w.isNotEmpty && !_noiseWords.contains(w))
            .toSet();

        if (pWords.length >= 2) {
          const optionalDescriptors = {
            'مصري',
            'مصرى',
            'فاخر',
            'ممتاز',
            'سادة',
            'ساده',
            'طبيعي',
            'طبيعى',
            'اصلي',
            'اصلى',
            'نقي',
            'نقى',
            'عادي',
            'عادى',
            'ابيض',
            'بلدي',
            'بلدى',
          };
          final pCoreWords = pWords
              .where((w) => !optionalDescriptors.contains(w))
              .toList();
          final selCoreWords = selWords
              .where((w) => !optionalDescriptors.contains(w))
              .toSet();

          if (pCoreWords.length >= 2 &&
              pCoreWords.every((w) => selCoreWords.contains(w))) {
            return true;
          }
          if (selCoreWords.length >= 2 &&
              selCoreWords.every((w) => pCoreWords.contains(w))) {
            return true;
          }
        }
      }
    }

    // 0.08 Brand Rule Match (including Company-Level Spend Rules):
    // If the rule has requiredBrands OR is a spend-based rule mentioning a brand in its title/trigger:
    final Set<String> rawEffectiveRuleBrands = <String>{};
    if (rule != null && rule.requiredBrands.isNotEmpty) {
      for (final rb in rule.requiredBrands) {
        final rbNorm = _normalize(rb);
        if (rbNorm.isNotEmpty) {
          rawEffectiveRuleBrands.add(rbNorm);
        }
        final roots = _getBrandRootsInText(rbNorm, allDynamicBrands);
        rawEffectiveRuleBrands.addAll(roots);
      }
    } else if (rule != null) {
      rawEffectiveRuleBrands.addAll(_getBrandRootsInText(rule.ruleTitle, allDynamicBrands));
      rawEffectiveRuleBrands.addAll(_getBrandRootsInText(triggerProduct, allDynamicBrands));
    }
    final effectiveRuleBrands = _isolateSubBrands(rawEffectiveRuleBrands);

    final bool isCompanyProductSpendRule =
        isCompanySpendRule && rule?.conditionType == 'by_spend';

    if (effectiveRuleBrands.isNotEmpty || isCompanyProductSpendRule) {
      final Set<String> productBrands =
          _getBrandRootsInText(pNorm, effectiveRuleBrands);
      final bool hasRuleBrand = effectiveRuleBrands.isEmpty ||
          effectiveRuleBrands.any((rb) {
            final rbNorm = _normalize(rb);
            return productBrands.contains(rbNorm) || pNorm.contains(rbNorm);
          });

      if (hasRuleBrand || isCompanyProductSpendRule) {
        // Form & category validation
        final bool hasCategoryFilter =
            isTriggerToothpaste ||
            isTriggerSpray ||
            isTriggerRollOn ||
            isTriggerShampoo ||
            isTriggerCoffee ||
            isTriggerConfectionery ||
            isTriggerInfantFormula;
        final bool matchesCategory =
            (isTriggerToothpaste && isProductToothpaste) ||
            (isTriggerSpray && isProductSpray) ||
            (isTriggerRollOn && isProductRollOn) ||
            (isTriggerShampoo && isProductShampoo) ||
            (isTriggerCoffee && isProductCoffee) ||
            (isTriggerConfectionery && isProductConfectionery) ||
            (isTriggerInfantFormula && isProductInfantFormula);

        if (hasCategoryFilter && !matchesCategory) {
          // Skip if product category does not match any triggered categories
        } else {
          // Volume/size conflict guard for brand-level rules:
          // If the rule specifies a volume (e.g. 600ml or 550ml), and the product specifies a different volume, skip!
          if (ruleExSize != null && pSize != null && ruleExSize == pSize) {
            // Skip due to size exclusion
          } else if (ruleReqSize != null && pSize != null && ruleReqSize != pSize) {
            // Skip due to size mismatch
          } else {
            return true;
          }
        }
      }
    }

    // Direct barcode matching if trigger contains barcodes or known promo bundle barcodes:
    if (product.barcode.isNotEmpty) {
      final cleanBarcode = product.barcode.trim();
      if (triggerProduct.contains(cleanBarcode)) return true;
      if (_knownSunsilkTwinBundleBarcodes.contains(cleanBarcode) &&
          (triggerNorm.contains('صنسيلك') ||
              triggerNorm.contains('صانسيلك') ||
              triggerNorm.contains('sunsilk'))) {
        return true;
      }
      if (_knownTresemmeTwinBundleBarcodes.contains(cleanBarcode) &&
          (triggerNorm.contains('تريزيم') ||
              triggerNorm.contains('tresemme'))) {
        return true;
      }
    }

    final int? productSize = _extractSizeMl(pNorm);

    // Strip parenthetical catalog metadata (e.g. "(23 صنف - 19 باركود)", "(457 صنف)")
    final cleanTrigger = triggerProduct.replaceAll(
      RegExp(r'\(\s*\d+\s*(?:صنف|أصناف|اصناف|باركود|منتج|منتجات)\s*(?:-\s*\d+\s*(?:صنف|أصناف|اصناف|باركود|منتج|منتجات))?\s*\)'),
      '',
    );

    final parts = cleanTrigger.split(
      RegExp(r'[|؛,،/\+\n]|(\s+أو\s+)|(\s+or\s+)|(\s+و\s+)', caseSensitive: false),
    );

    for (final part in parts) {
      final partNorm = _normalize(part);
      if (partNorm.isEmpty) continue;

      final bool isPartRollOn =
          partNorm.contains('رول') ||
          partNorm.contains('roll') ||
          partNorm.contains('ستيك');
      final bool isPartSpray =
          partNorm.contains('اسبراي') ||
          partNorm.contains('بخاخ') ||
          partNorm.contains('spray') ||
          partNorm.contains('150 مل');

      // Skip part if format conflicts with the physical product
      if (isProductRollOn && !isProductSpray && isPartSpray && !isPartRollOn) {
        continue;
      }
      if (isProductSpray && !isProductRollOn && isPartRollOn && !isPartSpray) {
        continue;
      }

      final int? partSize = _extractSizeMl(partNorm);
      // Volume/size conflict guard: If part specifies volume (e.g. 400ml) and product specifies a different volume (e.g. 600ml), reject!
      if (partSize != null && productSize != null && partSize != productSize) {
        continue;
      }
      // If the trigger explicitly specifies a volume (e.g. 400ml) anywhere in the rule, but the product has a conflicting volume (e.g. 600ml), reject generic parts
      if (partSize == null && productSize != null) {
        final int? triggerReqSize = _extractRuleRequiredSize(rule, triggerProduct);
        if (triggerReqSize != null && triggerReqSize != productSize) {
          continue;
        }
      }

      // 1. Direct substring match (product name must contain the trigger phrase)
      if (pNorm.contains(partNorm)) return true;

      // 2. Phrase matching (all non-noise words in phrase must be present or fuzzy matched)
      final phraseWords = partNorm
          .split(' ')
          .where((w) => w.length >= 2 && !_noiseWords.contains(w))
          .toList();

      if (phraseWords.isNotEmpty) {
        final pWords = pNorm
            .split(' ')
            .where((w) => w.length >= 2 && !_noiseWords.contains(w))
            .toList();
        final bool allWordsMatched = phraseWords.every((targetWord) {
          if (pWords.contains(targetWord) || pNorm.contains(targetWord)) {
            return true;
          }
          return pWords.any((pw) => _isFuzzyWordMatch(pw, targetWord, allDynamicBrands));
        });
        if (allWordsMatched) return true;
      }
    }

    return false;
  }

  static bool _isFuzzyWordMatch(
    String w1,
    String w2, [
    Iterable<String>? dynamicBrands,
  ]) {
    if (w1 == w2) return true;
    if (w1.isEmpty || w2.isEmpty) return false;

    // Brand words require exact canonical root match
    if (_brandRoots.contains(w1) || _brandRoots.contains(w2)) {
      return false;
    }
    if (dynamicBrands != null) {
      for (final b in dynamicBrands) {
        final bNorm = _normalize(b);
        if (bNorm.isNotEmpty && (w1 == bNorm || w2 == bNorm)) {
          return false;
        }
      }
    }

    // Both words must share the same first character to prevent false phonetic matches (e.g. حريمي vs تريزيمي)
    if (w1[0] != w2[0]) return false;

    // Substring contains for prefix/suffix
    if (w1.length >= 4 && w2.length >= 4) {
      if (w1.startsWith(w2) || w2.startsWith(w1)) return true;
    }

    // Levenshtein edit distance check (allow 1 single character edit only for words of length >= 5)
    final distance = _levenshtein(w1, w2);
    final maxLen = math.max(w1.length, w2.length);
    if (maxLen >= 5 && distance <= 1) return true;

    return false;
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    final v0 = List<int>.filled(t.length + 1, 0);
    final v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i <= t.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[t.length];
  }

  static String _normalize(String s) {
    var str = s.toEnglishDigits(convertDecimal: false).toLowerCase().trim();
    // Normalize Arabic diacritics / tatweel
    str = str.replaceAll(RegExp(r'[\u064B-\u0652\u0640]'), '');
    str = str.replaceAll(RegExp(r'[أإآ]'), 'ا');
    str = str.replaceAll('ى', 'ي');
    str = str.replaceAll('ة', 'ه');
    str = str.replaceAll('ؤ', 'و');
    str = str.replaceAll('ئ', 'ي');

    // Separate number from unit size (e.g. 400مل -> 400 مل, 150ml -> 150 ml, 400ملل -> 400 ملل)
    str = str.replaceAllMapped(
      RegExp(r'(\d+)\s*(ملى|ملي|ملل|مل|جرام|جم|لتر|كجم|g|ml|kg|l)'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );

    // POS Concatenated Volume and Price Separation (e.g. 600132.00 -> 600 132.00, 300160.00 -> 300 160.00, 150218.00 -> 150 218.00)
    str = str.replaceAllMapped(
      RegExp(r'\b(1000|900|750|700|650|600|550|500|450|400|360|350|300|250|220|200|180|150|120|100|90|75|50)(\d{2,4}\.\d{2})\b'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );

    // Spaced Al-Durra brand normalization in thermal POS (e.g. "د ر ه عرض كاتشب", "د ر ة" -> "دره")
    str = str.replaceAllMapped(
      RegExp(r'(^|\s)د\s+ر\s+[هة]($|\s)'),
      (m) => '${m.group(1)}دره${m.group(2)}',
    );

    // POS Truncated & Clipped Brand Handler (e.g. "كس اسبراى", "كس رول", "ايس شيل" -> "اكس اسبراي")
    str = str.replaceAllMapped(
      RegExp(
        r'(^|\s)كس\s+(اسبراي|اسبرى|اسبري|اسبراى|سبراي|سبراى|رول|بخاخ|ايس|بلاك|دارك|افريكان|مارين|ابولو|شيل|شارج|جولد|كولد|تيمبتيشن)',
      ),
      (m) => '${m.group(1)}اكس ${m.group(2)}',
    );
    str = str.replaceAllMapped(
      RegExp(
        r'(^|\s)(اسبراي|اسبرى|اسبري|اسبراى|سبراي|سبراى|رول|بخاخ)\s+كس($|\s)',
      ),
      (m) => '${m.group(1)}${m.group(2)} اكس${m.group(3)}',
    );
    str = str.replaceAllMapped(
      RegExp(
        r'(^|\s)(ايس\s*شيل|ايس\s*تشيل|ice\s*chill|بلاك\s*تيمبتيشن|black\s*temptation|دارك\s*تيمبتيشن|dark\s*temptation|افريكان\s*كول)',
      ),
      (m) => '${m.group(1)}اكس ${m.group(2)}',
    );

    // Rice Synonym & POS Edge-Truncation Normalization (e.g. "ز مصرى", "ز بسمتي" -> "رز مصري", "ارز" -> "رز")
    // When printed near paper margins in thermal POS printers (e.g. Hyper One), "رز" is frequently clipped to "ز"
    str = str.replaceAllMapped(
      RegExp(r'(^|\s)ز\s+(مصري|مصرى|بسمتي|بسمتى|ابيض|أبيض|حبة|حبه|فاخر|اصفر|أصفر|طبيعي|طبيعى|الضحى|الضحي|1|2|5)'),
      (m) => '${m.group(1)}رز ${m.group(2)}',
    );
    // Unify "ارز" -> "رز"
    str = str.replaceAllMapped(
      RegExp(r'\bارز\b'),
      (_) => 'رز',
    );

    // Speed (سبيد) cleaner / detergent alias when POS printer drops 'ب' (e.g. "سيد منظف", "سيد باودر", "سيد ارضيات" -> "سبيد منظف", "سبيد باودر")
    str = str.replaceAllMapped(
      RegExp(r'(^|\s)سيد\s+(منظف|باودر|بودر|ارضيات|حمام|سائل|تواليت)'),
      (m) => '${m.group(1)}سبيد ${m.group(2)}',
    );

    // POS & transliteration dictionary normalization
    str = str.replaceAll('شامبوزيت', 'شامبو زيت');
    str = str.replaceAll('بلسمزيت', 'بلسم زيت');
    str = str.replaceAll(RegExp(r'\bحر\b'), 'حريمي');
    str = str.replaceAll(RegExp(r'\bرج\b'), 'رجالي');
    str = str.replaceAll(
      RegExp(r'رول\s*اون|روول\s*اون|رول\s*أون|روول\s*أون|roll\s*on|roll-on|rollon|روول|رووول'),
      'رول',
    );
    str = str.replaceAll(
      RegExp(r'اسبرى|اسبري|اسبراى|سبراي|سبراى|بخاخ|body\s*spray'),
      'اسبراي',
    );
    str = str.replaceAll(RegExp(r'شا\s*مبو|شا\s*مبوا|شمبو|شامبوا|shampoo'), 'شامبو');
    str = str.replaceAll(RegExp(r'صا\s*نسيلك|صا\s*نسلك|صن\s*سيلك|صن\s*سلك|صنسلك|صانسيلك|صانسلك|sunsilk'), 'صنسيلك');
    str = str.replaceAll(
      RegExp(r'تري\s*زيم[يهى]|تري\s*سم[يهى]|ترزيم[يهى]|tresemme|treseme'),
      'تريزيمي',
    );
    str = str.replaceAll(RegExp(r'ري\s*كسونا|رك\s*سونا|rexona'), 'ريكسونا');
    str = str.replaceAll(RegExp(r'\baxe\b'), 'اكس');
    str = str.replaceAll(RegExp(r'\bclear\b'), 'كلير');
    str = str.replaceAll(RegExp(r'\bdove\b'), 'دوف');
    str = str.replaceAll(RegExp(r'سي\s*جنال|سج\s*نال|\bsignal\b'), 'سيجنال');
    str = str.replaceAll(
      RegExp(r'كلوس\s*اب|كلوساب|close\s*up|closeup|close-up'),
      'كلوس اب',
    );
    str = str.replaceAll('فيشار', 'فشار');
    str = str.replaceAll(
      RegExp(r'ايزى\s*باستا|ايزي\s*باستا|easy\s*pasta'),
      'ايزي باستا',
    );
    str = str.replaceAll(
      RegExp(r'مينى\s*شيف|ميني\s*شيف|mini\s*chef'),
      'ميني شيف',
    );

    // FMCG Unit Normalization across retail POS:
    // Unify kilogram units: 1ك, 1 ك, 1كيلو, 1 كيلو, 1كجم, 1 كجم, 1kg -> 1 كجم
    str = str.replaceAllMapped(
      RegExp(r'(\d+)\s*(?:كجم|كيلو|كيلوجرام|ك|kg)(?!\S)', caseSensitive: false),
      (m) => '${m.group(1)} كجم',
    );
    // Unify gram units: 400جم, 400 جرام, 400g -> 400 جم
    str = str.replaceAllMapped(
      RegExp(r'(\d+)\s*(?:جرام|جم|g)(?!\S)', caseSensitive: false),
      (m) => '${m.group(1)} جم',
    );
    // Unify ml units: 400مل, 400 ملى, 400ml -> 400 مل
    str = str.replaceAllMapped(
      RegExp(r'(\d+)\s*(?:ملى|مل|ml)(?!\S)', caseSensitive: false),
      (m) => '${m.group(1)} مل',
    );
    // Unify liter units: 1لتر, 1 لتر, 1liter, 1l -> 1 لتر
    str = str.replaceAllMapped(
      RegExp(r'(\d+)\s*(?:لتر|liter|l)(?!\S)', caseSensitive: false),
      (m) => '${m.group(1)} لتر',
    );

    // Zahran Market & retail POS keyboard typo for El-Doha brand:
    // Cashiers frequently type 'ص' instead of 'ض' ('الصحي' / 'الصحى' -> 'الضحي')
    str = str.replaceAll('الصحي', 'الضحي');
    str = str.replaceAll('الصحى', 'الضحي');

    // 150ml Aerosol Bodyspray Resolution: In retail FMCG, 150ml for Rexona/Axe is ALWAYS an aerosol spray
    // E.g. "ريكسونا 150 مل حريمي" -> "ريكسونا اسبراي 150 مل حريمي", "اكس 150 مل" -> "اكس اسبراي 150 مل"
    if ((str.contains('ريكسونا') || str.contains('اكس')) &&
        (str.contains('150 مل') ||
            str.contains('150ml') ||
            str.contains('150')) &&
        !str.contains('اسبراي') &&
        !str.contains('رول') &&
        !str.contains('ستيك')) {
      str = str.replaceAllMapped(
        RegExp(r'(ريكسونا|اكس)'),
        (m) => '${m.group(1)} اسبراي',
      );
    }

    // Compress repeated Arabic long vowels (e.g. روول -> رول, شوكلييت -> شوكليت)
    str = str.replaceAll(RegExp(r'([و])\1+'), 'و');
    str = str.replaceAll(RegExp(r'([ي])\1+'), 'ي');
    str = str.replaceAll(RegExp(r'([ا])\1+'), 'ا');

    str = str.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ');
    return str.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @visibleForTesting
  static String normalize(String s) => _normalize(s);

  @visibleForTesting
  static bool matchesProduct(
    ExtractedProductItem p,
    String trigger, [
    PromotionalRuleItem? rule,
    Iterable<String>? dynamicBrands,
  ]) => _matchesProduct(p, trigger, rule, dynamicBrands);

  static List<String> _extractTokens(String trigger) {
    final parts = trigger.split(
      RegExp(r'[,،/\+\n]|(\s+أو\s+)|(\s+or\s+)', caseSensitive: false),
    );
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

  /// Gift value used to rank rules on the same products: voucher value, else
  /// catalog unitValue x quantity of linked gifts. 0 means unknown.
  static double ruleGiftValue(PromotionalRuleItem rule) {
    if (rule.totalVoucherValue > 0) return rule.totalVoucherValue;
    if (rule.rewardAmount > 0) return rule.rewardAmount;
    return rule.linkedGifts.fold<double>(0.0, (acc, g) => acc + g.unitValue * g.quantity);
  }

  /// Known gift value first (high to low); gifts without a value come after,
  /// ranked by spend tier (high to low).
  static int compareRulesByGiftValue(PromotionalRuleItem a, PromotionalRuleItem b) {
    final va = ruleGiftValue(a);
    final vb = ruleGiftValue(b);
    if ((va > 0) != (vb > 0)) return va > 0 ? -1 : 1;
    if (va != vb) return vb.compareTo(va);
    return b.effectiveMinSpend.compareTo(a.effectiveMinSpend);
  }

  /// Spend rules on the same product set share one pool, whatever their wording.
  static String? _spendPoolKey(PromotionalRuleItem rule) {
    if (!rule.isSpendBased || rule.isCombo || rule.selectedBarcodes.isEmpty) return null;
    final codes = rule.selectedBarcodes.map((b) => b.trim()).where((b) => b.isNotEmpty).toSet().toList()..sort();
    if (codes.isEmpty) return null;
    return 'spend_pool_${codes.join(',')}';
  }

  static String _getProductGroupKey(PromotionalRuleItem rule) {
    final titleNorm = _normalize(rule.ruleTitle);
    final triggerNorm = _normalize(rule.triggerProduct);
    final combined = '$titleNorm $triggerNorm';

    // Canonical FMCG product family grouping:
    if (rule.isCombo ||
        (rule.requiredBrands.contains('سيجنال') &&
            rule.requiredBrands.contains('كلوس اب')) ||
        (combined.contains('سيجنال') && combined.contains('كلوس'))) {
      return 'oral_care_bundle_family';
    }
    if (combined.contains('كلوس اب') || combined.contains('closeup')) {
      return 'closeup_family';
    }
    // Check Roll-on first if explicitly mentioned in title or trigger
    if (titleNorm.contains('رول') ||
        titleNorm.contains('roll') ||
        titleNorm.contains('ستيك') ||
        (triggerNorm.contains('رول') && !triggerNorm.contains('اسبراي'))) {
      return 'rollon_family';
    }
    // Check Spray if explicitly mentioned in title or trigger
    if (titleNorm.contains('اسبراي') ||
        titleNorm.contains('spray') ||
        titleNorm.contains('بخاخ') ||
        titleNorm.contains('شرنك') ||
        (triggerNorm.contains('اسبراي') && !triggerNorm.contains('رول'))) {
      return 'spray_family';
    }
    String? baseFamily;
    if (combined.contains('كلير') || combined.contains('clear')) {
      baseFamily = 'clear_family';
    } else if (combined.contains('تريزيمي') || combined.contains('tresemme')) {
      baseFamily = 'tresemme_family';
    } else if (combined.contains('صنسيلك') || combined.contains('sunsilk')) {
      baseFamily = 'sunsilk_family';
    } else if (combined.contains('دوف') || combined.contains('dove')) {
      baseFamily = 'dove_family';
    } else if (combined.contains('سيجنال') || combined.contains('signal')) {
      baseFamily = 'signal_family';
    } else if (combined.contains('ريكسونا') || combined.contains('اكس')) {
      baseFamily = 'deodorant_general_family';
    } else if (combined.contains('كيت') || combined.contains('kitkat')) {
      baseFamily = 'kitkat_family';
    } else if (combined.contains('نسكافيه جولد') ||
        combined.contains('nescafe gold') ||
        (combined.contains('جولد') &&
            !combined.contains('سيريلاك') &&
            !combined.contains('اس26') &&
            !combined.contains('اس-26'))) {
      baseFamily = 'nescafe_gold_family';
    } else if (combined.contains('نسكافيه') || combined.contains('nescafe')) {
      baseFamily = 'nescafe_regular_family';
    } else if (combined.contains('اس26') ||
        combined.contains('اس-26') ||
        combined.contains('s26') ||
        combined.contains('s-26') ||
        combined.contains('بروجرس') ||
        combined.contains('بروميل')) {
      baseFamily = 's26_family';
    } else if (combined.contains('سيريلاك') || combined.contains('cerelac')) {
      baseFamily = 'cerelac_family';
    } else if (combined.contains('نسكويك') || combined.contains('nesquik')) {
      baseFamily = 'nesquik_family';
    }

    if (baseFamily != null) {
      final int? reqSize = _extractRuleRequiredSize(rule, rule.triggerProduct);
      if (reqSize != null) {
        return '${baseFamily}_size_$reqSize';
      }
      return baseFamily;
    }

    final tokens = _extractTokens(
      triggerNorm.isNotEmpty ? triggerNorm : titleNorm,
    )..sort();
    if (tokens.isNotEmpty) {
      return tokens.join('_');
    }
    return triggerNorm.isNotEmpty ? triggerNorm : titleNorm;
  }
}

/// Represents the resolved promotional rule result with multiplied rewards and chances
class MatchedPromotionalRuleResult {
  final PromotionalRuleItem rule;
  final int multiplier; // e.g. 2
  final int totalTriggerQuantity; // e.g. 4
  final double totalRewardAmount; // e.g. 250.0
  final String
  formattedPrizeSummary; // e.g. "2 × فواتشر بقيمة 125 جنيه (إجمالي 250 جنيه)"
  final List<LinkedGiftAllocation> multipliedLinkedGifts;
  final List<String> qualifyingProductNames;
  final double qualifyingSpend;

  MatchedPromotionalRuleResult({
    required this.rule,
    this.multiplier = 1,
    this.totalTriggerQuantity = 1,
    this.totalRewardAmount = 0.0,
    required this.formattedPrizeSummary,
    this.multipliedLinkedGifts = const [],
    this.qualifyingProductNames = const [],
    this.qualifyingSpend = 0.0,
  });

  /// Human-readable qualification reason in Arabic (e.g. "استحقاق لشراء (1) قطعة من (اكس اسبراى 150 مل)")
  String get qualifyingReasonText {
    if (qualifyingProductNames.isNotEmpty) {
      final joinedNames = qualifyingProductNames.toSet().join(' + ');
      if (rule.isSpendBased) {
        final spend = qualifyingSpend > 0 ? qualifyingSpend.toInt() : totalTriggerQuantity;
        return 'استحقاق لمشتريات بقيمة $spend ج.م من ($joinedNames)';
      } else {
        final qty = totalTriggerQuantity > 0 ? totalTriggerQuantity : multiplier;
        return 'استحقاق لشراء ($qty) قطعة من ($joinedNames)';
      }
    }
    if (rule.isSpendBased && rule.minSpend > 0) {
      return 'استحقاق لتجاوز مشتريات ${rule.minSpend.toInt()} ج.م من منتجات العرض';
    }
    if (rule.minQuantity > 0) {
      return 'استحقاق لشراء ${rule.minQuantity * multiplier} قطعة من منتجات العرض';
    }
    return 'استحقاق استيفاء شروط العرض الترويجي';
  }

  /// Human-readable qualification reason in English
  String get qualifyingReasonTextEn {
    if (qualifyingProductNames.isNotEmpty) {
      final joinedNames = qualifyingProductNames.toSet().join(' + ');
      if (rule.isSpendBased) {
        final spend = qualifyingSpend > 0 ? qualifyingSpend.toInt() : totalTriggerQuantity;
        return 'Qualified for purchases of $spend EGP of ($joinedNames)';
      } else {
        final qty = totalTriggerQuantity > 0 ? totalTriggerQuantity : multiplier;
        return 'Qualified for purchase of ($qty) pcs of ($joinedNames)';
      }
    }
    if (rule.isSpendBased && rule.minSpend > 0) {
      return 'Qualified for spending ${rule.minSpend.toInt()} EGP on promo items';
    }
    if (rule.minQuantity > 0) {
      return 'Qualified for purchasing ${rule.minQuantity * multiplier} pcs of promo items';
    }
    return 'Qualified for fulfilling promo conditions';
  }
}

/// A matched rule whose reward the customer must pick from several options.
class RewardChoiceGroup {
  final String ruleId;
  final String ruleTitle;
  final int multiplier;
  final List<RewardOption> options;

  const RewardChoiceGroup({
    required this.ruleId,
    required this.ruleTitle,
    this.multiplier = 1,
    required this.options,
  });

  static RewardChoiceGroup? fromRule(PromotionalRuleItem rule, {int multiplier = 1}) {
    if (!rule.hasRewardChoice) return null;
    return RewardChoiceGroup(
      ruleId: rule.id,
      ruleTitle: rule.ruleTitle,
      multiplier: multiplier < 1 ? 1 : multiplier,
      options: rule.rewardOptions,
    );
  }
}

/// Merges allocations that refer to the same gift (by id, or by name when no id).
List<LinkedGiftAllocation> consolidateLinkedGifts(Iterable<LinkedGiftAllocation> gifts) {
  final Map<String, LinkedGiftAllocation> out = {};
  for (final g in gifts) {
    final key = g.giftId.isNotEmpty ? g.giftId : 'name:${g.giftName}';
    final existing = out[key];
    out[key] = existing == null ? g : existing.copyWith(quantity: existing.quantity + g.quantity);
  }
  return out.values.toList();
}

/// Represents a composite multi-offer prize bundle synthesized from all matched rules in a single receipt
class CompositePromotionalBundle {
  final List<MatchedPromotionalRuleResult> matchedRules;
  final List<LinkedGiftAllocation> combinedLinkedGifts;
  /// Gifts from rules WITHOUT a reward choice (always handed over).
  final List<LinkedGiftAllocation> baseLinkedGifts;
  /// Rules where the customer must choose one reward option.
  final List<RewardChoiceGroup> rewardChoiceGroups;
  final String compositePrizeTitle;
  final double totalVoucherValue;
  final int totalChances;
  final String? resolvedGameType;

  CompositePromotionalBundle({
    required this.matchedRules,
    required this.combinedLinkedGifts,
    required this.compositePrizeTitle,
    this.totalVoucherValue = 0.0,
    this.totalChances = 1,
    this.resolvedGameType,
    this.baseLinkedGifts = const [],
    this.rewardChoiceGroups = const [],
  });

  bool get requiresRewardChoice => rewardChoiceGroups.isNotEmpty;

  /// Gift names for "choose your gift" games: base gifts plus every reward option.
  List<String> get candidateGiftNames {
    if (!requiresRewardChoice) {
      return combinedLinkedGifts.map((g) => g.giftName.trim()).where((n) => n.isNotEmpty).toSet().toList();
    }
    return <String>{
      ...baseLinkedGifts.map((g) => g.giftName.trim()),
      for (final grp in rewardChoiceGroups)
        for (final o in grp.options) o.toAllocation().giftName.trim(),
    }.where((n) => n.isNotEmpty).toList();
  }

  static CompositePromotionalBundle fromMatchedRules(
    List<MatchedPromotionalRuleResult> rules, {
    String fallbackTitle = 'هدية ترويجية مميزة',
  }) {
    if (rules.isEmpty) {
      return CompositePromotionalBundle(
        matchedRules: [],
        combinedLinkedGifts: [],
        compositePrizeTitle: fallbackTitle,
        totalVoucherValue: 0.0,
        totalChances: 1,
        resolvedGameType: null,
      );
    }

    final Map<String, LinkedGiftAllocation> consolidatedGifts = {};
    final List<RewardChoiceGroup> choiceGroups = [];
    final List<LinkedGiftAllocation> defaultChoiceGifts = [];
    final List<LinkedGiftAllocation> baseGifts = [];
    double totalVoucher = 0.0;
    int chances = 0;
    String? ruleLevelGameType;

    for (final r in rules) {
      totalVoucher += r.totalRewardAmount;
      chances += r.multiplier;
      if (r.rule.gameType != null && r.rule.gameType!.trim().isNotEmpty) {
        ruleLevelGameType = r.rule.gameType!.trim();
      }
      final choice = RewardChoiceGroup.fromRule(r.rule, multiplier: r.multiplier);
      if (choice != null) {
        choiceGroups.add(choice);
        // Default (first) option keeps legacy consumers working until the customer picks.
        final def = choice.options.first.toAllocation(multiplier: choice.multiplier);
        final key = def.giftId.isNotEmpty ? def.giftId : 'name:${def.giftName}';
        defaultChoiceGifts.add(def);
        final existing = consolidatedGifts[key];
        consolidatedGifts[key] = existing == null ? def : existing.copyWith(quantity: existing.quantity + def.quantity);
        continue;
      }
      final ruleGifts = r.multipliedLinkedGifts.isNotEmpty
          ? r.multipliedLinkedGifts
          : [
              LinkedGiftAllocation(
                giftId: r.rule.id,
                giftName: r.rule.rewardValue,
                quantity: r.multiplier,
                unitValue: r.rule.rewardAmount > 0
                    ? r.rule.rewardAmount
                    : (r.rule.totalVoucherValue > 0
                          ? r.rule.totalVoucherValue
                          : 0.0),
                giftType:
                    (r.rule.rewardType == 'voucher' || r.totalRewardAmount > 0)
                    ? 'voucher'
                    : 'product',
              ),
            ];

      baseGifts.addAll(ruleGifts);
      for (final g in ruleGifts) {
        if (consolidatedGifts.containsKey(g.giftId)) {
          final existing = consolidatedGifts[g.giftId]!;
          consolidatedGifts[g.giftId] = existing.copyWith(
            quantity: existing.quantity + g.quantity,
          );
        } else {
          consolidatedGifts[g.giftId] = g;
        }
      }
    }

    final title = rules.map((r) => r.formattedPrizeSummary).join(' + ');

    return CompositePromotionalBundle(
      matchedRules: rules,
      combinedLinkedGifts: consolidatedGifts.values.toList(),
      compositePrizeTitle: title,
      totalVoucherValue: totalVoucher,
      totalChances: chances > 0 ? chances : 1,
      resolvedGameType: ruleLevelGameType,
      baseLinkedGifts: consolidateLinkedGifts(baseGifts),
      rewardChoiceGroups: choiceGroups,
    );
  }
}
