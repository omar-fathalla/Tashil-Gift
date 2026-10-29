import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/services/company_gifts_service.dart';

/// Represents a specific quantity of an inventory gift allocated to a promotional rule
class LinkedGiftAllocation {
  final String giftId;
  final String giftName;
  final int quantity; // e.g. 2 of 50 EGP card, 1 of 25 EGP card
  final double unitValue; // 50.0
  final String giftType; // 'voucher' | 'product'
  final String? imageUrl;

  LinkedGiftAllocation({
    required this.giftId,
    required this.giftName,
    this.quantity = 1,
    this.unitValue = 0.0,
    this.giftType = 'product',
    this.imageUrl,
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
    String? imageUrl,
  }) {
    return LinkedGiftAllocation(
      giftId: giftId ?? this.giftId,
      giftName: giftName ?? this.giftName,
      quantity: quantity ?? this.quantity,
      unitValue: unitValue ?? this.unitValue,
      giftType: giftType ?? this.giftType,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  factory LinkedGiftAllocation.fromMap(Map<String, dynamic> data) {
    return LinkedGiftAllocation(
      giftId: data['giftId']?.toString() ?? '',
      giftName: data['giftName']?.toString() ?? '',
      quantity: (data['quantity'] as num?)?.toInt() ?? 1,
      unitValue: (data['unitValue'] as num?)?.toDouble() ?? 0.0,
      giftType: data['giftType']?.toString() ?? 'product',
      imageUrl: (data['imageUrl'] as String?)?.isNotEmpty == true ? (data['imageUrl'] as String) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'giftId': giftId,
      'giftName': giftName,
      'quantity': quantity,
      'unitValue': unitValue,
      'giftType': giftType,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
    };
  }
}

/// One selectable reward the customer may pick for a rule ("خيارات المكافأة").
/// Either a voucher with a value, or a gift linked from company inventory.
class RewardOption {
  final String id;
  final String kind; // 'voucher' | 'gift'
  final String label;
  final double voucherAmount;
  final String giftId;
  final String giftName;
  final String giftType; // inventory gift type: 'voucher' | 'product'
  final double unitValue;
  final String? imageUrl;
  /// Units handed out when this option is chosen (e.g. 2 chocolates). Default 1.
  final int quantity;

  const RewardOption({
    required this.id,
    this.kind = 'voucher',
    this.label = '',
    this.voucherAmount = 0.0,
    this.giftId = '',
    this.giftName = '',
    this.giftType = 'product',
    this.unitValue = 0.0,
    this.imageUrl,
    this.quantity = 1,
  });

  int get unitsPerChoice => quantity < 1 ? 1 : quantity;

  bool get isVoucher => kind == 'voucher' || giftType == 'voucher';

  /// Monetary value of one unit of this option (voucher amount, or voucher gift value).
  double get monetaryValue {
    if (kind == 'voucher') return voucherAmount > 0 ? voucherAmount : unitValue;
    return giftType == 'voucher' ? unitValue : 0.0;
  }

  String get displayLabel {
    if (label.trim().isNotEmpty) return label.trim();
    if (kind == 'gift' && giftName.trim().isNotEmpty) {
      return unitsPerChoice > 1 ? '$unitsPerChoice × ${giftName.trim()}' : giftName.trim();
    }
    final v = monetaryValue;
    final vText = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return 'قسيمة شراء $vText جنيه';
  }

  /// Converts the chosen option into the allocation used by the claim/stock path.
  LinkedGiftAllocation toAllocation({int multiplier = 1}) {
    final q = (multiplier < 1 ? 1 : multiplier) * unitsPerChoice;
    return LinkedGiftAllocation(
      giftId: giftId,
      giftName: kind == 'gift' && giftName.trim().isNotEmpty ? giftName.trim() : displayLabel,
      quantity: q,
      unitValue: kind == 'voucher' ? monetaryValue : unitValue,
      giftType: isVoucher ? 'voucher' : 'product',
      imageUrl: imageUrl,
    );
  }

  factory RewardOption.fromMap(Map<String, dynamic> data) {
    final kind = data['kind']?.toString() == 'gift' ? 'gift' : 'voucher';
    final img = data['imageUrl']?.toString();
    return RewardOption(
      id: data['id']?.toString() ?? '',
      kind: kind,
      label: data['label']?.toString() ?? '',
      voucherAmount: (data['voucherAmount'] as num?)?.toDouble() ?? 0.0,
      giftId: data['giftId']?.toString() ?? '',
      giftName: data['giftName']?.toString() ?? '',
      giftType: data['giftType']?.toString() ?? (kind == 'voucher' ? 'voucher' : 'product'),
      unitValue: (data['unitValue'] as num?)?.toDouble() ?? 0.0,
      imageUrl: (img != null && img.isNotEmpty) ? img : null,
      quantity: (data['quantity'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'kind': kind,
      if (label.trim().isNotEmpty) 'label': label.trim(),
      if (kind == 'voucher') 'voucherAmount': voucherAmount,
      if (giftId.isNotEmpty) 'giftId': giftId,
      if (giftName.isNotEmpty) 'giftName': giftName,
      'giftType': giftType,
      if (unitValue > 0) 'unitValue': unitValue,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      if (unitsPerChoice > 1) 'quantity': unitsPerChoice,
    };
  }

  /// Compact record stored on the receipt when the customer picks this option.
  Map<String, dynamic> toChosenRecord({String ruleId = '', String ruleTitle = '', int quantity = 1}) {
    return {
      'optionId': id,
      'kind': kind,
      'label': displayLabel,
      'value': monetaryValue,
      if (giftId.isNotEmpty) 'giftId': giftId,
      if (ruleId.isNotEmpty) 'ruleId': ruleId,
      if (ruleTitle.isNotEmpty) 'ruleTitle': ruleTitle,
      'quantity': (quantity < 1 ? 1 : quantity) * unitsPerChoice,
      if (unitsPerChoice > 1) 'unitsPerChoice': unitsPerChoice,
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
  final double? maxSpend; // Optional upper limit for spend range (e.g. 139.99 or 140.0)
  final double discountTolerance; // Optional discount tolerance in EGP (e.g. 5.0 EGP allows 95 EGP on 100 EGP rule)
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
  final String? gameType; // Specific delivery game: 'directGift' | 'scratch' | 'wheel' | 'chooseGift' | null (inherit from event)
  final List<RewardOption> rewardOptions; // Optional: customer picks exactly one (empty = legacy single reward)

  PromotionalRuleItem({
    required this.id,
    required this.ruleTitle,
    required this.triggerProduct,
    this.minQuantity = 1,
    this.conditionType = 'by_quantity',
    this.minSpend = 0.0,
    this.maxSpend,
    this.discountTolerance = 0.0,
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
    this.gameType,
    this.rewardOptions = const [],
  });

  /// True when the customer must choose one of several rewards for this rule.
  bool get hasRewardChoice => rewardOptions.length > 1;

  bool get hasLinkedGifts => linkedGifts.isNotEmpty || (linkedGiftId != null && linkedGiftId!.isNotEmpty);

  /// Whether this rule is evaluated based on total monetary spend (e.g. >= 100 EGP) rather than piece count
  bool get isSpendBased =>
      conditionType == 'by_spend' ||
      conditionType == 'combo_spend' ||
      (conditionType != 'by_quantity' && minSpend > 0);

  /// Whether this rule defines a bounded spend range (e.g. 95 to 139 EGP)
  bool get hasSpendRange => isSpendBased && maxSpend != null && maxSpend! > minSpend;

  /// Effective minimum spend taking discount tolerance into account
  double get effectiveMinSpend =>
      isSpendBased ? (minSpend - discountTolerance).clamp(0.0, double.infinity) : 0.0;

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
    final toleranceText = discountTolerance > 0 ? ' (سماحية خصومات ${discountTolerance.toInt()} ج.م)' : '';
    if (hasSpendRange) {
      final maxSpendInt = maxSpend == maxSpend!.roundToDouble() ? maxSpend!.toInt() : maxSpend;
      if (isCombo) {
        final brandsList = requiredBrands.isNotEmpty ? requiredBrands.join(' و ') : triggerProduct;
        return 'شراء بقيمة من $spendInt إلى $maxSpendInt ج.م من ($brandsList معاً)$toleranceText';
      } else {
        return 'شراء بقيمة من $spendInt إلى $maxSpendInt ج.م من [$triggerProduct]$toleranceText';
      }
    }
    if (isCombo) {
      final brandsList = requiredBrands.isNotEmpty ? requiredBrands.join(' و ') : triggerProduct;
      return 'شراء بقيمة $spendInt ج.م أو أكثر من ($brandsList معاً)$toleranceText';
    } else if (isSpendBased) {
      return 'شراء بقيمة $spendInt ج.م أو أكثر من [$triggerProduct]$toleranceText';
    } else {
      return 'شراء كمية ($minQuantity) قطعة أو أكثر من [$triggerProduct]';
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

    final condType = data['conditionType']?.toString() ?? 'by_quantity';
    final rawMinSpend = (data['minSpend'] as num?)?.toDouble() ?? 0.0;
    final effectiveMinSpend = condType == 'by_quantity' ? 0.0 : rawMinSpend;
    final effectiveMaxSpend = condType == 'by_quantity' ? null : (data['maxSpend'] as num?)?.toDouble();
    final effectiveDiscountTolerance = condType == 'by_quantity' ? 0.0 : ((data['discountTolerance'] as num?)?.toDouble() ?? 0.0);

    final parsedRewardOptions = (data['rewardOptions'] is List)
        ? (data['rewardOptions'] as List)
            .whereType<Map>()
            .map((e) => RewardOption.fromMap(Map<String, dynamic>.from(e)))
            .where((o) => o.kind == 'gift' ? (o.giftId.isNotEmpty || o.giftName.isNotEmpty) : o.monetaryValue > 0 || o.label.isNotEmpty)
            .toList()
        : <RewardOption>[];

    return PromotionalRuleItem(
      id: data['id']?.toString() ?? '',
      ruleTitle: data['ruleTitle']?.toString() ?? '',
      triggerProduct: data['triggerProduct']?.toString() ?? '',
      minQuantity: (data['minQuantity'] as num?)?.toInt() ?? 1,
      conditionType: condType,
      minSpend: effectiveMinSpend,
      maxSpend: effectiveMaxSpend,
      discountTolerance: effectiveDiscountTolerance,
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
      gameType: data['gameType']?.toString(),
      rewardOptions: parsedRewardOptions,
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
      'minSpend': conditionType == 'by_quantity' ? 0.0 : minSpend,
      if (conditionType != 'by_quantity' && maxSpend != null && maxSpend! > 0) 'maxSpend': maxSpend,
      if (conditionType != 'by_quantity' && discountTolerance > 0) 'discountTolerance': discountTolerance,
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
      if (gameType != null && gameType!.isNotEmpty) 'gameType': gameType,
      if (rewardOptions.isNotEmpty) 'rewardOptions': rewardOptions.map((o) => o.toMap()).toList(),
    };
  }

  PromotionalRuleItem copyWith({
    String? id,
    String? ruleTitle,
    String? triggerProduct,
    int? minQuantity,
    String? conditionType,
    double? minSpend,
    double? maxSpend,
    double? discountTolerance,
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
    String? gameType,
    List<RewardOption>? rewardOptions,
  }) {
    return PromotionalRuleItem(
      id: id ?? this.id,
      ruleTitle: ruleTitle ?? this.ruleTitle,
      triggerProduct: triggerProduct ?? this.triggerProduct,
      minQuantity: minQuantity ?? this.minQuantity,
      conditionType: conditionType ?? this.conditionType,
      minSpend: minSpend ?? this.minSpend,
      maxSpend: maxSpend ?? this.maxSpend,
      discountTolerance: discountTolerance ?? this.discountTolerance,
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
      gameType: gameType ?? this.gameType,
      rewardOptions: rewardOptions ?? this.rewardOptions,
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
  final String? imageUrl;

  AllocatedPrize({
    required this.giftId,
    required this.name,
    required this.allocatedQuantity,
    required this.remainingQuantity,
    this.branchId = '',
    this.branchName = '',
    this.giftType = 'product',
    this.unitValue = 0.0,
    this.imageUrl,
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
    String? imageUrl,
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
      imageUrl: imageUrl ?? this.imageUrl,
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
      imageUrl: (data['imageUrl'] as String?)?.isNotEmpty == true ? (data['imageUrl'] as String) : null,
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
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
    };
  }

  /// Checks whether this allocated prize is assigned to or compatible with [branch].
  /// Matches against branchId, branchName, and fuzzy normalized branch tokens.
  bool matchesBranch(String branch) {
    final b = branch.trim();
    if (b.isEmpty) return true;
    if (branchId.trim().isEmpty && branchName.trim().isEmpty) return true;
    if (branchId.trim().toLowerCase() == b.toLowerCase()) return true;
    if (branchName.trim().toLowerCase() == b.toLowerCase()) return true;
    return CompanyGiftsService.matchesBranchName(branchName, b) ||
        CompanyGiftsService.matchesBranchName(branchId, b);
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

  /// Independent control toggles for Promoter, Agency Operations, and Brand Executive Portals
  final bool isPromoterActive;
  final bool isAgencyActive;
  final bool isManagerActive;

  /// The raw natural language promotional idea typed by admin
  final String promotionalIdea;

  /// Human-readable structured Arabic/English summary produced by AI assistant
  final String aiValidationSummary;

  /// List of structured promotional rules parsed by AI
  final List<PromotionalRuleItem> promotionalRules;

  /// The type of game to show after receipt validation.
  /// Values: 'wheel' (عجلة الحظ), 'scratch' (امسح واربح), 'mysteryBox' (الصندوق الغامض), 'directGift' (هدية فورية مباشرة), 'chooseGift' (اختر هديتك - شبكة الاختيارات)
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

  /// Voucher serial entry mode on gift handover: 'required' | 'optional' | 'hidden'.
  /// Backward compatible: missing value derives from [requireVoucherSerials].
  final String voucherSerialMode;

  static String resolveVoucherSerialMode(Map<String, dynamic> data) {
    final raw = (data['voucherSerialMode'] ?? data['voucher_serial_mode'])?.toString().trim().toLowerCase();
    if (raw == 'required' || raw == 'optional' || raw == 'hidden') return raw!;
    final legacy = data['requireVoucherSerials'] == true || data['require_voucher_serials'] == true;
    return legacy ? 'required' : 'optional';
  }

  /// Whether to allow complementary / multi-receipt spend aggregation for this campaign (strictly false by default - AIR-61).
  final bool allowComplementaryReceipts;

  /// Whether to automatically send celebratory WhatsApp greeting messages to winning shoppers upon gift handover (true by default).
  final bool enableWhatsAppWinnerNotification;

  /// Tier 2 (Optional Campaign-Level Override): Whether this specific campaign uses custom Agency Operations credentials instead of inheriting Company-Level credentials.
  final bool hasCustomAgencyCredentials;
  final String customAgencyUsername;
  final String customAgencyPassword;
  final int customAgencyCredentialVersion;

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
    this.isAgencyActive = true,
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
    this.voucherSerialMode = 'optional',
    this.allowComplementaryReceipts = false,
    this.enableWhatsAppWinnerNotification = true,
    this.hasCustomAgencyCredentials = false,
    this.customAgencyUsername = '',
    this.customAgencyPassword = '',
    this.customAgencyCredentialVersion = 1,
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
  bool get canAgencyAccess => isActive && isAgencyActive;
  bool get canManagerAccess => isManagerActive;

  /// Formatted branches display for UI chips & summaries
  String get branchesDisplaySummary {
    if (retailChainName.isEmpty) return 'غير محدد';
    if (isAllBranches || branchNames.isEmpty) return '$retailChainName (جميع الفروع)';
    if (branchNames.length == 1) return '$retailChainName - ${branchNames.first}';
    return '$retailChainName (${branchNames.length} فروع: ${branchNames.join('، ')})';
  }

  /// Returns only prizes that still have remaining stock (> 0) for the given [branch] (branchId or branchName).
  /// Resolves any branch query (branchId, branchName, store code, normalized token)
  /// against event.branchIds, event.branchNames, and allocatedPrizes to discover all synonyms.
  Set<String> resolveBranchAliases(String branchQuery) {
    final query = branchQuery.trim();
    if (query.isEmpty) return const {};

    final aliases = <String>{query.toLowerCase()};
    final normQuery = CompanyGiftsService.normalizeBranchToken(query);
    if (normQuery.isNotEmpty) aliases.add(normQuery.toLowerCase());

    // 1. Cross-reference with event.branchIds and event.branchNames
    for (int i = 0; i < branchIds.length; i++) {
      final bId = branchIds[i].trim().toLowerCase();
      final bName = i < branchNames.length ? branchNames[i].trim() : '';
      final bNameNorm = CompanyGiftsService.normalizeBranchToken(bName).toLowerCase();

      final matchesId = bId == query.toLowerCase() ||
          (query.contains('_') && bId.endsWith(query.toLowerCase())) ||
          (bId.contains('_') && query == bId.split('_').last);
      final matchesName = bName.toLowerCase() == query.toLowerCase() ||
          (bNameNorm.isNotEmpty && bNameNorm == normQuery.toLowerCase()) ||
          CompanyGiftsService.matchesBranchName(bName, query);

      if (matchesId || matchesName) {
        if (bId.isNotEmpty) aliases.add(bId);
        if (bName.isNotEmpty) {
          aliases.add(bName.toLowerCase());
          if (bNameNorm.isNotEmpty) aliases.add(bNameNorm);
        }
      }
    }

    // 2. Cross-reference with allocatedPrizes
    for (final p in allocatedPrizes) {
      final pId = p.branchId.trim().toLowerCase();
      final pName = p.branchName.trim();
      final pNameNorm = CompanyGiftsService.normalizeBranchToken(pName).toLowerCase();

      final matchesId = pId.isNotEmpty &&
          (pId == query.toLowerCase() || (pId.contains('_') && query == pId.split('_').last));
      final matchesName = pName.isNotEmpty &&
          (pName.toLowerCase() == query.toLowerCase() ||
              (pNameNorm.isNotEmpty && pNameNorm == normQuery.toLowerCase()) ||
              CompanyGiftsService.matchesBranchName(pName, query));

      if (matchesId || matchesName) {
        if (pId.isNotEmpty) aliases.add(pId);
        if (pName.isNotEmpty) {
          aliases.add(pName.toLowerCase());
          if (pNameNorm.isNotEmpty) aliases.add(pNameNorm);
        }
      }
    }

    return aliases;
  }

  /// Returns allocated prizes that still have remaining stock (remainingQuantity > 0),
  /// strictly filtered for [branch] if specified.
  ///
  /// - If [branch] is provided and the campaign has allocations specifically for this branch,
  ///   it strictly returns those branch allocations where remainingQuantity > 0.
  /// - If no branch allocations match [branch], it checks general allocations (unassigned to any specific branch).
  /// - If [branch] is null or empty, it returns all allocated prizes with remainingQuantity > 0.
  List<AllocatedPrize> availablePrizesForBranch([String? branch]) {
    if (allocatedPrizes.isEmpty) return const [];

    final targetBranch = (branch ?? '').trim();
    if (targetBranch.isEmpty) {
      return allocatedPrizes.where((p) => p.remainingQuantity > 0).toList();
    }

    final aliases = resolveBranchAliases(targetBranch);

    // 1. Check for specific allocations matching this branch or any of its aliases
    final branchSpecific = allocatedPrizes.where((p) {
      if (p.branchId.trim().isEmpty && p.branchName.trim().isEmpty) return false;
      for (final alias in aliases) {
        if (p.matchesBranch(alias)) return true;
      }
      return false;
    }).toList();

    if (branchSpecific.isNotEmpty) {
      // Strictly enforce remainingQuantity > 0 for this specific branch
      return branchSpecific.where((p) => p.remainingQuantity > 0).toList();
    }

    // 2. Check for general allocations (accessible across all branches)
    final generalAllocations = allocatedPrizes.where((p) =>
        p.branchId.trim().isEmpty && p.branchName.trim().isEmpty).toList();

    if (generalAllocations.isNotEmpty) {
      return generalAllocations.where((p) => p.remainingQuantity > 0).toList();
    }

    return const [];
  }

  /// Returns clean prize names for display in games (strictly available ones with remainingQuantity > 0 for [branch]).
  List<String> availablePrizeNamesForBranch([String? branch]) {
    final available = availablePrizesForBranch(branch);
    if (available.isNotEmpty) {
      final seen = <String>{};
      final List<String> distinct = [];
      for (final p in available) {
        String name = p.name.trim();
        if (p.isVoucher && p.unitValue > 0) {
          final val = p.unitValue == p.unitValue.roundToDouble() ? p.unitValue.toInt() : p.unitValue;
          if (!name.contains('$val')) {
            name = '$name ($val ج.م)';
          }
        }
        if (name.isNotEmpty && seen.add(name)) {
          distinct.add(name);
        }
      }
      return distinct;
    }

    // Only if NO allocated prizes are configured for the entire campaign (legacy/promotional-only campaign),
    // fallback to promotional rules reward values.
    if (allocatedPrizes.isEmpty && promotionalRules.isNotEmpty) {
      return promotionalRules
          .map((r) => r.rewardValue.isNotEmpty ? r.rewardValue : r.linkedGiftsSummary)
          .where((n) => n.trim().isNotEmpty)
          .map((n) => n.trim())
          .toSet()
          .toList();
    }

    return const [];
  }

  /// Filters candidate gifts (e.g. from promotional rules) strictly against remaining stock for [branch].
  /// Any item with remainingQuantity <= 0 in this branch is strictly excluded.
  List<String> filterGiftsByBranchStock({
    required List<String> candidateGifts,
    String? branch,
  }) {
    // If the campaign has no inventory management configured, return raw candidates
    if (allocatedPrizes.isEmpty) {
      return candidateGifts.where((g) => g.trim().isNotEmpty).toSet().toList();
    }

    final inStockPrizeNames = availablePrizeNamesForBranch(branch);
    final targetBranch = (branch ?? '').trim();
    final aliases = resolveBranchAliases(targetBranch);

    // Find all allocations relevant to this branch (including general ones)
    final relevantAllocations = allocatedPrizes.where((p) {
      if (targetBranch.isEmpty) return true;
      final isGeneral = p.branchId.trim().isEmpty && p.branchName.trim().isEmpty;
      if (isGeneral) return true;
      for (final alias in aliases) {
        if (p.matchesBranch(alias)) return true;
      }
      return false;
    }).toList();

    if (candidateGifts.isEmpty) {
      return inStockPrizeNames;
    }

    final List<String> validCandidates = [];
    for (final candidate in candidateGifts) {
      final cleanCandidate = candidate.trim();
      if (cleanCandidate.isEmpty) continue;

      // Find if this candidate matches an allocation
      final matchedAlloc = relevantAllocations.where((p) {
        final pName = p.name.trim().toLowerCase();
        final cName = cleanCandidate.toLowerCase();
        return pName == cName || pName.contains(cName) || cName.contains(pName);
      }).firstOrNull;

      if (matchedAlloc != null) {
        if (matchedAlloc.remainingQuantity > 0) {
          validCandidates.add(cleanCandidate);
        }
      } else {
        // If not explicitly tracked, but matches an in-stock prize name, keep it
        final matchesInStock = inStockPrizeNames.any((p) {
          final pLow = p.toLowerCase();
          final cLow = cleanCandidate.toLowerCase();
          return pLow == cLow || pLow.contains(cLow) || cLow.contains(pLow);
        });
        if (matchesInStock) {
          validCandidates.add(cleanCandidate);
        }
      }
    }

    if (validCandidates.isNotEmpty) {
      return validCandidates.toSet().toList();
    }

    // Fallback: If candidate gifts were all out of stock in this branch,
    // return whatever in-stock prizes are available in this branch.
    return inStockPrizeNames;
  }

  /// Returns only prizes that still have remaining stock.
  List<AllocatedPrize> get availablePrizes => availablePrizesForBranch(null);

  /// Returns prize names for display in games (only available ones with remainingQuantity > 0, deduplicated).
  List<String> get availablePrizeNames => availablePrizeNamesForBranch(null);

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
      isAgencyActive: data['isAgencyActive'] ?? (data['isActive'] ?? true),
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
      requireVoucherSerials: EventModel.resolveVoucherSerialMode(data) == 'required',
      voucherSerialMode: EventModel.resolveVoucherSerialMode(data),
      allowComplementaryReceipts: data['allowComplementaryReceipts'] == true || data['allow_complementary_receipts'] == true,
      enableWhatsAppWinnerNotification: data['enableWhatsAppWinnerNotification'] != false && data['enable_whatsapp_winner_notification'] != false,
      hasCustomAgencyCredentials: data['hasCustomAgencyCredentials'] == true,
      customAgencyUsername: (data['customAgencyUsername'] ?? '').toString(),
      customAgencyPassword: (data['customAgencyPassword'] ?? '').toString(),
      customAgencyCredentialVersion: (data['customAgencyCredentialVersion'] as num?)?.toInt() ?? 1,
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
      final bKey = prize.branchId.isNotEmpty ? prize.branchId : prize.branchName.trim().toLowerCase();
      final gKey = prize.giftId.isNotEmpty ? prize.giftId : prize.name.trim().toLowerCase();
      final key = '${bKey}_$gKey';
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
      'isAgencyActive': isAgencyActive,
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
      'requireVoucherSerials': voucherSerialMode == 'required',
      'voucherSerialMode': voucherSerialMode,
      'allowComplementaryReceipts': allowComplementaryReceipts,
      'enableWhatsAppWinnerNotification': enableWhatsAppWinnerNotification,
      'hasCustomAgencyCredentials': hasCustomAgencyCredentials,
      'customAgencyUsername': customAgencyUsername,
      'customAgencyPassword': customAgencyPassword,
      'customAgencyCredentialVersion': customAgencyCredentialVersion,
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
    bool? isAgencyActive,
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
    String? voucherSerialMode,
    bool? allowComplementaryReceipts,
    bool? enableWhatsAppWinnerNotification,
    bool? hasCustomAgencyCredentials,
    String? customAgencyUsername,
    String? customAgencyPassword,
    int? customAgencyCredentialVersion,
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
      isAgencyActive: isAgencyActive ?? this.isAgencyActive,
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
      voucherSerialMode: voucherSerialMode ?? (requireVoucherSerials == null ? this.voucherSerialMode : (requireVoucherSerials ? 'required' : 'optional')),
      allowComplementaryReceipts: allowComplementaryReceipts ?? this.allowComplementaryReceipts,
      enableWhatsAppWinnerNotification: enableWhatsAppWinnerNotification ?? this.enableWhatsAppWinnerNotification,
      hasCustomAgencyCredentials: hasCustomAgencyCredentials ?? this.hasCustomAgencyCredentials,
      customAgencyUsername: customAgencyUsername ?? this.customAgencyUsername,
      customAgencyPassword: customAgencyPassword ?? this.customAgencyPassword,
      customAgencyCredentialVersion: customAgencyCredentialVersion ?? this.customAgencyCredentialVersion,
    );
  }
}

