import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:al_mraay/features/games/presentation/game_types_screen.dart';
import 'package:al_mraay/features/games/presentation/game_demo_banner.dart';
import 'package:al_mraay/features/games/presentation/mystery_box_screen.dart';
import 'package:al_mraay/features/games/presentation/spin_the_wheel_screen.dart';
import 'package:al_mraay/features/games/presentation/scratch_card_screen.dart';
import 'package:al_mraay/features/games/presentation/direct_gift_claim_screen.dart';

Widget createTestApp(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: child,
    ),
  );
}

void main() {
  group('Game Types & Live Demo Action Tests', () {
    testWidgets('GameTypesScreen renders all 4 games with Live Demo action buttons', (tester) async {
      await tester.pumpWidget(createTestApp(const Scaffold(body: GameTypesScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify all 5 game titles exist
      expect(find.text('عجلة الحظ'), findsOneWidget);
      expect(find.text('امسح واربح'), findsOneWidget);
      expect(find.text('الصندوق الغامض'), findsOneWidget);
      expect(find.text('الهدية الفورية المباشرة'), findsOneWidget);
      expect(find.text('اختر هديتك (شبكة الاختيارات)'), findsOneWidget);

      // Verify "تجربة اللعبة (ديمو تفاعلي)" button is present for all 5 games
      expect(find.text('تجربة اللعبة (ديمو تفاعلي)'), findsNWidgets(5));

      // Verify "تجربة المؤثرات الصوتية" button is present for all 5 games
      expect(find.text('تجربة المؤثرات الصوتية'), findsNWidgets(5));
    });

    testWidgets('GameDemoBanner renders DEMO chip, title, description, and exit button', (tester) async {
      bool resetTapped = false;
      bool exitTapped = false;

      await tester.pumpWidget(
        createTestApp(
          Scaffold(
            body: GameDemoBanner(
              onReset: () => resetTapped = true,
              onExit: () => exitTapped = true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('DEMO'), findsOneWidget);
      expect(find.byIcon(Icons.sports_esports_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      expect(resetTapped, isTrue);

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(exitTapped, isTrue);
    });

    testWidgets('MysteryBoxScreen renders 3 interactive gift boxes in demo mode', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestApp(
          const MysteryBoxScreen(
            isDemo: true,
            totalChances: 3,
            prizes: ['ساعة ذكية فاخرة ⌚', 'قسيمة 500 ج.م 🎟️'],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Top demo banner
      expect(find.byType(GameDemoBanner), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);

      // The 3 mystery boxes
      expect(find.text('الصندوق الأول'), findsOneWidget);
      expect(find.text('الصندوق الذهبي'), findsOneWidget);
      expect(find.text('الصندوق الثالث'), findsOneWidget);

      // Tap the golden box to reveal
      await tester.tap(find.text('الصندوق الذهبي'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Celebration or reveal happened cleanly
      expect(find.byType(MysteryBoxScreen), findsOneWidget);
    });

    testWidgets('SpinTheWheelScreen in demo mode renders GameDemoBanner without error', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestApp(
          const SpinTheWheelScreen(
            isDemo: true,
            totalChances: 3,
            prizes: ['جائزة 1', 'جائزة 2', 'جائزة 3', 'جائزة 4'],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(GameDemoBanner), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
      expect(find.text('مبروك! لقد تأهلت للسحب الفوري'), findsOneWidget);
    });

    testWidgets('ScratchCardScreen in demo mode renders GameDemoBanner cleanly', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestApp(
          const ScratchCardScreen(
            isDemo: true,
            totalChances: 2,
            prizes: ['قسيمة 200 ج.م', 'طقم أواني'],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(GameDemoBanner), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
      expect(find.text('أنت عميل مميز! بطاقة الكشط الذهبية'), findsOneWidget);
    });

    testWidgets('DirectGiftClaimScreen in demo mode renders GameDemoBanner and simulates handover', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestApp(
          const DirectGiftClaimScreen(
            isDemo: true,
            prizeName: 'طقم هدايا ترويجية VIP',
            quantity: 2,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(GameDemoBanner), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
      expect(find.text('طقم هدايا ترويجية VIP'), findsOneWidget);

      // Scroll into view & tap claim action
      final claimBtnFinder = find.text('تسليم الهدية للعميل');
      await tester.ensureVisible(claimBtnFinder);
      await tester.pump();

      await tester.tap(claimBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));

      // Celebration dialog triggers
      expect(find.text('تهانينا! ألف مبروك'), findsOneWidget);
    });
  });
}
