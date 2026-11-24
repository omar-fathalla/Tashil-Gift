/// Gifts handed out in one branch, read from its receipts (TG-2).
///
/// Each claimed gift entry is stored once. A gift column then counts an entry
/// by its giftId when the entry has one that names a known gift, otherwise by
/// the entry's gift name. So a receipt saved by an old app version (no giftId)
/// and a newer one (with giftId) both count toward the same row, and no entry
/// is ever counted twice. Before this, an entry with a giftId hid every
/// legacy name-only entry of the same gift (Smouha: 100 handed out, table 51).
class BranchClaimTally {
  final List<({String id, String name, int qty})> _entries = [];
  final Map<String, int> _legacyKeys = {};

  static String _norm(String s) => s.trim().toLowerCase();

  /// One claimed_gifts / linkedGifts entry.
  void addEntry({required String giftId, required String giftName, required int qty}) {
    _entries.add((id: _norm(giftId), name: _norm(giftName), qty: qty));
  }

  /// A receipt with no structured gift entries (`prizes_won`, `prize_won`, `voucher_VALUE`).
  void addLegacyKey(String key, int qty) {
    final k = _norm(key);
    if (k.isEmpty) return;
    _legacyKeys[k] = (_legacyKeys[k] ?? 0) + qty;
  }

  /// Units of one gift column handed out in this branch.
  ///
  /// [knownGiftIds] / [knownGiftNames] are every gift column of the table, so an
  /// entry that belongs to another column is never fuzzily matched to this one.
  int claimedFor({
    required String giftId,
    required String giftName,
    required bool isVoucher,
    required double unitValue,
    required Set<String> knownGiftIds,
    required Set<String> knownGiftNames,
  }) {
    final id = _norm(giftId);
    final name = _norm(giftName);
    final ids = knownGiftIds.map(_norm).toSet();
    final names = knownGiftNames.map(_norm).toSet();
    var total = 0;
    final unresolved = <String, int>{};
    for (final e in _entries) {
      if (e.id.isNotEmpty && ids.contains(e.id)) {
        if (e.id == id) total += e.qty;
        continue;
      }
      if (e.name.isNotEmpty && names.contains(e.name)) {
        if (e.name == name) total += e.qty;
        continue;
      }
      if (e.name.isNotEmpty) unresolved[e.name] = (unresolved[e.name] ?? 0) + e.qty;
    }
    // Loose matching (as before) only for entries no column claims exactly.
    void loose(String k, int n) {
      if (name.isNotEmpty && (k.contains(name) || name.contains(k))) {
        total += n;
      } else if (isVoucher) {
        final denom = unitValue.toInt();
        if (denom > 0 && (k.contains('$denom') || k == 'voucher_$denom')) total += n;
      }
    }

    unresolved.forEach(loose);
    _legacyKeys.forEach(loose);
    return total;
  }
}
