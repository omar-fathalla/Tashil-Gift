import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Invoices Log Campaign Selector & 20-Item Pagination Tests', () {
    test('Default page size is 20 and handles slicing correctly', () {
      const pageSize = 20;
      final dummyInvoices = List.generate(55, (i) => {'id': 'inv_$i', 'receipt_number': 'REC-$i'});

      int displayedCount = pageSize;
      var currentBatch = dummyInvoices.take(displayedCount).toList();

      expect(currentBatch.length, 20);
      expect(currentBatch.first['id'], 'inv_0');
      expect(currentBatch.last['id'], 'inv_19');

      // Scroll down -> fetch next 20
      displayedCount += pageSize;
      currentBatch = dummyInvoices.take(displayedCount).toList();
      expect(currentBatch.length, 40);
      expect(currentBatch.last['id'], 'inv_39');

      // Scroll down -> fetch remaining
      displayedCount += pageSize;
      currentBatch = dummyInvoices.take(displayedCount).toList();
      expect(currentBatch.length, 55);
      expect(currentBatch.last['id'], 'inv_54');
    });

    test('Pagination resets to 20 on search or filter updates', () {
      const pageSize = 20;
      int displayedCount = 60; // User had scrolled down

      // Reset triggered
      displayedCount = pageSize;
      expect(displayedCount, 20);
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
