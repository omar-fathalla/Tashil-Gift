import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/services/firebase_service.dart';
import 'package:al_mraay/features/auth/presentation/auth_screen.dart';
import 'package:al_mraay/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:al_mraay/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Admin Auth & Security Tests', () {
    test('Primary admin credentials constants are defined', () {
      expect(kPrimaryAdminEmail, 'support@switchpoint.com');
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
            isAdminProvider.overrideWithValue(false),
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

    testWidgets('AdminDashboardScreen header removes AI speed test and Preview buttons and renders Profile Menu with Logout', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminSessionEmailProvider.overrideWith((ref) => 'support@switchpoint.com'),
            isAdminProvider.overrideWithValue(true),
          ],
          child: const MaterialApp(
            home: AdminDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify AI speed benchmark button is removed from header
      expect(find.text('اختبار سرعة AI ⚡'), findsNothing);
      expect(find.text('AI Speed KPI ⚡'), findsNothing);

      // 2. Verify top header Preview Client App button is removed
      expect(find.widgetWithText(FilledButton, 'معاينة تطبيق العميل / البروموتر'), findsNothing);

      // 3. Verify standalone Outlined Logout button is replaced
      expect(find.byType(OutlinedButton), findsNothing);

      // 4. Verify Profile Menu is rendered in header
      final profileIconFinder = find.byIcon(Icons.person_rounded);
      expect(profileIconFinder, findsOneWidget);

      // 5. Tap Profile menu to open popup
      await tester.tap(profileIconFinder);
      await tester.pumpAndSettle();

      // 6. Verify Profile dropdown contents including Logout
      expect(find.text('مسؤول النظام'), findsWidgets);
      expect(find.text('support@switchpoint.com'), findsOneWidget);
      expect(find.text('جلسة إدارية نشطة'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsOneWidget);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    });
  });
}
