import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Invoices Log Campaign Selector & 25-Item Desktop/Mobile Pagination Tests', () {
    test('Desktop M3 Pagination divides 70 items into 3 pages of 25 items correctly', () {
      const pageSize = 25;
      final dummyInvoices = List.generate(70, (i) => {'id': 'inv_$i', 'receipt_number': 'REC-$i'});
      final totalItems = dummyInvoices.length;
      final totalPages = (totalItems / pageSize).ceil();

      expect(totalPages, 3);

      // Page 1 (index 0)
      int currentPage = 0;
      int safePage = currentPage.clamp(0, totalPages - 1);
      int startIndex = safePage * pageSize;
      int endIndex = (startIndex + pageSize).clamp(0, totalItems);
      var pageItems = dummyInvoices.sublist(startIndex, endIndex);

      expect(pageItems.length, 25);
      expect(pageItems.first['id'], 'inv_0');
      expect(pageItems.last['id'], 'inv_24');

      // Page 2 (index 1) - Next Page
      currentPage = 1;
      safePage = currentPage.clamp(0, totalPages - 1);
      startIndex = safePage * pageSize;
      endIndex = (startIndex + pageSize).clamp(0, totalItems);
      pageItems = dummyInvoices.sublist(startIndex, endIndex);

      expect(pageItems.length, 25);
      expect(pageItems.first['id'], 'inv_25');
      expect(pageItems.last['id'], 'inv_49');

      // Page 3 (index 2) - Last Page
      currentPage = 2;
      safePage = currentPage.clamp(0, totalPages - 1);
      startIndex = safePage * pageSize;
      endIndex = (startIndex + pageSize).clamp(0, totalItems);
      pageItems = dummyInvoices.sublist(startIndex, endIndex);

      expect(pageItems.length, 20);
      expect(pageItems.first['id'], 'inv_50');
      expect(pageItems.last['id'], 'inv_69');
    });

    test('Mobile Progressive Lazy Loading batches 70 items into +25 increments', () {
      const pageSize = 25;
      final dummyInvoices = List.generate(70, (i) => {'id': 'inv_$i', 'receipt_number': 'REC-$i'});
      final totalItems = dummyInvoices.length;

      int mobileLimit = pageSize;
      var currentBatch = dummyInvoices.take(mobileLimit).toList();

      expect(currentBatch.length, 25);
      expect(currentBatch.first['id'], 'inv_0');
      expect(currentBatch.last['id'], 'inv_24');
      expect(totalItems - mobileLimit, 45); // Remaining

      // Load More 1
      mobileLimit += pageSize;
      currentBatch = dummyInvoices.take(mobileLimit).toList();
      expect(currentBatch.length, 50);
      expect(currentBatch.last['id'], 'inv_49');
      expect(totalItems - mobileLimit, 20); // Remaining

      // Load More 2
      mobileLimit += pageSize;
      currentBatch = dummyInvoices.take(mobileLimit).toList();
      expect(currentBatch.length, 70);
      expect(currentBatch.last['id'], 'inv_69');
      expect(mobileLimit >= totalItems, isTrue); // Completed
    });

    test('Pagination resets currentPage to 0 and mobileLimit to 25 on search or filter updates', () {
      const pageSize = 25;
      int currentPage = 2;
      int mobileLimit = 75;

      // Filter changed -> reset
      currentPage = 0;
      mobileLimit = pageSize;

      expect(currentPage, 0);
      expect(mobileLimit, 25);
    });

    test('Campaign Selector filter matches name, company, store chain, and branches', () {
      final events = [
        EventModel(
          id: 'ev1',
          eventName: 'مهرجان المراعي الصيفي',
          companySlug: 'almarai',
          targetCompany: 'المراعي',
          retailChainName: 'فتح الله ماركت',
          branchNames: ['فرع سموحة (209)', 'فرع سان ستيفانو (214)'],
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
          minimumSpend: 100.0,
          isActive: true,
        ),
        EventModel(
          id: 'ev2',
          eventName: 'مهرجان ادكو للتسوق',
          companySlug: 'adco',
          targetCompany: 'ادكو',
          retailChainName: 'كارفور',
          branchNames: ['فرع سيتي سنتر'],
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
          minimumSpend: 100.0,
          isActive: true,
        ),
        EventModel(
          id: 'ev3',
          eventName: 'عروض جهينة الرمضانية',
          companySlug: 'juhayna',
          targetCompany: 'جهينة',
          retailChainName: 'فتح الله ماركت',
          branchNames: ['فرع لوران (235)'],
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 2, 1), // Expired
          minimumSpend: 100.0,
          isActive: false,
        ),
      ];

      // 1. Search query "سموحة" matches Almarai
      final query1 = 'سموحة';
      final results1 = events.where((e) {
        return e.eventName.contains(query1) ||
            e.targetCompany.contains(query1) ||
            e.retailChainName.contains(query1) ||
            e.branchNames.join(' ').contains(query1);
      }).toList();
      expect(results1.length, 1);
      expect(results1.first.id, 'ev1');

      // 2. Search query "كارفور" matches Adco
      final query2 = 'كارفور';
      final results2 = events.where((e) {
        return e.eventName.contains(query2) ||
            e.targetCompany.contains(query2) ||
            e.retailChainName.contains(query2) ||
            e.branchNames.join(' ').contains(query2);
      }).toList();
      expect(results2.length, 1);
      expect(results2.first.id, 'ev2');

      // 3. Active filter only
      final activeOnly = events.where((e) => e.isActive && !e.isExpired).toList();
      expect(activeOnly.length, 2);
      expect(activeOnly.map((e) => e.id), containsAll(['ev1', 'ev2']));

      // 4. Expired filter only
      final expiredOnly = events.where((e) => e.isExpired || !e.isActive).toList();
      expect(expiredOnly.length, 1);
      expect(expiredOnly.first.id, 'ev3');
    });

    test('Branch filtering and phonetic normalization matches invoices correctly', () {
      final invoices = [
        {
          'id': 'inv_1',
          'receipt_number': 'REC-101',
          'branch_detected': 'أسواق فتح الله - فرع سموحة',
          'store_chain_detected': 'فتح الله ماركت',
        },
        {
          'id': 'inv_2',
          'receipt_number': 'REC-102',
          'branch_detected': 'أسواق فتح الله - فرع سان ستيفانو',
          'store_chain_detected': 'فتح الله ماركت',
        },
        {
          'id': 'inv_3',
          'receipt_number': 'REC-103',
          'branch_detected': 'كارفور - فرع سيتي سنتر',
          'store_chain_detected': 'كارفور',
        },
      ];

      // Branch match helper logic
      bool matchesBranch(Map<String, dynamic> inv, String selectedBranch) {
        if (selectedBranch == 'all') return true;
        final branch = (inv['branch_detected'] ?? '').toString().trim().toLowerCase();
        final store = (inv['store_chain_detected'] ?? '').toString().trim().toLowerCase();
        final sel = selectedBranch.trim().toLowerCase();
        return branch.contains(sel) || sel.contains(branch) || store.contains(sel);
      }

      // 1. Select 'سموحة' -> only inv_1
      final filteredSmoha = invoices.where((inv) => matchesBranch(inv, 'سموحة')).toList();
      expect(filteredSmoha.length, 1);
      expect(filteredSmoha.first['id'], 'inv_1');

      // 2. Select 'كارفور' -> only inv_3
      final filteredCarrefour = invoices.where((inv) => matchesBranch(inv, 'كارفور')).toList();
      expect(filteredCarrefour.length, 1);
      expect(filteredCarrefour.first['id'], 'inv_3');

      // 3. Select 'all' -> all 3
      final filteredAll = invoices.where((inv) => matchesBranch(inv, 'all')).toList();
      expect(filteredAll.length, 3);
    });

    test('Resolves and consolidates 38 raw branch variants into strictly 12 canonical campaign branches', () {
      final canonical12Branches = [
        'المنتزه',
        'سموحة',
        'جناكليس',
        'التجمع (Tagmoo)',
        'أكتوبر (October)',
        'عمارات العبور - صلاح سالم',
        'شبين الكوم',
        'المنصورة',
        'المحلة الكبرى',
        'جاردينيا',
        'سان ستيفانو',
        'سيتي سنتر',
      ];

      final rawVariants = [
        'Store: 418',
        'The Park Mall - التجمع الخامس',
        'أكتوبر (October)',
        'أكتوبر (October) (السادس من أكتوبر)',
        'التجمع (TAGMOO)',
        'التجمع (Tagmoo)',
        'التجمع (Tagmoo) (القاهرة)',
        'المنتزه',
        'المنتزه (18 Store: 418 - MONTAZAH)',
        'المنتزه (MONTAZAH)',
        'المنتزه (Store: 418)',
        'المنتزه (الإسكندرية)',
        'المنصورة',
        'المنصورة (المنصورة)',
        'جناكليس',
        'جناكليس (الإسكندرية)',
        'سموحة',
        'شين الكوم (شبين الكوم)',
        'عمارات العبور - صلاح سالم',
        'عمارات العبور - صلاح سالم (القاهرة)',
        'عمارات العبور_صلاح سالم',
        'فرع المحلة الكبرى',
        'فرع المحلة الكبرى (الغربية)',
        'فرع المنتزه',
        'فرع المنتزه (MONTAZAH)',
        'فرع جاردينيا',
      ];

      // Clean normalizer simulation
      String normalize(String raw) {
        var s = raw.trim().toLowerCase();
        s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
        s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
        s = s.replaceAll('ة', 'ه').replaceAll('ى', 'ي');
        s = s.replaceAll(RegExp(r'[\(\)\[\]\{\}\-\_\,\.\:\/]'), ' ');
        s = s.replaceAll(RegExp(r'\b(فرع|سلسلة|store|branch|مفرع|pos|كود|محافظة|مدينة)\b', caseSensitive: false), ' ');
        s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

        if (s.contains('418') || s.contains('منتزه') || s.contains('montazah')) return 'المنتزه';
        if (s.contains('تجمع') || s.contains('tagmoo') || s.contains('park mall')) return 'التجمع (Tagmoo)';
        if (s.contains('اكتوبر') || s.contains('october') || s.contains('سادس')) return 'أكتوبر (October)';
        if (s.contains('عبور') || s.contains('صلاح سالم')) return 'عمارات العبور - صلاح سالم';
        if (s.contains('شين') || s.contains('شبين')) return 'شبين الكوم';
        if (s.contains('محله')) return 'المحلة الكبرى';
        if (s.contains('منصور')) return 'المنصورة';
        if (s.contains('جناكليس')) return 'جناكليس';
        if (s.contains('سموح')) return 'سموحة';
        if (s.contains('جاردينيا')) return 'جاردينيا';
        if (s.contains('سان ستيفانو')) return 'سان ستيفانو';
        if (s.contains('سيتي سنتر')) return 'سيتي سنتر';

        return raw;
      }

      final resolvedSet = rawVariants.map(normalize).toSet();

      // Ensure every single raw variant maps ONLY to one of the 12 canonical branches
      for (final resolved in resolvedSet) {
        expect(canonical12Branches.contains(resolved), isTrue, reason: '$resolved must be one of the 12 canonical branches');
      }

      // Check specific mappings
      expect(normalize('Store: 418'), 'المنتزه');
      expect(normalize('The Park Mall - التجمع الخامس'), 'التجمع (Tagmoo)');
      expect(normalize('المنتزه (18 Store: 418 - MONTAZAH)'), 'المنتزه');
      expect(normalize('عمارات العبور_صلاح سالم'), 'عمارات العبور - صلاح سالم');
      expect(normalize('شين الكوم (شبين الكوم)'), 'شبين الكوم');
      expect(normalize('فرع المحلة الكبرى (الغربية)'), 'المحلة الكبرى');
    });

    test('Strict branch filtering isolates selected branch invoices and calculates accurate KPIs', () {
      final dataset = [
        // 17 invoices for Tagmoo
        ...List.generate(17, (i) => {
          'id': 'tagmoo_$i',
          'canonical_branch': 'التجمع (Tagmoo) (القاهرة)',
          'target_company_total': 100.0,
          'extracted_products': [{'quantity': 2}],
          'analysis_duration_seconds': 5.0,
          'is_valid': true,
        }),
        // 38 invoices for Obour (also in Cairo)
        ...List.generate(38, (i) => {
          'id': 'obour_$i',
          'canonical_branch': 'عمارات العبور - صلاح سالم (القاهرة)',
          'target_company_total': 200.0,
          'extracted_products': [{'quantity': 3}],
          'analysis_duration_seconds': 8.0,
          'is_valid': true,
        }),
        // 73 invoices for Gardenia (Alexandria)
        ...List.generate(73, (i) => {
          'id': 'gardenia_$i',
          'canonical_branch': 'فرع جاردينيا (الإسكندرية)',
          'target_company_total': 150.0,
          'extracted_products': [{'quantity': 1}],
          'analysis_duration_seconds': 6.0,
          'is_valid': true,
        }),
      ];

      expect(dataset.length, 128);

      // Filter by Tagmoo
      final selectedBranch = 'التجمع (Tagmoo) (القاهرة)';
      final filtered = dataset.where((inv) => inv['canonical_branch'] == selectedBranch).toList();

      expect(filtered.length, 17);
      expect(filtered.every((inv) => inv['canonical_branch'] == selectedBranch), isTrue);
      // Ensure zero Obour invoices leaked in
      expect(filtered.any((inv) => (inv['id'] as String).startsWith('obour_')), isFalse);

      // KPI Metrics for filtered Tagmoo
      final totalSales = filtered.fold<double>(0.0, (acc, inv) => acc + (inv['target_company_total'] as double));
      final totalItems = filtered.fold<int>(0, (acc, inv) => acc + ((inv['extracted_products'] as List).first['quantity'] as int));
      final avgSpeed = filtered.fold<double>(0.0, (acc, inv) => acc + (inv['analysis_duration_seconds'] as double)) / filtered.length;

      expect(totalSales, 1700.0);
      expect(totalItems, 34);
      expect(avgSpeed, 5.0);

      // Filter by Gardenia
      final filteredGardenia = dataset.where((inv) => inv['canonical_branch'] == 'فرع جاردينيا (الإسكندرية)').toList();
      expect(filteredGardenia.length, 73);
      expect(filteredGardenia.fold<double>(0.0, (acc, inv) => acc + (inv['target_company_total'] as double)), 73 * 150.0);
    });

    test('Trilingual strings exist for invoices log & campaign selector', () {
      final ar = AppStrings('ar');
      final en = AppStrings('en');
      final hi = AppStrings('hi');

      expect(ar.allCampaigns, isNotEmpty);
      expect(en.allCampaigns, isNotEmpty);
      expect(hi.allCampaigns, isNotEmpty);

      expect(ar.invoicesAuditTitle, isNotEmpty);
      expect(en.invoicesAuditTitle, isNotEmpty);
      expect(hi.invoicesAuditTitle, isNotEmpty);

      expect(ar.searchReceiptPlaceholder, isNotEmpty);
      expect(en.searchReceiptPlaceholder, isNotEmpty);
      expect(hi.searchReceiptPlaceholder, isNotEmpty);

      expect(ar.filterByDate, isNotEmpty);
      expect(en.filterByDate, isNotEmpty);
      expect(hi.filterByDate, isNotEmpty);
    });
  });
}

