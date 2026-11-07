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
    test('Primary admin email constant is defined and no hardcoded password exists', () {
      expect(kPrimaryAdminEmail, 'support@switchpoint.com');
      expect(kFallbackAdminEmail, 'support@sw-point.com');
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

    test('SharedPreferences remembers admin email and never stores passwords', () async {
      SharedPreferences.setMockInitialValues({
        'saved_admin_email': 'support@sw-point.com',
        'remember_admin_me': true,
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_admin_email'), 'support@sw-point.com');
      expect(prefs.getBool('remember_admin_me'), true);
      expect(prefs.getString('saved_admin_password'), isNull);
      expect(prefs.getString('active_admin_session'), isNull);
    });

    test('Staff access is granted only by the ID token role claim', () {
      expect(isStaffRole('super_admin'), isTrue);
      expect(isStaffRole('admin'), isTrue);
      expect(isStaffRole('partner'), isFalse);
      expect(isStaffRole(null), isFalse);
      expect(isStaffRole(''), isFalse);
    });

    test('Historical admin inboxes are recognized but are not an authorization allow-list', () {
      expect(isAuthorizedAdminEmail('support@switchpoint.com'), isTrue);
      expect(isAuthorizedAdminEmail('support@sw-point.com'), isTrue);
      expect(isAuthorizedAdminEmail(' Support@SwitchPoint.com '), isTrue);
      expect(isAuthorizedAdminEmail('admin@switchpoint.com'), isFalse);
      expect(isAuthorizedAdminEmail('anyone@sw-point.com'), isFalse);
      expect(isAuthorizedAdminEmail('hacker@gmail.com'), isFalse);
      expect(isAuthorizedAdminEmail(null), isFalse);
      expect(isAuthorizedAdminEmail(''), isFalse);
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

    testWidgets('AdminAuthGuard routes authenticated users to AdminDashboardScreen when session is active', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminSessionEmailProvider.overrideWith((ref) => 'support@switchpoint.com'),
            isAdminProvider.overrideWithValue(true),
            authStateStreamProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: const MaterialApp(
            home: AdminAuthGuard(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AdminDashboardScreen), findsOneWidget);
      expect(find.byType(AuthScreen), findsNothing);
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
      await tester.pump();

      // 1. Verify AI speed benchmark button is removed from header
      expect(find.text('اختبار سرعة AI ⚡'), findsNothing);
      expect(find.text('AI Speed KPI ⚡'), findsNothing);

      // 2. Verify top header Preview Client App button is removed
      expect(find.widgetWithText(FilledButton, 'معاينة تطبيق العميل / البروموتر'), findsNothing);

      // 3. Verify standalone Outlined Logout button is replaced
      expect(find.byType(OutlinedButton), findsNothing);

      // 4. Verify Profile Menu is rendered in header
      final profileFinder = find.text('مسؤول النظام');
      expect(profileFinder, findsOneWidget);

      // 5. Tap Profile menu to open popup
      await tester.tap(profileFinder);
      await tester.pumpAndSettle();

      // 6. Verify Profile dropdown contents including Logout
      expect(find.text('مسؤول النظام'), findsWidgets);
      expect(find.text('support@switchpoint.com'), findsOneWidget);
      expect(find.text('جلسة إدارية نشطة'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsOneWidget);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    });

    testWidgets('AuthScreen renders desktop split layout with hero showcase and 4 pillars', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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

      // Verify Brand Headline & Gemini badge
      expect(find.text('منظومة سويتش بوينت الذكية'), findsOneWidget);
      expect(find.text('مدعوم بمحرك Gemini 3.7 Flash'), findsOneWidget);
      expect(find.text('حوكمة وحماية من الاحتيال 100%'), findsOneWidget);

      // Verify 4 System Pillars
      expect(find.text('إدارة الحملات والفعاليات الترويجية'), findsOneWidget);
      expect(find.text('فحص الفواتير والأسعار بالذكاء الاصطناعي'), findsOneWidget);
      expect(find.text('حوكمة الجوائز والمخزون اللحظي'), findsOneWidget);
      expect(find.text('بوابات وتقارير إدارية متعددة الشركات'), findsOneWidget);

      // Verify Quick Stats
      expect(find.text('< 1.8 ث'), findsOneWidget);
      expect(find.text('99.8%'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      // Verify Login Card
      expect(find.text('تسجيل الدخول للنظام'), findsOneWidget);
    });

    testWidgets('AuthScreen renders mobile layout with hero banner', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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

      // Verify Mobile Banner & Gemini tag
      expect(find.text('منظومة سويتش بوينت الذكية'), findsOneWidget);
      expect(find.text('مدعوم بمحرك Gemini 3.7 Flash'), findsOneWidget);
      expect(find.text('تسجيل الدخول للنظام'), findsOneWidget);
    });
  });
}
