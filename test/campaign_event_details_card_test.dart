import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/presentation/campaign_reports_screen.dart';

void main() {
  group('Campaign Details Card - Split Chains & Collapsible Branches Tests', () {
    testWidgets('Renders individual chain pills and starts with branches collapsed', (tester) async {
      final event = EventModel(
        id: 'event-unilever-1',
        eventName: 'يونيليفر ديوز - هيركير',
        targetCompany: 'يونيليفر',
        minimumSpend: 0,
        retailChainId: 'fathalla,beit-elgomla,gomla-market',
        retailChainName: 'أسواق فتح الله • بيت الجملة • جملة ماركت',
        branchNames: [
          'فرع جاردينيا (الإسكندرية)',
          'فرع سموحة (الإسكندرية)',
          'فرع عجمي ستار (الإسكندرية)',
          'فرع المحلة الكبري (الغربية)',
          'شبين الكوم (شبين الكوم)',
          'التجمع (Tagmoo) (القاهرة)',
          'أكتوبر (October) (السادس من أكتوبر)',
          'المنصورة (المنصورة)',
          'عمارات العبور - صلاح سالم (القاهرة)',
          'المنتزه (الإسكندرية)',
          'ميامي (الإسكندرية)',
          'جناكليس (الإسكندرية)',
        ],
        isAllBranches: false,
        isActive: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CampaignReportsScreen(
                  initialEvent: event,
                  isEmbedded: true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Campaign Title and Company are visible
      expect(find.text('يونيليفر ديوز - هيركير'), findsWidgets);
      expect(find.text('يونيليفر'), findsWidgets);

      // Verify all 3 chains are separated into individual distinct pills
      expect(find.text('أسواق فتح الله'), findsWidgets);
      expect(find.text('بيت الجملة'), findsWidgets);
      expect(find.text('جملة ماركت'), findsWidgets);

      // Verify the branches list is NOT visible by default (compact card)
      expect(find.text('المنافذ والفروع المعتمدة لسحب الجوائز (12 فرع):'), findsNothing);
      expect(find.text('فرع جاردينيا (الإسكندرية)'), findsNothing);

      // Click on "12 فروع ومنافذ معتمدة" to expand all branches
      final branchesToggle = find.textContaining('12 فروع ومنافذ معتمدة');
      expect(branchesToggle, findsWidgets);
      await tester.tap(branchesToggle.first);
      await tester.pumpAndSettle();

      // Now the branches drawer is open
      expect(find.textContaining('المنافذ والفروع المعتمدة'), findsWidgets);
      expect(find.text('فرع جاردينيا (الإسكندرية)'), findsWidgets);
      expect(find.text('فرع سموحة (الإسكندرية)'), findsWidgets);
      expect(find.text('إخفاء الفروع'), findsWidgets);

      // Click on "إخفاء الفروع" to collapse
      await tester.tap(find.text('إخفاء الفروع').first);
      await tester.pumpAndSettle();

      // Branches should be collapsed again
      expect(find.text('فرع جاردينيا (الإسكندرية)'), findsNothing);
    });

    testWidgets('Tapping individual chain pill filters branches directly', (tester) async {
      final event = EventModel(
        id: 'event-unilever-2',
        eventName: 'عروض يونيليفر الشاملة',
        targetCompany: 'يونيليفر',
        minimumSpend: 100,
        retailChainName: 'أسواق فتح الله • بيت الجملة • جملة ماركت',
        branchNames: [
          'فرع سموحة (الإسكندرية)',
          'فرع المنتزه (الإسكندرية)',
          'فرع المحلة (الغربية)',
        ],
        isAllBranches: false,
        isActive: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CampaignReportsScreen(
                  initialEvent: event,
                  isEmbedded: true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Click on 'أسواق فتح الله' pill
      await tester.tap(find.text('أسواق فتح الله').first);
      await tester.pumpAndSettle();

      // Should open drawer filtered to 'أسواق فتح الله'
      expect(find.textContaining('أسواق فتح الله'), findsWidgets);
      expect(find.text('إخفاء الفروع'), findsWidgets);
    });
  });
}
