import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/chain_product_model.dart';
import 'package:al_mraay/features/admin/presentation/widgets/chain_products_matrix_table.dart';

void main() {
  group('ChainProductsMatrixTable Dual-Pane & Omni-Chain Layout Tests', () {
    final mockProducts = [
      ChainProductItem(
        id: '6221155122926',
        name: 'اكس اسبراي بلاك نايت 150 مل',
        barcode: '6221155122926',
        brand: 'Axe',
        category: 'مزيلات عرق',
        latestPricesByChain: {
          'أسواق فتح الله': 170.0,
          'جملة ماركت': 140.0,
          'هايبر وان': 155.0,
          'لولو هايبرماركت': 165.0,
        },
      ),
      ChainProductItem(
        id: '6221155611529',
        name: 'ريكسونا رول اون حريمي خوخ وعشب الليمون',
        barcode: '6221155611529',
        brand: 'Rexona',
        category: 'مزيلات عرق',
        latestPricesByChain: {
          'أسواق فتح الله': 69.0,
          'جملة ماركت': 34.50,
          'بيت الجملة': 67.0,
        },
      ),
      ChainProductItem(
        id: '622014354342',
        name: 'جهينه زبادي طبيعي 105 جم (9+3)',
        barcode: '622014354342',
        brand: 'عام',
        category: 'منتجات استهلاكية',
        latestPricesByChain: {
          'أسواق فتح الله': 99.0,
          'جملة ماركت': 78.0,
          'كارفور': 85.0,
        },
      ),
    ];

    final distinctChains = ['أسواق فتح الله', 'جملة ماركت', 'هايبر وان', 'لولو هايبرماركت', 'بيت الجملة', 'كارفور'];

    testWidgets('ChainProductsMatrixTable renders pinned baseline and scrollable competitors side-by-side', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Directionality(
                textDirection: TextDirection.rtl,
                child: ChainProductsMatrixTable(
                  products: mockProducts,
                  distinctChains: distinctChains,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Table Toolbar
      expect(find.text('مصفوفة الأسعار المقارنة'), findsOneWidget);
      expect(find.text('3 صنف'), findsOneWidget);

      // Verify Pinned Header (Product, Brand, Fathalla Baseline)
      expect(find.text('المنتج / الباركود'), findsOneWidget);
      expect(find.text('العلامة'), findsOneWidget);
      expect(find.text('أسواق فتح الله (المرجع)'), findsOneWidget);

      // Verify Product names rendered
      expect(find.text('اكس اسبراي بلاك نايت 150 مل'), findsOneWidget);
      expect(find.text('ريكسونا رول اون حريمي خوخ وعشب الليمون'), findsOneWidget);

      // Verify Fathalla baseline prices
      expect(find.text('170 ج.م'), findsOneWidget);
      expect(find.text('69 ج.م'), findsOneWidget);
      expect(find.text('99 ج.م'), findsOneWidget);

      // Verify Competitors columns rendered in scrollable pane
      expect(find.text('جملة ماركت'), findsWidgets);
      expect(find.text('هايبر وان'), findsWidgets);
      expect(find.text('كارفور'), findsWidgets);

      // Verify Competitor underpriced threat badges
      expect(find.textContaining('جملة ماركت أرخص بـ'), findsWidgets);
    });

    testWidgets('Toggling show all registered chains updates competitor columns count', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Directionality(
                textDirection: TextDirection.rtl,
                child: ChainProductsMatrixTable(
                  products: mockProducts,
                  distinctChains: distinctChains,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Default has "كافة السلاسل المنافسة (16)" active
      expect(find.text('كافة السلاسل المنافسة (16)'), findsOneWidget);

      // Tap to toggle to "السلاسل النشطة فقط"
      await tester.tap(find.text('كافة السلاسل المنافسة (16)'));
      await tester.pumpAndSettle();

      expect(find.text('السلاسل النشطة فقط'), findsOneWidget);
    });

    testWidgets('ChainProductsMatrixTable renders Head-to-Head 1-on-1 comparison correctly', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Directionality(
                textDirection: TextDirection.rtl,
                child: ChainProductsMatrixTable(
                  products: mockProducts,
                  distinctChains: distinctChains,
                  isHeadToHead: true,
                  anchorChain: 'أسواق فتح الله',
                  comparisonChain: 'جملة ماركت',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Pinned header shows baseline chain
      expect(find.text('أسواق فتح الله (المرجع)'), findsOneWidget);

      // Pane B shows comparison chain
      expect(find.text('جملة ماركت'), findsWidgets);

      // Pane B does not show other competitors like Hyper One or Carrefour in 1-on-1 mode
      expect(find.text('هايبر وان'), findsNothing);
      expect(find.text('كارفور'), findsNothing);

      // Head-to-Head column header is rendered
      expect(find.text('المقارنة المباشرة'), findsOneWidget);
    });
  });
}
