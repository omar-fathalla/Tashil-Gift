import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/games/presentation/choose_gift_screen.dart';

void main() {
  testWidgets('ChooseGiftScreen renders grid of gifts and selects a gift', (WidgetTester tester) async {
    final samplePrizes = [
      'ساعة ذكية فاخرة ⌚',
      'قسيمة مشتريات 150 ج.م 🎟️',
      'سماعات لاسلكية Pro 🎧',
      'ماكينة قهوة اسبريسو ☕',
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ChooseGiftScreen(
            isDemo: true,
            totalChances: 1,
            prizes: samplePrizes,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify all gifts are rendered in the grid
    for (final prize in samplePrizes) {
      expect(find.text(prize), findsOneWidget);
    }

    // Verify confirm bar is NOT visible before selecting
    expect(find.text('تأكيد الهدية 🎁'), findsNothing);

    // Tap on the first gift
    await tester.tap(find.text(samplePrizes[0]));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify confirm bar is now visible
    expect(find.text('تأكيد الهدية 🎁'), findsOneWidget);
    expect(find.textContaining('تم الاختيار ✓'), findsOneWidget);
  });

  testWidgets('ChooseGiftScreen renders provided prizeImages and falls back to icon when image missing', (WidgetTester tester) async {
    final samplePrizes = [
      'كيس مكرونة ايزى باستا هالبينو',
      'لانش بوكس',
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ChooseGiftScreen(
            isDemo: true,
            totalChances: 1,
            prizes: samplePrizes,
            prizeImages: {
              'كيس مكرونة ايزى باستا هالبينو': 'https://example.com/jalapeno.png',
            },
          ),
        ),
      ),
    );

    await tester.pump();

    // Verify Image widget is rendered for the item with prizeImage
    expect(find.byType(Image), findsOneWidget);

    // Verify fallback Icon is rendered for the item without prizeImage
    expect(find.byIcon(Icons.card_giftcard_rounded), findsWidgets);
  });

  testWidgets('ChooseGiftScreen back button triggers confirmation dialog and allows staying or leaving', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));

    final samplePrizes = [
      'كيس مكرونة ايزى باستا هالبينو',
      'لانش بوكس',
    ];

    final observer = _TestNavObserver();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorObservers: [observer],
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => ChooseGiftScreen(
                        isDemo: true,
                        totalChances: 1,
                        prizes: samplePrizes,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pump(const Duration(milliseconds: 300));

    // Verify back button and cancel buttons are visible
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('إلغاء والعودة'), findsOneWidget);
    expect(find.text('عودة للفواتير'), findsOneWidget);

    // Tap back button
    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify confirmation dialog is visible
    expect(find.text('العودة لشاشة رفع الفواتير'), findsOneWidget);
    expect(find.textContaining('هل أنت متأكد من العودة دون اختيار أي هدية؟'), findsOneWidget);

    // Tap stay button
    await tester.tap(find.text('البقاء واختيار هدية'));
    await tester.pump(const Duration(milliseconds: 300));

    // Dialog should be dismissed and screenPopCount is 0
    expect(find.text('العودة لشاشة رفع الفواتير'), findsNothing);
    expect(observer.screenPopCount, equals(0));

    // Tap 'إلغاء والعودة' action
    await tester.tap(find.text('إلغاء والعودة'));
    await tester.pump(const Duration(milliseconds: 300));

    // Tap confirm exit button
    expect(find.text('نعم، إلغاء والعودة'), findsOneWidget);
    await tester.tap(find.text('نعم، إلغاء والعودة'));
    await tester.pump(const Duration(milliseconds: 300));

    // Screen should have popped
    expect(observer.screenPopCount, equals(1));
  });
}

class _TestNavObserver extends NavigatorObserver {
  int screenPopCount = 0;

  @override
  void didPop(Route route, Route? previousRoute) {
    if (route is MaterialPageRoute) {
      screenPopCount++;
    }
    super.didPop(route, previousRoute);
  }
}
