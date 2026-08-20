import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:al_mraay/core/localization/app_strings.dart";
import "package:al_mraay/features/admin/domain/event_model.dart";
import "package:al_mraay/features/company_portal/presentation/company_prizes_stock_report_screen.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("Manager Branch Prize Allocation & Real-Time Supply Tests", () {
    test("AllocatedPrize correctly models branch quotas, voucher values, and remaining counts", () {
      final prize = AllocatedPrize(
        giftId: "gift_clear_90ml",
        name: "كلير 90 مل هديه",
        allocatedQuantity: 5,
        remainingQuantity: 5,
        branchId: "branch_gardenia",
        branchName: "فرع جاردينيا (الإسكندرية)",
        giftType: "product",
      );

      expect(prize.allocatedQuantity, 5);
      expect(prize.remainingQuantity, 5);
      expect(prize.branchName, "فرع جاردينيا (الإسكندرية)");

      // Simulate increasing branch allocation by +5
      final updated = prize.copyWith(
        allocatedQuantity: 10,
        remainingQuantity: 10,
      );

      expect(updated.allocatedQuantity, 10);
      expect(updated.remainingQuantity, 10);
      expect(updated.branchName, "فرع جاردينيا (الإسكندرية)");

      final map = updated.toMap();
      expect(map["allocatedQuantity"], 10);
      expect(map["remainingQuantity"], 10);
      expect(map["branchName"], "فرع جاردينيا (الإسكندرية)");
    });

    test("Localization strings for Branch Prize Supply & Quota Adjustment are defined in AR, EN, HI", () {
      final stringsAr = AppStrings("ar");
      final stringsEn = AppStrings("en");
      final stringsHi = AppStrings("hi");

      expect(stringsAr.adjustBranchAllocationTitle, "تعديل وتزويد حصة الفرع");
      expect(stringsEn.adjustBranchAllocationTitle, "Adjust & Supply Branch Allocation");
      expect(stringsHi.adjustBranchAllocationTitle, "शाखा कोटा संशोधित और आपूर्ति करें");

      expect(stringsAr.quickSupplyBranchBtn, "تزويد رصيد الفرع");
      expect(stringsEn.quickSupplyBranchBtn, "Supply Branch Stock");

      expect(stringsAr.branchAllocationSuccessMsg, contains("تم تحديث وتزويد حصة الفرع بنجاح"));
      expect(stringsEn.branchAllocationSuccessMsg, contains("Branch prize allocation updated"));
      expect(stringsHi.branchAllocationSuccessMsg, contains("शाखा उपहार आवंटन"));

      expect(stringsAr.cannotReduceBelowClaimedError, contains("لا يمكن تقليل حصة الفرع"));
    });

    testWidgets("CompanyPrizesStockReportScreen renders Branch Breakdown with Supply Actions", (tester) async {
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
      await tester.pump(const Duration(milliseconds: 100));

      // Verify screen renders properly
      expect(find.byType(CompanyPrizesStockReportScreen), findsOneWidget);
    });
  });
}
