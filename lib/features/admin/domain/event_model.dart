import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a structured promotional rule/offer condition (e.g. "Buy 1 Axe/Rexona spray -> Get 50 EGP voucher")
class PromotionalRuleItem {
  final String id;
  final String ruleTitle;
  final String triggerProduct;
  final int minQuantity;
  final String rewardType; // 'voucher' | 'free_product' | 'game_spin'
  final String rewardValue; // e.g. 'قسيمة مشتريات 50 ج.م' or 'كلير 90 مل هدية'
  final double rewardAmount; // 50.0 if voucher
  final bool allowMultipliers; // true if buying 2x items gives 2x rewards

  PromotionalRuleItem({
    required this.id,
    required this.ruleTitle,
    required this.triggerProduct,
    this.minQuantity = 1,
    this.rewardType = 'free_product',
    required this.rewardValue,
    this.rewardAmount = 0.0,
    this.allowMultipliers = true,
  });

  factory PromotionalRuleItem.fromMap(Map<String, dynamic> data) {
    return PromotionalRuleItem(
      id: data['id']?.toString() ?? '',
      ruleTitle: data['ruleTitle']?.toString() ?? '',
      triggerProduct: data['triggerProduct']?.toString() ?? '',
      minQuantity: (data['minQuantity'] as num?)?.toInt() ?? 1,
      rewardType: data['rewardType']?.toString() ?? 'free_product',
      rewardValue: data['rewardValue']?.toString() ?? '',
      rewardAmount: (data['rewardAmount'] as num?)?.toDouble() ?? 0.0,
      allowMultipliers: data['allowMultipliers'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ruleTitle': ruleTitle,
      'triggerProduct': triggerProduct,
      'minQuantity': minQuantity,
      'rewardType': rewardType,
      'rewardValue': rewardValue,
      'rewardAmount': rewardAmount,
      'allowMultipliers': allowMultipliers,
    };
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

  AllocatedPrize({
    required this.giftId,
    required this.name,
    required this.allocatedQuantity,
    required this.remainingQuantity,
    this.branchId = '',
    this.branchName = '',
  });

  factory AllocatedPrize.fromMap(Map<String, dynamic> data) {
    return AllocatedPrize(
      giftId: data['giftId'] ?? '',
      name: data['name'] ?? '',
      allocatedQuantity: (data['allocatedQuantity'] as num?)?.toInt() ?? 0,
      remainingQuantity: (data['remainingQuantity'] as num?)?.toInt() ?? 0,
      branchId: data['branchId'] ?? '',
      branchName: data['branchName'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'giftId': giftId,
      'name': name,
      'allocatedQuantity': allocatedQuantity,
      'remainingQuantity': remainingQuantity,
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

  /// Whether to grant multiple draw/spin chances when the customer spends multiples of the minimum spend.
  final bool allowMultipleChances;

  /// Maximum draw chances allowed per single receipt (0 = unlimited / no cap).
  final int maxChancesPerReceipt;

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
    this.maxChancesPerReceipt = 0,
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
    return availablePrizes.map((p) => p.name).toList();
  }

  /// Calculates the number of lottery/game chances earned based on the receipt spend.
  int calculateChancesEarned(double targetCompanySpend) {
    if (minimumSpend <= 0 || targetCompanySpend < minimumSpend) return 0;
    if (!allowMultipleChances) return 1;
    final int computed = (targetCompanySpend / minimumSpend).floor();
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
      promotionalIdea: data['promotionalIdea']?.toString() ?? '',
      aiValidationSummary: data['aiValidationSummary']?.toString() ?? '',
      promotionalRules: (data['promotionalRules'] as List<dynamic>?)
              ?.map((e) => PromotionalRuleItem.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      gameType: data['gameType'] ?? 'wheel',
      allocatedPrizes: (data['allocatedPrizes'] as List<dynamic>?)
              ?.map((e) => AllocatedPrize.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      retailChainId: data['retailChainId'] ?? '',
      retailChainName: data['retailChainName'] ?? '',
      branchIds: List<String>.from(data['branchIds'] ?? []),
      branchNames: List<String>.from(data['branchNames'] ?? []),
      isAllBranches: data['isAllBranches'] ?? true,
      allowMultipleChances: data['allowMultipleChances'] == true,
      maxChancesPerReceipt: (data['maxChancesPerReceipt'] as num?)?.toInt() ?? 0,
    );
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
      'promotionalIdea': promotionalIdea,
      'aiValidationSummary': aiValidationSummary,
      'promotionalRules': promotionalRules.map((r) => r.toMap()).toList(),
      'gameType': gameType,
      'allocatedPrizes': allocatedPrizes.map((p) => p.toMap()).toList(),
      'retailChainId': retailChainId,
      'retailChainName': retailChainName,
      'branchIds': branchIds,
      'branchNames': branchNames,
      'isAllBranches': isAllBranches,
      'allowMultipleChances': allowMultipleChances,
      'maxChancesPerReceipt': maxChancesPerReceipt,
    };
  }
}

