/// How many gift units are already stored. A missing quantity counts as one,
/// matching the server ledger.
int claimedLedgerUnits(Object? raw) {
  if (raw is! List) return 0;
  var total = 0;
  for (final entry in raw) {
    total += claimedEntryUnits(entry);
  }
  return total;
}

int claimedEntryUnits(Object? gift) {
  if (gift is! Map) return 1;
  final quantity = gift['quantity'];
  if (quantity == null || quantity == '') return 1;
  final parsed = quantity is num ? quantity.toDouble() : double.tryParse('$quantity');
  if (parsed == null || parsed <= 0) return 1;
  return parsed.floor();
}

class GiftResume {
  final int claimedUnits;
  final int currentRound;
  final int remaining;
  final List<String> wonNames;

  const GiftResume({
    required this.claimedUnits,
    required this.currentRound,
    required this.remaining,
    required this.wonNames,
  });
}

/// Next screen position from the stored gift list. [totalRounds] is the full
/// award, not the chances still left.
GiftResume resumeFromLedger({
  required Object? claimedGifts,
  required int totalRounds,
}) {
  final total = totalRounds > 0 ? totalRounds : 1;
  final claimed = claimedLedgerUnits(claimedGifts);
  final done = claimed > total ? total : claimed;
  final names = <String>[];
  if (claimedGifts is List) {
    for (final entry in claimedGifts) {
      final units = claimedEntryUnits(entry);
      final name = entry is Map ? '${entry['giftName'] ?? ''}'.trim() : '';
      for (var i = 0; i < units; i++) {
        names.add(name);
      }
    }
  }
  return GiftResume(
    claimedUnits: done,
    currentRound: done >= total ? total : done + 1,
    remaining: total - done,
    wonNames: names.take(done).toList(),
  );
}
