import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/anonymous_session_policy.dart';

void main() {
  test('public link routes need anonymous session', () {
    for (final u in [
      'https://gift.sw-point.com/c?company=x',
      'https://gift.sw-point.com/submit?company=x&event=1',
      'https://gift.sw-point.com/e/abc',
      'https://gift.sw-point.com/portal?company=x',
      'https://gift.sw-point.com/ops?company=x',
      'https://gift.sw-point.com/#/c?company=x',
    ]) {
      expect(routeNeedsAnonymousSession(Uri.parse(u)), isTrue, reason: u);
    }
  });
  test('admin and root routes do not', () {
    for (final u in [
      'https://gift.sw-point.com/',
      'https://gift.sw-point.com/admin',
      'https://gift.sw-point.com/login',
      'https://gift.sw-point.com/#/admin',
    ]) {
      expect(routeNeedsAnonymousSession(Uri.parse(u)), isFalse, reason: u);
    }
  });
}
