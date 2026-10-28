import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:al_mraay/core/constants/country_currency_config.dart';
import 'package:al_mraay/core/widgets/switch_point_branding.dart';
import 'package:al_mraay/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('CountryCurrencyConfig Unit Tests', () {
    test('Default country is Egypt (جمهورية مصر العربية) with EGP / ج.م', () {
      final defaultCountry = CountryCurrencyConfig.defaultCountry;
      expect(defaultCountry.code, 'EG');
      expect(defaultCountry.nameAr, 'مصر');
      expect(defaultCountry.fullNameAr, 'جمهورية مصر العربية');
      expect(defaultCountry.flagEmoji, '🇪🇬');
      expect(defaultCountry.currencyCode, 'EGP');
      expect(defaultCountry.currencySymbol, 'ج.م');
      expect(defaultCountry.currencyNameAr, 'الجنيه المصري');
    });

    test('Supported countries list contains 8 countries with Egypt as first', () {
      final list = CountryCurrencyConfig.supportedCountries;
      expect(list.length, 8);
      expect(list.first.code, 'EG');
      expect(list.map((c) => c.code).toSet(), containsAll(['EG', 'SA', 'AE', 'KW', 'QA', 'BH', 'OM', 'JO']));
    });

    test('findByCode resolves valid codes and falls back to Egypt for unknown codes', () {
      final sa = CountryCurrencyConfig.findByCode('SA');
      expect(sa.nameAr, 'السعودية');
      expect(sa.currencySymbol, 'ر.س');

      final aeLower = CountryCurrencyConfig.findByCode('ae');
      expect(aeLower.nameAr, 'الإمارات');
      expect(aeLower.currencySymbol, 'د.إ');

      final unknown = CountryCurrencyConfig.findByCode('XX');
      expect(unknown.code, 'EG');
    });

    test('findByCurrencyCode resolves valid currency codes and falls back to Egypt', () {
      final sar = CountryCurrencyConfig.findByCurrencyCode('SAR');
      expect(sar.nameAr, 'السعودية');
      expect(sar.currencySymbol, 'ر.س');

      final kwd = CountryCurrencyConfig.findByCurrencyCode('kwd');
      expect(kwd.nameAr, 'الكويت');
      expect(kwd.currencySymbol, 'د.ك');

      final unknown = CountryCurrencyConfig.findByCurrencyCode('USD');
      expect(unknown.code, 'EG');
    });
  });

  group('SwitchPoint Country & Currency Selector Widget Tests', () {
    testWidgets('Renders default Egypt badge and allows switching country', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              appBar: SwitchPointHeader(),
            ),
          ),
        ),
      );

      // Verify default Egypt flag & currency badge is shown
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.textContaining('🇪🇬'), findsWidgets);
      await tester.tap(find.byIcon(Icons.payments_outlined));
      await tester.pumpAndSettle();

      // Verify the popup menu opens with options
      expect(find.textContaining('المملكة العربية السعودية'), findsOneWidget);
      expect(find.textContaining('الإمارات العربية المتحدة'), findsOneWidget);

      // Select Saudi Arabia
      await tester.tap(find.textContaining('المملكة العربية السعودية'));
      await tester.pumpAndSettle();

      // Verify the settings menu now shows Saudi Arabia
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.textContaining('🇸🇦'), findsWidgets);
    });
  });
}
