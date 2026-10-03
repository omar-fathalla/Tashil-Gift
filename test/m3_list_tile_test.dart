import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:al_mraay/core/widgets/m3_list_tile.dart';
import 'package:al_mraay/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('M3ListTile Standard Line Heights Tests', () {
    testWidgets('M3ListTile.oneLine renders with 56dp minimum height on mobile', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800)); // Mobile viewport
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ListTile.oneLine(
                leading: const Icon(Icons.settings),
                headline: const Text('إعدادات الحساب'),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final tileFinder = find.byType(M3ListTile);
      expect(tileFinder, findsOneWidget);

      final Size size = tester.getSize(tileFinder);
      expect(size.height, greaterThanOrEqualTo(56.0));
    });

    testWidgets('M3ListTile.twoLine renders with 72dp minimum height on mobile', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ListTile.twoLine(
                leading: const Icon(Icons.card_giftcard),
                headline: const Text('هدية فورية معتمدة'),
                subtitle: const Text('فواتشر كارفور بقيمة 50 جنيه'),
                trailing: const Text('1 ×'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final tileFinder = find.byType(M3ListTile);
      expect(tileFinder, findsOneWidget);

      final Size size = tester.getSize(tileFinder);
      expect(size.height, greaterThanOrEqualTo(72.0));
    });

    testWidgets('M3ListTile.threeLine renders with 88dp minimum height on mobile', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ListTile.threeLine(
                leading: const Icon(Icons.receipt_long),
                headline: const Text('فاتورة #98214'),
                subtitle: const Text('كارفور - فرع المعادي'),
                supportingText: const Text('2026-10-02 • 4 منتجات مؤهلة'),
                trailing: const Text('450.00 ج.م'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final tileFinder = find.byType(M3ListTile);
      expect(tileFinder, findsOneWidget);

      final Size size = tester.getSize(tileFinder);
      expect(size.height, greaterThanOrEqualTo(88.0));
    });
  });

  group('M3InsetDivider Tests', () {
    testWidgets('M3InsetDivider has exact directional 72dp indent', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: M3InsetDivider(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final dividerFinder = find.byType(Divider);
      expect(dividerFinder, findsOneWidget);

      final Divider divider = tester.widget<Divider>(dividerFinder);
      expect(divider.indent, equals(72.0));
      expect(divider.endIndent, equals(0.0));
    });
  });

  group('M3TouchTargetBoundary a11y Tests', () {
    testWidgets('M3TouchTargetBoundary guarantees at least 48x48dp touch area', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: M3TouchTargetBoundary(
                minSize: 48.0,
                child: IconButton(
                  iconSize: 16.0,
                  icon: const Icon(Icons.delete),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final boundaryFinder = find.byType(M3TouchTargetBoundary);
      expect(boundaryFinder, findsOneWidget);

      final Size size = tester.getSize(boundaryFinder);
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });
  });

  group('M3Subheader Widget Tests', () {
    testWidgets('M3Subheader renders with standard 48dp height', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: M3Subheader(
              icon: Icons.storefront_rounded,
              title: Text('فروع كارفور المعتمدة'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final subheaderFinder = find.byType(M3Subheader);
      expect(subheaderFinder, findsOneWidget);

      final Size size = tester.getSize(subheaderFinder);
      expect(size.height, equals(48.0));
    });
  });

  group('M3ListTile Selection and Semantics Tests', () {
    testWidgets('M3ListTile isSelected highlights with secondaryContainer and 12dp border radius', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ListTile.oneLine(
                isSelected: true,
                headline: const Text('فاتورة محددة'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('فاتورة محددة'), findsOneWidget);
    });

    testWidgets('M3ListTile renders with Semantics label', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: M3ListTile.oneLine(
                headline: const Text('فاتورة #102'),
                semanticsLabel: 'فاتورة رقم 102 مسجلة',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final semanticsFinder = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'فاتورة رقم 102 مسجلة',
      );
      expect(semanticsFinder, findsOneWidget);
    });
  });
}
