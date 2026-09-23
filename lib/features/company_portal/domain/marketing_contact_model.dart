import 'package:cloud_firestore/cloud_firestore.dart';
import '../presentation/widgets/whatsapp_campaign_dispatcher_dialog.dart';

/// Represents a customer contact added manually or imported via Excel/CSV
/// for WhatsApp marketing and promotional campaigns.
class MarketingContactModel {
  final String id;
  final String name;
  final String rawPhone;
  final String cleanPhone;
  final String branch;
  final String companySlug;
  final String source; // 'manual' or 'excel_import'
  final String notes;
  final DateTime createdAt;

  const MarketingContactModel({
    required this.id,
    required this.name,
    required this.rawPhone,
    required this.cleanPhone,
    required this.branch,
    required this.companySlug,
    this.source = 'manual',
    this.notes = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name.trim(),
      'rawPhone': rawPhone.trim(),
      'cleanPhone': cleanPhone.trim(),
      'branch': branch.trim(),
      'companySlug': companySlug.trim().toLowerCase(),
      'source': source,
      'notes': notes.trim(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory MarketingContactModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return MarketingContactModel.fromMap(data, doc.id);
  }

  factory MarketingContactModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedDate = DateTime.now();
    if (map['createdAt'] is Timestamp) {
      parsedDate = (map['createdAt'] as Timestamp).toDate();
    } else if (map['createdAt'] is String) {
      parsedDate = DateTime.tryParse(map['createdAt']) ?? DateTime.now();
    }

    return MarketingContactModel(
      id: id,
      name: (map['name'] ?? '').toString(),
      rawPhone: (map['rawPhone'] ?? map['phone'] ?? '').toString(),
      cleanPhone: (map['cleanPhone'] ?? id).toString(),
      branch: (map['branch'] ?? '').toString(),
      companySlug: (map['companySlug'] ?? 'global').toString(),
      source: (map['source'] ?? 'manual').toString(),
      notes: (map['notes'] ?? '').toString(),
      createdAt: parsedDate,
    );
  }

  /// Converts this contact into CustomerCampaignContact for marketing table and queue dispatch
  CustomerCampaignContact toCustomerCampaignContact() {
    return CustomerCampaignContact(
      id: id,
      name: name.isNotEmpty ? name : 'عميل مسجل',
      rawPhone: rawPhone.isNotEmpty ? rawPhone : cleanPhone,
      cleanPhone: cleanPhone,
      totalSpend: 0,
      totalInvoices: 0,
      prizesWon: const [],
      branches: branch.isNotEmpty ? [branch] : const [],
      lastBranch: branch,
      lastVisitDate: createdAt,
      sourceTag: source,
    );
  }

  MarketingContactModel copyWith({
    String? name,
    String? rawPhone,
    String? cleanPhone,
    String? branch,
    String? companySlug,
    String? source,
    String? notes,
    DateTime? createdAt,
  }) {
    return MarketingContactModel(
      id: id,
      name: name ?? this.name,
      rawPhone: rawPhone ?? this.rawPhone,
      cleanPhone: cleanPhone ?? this.cleanPhone,
      branch: branch ?? this.branch,
      companySlug: companySlug ?? this.companySlug,
      source: source ?? this.source,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
