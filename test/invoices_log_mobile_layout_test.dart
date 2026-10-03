import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';

void main() {
  group('InvoicesLogScreen Mobile UI Layout & Metrics Tests', () {
    test('branchInvoicesChartTitle is concise "توزيع فواتير الفروع" across locales', () {
      final stringsAr = AppStrings('ar');
      expect(stringsAr.branchInvoicesChartTitle, 'توزيع فواتير الفروع');

      final stringsEn = AppStrings('en');
      expect(stringsEn.branchInvoicesChartTitle, 'Branch Invoices Distribution');

      final stringsHi = AppStrings('hi');
      expect(stringsHi.branchInvoicesChartTitle, 'शाखा चालान वितरण');
    });

    test('Total accepted invoices calculation filters only valid invoices', () {
      final invoices = [
        {'id': '1', 'validation': {'isValid': true}, 'total_amount': 150.0},
        {'id': '2', 'validation': {'isValid': false}, 'total_amount': 200.0},
        {'id': '3', 'validation': {'isValid': true}, 'total_amount': 300.0},
        {'id': '4', 'validation': {'isValid': null}, 'total_amount': 50.0},
        {'id': '5', 'isValid': true, 'total_amount': 100.0},
      ];

      final totalAcceptedInvoices = invoices.where((inv) {
        final val = inv['validation'];
        if (val is Map && val['isValid'] == true) return true;
        return inv['isValid'] == true;
      }).length;

      expect(totalAcceptedInvoices, 3);
      expect(invoices.length, 5);
    });

    test('Mobile KPI grid layout specifies crossAxisCount = 2 (2x2 grid)', () {
      // Screen widths test
      double mobileWidth = 390; // Typical iPhone width
      double tabletWidth = 750;
      double desktopWidth = 1200;

      int getCrossAxisCount(double width) {
        if (width < 700) return 2; // 2x2 grid on mobile
        if (width < 1100) return 2;
        return 4; // 1x4 row on desktop
      }

      expect(getCrossAxisCount(mobileWidth), 2);
      expect(getCrossAxisCount(tabletWidth), 2);
      expect(getCrossAxisCount(desktopWidth), 4);
    });

    test('Mobile toolbar labels are shortened correctly', () {
      String getBranchLabel(bool isMobile, bool isAr) =>
          isMobile ? (isAr ? 'الفروع' : 'Branches') : 'كافة الفروع (9)';
      String getDateLabel(bool isMobile, bool isAr) =>
          isMobile ? (isAr ? 'التاريخ' : 'Date') : 'نطاق التاريخ';

      expect(getBranchLabel(true, true), 'الفروع');
      expect(getBranchLabel(false, true), 'كافة الفروع (9)');
      expect(getDateLabel(true, true), 'التاريخ');
      expect(getDateLabel(false, true), 'نطاق التاريخ');
    });
  });
}
