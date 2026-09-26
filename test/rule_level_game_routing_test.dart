import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';

void main() {
  group('Rule-Level Game Routing Tests (تعدد الألعاب في الحملة الواحدة)', () {
    test('PromotionalRuleItem serialization preserves gameType', () {
      final rule = PromotionalRuleItem(
        id: 'rule_1',
        ruleTitle: 'الشريحة الأولى (150 ج.م): هدية فورية',
        triggerProduct: 'هاينز',
        conditionType: 'by_spend',
        minSpend: 150.0,
        rewardType: 'free_product',
        rewardValue: 'هاينز كاتشب دوي باك',
        gameType: 'directGift',
      );

      final map = rule.toMap();
      expect(map['gameType'], 'directGift');

      final deserialized = PromotionalRuleItem.fromMap(map);
      expect(deserialized.gameType, 'directGift');

      final copied = deserialized.copyWith(gameType: 'scratch');
      expect(copied.gameType, 'scratch');
    });

    test('CompositePromotionalBundle resolves rule-level gameType for Heinz Tier 1 (Direct Gift)', () {
      final tier1Rule = PromotionalRuleItem(
        id: 'rule_1',
        ruleTitle: 'الشريحة الأولى (بقيمة 150 جنية): هتكسب منتج من منتجات هاينز',
        triggerProduct: 'هاينز',
        conditionType: 'by_spend',
        minSpend: 150.0,
        maxSpend: 239.99,
        rewardType: 'free_product',
        rewardValue: 'هاينز كاتشب دوي باك',
        gameType: 'directGift',
        linkedGifts: [
          LinkedGiftAllocation(
            giftId: 'g_heinz_1',
            giftName: 'هاينز كاتشب دوي باك',
            quantity: 1,
            unitValue: 42.0,
            giftType: 'product',
          ),
        ],
      );

      final matchedResult = MatchedPromotionalRuleResult(
        rule: tier1Rule,
        multiplier: 1,
        totalRewardAmount: 0.0,
        multipliedLinkedGifts: tier1Rule.linkedGifts,
        formattedPrizeSummary: 'هاينز كاتشب دوي باك',
      );

      final bundle = CompositePromotionalBundle.fromMatchedRules([matchedResult]);

      expect(bundle.resolvedGameType, 'directGift');
      // Effective resolution with campaign fallback
      const fallbackGame = 'scratch';
      final effectiveGame = bundle.resolvedGameType ?? fallbackGame;
      expect(effectiveGame, 'directGift');
    });

    test('CompositePromotionalBundle resolves rule-level gameType for Heinz Tier 2 (Scratch Card)', () {
      final tier2Rule = PromotionalRuleItem(
        id: 'rule_2',
        ruleTitle: 'الشريحة الثانية (بقيمة 250 جنية): هتكسب هدية فورية من هاينز (خربش واكسب)',
        triggerProduct: 'هاينز',
        conditionType: 'by_spend',
        minSpend: 240.0,
        rewardType: 'game_spin',
        rewardValue: 'شنطة مدرسية / بوكس هدايا / مج حراري',
        gameType: 'scratch',
        linkedGifts: [
          LinkedGiftAllocation(
            giftId: 'g_heinz_mug',
            giftName: 'مج حراري',
            quantity: 1,
            unitValue: 120.0,
            giftType: 'product',
          ),
        ],
      );

      final matchedResult = MatchedPromotionalRuleResult(
        rule: tier2Rule,
        multiplier: 1,
        totalRewardAmount: 0.0,
        multipliedLinkedGifts: tier2Rule.linkedGifts,
        formattedPrizeSummary: 'مج حراري',
      );

      final bundle = CompositePromotionalBundle.fromMatchedRules([matchedResult]);

      expect(bundle.resolvedGameType, 'scratch');
      // Effective resolution with campaign fallback (even if campaign was set to wheel or directGift)
      const fallbackGame = 'directGift';
      final effectiveGame = bundle.resolvedGameType ?? fallbackGame;
      expect(effectiveGame, 'scratch');
    });

    test('Falls back to campaign gameType when rule does not specify gameType', () {
      final defaultRule = PromotionalRuleItem(
        id: 'rule_legacy',
        ruleTitle: 'شريحة عامة ترث لعبة الحملة',
        triggerProduct: 'هاينز',
        conditionType: 'by_spend',
        minSpend: 100.0,
        rewardType: 'free_product',
        rewardValue: 'هدية عامة',
        gameType: null, // No rule-level override
      );

      final matchedResult = MatchedPromotionalRuleResult(
        rule: defaultRule,
        multiplier: 1,
        totalRewardAmount: 0.0,
        multipliedLinkedGifts: [],
        formattedPrizeSummary: 'هدية عامة',
      );

      final bundle = CompositePromotionalBundle.fromMatchedRules([matchedResult]);

      expect(bundle.resolvedGameType, isNull);
      const campaignGameType = 'wheel';
      final effectiveGame = bundle.resolvedGameType ?? campaignGameType;
      expect(effectiveGame, 'wheel');
    });

    test('Simulating Heinz Live Receipts Scenario: Receipt 1 (210 EGP) vs Receipt 2 (462 EGP)', () {
      // 1. Setup Heinz Campaign Rules
      final heinzTier1 = PromotionalRuleItem(
        id: 'rule_1',
        ruleTitle: 'الشريحة الأولى (بقيمة 150 جنية): هتكسب منتج من منتجات هاينز',
        triggerProduct: 'هاينز',
        conditionType: 'by_spend',
        minSpend: 145.0,
        maxSpend: 239.99,
        rewardType: 'free_product',
        rewardValue: 'هاينز كاتشب دوي باك',
        gameType: 'directGift', // Direct gift claim
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'g1', giftName: 'هاينز كاتشب', quantity: 1, unitValue: 42.0),
        ],
      );

      final heinzTier2 = PromotionalRuleItem(
        id: 'rule_2',
        ruleTitle: 'الشريحة الثانية (بقيمة 250 جنية): هتكسب هدية قيمة (خربش واكسب)',
        triggerProduct: 'هاينز',
        conditionType: 'by_spend',
        minSpend: 240.0,
        rewardType: 'game_spin',
        rewardValue: 'مج حراري / زجاجة مياه',
        gameType: 'scratch', // Scratch & win
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'g2', giftName: 'مج حراري', quantity: 1, unitValue: 120.0),
        ],
      );

      // Receipt 1: 210 EGP (Bought 5 Heinz ketchup @ 42 = 210 EGP) -> Qualifies for Tier 1
      final receipt1Result = MatchedPromotionalRuleResult(
        rule: heinzTier1,
        multiplier: 1,
        totalRewardAmount: 0.0,
        multipliedLinkedGifts: heinzTier1.linkedGifts,
        formattedPrizeSummary: 'هاينز كاتشب',
      );
      final bundleReceipt1 = CompositePromotionalBundle.fromMatchedRules([receipt1Result]);
      expect(bundleReceipt1.resolvedGameType, equals('directGift'),
          reason: 'بونة هاينز الأولى (210 ج.م) يجب أن توجه تلقائياً إلى الهدية الفورية المباشرة');

      // Receipt 2: 462 EGP (Bought 11 Heinz ketchup @ 42 = 462 EGP) -> Qualifies for Tier 2
      final receipt2Result = MatchedPromotionalRuleResult(
        rule: heinzTier2,
        multiplier: 1,
        totalRewardAmount: 0.0,
        multipliedLinkedGifts: heinzTier2.linkedGifts,
        formattedPrizeSummary: 'مج حراري',
      );
      final bundleReceipt2 = CompositePromotionalBundle.fromMatchedRules([receipt2Result]);
      expect(bundleReceipt2.resolvedGameType, equals('scratch'),
          reason: 'بونة هاينز الثانية (462 ج.م) يجب أن توجه تلقائياً إلى كارت خربش واكسب');
    });

    test('EventModel.availablePrizeNames deduplicates prizes across multi-branch allocations', () {
      final event = EventModel(
        id: 'cadbury_event',
        eventName: 'ماراثون جوائز كادبوري',
        targetCompany: 'كادبوري',
        minimumSpend: 250.0,
        retailChainId: 'fathalla',
        retailChainName: 'أسواق فتح الله',
        allocatedPrizes: [
          // Global allocations
          AllocatedPrize(giftId: 'g1', name: 'فواتشر 100 جنيه', allocatedQuantity: 100, remainingQuantity: 1000, giftType: 'voucher', unitValue: 100),
          AllocatedPrize(giftId: 'g2', name: 'لانش بوكس كادبوري', allocatedQuantity: 100, remainingQuantity: 1000),
          // Branch 1 allocations (same gift names)
          AllocatedPrize(giftId: 'g1', name: 'فواتشر 100 جنيه', branchName: 'فرع سموحة', allocatedQuantity: 100, remainingQuantity: 1000, giftType: 'voucher', unitValue: 100),
          AllocatedPrize(giftId: 'g2', name: 'لانش بوكس كادبوري', branchName: 'فرع سموحة', allocatedQuantity: 100, remainingQuantity: 1000),
          // Branch 2 allocations (same gift names)
          AllocatedPrize(giftId: 'g1', name: 'فواتشر 100 جنيه', branchName: 'فرع المحلة', allocatedQuantity: 100, remainingQuantity: 1000, giftType: 'voucher', unitValue: 100),
          AllocatedPrize(giftId: 'g2', name: 'لانش بوكس كادبوري', branchName: 'فرع المحلة', allocatedQuantity: 100, remainingQuantity: 1000),
          // Out of stock item (should be excluded)
          AllocatedPrize(giftId: 'g3', name: 'هدية منتهية', allocatedQuantity: 10, remainingQuantity: 0),
        ],
      );

      final prizeNames = event.availablePrizeNames;
      // Must contain only the 2 distinct available prizes, without any duplicates
      expect(prizeNames.length, equals(2));
      expect(prizeNames, contains('فواتشر 100 جنيه'));
      expect(prizeNames, contains('لانش بوكس كادبوري'));
      expect(prizeNames, isNot(contains('هدية منتهية')));
    });
  });
}

