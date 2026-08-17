import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:al_mraay/core/widgets/m3_button_groups.dart';
import 'package:al_mraay/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('M3ConnectedButtonGroup Widget Tests', () {
    testWidgets('Renders all segments and updates on tap', (WidgetTester tester) async {
      String selected = 'opt1';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return M3ConnectedButtonGroup<String>(
                  selectedValue: selected,
                  onSelected: (val) {
                    setState(() => selected = val);
                  },
                  segments: const [
                    M3ButtonSegment(
                      value: 'opt1',
                      label: 'الخيار الأول',
                      icon: Icons.star,
                    ),
                    M3ButtonSegment(
                      value: 'opt2',
                      label: 'الخيار الثاني',
                      icon: Icons.favorite,
                      badgeText: 'جديد',
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Verify both segment labels are displayed
      expect(find.text('الخيار الأول'), findsOneWidget);
      expect(find.text('الخيار الثاني'), findsOneWidget);
      expect(find.text('جديد'), findsOneWidget);

      // Tap on second segment
      await tester.tap(find.text('الخيار الثاني'));
      await tester.pumpAndSettle();

      expect(selected, 'opt2');
    });

    testWidgets('M3MorphingActionButton triggers onPressed callback', (WidgetTester tester) async {
      bool wasPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: M3MorphingActionButton(
              onPressed: () => wasPressed = true,
              icon: Icons.bolt,
              label: 'زر تجريبي',
              isSelected: true,
            ),
          ),
        ),
      );

      expect(find.text('زر تجريبي'), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget);

      await tester.tap(find.text('زر تجريبي'));
      await tester.pumpAndSettle();

      expect(wasPressed, true);
    });
  });
}
