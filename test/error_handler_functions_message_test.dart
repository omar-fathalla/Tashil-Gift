import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/error_handler.dart';

void main() {
  test('Arabic Cloud Functions message is shown as-is', () {
    final e = FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'لا يوجد رصيد مخصص لهدية (فواتشر 50 جنيه) في هذه الحملة/الفرع.',
    );
    expect(AppErrorHandler.getFriendlyMessage(e), contains('لا يوجد رصيد مخصص'));
  });

  test('English functions not-found keeps the generic mapping', () {
    final e = FirebaseFunctionsException(code: 'not-found', message: 'Receipt not found.');
    expect(AppErrorHandler.getFriendlyMessage(e), 'البيانات المطلوبة غير موجودة في قاعدة البيانات.');
  });
}
