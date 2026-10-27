import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_gateway_config_model.dart';
import 'package:al_mraay/features/company_portal/presentation/widgets/whatsapp_live_outbox_view.dart';
import 'package:al_mraay/features/company_portal/presentation/widgets/whatsapp_campaign_dispatcher_dialog.dart';

void main() {
  group('WhatsAppLiveOutboxView Widget Tests', () {
    testWidgets('renders unconfigured state when gatewayConfig is not set', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WhatsAppLiveOutboxView(
              gatewayConfig: const WhatsAppGatewayConfigModel(customEndpointUrl: ''),
              strings: AppStrings('ar'),
              isAr: true,
              onOpenSettings: () {},
            ),
          ),
        ),
      );

      expect(find.text('بوابة الواتساب غير مضبوطة'), findsOneWidget);
      expect(find.text('ضبط إعدادات البوابة الآن'), findsOneWidget);
    });

    testWidgets('renders desktop layout without any layout exceptions or crashes', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const configuredGateway = WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.waha,
        instanceId: 'default',
        apiToken: 'test-waha-token',
        customEndpointUrl: 'http://76.13.14.23:3000',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: WhatsAppLiveOutboxView(
                gatewayConfig: configuredGateway,
                strings: AppStrings('ar'),
                isAr: true,
                onOpenSettings: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('الكل'), findsOneWidget);
      expect(find.text('المرسلة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders mobile layout on small screens without exceptions', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const configuredGateway = WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.waha,
        instanceId: 'default',
        apiToken: 'test-waha-token',
        customEndpointUrl: 'http://76.13.14.23:3000',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: WhatsAppLiveOutboxView(
                gatewayConfig: configuredGateway,
                strings: AppStrings('ar'),
                isAr: true,
                onOpenSettings: () {},
                customerContacts: [
                  CustomerCampaignContact(
                    id: 'c1',
                    name: 'عمر فتح الله',
                    rawPhone: '01211857725',
                    cleanPhone: '201211857725',
                    totalSpend: 500,
                    totalInvoices: 2,
                    prizesWon: [],
                    branches: ['سموحة'],
                    lastBranch: 'سموحة',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('المرسلة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
