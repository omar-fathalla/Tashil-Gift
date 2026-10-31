import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_gateway_config_model.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_winner_notification_service.dart';

void main() {
  test('default template has no prize placeholder', () {
    expect(WhatsAppGatewayConfigModel.defaultWinnerTemplate.contains('{prize_name}'), isFalse);
  });
  test('old template prize lines are stripped', () {
    const old = 'مبروك {customer_name}\nتهنئتكم بالفوز بـ:\n✨ {prize_name} ✨\nرقم {receipt_number}';
    final out = stripPrizeFromWinnerTemplate(old);
    expect(out.contains('{prize_name}'), isFalse);
    expect(out.contains('✨'), isFalse);
    expect(out, contains('تهنئتكم بالفوز معانا! 🎉'));
    expect(out, contains('رقم {receipt_number}'));
  });
}
