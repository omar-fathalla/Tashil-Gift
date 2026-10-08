import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/widgets/m3_button_groups.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Campaign Reports Date & Export Bar Layout Tests', () {
    testWidgets('Renders unified single-row layout on wide desktop displays (>= 720px)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final strings = AppStrings('ar');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 720;
                  expect(isWide, isTrue);

                  return Row(
                    children: [
                      // Quick Toggle Group: compact natural size
                      M3ConnectedButtonGroup<String>(
                        height: 38,
                        borderRadius: 12,
                        isExpanded: false,
                        showCheckmark: false,
                        segments: [
                          M3ButtonSegment<String>(
                            value: 'ALL',
                            label: strings.totalLabel,
                            icon: Icons.analytics_rounded,
                            badgeText: '473',
                          ),
                          M3ButtonSegment<String>(
                            value: 'DAYS',
                            label: strings.daysLabel,
                            icon: Icons.calendar_today_rounded,
                          ),
                        ],
                        selectedValue: 'ALL',
                        onSelected: (_) {},
                      ),
                      const SizedBox(width: 8),
                      // Date Navigator
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton.filledTonal(
                            icon: const Icon(Icons.chevron_right_rounded, size: 18),
                            onPressed: () {},
                          ),
                          const SizedBox(width: 6),
                          Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: const Row(
                              children: [
                                Icon(Icons.calendar_month_rounded, size: 17),
                                SizedBox(width: 8),
                                Text('اختر اليوم'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.chevron_left_rounded, size: 18),
                            onPressed: null,
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Export Buttons
                      FilledButton.tonalIcon(
                        onPressed: () {},
                        icon: const Icon(Icons.table_chart_rounded, size: 16),
                        label: Text(strings.excelBtn),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () {},
                        icon: const Icon(Icons.description_rounded, size: 16),
                        label: Text(strings.csvBtn),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text(strings.totalLabel), findsOneWidget);
      expect(find.text('473'), findsOneWidget);
      expect(find.text(strings.daysLabel), findsOneWidget);
      expect(find.text('اختر اليوم'), findsOneWidget);
      expect(find.text(strings.excelBtn), findsOneWidget);
      expect(find.text(strings.csvBtn), findsOneWidget);
    });
  });
}
