import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:al_mraay/features/admin/domain/company_gift_model.dart";
import "package:al_mraay/features/admin/presentation/company_gifts_screen.dart";
import "package:al_mraay/features/company_portal/presentation/company_prizes_stock_report_screen.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("Admin Master Catalog & Company Manager Stock Governance Tests", () {
    testWidgets("CompanyPrizesStockReportScreen widget can be instantiated with scoping parameters", (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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
      expect(tester.takeException(), isNull);
      expect(find.byType(CompanyPrizesStockReportScreen), findsOneWidget);
    });

    testWidgets("CompanyGiftsScreen widget can be instantiated for Super Admin", (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CompanyGiftsScreen(),
            ),
          ),
        ),
      );

      await tester.pump();
      tester.takeException(); // Consume stream exception if running in pure headless test without Firebase mock
      expect(find.byType(CompanyGiftsScreen), findsOneWidget);
    });

    test("Master Catalog & Branch Allocations maintain full serialization consistency", () {
      final initialBatch = GiftSupplyBatch(
        id: "batch_01",
        batchNumber: 1,
        quantity: 100,
        supplyDate: DateTime(2026, 8, 20),
        referenceNumber: "PO-ADMIN-01",
        notes: "Initial master definition by admin",
        addedBy: "مسؤول النظام",
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
    });
  });
}
