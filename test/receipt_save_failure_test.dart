import 'package:al_mraay/core/services/receipt_save_failure.dart';
import 'package:flutter_test/flutter_test.dart';

class _Err implements Exception {
  final String code;
  _Err(this.code);
  @override
  String toString() => '[cloud_firestore/$code] denied';
}

Map<String, dynamic> base() => {
      'submittedByUid': 'u1',
      'campaignId': 'E',
      'companySlug': '469',
      'receipt_number': '22_13_250_291026',
      'customerPhone': '01012345678',
      'total_value': 79,
      'extracted_products': [],
    };

void main() {
  final denied = _Err('permission-denied');
  test('already uploaded wins and formats approved text 1', () {
    final f = diagnoseReceiptSaveFailure(error: denied, alreadyUploaded: true);
    expect(f.kind, ReceiptSaveFailureKind.alreadyUploaded);
    expect(receiptSaveFailureMessage(f, uploadedAt: '29/10/2026  18:51', branch: 'فرع طنطا', status: 'مرفوضة'),
        'هذه الفاتورة مرفوعة بالفعل بتاريخ 29/10/2026  18:51 من فرع فرع طنطا — حالتها: مرفوضة. لا يمكن رفعها مرة أخرى.');
  });
  test('session expired: unauthenticated, no user, or uid changed', () {
    expect(diagnoseReceiptSaveFailure(error: _Err('unauthenticated'), currentUid: 'u1').kind, ReceiptSaveFailureKind.sessionExpired);
    expect(diagnoseReceiptSaveFailure(error: denied, currentUid: null).kind, ReceiptSaveFailureKind.sessionExpired);
    expect(diagnoseReceiptSaveFailure(error: denied, data: base(), currentUid: 'u2').kind, ReceiptSaveFailureKind.sessionExpired);
  });
  test('campaign stopped, branch, invalid field, fallback code', () {
    expect(diagnoseReceiptSaveFailure(error: denied, data: base(), currentUid: 'u1', campaignActive: false).kind, ReceiptSaveFailureKind.campaignStopped);
    expect(diagnoseReceiptSaveFailure(error: denied, data: base(), currentUid: 'u1', branchInCampaign: false).kind, ReceiptSaveFailureKind.branchNotInCampaign);
    final f = diagnoseReceiptSaveFailure(error: denied, data: base()..['customerPhone'] = '0' * 40, currentUid: 'u1');
    expect(f.kind, ReceiptSaveFailureKind.invalidData);
    expect(receiptSaveFailureMessage(f), 'بيانات الفاتورة غير مقبولة: رقم الهاتف غير صالح. صحّح البيانات ثم حاول مرة أخرى.');
    final g = diagnoseReceiptSaveFailure(error: denied, data: base(), currentUid: 'u1', campaignActive: true, branchInCampaign: true);
    expect(receiptSaveFailureMessage(g), 'تعذّر حفظ الفاتورة: تم رفض صلاحية الحفظ (permission-denied). أرسل لقطة الشاشة للمشرف.');
    expect(receiptSaveFailureMessage(const ReceiptSaveFailure(ReceiptSaveFailureKind.sessionExpired)),
        'انتهت جلسة الرابط. أعد فتح رابط الحملة من الرسالة الأصلية ثم ارفع الفاتورة مرة أخرى.');
    expect(receiptSaveFailureMessage(const ReceiptSaveFailure(ReceiptSaveFailureKind.campaignStopped)),
        'الحملة متوقفة حاليًا ولا تقبل فواتير جديدة. تواصل مع المشرف.');
    expect(receiptSaveFailureMessage(const ReceiptSaveFailure(ReceiptSaveFailureKind.branchNotInCampaign), branch: 'فرع طنطا'),
        'الفرع فرع طنطا غير مسجّل في هذه الحملة، لذلك لم يتم حفظ الفاتورة.');
  });
}
