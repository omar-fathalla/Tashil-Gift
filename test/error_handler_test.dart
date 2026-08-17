import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:al_mraay/core/utils/error_handler.dart';

void main() {
  group('AppErrorHandler Tests (Online-Only Architecture)', () {
    test('Translates network offline errors into clear Arabic online-only guidance', () {
      final error = Exception('Failed host lookup: firestore.googleapis.com client is offline');
      final message = AppErrorHandler.getFriendlyMessage(error);

      expect(message, contains('Online Only'));
      expect(message, contains('الاتصال المباشر'));
    });

    test('Translates Firestore unavailable error correctly', () {
      final exception = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'The service is currently unavailable.',
      );
      final message = AppErrorHandler.getFriendlyMessage(exception);

      expect(message, contains('تعذر الاتصال بقاعدة البيانات السحابية'));
      expect(message, contains('Online Only'));
    });

    test('Translates FirebaseAuth wrong password error correctly', () {
      final authException = FirebaseAuthException(
        code: 'wrong-password',
        message: 'Wrong password provided.',
      );
      final message = AppErrorHandler.getFriendlyMessage(authException);

      expect(message, contains('كلمة المرور غير صحيحة'));
    });

    test('Translates JSON syntax and FormatException into clear Arabic guidance', () {
      final jsonError = Exception("FormatSyntaxError: Expected property name or '}' in JSON at position 683 (line 32 column 7)");
      final message = AppErrorHandler.getFriendlyMessage(jsonError);

      expect(message, contains('تعذر قراءة بيانات الفاتورة'));
      expect(message, contains('إعادة المحاولة'));
    });

    test('Translates AI quota / rate limit errors into Arabic', () {
      final quotaError = Exception('GenerativeAIException: Quota exceeded 429 resource exhausted');
      final message = AppErrorHandler.getFriendlyMessage(quotaError);

      expect(message, contains('مشغولة حالياً بكثرة الطلبات'));
    });

    test('Translates timeout / deadline exceeded into Arabic', () {
      final timeoutError = Exception('TimeoutException after 0:00:12.000000: Future not completed');
      final message = AppErrorHandler.getFriendlyMessage(timeoutError);

      expect(message, contains('استغرقت عملية فحص الفاتورة وقتاً أطول من المتوقع'));
    });

    test('Translates technical English errors into clean Arabic', () {
      final techError = Exception('NoSuchMethodError: The getter length was called on null');
      final message = AppErrorHandler.getFriendlyMessage(techError);

      expect(message, contains('حدث خطأ أثناء معالجة بيانات الفاتورة'));
    });

    test('Preserves clean Arabic business error messages', () {
      final customArabic = Exception('قيمة مشتريات منتجات العرض لم تصل إلى الحد الأدنى المطلوب');
      final message = AppErrorHandler.getFriendlyMessage(customArabic);

      expect(message, equals('قيمة مشتريات منتجات العرض لم تصل إلى الحد الأدنى المطلوب'));
    });

    test('Returns default message when error is null or empty', () {
      final message = AppErrorHandler.getFriendlyMessage(null, defaultMessage: 'رسالة افتراضية');
      expect(message, equals('رسالة افتراضية'));
    });
  });
}
