import 'dart:io';

import 'package:al_mraay/core/services/firebase_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('routeUsesPartnerPortalApp', () {
    test('portal / agency routes use the isolated app', () {
      for (final u in [
        'https://gift.sw-point.com/portal/577',
        'https://gift.sw-point.com/p/577?role=brand_manager',
        'https://gift.sw-point.com/company/abc',
        'https://gift.sw-point.com/ops/1434',
        'https://gift.sw-point.com/agency/x',
        'https://gift.sw-point.com/#/ops/1434?event=e',
      ]) {
        expect(routeUsesPartnerPortalApp(Uri.parse(u)), isTrue, reason: u);
      }
    });
    test('rep and admin routes keep the default app', () {
      for (final u in [
        'https://gift.sw-point.com/c/577',
        'https://gift.sw-point.com/e/abc',
        'https://gift.sw-point.com/submit/x',
        'https://gift.sw-point.com/',
        'https://gift.sw-point.com/admin',
        'https://gift.sw-point.com/login',
      ]) {
        expect(routeUsesPartnerPortalApp(Uri.parse(u)), isFalse, reason: u);
      }
    });
  });

  test('staff admin on a portal link keeps the default app', () {
    expect(shouldUsePartnerPortalApp(portalRoute: true, defaultUserIsStaff: false), isTrue);
    expect(shouldUsePartnerPortalApp(portalRoute: true, defaultUserIsStaff: true), isFalse);
    expect(shouldUsePartnerPortalApp(portalRoute: false, defaultUserIsStaff: false), isFalse);
  });

  test('app name is stable', () {
    expect(kPartnerPortalAppName, 'partner-portal');
  });

  test('no service reaches the default Firebase singletons directly', () {
    final offenders = <String>[];
    final re = RegExp(r'Firebase(Firestore|Auth|Storage|Functions|AppCheck)\.instance\b(?!For)');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('firebase_scope.dart') ||
          f.path.endsWith('main.dart') ||
          f.path.endsWith('app_check_bootstrap.dart') ||
          // Emulator-only wiring (FIREBASE_EMULATOR builds): it must attach
          // the default app's singletons to localhost, like main.dart.
          f.path.endsWith('firebase_emulator_config.dart')) {
        continue;
      }
      for (final line in f.readAsLinesSync()) {
        if (re.hasMatch(line) && !line.trim().startsWith('//')) offenders.add('${f.path}: $line');
      }
    }
    expect(offenders, isEmpty);
  });

  test('partner portal callables use the scoped functions provider', () {
    final src = File('lib/core/services/partner_portal_auth_service.dart').readAsStringSync();
    expect(src, contains('ref.watch(firebaseFunctionsProvider)'));
    expect(src, isNot(contains("FirebaseFunctions.instanceFor(region")));
  });
}
