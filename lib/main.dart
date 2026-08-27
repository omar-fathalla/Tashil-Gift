import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/localization/locale_provider.dart';
import 'core/services/firebase_service.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/admin/presentation/admin_dashboard_screen.dart';
import 'features/client_portal/presentation/client_receipt_upload_screen.dart';
import 'features/company_portal/presentation/company_manager_portal_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with the mock/configured options.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final currentLocale = ref.watch(localeProvider);
    final isAr = currentLocale.languageCode == 'ar';

    return MaterialApp(
      title: 'Tashil Gift',
      theme: AppTheme.getLightTheme(),
      darkTheme: AppTheme.getDarkTheme(),
      themeMode: themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar', ''),
        Locale('en', ''),
        Locale('hi', ''),
      ],
      locale: currentLocale,
      builder: (context, child) {
        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute: '/',
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');
        
        // 1. Direct Event Link (/event/xyz or /e/xyz)
        if (uri.pathSegments.length >= 2 && (uri.pathSegments[0] == 'event' || uri.pathSegments[0] == 'e')) {
          final eventId = uri.pathSegments[1].trim();
          if (eventId.isEmpty) {
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: settings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => ClientReceiptUploadScreen(
              companySlug: '',
              initialEventId: eventId,
            ),
            settings: settings,
          );
        }

        // 2. Direct Event Manager Portal Link (/event-portal/xyz or /ep/xyz)
        if (uri.pathSegments.length >= 2 && (uri.pathSegments[0] == 'event-portal' || uri.pathSegments[0] == 'ep')) {
          final eventId = uri.pathSegments[1].trim();
          if (eventId.isEmpty) {
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: settings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => CompanyManagerPortalScreen(
              companySlug: '',
              initialEventId: eventId,
            ),
            settings: settings,
          );
        }

        // 3. Promoter & Customer submission link (/c/unilever or /client/adco)
        if (uri.pathSegments.length >= 2 && (uri.pathSegments[0] == 'c' || uri.pathSegments[0] == 'client')) {
          final slug = uri.pathSegments[1].trim();
          final eventId = uri.queryParameters['event'] ?? uri.queryParameters['id'];
          if (slug.isEmpty && (eventId == null || eventId.trim().isEmpty)) {
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: settings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => ClientReceiptUploadScreen(
              companySlug: slug,
              initialEventId: eventId,
            ),
            settings: settings,
          );
        }

        // 4. Company Manager & Partner Portal link (/portal/unilever or /p/juhayna)
        if (uri.pathSegments.length >= 2 &&
            (uri.pathSegments[0] == 'portal' || uri.pathSegments[0] == 'p' || uri.pathSegments[0] == 'company')) {
          final slug = uri.pathSegments[1].trim();
          final eventId = uri.queryParameters['event'] ?? uri.queryParameters['id'];
          if (slug.isEmpty && (eventId == null || eventId.trim().isEmpty)) {
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: settings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => CompanyManagerPortalScreen(
              companySlug: slug,
              initialEventId: eventId,
            ),
            settings: settings,
          );
        }

        final normalizedPath = uri.path.replaceAll(RegExp(r'/+$'), '');

        switch (normalizedPath) {
          case '/admin':
            return MaterialPageRoute(
              builder: (context) => const AdminAuthGuard(),
              settings: settings,
            );
          case '/portal':
          case '/p':
          case '/company':
            final slug = (uri.queryParameters['company'] ?? uri.queryParameters['slug'] ?? '').trim();
            final eventId = uri.queryParameters['event'] ?? uri.queryParameters['id'];
            if (slug.isEmpty && (eventId == null || eventId.trim().isEmpty)) {
              return MaterialPageRoute(
                builder: (context) => const AuthScreen(),
                settings: settings,
              );
            }
            return MaterialPageRoute(
              builder: (context) => CompanyManagerPortalScreen(
                companySlug: slug,
                initialEventId: eventId,
              ),
              settings: settings,
            );
          case '/submit':
          case '/c':
          case '/client':
            final slug = (uri.queryParameters['company'] ?? uri.queryParameters['slug'] ?? '').trim();
            final eventId = uri.queryParameters['event'] ?? uri.queryParameters['id'];
            if (slug.isEmpty && (eventId == null || eventId.trim().isEmpty)) {
              return MaterialPageRoute(
                builder: (context) => const AuthScreen(),
                settings: settings,
              );
            }
            return MaterialPageRoute(
              builder: (context) => ClientReceiptUploadScreen(
                companySlug: slug,
                initialEventId: eventId,
              ),
              settings: settings,
            );
          case '':
          case '/':
          default:
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: settings,
            );
        }
      },
    );
  }
}

class AdminAuthGuard extends ConsumerWidget {
  const AdminAuthGuard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    if (isAdmin) {
      return const AdminDashboardScreen();
    }
    return const AuthScreen();
  }
}



