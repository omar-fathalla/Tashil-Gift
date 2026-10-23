// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('El-Rashidi El-Mizan (حملة الرشيدي الميزان) - Zero Stock Exclusion & Wheel Slices Test', () {
    late EventModel elRashidiCampaign;

    setUp(() {
      elRashidiCampaign = EventModel(
        id: 'q1r45sW0bcYNJ2RU2aEI',
        eventName: 'عروض وحملات  الرشيدي الميزان',
        targetCompany: 'الرشيدى الميزان',
        companySlug: '83',
        minimumSpend: 150.0,
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 11, 29),
        gameType: 'wheel',
        branchNames: [
          'فرع عجمي ستار (الإسكندرية)',
          'فرع هانوفيل (الإسكندرية)',
          'فرع جاردينيا (الإسكندرية)',
          'فرع سموحة (الإسكندرية)',
          'جناكليس (الإسكندرية)',
          'المنتزه (الإسكندرية)',
          'فرع الزقازيق',
          'عمارات العبور - صلاح سالم (القاهرة)',
        ],
        promotionalRules: [
          // Rule 1: 150 EGP spend including Halawa -> Wheel with (سكينة + عسل اسود 320جم + مربى تين 340جم + glass cup)
          PromotionalRuleItem(
            id: 'rule_1',
            ruleTitle: 'اشتري ب150 جنيه من منتجات رشيدي الميزان بشرط وجود منتج حلاوه بشركه رشيد الميزان',
            minSpend: 150.0,
            conditionType: 'by_spend',
            triggerProduct: 'منتجات الميزان و حلاوة و الرشيدى و الرشيدي و كريميتا',
            rewardType: 'free_product',
            rewardValue: 'اشتري ب150 جنيه من منتجات رشيدي الميزان بشرط وجود منتج حلاوه بشركه رشيد الميزان',
            gameType: 'wheel',
            linkedGifts: [
              LinkedGiftAllocation(giftId: 'g_knife', giftName: 'سكينة', quantity: 1),
              LinkedGiftAllocation(giftId: 'g_honey', giftName: 'عسل اسود 320جم', quantity: 1),
              LinkedGiftAllocation(giftId: 'g_jam', giftName: 'مربى  340جم', quantity: 1),
              LinkedGiftAllocation(giftId: 'g_cup', giftName: 'glass cup', quantity: 1),
            ],
          ),
          // Rule 2: 250 EGP spend including Halawa -> Wheel with (plate + lunch box)
          PromotionalRuleItem(
            id: 'rule_2',
            ruleTitle: 'اشتري ب 250 جنيه من منتجات رشيدي الميزان بشرط وجود حلاوه رشيدي الميزان',
            minSpend: 250.0,
            conditionType: 'by_spend',
            triggerProduct: 'منتجات الميزان و حلاوة و الرشيدى و الرشيدي و كريميتا',
            rewardType: 'free_product',
            rewardValue: 'اشتري ب 250 جنيه من منتجات رشيدي الميزان بشرط وجود حلاوه رشيدي الميزان',
            gameType: 'wheel',
            linkedGifts: [
              LinkedGiftAllocation(giftId: 'g_plate', giftName: 'plate', quantity: 1),
              LinkedGiftAllocation(giftId: 'g_lunchbox', giftName: 'lunch box', quantity: 1),
            ],
          ),
        ],
        allocatedPrizes: [
          // === فرع هانوفيل (الإسكندرية) ===
          // سكينة has 0 remaining stock!
          AllocatedPrize(
            giftId: 'g_knife_hanoville',
            name: 'سكينة',
            allocatedQuantity: 10,
            remainingQuantity: 0, // OUT OF STOCK 🔴
            branchName: 'فرع هانوفيل (الإسكندرية)',
          ),
          AllocatedPrize(
            giftId: 'g_honey_hanoville',
            name: 'عسل اسود 320جم',
            allocatedQuantity: 10,
            remainingQuantity: 10, // IN STOCK 🟢
            branchName: 'فرع هانوفيل (الإسكندرية)',
          ),
          AllocatedPrize(
            giftId: 'g_cup_hanoville',
            name: 'glass cup',
            allocatedQuantity: 30,
            remainingQuantity: 30, // IN STOCK 🟢
            branchName: 'فرع هانوفيل (الإسكندرية)',
          ),
          AllocatedPrize(
            giftId: 'g_jam_hanoville',
            name: 'مربى  340جم',
            allocatedQuantity: 24,
            remainingQuantity: 24, // IN STOCK 🟢
            branchName: 'فرع هانوفيل (الإسكندرية)',
          ),
          AllocatedPrize(
            giftId: 'g_plate_hanoville',
            name: 'plate',
            allocatedQuantity: 48,
            remainingQuantity: 38, // IN STOCK 🟢
            branchName: 'فرع هانوفيل (الإسكندرية)',
          ),
          AllocatedPrize(
            giftId: 'g_lunchbox_hanoville',
            name: 'lunch box',
            allocatedQuantity: 10,
            remainingQuantity: 6, // IN STOCK 🟢
            branchName: 'فرع هانوفيل (الإسكندرية)',
          ),

          // === فرع عجمي ستار (الإسكندرية) ===
          // plate and lunch box have 0 remaining stock!
          AllocatedPrize(
            giftId: 'g_knife_agamy',
            name: 'سكينة',
            allocatedQuantity: 23,
            remainingQuantity: 13,
            branchName: 'فرع عجمي ستار (الإسكندرية)',
          ),
          AllocatedPrize(
            giftId: 'g_honey_agamy',
            name: 'عسل اسود 320جم',
            allocatedQuantity: 10,
            remainingQuantity: 1,
            branchName: 'فرع عجمي ستار (الإسكندرية)',
          ),
          AllocatedPrize(
            giftId: 'g_plate_agamy',
            name: 'plate',
            allocatedQuantity: 48,
            remainingQuantity: 0, // OUT OF STOCK 🔴
            branchName: 'فرع عجمي ستار (الإسكندرية)',
          ),
          AllocatedPrize(
            giftId: 'g_lunchbox_agamy',
            name: 'lunch box',
            allocatedQuantity: 10,
            remainingQuantity: 0, // OUT OF STOCK 🔴
            branchName: 'فرع عجمي ستار (الإسكندرية)',
          ),
          AllocatedPrize(
            giftId: 'g_cup_agamy',
            name: 'glass cup',
            allocatedQuantity: 30,
            remainingQuantity: 22,
            branchName: 'فرع عجمي ستار (الإسكندرية)',
          ),
          AllocatedPrize(
            giftId: 'g_jam_agamy',
            name: 'مربى  340جم',
            allocatedQuantity: 24,
            remainingQuantity: 18,
            branchName: 'فرع عجمي ستار (الإسكندرية)',
          ),

          // === المنتزه (الإسكندرية) ===
          // سكينة has 0 remaining stock!
          AllocatedPrize(
            giftId: 'g_knife_montazah',
            name: 'سكينة',
            allocatedQuantity: 10,
            remainingQuantity: 0, // OUT OF STOCK 🔴
            branchName: 'المنتزه (الإسكندرية)',
          ),
          AllocatedPrize(
            giftId: 'g_honey_montazah',
            name: 'عسل اسود 320جم',
            allocatedQuantity: 10,
            remainingQuantity: 10,
            branchName: 'المنتزه (الإسكندرية)',
          ),
        ],
      );
    });

    test('Test Real Hanoville Branch Invoice: "سكينة" is strictly excluded and Fortune Wheel renders 3 in-stock prizes', () {
      // 1. Stored receipt lzoup6pHJhS17WlpSrFX:
      // Total 198 EGP (> 150 EGP), contains Halawa products in Hanoville branch
      final receiptProducts = [
        ExtractedProductItem(
          name: 'الرشيدى الميزان حلاوة سادة 900جم',
          price: 135.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'الرشيدى الميزان طحينة 450جم',
          price: 63.0,
          quantity: 1,
          isTargetCompany: true,
        ),
      ];

      final totalSpend = receiptProducts.fold<double>(0.0, (acc, item) => acc + (item.price * item.quantity));
      expect(totalSpend, 198.0);

      // 2. Promotional Rule Matching
      final matchedRule = PromotionalRuleMatcher.match(
        promotionalRules: elRashidiCampaign.promotionalRules,
        extractedProducts: receiptProducts,
        matchedRuleId: 'rule_1',
      );

      expect(matchedRule, isNotNull);
      expect(matchedRule!.id, 'rule_1');
      expect(matchedRule.gameType, 'wheel');

      // Rule 1 candidate gifts configured in campaign:
      final rawCandidates = matchedRule.linkedGifts.map((g) => g.giftName).toList();
      expect(rawCandidates, ['سكينة', 'عسل اسود 320جم', 'مربى  340جم', 'glass cup']);
      expect(rawCandidates.contains('سكينة'), isTrue);

      // 3. Branch-scoped Inventory Filter for Hanoville Branch (AIR-85)
      const branchName = 'فرع هانوفيل (الإسكندرية)';
      final branchFilteredPrizes = elRashidiCampaign.filterGiftsByBranchStock(
        candidateGifts: rawCandidates,
        branch: branchName,
      );

      // ASSERTION: 'سكينة' MUST be completely excluded because remainingQuantity == 0 in Hanoville
      expect(branchFilteredPrizes.contains('سكينة'), isFalse,
          reason: 'Knife has 0 remaining stock in Hanoville and must NEVER be placed on the wheel');

      // ASSERTION: The remaining 3 items with positive stock are preserved
      expect(branchFilteredPrizes.length, 3);
      expect(branchFilteredPrizes, containsAll(['عسل اسود 320جم', 'glass cup', 'مربى  340جم']));

      print('✅ SUCCESS - Hanoville Branch Fortune Wheel Slices:');
      print('   Total candidates before stock check: ${rawCandidates.length} $rawCandidates');
      print('   Excluded zero-stock prize: "سكينة" (رصيد: 0)');
      print('   Final Fortune Wheel slices: ${branchFilteredPrizes.length} $branchFilteredPrizes');
    });

    test('Test Agamy Star Branch: "plate" and "lunch box" are excluded when Rule 2 is triggered', () {
      final rawCandidates = ['plate', 'lunch box'];

      const branchName = 'فرع عجمي ستار (الإسكندرية)';
      final branchFilteredPrizes = elRashidiCampaign.filterGiftsByBranchStock(
        candidateGifts: rawCandidates,
        branch: branchName,
      );

      // In Agamy Star, both plate and lunch box have remainingQuantity == 0.
      expect(branchFilteredPrizes.contains('plate'), isFalse);
      expect(branchFilteredPrizes.contains('lunch box'), isFalse);

      print('✅ SUCCESS - Agamy Star Branch: Zero-stock Rule 2 prizes ("plate", "lunch box") successfully excluded!');
      print('   Fallback available prizes for branch: $branchFilteredPrizes');
    });

    test('Test Montazah Branch: "سكينة" is excluded while "عسل اسود 320جم" is available', () {
      const branchName = 'المنتزه (الإسكندرية)';
      final rawCandidates = ['سكينة', 'عسل اسود 320جم'];

      final filtered = elRashidiCampaign.filterGiftsByBranchStock(
        candidateGifts: rawCandidates,
        branch: branchName,
      );

      expect(filtered.contains('سكينة'), isFalse);
      expect(filtered.contains('عسل اسود 320جم'), isTrue);
      expect(filtered, ['عسل اسود 320جم']);

      print('✅ SUCCESS - Montazah Branch: "سكينة" (رصيد: 0) excluded, "عسل اسود 320جم" preserved!');
    });
  });
}
