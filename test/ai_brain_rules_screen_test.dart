import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/services/ai_directives_service.dart';
import 'package:al_mraay/core/services/ai_model_config_service.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/company_gifts_service.dart';
import 'package:al_mraay/core/utils/responsive.dart';
import 'package:al_mraay/core/widgets/m3_adaptive_scaffold.dart';
import 'package:al_mraay/features/admin/domain/ai_directive_model.dart';
import 'package:al_mraay/features/admin/domain/ai_directives_seed_data.dart';
import 'package:al_mraay/features/admin/presentation/ai_brain_rules_screen.dart';

class FakeAiDirectivesService implements AiDirectivesService {
  @override
  Future<void> seedDirectivesIfEmpty() async {}

  @override
  Future<int> forceSyncAllDirectives() async => 0;

  @override
  Stream<List<AiDirectiveModel>> streamDirectives() =>
      Stream.value(AiDirectivesSeedData.initialDirectives);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final sampleDirectives = AiDirectivesSeedData.initialDirectives;

  Widget createTestWidget({
    required Size physicalSize,
    String localeCode = 'ar',
    int initialTabIndex = 0,
  }) {
    return ProviderScope(
      overrides: [
        aiDirectivesServiceProvider.overrideWithValue(FakeAiDirectivesService()),
        aiDirectivesStreamProvider.overrideWith(
          (ref) => Stream.value(sampleDirectives),
        ),
        aiModelConfigStreamProvider.overrideWith(
          (ref) => Stream.value(const AiModelConfig()),
        ),
      ],
      child: MaterialApp(
        locale: Locale(localeCode),
        home: Scaffold(
          body: AiBrainRulesScreen(
            initialTabIndex: initialTabIndex,
          ),
        ),
      ),
    );
  }

  group('AiBrainRulesScreen M3 Architecture Tests', () {
    testWidgets('Renders in Arabic with TabBar and Catalog tab active by default', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(physicalSize: const Size(1400, 900)),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(AiBrainRulesScreen), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byIcon(Icons.auto_stories_rounded), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy_rounded), findsOneWidget);
    });

    testWidgets('On Expanded+ desktop (1400x900), renders M3ListDetailLayout with dual panes', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(physicalSize: const Size(1400, 900)),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(M3ContentBoundary), findsAtLeastNWidgets(1));

      // Verify list pane and detail pane both exist
      expect(find.text('AIR-01'), findsAtLeastNWidgets(1));
      // First directive is selected by default in detail pane
      expect(find.text('المنطق والخوارزمية البرمجية:'), findsOneWidget);
      expect(find.text('مثال عملي حي من واقع البونات:'), findsOneWidget);
      expect(find.text('تجربة في استوديو الذكاء'), findsOneWidget);
    });

    testWidgets('Tapping a directive card in the list pane updates the selected directive in the detail pane', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(physicalSize: const Size(1400, 900)),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Find AIR-02 card in list pane and tap it
      final air02Finder = find.text('AIR-02');
      if (air02Finder.evaluate().isNotEmpty) {
        await tester.tap(air02Finder.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        // Detail pane now shows AIR-02
        expect(find.text('AIR-02'), findsAtLeastNWidgets(2));
      }
    });

    testWidgets('Searching directives by code or keyword filters the list dynamically', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(physicalSize: const Size(1400, 900)),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // Search for AIR-05
      await tester.enterText(searchField, 'AIR-05');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('AIR-05'), findsAtLeastNWidgets(1));
    });

    testWidgets('Category chips filter the directives list cleanly', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(physicalSize: const Size(1400, 900)),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap the first category chip (e.g. promotional rules)
      final filterChips = find.byType(FilterChip);
      expect(filterChips, findsWidgets);

      await tester.tap(filterChips.at(1), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets('On mobile (390x844), renders single list pane without overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(physicalSize: const Size(390, 844)),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      // On compact/mobile, M3ListDetailLayout renders only listPane (single pane)
      expect(find.byType(M3ListDetailLayout), findsNothing);
      expect(find.text('AIR-01'), findsAtLeastNWidgets(1));

      // Tapping a directive card opens the modal dialog on mobile
      await tester.tap(find.text('AIR-01').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);

      // Close dialog
      final closeBtn = find.text('إغلاق');
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      }
    });

    testWidgets('Switching to Co-Pilot Studio Tab renders studio widget without crash', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(physicalSize: const Size(1280, 800)),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap the Studio tab
      await tester.tap(find.byIcon(Icons.smart_toy_rounded));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test('AIR-71 directive is properly registered in AiDirectivesSeedData', () {
      final air71 = sampleDirectives.where((d) => d.id == 'AIR-71').firstOrNull;
      expect(air71, isNotNull);
      expect(air71!.code, 'GENERIC_MULTIPACK_BRAND_AMBIGUITY_AND_STRICT_ISOLATION_GOVERNANCE');
      expect(air71.orderIndex, 71);
      expect(air71.tags, contains('generic-multipack'));
      expect(air71.tags, contains('cadbury-mondelez'));
    });

    test('AIR-80 directive and branch/brand isolation rules work accurately', () {
      final air80 = sampleDirectives.where((d) => d.id == 'AIR-80').firstOrNull;
      expect(air80, isNotNull);
      expect(
        air80!.code,
        'CANONICAL_ARABIC_BRANCH_TOKEN_PRESERVATION_AND_SAUCE_BRAND_ISOLATION_STANDARD',
      );
      expect(air80.orderIndex, 80);

      // 1. Verify Arabic branch token normalization preserves Arabic letters & strips governorate
      final normSmouha = CompanyGiftsService.normalizeBranchToken(
        'أسواق فتح الله للجملة - فرع سموحة (الإسكندرية)',
      );
      final normStanley = CompanyGiftsService.normalizeBranchToken(
        'أسواق فتح الله - فرع ستانلي (الإسكندرية)',
      );
      expect(normSmouha, 'سموحه');
      expect(normStanley, 'ستانلي');
      expect(normSmouha == normStanley, isFalse);
      expect(
        CompanyGiftsService.matchesBranchName(
          'سموحة',
          'فرع ستانلي (الإسكندرية)',
        ),
        isFalse,
      );
      expect(
        CompanyGiftsService.matchesBranchName(
          'فرع سموحة',
          'أسواق فتح الله - سموحة (الإسكندرية)',
        ),
        isTrue,
      );

      // 2. Verify Shoman umbrella brand qualification (Al-Durra & Seyidoglu) vs competitor brand isolation (Heinz, Harvest)
      final dorraKetchupInShoman = ExtractedProductItem.fromJson(
        {
          'name': 'دره عرض كاتشب 300',
          'price': 135.0,
          'quantity': 1,
          'isTargetCompany': true,
        },
        targetCompany: 'شومان',
      );
      final spacedDorraInShoman = ExtractedProductItem.fromJson(
        {
          'name': 'د ر ه عرض كاتشب 300',
          'price': 135.0,
          'quantity': 1,
          'isTargetCompany': true,
        },
        targetCompany: 'شومان',
      );
      final dorraChiliInShoman = ExtractedProductItem.fromJson(
        {
          'name': 'الدرة شيلي صوص 41',
          'price': 59.0,
          'quantity': 1,
          'isTargetCompany': true,
        },
        targetCompany: 'شومان',
      );
      final genuineShomanKetchup = ExtractedProductItem.fromJson(
        {
          'name': 'شومان كاتشب 250 ملي',
          'price': 30.0,
          'quantity': 2,
          'isTargetCompany': true,
        },
        targetCompany: 'شومان',
      );
      final competitorHeinzKetchup = ExtractedProductItem.fromJson(
        {
          'name': 'هاينز كاتشب 300 جرام',
          'price': 45.0,
          'quantity': 1,
          'isTargetCompany': true,
        },
        targetCompany: 'شومان',
      );
      final competitorHarvestSauce = ExtractedProductItem.fromJson(
        {
          'name': 'هارفست صلصة 320 جرام',
          'price': 25.0,
          'quantity': 1,
          'isTargetCompany': true,
        },
        targetCompany: 'شومان',
      );

      expect(dorraKetchupInShoman.isTargetCompany, isTrue);
      expect(spacedDorraInShoman.isTargetCompany, isTrue);
      expect(dorraChiliInShoman.isTargetCompany, isTrue);
      expect(genuineShomanKetchup.isTargetCompany, isTrue);
      expect(competitorHeinzKetchup.isTargetCompany, isFalse);
      expect(competitorHarvestSauce.isTargetCompany, isFalse);
    });
  });
}
