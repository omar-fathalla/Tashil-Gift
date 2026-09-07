import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/localization/locale_provider.dart';
import 'core/services/firebase_service.dart';
import 'core/utils/app_url_strategy.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/admin/presentation/admin_dashboard_screen.dart';
import 'features/client_portal/presentation/client_receipt_upload_screen.dart';
import 'features/company_portal/presentation/company_manager_portal_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppPathUrlStrategy();
  
  // Initialize Firebase with the mock/configured options.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Restore persistent admin session before initial frame render to prevent spurious sign-out
  String? initialAdminSession;
  try {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_admin_me') ?? true;
    final activeSession = prefs.getString('active_admin_session');
    if (rememberMe && activeSession != null && isAuthorizedAdminEmail(activeSession)) {
      initialAdminSession = activeSession.toLowerCase();
    }
  } catch (_) {}
  
  runApp(
    ProviderScope(
      overrides: [
        if (initialAdminSession != null)
          adminSessionEmailProvider.overrideWith((ref) => initialAdminSession),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  /// Resolves the actual route URI whether loaded via clean path, legacy hash (#),
  /// or directly in the browser address bar on Flutter Web.
  Uri _resolveRouteUri(RouteSettings settings) {
    var raw = settings.name ?? '/';

    if (kIsWeb) {
      final base = Uri.base;
      // If Flutter Web defaulted to '/' or empty (e.g. initial load without hash):
      if (raw == '/' || raw.isEmpty) {
        if (base.fragment.isNotEmpty) {
          final frag = base.fragment.replaceFirst(RegExp(r'^!?/?'), '/');
          final parsed = Uri.parse(frag);
          if (parsed.queryParameters.isEmpty && base.queryParameters.isNotEmpty) {
            return parsed.replace(queryParameters: base.queryParameters);
          }
          return parsed;
        } else if (base.path.isNotEmpty && base.path != '/') {
          final full = base.query.isNotEmpty ? '${base.path}?${base.query}' : base.path;
          return Uri.parse(full);
        }
      } else if (raw.startsWith('/#') || raw.startsWith('#')) {
        final stripped = raw.replaceFirst(RegExp(r'^/?#?!?/?'), '/');
        final parsed = Uri.parse(stripped);
        if (parsed.queryParameters.isEmpty && base.queryParameters.isNotEmpty) {
          return parsed.replace(queryParameters: base.queryParameters);
        }
        return parsed;
      }
    }

    return Uri.parse(raw);
  }

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
        final uri = _resolveRouteUri(settings);
        final effectiveSettings = RouteSettings(
          name: uri.toString(),
          arguments: settings.arguments,
        );
        
        // 1. Direct Event Link (/event/xyz or /e/xyz)
        if (uri.pathSegments.length >= 2 && (uri.pathSegments[0] == 'event' || uri.pathSegments[0] == 'e')) {
          final eventId = uri.pathSegments[1].trim();
          if (eventId.isEmpty) {
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: effectiveSettings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => ClientReceiptUploadScreen(
              companySlug: '',
              initialEventId: eventId,
            ),
            settings: effectiveSettings,
          );
        }

        // 2. Direct Event Operations Portal Link (/event-portal/xyz or /ep/xyz)
        if (uri.pathSegments.length >= 2 && (uri.pathSegments[0] == 'event-portal' || uri.pathSegments[0] == 'ep')) {
          final eventId = uri.pathSegments[1].trim();
          if (eventId.isEmpty) {
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: effectiveSettings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => CompanyManagerPortalScreen(
              companySlug: '',
              initialEventId: eventId,
              isAgencyOpsMode: true,
            ),
            settings: effectiveSettings,
          );
        }

        // 3. Promoter & In-Store submission link (/c/unilever or /client/adco or /promoter/512)
        if (uri.pathSegments.length >= 2 && (uri.pathSegments[0] == 'c' || uri.pathSegments[0] == 'client' || uri.pathSegments[0] == 'promoter')) {
          final slug = uri.pathSegments[1].trim();
          final eventId = uri.queryParameters['event'] ?? uri.queryParameters['id'];
          if (slug.isEmpty && (eventId == null || eventId.trim().isEmpty)) {
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: effectiveSettings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => ClientReceiptUploadScreen(
              companySlug: slug,
              initialEventId: eventId,
            ),
            settings: effectiveSettings,
          );
        }

        // 4. Agency Operations & Field Management Portal link (/ops/unilever or /agency/adco or /operations/512)
        if (uri.pathSegments.length >= 2 &&
            (uri.pathSegments[0] == 'ops' || uri.pathSegments[0] == 'agency' || uri.pathSegments[0] == 'operations')) {
          final slug = uri.pathSegments[1].trim();
          final eventId = uri.queryParameters['event'] ?? uri.queryParameters['id'];
          if (slug.isEmpty && (eventId == null || eventId.trim().isEmpty)) {
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: effectiveSettings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => CompanyManagerPortalScreen(
              companySlug: slug,
              initialEventId: eventId,
              isAgencyOpsMode: true,
            ),
            settings: effectiveSettings,
          );
        }

        // 5. Brand Executive Master Portal link (/portal/unilever or /p/juhayna or /brand/512 or /company/adco)
        if (uri.pathSegments.length >= 2 &&
            (uri.pathSegments[0] == 'portal' || uri.pathSegments[0] == 'p' || uri.pathSegments[0] == 'brand' || uri.pathSegments[0] == 'company')) {
          final slug = uri.pathSegments[1].trim();
          final eventId = uri.queryParameters['event'] ?? uri.queryParameters['id'];
          if (slug.isEmpty && (eventId == null || eventId.trim().isEmpty)) {
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: effectiveSettings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => CompanyManagerPortalScreen(
              companySlug: slug,
              initialEventId: eventId,
              isAgencyOpsMode: false,
            ),
            settings: effectiveSettings,
          );
        }

        final normalizedPath = uri.path.replaceAll(RegExp(r'/+$'), '');

        switch (normalizedPath) {
          case '/admin':
            return MaterialPageRoute(
              builder: (context) => const AdminAuthGuard(),
              settings: effectiveSettings,
            );
          case '/portal':
          case '/p':
          case '/company':
            final slug = (uri.queryParameters['company'] ?? uri.queryParameters['slug'] ?? '').trim();
            final eventId = uri.queryParameters['event'] ?? uri.queryParameters['id'];
            if (slug.isEmpty && (eventId == null || eventId.trim().isEmpty)) {
              return MaterialPageRoute(
                builder: (context) => const AuthScreen(),
                settings: effectiveSettings,
              );
            }
            return MaterialPageRoute(
              builder: (context) => CompanyManagerPortalScreen(
                companySlug: slug,
                initialEventId: eventId,
              ),
              settings: effectiveSettings,
            );
          case '/ops':
          case '/agency':
          case '/operations':
            final slug = (uri.queryParameters['company'] ?? uri.queryParameters['slug'] ?? '').trim();
            final eventId = uri.queryParameters['event'] ?? uri.queryParameters['id'];
            if (slug.isEmpty && (eventId == null || eventId.trim().isEmpty)) {
              return MaterialPageRoute(
                builder: (context) => const AuthScreen(),
                settings: effectiveSettings,
              );
            }
            return MaterialPageRoute(
              builder: (context) => CompanyManagerPortalScreen(
                companySlug: slug,
                initialEventId: eventId,
                isAgencyOpsMode: true,
              ),
              settings: effectiveSettings,
            );
          case '/submit':
          case '/c':
          case '/client':
          case '/promoter':
            final slug = (uri.queryParameters['company'] ?? uri.queryParameters['slug'] ?? '').trim();
            final eventId = uri.queryParameters['event'] ?? uri.queryParameters['id'];
            if (slug.isEmpty && (eventId == null || eventId.trim().isEmpty)) {
              return MaterialPageRoute(
                builder: (context) => const AuthScreen(),
                settings: effectiveSettings,
              );
            }
            return MaterialPageRoute(
              builder: (context) => ClientReceiptUploadScreen(
                companySlug: slug,
                initialEventId: eventId,
              ),
              settings: effectiveSettings,
            );
          case '/login':
          case '/auth':
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: effectiveSettings,
            );
          case '':
          case '/':
          default:
            return MaterialPageRoute(
              builder: (context) => const AdminAuthGuard(),
              settings: effectiveSettings,
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

    final authState = ref.watch(authStateStreamProvider);
    return authState.when(
      data: (user) {
        if (user != null && isAuthorizedAdminEmail(user.email)) {
          return const AdminDashboardScreen();
        }
        return const AuthScreen();
      },
      loading: () {
        final sessionEmail = ref.watch(adminSessionEmailProvider);
        if (sessionEmail != null && isAuthorizedAdminEmail(sessionEmail)) {
          return const AdminDashboardScreen();
        }
        return const AuthScreen();
      },
      error: (error, stack) => const AuthScreen(),
    );
  }
}



