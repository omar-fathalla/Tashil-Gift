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
    expect(find.textContaining('تأكيد الهدية'), findsNothing);

    // Tap on the first gift
    await tester.tap(find.text(samplePrizes[0]));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify confirm bar is now visible
    expect(find.textContaining('تأكيد الهدية'), findsOneWidget);
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
}
