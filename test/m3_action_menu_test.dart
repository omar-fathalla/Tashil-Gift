import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:al_mraay/core/widgets/m3_action_menu.dart';
import 'package:al_mraay/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('M3ActionMenu Widget & Integration Tests', () {
    testWidgets('Renders standard anchor icon button with 48x48dp touch target', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ActionMenu(
                tooltip: 'خيارات الفاتورة',
                children: [
                  Builder(
                    builder: (context) => M3ActionMenu.item(
                      context: context,
                      label: 'عرض التفاصيل',
                      icon: Icons.visibility_outlined,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final iconBtnFinder = find.byType(IconButton);
      expect(iconBtnFinder, findsOneWidget);

      final Size size = tester.getSize(iconBtnFinder);
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('Tapping anchor button opens M3ActionMenu and renders items', (WidgetTester tester) async {
      bool itemTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ActionMenu(
                children: [
                  Builder(
                    builder: (context) => M3ActionMenu.item(
                      context: context,
                      label: 'تحميل الصورة',
                      icon: Icons.download_rounded,
                      onPressed: () {
                        itemTapped = true;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Before tap, menu items should not be visible
      expect(find.text('تحميل الصورة'), findsNothing);

      // Tap anchor button to open menu
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Menu item should now be visible
      expect(find.text('تحميل الصورة'), findsOneWidget);

      // Tap menu item
      await tester.tap(find.text('تحميل الصورة'));
      await tester.pumpAndSettle();

      expect(itemTapped, isTrue);
    });

    testWidgets('Custom anchorBuilder renders custom trigger and opens menu', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ActionMenu(
                anchorBuilder: (context, controller, child) {
                  return ElevatedButton(
                    onPressed: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                    child: const Text('افتح القائمة'),
                  );
                },
                children: [
                  Builder(
                    builder: (context) => M3ActionMenu.item(
                      context: context,
                      label: 'خيار مخصص',
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('افتح القائمة'), findsOneWidget);
      expect(find.text('خيار مخصص'), findsNothing);

      await tester.tap(find.text('افتح القائمة'));
      await tester.pumpAndSettle();

      expect(find.text('خيار مخصص'), findsOneWidget);
    });

    testWidgets('isDestructive: true styles item in colorScheme.error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ActionMenu(
                children: [
                  Builder(
                    builder: (context) => M3ActionMenu.item(
                      context: context,
                      label: 'حذف نهائي',
                      icon: Icons.delete_outline_rounded,
                      isDestructive: true,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text('حذف نهائي'));
      expect(textWidget.style?.color, AppTheme.lightTheme.colorScheme.error);

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.delete_outline_rounded));
      expect(iconWidget.color, AppTheme.lightTheme.colorScheme.error);
    });

    testWidgets('isSelected: true displays checkmark icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ActionMenu(
                children: [
                  Builder(
                    builder: (context) => M3ActionMenu.item(
                      context: context,
                      label: 'الفرع النشط',
                      isSelected: true,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('shortcutText displays trailing shortcut badge', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ActionMenu(
                children: [
                  Builder(
                    builder: (context) => M3ActionMenu.item(
                      context: context,
                      label: 'تصدير',
                      shortcutText: 'Ctrl+E',
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('Ctrl+E'), findsOneWidget);
    });

    testWidgets('Submenu arrows in RTL (Arabic) point left', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: M3ActionMenu(
                  children: [
                    Builder(
                      builder: (context) => M3ActionMenu.submenu(
                        context: context,
                        label: 'المزيد من الخيارات',
                        children: [
                          M3ActionMenu.item(
                            context: context,
                            label: 'خيار فرعي',
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // In RTL, the chevron MUST point left
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('Submenu arrows in LTR (English) point right', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(
              body: Center(
                child: M3ActionMenu(
                  children: [
                    Builder(
                      builder: (context) => M3ActionMenu.submenu(
                        context: context,
                        label: 'More Options',
                        children: [
                          M3ActionMenu.item(
                            context: context,
                            label: 'Sub Item',
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // In LTR, the chevron MUST point right
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    });

    testWidgets('M3ActionMenu.header and divider render correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ActionMenu(
                children: [
                  Builder(
                    builder: (context) => M3ActionMenu.header(
                      context: context,
                      title: 'الفئات الرئيسية',
                      icon: Icons.category_outlined,
                    ),
                  ),
                  M3ActionMenu.divider(),
                  Builder(
                    builder: (context) => M3ActionMenu.item(
                      context: context,
                      label: 'عنصر 1',
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('الفئات الرئيسية'), findsOneWidget);
      expect(find.byIcon(Icons.category_outlined), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('Disabled item (enabled: false) cannot be tapped', (WidgetTester tester) async {
      bool itemTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ActionMenu(
                children: [
                  Builder(
                    builder: (context) => M3ActionMenu.item(
                      context: context,
                      label: 'معطل',
                      enabled: false,
                      onPressed: () {
                        itemTapped = true;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('معطل'));
      await tester.pumpAndSettle();

      expect(itemTapped, isFalse);
    });

    testWidgets('M3ActionMenu.header with badge renders title, icon, and badge cleanly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ActionMenu(
                minWidth: 460,
                maxWidth: 460,
                crossAxisUnconstrained: false,
                children: [
                  Builder(
                    builder: (context) => M3ActionMenu.header(
                      context: context,
                      title: 'الفعاليات والمهرجانات',
                      icon: Icons.campaign_rounded,
                      badge: '13 حملة',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('الفعاليات والمهرجانات'), findsOneWidget);
      expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);
      expect(find.text('13 حملة'), findsOneWidget);
    });

    testWidgets('M3ActionMenu.item with subtitle and trailing widget renders without overflow', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: M3ActionMenu(
                minWidth: 480,
                maxWidth: 480,
                crossAxisUnconstrained: false,
                children: [
                  Builder(
                    builder: (context) => M3ActionMenu.item(
                      context: context,
                      label: 'Back To School Heinz',
                      subtitle: 'هاينز • كارفور مصر • هايبر وان • جملة ماركت • أوسكار ستورز',
                      icon: Icons.campaign_rounded,
                      isSelected: true,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        child: const Text('174 فاتورة'),
                      ),
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('Back To School Heinz'), findsOneWidget);
      expect(find.text('هاينز • كارفور مصر • هايبر وان • جملة ماركت • أوسكار ستورز'), findsOneWidget);
      expect(find.text('174 فاتورة'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });
}
