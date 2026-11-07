import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/games/presentation/direct_gift_claim_screen.dart';

PromotionalRuleItem _oreoRule({String id = 'r200', double min = 200, double? max = 349.99, List<RewardOption>? options}) {
  return PromotionalRuleItem(
    id: id,
    ruleTitle: 'أوريو $min',
    triggerProduct: 'أوريو',
    conditionType: 'by_spend',
    minSpend: min,
    maxSpend: max,
    rewardType: 'voucher',
    rewardValue: 'قسيمة 50 أو إزازة',
    rewardAmount: 50,
    rewardOptions: options ??
        const [
          RewardOption(id: 'o1', kind: 'voucher', voucherAmount: 50, giftType: 'voucher', unitValue: 50),
          RewardOption(id: 'o2', kind: 'gift', giftId: 'g_bottle', giftName: 'إزازة أوريو', giftType: 'product'),
        ],
  );
}

void main() {
  group('RewardOption model', () {
    test('json roundtrip keeps options', () {
      final rule = _oreoRule();
      final back = PromotionalRuleItem.fromMap(rule.toMap());
      expect(back.rewardOptions.length, 2);
      expect(back.hasRewardChoice, isTrue);
      expect(back.rewardOptions[0].kind, 'voucher');
      expect(back.rewardOptions[0].voucherAmount, 50);
      expect(back.rewardOptions[0].displayLabel, 'قسيمة شراء 50 جنيه');
      expect(back.rewardOptions[1].kind, 'gift');
      expect(back.rewardOptions[1].giftId, 'g_bottle');
      expect(back.rewardOptions[1].displayLabel, 'إزازة أوريو');
    });

    test('legacy rule without options parses to empty and writes no key', () {
      final legacy = PromotionalRuleItem.fromMap({
        'id': 'legacy',
        'ruleTitle': 'قديمة',
        'triggerProduct': 'x',
        'rewardType': 'voucher',
        'rewardValue': 'فواتشر 50',
        'rewardAmount': 50,
        'linkedGiftId': 'g50',
        'linkedGiftName': 'فواتشر 50',
      });
      expect(legacy.rewardOptions, isEmpty);
      expect(legacy.hasRewardChoice, isFalse);
      expect(legacy.toMap().containsKey('rewardOptions'), isFalse);
      expect(legacy.linkedGifts.single.giftId, 'g50');
    });

    test('single option is not a choice', () {
      final r = _oreoRule(options: const [RewardOption(id: 'o1', kind: 'voucher', voucherAmount: 50)]);
      expect(r.hasRewardChoice, isFalse);
    });

    test('toAllocation multiplies and maps types', () {
      final v = const RewardOption(id: 'o1', kind: 'voucher', voucherAmount: 100).toAllocation(multiplier: 2);
      expect(v.quantity, 2);
      expect(v.isVoucher, isTrue);
      expect(v.totalMonetaryValue, 200);
      final g = const RewardOption(id: 'o2', kind: 'gift', giftId: 'bag', giftName: 'شنطة').toAllocation();
      expect(g.giftId, 'bag');
      expect(g.isVoucher, isFalse);
    });
  });

  group('CompositePromotionalBundle with reward options', () {
    test('legacy bundles unchanged (no choice groups)', () {
      final legacy = PromotionalRuleItem(
        id: 'l', ruleTitle: 't', triggerProduct: 'x', rewardValue: 'كلير', rewardType: 'free_product',
        linkedGifts: [LinkedGiftAllocation(giftId: 'g1', giftName: 'كلير')],
      );
      final b = CompositePromotionalBundle.fromMatchedRules([
        MatchedPromotionalRuleResult(rule: legacy, formattedPrizeSummary: 'كلير', multipliedLinkedGifts: legacy.linkedGifts),
      ]);
      expect(b.requiresRewardChoice, isFalse);
      expect(b.combinedLinkedGifts.single.giftId, 'g1');
      expect(b.candidateGiftNames, ['كلير']);
    });

    test('choice rule exposes a group and keeps other gifts as base', () {
      final legacy = PromotionalRuleItem(
        id: 'l', ruleTitle: 't', triggerProduct: 'x', rewardValue: 'كلير',
        linkedGifts: [LinkedGiftAllocation(giftId: 'g1', giftName: 'كلير')],
      );
      final b = CompositePromotionalBundle.fromMatchedRules([
        MatchedPromotionalRuleResult(rule: _oreoRule(), multiplier: 1, formattedPrizeSummary: 'x'),
        MatchedPromotionalRuleResult(rule: legacy, formattedPrizeSummary: 'كلير', multipliedLinkedGifts: legacy.linkedGifts),
      ]);
      expect(b.requiresRewardChoice, isTrue);
      expect(b.rewardChoiceGroups.single.options.length, 2);
      expect(b.baseLinkedGifts.single.giftId, 'g1');
      expect(b.candidateGiftNames, containsAll(['كلير', 'قسيمة شراء 50 جنيه', 'إزازة أوريو']));
    });
  });

  group('DirectGiftClaimScreen reward choice', () {
    testWidgets('shows options, blocks handover until one is picked', (tester) async {
      final group = RewardChoiceGroup.fromRule(_oreoRule())!;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: DirectGiftClaimScreen(
            prizeName: 'قسيمة 50 أو إزازة',
            isDemo: true,
            rewardChoiceGroups: [group],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('اختار مكافأتك (اختيار واحد)'), findsOneWidget);
      expect(find.byKey(const ValueKey('reward_option_0_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('reward_option_0_1')), findsOneWidget);
      expect(find.text('لازم العميل يختار مكافأة قبل التسليم'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('reward_option_0_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reward_option_0_1')));
      await tester.pumpAndSettle();
      final chip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('reward_option_0_1')));
      expect(chip.selected, isTrue);
      expect(find.text('لازم العميل يختار مكافأة قبل التسليم'), findsNothing);
      expect(find.text('إزازة أوريو'), findsWidgets);
    });

    testWidgets('legacy screen has no choice card', (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: DirectGiftClaimScreen(prizeName: 'زمزمية', isDemo: true)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('اختار مكافأتك (اختيار واحد)'), findsNothing);
    });
  });
}
