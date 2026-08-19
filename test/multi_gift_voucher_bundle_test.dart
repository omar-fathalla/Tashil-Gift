import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';
import 'package:al_mraay/core/services/campaign_ai_assistant_service.dart';
import 'package:al_mraay/features/games/presentation/winner_celebration_dialog.dart';
import 'package:al_mraay/features/games/presentation/direct_gift_claim_screen.dart';

void main() {
  group('Multi-Gift & Voucher Bundle Architecture Tests', () {
    test('LinkedGiftAllocation correctly calculates monetary value and serializes to/from map', () {
      final alloc = LinkedGiftAllocation(
        giftId: 'vouch-50',
        giftName: 'فواتشر 50 جنيه',
        quantity: 2,
        unitValue: 50.0,
        giftType: 'voucher',
      );

      expect(alloc.isVoucher, isTrue);
      expect(alloc.totalMonetaryValue, 100.0);

      final map = alloc.toMap();
      expect(map['giftId'], 'vouch-50');
      expect(map['quantity'], 2);
      expect(map['unitValue'], 50.0);
      expect(map['giftType'], 'voucher');

      final deserialized = LinkedGiftAllocation.fromMap(map);
      expect(deserialized.giftId, 'vouch-50');
      expect(deserialized.giftName, 'فواتشر 50 جنيه');
      expect(deserialized.quantity, 2);
      expect(deserialized.unitValue, 50.0);
      expect(deserialized.totalMonetaryValue, 100.0);
    });

    test('PromotionalRuleItem handles multiple linked gifts and calculates summary and total value', () {
      final rule = PromotionalRuleItem(
        id: 'rule-125',
        ruleTitle: 'عرض اسبراي ريكسونا أو أكس (قطعتين)',
        triggerProduct: 'ريكسونا أو أكس',
        minQuantity: 2,
        rewardType: 'voucher',
        rewardValue: 'فواتشر بقيمة 125 جنيه',
        rewardAmount: 125.0,
        linkedGifts: [
          LinkedGiftAllocation(
            giftId: 'vouch-50',
            giftName: 'فواتشر 50 جنيه',
            quantity: 2,
            unitValue: 50.0,
            giftType: 'voucher',
          ),
          LinkedGiftAllocation(
            giftId: 'vouch-25',
            giftName: 'فواتشر 25 جنيه',
            quantity: 1,
            unitValue: 25.0,
            giftType: 'voucher',
          ),
        ],
      );

      expect(rule.hasLinkedGifts, isTrue);
      expect(rule.totalVoucherValue, 125.0);
      expect(rule.linkedGiftsSummary, '2 × فواتشر 50 جنيه + فواتشر 25 جنيه');

      final map = rule.toMap();
      expect(map['linkedGifts'], isA<List>());
      expect((map['linkedGifts'] as List).length, 2);

      final fromMap = PromotionalRuleItem.fromMap(map);
      expect(fromMap.linkedGifts.length, 2);
      expect(fromMap.totalVoucherValue, 125.0);
      expect(fromMap.linkedGiftsSummary, '2 × فواتشر 50 جنيه + فواتشر 25 جنيه');
    });

    test('PromotionalRuleItem maintains backward compatibility with legacy linkedGiftId', () {
      final legacyMap = {
        'id': 'legacy-rule',
        'ruleTitle': 'عرض قديم',
        'triggerProduct': 'شامبو',
        'minQuantity': 1,
        'rewardType': 'voucher',
        'rewardValue': 'فواتشر 50 جنيه',
        'rewardAmount': 50.0,
        'linkedGiftId': 'gift-123',
        'linkedGiftName': 'كارت 50 ج',
      };

      final rule = PromotionalRuleItem.fromMap(legacyMap);
      expect(rule.hasLinkedGifts, isTrue);
      expect(rule.linkedGifts.length, 1);
      expect(rule.linkedGifts.first.giftId, 'gift-123');
      expect(rule.linkedGifts.first.giftName, 'كارت 50 ج');
      expect(rule.linkedGifts.first.unitValue, 50.0);
      expect(rule.totalVoucherValue, 50.0);
    });

    test('CampaignAiAssistantService.decomposeVoucherAmount correctly breaks down 125 EGP into 2x50 + 1x25', () {
      final availableGifts = [
        CompanyGiftModel(
          id: 'v-50',
          companySlug: 'unilever',
          giftName: 'فواتشر 50 جنيه',
          totalQuantity: 100,
          availableQuantity: 100,
          giftType: 'voucher',
          unitValue: 50.0,
        ),
        CompanyGiftModel(
          id: 'v-25',
          companySlug: 'unilever',
          giftName: 'فواتشر 25 جنيه',
          totalQuantity: 100,
          availableQuantity: 100,
          giftType: 'voucher',
          unitValue: 25.0,
        ),
        CompanyGiftModel(
          id: 'v-100',
          companySlug: 'unilever',
          giftName: 'فواتشر 100 جنيه',
          totalQuantity: 100,
          availableQuantity: 100,
          giftType: 'voucher',
          unitValue: 100.0,
        ),
        CompanyGiftModel(
          id: 'prod-1',
          companySlug: 'unilever',
          giftName: 'تريزيمي 250 مل',
          totalQuantity: 50,
          availableQuantity: 50,
          giftType: 'product',
        ),
      ];

      // Test 125 EGP with [100, 50, 25] -> 1x 100 + 1x 25
      final breakdown125With100 = CampaignAiAssistantService.decomposeVoucherAmount(125.0, availableGifts);
      expect(breakdown125With100.length, 2);
      expect(breakdown125With100[0].unitValue, 100.0);
      expect(breakdown125With100[0].quantity, 1);
      expect(breakdown125With100[1].unitValue, 25.0);
      expect(breakdown125With100[1].quantity, 1);

      // Test 125 EGP with only [50, 25] (user scenario!)
      final giftsOnly50And25 = availableGifts.where((g) => g.id != 'v-100').toList();
      final breakdown125 = CampaignAiAssistantService.decomposeVoucherAmount(125.0, giftsOnly50And25);
      expect(breakdown125.length, 2);
      expect(breakdown125[0].giftId, 'v-50');
      expect(breakdown125[0].quantity, 2);
      expect(breakdown125[1].giftId, 'v-25');
      expect(breakdown125[1].quantity, 1);

      final totalDecomposed = breakdown125.fold(0.0, (sum, g) => sum + g.totalMonetaryValue);
      expect(totalDecomposed, 125.0);
    });

    test('CampaignAiAssistantService.decomposeVoucherAmount handles exact matches directly', () {
      final availableGifts = [
        CompanyGiftModel(
          id: 'v-50',
          companySlug: 'unilever',
          giftName: 'فواتشر 50 جنيه',
          totalQuantity: 100,
          availableQuantity: 100,
          giftType: 'voucher',
          unitValue: 50.0,
        ),
      ];

      final result = CampaignAiAssistantService.decomposeVoucherAmount(50.0, availableGifts);
      expect(result.length, 1);
      expect(result.first.giftId, 'v-50');
      expect(result.first.quantity, 1);
      expect(result.first.unitValue, 50.0);
    });
  });

  group('Winner Celebration & Direct Gift UI Rendering Tests', () {
    testWidgets('WinnerCelebrationDialog renders clean prize name and multi-voucher breakdown chips', (tester) async {
      final linkedGifts = [
        LinkedGiftAllocation(
          giftId: 'v-50',
          giftName: 'فواتشر 50 جنيه',
          quantity: 2,
          unitValue: 50.0,
          giftType: 'voucher',
        ),
        LinkedGiftAllocation(
          giftId: 'v-25',
          giftName: 'فواتشر 25 جنيه',
          quantity: 1,
          unitValue: 25.0,
          giftType: 'voucher',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WinnerCelebrationDialog(
                prizeName: 'فواتشر بقيمة 125 جنيه',
                unitValue: 125.0,
                isVoucher: true,
                linkedGifts: linkedGifts,
                onNextCustomer: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify the real prize name appears
      expect(find.text('فواتشر بقيمة 125 جنيه'), findsOneWidget);
      // Verify prominent monetary value badge
      expect(find.text('بقيمة 125 ج.م'), findsOneWidget);
      // Verify voucher breakdown chips
      expect(find.text('2 × فواتشر 50 جنيه'), findsOneWidget);
      expect(find.text('1 × فواتشر 25 جنيه'), findsOneWidget);
      // Verify fallback text is NOT present
      expect(find.text('هدية ترويجية مميزة'), findsNothing);
    });

    testWidgets('DirectGiftClaimScreen renders promotional prize with breakdown chips and amount', (tester) async {
      final linkedGifts = [
        LinkedGiftAllocation(
          giftId: 'v-50',
          giftName: 'فواتشر 50 جنيه',
          quantity: 2,
          unitValue: 50.0,
          giftType: 'voucher',
        ),
        LinkedGiftAllocation(
          giftId: 'v-25',
          giftName: 'فواتشر 25 جنيه',
          quantity: 1,
          unitValue: 25.0,
          giftType: 'voucher',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DirectGiftClaimScreen(
              prizeName: 'فواتشر بقيمة 125 جنيه',
              quantity: 1,
              isDemo: true,
              unitValue: 125.0,
              isVoucher: true,
              linkedGifts: linkedGifts,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check prize name
      expect(find.text('فواتشر بقيمة 125 جنيه'), findsOneWidget);
      // Check monetary badge
      expect(find.text('بقيمة 125 ج.م'), findsOneWidget);
      // Check breakdown chips
      expect(find.text('2 × فواتشر 50 جنيه'), findsOneWidget);
      expect(find.text('1 × فواتشر 25 جنيه'), findsOneWidget);
      // Verify fallback text is NOT present
      expect(find.text('هدية ترويجية مميزة'), findsNothing);
    });
  });
}
