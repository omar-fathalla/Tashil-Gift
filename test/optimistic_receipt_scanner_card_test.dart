import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/widgets/optimistic_receipt_scanner_card.dart';
import 'package:al_mraay/core/utils/receipt_image_calibrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestCard({
    required int activePhase,
    required String statusText,
    CalibratedImageResult? calibrationResult,
    bool isCompleted = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: OptimisticReceiptScannerCard(
            activePhase: activePhase,
            statusText: statusText,
            calibrationResult: calibrationResult,
            isCompleted: isCompleted,
          ),
        ),
      ),
    );
  }

  group('OptimisticReceiptScannerCard Widget Tests', () {
    testWidgets('renders active laser scanner card with initial phase and status text',
        (tester) async {
      await tester.pumpWidget(
        buildTestCard(
          activePhase: 0,
          statusText: '1/3 جاري معايرة الصورة وضبط التباين محلياً...',
        ),
      );

      // Verify header and status text
      expect(find.text('المسح والمعالجة الذكية اللحظية'), findsOneWidget);
      expect(find.text('1/3 جاري معايرة الصورة وضبط التباين محلياً...'), findsOneWidget);

      // Verify 3 phase step labels
      expect(find.text('1. المعايرة محلياً'), findsOneWidget);
      expect(find.text('2. الذكاء الاصطناعي'), findsOneWidget);
      expect(find.text('3. استحقاق الجوائز'), findsOneWidget);
    });

    testWidgets('displays payload compression badge when calibrationResult is provided',
        (tester) async {
      final mockResult = CalibratedImageResult(
        bytes: Uint8List(0),
        originalSize: 4 * 1024 * 1024,
        calibratedSize: 800 * 1024,
        width: 1200,
        height: 1600,
        duration: Duration(milliseconds: 55),
      );

      await tester.pumpWidget(
        buildTestCard(
          activePhase: 1,
          statusText: '2/3 جاري قراءة وتدقيق الفاتورة بالذكاء الاصطناعي...',
          calibrationResult: mockResult,
        ),
      );

      // Verify compression badge is present with computed percentage
      expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
      expect(find.textContaining('تم تخفيض الحجم بنسبة'), findsOneWidget);
    });

    testWidgets('displays completed state with checkmark', (tester) async {
      await tester.pumpWidget(
        buildTestCard(
          activePhase: 3,
          statusText: 'تم اعتماد الفاتورة واستحقاق الجائزة!',
          isCompleted: true,
        ),
      );

      expect(find.text('اكتمل التدقيق بنجاح'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });
  });
}
