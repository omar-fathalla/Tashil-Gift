import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/theme/app_theme.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_webhook_admin_models.dart';
import 'package:al_mraay/features/company_portal/presentation/widgets/whatsapp_webhook_inbox_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const message = WhatsappInboundMessage(
    id: 'img-1',
    phone: '201012345678',
    status: 'awarded',
    prize: 'Gift A',
    receiptNumber: 'R-77',
    campaignId: 'camp-1',
    replyText: 'Prize Gift A receipt R-77',
    replyMessageId: 'waha-1',
    analysis: {
      'verdict': 'valid',
      'confidence': 0.91,
      'message': 'ok',
      'storeChainDetected': 'Gomla',
    },
  );
  const pending = WhatsappInboundMessage(
    id: 'img-2',
    phone: '201099900011',
    status: 'rejected',
    reason: 'invoice_not_valid',
    campaignId: 'camp-1',
  );

  Future<void> pumpBody(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.getLightTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: WhatsAppWebhookInboxBody(
              strings: AppStrings('ar'),
              config: const WhatsappWebhookConfig(
                enabled: true,
                autoRepliesEnabled: true,
                businessNumber: '201012345678',
                businessDisplayName: 'Tashil',
                lastEventName: 'message',
                lastSessionStatus: 'WORKING',
              ),
              messages: const [message, pending],
              links: const [
                WhatsappSenderLink(phone: '201012345678', campaignId: 'camp-1', campaignName: 'درة', active: true),
              ],
              registrations: const [],
              ackCounts: const {'READ': 2, 'SERVER': 1},
              campaigns: const [WhatsappCampaignOption(id: 'camp-1', name: 'درة')],
              companySlug: 'durra',
              sessionPhone: '201055500000',
              sessionStatus: 'WORKING',
              onUpdateConfig: (_) async {},
              onUpsertLink: (_) async {},
              onDeleteLink: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('control tab shows the webhook switch, session, and business number', (tester) async {
    await pumpBody(tester);
    expect(find.text('تشغيل استقبال الويب هوك'), findsOneWidget);
    expect(find.text('WORKING'), findsOneWidget);
    expect(find.text('201055500000'), findsOneWidget);
    expect(find.text('READ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final scheme = Theme.of(tester.element(find.text('WORKING'))).colorScheme;
    final chip = tester.widget<Chip>(find.widgetWithText(Chip, 'WORKING'));
    expect(chip.backgroundColor, scheme.secondaryContainer);
  });

  testWidgets('inbox filters by status and opens the analysis sheet', (tester) async {
    await pumpBody(tester);
    await tester.tap(find.text('الفواتير الواردة'));
    await tester.pumpAndSettle();

    expect(find.text('201012345678'), findsWidgets);
    expect(find.text('تم التحقق'), findsWidgets);

    await tester.tap(find.widgetWithText(FilterChip, 'مرفوضة'));
    await tester.pumpAndSettle();
    expect(find.text('201099900011'), findsOneWidget);
    expect(find.text('201012345678'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'الكل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('201012345678').first);
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل الرسالة'), findsOneWidget);
    expect(find.text('الحكم: valid'), findsOneWidget);
    expect(find.textContaining('0.91'), findsOneWidget);
    expect(find.text('Prize Gift A receipt R-77'), findsOneWidget);
  });

  testWidgets('phone search keeps only the matching sender', (tester) async {
    await pumpBody(tester);
    await tester.tap(find.text('الفواتير الواردة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), '999000');
    await tester.pump();
    expect(find.text('201099900011'), findsOneWidget);
    expect(find.text('201012345678'), findsNothing);
  });

  testWidgets('allowed-numbers tab lists the sender link', (tester) async {
    await pumpBody(tester);
    await tester.tap(find.text('الأرقام المسموحة'));
    await tester.pumpAndSettle();
    expect(find.text('201012345678'), findsOneWidget);
    expect(find.textContaining('درة'), findsWidgets);
  });

  testWidgets('status colors come from the seed color scheme', (tester) async {
    final scheme = AppTheme.getLightTheme().colorScheme;
    expect(webhookStatusBackground(scheme, 'verified'), scheme.primaryContainer);
    expect(webhookStatusBackground(scheme, 'pending_review'), scheme.tertiaryContainer);
    expect(webhookStatusBackground(scheme, 'rejected'), scheme.errorContainer);
    expect(webhookStatusBackground(scheme, 'verified_without_prize'), scheme.secondaryContainer);
    expect(scheme.primary, isNot(equals(const Color(0xFF000000))));
  });
}
