import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/arabic_numbers_utils.dart';
import '../presentation/widgets/whatsapp_campaign_dispatcher_dialog.dart';
import 'company_supervisor_import.dart';

/// Stored WhatsApp audience member for company supervisors (مشرفين الشركات).
///
/// This list is not derived from receipts, gifts, or marketing customers.
/// The document id is the Western-digit Egyptian mobile so re-imports update
/// the same record instead of creating a second one.
class CompanySupervisor {
  static const String audienceId = companySupervisorsAudience;
  static const String collectionName = companySupervisorsCollection;

  factory CompanySupervisor.fromImport(ImportedCompanySupervisor row, {DateTime? createdAt}) {
    return CompanySupervisor(
      id: row.mobile,
      name: row.name,
      alternateNames: row.alternateNames,
      mobile: row.mobile,
      cleanPhone: row.cleanPhone,
      source: row.source,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  final String id;
  final String name;
  final List<String> alternateNames;
  final String mobile;
  final String cleanPhone;
  final String source;
  final DateTime? createdAt;

  const CompanySupervisor({
    required this.id,
    required this.name,
    required this.alternateNames,
    required this.mobile,
    required this.cleanPhone,
    this.source = 'excel_import',
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name.trim(),
      'alternateNames': alternateNames,
      'mobile': mobile,
      'cleanPhone': cleanPhone,
      'source': source,
      'audience': audienceId,
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime.now()),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory CompanySupervisor.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CompanySupervisor.fromMap(data, doc.id);
  }

  factory CompanySupervisor.fromMap(Map<String, dynamic> map, String id) {
    DateTime? createdAt;
    final rawCreated = map['createdAt'];
    if (rawCreated is Timestamp) {
      createdAt = rawCreated.toDate();
    } else if (rawCreated is String) {
      createdAt = DateTime.tryParse(rawCreated);
    }

    final mobile = (map['mobile'] ?? id).toString().toEnglishDigits().trim();
    final alternates = <String>[];
    final rawAlternates = map['alternateNames'];
    if (rawAlternates is List) {
      for (final item in rawAlternates) {
        final name = item.toString().trim();
        if (name.isNotEmpty) alternates.add(name);
      }
    }

    return CompanySupervisor(
      id: id,
      name: (map['name'] ?? '').toString().trim(),
      alternateNames: alternates,
      mobile: mobile,
      cleanPhone: (map['cleanPhone'] ?? '').toString().toEnglishDigits().trim(),
      source: (map['source'] ?? 'excel_import').toString(),
      createdAt: createdAt,
    );
  }

  /// Collapses duplicate mobiles. The longer name stays primary and the other
  /// name is kept as an alternate.
  static List<CompanySupervisor> dedupeByMobile(List<CompanySupervisor> raw) {
    final byMobile = <String, CompanySupervisor>{};
    for (final supervisor in raw) {
      final mobile = supervisor.mobile;
      if (mobile.isEmpty) continue;
      final existing = byMobile[mobile];
      if (existing == null) {
        byMobile[mobile] = supervisor;
        continue;
      }
      final keepNext = supervisor.name.length > existing.name.length;
      final primary = keepNext ? supervisor : existing;
      final secondary = keepNext ? existing : supervisor;
      final alternates = {...primary.alternateNames, ...secondary.alternateNames, secondary.name}
          .where((name) => name.trim().isNotEmpty && name.trim() != primary.name)
          .toList();
      byMobile[mobile] = CompanySupervisor(
        id: primary.mobile,
        name: primary.name,
        alternateNames: alternates,
        mobile: primary.mobile,
        cleanPhone: primary.cleanPhone.isNotEmpty ? primary.cleanPhone : secondary.cleanPhone,
        source: primary.source,
        createdAt: existing.createdAt ?? supervisor.createdAt,
      );
    }
    final list = byMobile.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Contact row used by the existing WhatsApp compose, select, and send flow.
  CustomerCampaignContact toCampaignContact() {
    return CustomerCampaignContact(
      id: 'supervisor_$mobile',
      name: name,
      rawPhone: mobile,
      cleanPhone: cleanPhone,
      totalSpend: 0,
      totalInvoices: 0,
      prizesWon: const [],
      branches: const [],
      lastBranch: '',
      lastVisitDate: createdAt,
      sourceTag: 'company_supervisor',
      alternateNames: alternateNames,
    );
  }
}
