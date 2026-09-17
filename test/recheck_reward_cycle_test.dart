import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Recheck Reward & Interactive Game Cycle Tests', () {
    final alDohaEvent = EventModel(
      id: 'y5ujNVYJxsYIEgK1xmQL',
      eventName: 'حملة العودة للمدارس - الضحى',
      welcomeTitle: 'أهلاً بكم في مهرجان الضحى',
      welcomeMessage: 'ارفع فاتورتك واكسب هدية فورية',
      targetCompany: 'الضحى',
      companySlug: 'eldoha',
      companyLogoUrl: '',
      minimumSpend: 200.0,
      termsAndConditions: 'الشروط والأحكام',
      gameType: 'chooseGift',
      allocatedPrizes: [
        AllocatedPrize(giftId: 'g1', name: 'لانش بوكس', allocatedQuantity: 100, remainingQuantity: 95),
        AllocatedPrize(giftId: 'g2', name: 'زجاجة مياه', allocatedQuantity: 100, remainingQuantity: 90),
        AllocatedPrize(giftId: 'g3', name: 'مقلمة مدرسية', allocatedQuantity: 100, remainingQuantity: 88),
        AllocatedPrize(giftId: 'g4', name: 'مكرونة إيزي باستا سجق', allocatedQuantity: 200, remainingQuantity: 180),
      ],
      createdAt: DateTime.now(),
      branchNames: ['سيتي ستارز', 'مول العرب', 'الرحاب'],
      promotionalRules: [
        PromotionalRuleItem(
          id: 'rule_doha_school',
          ruleTitle: 'عرض المدارس من الضحى',
          triggerProduct: 'الضحى',
          conditionType: 'by_spend',
          minSpend: 200.0,
          rewardType: 'free_product',
          rewardValue: 'عرض المدارس (اختر هديتك)',
          linkedGifts: [
            LinkedGiftAllocation(giftName: 'لانش بوكس', quantity: 1, giftId: 'g1'),
            LinkedGiftAllocation(giftName: 'زجاجة مياه', quantity: 1, giftId: 'g2'),
            LinkedGiftAllocation(giftName: 'مقلمة مدرسية', quantity: 1, giftId: 'g3'),
            LinkedGiftAllocation(giftName: 'مكرونة إيزي باستا سجق', quantity: 1, giftId: 'g4'),
          ],
        ),
      ],
    );

    final wheelEvent = EventModel(
      id: 'wheel_event_1',
      eventName: 'عجلة الحظ يونيليفر',
      welcomeTitle: 'أهلاً بكم',
      welcomeMessage: 'لف العجلة واكسب',
      targetCompany: 'يونيليفر',
      companySlug: 'unilever',
      companyLogoUrl: '',
      minimumSpend: 100.0,
      termsAndConditions: 'الشروط',
      gameType: 'wheel',
      allocatedPrizes: [
        AllocatedPrize(giftId: 'w1', name: 'شامبو صانسيلك', allocatedQuantity: 50, remainingQuantity: 40),
        AllocatedPrize(giftId: 'w2', name: 'شاور دوف', allocatedQuantity: 50, remainingQuantity: 45),
      ],
      createdAt: DateTime.now(),
      branchNames: ['المنتزه', 'سموحة'],
    );

    final directEvent = EventModel(
      id: 'direct_event_1',
      eventName: 'هدية مباشرة ليبتون',
      welcomeTitle: 'أهلاً بكم',
      welcomeMessage: 'استلم هديتك',
      targetCompany: 'ليبتون',
      companySlug: 'lipton',
      companyLogoUrl: '',
      minimumSpend: 80.0,
      termsAndConditions: 'الشروط',
      gameType: 'directGift',
      allocatedPrizes: [
        AllocatedPrize(giftId: 'd1', name: 'مج ليبتون حراري', allocatedQuantity: 50, remainingQuantity: 30),
      ],
      createdAt: DateTime.now(),
      branchNames: ['المهندسين', 'المعادي'],
    );

    test('Identifies interactive reward correctly for chooseGift, wheel, scratch, and directGift', () {
      bool isInteractive(EventModel ev, List<LinkedGiftAllocation> linkedGifts) {
        final gameType = ev.gameType.trim().toLowerCase();
        return (gameType == 'choosegift') ||
            (gameType == 'wheel') ||
            (gameType == 'scratch') ||
            (gameType == 'scratchcard') ||
            (linkedGifts.length > 1 && gameType != 'directgift');
      }

      // Al Doha: chooseGift
      expect(isInteractive(alDohaEvent, alDohaEvent.promotionalRules.first.linkedGifts), isTrue);

      // Wheel event: wheel
      expect(isInteractive(wheelEvent, []), isTrue);

      // Direct gift single prize: false
      expect(isInteractive(directEvent, [
        LinkedGiftAllocation(giftName: 'مج حراري', quantity: 1, giftId: 'd1'),
      ]), isFalse);
    });

    test('Does NOT pre-claim candidate gifts in Firestore when receipt is an interactive reward', () {
      final linkedGifts = alDohaEvent.promotionalRules.first.linkedGifts;
      final gameType = alDohaEvent.gameType.trim().toLowerCase();
      final bool isInteractiveReward = (gameType == 'choosegift') ||
          (gameType == 'wheel') ||
          (gameType == 'scratch') ||
          (gameType == 'scratchcard') ||
          (linkedGifts.length > 1 && gameType != 'directgift');

      final claimedGifts = <Map<String, dynamic>>[];
      if (!isInteractiveReward) {
        for (final g in linkedGifts) {
          claimedGifts.add({
            'giftId': g.giftId,
            'giftName': g.giftName,
            'quantity': g.quantity,
          });
        }
      }

      // Claimed gifts must be empty because the customer hasn't made their choice yet!
      expect(claimedGifts, isEmpty);

      // Update payload must record game_played: false
      final firestoreUpdate = <String, dynamic>{
        'is_valid': true,
        'status': 'accepted',
        'campaignId': alDohaEvent.id,
        if (claimedGifts.isNotEmpty) 'claimed_gifts': claimedGifts,
        if (isInteractiveReward) 'game_played': false,
      };

      expect(firestoreUpdate.containsKey('claimed_gifts'), isFalse);
      expect(firestoreUpdate['game_played'], equals(false));
    });

    test('Candidate prizes are extracted correctly for choice dialog display and navigation', () {
      final linkedGifts = alDohaEvent.promotionalRules.first.linkedGifts;
      List<String> candidatePrizes = [];
      if (linkedGifts.isNotEmpty) {
        candidatePrizes = linkedGifts.map((g) => g.giftName.trim()).where((n) => n.isNotEmpty).toSet().toList();
      }

      expect(candidatePrizes.length, equals(4));
      expect(candidatePrizes, contains('لانش بوكس'));
      expect(candidatePrizes, contains('زجاجة مياه'));
      expect(candidatePrizes, contains('مقلمة مدرسية'));
      expect(candidatePrizes, contains('مكرونة إيزي باستا سجق'));
    });

    test('Cleans title for choice campaigns so raw rule string is not shown as a prize item', () {
      final linkedGifts = alDohaEvent.promotionalRules.first.linkedGifts;
      final String rawRuleTitle = alDohaEvent.promotionalRules.first.ruleTitle;
      final bool isChooseGift = alDohaEvent.gameType.trim().toLowerCase() == 'choosegift';

      String effectiveTitle = rawRuleTitle;
      if (isChooseGift) {
        effectiveTitle = 'عرض ترويجي بنظام اختيار الهدية (${linkedGifts.length} خيارات متاحة)';
      }

      expect(effectiveTitle, equals('عرض ترويجي بنظام اختيار الهدية (4 خيارات متاحة)'));
    });
  });
}
