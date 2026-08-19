import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a gift/prize in a company's master inventory.
class CompanyGiftModel {
  final String id;
  final String companySlug;
  final String companyName;
  final String giftName;
  final int totalQuantity;
  final int availableQuantity;
  final int allocatedInOtherCampaigns;
  final String giftType; // 'product' | 'voucher'
  final double unitValue; // Denomination / face value per card for vouchers (e.g. 25.0, 50.0, 100.0)
  final int orderIndex; // Index for drag & drop custom sorting
  final DateTime? createdAt;

  CompanyGiftModel({
    required this.id,
    required this.companySlug,
    this.companyName = '',
    required this.giftName,
    required this.totalQuantity,
    required this.availableQuantity,
    this.allocatedInOtherCampaigns = 0,
    this.giftType = 'product',
    this.unitValue = 0.0,
    this.orderIndex = 0,
    this.createdAt,
  });

  bool get isVoucher => giftType == 'voucher' || unitValue > 0;

  /// Total monetary value of all cards in inventory (e.g. 200 cards * 50 EGP = 10,000 EGP)
  double get totalMonetaryValue => isVoucher ? (totalQuantity * unitValue) : 0.0;

  /// Available monetary value of remaining cards
  double get availableMonetaryValue => isVoucher ? (availableQuantity * unitValue) : 0.0;

  String get formattedUnitValue => isVoucher
      ? (unitValue == unitValue.roundToDouble() ? '${unitValue.toInt()} ج.م' : '$unitValue ج.م')
      : '';

  CompanyGiftModel copyWith({
    String? id,
    String? companySlug,
    String? companyName,
    String? giftName,
    int? totalQuantity,
    int? availableQuantity,
    int? allocatedInOtherCampaigns,
    String? giftType,
    double? unitValue,
    int? orderIndex,
    DateTime? createdAt,
  }) {
    return CompanyGiftModel(
      id: id ?? this.id,
      companySlug: companySlug ?? this.companySlug,
      companyName: companyName ?? this.companyName,
      giftName: giftName ?? this.giftName,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      availableQuantity: availableQuantity ?? this.availableQuantity,
      allocatedInOtherCampaigns: allocatedInOtherCampaigns ?? this.allocatedInOtherCampaigns,
      giftType: giftType ?? this.giftType,
      unitValue: unitValue ?? this.unitValue,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory CompanyGiftModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawUnitVal = (data['unitValue'] as num?)?.toDouble() ?? 0.0;
    final rawType = data['giftType'] as String? ?? (rawUnitVal > 0 ? 'voucher' : 'product');
    final rawOrder = (data['orderIndex'] as num?)?.toInt() ?? (data['order'] as num?)?.toInt() ?? 0;

    return CompanyGiftModel(
      id: doc.id,
      companySlug: data['companySlug'] ?? '',
      companyName: data['companyName'] ?? '',
      giftName: (data['giftName'] as String?)?.isNotEmpty == true
          ? data['giftName']
          : (data['name'] ?? ''),
      totalQuantity: (data['totalQuantity'] as num?)?.toInt() ?? 0,
      availableQuantity: (data['availableQuantity'] as num?)?.toInt() ?? 0,
      allocatedInOtherCampaigns: 0,
      giftType: rawType,
      unitValue: rawUnitVal,
      orderIndex: rawOrder,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'companySlug': companySlug.toLowerCase().trim(),
      'companyName': companyName,
      'giftName': giftName,
      'totalQuantity': totalQuantity,
      'availableQuantity': availableQuantity,
      'giftType': giftType,
      'unitValue': unitValue,
      'orderIndex': orderIndex,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }
}
