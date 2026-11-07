import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_webhook_admin_models.dart';

void main() {
  test('verification key, invite link, and template placeholders', () {
    const awarded = WhatsappInboundMessage(id: '1', status: 'awarded', prize: 'Gift');
    const waiting = WhatsappInboundMessage(
      id: '2',
      status: 'pending_review',
      reason: 'verified_without_prize',
    );
    const blocked = WhatsappInboundMessage(id: '3', status: 'not_allowed');
    expect(awarded.verificationKey, 'verified');
    expect(waiting.verificationKey, 'verified_without_prize');
    expect(blocked.verificationKey, 'not_allowed');

    expect(
      buildWaMeInvite('01012345678', 'JOIN1'),
      'https://wa.me/01012345678?text=JOIN1',
    );
    expect(buildWaMeInvite('', 'JOIN1'), isEmpty);
    expect(
      fillWhatsappTemplate('Hi {name} {prize} {receipt} {campaign}', name: 'Nour', prize: 'Gift', receipt: 'R-1', campaign: 'Durra'),
      'Hi Nour Gift R-1 Durra',
    );
    expect(inboxMatchesQuery(const WhatsappInboundMessage(id: '1', phone: '201012345678'), '123456'), isTrue);
    expect(inboxMatchesQuery(const WhatsappInboundMessage(id: '1', phone: '201012345678'), '999'), isFalse);

    final config = WhatsappWebhookConfig.fromMap(const {
      'enabled': false,
      'autoRepliesEnabled': true,
      'allowListOnly': true,
      'businessNumber': '2010',
    });
    expect(config.enabled, isFalse);
    expect(config.template('verified'), kWhatsappReplyTemplateDefaults['verified']);

    final strings = AppStrings('hi');
    expect(strings.webhookStatusLabel('verified'), 'सत्यापित');
    expect(AppStrings('en').webhookTabInbox, 'Incoming invoices');
  });

  test('session payload exposes the linked WhatsApp number', () {
    expect(
      wahaSessionPhone({
        'status': 'WORKING',
        'me': {'id': '201055500000@c.us', 'pushName': 'Desk'},
      }),
      '201055500000',
    );
    expect(wahaSessionStatus({'status': 'SCAN_QR_CODE'}), 'SCAN_QR_CODE');
  });
}
