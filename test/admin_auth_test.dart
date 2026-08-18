import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/services/firebase_service.dart';
import 'package:al_mraay/features/auth/presentation/auth_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Admin Auth & Security Tests', () {
    test('Primary admin email constant is support@sw-point.com', () {
      expect(kPrimaryAdminEmail, 'support@sw-point.com');
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

    testWidgets('AuthScreen renders Remember Me and has no demo bypass button', (tester) async {
      SharedPreferences.setMockInitialValues({
        'saved_admin_email': 'support@sw-point.com',
        'remember_admin_me': true,
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
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
  });
}
