import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/widgets/m3_date_range_picker_dialog.dart';

void main() {
  group('M3DateRangePickerDialog Tests', () {
    testWidgets('Renders M3 Date Range Picker Dialog with proper structure and badges', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await showM3DateRangePicker(
                      context: context,
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2030),
                      isAr: true,
                    );
                  },
                  child: const Text('Open Picker'),
                );
              },
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Verify title & badges
      expect(find.text('تحديد نطاق التاريخ'), findsOneWidget);
      expect(find.text('تاريخ البداية (من)'), findsOneWidget);
      expect(find.text('تاريخ النهاية (إلى)'), findsOneWidget);
      expect(find.text('اختر البداية'), findsOneWidget);

      // Verify Save button is visible and clear at the bottom
      expect(find.text('حفظ النطاق'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
    });

    testWidgets('Validates missing start date when user clicks Save without selection', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => showM3DateRangePicker(
                    context: context,
                    firstDate: DateTime(2023),
                    lastDate: DateTime(2030),
                    isAr: true,
                  ),
                  child: const Text('Open Picker'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Click Save Range with nothing selected
      await tester.tap(find.text('حفظ النطاق'));
      await tester.pumpAndSettle();

      // Expect validation error
      expect(find.text('برجاء تحديد تاريخ البداية والنهاية أولاً'), findsOneWidget);
    });

    testWidgets('Validates missing end date if user selects start date and clicks Save', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => showM3DateRangePicker(
                    context: context,
                    initialStartDate: DateTime(2026, 9, 26),
                    // initialEndDate is null
                    firstDate: DateTime(2023),
                    lastDate: DateTime(2030),
                    isAr: true,
                  ),
                  child: const Text('Open Picker'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Start date is set, but end date is null
      expect(find.text('26 سبتمبر 2026'), findsOneWidget);
      expect(find.text('اختر النهاية...'), findsOneWidget);

      // Click Save Range
      await tester.tap(find.text('حفظ النطاق'));
      await tester.pumpAndSettle();

      // Expect specific error message required by user:
      expect(
        find.text('لم تقم بتحديد تاريخ النهاية! برجاء اختيار تاريخ النهاية لاكتمال النطاق.'),
        findsOneWidget,
      );
    });

    testWidgets('Successfully saves and returns DateTimeRange when both dates are selected', (tester) async {
      DateTimeRange? returnedRange;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    returnedRange = await showM3DateRangePicker(
                      context: context,
                      initialStartDate: DateTime(2026, 9, 26),
                      initialEndDate: DateTime(2026, 10, 3),
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2030),
                      isAr: true,
                    );
                  },
                  child: const Text('Open Picker'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      expect(find.text('26 سبتمبر 2026'), findsOneWidget);
      expect(find.text('3 أكتوبر 2026'), findsOneWidget);

      // Click Save Range
      await tester.tap(find.text('حفظ النطاق'));
      await tester.pumpAndSettle();

      // Dialog closed and returned valid range
      expect(returnedRange, isNotNull);
      expect(returnedRange!.start, equals(DateTime(2026, 9, 26)));
      expect(returnedRange!.end, equals(DateTime(2026, 10, 3)));
    });
  });
}
