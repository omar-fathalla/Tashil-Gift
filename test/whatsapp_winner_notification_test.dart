import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_gateway_config_model.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_gateway_service.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_winner_notification_service.dart';
import 'package:al_mraay/features/company_portal/presentation/widgets/whatsapp_campaign_dispatcher_dialog.dart';

void main() {
  group('WhatsApp Winner Notification Service Tests', () {
    test('buildWinnerMessage replaces all placeholders accurately', () {
      const config = WhatsAppGatewayConfigModel();
      final claimDate = DateTime(2026, 10, 9, 14, 30);

      final message = WhatsAppWinnerNotificationService.buildWinnerMessage(
        config: config,
        prizeName: 'فواتشر بقيمة 50 جنيه',
        customerName: 'عمر فتح الله',
        retailChain: 'أسواق فتح الله',
        branchName: 'فرع الإقبال',
        companyName: 'شركة ادكو للتجارة والصناعة',
        campaignName: 'مهرجان التوفير والجوائز',
        voucherSerials: ['VCH-123456'],
        receiptNumber: 'REC-99401',
        claimDate: claimDate,
      );

      expect(message, contains('عمر فتح الله'));
      expect(message, contains('أسواق فتح الله'));
      expect(message, contains('فرع الإقبال'));
      expect(message, contains('شركة ادكو للتجارة والصناعة'));
      expect(message, contains('مهرجان التوفير والجوائز'));
      // 2.0.157: the gift name is never sent to the customer.
      expect(message, isNot(contains('فواتشر بقيمة 50 جنيه')));
      expect(message, contains('كسبت معانا'));
      expect(message, contains('VCH-123456'));
      expect(message, contains('REC-99401'));
    });

    test('buildWinnerMessage uses elegant defaults when fields are empty', () {
      const config = WhatsAppGatewayConfigModel();

      final message = WhatsAppWinnerNotificationService.buildWinnerMessage(
        config: config,
        prizeName: 'هدية فورية معتمدة',
        customerName: '',
        retailChain: '',
        branchName: '',
        companyName: '',
        campaignName: '',
      );

      expect(message, contains('عميلنا العزيز'));
      expect(message, contains('المتجر'));
      expect(message, contains('إدارة العروض الترويجية'));
      expect(message, isNot(contains('هدية فورية معتمدة')));
    });

    test('WhatsAppGatewayConfigModel correctly serializes winner notification settings', () {
      const config = WhatsAppGatewayConfigModel(
        autoNotifyWinnersOnGiftHandover: true,
        winnerNotificationTemplate: 'مبروك {customer_name} كسبت {prize_name}',
      );

      final map = config.toMap();
      expect(map['autoNotifyWinnersOnGiftHandover'], isTrue);
      expect(map['winnerNotificationTemplate'], equals('مبروك {customer_name} كسبت {prize_name}'));

      final restored = WhatsAppGatewayConfigModel.fromMap(map);
      expect(restored.autoNotifyWinnersOnGiftHandover, isTrue);
      expect(restored.winnerNotificationTemplate, equals('مبروك {customer_name} كسبت {prize_name}'));
    });

    test('formatInternationalPhone normalizes Egyptian and Arabic numerals', () {
      // Standard local
      expect(WhatsAppGatewayService.formatInternationalPhone('01211857725'), equals('201211857725'));
      // With international plus
      expect(WhatsAppGatewayService.formatInternationalPhone('+201508899965'), equals('201508899965'));
      // Eastern Arabic numerals
      expect(WhatsAppGatewayService.formatInternationalPhone('٠١٢١١٨٥٧٧٢٥'), equals('201211857725'));
      // Formatted with spaces and dashes
      expect(WhatsAppGatewayService.formatInternationalPhone('012-1185-7725'), equals('201211857725'));
    });

    test('CustomerCampaignContact.searchIndex computes fast searchable tokens', () {
      final contact = CustomerCampaignContact(
        id: 'c1',
        name: 'عمر أحمد فتح الله',
        rawPhone: '٠١٢١١٨٥٧٧٢٥',
        cleanPhone: '201211857725',
        totalSpend: 500,
        totalInvoices: 3,
        prizesWon: ['فواتشر 50'],
        branches: ['فرع الإقبال', 'فرع سموحة'],
        lastBranch: 'فرع الإقبال',
      );

      // Search by partial Arabic name
      expect(contact.searchIndex.contains('عمر'), isTrue);
      expect(contact.searchIndex.contains('فتح الله'), isTrue);
      // Search by Western digits even when entered as raw Eastern Arabic
      expect(contact.searchIndex.contains('01211857725'), isTrue);
      expect(contact.searchIndex.contains('201211857725'), isTrue);
      // Search by branch name
      expect(contact.searchIndex.contains('الإقبال'), isTrue);
      expect(contact.searchIndex.contains('سموحة'), isTrue);
      // Non-matching
      expect(contact.searchIndex.contains('القاهرة'), isFalse);
    });

    test('EventModel defaults enableWhatsAppWinnerNotification to true', () {
      final event = EventModel(
        id: 'ev1',
        eventName: 'مهرجان التوفير',
        targetCompany: 'ادكو',
        minimumSpend: 100,
      );
      expect(event.enableWhatsAppWinnerNotification, isTrue);

      final map = event.toFirestore();
      expect(map['enableWhatsAppWinnerNotification'], isTrue);

      final restored = EventModel.fromFirestoreMap('ev1', map);
      expect(restored.enableWhatsAppWinnerNotification, isTrue);
    });

    test('EventModel properly disables enableWhatsAppWinnerNotification when toggled off', () {
      final event = EventModel(
        id: 'ev2',
        eventName: 'مهرجان كادبوري',
        targetCompany: 'مونديليز',
        minimumSpend: 200,
        enableWhatsAppWinnerNotification: false,
      );
      expect(event.enableWhatsAppWinnerNotification, isFalse);

      final map = event.toFirestore();
      expect(map['enableWhatsAppWinnerNotification'], isFalse);

      final restored = EventModel.fromFirestoreMap('ev2', map);
      expect(restored.enableWhatsAppWinnerNotification, isFalse);

      final toggledBack = restored.copyWith(enableWhatsAppWinnerNotification: true);
      expect(toggledBack.enableWhatsAppWinnerNotification, isTrue);
    });
  });
}
