import 'package:al_mraay/core/update/app_update_checker.dart';
import 'package:al_mraay/core/utils/receipt_unit_clamp.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Panda campaign Al5D91dX3qroedYdIGri: cap 3, one rule, 1 piece per offer.
  final panda = <String, dynamic>{
    'allowMultipleChances': true,
    'maxChancesPerReceipt': 3,
    'promotionalRules': [
      {
        'linkedGifts': [
          {'giftId': 'GPBO7WkkjOr6iuWIbKqQ', 'giftName': 'العب مع باندا', 'quantity': '1'},
        ],
      },
    ],
  };

  test('Panda: 7 x العب مع باندا with cap 3 shows and claims 3', () {
    expect(receiptPieceLimitFromEvent(panda), 3);
    final gifts = [LinkedGiftAllocation(giftId: 'GPBO7WkkjOr6iuWIbKqQ', giftName: 'العب مع باندا', quantity: 7)];
    final out = clampLinkedGiftsToPieces(gifts, receiptPieceLimitFromEvent(panda));
    expect(totalPieces(out), 3);
    expect(linkedGiftsSummary(out), '3 × العب مع باندا');
  });

  test('highest value first across gifts', () {
    final gifts = [
      LinkedGiftAllocation(giftId: 'g50', giftName: 'فواتشر 50', quantity: 2, unitValue: 50, giftType: 'voucher'),
      LinkedGiftAllocation(giftId: 'g100', giftName: 'فواتشر 100', quantity: 2, unitValue: 100, giftType: 'voucher'),
    ];
    final out = clampLinkedGiftsToPieces(gifts, 3);
    expect(out.map((g) => '${g.giftId}:${g.quantity}').toList(), ['g50:1', 'g100:2']);
  });

  test('multi-piece offer (6 bags) keeps the offer whole; switch OFF => no client cap', () {
    final bags = <String, dynamic>{
      'allowMultipleChances': true,
      'maxChancesPerReceipt': 3,
      'promotionalRules': [
        {'linkedGifts': [{'giftId': 'b', 'quantity': 6}]},
      ],
    };
    expect(receiptPieceLimitFromEvent(bags), 18);
    expect(receiptPieceLimitFromEvent({...panda, 'allowMultipleChances': false}), isNull);
    final g = [LinkedGiftAllocation(giftId: 'b', giftName: 'b', quantity: 12)];
    expect(clampLinkedGiftsToPieces(g, 18), same(g));
  });

  test('forced reload: only when newer, and not again for same version within cooldown', () {
    const running = BuildId(2, 0, 161, 222);
    const remote = BuildId(2, 0, 164, 225);
    final now = DateTime(2026, 10, 31, 21);
    expect(shouldForceReload(remote: remote, running: running, now: now), isTrue);
    expect(shouldForceReload(remote: running, running: running, now: now), isFalse);
    final recent = '2.0.164+225|${now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch}';
    expect(shouldForceReload(remote: remote, running: running, lastAttempt: recent, now: now), isFalse);
    final old = '2.0.164+225|${now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch}';
    expect(shouldForceReload(remote: remote, running: running, lastAttempt: old, now: now), isTrue);
    final older = '2.0.163+224|${now.millisecondsSinceEpoch}';
    expect(shouldForceReload(remote: remote, running: running, lastAttempt: older, now: now), isTrue);
  });
}
