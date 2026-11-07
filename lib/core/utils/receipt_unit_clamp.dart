import 'package:al_mraay/features/admin/domain/event_model.dart';

/// 2.0.164: client mirror of the server's per-receipt piece limit
/// (`receiptUnitLimit` in functions/security_functions.js).
///
/// Smart Multipliers ON with cap N => N offers x pieces per offer.
/// Returns null when there is no cap (switch OFF is already limited to one
/// offer per rule by the matcher, and the server still enforces it).
int? receiptPieceLimitFromEvent(Map<String, dynamic> event, {int? receiptChances}) {
  final allow = event['allowMultipleChances'] == true;
  final cap = (event['maxChancesPerReceipt'] as num?)?.toInt() ??
      int.tryParse('${event['maxChancesPerReceipt'] ?? ''}') ??
      0;
  int? units = allow && cap > 0 ? cap : null;
  if (receiptChances != null && receiptChances > 0) {
    units = units == null ? receiptChances : (units < receiptChances ? units : receiptChances);
  }
  if (units == null) return null;
  return units * piecesPerOfferFromEvent(event);
}

/// Most pieces any one rule's offer hands over (>= 1).
int piecesPerOfferFromEvent(Map<String, dynamic> event) {
  final rules = event['promotionalRules'];
  int best = 1;
  if (rules is List) {
    for (final r in rules) {
      final gifts = r is Map ? r['linkedGifts'] : null;
      if (gifts is! List) continue;
      int sum = 0;
      for (final g in gifts) {
        if (g is! Map) continue;
        final q = g['quantity'];
        final n = q is num ? q.floor() : (num.tryParse('$q')?.floor() ?? 0);
        if (n > 0) sum += n;
      }
      if (sum > best) best = sum;
    }
  }
  return best;
}

int totalPieces(List<LinkedGiftAllocation> gifts) =>
    gifts.fold<int>(0, (s, g) => s + (g.quantity > 0 ? g.quantity : 0));

/// Trims [gifts] to at most [limit] pieces, highest unit value first.
/// Keeps the original order; drops gifts that end up with 0 pieces.
List<LinkedGiftAllocation> clampLinkedGiftsToPieces(List<LinkedGiftAllocation> gifts, int? limit) {
  if (limit == null || limit <= 0 || gifts.isEmpty) return gifts;
  if (totalPieces(gifts) <= limit) return gifts;
  final order = List<int>.generate(gifts.length, (i) => i)
    ..sort((a, b) {
      final c = gifts[b].unitValue.compareTo(gifts[a].unitValue);
      return c != 0 ? c : a.compareTo(b);
    });
  final kept = <int, int>{};
  int left = limit;
  for (final i in order) {
    final take = gifts[i].quantity < left ? gifts[i].quantity : left;
    left -= take;
    if (take > 0) kept[i] = take;
  }
  return [
    for (int i = 0; i < gifts.length; i++)
      if (kept.containsKey(i)) gifts[i].copyWith(quantity: kept[i]),
  ];
}

String linkedGiftsSummary(List<LinkedGiftAllocation> gifts) =>
    gifts.map((g) => g.quantity > 1 ? '${g.quantity} × ${g.giftName}' : g.giftName).join(' + ');
