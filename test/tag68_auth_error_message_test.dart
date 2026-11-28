import 'package:al_mraay/core/utils/error_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TAG-68: login error never shows a bare «Error»', () {
    test('referer block explains the domain/key problem and keeps the code', () {
      final e = FirebaseAuthException(
        code: 'requests-from-referer-https://x.web.app-are-blocked',
        message: 'Error',
      );
      final m = AppErrorHandler.getFriendlyMessage(e);
      expect(m, contains('الدومين ده مش مسموح'));
      expect(m, contains('requests-from-referer-'));
    });

    test('unauthorized-domain gets an Arabic message', () {
      final m = AppErrorHandler.getFriendlyMessage(FirebaseAuthException(code: 'unauthorized-domain'));
      expect(m, contains('الدومين ده مش مسموح'));
    });

    test('app-check failure gets an Arabic message', () {
      final m = AppErrorHandler.getFriendlyMessage(FirebaseAuthException(code: 'app-check-token-is-invalid', message: 'Error'));
      expect(m, contains('App Check'));
    });

    test('unknown code with message «Error» shows the code', () {
      final m = AppErrorHandler.getFriendlyMessage(FirebaseAuthException(code: 'something-new', message: 'Error'));
      expect(m, 'فشل تسجيل الدخول (something-new).');
    });

    test('unknown code with a real message keeps the message', () {
      final m = AppErrorHandler.getFriendlyMessage(FirebaseAuthException(code: 'x', message: 'Real reason'));
      expect(m, 'Real reason');
    });

    test('known codes are unchanged', () {
      final m = AppErrorHandler.getFriendlyMessage(FirebaseAuthException(code: 'wrong-password'));
      expect(m, contains('كلمة المرور غير صحيحة'));
    });
  });
}
