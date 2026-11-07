import 'package:al_mraay/features/games/presentation/choose_gift_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('consuming rounds stay visible while the open round shows only its gift', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('ar'),
          home: ChooseGiftScreen(
            totalChances: 3,
            isDemo: true,
            prizes: ['قسيمة 150'],
            roundPrizeNames: [
              ['قسيمة 150'],
              ['قسيمة 150'],
              ['قسيمة 100'],
            ],
            roundGiftIds: [
              ['gift-500'],
              ['gift-500'],
              ['gift-350'],
            ],
            roundUnitValues: [
              [150],
              [150],
              [100],
            ],
            roundTierMinSpends: [500, 500, 350],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('من إجمالي (3) هدايا — شريحة 500'), findsOneWidget);
    expect(find.text('قسيمة 150'), findsOneWidget);
    expect(find.text('قسيمة 100'), findsNothing);
    expect(find.textContaining('الجولة 3 — شريحة 350: قسيمة 100'), findsOneWidget);
    expect(find.textContaining('الجولة 2 — شريحة 500: قسيمة 150'), findsOneWidget);
  });
}
