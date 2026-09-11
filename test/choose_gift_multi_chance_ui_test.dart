import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/games/presentation/choose_gift_screen.dart';

void main() {
  testWidgets('ChooseGiftScreen displays clear multi-chance indicators and round status', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ChooseGiftScreen(
            totalChances: 2,
            isDemo: true,
            prizes: [
              'كيس مكرونة ايزى باستا ترافيل',
              'كيس مكرونة ايزى باستا مبكبكة',
              'كيس مكرونة ايزى باستا هالبينو',
              'لانش بوكس',
              'زجاجة مياه',
              'مقلمة',
            ],
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    // Verify prominent total wins counter badge is visible
    expect(find.textContaining('عدد مرات الفوز: مرتان (هديتان)'), findsOneWidget);

    // Verify current round headline
    expect(find.textContaining('الفرصة الحالية: اختيار الهدية رقم (1) من إجمالي (2) هدايا'), findsOneWidget);

    // Verify step badges
    expect(find.textContaining('الهدية 1: اختر الآن 👈'), findsOneWidget);
    expect(find.textContaining('الهدية 2: في الانتظار ⏳'), findsOneWidget);

    // Tap the first gift
    await tester.tap(find.text('كيس مكرونة ايزى باستا ترافيل'));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify selection pill on card reflects current round
    expect(find.textContaining('تم الاختيار (فرصة 1) ✓'), findsOneWidget);

    // Verify bottom confirm bar reflects chance 1 of 2
    expect(find.textContaining('تأكيد الهدية (1 من 2)'), findsOneWidget);
  });
}
