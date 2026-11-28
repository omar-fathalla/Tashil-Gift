/// Build-time environment of the app: production (`tashil-gift`) or
/// development (`tashil-gift-dev`).
///
/// Selected with `--dart-define=APP_ENV=dev`. Without it (every existing
/// build and the production deploy) the app is production, exactly as before.
///
///   flutter build web --release                           -> prod (tashil-gift)
///   flutter build web --release --dart-define=APP_ENV=dev -> dev (tashil-gift-dev)
///
/// See docs/DEV_ENVIRONMENT.md.
library;

enum AppEnvironment { prod, dev }

/// Raw value of `--dart-define=APP_ENV`. Empty means "not set" (= prod).
const String kAppEnvRaw = String.fromEnvironment('APP_ENV');

/// Firebase project id of each environment.
const String kProdProjectId = 'tashil-gift';
const String kDevProjectId = 'tashil-gift-dev';

/// Parses an APP_ENV value. Empty / `prod` / `production` -> prod,
/// `dev` / `development` -> dev (exact, lowercase). Anything else throws, so a
/// typo such as `APP_ENV=dve` can never silently build against production.
AppEnvironment parseAppEnvironment(String raw) {
  switch (raw) {
    case '':
    case 'prod':
    case 'production':
      return AppEnvironment.prod;
    case 'dev':
    case 'development':
      return AppEnvironment.dev;
    default:
      throw ArgumentError.value(
        raw,
        'APP_ENV',
        'Unknown APP_ENV. Use "prod" (default) or "dev".',
      );
  }
}

/// Compile-time constant: true only for `--dart-define=APP_ENV=dev`
/// (or `development`). Use this in `const` expressions.
const bool kIsDevEnv = kAppEnvRaw == 'dev' || kAppEnvRaw == 'development';

class AppEnv {
  AppEnv._();

  /// The environment of this build.
  static AppEnvironment get current => parseAppEnvironment(kAppEnvRaw);

  static bool get isDev => current == AppEnvironment.dev;
  static bool get isProd => current == AppEnvironment.prod;

  /// Short label stored in web/version.json (`env`) and shown in the UI.
  static String labelOf(AppEnvironment env) =>
      env == AppEnvironment.dev ? 'dev' : 'prod';

  static String get label => labelOf(current);

  /// Firebase project id this build talks to (ignoring the local emulator).
  static String projectIdOf(AppEnvironment env) =>
      env == AppEnvironment.dev ? kDevProjectId : kProdProjectId;

  /// Default Hosting origin of each environment (used only when the page
  /// origin is not available, e.g. mobile builds).
  static String hostingOriginOf(AppEnvironment env) =>
      'https://${projectIdOf(env)}.web.app';
}

/// Hosting origin for `const` contexts. Same value as before for prod.
const String kDefaultHostingOrigin =
    kIsDevEnv ? 'https://tashil-gift-dev.web.app' : 'https://tashil-gift.web.app';

/// Human-readable environment tag (header badge, version.json `environment`).
const String kEnvironmentDisplayName =
    kIsDevEnv ? 'Development (tashil-gift-dev)' : 'Production (Firebase)';
