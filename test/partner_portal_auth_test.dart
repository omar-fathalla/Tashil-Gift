import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:al_mraay/core/services/firebase_service.dart';
import 'package:al_mraay/core/services/partner_portal_auth_service.dart';
import 'package:al_mraay/core/theme/app_theme.dart';
import 'package:al_mraay/features/admin/domain/company_model.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/auth/presentation/partner_portal_login_screen.dart';
import 'package:al_mraay/features/client_portal/presentation/widgets/campaign_gift_balance_dialog.dart';
import 'package:al_mraay/features/company_portal/presentation/branch_stock_balances_screen.dart';
import 'package:al_mraay/features/company_portal/presentation/company_vouchers_report_screen.dart';
import 'package:al_mraay/features/company_portal/presentation/daily_branch_sales_screen.dart';
import 'package:al_mraay/features/validation/presentation/invoices_log_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PartnerPortalAuthService.clearMemorySessions();
  });

  group('Two-Tier Partner Portal Authentication & Role Isolation Tests', () {
    test('Tier 1: Company-level default credentials resolve deterministically and authenticate', () async {
      final service = PartnerPortalAuthService();

      final creds = await service.resolveCredentials(
        companySlug: '512',
        companyNameHint: 'يونيليفر المشرق',
      );
      expect(creds.brandManagerUsername, 'brand_512');
      expect(creds.brandManagerPassword, PartnerPortalAuthService.defaultBrandPassword('512'));
      expect(creds.brandCredentialVersion, 1);
      expect(creds.agencyOpsUsername, 'ops_512');
      expect(creds.agencyOpsPassword, PartnerPortalAuthService.defaultAgencyPassword('512'));
      expect(creds.agencyCredentialVersion, 1);
      expect(creds.hasCustomAgencyCredentials, isFalse);

      // Authenticate Brand Manager on Brand Portal
      final brandLogin = await service.authenticate(
        companySlug: '512',
        requiredRole: PartnerPortalRole.brandManager,
        username: creds.brandManagerUsername,
        password: creds.brandManagerPassword,
        rememberMe: true,
      );
      expect(brandLogin.isSuccess, isTrue);
      expect(brandLogin.session?.role, PartnerPortalRole.brandManager);
    });

    test('Strict Role Isolation prevents Brand credentials on Ops portal and Ops credentials on Brand portal', () async {
      final service = PartnerPortalAuthService();
      final creds = await service.resolveCredentials(companySlug: '512');

      // Try Brand Manager credentials on Agency Ops portal
      final brandOnOps = await service.authenticate(
        companySlug: '512',
        requiredRole: PartnerPortalRole.agencyOps,
        username: creds.brandManagerUsername,
        password: creds.brandManagerPassword,
        rememberMe: false,
      );
      expect(brandOnOps.isSuccess, isFalse);
      expect(brandOnOps.errorMessageEn, contains('Brand Executive credentials'));

      // Try Agency Ops credentials on Brand Manager portal
      final opsOnBrand = await service.authenticate(
        companySlug: '512',
        requiredRole: PartnerPortalRole.brandManager,
        username: creds.agencyOpsUsername,
        password: creds.agencyOpsPassword,
        rememberMe: false,
      );
      expect(opsOnBrand.isSuccess, isFalse);
      expect(opsOnBrand.errorMessageEn, contains('Agency Operations'));
    });

    test('Tier 2: Campaign-level custom agency credentials override Tier 1 when enabled', () async {
      final service = PartnerPortalAuthService();
      await service.saveCampaignAgencyOverride(
        eventId: 'ev_ramadan',
        companySlug: '512',
        hasCustomAgencyCredentials: true,
        customAgencyUsername: 'agency_ramadan',
        customAgencyPassword: 'Ramadan#2026',
      );

      // Resolve for campaign ev_ramadan -> uses Tier 2 override
      final overrideCreds = await service.resolveCredentials(
        companySlug: '512',
        eventId: 'ev_ramadan',
      );
      expect(overrideCreds.hasCustomAgencyCredentials, isTrue);
      expect(overrideCreds.effectiveAgencyUsername, 'agency_ramadan');
      expect(overrideCreds.effectiveAgencyPassword, 'Ramadan#2026');
      expect(overrideCreds.effectiveAgencyVersion, 2);

      // Tier 1 default password should fail on overridden campaign
      final tier1Attempt = await service.authenticate(
        companySlug: '512',
        eventId: 'ev_ramadan',
        requiredRole: PartnerPortalRole.agencyOps,
        username: overrideCreds.agencyOpsUsername,
        password: overrideCreds.agencyOpsPassword,
        rememberMe: false,
      );
      expect(tier1Attempt.isSuccess, isFalse);

      // Tier 2 custom password succeeds on campaign link (/ep/ev_ramadan)
      final tier2Attempt = await service.authenticate(
        companySlug: '512',
        eventId: 'ev_ramadan',
        requiredRole: PartnerPortalRole.agencyOps,
        username: 'agency_ramadan',
        password: 'Ramadan#2026',
        rememberMe: true,
      );
      expect(tier2Attempt.isSuccess, isTrue);
      expect(tier2Attempt.session?.credentialVersion, 2);
      expect(tier2Attempt.session?.isCampaignTier, isTrue);
      expect(tier2Attempt.session?.lockedEventId, 'ev_ramadan');

      // Cross-Campaign Isolation: Tier-2 session for ev_ramadan MUST NOT unlock another campaign ev_summer
      final otherCampaignSession = await service.getValidSession(
        companySlug: '512',
        eventId: 'ev_summer',
        requiredRole: PartnerPortalRole.agencyOps,
      );
      expect(otherCampaignSession, isNull);

      // Same campaign ev_ramadan remains unlocked
      final sameCampaignSession = await service.getValidSession(
        companySlug: '512',
        eventId: 'ev_ramadan',
        requiredRole: PartnerPortalRole.agencyOps,
      );
      expect(sameCampaignSession, isNotNull);
      expect(sameCampaignSession?.lockedEventId, 'ev_ramadan');

      // Tier 2 custom credentials also work when logging in from /ops/512 (eventId == null)
      await service.signOut(
        companySlug: '512',
        eventId: 'ev_ramadan',
        role: PartnerPortalRole.agencyOps,
      );
      final opsSlugTier2Login = await service.authenticate(
        companySlug: '512',
        requiredRole: PartnerPortalRole.agencyOps,
        username: 'agency_ramadan',
        password: 'Ramadan#2026',
        rememberMe: true,
      );
      expect(opsSlugTier2Login.isSuccess, isTrue);
      expect(opsSlugTier2Login.session?.isCampaignTier, isTrue);
      expect(opsSlugTier2Login.session?.lockedEventId, 'ev_ramadan');

      // Updating campaign override password increments version and revokes the Tier-2 session
      final newVer = await service.saveCampaignAgencyOverride(
        eventId: 'ev_ramadan',
        companySlug: '512',
        hasCustomAgencyCredentials: true,
        customAgencyUsername: 'agency_ramadan',
        customAgencyPassword: 'Ramadan#NewPassword99',
      );
      expect(newVer, 3);

      final revokedCampaignSession = await service.getValidSession(
        companySlug: '512',
        eventId: 'ev_ramadan',
        requiredRole: PartnerPortalRole.agencyOps,
      );
      expect(revokedCampaignSession, isNull);
    });

    test('Password update increments credentialVersion and revokes existing remembered sessions', () async {
      final service = PartnerPortalAuthService();
      final initialCreds = await service.resolveCredentials(companySlug: '512');

      final loginRes = await service.authenticate(
        companySlug: '512',
        requiredRole: PartnerPortalRole.brandManager,
        username: initialCreds.brandManagerUsername,
        password: initialCreds.brandManagerPassword,
        rememberMe: true,
      );
      expect(loginRes.isSuccess, isTrue);

      // Verify session is active before password change
      final validSession = await service.getValidSession(
        companySlug: '512',
        requiredRole: PartnerPortalRole.brandManager,
      );
      expect(validSession, isNotNull);

      // Admin changes password -> increments credentialVersion to 2
      final updated = await service.saveCompanyCredentials(
        companySlug: '512',
        companyName: 'يونيليفر المشرق',
        brandManagerUsername: 'brand_512',
        brandManagerPassword: 'NewSecret@999',
        agencyOpsUsername: initialCreds.agencyOpsUsername,
        agencyOpsPassword: initialCreds.agencyOpsPassword,
        incrementBrandVersion: true,
      );
      expect(updated.brandCredentialVersion, 2);

      // Old session is immediately revoked on next verification
      final revokedSession = await service.getValidSession(
        companySlug: '512',
        requiredRole: PartnerPortalRole.brandManager,
      );
      expect(revokedSession, isNull);
    });

    test('1-Click WhatsApp Login Card contains URL, Username, Password, and Remember Me tip', () {
      final cardAr = PartnerPortalAuthService.buildWhatsAppLoginCard(
        role: PartnerPortalRole.brandManager,
        companyName: 'يونيليفر المشرق',
        portalUrl: 'https://tashil-gift.web.app/portal/512',
        username: 'brand_512',
        password: 'Tashil@512',
        isAr: true,
      );

      expect(cardAr, contains('/portal/512'));
      expect(cardAr, contains('brand_512'));
      expect(cardAr, contains('Tashil@512'));
      expect(cardAr, contains('تذكرني على هذا الجهاز'));

      final cardEn = PartnerPortalAuthService.buildWhatsAppLoginCard(
        role: PartnerPortalRole.agencyOps,
        companyName: 'Unilever',
        portalUrl: 'https://tashil-gift.web.app/ops/512',
        username: 'ops_512',
        password: 'Ops@512',
        isAr: false,
      );

      expect(cardEn, contains('/ops/512'));
      expect(cardEn, contains('ops_512'));
      expect(cardEn, contains('Ops@512'));
      expect(cardEn, contains('Remember me on this device'));
    });

    testWidgets('PortalAuthGuard blocks unauthenticated users and unlocks protected child after valid login', (tester) async {
      final defaultBrandUser = PartnerPortalAuthService.defaultBrandUsername('512');
      final defaultBrandPass = PartnerPortalAuthService.defaultBrandPassword('512');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWithValue(false),
            partnerPortalAuthServiceProvider.overrideWithValue(PartnerPortalAuthService()),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PortalAuthGuard(
              companySlug: '512',
              requiredRole: PartnerPortalRole.brandManager,
              child: Scaffold(
                body: Center(child: Text('PROTECTED_BRAND_DASHBOARD')),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Protected child is hidden; login screen is displayed
      expect(find.text('PROTECTED_BRAND_DASHBOARD'), findsNothing);
      expect(find.byType(PartnerPortalLoginScreen), findsOneWidget);

      // Enter valid Brand Manager credentials
      final textFields = find.byType(TextFormField);
      expect(textFields, findsNWidgets(2));
      await tester.enterText(textFields.at(0), defaultBrandUser);
      await tester.enterText(textFields.at(1), defaultBrandPass);
      await tester.pump();

      // Tap login button
      await tester.tap(find.byIcon(Icons.login_rounded));
      await tester.pumpAndSettle();

      // Protected child is now unlocked and rendered
      expect(find.text('PROTECTED_BRAND_DASHBOARD'), findsOneWidget);
    });

    testWidgets('System Admin (isAdminProvider == true) automatically bypasses PortalAuthGuard without password', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWithValue(true),
            partnerPortalAuthServiceProvider.overrideWithValue(PartnerPortalAuthService()),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PortalAuthGuard(
              companySlug: '512',
              requiredRole: PartnerPortalRole.agencyOps,
              child: Scaffold(
                body: Center(child: Text('ADMIN_BYPASS_AGENCY_DASHBOARD')),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Admin bypasses login screen immediately
      expect(find.byType(PartnerPortalLoginScreen), findsNothing);
      expect(find.text('ADMIN_BYPASS_AGENCY_DASHBOARD'), findsOneWidget);
    });

    testWidgets('BranchStockBalancesScreen accepts isReadOnly true for Brand Manager and false for Agency Ops', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: BranchStockBalancesScreen(
                lockedCompanySlug: '512',
                lockedCompanyName: 'يونيليفر',
                initialEventId: 'ev_stock_1',
                lockedEventId: 'ev_stock_1',
                isEmbedded: true,
                isReadOnly: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final readOnlyWidget = tester.widget<BranchStockBalancesScreen>(find.byType(BranchStockBalancesScreen));
      expect(readOnlyWidget.isReadOnly, isTrue);
      expect(readOnlyWidget.lockedEventId, 'ev_stock_1');

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: BranchStockBalancesScreen(
                lockedCompanySlug: '512',
                lockedCompanyName: 'يونيليفر',
                initialEventId: 'ev_stock_1',
                lockedEventId: 'ev_stock_1',
                isEmbedded: true,
                isReadOnly: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final editableWidget = tester.widget<BranchStockBalancesScreen>(find.byType(BranchStockBalancesScreen));
      expect(editableWidget.isReadOnly, isFalse);
      expect(editableWidget.lockedEventId, 'ev_stock_1');
    });

    testWidgets('Tier-2 lockedEventId propagates to InvoicesLogScreen, CompanyVouchersReportScreen, and DailyBranchSalesScreen', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: InvoicesLogScreen(
                      lockedCompanySlug: '512',
                      lockedCompanyName: 'يونيليفر',
                      initialEventId: 'ev_locked_99',
                      lockedEventId: 'ev_locked_99',
                      isEmbedded: true,
                    ),
                  ),
                  Expanded(
                    child: CompanyVouchersReportScreen(
                      lockedCompanySlug: '512',
                      lockedCompanyName: 'يونيليفر',
                      initialEventId: 'ev_locked_99',
                      lockedEventId: 'ev_locked_99',
                      isEmbedded: true,
                    ),
                  ),
                  Expanded(
                    child: DailyBranchSalesScreen(
                      lockedCompanySlug: '512',
                      initialEventId: 'ev_locked_99',
                      lockedEventId: 'ev_locked_99',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      final invoicesWidget = tester.widget<InvoicesLogScreen>(find.byType(InvoicesLogScreen));
      expect(invoicesWidget.lockedEventId, 'ev_locked_99');

      final vouchersWidget = tester.widget<CompanyVouchersReportScreen>(find.byType(CompanyVouchersReportScreen));
      expect(vouchersWidget.lockedEventId, 'ev_locked_99');

      final dailySalesWidget = tester.widget<DailyBranchSalesScreen>(find.byType(DailyBranchSalesScreen));
      expect(dailySalesWidget.lockedEventId, 'ev_locked_99');
    });

    testWidgets('Field Promoter CampaignGiftBalanceDialog renders strictly read-only stock view', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final event = EventModel(
        id: 'ev_promoter_test',
        eventName: 'حملة تريزيمي',
        targetCompany: 'يونيليفر',
        companySlug: '512',
        minimumSpend: 100.0,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        branchNames: const ['سموحة', 'سان ستيفانو'],
        allocatedPrizes: [
          AllocatedPrize(
            giftId: 'g1',
            name: 'كارت فواتشر مشتريات 50 ج.م',
            allocatedQuantity: 40,
            remainingQuantity: 25,
            branchName: 'سموحة',
            unitValue: 50.0,
            giftType: 'voucher',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('ar'),
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: CampaignGiftBalanceDialog(event: event),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Promoter dialog displays stock and daily handover tabs without any editable TextFormField inputs
      expect(find.byType(CampaignGiftBalanceDialog), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    });
  });

  group('CompanyModel & EventModel Credential Serialization Tests', () {
    test('CompanyModel serializes and deserializes Tier-1 credentials and versions', () {
      final company = CompanyModel(
        id: '512',
        name: 'يونيليفر',
        slug: '512',
        productsCount: 10,
        brandManagerUsername: 'brand_512',
        brandManagerPassword: 'Tashil@512',
        brandCredentialVersion: 3,
        agencyOpsUsername: 'ops_512',
        agencyOpsPassword: 'Ops@512',
        agencyCredentialVersion: 4,
      );

      final map = company.toFirestore();
      final restored = CompanyModel.fromFirestoreMap('512', map);
      expect(restored.effectiveBrandUsername, 'brand_512');
      expect(restored.effectiveBrandPassword, 'Tashil@512');
      expect(restored.brandCredentialVersion, 3);
      expect(restored.effectiveAgencyUsername, 'ops_512');
      expect(restored.effectiveAgencyPassword, 'Ops@512');
      expect(restored.agencyCredentialVersion, 4);
    });

    test('EventModel serializes and deserializes Tier-2 custom agency credentials', () {
      final event = EventModel(
        id: 'ev_1',
        eventName: 'حملة العيد',
        targetCompany: 'يونيليفر',
        companySlug: '512',
        minimumSpend: 100.0,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        hasCustomAgencyCredentials: true,
        customAgencyUsername: 'eid_ops',
        customAgencyPassword: 'Eid@2026',
        customAgencyCredentialVersion: 5,
      );

      final map = event.toFirestore();
      final restored = EventModel.fromFirestoreMap('ev_1', map);
      expect(restored.hasCustomAgencyCredentials, isTrue);
      expect(restored.customAgencyUsername, 'eid_ops');
      expect(restored.customAgencyPassword, 'Eid@2026');
      expect(restored.customAgencyCredentialVersion, 5);
    });

    test(
      'Tier-2 /ep/:id route with empty companySlug resolves companySlug and signs out cleanly',
      () async {
        final service = PartnerPortalAuthService();
        await service.saveCampaignAgencyOverride(
          eventId: 'ev_1',
          companySlug: '512',
          hasCustomAgencyCredentials: true,
          customAgencyUsername: 'ramadan_ops',
          customAgencyPassword: 'Ramadan#2026',
        );

        // Visiting /ep/ev_1 passes companySlug: '' and eventId: 'ev_1'
        final creds = await service.resolveCredentials(
          companySlug: '',
          eventId: 'ev_1',
        );
        expect(creds.companySlug, '512');
        expect(creds.hasCustomAgencyCredentials, isTrue);
        expect(creds.effectiveAgencyUsername, 'ramadan_ops');

        final loginRes = await service.authenticate(
          companySlug: '',
          eventId: 'ev_1',
          requiredRole: PartnerPortalRole.agencyOps,
          username: 'ramadan_ops',
          password: 'Ramadan#2026',
          rememberMe: true,
        );
        expect(loginRes.isSuccess, isTrue);

        final session = await service.getValidSession(
          companySlug: '',
          eventId: 'ev_1',
          requiredRole: PartnerPortalRole.agencyOps,
        );
        expect(session, isNotNull);
        expect(session!.companySlug, '512');
        expect(session.lockedEventId, 'ev_1');

        // Signing out from /ep/ev_1 with empty companySlug must clear the session
        await service.signOut(
          companySlug: '',
          eventId: 'ev_1',
          role: PartnerPortalRole.agencyOps,
        );

        final afterSignOut = await service.getValidSession(
          companySlug: '',
          eventId: 'ev_1',
          requiredRole: PartnerPortalRole.agencyOps,
        );
        expect(afterSignOut, isNull);
      },
    );

    test(
      'Tier-2 login on /ops/:slug clears campaign-locked session upon signOut even without explicit eventId',
      () async {
        final service = PartnerPortalAuthService();
        await service.saveCampaignAgencyOverride(
          eventId: 'ev_1',
          companySlug: '512',
          hasCustomAgencyCredentials: true,
          customAgencyUsername: 'ramadan_ops',
          customAgencyPassword: 'Ramadan#2026',
        );

        // User logs in at /ops/512 (eventId is null on route) using Tier-2 credentials
        final loginRes = await service.authenticate(
          companySlug: '512',
          requiredRole: PartnerPortalRole.agencyOps,
          username: 'ramadan_ops',
          password: 'Ramadan#2026',
          rememberMe: true,
        );
        expect(loginRes.isSuccess, isTrue);

        final activeSession = await service.getValidSession(
          companySlug: '512',
          requiredRole: PartnerPortalRole.agencyOps,
        );
        expect(activeSession, isNotNull);
        expect(activeSession!.lockedEventId, 'ev_1');

        // Signing out at company level (/ops/512) must also purge locked campaign sessions
        await service.signOut(
          companySlug: '512',
          role: PartnerPortalRole.agencyOps,
        );

        expect(
          await service.getValidSession(
            companySlug: '512',
            requiredRole: PartnerPortalRole.agencyOps,
          ),
          isNull,
        );
        expect(
          await service.getValidSession(
            companySlug: '512',
            eventId: 'ev_1',
            requiredRole: PartnerPortalRole.agencyOps,
          ),
          isNull,
        );
      },
    );

    test('signOutAllRoles exhaustively clears both Brand and Ops sessions across event and company scopes', () async {
      final service = PartnerPortalAuthService();

      // Authenticate Brand Manager
      final brandLogin = await service.authenticate(
        companySlug: '1440',
        requiredRole: PartnerPortalRole.brandManager,
        username: 'brand_1440',
        password: PartnerPortalAuthService.defaultBrandPassword('1440'),
        rememberMe: true,
      );
      expect(brandLogin.isSuccess, isTrue);

      // Authenticate Ops
      final opsLogin = await service.authenticate(
        companySlug: '1440',
        eventId: 'FCpIla3IiddvKrGZvLKD',
        requiredRole: PartnerPortalRole.agencyOps,
        username: 'ops_1440',
        password: PartnerPortalAuthService.defaultAgencyPassword('1440'),
        rememberMe: true,
      );
      expect(opsLogin.isSuccess, isTrue);

      // Verify sessions are valid
      expect(await service.getValidSession(companySlug: '1440', requiredRole: PartnerPortalRole.brandManager), isNotNull);
      expect(await service.getValidSession(companySlug: '1440', eventId: 'FCpIla3IiddvKrGZvLKD', requiredRole: PartnerPortalRole.agencyOps), isNotNull);

      // Call signOutAllRoles
      await service.signOutAllRoles(
        companySlug: '1440',
        eventId: 'FCpIla3IiddvKrGZvLKD',
      );

      // Verify both sessions are purged
      expect(await service.getValidSession(companySlug: '1440', requiredRole: PartnerPortalRole.brandManager), isNull);
      expect(await service.getValidSession(companySlug: '1440', eventId: 'FCpIla3IiddvKrGZvLKD', requiredRole: PartnerPortalRole.agencyOps), isNull);
      expect(await service.getValidSession(companySlug: '1440', requiredRole: PartnerPortalRole.agencyOps), isNull);
    });

    testWidgets('PortalAuthGuard respects partnerPortalAdminBypassRevokedProvider when admin is true', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWith((ref) => true),
            partnerPortalAdminBypassRevokedProvider.overrideWith((ref) => true),
          ],
          child: const MaterialApp(
            home: PortalAuthGuard(
              companySlug: '1440',
              requiredRole: PartnerPortalRole.brandManager,
              child: Text('PROTECTED_PORTAL_CONTENT'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Protected content should NOT be displayed because bypass is revoked
      expect(find.text('PROTECTED_PORTAL_CONTENT'), findsNothing);
      // Login screen should be rendered
      expect(find.byType(PartnerPortalLoginScreen), findsOneWidget);
    });
  });
}


