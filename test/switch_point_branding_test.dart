import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:al_mraay/core/widgets/switch_point_branding.dart';
import 'package:al_mraay/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('SwitchPoint Branding Constants Tests', () {
    test('Company constants are correctly defined', () {
      expect(SwitchPointInfo.companyName, 'Switch Point');
      expect(SwitchPointInfo.platformName, 'Tashil Gift');
      expect(SwitchPointInfo.websiteUrl, 'https://www.sw-point.com/');
      expect(SwitchPointInfo.websiteDisplay, 'www.switchpoint.com');
      expect(SwitchPointInfo.supportEmail, 'support@switchpoint.com');
      expect(SwitchPointInfo.whatsappEgypt, '+20 121 185 7725');
      expect(SwitchPointInfo.whatsappEgyptUrl, 'https://wa.me/201211857725');
      expect(SwitchPointInfo.whatsappUae, '+971 55 871 5615');
      expect(SwitchPointInfo.whatsappUaeUrl, 'https://wa.me/971558715615');
      expect(SwitchPointInfo.copyright, '© 2026 Switch Point. All rights reserved.');
    });
  });

  group('SwitchPoint Header & Footer Widget Tests', () {
    testWidgets('SwitchPointHeader renders brand name, subtitle, and Theme toggle button', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              appBar: SwitchPointHeader(
                subtitle: 'نظام إدارة الحملات',
              ),
            ),
          ),
        ),
      );

      expect(find.text(SwitchPointInfo.platformName), findsOneWidget);
      expect(find.text('عربي'), findsOneWidget); // Active language selector badge
      expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget); // Theme toggle icon
    });

    testWidgets('SwitchPointFooter renders copyright, support email, website and clean WhatsApp pills', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SwitchPointFooter(),
          ),
        ),
      );

      expect(find.text(SwitchPointInfo.copyright), findsOneWidget);
      expect(find.text(SwitchPointInfo.supportEmail), findsOneWidget);
      expect(find.text(SwitchPointInfo.websiteDisplay), findsOneWidget);
      expect(find.text('WhatsApp Egypt'), findsOneWidget);
      expect(find.text('WhatsApp UAE'), findsOneWidget);
      expect(find.text('Powered by Switch Point Smart Systems'), findsOneWidget);
    });
  });
}
