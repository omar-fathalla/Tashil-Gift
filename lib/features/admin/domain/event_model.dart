import 'package:cloud_firestore/cloud_firestore.dart';

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
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return EventModel(
      id: doc.id,
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
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      gameType: data['gameType'] ?? 'wheel',
      allocatedPrizes: (data['allocatedPrizes'] as List<dynamic>?)
              ?.map((e) => AllocatedPrize.fromMap(e as Map<String, dynamic>))
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
