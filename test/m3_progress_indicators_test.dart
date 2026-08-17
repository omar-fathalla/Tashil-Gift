import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:al_mraay/core/widgets/m3_progress_indicators.dart';
import 'package:al_mraay/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('M3LinearProgress Widget Tests', () {
    testWidgets('Renders determinate progress bar', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: M3LinearProgress(
              value: 0.65,
              height: 10.0,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(M3LinearProgress), findsOneWidget);
    });

    testWidgets('Renders indeterminate progress bar when value is null', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: M3LinearProgress(
              value: null,
              height: 8.0,
            ),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  group('M3ProgressCard Widget Tests', () {
    testWidgets('Renders progress card with real-time percentage and counter', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: M3ProgressCard(
              title: 'جاري حفظ المنتجات في الفايربيز',
              subtitle: 'يتم الآن ترحيل الحزمة الثانية...',
              progress: 0.50,
              currentCount: 400,
              totalCount: 800,
              icon: Icons.cloud_upload_rounded,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('جاري حفظ المنتجات في الفايربيز'), findsOneWidget);
      expect(find.text('يتم الآن ترحيل الحزمة الثانية...'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('تم إنجاز 400 من 800 عنصر (50%)'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_upload_rounded), findsOneWidget);
    });

    testWidgets('Renders complete state when progress reaches 1.0 (100%)', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: M3ProgressCard(
              title: 'اكتملت عملية الحفظ',
              progress: 1.0,
              currentCount: 854,
              totalCount: 854,
              icon: Icons.cloud_upload_rounded,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('100%'), findsOneWidget);
      expect(find.text('تم إنجاز 854 من 854 عنصر (100%)'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('Triggers cancel callback when cancel button is clicked', (WidgetTester tester) async {
      bool cancelPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: M3ProgressCard(
              title: 'جاري المعالجة',
              progress: 0.3,
              currentCount: 30,
              totalCount: 100,
              onCancel: () {
                cancelPressed = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('إلغاء'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      expect(cancelPressed, isTrue);
    });
  });
}
