/// 2.0.148+206: company-shared prize stock.
///
/// Mirrors `findSharedPoolRow` / `sharedPoolEnabled` in
/// functions/security_functions.js. A campaign with no stock row for a gift
/// draws that gift from a sibling active campaign of the same company (same
/// branch row or a general row). `balanceMode: "campaign_only"` opts out.
library;

const String kBalanceModeCampaignOnly = 'campaign_only';

bool sharedPoolEnabledFor(Map<String, dynamic>? event) =>
    (event?['balanceMode'] ?? '').toString().trim() != kBalanceModeCampaignOnly;

/// Ids of active sibling campaigns (same company) that hold stock rows and
/// would feed [eventId] when it has no rows of its own.
List<String> sharedPoolSourceEventIds({
  required String eventId,
  required List<({String id, bool isActive, int rowCount})> companyEvents,
}) {
  final self = companyEvents.where((e) => e.id == eventId).toList();
  if (self.isEmpty || self.first.rowCount > 0) return const [];
  return companyEvents
      .where((e) => e.id != eventId && e.isActive && e.rowCount > 0)
      .map((e) => e.id)
      .toList();
}
