import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/localization/locale_provider.dart';
import 'core/services/firebase_service.dart';
import 'core/utils/app_url_strategy.dart';
import 'core/widgets/campaign_suspended_screen.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/admin/presentation/admin_dashboard_screen.dart';
import 'features/client_portal/presentation/client_receipt_upload_screen.dart';
import 'features/company_portal/presentation/company_manager_portal_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppPathUrlStrategy();
  
  // Filter out harmless Flutter Web engine Hot-Restart / disposed view assertions
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    if (msg.contains('disposed EngineFlutterView') ||
        msg.contains('Trying to render a disposed EngineFlutterView')) {
      // Harmless web engine teardown noise during hot-restart or browser tab refresh
      return;
    }
    if (originalOnError != null) {
      originalOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  // Initialize Firebase with the mock/configured options.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Ensure background anonymous auth session if no active user for seamless Firestore/Storage access
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (_) {}

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

    // 1. If raw contains a hash fragment prefix (e.g. /#/ops/1434?event=... or #/c/1434)
    if (raw.startsWith('/#') || raw.startsWith('#')) {
      final stripped = raw.replaceFirst(RegExp(r'^/?#?!?/?'), '/');
      var parsed = Uri.parse(stripped);
      if (kIsWeb) {
        final base = Uri.base;
        if (parsed.queryParameters.isEmpty && base.queryParameters.isNotEmpty) {
          parsed = parsed.replace(queryParameters: base.queryParameters);
        }
      }
      return parsed;
    }

    if (kIsWeb) {
      final base = Uri.base;

      // 2. If base has a hash fragment (e.g. browser URL is http://localhost/#/ops/1434)
      if (base.fragment.isNotEmpty) {
        final frag = base.fragment.replaceFirst(RegExp(r'^!?/?'), '/');
        final parsed = Uri.parse(frag);
        if (parsed.queryParameters.isEmpty && base.queryParameters.isNotEmpty) {
          return parsed.replace(queryParameters: base.queryParameters);
        }
        return parsed;
      }

      // 3. If raw is empty or root '/', but base has a deep path
      if (raw == '/' || raw.isEmpty) {
        if (base.path.isNotEmpty && base.path != '/') {
          final full = base.query.isNotEmpty ? '${base.path}?${base.query}' : base.path;
          return Uri.parse(full);
        }
      }

      // 4. Ensure query parameters from base are preserved if raw omitted them
      final parsedRaw = Uri.parse(raw);
      if (parsedRaw.queryParameters.isEmpty && base.queryParameters.isNotEmpty) {
        return parsedRaw.replace(queryParameters: base.queryParameters);
      }
      return parsedRaw;
    }

    return Uri.parse(raw);
  }

  /// Single-resolution route builder for any given URI.
  /// Prevents Flutter Navigator from decomposing deep links into multiple intermediate routes.
  Route<dynamic> _buildRouteForUri(Uri uri, {RouteSettings? originalSettings}) {
    final effectiveSettings = RouteSettings(
      name: uri.toString(),
      arguments: originalSettings?.arguments,
    );

    // 1. Direct Event Link (/event/xyz or /e/xyz)
    if (uri.pathSegments.length >= 2 && (uri.pathSegments[0] == 'event' || uri.pathSegments[0] == 'e')) {
      final eventId = uri.pathSegments[1].trim();
      if (eventId.isEmpty) {
        return MaterialPageRoute(
          builder: (context) => const CampaignSuspendedScreen(
            portalType: SuspendedPortalType.promoter,
            event: null,
            companySlug: '',
            companyName: 'الرابط غير صالح',
          ),
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
          builder: (context) => const CampaignSuspendedScreen(
            portalType: SuspendedPortalType.agency,
            event: null,
            companySlug: '',
            companyName: 'الرابط غير صالح',
          ),
          settings: effectiveSettings,
        );
      }
      return MaterialPageRoute(
        builder: (context) => CompanyManagerPortalScreen(
          companySlug: '',
          initialEventId: eventId,
          isAgencyOpsMode: true,
          requirePortalAuth: true,
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
          builder: (context) => const CampaignSuspendedScreen(
            portalType: SuspendedPortalType.promoter,
            event: null,
            companySlug: '',
            companyName: 'الرابط غير صالح',
          ),
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
          builder: (context) => const CampaignSuspendedScreen(
            portalType: SuspendedPortalType.agency,
            event: null,
            companySlug: '',
            companyName: 'الرابط غير صالح',
          ),
          settings: effectiveSettings,
        );
      }
      return MaterialPageRoute(
        builder: (context) => CompanyManagerPortalScreen(
          companySlug: slug,
          initialEventId: eventId,
          isAgencyOpsMode: true,
          requirePortalAuth: true,
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
          builder: (context) => const CampaignSuspendedScreen(
            portalType: SuspendedPortalType.manager,
            event: null,
            companySlug: '',
            companyName: 'الرابط غير صالح',
          ),
          settings: effectiveSettings,
        );
      }
      return MaterialPageRoute(
        builder: (context) => CompanyManagerPortalScreen(
          companySlug: slug,
          initialEventId: eventId,
          isAgencyOpsMode: false,
          requirePortalAuth: true,
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
            builder: (context) => const CampaignSuspendedScreen(
              portalType: SuspendedPortalType.manager,
              event: null,
              companySlug: '',
              companyName: 'الرابط غير صالح',
            ),
            settings: effectiveSettings,
          );
        }
        return MaterialPageRoute(
          builder: (context) => CompanyManagerPortalScreen(
            companySlug: slug,
            initialEventId: eventId,
            requirePortalAuth: true,
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
            builder: (context) => const CampaignSuspendedScreen(
              portalType: SuspendedPortalType.agency,
              event: null,
              companySlug: '',
              companyName: 'الرابط غير صالح',
            ),
            settings: effectiveSettings,
          );
        }
        return MaterialPageRoute(
          builder: (context) => CompanyManagerPortalScreen(
            companySlug: slug,
            initialEventId: eventId,
            isAgencyOpsMode: true,
            requirePortalAuth: true,
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
            builder: (context) => const CampaignSuspendedScreen(
              portalType: SuspendedPortalType.promoter,
              event: null,
              companySlug: '',
              companyName: 'الرابط غير صالح',
            ),
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
      onGenerateInitialRoutes: (initialRouteName) {
        final uri = _resolveRouteUri(RouteSettings(name: initialRouteName));
        return [
          _buildRouteForUri(uri),
        ];
      },
      onGenerateRoute: (settings) {
        final uri = _resolveRouteUri(settings);
        return _buildRouteForUri(uri, originalSettings: settings);
      },
    );
  }
}

class AdminAuthGuard extends ConsumerWidget {
  const AdminAuthGuard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      final isAdmin = ref.watch(isAdminProvider);
      if (isAdmin) {
        return const AdminDashboardScreen();
      }

      final authState = ref.watch(authStateStreamProvider);
      return authState.when(
        data: (user) {
          if (user != null && !user.isAnonymous && isAuthorizedAdminEmail(user.email)) {
            return const AdminDashboardScreen();
          }
          return const AuthScreen();
        },
        loading: () {
          final colorScheme = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: colorScheme.surface,
            body: Center(
              child: CircularProgressIndicator(
                color: colorScheme.primary,
              ),
            ),
          );
        },
        error: (error, stack) => const AuthScreen(),
      );
    } catch (_) {
      return const AuthScreen();
    }
  }
}



