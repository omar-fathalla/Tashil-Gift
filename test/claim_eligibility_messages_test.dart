import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/error_handler.dart';

const _serverReasons = [
  'campaign_inactive',
  'campaign_not_started',
  'campaign_ended',
  'receipt_date_outside_campaign',
  'receipt_lines_missing',
  'required_products_missing',
  'min_spend_not_met',
  'no_eligible_gift',
];

FirebaseFunctionsException _rejection(String reason, {String message = 'rejected'}) {
  return FirebaseFunctionsException(
    code: 'failed-precondition',
    message: message,
    details: {'reason': reason},
  );
}

void main() {
  test('every server eligibility reason has an Arabic message', () {
    for (final reason in _serverReasons) {
      final text = AppErrorHandler.claimFailureMessage(_rejection(reason));
      expect(text, AppErrorHandler.claimEligibilityMessages[reason], reason: reason);
      expect(RegExp(r'[\u0600-\u06FF]').hasMatch(text), isTrue, reason: reason);
    }
    expect(AppErrorHandler.claimEligibilityMessages.keys.toSet(), _serverReasons.toSet());
  });

  test('copy rules: Western digits, فاتورة not إيصال, no AI model names', () {
    final forbidden = RegExp(r'gemini|gpt|claude|openai|[\u0660-\u0669\u06F0-\u06F9]|إيصال|الإيصال|ايصال',
        caseSensitive: false);
    for (final entry in AppErrorHandler.claimEligibilityMessages.entries) {
      expect(forbidden.hasMatch(entry.value), isFalse, reason: entry.key);
    }
    final withReceipt = AppErrorHandler.claimEligibilityMessages.values.where((m) => m.contains('الفاتورة'));
    expect(withReceipt.length, greaterThan(AppErrorHandler.claimEligibilityMessages.length ~/ 2));
    expect(AppErrorHandler.claimEligibilityMessages['receipt_lines_missing'], contains('المندوب'));
  });

  test('an Arabic server message with its own numbers is shown as sent', () {
    const sent = 'قيمة مشتريات منتجات الحملة في الفاتورة (120 جنيه) أقل من الحد الأدنى المطلوب (150 جنيه)، ولم يُصرف أي مخزون.';
    expect(AppErrorHandler.claimFailureMessage(_rejection('min_spend_not_met', message: sent)), sent);
  });

  test('the English inactive-campaign message is replaced by the Arabic reason text', () {
    final e = _rejection('campaign_inactive', message: 'Campaign is not active.');
    expect(AppErrorHandler.claimRejectionReason(e), 'campaign_inactive');
    expect(AppErrorHandler.claimFailureMessage(e), AppErrorHandler.claimEligibilityMessages['campaign_inactive']);
  });

  test('an unknown reason falls back to the generic claim mapping', () {
    final e = _rejection('something_new', message: 'Receipt not found.');
    expect(AppErrorHandler.claimFailureMessage(e), 'الفاتورة غير موجودة.');
    expect(AppErrorHandler.claimRejectionReason(FirebaseFunctionsException(code: 'internal', message: 'x')), isNull);
  });
}
