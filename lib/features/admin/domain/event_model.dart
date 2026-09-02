import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a specific quantity of an inventory gift allocated to a promotional rule
class LinkedGiftAllocation {
  final String giftId;
  final String giftName;
  final int quantity; // e.g. 2 of 50 EGP card, 1 of 25 EGP card
  final double unitValue; // 50.0
  final String giftType; // 'voucher' | 'product'

  LinkedGiftAllocation({
    required this.giftId,
    required this.giftName,
    this.quantity = 1,
    this.unitValue = 0.0,
    this.giftType = 'product',
  });

  bool get isVoucher {
    if (giftType == 'voucher') return true;
    if (giftType == 'product') return false;
    final clean = giftName.toLowerCase();
    return unitValue > 0 &&
        (clean.contains('فواتشر') ||
            clean.contains('فوتشر') ||
            clean.contains('قسيمة') ||
            clean.contains('قسائم') ||
            clean.contains('كارت مشتريات') ||
            clean.contains('كوبون') ||
            clean.contains('voucher') ||
            clean.contains('coupon'));
  }
  double get totalMonetaryValue => isVoucher ? (unitValue * quantity) : 0.0;

  LinkedGiftAllocation copyWith({
    String? giftId,
    String? giftName,
    int? quantity,
    double? unitValue,
    String? giftType,
  }) {
    return LinkedGiftAllocation(
      giftId: giftId ?? this.giftId,
      giftName: giftName ?? this.giftName,
      quantity: quantity ?? this.quantity,
      unitValue: unitValue ?? this.unitValue,
      giftType: giftType ?? this.giftType,
    );
  }

  factory LinkedGiftAllocation.fromMap(Map<String, dynamic> data) {
    return LinkedGiftAllocation(
      giftId: data['giftId']?.toString() ?? '',
      giftName: data['giftName']?.toString() ?? '',
      quantity: (data['quantity'] as num?)?.toInt() ?? 1,
      unitValue: (data['unitValue'] as num?)?.toDouble() ?? 0.0,
      giftType: data['giftType']?.toString() ?? 'product',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'giftId': giftId,
      'giftName': giftName,
      'quantity': quantity,
      'unitValue': unitValue,
      'giftType': giftType,
    };
  }
}

/// Represents a structured promotional rule/offer condition (e.g. "Buy 1 Axe/Rexona spray -> Get 50 EGP voucher" or "Buy >= 100 EGP of Signal + Closeup -> Get 25 EGP voucher")
class PromotionalRuleItem {
  final String id;
  final String ruleTitle;
  final String triggerProduct;
  final int minQuantity;
  final String conditionType; // 'by_quantity' | 'by_spend' | 'combo_spend'
  final double minSpend; // e.g. 100.0, 150.0, 200.0 if conditionType is by_spend or combo_spend
  final String matchMode; // 'OR' | 'AND' (for combo bundles, 'AND' requires presence of all required brands/items)
  final List<String> requiredBrands; // e.g. ['سيجنال', 'كلوس اب'] or ['Signal', 'Closeup']
  final List<String> selectedProductIds; // Specific company_products IDs selected from catalog
  final List<String> selectedBarcodes; // Specific company_products barcodes selected from catalog
  final List<String> selectedProductNames; // Specific company_products names selected from catalog
  final String rewardType; // 'voucher' | 'free_product' | 'game_spin'
  final String rewardValue; // e.g. 'قسيمة مشتريات 50 ج.م' or 'كلير 90 مل هدية'
  final double rewardAmount; // 50.0 if voucher
  final bool allowMultipliers; // true if buying multiples gives multiple rewards
  final String? linkedGiftId; // ID of the linked CompanyGiftModel from inventory (legacy/fallback)
  final String? linkedGiftName; // Friendly display name of the linked gift (legacy/fallback)
  final List<LinkedGiftAllocation> linkedGifts; // Multiple allocated gifts/vouchers for this rule

  PromotionalRuleItem({
    required this.id,
    required this.ruleTitle,
    required this.triggerProduct,
    this.minQuantity = 1,
    this.conditionType = 'by_quantity',
    this.minSpend = 0.0,
    this.matchMode = 'OR',
    this.requiredBrands = const [],
    this.selectedProductIds = const [],
    this.selectedBarcodes = const [],
    this.selectedProductNames = const [],
    this.rewardType = 'free_product',
    required this.rewardValue,
    this.rewardAmount = 0.0,
    this.allowMultipliers = true,
    this.linkedGiftId,
    this.linkedGiftName,
    this.linkedGifts = const [],
  });

  bool get hasLinkedGifts => linkedGifts.isNotEmpty || (linkedGiftId != null && linkedGiftId!.isNotEmpty);

  /// Whether this rule is evaluated based on total monetary spend (e.g. >= 100 EGP) rather than piece count
  bool get isSpendBased => conditionType == 'by_spend' || conditionType == 'combo_spend' || minSpend > 0;

  /// Whether this rule requires multiple brands or products together (e.g. Signal + Closeup combo)
  bool get isCombo => conditionType == 'combo_spend' || (matchMode == 'AND' && requiredBrands.length > 1);

  /// Returns total monetary value of linked vouchers
  double get totalVoucherValue {
    if (linkedGifts.isNotEmpty) {
      return linkedGifts.where((g) => g.isVoucher).fold(0.0, (total, g) => total + g.totalMonetaryValue);
    }
    return rewardAmount;
  }

  /// Formatted summary of linked gifts (e.g. "2 × فواتشر 50 جنيه + 1 × فواتشر 25 جنيه")
  String get linkedGiftsSummary {
    if (linkedGifts.isEmpty) {
      return linkedGiftName ?? '';
    }
    return linkedGifts.map((g) => g.quantity > 1 ? '${g.quantity} × ${g.giftName}' : g.giftName).join(' + ');
  }

  /// Human-readable summary of the condition
  String get conditionSummaryText {
    final spendInt = minSpend == minSpend.roundToDouble() ? minSpend.toInt() : minSpend;
    if (isCombo) {
      final brandsList = requiredBrands.isNotEmpty ? requiredBrands.join(' و ') : triggerProduct;
      return 'شراء بقيمة $spendInt ج.م أو أكثر من ($brandsList معاً)';
    } else if (isSpendBased) {
      return 'شراء بقيمة $spendInt ج.م أو أكثر من [$triggerProduct]';
    } else {
      return 'شراء كمية ($minQuantity) أو أكثر من [$triggerProduct]';
    }
  }

  factory PromotionalRuleItem.fromMap(Map<String, dynamic> data) {
    List<LinkedGiftAllocation> parsedLinkedGifts = [];
    if (data['linkedGifts'] is List) {
      parsedLinkedGifts = (data['linkedGifts'] as List)
          .map((e) => LinkedGiftAllocation.fromMap(Map<String, dynamic>.from(e as Map)))
          .where((g) => g.giftId.isNotEmpty)
          .toList();
    }

    final rawGiftId = data['linkedGiftId']?.toString();
    final rawGiftName = data['linkedGiftName']?.toString();

    // Backward compatibility: if linkedGifts is empty but linkedGiftId is present
    if (parsedLinkedGifts.isEmpty && rawGiftId != null && rawGiftId.isNotEmpty) {
      parsedLinkedGifts.add(LinkedGiftAllocation(
        giftId: rawGiftId,
        giftName: rawGiftName ?? '',
        quantity: 1,
        unitValue: (data['rewardAmount'] as num?)?.toDouble() ?? 0.0,
        giftType: data['rewardType']?.toString() ?? 'product',
      ));
    }

    final parsedRequiredBrands = (data['requiredBrands'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];

    final parsedSelectedProductIds = (data['selectedProductIds'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];

    final parsedSelectedBarcodes = (data['selectedBarcodes'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];

    final parsedSelectedProductNames = (data['selectedProductNames'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];

    return PromotionalRuleItem(
      id: data['id']?.toString() ?? '',
      ruleTitle: data['ruleTitle']?.toString() ?? '',
      triggerProduct: data['triggerProduct']?.toString() ?? '',
      minQuantity: (data['minQuantity'] as num?)?.toInt() ?? 1,
      conditionType: data['conditionType']?.toString() ?? 'by_quantity',
      minSpend: (data['minSpend'] as num?)?.toDouble() ?? 0.0,
      matchMode: data['matchMode']?.toString() ?? 'OR',
      requiredBrands: parsedRequiredBrands,
      selectedProductIds: parsedSelectedProductIds,
      selectedBarcodes: parsedSelectedBarcodes,
      selectedProductNames: parsedSelectedProductNames,
      rewardType: data['rewardType']?.toString() ?? 'free_product',
      rewardValue: data['rewardValue']?.toString() ?? '',
      rewardAmount: (data['rewardAmount'] as num?)?.toDouble() ?? 0.0,
      allowMultipliers: data['allowMultipliers'] != false,
      linkedGiftId: rawGiftId,
      linkedGiftName: rawGiftName,
      linkedGifts: parsedLinkedGifts,
    );
  }

  Map<String, dynamic> toMap() {
    final effectiveGiftId = linkedGifts.isNotEmpty ? linkedGifts.first.giftId : (linkedGiftId ?? '');
    final effectiveGiftName = linkedGifts.isNotEmpty ? linkedGiftsSummary : (linkedGiftName ?? '');

    return {
      'id': id,
      'ruleTitle': ruleTitle,
      'triggerProduct': triggerProduct,
      'minQuantity': minQuantity,
      'conditionType': conditionType,
      'minSpend': minSpend,
      'matchMode': matchMode,
      if (requiredBrands.isNotEmpty) 'requiredBrands': requiredBrands,
      if (selectedProductIds.isNotEmpty) 'selectedProductIds': selectedProductIds,
      if (selectedBarcodes.isNotEmpty) 'selectedBarcodes': selectedBarcodes,
      if (selectedProductNames.isNotEmpty) 'selectedProductNames': selectedProductNames,
      'rewardType': rewardType,
      'rewardValue': rewardValue,
      'rewardAmount': rewardAmount,
      'allowMultipliers': allowMultipliers,
      if (effectiveGiftId.isNotEmpty) 'linkedGiftId': effectiveGiftId,
      if (effectiveGiftName.isNotEmpty) 'linkedGiftName': effectiveGiftName,
      if (linkedGifts.isNotEmpty) 'linkedGifts': linkedGifts.map((g) => g.toMap()).toList(),
    };
  }

  PromotionalRuleItem copyWith({
    String? id,
    String? ruleTitle,
    String? triggerProduct,
    int? minQuantity,
    String? conditionType,
    double? minSpend,
    String? matchMode,
    List<String>? requiredBrands,
    List<String>? selectedProductIds,
    List<String>? selectedBarcodes,
    List<String>? selectedProductNames,
    String? rewardType,
    String? rewardValue,
    double? rewardAmount,
    bool? allowMultipliers,
    String? linkedGiftId,
    String? linkedGiftName,
    List<LinkedGiftAllocation>? linkedGifts,
  }) {
    return PromotionalRuleItem(
      id: id ?? this.id,
      ruleTitle: ruleTitle ?? this.ruleTitle,
      triggerProduct: triggerProduct ?? this.triggerProduct,
      minQuantity: minQuantity ?? this.minQuantity,
      conditionType: conditionType ?? this.conditionType,
      minSpend: minSpend ?? this.minSpend,
      matchMode: matchMode ?? this.matchMode,
      requiredBrands: requiredBrands ?? this.requiredBrands,
      selectedProductIds: selectedProductIds ?? this.selectedProductIds,
      selectedBarcodes: selectedBarcodes ?? this.selectedBarcodes,
      selectedProductNames: selectedProductNames ?? this.selectedProductNames,
      rewardType: rewardType ?? this.rewardType,
      rewardValue: rewardValue ?? this.rewardValue,
      rewardAmount: rewardAmount ?? this.rewardAmount,
      allowMultipliers: allowMultipliers ?? this.allowMultipliers,
      linkedGiftId: linkedGiftId ?? this.linkedGiftId,
      linkedGiftName: linkedGiftName ?? this.linkedGiftName,
      linkedGifts: linkedGifts ?? this.linkedGifts,
    );
  }
}

/// Represents a single prize allocated to a campaign or specific branch from the company's master inventory.
class AllocatedPrize {
  final String giftId;
  final String name;
  final int allocatedQuantity;
  final int remainingQuantity;
  final String branchId;
  final String branchName;
  final String giftType; // 'product' | 'voucher'
  final double unitValue; // Denomination per card for vouchers (e.g. 25.0, 50.0, 100.0)

  AllocatedPrize({
    required this.giftId,
    required this.name,
    required this.allocatedQuantity,
    required this.remainingQuantity,
    this.branchId = '',
    this.branchName = '',
    this.giftType = 'product',
    this.unitValue = 0.0,
  });

  bool get isVoucher {
    if (giftType == 'voucher') return true;
    if (giftType == 'product') return false;
    final clean = name.toLowerCase();
    return unitValue > 0 &&
        (clean.contains('فواتشر') ||
            clean.contains('فوتشر') ||
            clean.contains('قسيمة') ||
            clean.contains('قسائم') ||
            clean.contains('كارت مشتريات') ||
            clean.contains('كوبون') ||
            clean.contains('voucher') ||
            clean.contains('coupon'));
  }

  /// Calculates how many physical voucher cards should be deducted/handed over for a given winning cash amount.
  /// Example: Winning 100 EGP with 50 EGP vouchers -> 2 cards.
  /// Example: Winning 100 EGP with 25 EGP vouchers -> 4 cards.
  int calculateVoucherUnitsForAmount(double targetAmount) {
    if (!isVoucher || unitValue <= 0) return 1;
    if (targetAmount <= 0) return 1;
    final units = (targetAmount / unitValue).ceil();
    return units > 0 ? units : 1;
  }

  AllocatedPrize copyWith({
    String? giftId,
    String? name,
    int? allocatedQuantity,
    int? remainingQuantity,
    String? branchId,
    String? branchName,
    String? giftType,
    double? unitValue,
  }) {
    return AllocatedPrize(
      giftId: giftId ?? this.giftId,
      name: name ?? this.name,
      allocatedQuantity: allocatedQuantity ?? this.allocatedQuantity,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      giftType: giftType ?? this.giftType,
      unitValue: unitValue ?? this.unitValue,
    );
  }

  factory AllocatedPrize.fromMap(Map<String, dynamic> data) {
    String rawName = (data['name'] as String? ?? '').trim();
    final cleanName = rawName.toLowerCase();
    final isExplicitVoucherName = cleanName.contains('فواتشر') ||
        cleanName.contains('فوتشر') ||
        cleanName.contains('قسيمة') ||
        cleanName.contains('قسائم') ||
        cleanName.contains('كارت مشتريات') ||
        cleanName.contains('كوبون') ||
        cleanName.contains('voucher') ||
        cleanName.contains('coupon');

    final declaredType = data['giftType'] as String?;
    final rawType = declaredType != null && declaredType.isNotEmpty
        ? declaredType
        : (isExplicitVoucherName ? 'voucher' : 'product');

    final rawUnitVal = (rawType == 'voucher' || isExplicitVoucherName)
        ? ((data['unitValue'] as num?)?.toDouble() ?? 0.0)
        : 0.0;
    final giftId = (data['giftId'] as String? ?? '').trim();

    // Self-healing: if name is empty, or is a raw Firestore ID (e.g. 20-character alphanumeric ID)
    final isRawId = rawName.isEmpty ||
        (rawName == giftId && RegExp(r'^[a-zA-Z0-9_-]{15,35}$').hasMatch(rawName)) ||
        RegExp(r'^[a-zA-Z0-9]{18,30}$').hasMatch(rawName);

    if (isRawId) {
      if (rawType == 'voucher' || rawUnitVal > 0) {
        final formattedVal = rawUnitVal == rawUnitVal.roundToDouble() ? rawUnitVal.toInt() : rawUnitVal;
        rawName = rawUnitVal > 0 ? 'فواتشر $formattedVal جنيه' : 'كارت فواتشر مشتريات';
      } else {
        rawName = 'هدية ترويجية مميزة';
      }
    }

    return AllocatedPrize(
      giftId: giftId,
      name: rawName,
      allocatedQuantity: (data['allocatedQuantity'] as num?)?.toInt() ?? 0,
      remainingQuantity: (data['remainingQuantity'] as num?)?.toInt() ?? 0,
      branchId: data['branchId'] ?? '',
      branchName: data['branchName'] ?? '',
      giftType: rawType,
      unitValue: rawUnitVal,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'giftId': giftId,
      'name': name,
      'allocatedQuantity': allocatedQuantity,
      'remainingQuantity': remainingQuantity,
      'giftType': giftType,
      'unitValue': unitValue,
      if (branchId.isNotEmpty) 'branchId': branchId,
      if (branchName.isNotEmpty) 'branchName': branchName,
    };
  }
}

class EventModel {
  final String id;
  final String eventName;
  final String targetCompany;
  final String companySlug;
  final String companyLogoUrl;
  final double minimumSpend;
  final List<String> requiredProducts;
  final String customPrompt;
  final String welcomeTitle;
  final String welcomeMessage;
  final String termsAndConditions;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;
  final DateTime? createdAt;

  /// Independent control toggles for Promoter and Company Manager Portals
  final bool isPromoterActive;
  final bool isManagerActive;

  /// The raw natural language promotional idea typed by admin
  final String promotionalIdea;

  /// Human-readable structured Arabic/English summary produced by AI assistant
  final String aiValidationSummary;

  /// List of structured promotional rules parsed by AI
  final List<PromotionalRuleItem> promotionalRules;

  /// The type of game to show after receipt validation.
  /// Values: 'wheel' (عجلة الحظ), 'scratch' (امسح واربح)
  final String gameType;

  /// Prizes allocated to this specific campaign/branch from the company's master inventory.
  final List<AllocatedPrize> allocatedPrizes;

  /// Target Retail Chain / Hypermarket Organization (e.g. أسواق فتح الله, كارفور, سبينس, سعودي)
  final String retailChainId;
  final String retailChainName;

  /// Target Branches under the Retail Chain (e.g. ['فرع سموحة', 'فرع الهانوفيل'])
  final List<String> branchIds;
  final List<String> branchNames;
  final bool isAllBranches;

  /// Whether to grant multiple draw/spin chances when the customer spends multiples of the minimum spend or buys multiples of products.
  final bool allowMultipleChances;

  /// Multiplier Basis: 'quantity' (بناءً على كمية المنتجات), 'spend' (بناءً على قيمة الشراء), or 'both' (كلاهما معاً).
  final String multiplierBasis;

  /// Maximum draw chances / gifts allowed per single receipt (0 = unlimited / no cap).
  final int maxChancesPerReceipt;

  /// Whether entering voucher card serial numbers is strictly mandatory for promoters upon gift claim (false = optional by default).
  final bool requireVoucherSerials;

  EventModel({
    required this.id,
    required this.eventName,
    required this.targetCompany,
    this.companySlug = '',
    this.companyLogoUrl = '',
    required this.minimumSpend,
    this.requiredProducts = const [],
    this.customPrompt = '',
    this.welcomeTitle = '',
    this.welcomeMessage = '',
    this.termsAndConditions = '',
    this.startDate,
    this.endDate,
    this.isActive = true,
    this.createdAt,
    this.isPromoterActive = true,
    this.isManagerActive = true,
    this.promotionalIdea = '',
    this.aiValidationSummary = '',
    this.promotionalRules = const [],
    this.gameType = 'wheel',
    this.allocatedPrizes = const [],
    this.retailChainId = '',
    this.retailChainName = '',
    this.branchIds = const [],
    this.branchNames = const [],
    this.isAllBranches = true,
    this.allowMultipleChances = false,
    this.multiplierBasis = 'both',
    this.maxChancesPerReceipt = 0,
    this.requireVoucherSerials = false,
  });

  bool get isExpired {
    if (endDate == null) return false;
    return DateTime.now().isAfter(endDate!);
  }

  bool get isNotStartedYet {
    if (startDate == null) return false;
    return DateTime.now().isBefore(startDate!);
  }

  bool get isWithinValidDates {
    if (!isActive) return false;
    if (isNotStartedYet) return false;
    if (isExpired) return false;
    return true;
  }

  bool get isQuantityMultiplier => multiplierBasis == 'quantity' || multiplierBasis == 'both';
  bool get isSpendMultiplier => multiplierBasis == 'spend' || multiplierBasis == 'both';

  /// Granular portal access status helpers
  bool get canPromoterAccess => isActive && isPromoterActive && !isExpired && !isNotStartedYet;
  bool get canManagerAccess => isActive && isManagerActive;

  /// Formatted branches display for UI chips & summaries
  String get branchesDisplaySummary {
    if (retailChainName.isEmpty) return 'غير محدد';
    if (isAllBranches || branchNames.isEmpty) return '$retailChainName (جميع الفروع)';
    if (branchNames.length == 1) return '$retailChainName - ${branchNames.first}';
    return '$retailChainName (${branchNames.length} فروع: ${branchNames.join('، ')})';
  }

  /// Returns only prizes that still have remaining stock.
  List<AllocatedPrize> get availablePrizes {
    return allocatedPrizes.where((p) => p.remainingQuantity > 0).toList();
  }

  /// Returns prize names for display in games (only available ones).
  List<String> get availablePrizeNames {
    if (availablePrizes.isNotEmpty) {
      return availablePrizes.map((p) {
        if (p.isVoucher && p.unitValue > 0) {
          final val = p.unitValue == p.unitValue.roundToDouble() ? p.unitValue.toInt() : p.unitValue;
          if (!p.name.contains('$val')) {
            return '${p.name} ($val ج.م)';
          }
        }
        return p.name;
      }).toList();
    }
    if (allocatedPrizes.isNotEmpty) {
      return allocatedPrizes.map((p) => p.name).toList();
    }
    if (promotionalRules.isNotEmpty) {
      return promotionalRules
          .map((r) => r.rewardValue.isNotEmpty ? r.rewardValue : r.linkedGiftsSummary)
          .where((n) => n.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Calculates the number of lottery/game chances earned based on the receipt spend.
  int calculateChancesEarned(double targetCompanySpend) {
    if (minimumSpend > 0 && targetCompanySpend < minimumSpend) return 0;
    if (!allowMultipleChances || !isSpendMultiplier || minimumSpend <= 0) return 1;
    final int computed = (targetCompanySpend / minimumSpend).floor();
    if (maxChancesPerReceipt > 0 && computed > maxChancesPerReceipt) {
      return maxChancesPerReceipt;
    }
    return computed > 0 ? computed : 1;
  }

  /// Calculates the number of rewards / chances earned based on purchased product quantity.
  int calculateQuantityMultiplier({required int matchedQuantity, required int minQuantityPerReward}) {
    if (!allowMultipleChances || !isQuantityMultiplier || minQuantityPerReward <= 0) return 1;
    final int computed = (matchedQuantity / minQuantityPerReward).floor();
    if (maxChancesPerReceipt > 0 && computed > maxChancesPerReceipt) {
      return maxChancesPerReceipt;
    }
    return computed > 0 ? computed : 1;
  }

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    return EventModel.fromFirestoreMap(
      doc.id,
      (doc.data() as Map<String, dynamic>?) ?? {},
    );
  }

  factory EventModel.fromFirestoreMap(String id, Map<String, dynamic> data) {
    return EventModel(
      id: id,
      eventName: data['eventName'] ?? '',
      targetCompany: data['targetCompany'] ?? '',
      companySlug: data['companySlug'] ?? '',
      companyLogoUrl: data['companyLogoUrl'] ?? data['logoUrl'] ?? '',
      minimumSpend: (data['minimumSpend'] as num?)?.toDouble() ?? 0.0,
      requiredProducts: List<String>.from(data['requiredProducts'] ?? []),
      customPrompt: data['customPrompt'] ?? '',
      welcomeTitle: data['welcomeTitle'] ?? '',
      welcomeMessage: data['welcomeMessage'] ?? '',
      termsAndConditions: data['termsAndConditions'] ?? '',
      startDate: data['startDate'] is Timestamp
          ? (data['startDate'] as Timestamp).toDate()
          : data['startDate'] is DateTime
              ? data['startDate'] as DateTime
              : null,
      endDate: data['endDate'] is Timestamp
          ? (data['endDate'] as Timestamp).toDate()
          : data['endDate'] is DateTime
              ? data['endDate'] as DateTime
              : null,
      isActive: data['isActive'] ?? true,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : data['createdAt'] is DateTime
              ? data['createdAt'] as DateTime
              : null,
      isPromoterActive: data['isPromoterActive'] ?? (data['isActive'] ?? true),
      isManagerActive: data['isManagerActive'] ?? (data['isActive'] ?? true),
      promotionalIdea: data['promotionalIdea']?.toString() ?? '',
      aiValidationSummary: data['aiValidationSummary']?.toString() ?? '',
      promotionalRules: (data['promotionalRules'] as List<dynamic>?)
              ?.map((e) => PromotionalRuleItem.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      gameType: data['gameType'] ?? 'wheel',
      allocatedPrizes: _deduplicatePrizes((data['allocatedPrizes'] as List<dynamic>?)
              ?.map((e) => AllocatedPrize.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          []),
      retailChainId: (data['retailChainId'] ?? '').toString(),
      retailChainName: (data['retailChainName'] ?? '').toString(),
      branchIds: _deduplicateStrings(List<String>.from(data['branchIds'] ?? [])),
      branchNames: _deduplicateStrings(List<String>.from(data['branchNames'] ?? [])),
      isAllBranches: data['isAllBranches'] ?? true,
      allowMultipleChances: data['allowMultipleChances'] == true,
      multiplierBasis: (data['multiplierBasis'] ?? 'both').toString(),
      maxChancesPerReceipt: (data['maxChancesPerReceipt'] as num?)?.toInt() ?? 0,
      requireVoucherSerials: data['requireVoucherSerials'] == true || data['require_voucher_serials'] == true,
    );
  }

  static List<String> _deduplicateStrings(List<String> list) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in list) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  static List<AllocatedPrize> _deduplicatePrizes(List<AllocatedPrize> list) {
    final seenKeys = <String>{};
    final result = <AllocatedPrize>[];
    for (final prize in list) {
      final key = '${prize.branchId}_${prize.giftId}_${prize.name}';
      if (seenKeys.add(key)) {
        result.add(prize);
      }
    }
    return result;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'eventName': eventName,
      'targetCompany': targetCompany,
      'companySlug': companySlug,
      'companyLogoUrl': companyLogoUrl,
      'minimumSpend': minimumSpend,
      'requiredProducts': requiredProducts,
      'customPrompt': customPrompt,
      'welcomeTitle': welcomeTitle,
      'welcomeMessage': welcomeMessage,
      'termsAndConditions': termsAndConditions,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'isActive': isActive,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'isPromoterActive': isPromoterActive,
      'isManagerActive': isManagerActive,
      'promotionalIdea': promotionalIdea,
      'aiValidationSummary': aiValidationSummary,
      'promotionalRules': promotionalRules.map((r) => r.toMap()).toList(),
      'gameType': gameType,
      'allocatedPrizes': _deduplicatePrizes(allocatedPrizes).map((p) => p.toMap()).toList(),
      'retailChainId': retailChainId,
      'retailChainName': retailChainName,
      'branchIds': _deduplicateStrings(branchIds),
      'branchNames': _deduplicateStrings(branchNames),
      'isAllBranches': isAllBranches,
      'allowMultipleChances': allowMultipleChances,
      'multiplierBasis': multiplierBasis,
      'maxChancesPerReceipt': maxChancesPerReceipt,
      'requireVoucherSerials': requireVoucherSerials,
    };
  }

  EventModel copyWith({
    String? id,
    String? eventName,
    String? targetCompany,
    String? companySlug,
    String? companyLogoUrl,
    double? minimumSpend,
    List<String>? requiredProducts,
    String? customPrompt,
    String? welcomeTitle,
    String? welcomeMessage,
    String? termsAndConditions,
    DateTime? startDate,
    DateTime? endDate,
    bool? isActive,
    DateTime? createdAt,
    bool? isPromoterActive,
    bool? isManagerActive,
    String? promotionalIdea,
    String? aiValidationSummary,
    List<PromotionalRuleItem>? promotionalRules,
    String? gameType,
    List<AllocatedPrize>? allocatedPrizes,
    String? retailChainId,
    String? retailChainName,
    List<String>? branchIds,
    List<String>? branchNames,
    bool? isAllBranches,
    bool? allowMultipleChances,
    String? multiplierBasis,
    int? maxChancesPerReceipt,
    bool? requireVoucherSerials,
  }) {
    return EventModel(
      id: id ?? this.id,
      eventName: eventName ?? this.eventName,
      targetCompany: targetCompany ?? this.targetCompany,
      companySlug: companySlug ?? this.companySlug,
      companyLogoUrl: companyLogoUrl ?? this.companyLogoUrl,
      minimumSpend: minimumSpend ?? this.minimumSpend,
      requiredProducts: requiredProducts ?? this.requiredProducts,
      customPrompt: customPrompt ?? this.customPrompt,
      welcomeTitle: welcomeTitle ?? this.welcomeTitle,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      termsAndConditions: termsAndConditions ?? this.termsAndConditions,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      isPromoterActive: isPromoterActive ?? this.isPromoterActive,
      isManagerActive: isManagerActive ?? this.isManagerActive,
      promotionalIdea: promotionalIdea ?? this.promotionalIdea,
      aiValidationSummary: aiValidationSummary ?? this.aiValidationSummary,
      promotionalRules: promotionalRules ?? this.promotionalRules,
      gameType: gameType ?? this.gameType,
      allocatedPrizes: allocatedPrizes ?? this.allocatedPrizes,
      retailChainId: retailChainId ?? this.retailChainId,
      retailChainName: retailChainName ?? this.retailChainName,
      branchIds: branchIds ?? this.branchIds,
      branchNames: branchNames ?? this.branchNames,
      isAllBranches: isAllBranches ?? this.isAllBranches,
      allowMultipleChances: allowMultipleChances ?? this.allowMultipleChances,
      multiplierBasis: multiplierBasis ?? this.multiplierBasis,
      maxChancesPerReceipt: maxChancesPerReceipt ?? this.maxChancesPerReceipt,
      requireVoucherSerials: requireVoucherSerials ?? this.requireVoucherSerials,
    );
  }
}

