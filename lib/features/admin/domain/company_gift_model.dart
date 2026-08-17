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
  final DateTime? createdAt;

  CompanyGiftModel({
    required this.id,
    required this.companySlug,
    this.companyName = '',
    required this.giftName,
    required this.totalQuantity,
    required this.availableQuantity,
    this.allocatedInOtherCampaigns = 0,
    this.createdAt,
  });

  CompanyGiftModel copyWith({
    String? id,
    String? companySlug,
    String? companyName,
    String? giftName,
    int? totalQuantity,
    int? availableQuantity,
    int? allocatedInOtherCampaigns,
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
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory CompanyGiftModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
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
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }
}
