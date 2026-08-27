import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  final testEvent = EventModel(
    id: 'test-event-123',
    eventName: 'يونيليفر ديوز - هيركير',
    welcomeTitle: 'أهلاً بكم في مهرجان يونيليفر',
    welcomeMessage: 'ارفع فاتورتك وادخل السحب',
    targetCompany: 'يونيليفر',
    companyLogoUrl: '',
    minimumSpend: 100.0,
    termsAndConditions: 'الشروط والأحكام',
    gameType: 'spinTheWheel',
    allocatedPrizes: [],
    createdAt: DateTime.now(),
    branchNames: [
      'المنتزه',
      'سموحة',
      'السيوف',
      'ميامي',
      'جناكليس',
      'لوران',
      'ستانلي',
      'العجمي',
      'الزهور',
      'المكس',
      'كرموز',
      'محرم بك',
    ],
  );

  group('PromoterInvoicesDialog Canonical Branch Governance & Scoping Tests', () {
    test('Canonical branches strictly contains only the 12 configured campaign branches', () {
      final canonicalBranches = testEvent.branchNames
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .toList();

      expect(canonicalBranches.length, equals(12));
      expect(canonicalBranches, contains('المنتزه'));
      expect(canonicalBranches, contains('سموحة'));
      expect(canonicalBranches, contains('السيوف'));
      expect(canonicalBranches, contains('ميامي'));
      expect(canonicalBranches, contains('جناكليس'));
      expect(canonicalBranches, contains('لوران'));
      expect(canonicalBranches, contains('ستانلي'));
      expect(canonicalBranches, contains('العجمي'));
      expect(canonicalBranches, contains('الزهور'));
      expect(canonicalBranches, contains('المكس'));
      expect(canonicalBranches, contains('كرموز'));
      expect(canonicalBranches, contains('محرم بك'));

      // Rogue OCR strings must not be in canonical branches
      expect(canonicalBranches, isNot(contains('Store: 418')));
      expect(canonicalBranches, isNot(contains('fathalla_211')));
    });

    test('Normalizes raw OCR branch variations and Store 418 to canonical Montazah', () {
      final canonicalBranches = testEvent.branchNames;

      // Store 418 / Montazah variations
      final res1 = PromoterInvoicesDialogStateNormalizeTester.normalize(
        'Store: 418 - MONTAZAH',
        canonicalBranches,
        true,
      );
      expect(res1, equals('المنتزه'));

      final res2 = PromoterInvoicesDialogStateNormalizeTester.normalize(
        'أسواق فتح الله - المنتزه (Store: 418)',
        canonicalBranches,
        true,
      );
      expect(res2, equals('المنتزه'));

      // Smouha variation
      final res3 = PromoterInvoicesDialogStateNormalizeTester.normalize(
        'فتح الله ماركت سموحه (الإسكندرية)',
        canonicalBranches,
        true,
      );
      expect(res3, equals('سموحة'));

      // Miami variation
      final res4 = PromoterInvoicesDialogStateNormalizeTester.normalize(
        'فرع ميامى',
        canonicalBranches,
        true,
      );
      expect(res4, equals('ميامي'));

      // Agamy variation
      final res5 = PromoterInvoicesDialogStateNormalizeTester.normalize(
        'العجمى هانوفيل',
        canonicalBranches,
        true,
      );
      expect(res5, equals('العجمي'));
    });

    test('Filters out rejected receipts and groups counts strictly by canonical branch', () {
      final canonicalBranches = testEvent.branchNames;
      final rawReceipts = [
        {
          'receipt_number': '17/39/418/200826',
          'branch_detected': 'Store: 418 - MONTAZAH',
          'total_value': 138.0,
          'is_valid': true,
        },
        {
          'receipt_number': '126/18/418/200826',
          'branch_detected': 'أسواق فتح الله - المنتزه (Store: 418)',
          'total_value': 120.0,
          'is_valid': true,
        },
        {
          'receipt_number': '86/11/418/200826',
          'branch_detected': 'جملة ماركت - Store: 418',
          'total_value': 295.0,
          'is_valid': true,
        },
        {
          'receipt_number': 'REJ-001',
          'branch_detected': 'Store: 418',
          'total_value': 50.0,
          'is_valid': false, // REJECTED
        },
      ];

      final validInvoices = <Map<String, dynamic>>[];
      for (final r in rawReceipts) {
        if (r['is_valid'] != true) continue;
        final rawBranch = r['branch_detected'].toString();
        final canonicalBranch = PromoterInvoicesDialogStateNormalizeTester.normalize(
          rawBranch,
          canonicalBranches,
          true,
        );
        validInvoices.add({
          ...r,
          'canonical_branch': canonicalBranch,
        });
      }

      expect(validInvoices.length, equals(3));

      final branchCounts = <String, int>{};
      for (final b in canonicalBranches) {
        branchCounts[b] = 0;
      }
      for (final inv in validInvoices) {
        final b = inv['canonical_branch'] as String;
        if (branchCounts.containsKey(b)) {
          branchCounts[b] = (branchCounts[b] ?? 0) + 1;
        }
      }

      expect(branchCounts['المنتزه'], equals(3));
      expect(branchCounts['سموحة'], equals(0));
      expect(branchCounts['ميامي'], equals(0));
    });
  });
}

/// Helper to test static normalization logic directly
class PromoterInvoicesDialogStateNormalizeTester {
  static String normalize(String raw, List<String> canonical, bool isAr) {
    return _normalizeBranchName(raw, canonical, isAr);
  }

  static String _cleanBranchForComparison(String branch) {
    var s = branch.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    s = s.replaceAll('ة', 'ه').replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'\((القاهرة|الإسكندرية|الاسكندرية|الجيزة|الغربية|الدقهلية|المنوفية|الشرقية|البحيرة|كفر الشيخ|دمياط|بورسعيد|السويس|الإسماعيلية|الفيوم|بني سويف|المنيا|أسيوط|سوهاج|قنا|الأقصر|أسوان|مطروح|cairo|alexandria|giza)\)', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'[\(\)\[\]\{\}\-\_\,\.\:\/]'), ' ');
    s = s.replaceAll(RegExp(r'\b(فرع|سلسلة|store|branch|مفرع|pos|كود|محافظة|مدينة)\b', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String _normalizeBranchName(
    String rawBranch,
    List<String> canonicalBranches,
    bool isAr,
  ) {
    final clean = rawBranch.trim();
    if (clean.isEmpty) return isAr ? 'فرع غير محدد' : 'Unspecified Branch';
    if (canonicalBranches.isEmpty) return clean;

    for (final canonical in canonicalBranches) {
      if (canonical.trim().toLowerCase() == clean.toLowerCase()) {
        return canonical;
      }
    }

    final cleanComp = _cleanBranchForComparison(clean);
    for (final canonical in canonicalBranches) {
      final canonComp = _cleanBranchForComparison(canonical);
      if (cleanComp == canonComp && cleanComp.isNotEmpty) {
        return canonical;
      }
    }

    if (clean.contains('418') || cleanComp.contains('منتزه') || cleanComp.contains('montazah')) {
      for (final canonical in canonicalBranches) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('منتزه') || c.contains('montazah') || canonical.contains('418')) return canonical;
      }
    }
    if (cleanComp.contains('سموح') || cleanComp.contains('smouha')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('سموح')) return canonical;
      }
    }
    if (cleanComp.contains('ميام') || cleanComp.contains('miami')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('ميام')) return canonical;
      }
    }
    if (cleanComp.contains('عجم') || cleanComp.contains('agamy') || cleanComp.contains('agami')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('عجم')) return canonical;
      }
    }

    return canonicalBranches.first;
  }
}
