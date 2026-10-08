import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/chain_product_model.dart';
import 'package:al_mraay/features/admin/presentation/widgets/product_price_history_dialog.dart';

void main() {
  group('ProductPriceHistoryDialog Smooth Scroll & Tab Slivers Tests', () {
    final mockProduct = ChainProductItem(
      id: '2300302000004',
      name: 'جبنة ريكفورد بالوزن',
      barcode: '2300302000004',
      brand: 'عام',
      category: 'أجبان',
      latestPricesByChain: {
        'أسواق فتح الله': 625.0,
        'جملة ماركت': 575.0,
      },
      chainSummaries: {
        'أسواق فتح الله': const ChainPricingSummary(
          chainName: 'أسواق فتح الله',
          regularUnitPrice: 656.0,
          netUnitPrice: 625.0,
          totalScans: 1,
          totalQuantity: 2,
        ),
        'جملة ماركت': const ChainPricingSummary(
          chainName: 'جملة ماركت',
          regularUnitPrice: 575.0,
          netUnitPrice: 575.0,
          totalScans: 2,
          totalQuantity: 2,
        ),
      },
      priceHistory: [
        ProductPriceHistoryEntry(
          storeChain: 'أسواق فتح الله',
          branchName: 'سموحة',
          receiptNumber: 'REC-101',
          receiptDate: '24/08/2026',
          price: 625.0,
          originalPrice: 656.0,
          quantity: 2,
          receiptImageUrl: '',
        ),
        ProductPriceHistoryEntry(
          storeChain: 'جملة ماركت',
          branchName: 'جناكليس',
          receiptNumber: 'REC-202',
          receiptDate: '22/08/2026',
          price: 575.0,
          originalPrice: 575.0,
          quantity: 1,
          receiptImageUrl: 'https://example.com/receipt2.jpg',
        ),
        ProductPriceHistoryEntry(
          storeChain: 'جملة ماركت',
          branchName: 'لوران',
          receiptNumber: 'REC-303',
          receiptDate: '15/08/2026',
          price: 580.0,
          originalPrice: 600.0,
          quantity: 1,
          receiptImageUrl: '',
        ),
      ],
    );

    testWidgets('Renders ProductPriceHistoryDialog with fluid CustomScrollView and pinned TabBar', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Directionality(
                textDirection: TextDirection.rtl,
                child: ProductPriceHistoryDialog(product: mockProduct),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header details
      expect(find.text('جبنة ريكفورد بالوزن'), findsOneWidget);
      expect(find.text('2300302000004'), findsOneWidget);
      expect(find.text('عام'), findsOneWidget);

      // Verify Alert Banner for competitor underpriced threat
      expect(find.text('إنذار كسر سعر لمنافس (سعر أرخص من أسواق فتح الله)'), findsOneWidget);

      // Verify Summary KPIs
      expect(find.text('الأرخص سعراً'), findsOneWidget);
      expect(find.text('الأعلى سعراً'), findsOneWidget);
      expect(find.textContaining('فارق السعر'), findsOneWidget);
      expect(find.text('مرات الرصد بالفواتير:'), findsOneWidget);

      // Verify Enterprise Retail Chains Pricing section
      expect(find.text('تسعير السلاسل والمؤسسات التجارية المعتمدة:'), findsOneWidget);
      expect(find.text('أسواق فتح الله'), findsWidgets);
      expect(find.text('جملة ماركت'), findsWidgets);

      // Verify Pinned TabBar with both tabs
      expect(find.text('سجل تغيرات وتعديلات الأسعار'), findsOneWidget);
      expect(find.text('كافة الفواتير المرصودة (3)'), findsOneWidget);

      // Tab 1 (Price evolution) is active initially
      expect(find.text('السعر الساري'), findsOneWidget);

      // Switch to Tab 2: "كافة الفواتير المرصودة (3)"
      await tester.tap(find.text('كافة الفواتير المرصودة (3)'));
      await tester.pumpAndSettle();

      // Verify that raw receipts audit stream renders all 3 receipts with full details
      expect(find.text('#REC-101'), findsOneWidget);
      expect(find.text('#REC-202'), findsOneWidget);
      expect(find.text('#REC-303'), findsOneWidget);

      // Verify quantities and branches rendered
      expect(find.textContaining('سموحة'), findsOneWidget);
      expect(find.textContaining('جناكليس'), findsOneWidget);
      expect(find.textContaining('لوران'), findsOneWidget);

      // Verify close button
      expect(find.text('إغلاق'), findsOneWidget);
    });

    testWidgets('Scrolls smoothly down and up without overflow or rigid hold exceptions', (tester) async {
      tester.view.physicalSize = const Size(800, 600); // Compact viewport
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Directionality(
                textDirection: TextDirection.rtl,
                child: ProductPriceHistoryDialog(product: mockProduct),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll CustomScrollView down to reveal and pin the TabBar
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();

      // Verify TabBar is visible and pinned
      expect(find.text('كافة الفواتير المرصودة (3)'), findsOneWidget);

      // Switch to raw receipts tab
      await tester.tap(find.text('كافة الفواتير المرصودة (3)'));
      await tester.pumpAndSettle();

      // Verify receipt items are visible after scrolling
      expect(find.text('#REC-101'), findsOneWidget);
    });
  });
}
