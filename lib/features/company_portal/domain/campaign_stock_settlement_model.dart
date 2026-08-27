import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a finalized stock settlement cycle / wave for a campaign.
/// Stores an immutable audit snapshot of quotas, claimed prizes, and returned stock per branch.
class CampaignStockSettlementModel {
  final String id;
  final String campaignId;
  final String campaignName;
  final String companySlug;
  final String cycleTitle;
  final DateTime settledAt;
  final String settledBy;
  final int totalAllocatedBefore;
  final int totalClaimed;
  final int totalReturned;
  final int newAllocatedStock;
  final Map<String, dynamic> branchSnapshots;

  CampaignStockSettlementModel({
    required this.id,
    required this.campaignId,
    required this.campaignName,
    required this.companySlug,
    required this.cycleTitle,
    required this.settledAt,
    required this.settledBy,
    required this.totalAllocatedBefore,
    required this.totalClaimed,
    required this.totalReturned,
    required this.newAllocatedStock,
    required this.branchSnapshots,
  });

  factory CampaignStockSettlementModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawDate = data['settledAt'] ?? data['settled_at'] ?? data['timestamp'];
    DateTime date = DateTime.now();
    if (rawDate is Timestamp) {
      date = rawDate.toDate();
    } else if (rawDate is String && rawDate.isNotEmpty) {
      date = DateTime.tryParse(rawDate) ?? DateTime.now();
    }

    return CampaignStockSettlementModel(
      id: doc.id,
      campaignId: (data['campaignId'] ?? data['campaign_id'] ?? '').toString(),
      campaignName: (data['campaignName'] ?? data['campaign_name'] ?? '').toString(),
      companySlug: (data['companySlug'] ?? data['company_slug'] ?? '').toString(),
      cycleTitle: (data['cycleTitle'] ?? data['cycle_title'] ?? 'تسوية دورة الويك إند').toString(),
      settledAt: date,
      settledBy: (data['settledBy'] ?? data['settled_by'] ?? 'مدير الشركة').toString(),
      totalAllocatedBefore: ((data['totalAllocatedBefore'] ?? data['total_allocated_before'] ?? 0) as num).toInt(),
      totalClaimed: ((data['totalClaimed'] ?? data['total_claimed'] ?? 0) as num).toInt(),
      totalReturned: ((data['totalReturned'] ?? data['total_returned'] ?? 0) as num).toInt(),
      newAllocatedStock: ((data['newAllocatedStock'] ?? data['new_allocated_stock'] ?? 0) as num).toInt(),
      branchSnapshots: (data['branchSnapshots'] ?? data['branch_snapshots'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'campaignId': campaignId,
      'campaignName': campaignName,
      'companySlug': companySlug,
      'cycleTitle': cycleTitle,
      'settledAt': FieldValue.serverTimestamp(),
      'settledBy': settledBy,
      'totalAllocatedBefore': totalAllocatedBefore,
      'totalClaimed': totalClaimed,
      'totalReturned': totalReturned,
      'newAllocatedStock': newAllocatedStock,
      'branchSnapshots': branchSnapshots,
    };
  }
}
