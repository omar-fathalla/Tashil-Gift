import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/utils/arabic_numbers_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Retail Chains & Branches Domain Tests', () {
    test('RetailChainModel fromMap and toFirestore works accurately', () {
      final model = RetailChainModel.fromMap({
        'name': 'أسواق فتح الله',
        'slug': 'fathalla',
        'branchesCount': 10,
      }, 'fathalla');

      expect(model.id, 'fathalla');
      expect(model.name, 'أسواق فتح الله');
      expect(model.slug, 'fathalla');
      expect(model.branchesCount, 10);

      final map = model.toFirestore();
      expect(map['name'], 'أسواق فتح الله');
      expect(map['slug'], 'fathalla');
      expect(map['branchesCount'], 10);
    });

    test('BranchModel fromMap and toFirestore works accurately', () {
      final branch = BranchModel.fromMap({
        'retailChainId': 'fathalla',
        'retailChainName': 'أسواق فتح الله',
        'branchName': 'فرع الهانوفيل',
        'city': 'الإسكندرية (العجمي)',
        'branchCode': 'FAT-HNF',
        'address': 'طريق إسكندرية مطروح',
      }, 'branch-101');

      expect(branch.id, 'branch-101');
      expect(branch.retailChainId, 'fathalla');
      expect(branch.branchName, 'فرع الهانوفيل');
      expect(branch.city, 'الإسكندرية (العجمي)');
      expect(branch.branchCode, 'FAT-HNF');

      final map = branch.toFirestore();
      expect(map['retailChainId'], 'fathalla');
      expect(map['branchName'], 'فرع الهانوفيل');
      expect(map['branchCode'], 'FAT-HNF');
    });

    test('EventModel supports retail chain and branch properties', () {
      final event = EventModel(
        id: 'event-001',
        eventName: 'عروض الصيف',
        targetCompany: 'المراعي',
        companySlug: 'almarai',
        minimumSpend: 150.0,
        retailChainId: 'fathalla',
        retailChainName: 'أسواق فتح الله',
        isAllBranches: false,
        branchIds: ['b1', 'b2'],
        branchNames: ['فرع سموحة', 'فرع الهانوفيل'],
      );

      expect(event.retailChainId, 'fathalla');
      expect(event.retailChainName, 'أسواق فتح الله');
      expect(event.isAllBranches, false);
      expect(event.branchNames.length, 2);
      expect(event.branchesDisplaySummary, 'أسواق فتح الله (2 فروع: فرع سموحة، فرع الهانوفيل)');

      final map = event.toFirestore();
      expect(map['retailChainId'], 'fathalla');
      expect(map['retailChainName'], 'أسواق فتح الله');
      expect(map['isAllBranches'], false);
      expect(map['branchNames'], ['فرع سموحة', 'فرع الهانوفيل']);
    });

    test('EventModel branchesDisplaySummary with all branches', () {
      final event = EventModel(
        id: 'event-002',
        eventName: 'مهرجان الجبن',
        targetCompany: 'المراعي',
        retailChainId: 'carrefour',
        retailChainName: 'كارفور مصر',
        isAllBranches: true,
        minimumSpend: 200,
      );

      expect(event.branchesDisplaySummary, 'كارفور مصر (جميع الفروع)');
    });

    test('EventModel supports multiple retail chains and comma-separated IDs', () {
      final event = EventModel(
        id: 'event-003',
        eventName: 'مهرجان الصيف الكبرى',
        targetCompany: 'المراعي',
        retailChainId: 'fathalla,carrefour,spinneys',
        retailChainName: 'أسواق فتح الله • كارفور • سبينس',
        isAllBranches: true,
        minimumSpend: 200,
      );

      expect(event.retailChainId, 'fathalla,carrefour,spinneys');
      expect(event.retailChainName, 'أسواق فتح الله • كارفور • سبينس');
      expect(event.isAllBranches, true);
      expect(event.branchesDisplaySummary, 'أسواق فتح الله • كارفور • سبينس (جميع الفروع)');

      final map = event.toFirestore();
      expect(map['retailChainId'], 'fathalla,carrefour,spinneys');
      expect(map['retailChainName'], 'أسواق فتح الله • كارفور • سبينس');
    });
  });

  group('Arabic Numerals Normalization in Retail Chains', () {
    test('Converts Eastern Arabic digits in branch codes and slugs', () {
      final easternSlug = 'fathalla-١٠١';
      expect(easternSlug.toEnglishDigits(), 'fathalla-101');

      final easternCode = 'FAT-٠٠٥';
      expect(easternCode.toEnglishDigits(), 'FAT-005');
    });
  });
}
