import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/services/firebase_service.dart';
import 'package:al_mraay/features/auth/presentation/auth_screen.dart';
import 'package:al_mraay/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Admin Auth & Security Tests', () {
    test('Primary admin credentials constants are defined', () {
      expect(kPrimaryAdminEmail, 'support@sw-point.com');
      expect(kPrimaryAdminPassword, 'Youniis@!1987');
    });

    test('Trilingual strings for Admin Security & Auth are defined', () {
      final stringsAr = AppStrings('ar');
      expect(stringsAr.rememberMe, 'تذكر بيانات الدخول');
      expect(stringsAr.signOutBtn, 'تسجيل الخروج');
      expect(stringsAr.confirmSignOutTitle, 'تأكيد تسجيل الخروج');
      expect(stringsAr.secureAdminPortalBadge, 'بوابة الإدارة الآمنة (Protected)');

      final stringsEn = AppStrings('en');
      expect(stringsEn.rememberMe, 'Remember Me');
      expect(stringsEn.signOutBtn, 'Sign Out');
      expect(stringsEn.confirmSignOutTitle, 'Confirm Sign Out');
      expect(stringsEn.secureAdminPortalBadge, 'Secure Admin Portal (Protected)');

      final stringsHi = AppStrings('hi');
      expect(stringsHi.rememberMe, 'मुझे याद रखें');
      expect(stringsHi.signOutBtn, 'साइन आउट');
    });

    test('SharedPreferences remembers admin credentials', () async {
      SharedPreferences.setMockInitialValues({
        'saved_admin_email': 'support@sw-point.com',
        'remember_admin_me': true,
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_admin_email'), 'support@sw-point.com');
      expect(prefs.getBool('remember_admin_me'), true);
    });

    test('isAdminProvider evaluates correctly with session email', () {
      final container = ProviderContainer(
        overrides: [
          adminSessionEmailProvider.overrideWith((ref) => 'support@sw-point.com'),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isAdminProvider), isTrue);

      final unauthorizedContainer = ProviderContainer(
        overrides: [
          adminSessionEmailProvider.overrideWith((ref) => 'other@gmail.com'),
        ],
      );
      addTearDown(unauthorizedContainer.dispose);

      expect(unauthorizedContainer.read(isAdminProvider), isFalse);
    });

    testWidgets('AuthScreen renders Remember Me, prefilled admin email, and has no demo bypass button', (tester) async {
      SharedPreferences.setMockInitialValues({
        'saved_admin_email': 'support@sw-point.com',
        'remember_admin_me': true,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateStreamProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: const MaterialApp(
            home: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify email field is prefilled or visible
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('تذكر بيانات الدخول'), findsOneWidget);
      expect(find.text('دخول الحساب'), findsOneWidget);

      // Verify demo bypass button is NOT present
      expect(find.text('دخول تجريبي سريع'), findsNothing);
      expect(find.text('Quick Demo Login'), findsNothing);
    });

    testWidgets('AdminAuthGuard routes unauthenticated users to AuthScreen', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminSessionEmailProvider.overrideWith((ref) => null),
            authStateStreamProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: const MaterialApp(
            home: AdminAuthGuard(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AuthScreen), findsOneWidget);
    });
  });
}
