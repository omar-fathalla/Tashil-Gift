import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:al_mraay/core/security/password_hash.dart';
import 'package:al_mraay/core/security/rep_login_policy.dart';
import 'package:al_mraay/core/services/partner_portal_auth_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PartnerPortalAuthService.clearMemorySessions();
    RepLoginPolicy.setRuntimeOverride(null);
  });

  tearDown(() {
    RepLoginPolicy.setRuntimeOverride(null);
  });

  test('pbkdf2 matches the Node RFC 6070 vector', () {
    final stored = PasswordHash.hash('password', iterations: 1, salt: 'salt'.codeUnits);
    expect(
      stored,
      'pbkdf2-sha256\$1\$c2FsdA\$Eg-2z_z4syxD5yJSVsT4N6hlSMkszDVICAWYfLcL4Xs',
    );
    expect(PasswordHash.verify(stored, 'password'), isTrue);
    expect(PasswordHash.verify(stored, 'other'), isFalse);
    expect(PasswordHash.passwordMatches('plain', 'plain').legacy, isTrue);
    expect(PasswordHash.isHash(stored), isTrue);
  });

  test('rep login succeeds, rejects a bad password and an agency password, and dies when the version changes', () async {
    final service = PartnerPortalAuthService();
    final company = await service.resolveCredentials(companySlug: '512');

    final created = await service.saveRepUploaderCredentials(
      companySlug: '512',
      companyName: 'وكالة تجريبية',
      username: 'rep_512',
      password: 'rep-secret-1',
    );
    expect(created.isSuccess, isTrue);
    expect(created.session?.credentialVersion, 1);
    expect(created.session?.role, PartnerPortalRole.repUploader);

    final stored = await service.resolveCredentials(companySlug: '512');
    expect(stored.repUploaderConfigured, isTrue);
    expect(PasswordHash.isHash(stored.repUploaderPasswordHash), isTrue);
    expect(stored.repUploaderPasswordHash.contains('rep-secret-1'), isFalse);

    final ok = await service.authenticate(
      companySlug: '512',
      requiredRole: PartnerPortalRole.repUploader,
      username: 'REP_512',
      password: 'rep-secret-1',
      rememberMe: true,
    );
    expect(ok.isSuccess, isTrue);
    expect(ok.session?.credentialVersion, 1);

    final session = await service.getValidSession(
      companySlug: '512',
      requiredRole: PartnerPortalRole.repUploader,
    );
    expect(session, isNotNull);

    final wrong = await service.authenticate(
      companySlug: '512',
      requiredRole: PartnerPortalRole.repUploader,
      username: 'rep_512',
      password: 'not-the-password',
      rememberMe: false,
    );
    expect(wrong.isSuccess, isFalse);

    final agencyOnRep = await service.authenticate(
      companySlug: '512',
      requiredRole: PartnerPortalRole.repUploader,
      username: company.agencyOpsUsername,
      password: company.agencyOpsPassword,
      rememberMe: false,
    );
    expect(agencyOnRep.isSuccess, isFalse);
    expect(agencyOnRep.errorMessageEn, contains('field-rep'));

    final repOnAgency = await service.authenticate(
      companySlug: '512',
      requiredRole: PartnerPortalRole.agencyOps,
      username: 'rep_512',
      password: 'rep-secret-1',
      rememberMe: false,
    );
    expect(repOnAgency.isSuccess, isFalse);
    expect(repOnAgency.errorMessageEn, contains('field-rep'));

    final rotated = await service.saveRepUploaderCredentials(
      companySlug: '512',
      username: 'rep_512',
      password: 'rep-secret-2',
    );
    expect(rotated.session?.credentialVersion, 2);

    final revoked = await service.getValidSession(
      companySlug: '512',
      requiredRole: PartnerPortalRole.repUploader,
    );
    expect(revoked, isNull);

    final oldPassword = await service.authenticate(
      companySlug: '512',
      requiredRole: PartnerPortalRole.repUploader,
      username: 'rep_512',
      password: 'rep-secret-1',
      rememberMe: false,
    );
    expect(oldPassword.isSuccess, isFalse);

    final fresh = await service.authenticate(
      companySlug: '512',
      requiredRole: PartnerPortalRole.repUploader,
      username: 'rep_512',
      password: 'rep-secret-2',
      rememberMe: true,
    );
    expect(fresh.isSuccess, isTrue);
    expect(fresh.session?.credentialVersion, 2);
  });

  test('unconfigured company cannot log in as a rep, and a hash is not copied into a WhatsApp card', () async {
    final service = PartnerPortalAuthService();
    final missing = await service.authenticate(
      companySlug: '512',
      requiredRole: PartnerPortalRole.repUploader,
      username: 'rep_512',
      password: 'anything',
      rememberMe: false,
    );
    expect(missing.isSuccess, isFalse);
    expect(missing.errorMessageEn, contains('No field-rep account'));

    final card = PartnerPortalAuthService.buildWhatsAppLoginCard(
      role: PartnerPortalRole.repUploader,
      companyName: 'وكالة',
      portalUrl: 'https://tashil-gift.web.app/rep/512',
      username: 'rep_512',
      password: PasswordHash.hash('rep-secret-1', iterations: 1, salt: 'salt'.codeUnits),
      isAr: true,
    );
    expect(card.contains('rep-secret-1'), isFalse);
    expect(card.contains('pbkdf2-sha256'), isFalse);
    expect(card.contains('/rep/512'), isTrue);
    expect(card.contains('rep_512'), isTrue);
  });

  test('requireRepLogin closes public links only when the switch is on', () {
    expect(RepLoginPolicy.requireRepLogin, isFalse);
    expect(RepLoginPolicy.requiresLogin(repEntry: false), isFalse);
    expect(RepLoginPolicy.requiresLogin(repEntry: true), isTrue);
    RepLoginPolicy.setRuntimeOverride(true);
    expect(RepLoginPolicy.requiresLogin(repEntry: false), isTrue);
    expect(RepLoginPolicy.requiresLogin(repEntry: true), isTrue);
  });
}
