import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:al_mraay/features/admin/domain/company_gift_model.dart";
import "package:al_mraay/features/company_portal/presentation/company_prizes_stock_report_screen.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("Company Manager Gift Actions & 2-Way Synchronization Tests", () {
    testWidgets("CompanyPrizesStockReportScreen toolbar includes Add New Gift button", (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CompanyPrizesStockReportScreen(
                lockedCompanySlug: "unilever",
                lockedCompanyName: "يونيليفر مصر",
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Find the Add Gift button in toolbar
      final addGiftBtn = find.text("إضافة هدية أو فواتشر جديد");
      expect(addGiftBtn, findsOneWidget);
    });

    test("Manager Stock Actions maintain full serialization and audit consistency", () {
      final initialBatch = GiftSupplyBatch(
        id: "batch_01",
        batchNumber: 1,
        quantity: 100,
        supplyDate: DateTime(2026, 8, 20),
        referenceNumber: "PO-MANAGER-01",
        notes: "Initial stock added by manager",
        addedBy: "مدير الشركة",
      );

      final gift = CompanyGiftModel(
        id: "gift_mgr_01",
        companySlug: "unilever",
        companyName: "يونيليفر مصر",
        giftName: "فواتشر 100 جنيه كارفور",
        totalQuantity: 100,
        availableQuantity: 100,
        giftType: "voucher",
        unitValue: 100.0,
        batches: [initialBatch],
      );

      expect(gift.isVoucher, isTrue);
      expect(gift.totalMonetaryValue, equals(10000.0));
      expect(gift.availableMonetaryValue, equals(10000.0));
      expect(gift.batchCount, equals(1));

      // Manager supplies second batch (+50 cards)
      final batch2 = GiftSupplyBatch(
        id: "batch_02",
        batchNumber: 2,
        quantity: 50,
        supplyDate: DateTime(2026, 8, 25),
        referenceNumber: "PO-MANAGER-02",
        notes: "Second batch supplied by company manager",
        addedBy: "مدير الشركة",
      );

      final updatedGift = gift.copyWith(
        totalQuantity: gift.totalQuantity + 50,
        availableQuantity: gift.availableQuantity + 50,
        batches: [...gift.batches, batch2],
      );

      expect(updatedGift.totalQuantity, equals(150));
      expect(updatedGift.availableQuantity, equals(150));
      expect(updatedGift.totalMonetaryValue, equals(15000.0));
      expect(updatedGift.batchCount, equals(2));

      // Manager logs stock adjustment (-5 cards damaged during transit)
      final adjMovement = GiftStockMovement(
        id: "mov_adj_01",
        companySlug: "unilever",
        giftId: updatedGift.id,
        giftName: updatedGift.giftName,
        movementType: "adjustment_deduct",
        quantityChange: -5,
        previousTotal: 150,
        newTotal: 145,
        previousAvailable: 150,
        newAvailable: 145,
        reference: "محضر هالك رقم 12",
        notes: "بطاقات تالفة أثناء الشحن",
        performedBy: "مدير الشركة",
        timestamp: DateTime.now(),
      );

      expect(adjMovement.isDeduction, isTrue);
      expect(adjMovement.typeLabelAr, equals("تسوية جردية بالنقص / هالك"));
      expect(adjMovement.performedBy, equals("مدير الشركة"));
    });
  });
}
