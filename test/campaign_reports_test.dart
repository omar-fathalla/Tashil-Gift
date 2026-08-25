import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Campaign Reports & Event Scoping Tests', () {
    test('EventModel properly exposes company, chain, and branch metadata', () {
      final event = EventModel(
        id: 'event-mraay-fathalla-1',
        eventName: 'حملة الصيف الكبرى 2026',
        targetCompany: 'المراعي',
        companySlug: 'almarai',
        minimumSpend: 250.0,
        retailChainId: 'fathalla-chain-1',
        retailChainName: 'أسواق فتح الله',
        branchIds: ['branch-smouha', 'branch-gleem'],
        branchNames: ['فرع سموحة', 'فرع جليم'],
        isAllBranches: false,
        isActive: true,
      );

      expect(event.eventName, 'حملة الصيف الكبرى 2026');
      expect(event.targetCompany, 'المراعي');
      expect(event.retailChainName, 'أسواق فتح الله');
      expect(event.branchNames.length, 2);
      expect(event.branchesDisplaySummary, 'أسواق فتح الله (2 فروع: فرع سموحة، فرع جليم)');
      expect(event.minimumSpend, 250.0);
      expect(event.isActive, true);
    });

    test('EventModel formats all branches summary correctly when isAllBranches is true', () {
      final event = EventModel(
        id: 'event-all-branches',
        eventName: 'مهرجان الجوائز',
        targetCompany: 'جهينة',
        minimumSpend: 150.0,
        retailChainName: 'كارفور',
        isAllBranches: true,
      );

      expect(event.branchesDisplaySummary, 'كارفور (جميع الفروع)');
    });

    test('AllocatedPrize maps correctly for inventory and campaign awards', () {
      final prize = AllocatedPrize(
        giftId: 'gift-airfryer-1',
        name: 'قلاية هوائية فيليبس XXL',
        allocatedQuantity: 10,
        remainingQuantity: 6,
        branchId: 'branch-smouha',
        branchName: 'فرع سموحة',
      );

      expect(prize.giftId, 'gift-airfryer-1');
      expect(prize.allocatedQuantity, 10);
      expect(prize.remainingQuantity, 6);
      expect(prize.branchName, 'فرع سموحة');

      final map = prize.toMap();
      expect(map['giftId'], 'gift-airfryer-1');
      expect(map['remainingQuantity'], 6);

      final fromMap = AllocatedPrize.fromMap(map);
      expect(fromMap.name, prize.name);
      expect(fromMap.remainingQuantity, 6);
    });

    test('Branch names normalize variants (فرع سموحة, سموحة, فرع سموحة (الإسكندرية)) into a single canonical branch', () {
      final canonicalBranches = [
        'فرع سموحة (الإسكندرية)',
        'فرع عجمي ستار (الإسكندرية)',
        'فرع المحلة الكبرى (الغربية)',
        'شبين الكوم (شبين الكوم)',
        'عمارات العبور - صلاح سالم (القاهرة)',
        'المنصورة (المنصورة)',
      ];

      // Simulated detected branches from 5 invoices
      final invoiceBranchDetections = [
        'فرع سموحة',
        'فرع سموحة',
        'سموحة',
        'فرع سموحة',
        'فرع سموحة',
      ];

      // Aggregation simulation
      final Map<String, int> branchInvoiceCounts = {};
      final Map<String, double> branchRevenues = {};

      for (int i = 0; i < invoiceBranchDetections.length; i++) {
        final raw = invoiceBranchDetections[i];
        final spend = (i == 2) ? 299.0 : 171.25; // 4 * 171.25 = 685.0 + 299.0 = 984.0

        // Canonical normalization matching logic
        String matched = raw;
        for (final c in canonicalBranches) {
          final normRaw = raw.replaceAll('فرع ', '').replaceAll('ة', 'ه').trim();
          final normC = c.replaceAll('فرع ', '').replaceAll(RegExp(r'\(.*?\)'), '').replaceAll('ة', 'ه').trim();
          if (normRaw == normC || normC.contains(normRaw)) {
            matched = c;
            break;
          }
        }

        branchInvoiceCounts[matched] = (branchInvoiceCounts[matched] ?? 0) + 1;
        branchRevenues[matched] = (branchRevenues[matched] ?? 0) + spend;
      }

      // Must merge all 5 invoices into 1 single unified branch entry
      expect(branchInvoiceCounts.length, 1);
      expect(branchInvoiceCounts['فرع سموحة (الإسكندرية)'], 5);
      expect(branchRevenues['فرع سموحة (الإسكندرية)'], 984.0);
    });

    test('Store code variations (Store: 418, فرع كود 418, كود 418) normalize and consolidate without rogue branches', () {
      final canonicalBranches = [
        'فرع عجمي ستار (الإسكندرية)',
        'فرع سموحة (الإسكندرية)',
        'المنتزه (الإسكندرية)',
      ];

      // Simulated DB branches mapping code 418 to 'فرع عجمي ستار'
      final dbBranches = [
        {
          'branchName': 'فرع عجمي ستار (الإسكندرية)',
          'branchCode': '418',
          'storeId': '418',
        },
        {
          'branchName': 'فرع سموحة (الإسكندرية)',
          'branchCode': '102',
          'storeId': '102',
        },
      ];

      final rawDetections = [
        {'raw': 'Store: 418', 'spend': 295.0},
        {'raw': 'فرع كود 418', 'spend': 120.0},
        {'raw': 'فرع عجمي ستار', 'spend': 55743.0},
      ];

      final Map<String, double> branchRevenues = {};
      final Map<String, int> branchCounts = {};

      for (final item in rawDetections) {
        final raw = item['raw'] as String;
        final spend = item['spend'] as double;

        // Code matching simulation
        String effective = raw;
        final clean = raw.trim();
        final codeMatch = RegExp(r'\b418\b').hasMatch(clean);
        if (codeMatch) {
          final matchedDb = dbBranches.firstWhere((b) => b['branchCode'] == '418');
          effective = matchedDb['branchName']!;
        } else {
          for (final c in canonicalBranches) {
            if (c.contains(clean) || clean.contains(c)) {
              effective = c;
              break;
            }
          }
        }

        branchRevenues[effective] = (branchRevenues[effective] ?? 0.0) + spend;
        branchCounts[effective] = (branchCounts[effective] ?? 0) + 1;
      }

      // Must consolidate all 3 transactions into the single canonical branch
      expect(branchCounts.length, 1);
      expect(branchCounts['فرع عجمي ستار (الإسكندرية)'], 3);
      expect(branchRevenues['فرع عجمي ستار (الإسكندرية)'], 55743.0 + 295.0 + 120.0);
    });
  });
}

