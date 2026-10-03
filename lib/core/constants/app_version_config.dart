/// Application Version & Build Tracking Configuration
///
/// This file is automatically maintained and incremented upon each authorized
/// release deployment to Firebase Hosting and Git push to GitHub.
class AppVersionConfig {
  /// Major version (Breaking architectural changes)
  static const int major = 2;

  /// Minor version (Major feature releases)
  static const int minor = 0;

  /// Patch / Iteration version (Feature additions, enhancements, bugfixes)
  static const int patch = 81;

  /// Global sequential build counter (Increments on every deployment)
  static const int buildNumber = 136;

  /// Release date of the current build
  static const String releaseDate = '2026-10-03';

  /// Environment tag
  static const String environment = 'Production (Firebase)';

  /// Clean display string for headers and badges (e.g. "v2.0.1")
  static const String versionDisplay = 'v$major.$minor.$patch';

  /// Full technical build identifier (e.g. "v2.0.1 (Build #56)")
  static const String fullBuildDisplay = '$versionDisplay (Build #$buildNumber)';

  /// SemVer build string for pubspec compatibility (e.g. "2.0.1+56")
  static const String semVer = '$major.$minor.$patch+$buildNumber';

  /// Detailed release info tooltip text
  static String get tooltipText =>
      'Tashil Gift $versionDisplay\nBuild: #$buildNumber\nUpdated: $releaseDate\nEnv: $environment';
}
