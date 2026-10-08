import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/widgets/m3_button_groups.dart';

void main() {
  group('M3ConnectedActionGroup Widget Tests', () {
    testWidgets('renders action items with correct labels and icons', (tester) async {
      bool screenTapped = false;
      bool settingsTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: M3ConnectedActionGroup(
                actions: [
                  M3ConnectedActionItem(
                    label: 'الشاشة',
                    icon: Icons.screenshot_monitor_rounded,
                    isPrimary: true,
                    onPressed: () => screenTapped = true,
                  ),
                  M3ConnectedActionItem(
                    label: 'إعدادات',
                    icon: Icons.tune_rounded,
                    onPressed: () => settingsTapped = true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('الشاشة'), findsOneWidget);
      expect(find.text('إعدادات'), findsOneWidget);
      expect(find.byIcon(Icons.screenshot_monitor_rounded), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      await tester.tap(find.text('الشاشة'));
      expect(screenTapped, isTrue);

      await tester.tap(find.text('إعدادات'));
      expect(settingsTapped, isTrue);
    });

    testWidgets('renders custom iconWidget during loading or testing state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: M3ConnectedActionGroup(
                actions: [
                  M3ConnectedActionItem(
                    label: 'اختبار الاتصال',
                    iconWidget: const SizedBox(
                      key: Key('loading_spinner'),
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    onPressed: null,
                  ),
                  M3ConnectedActionItem(
                    label: 'حفظ الإعدادات',
                    icon: Icons.check_circle_rounded,
                    isPrimary: true,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('اختبار الاتصال'), findsOneWidget);
      expect(find.text('حفظ الإعدادات'), findsOneWidget);
      expect(find.byKey(const Key('loading_spinner')), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });
  });
}
