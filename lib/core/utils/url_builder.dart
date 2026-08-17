import 'package:flutter/foundation.dart';

/// Central URL builder for Tashil Gift platform.
/// Handles generating links for Promoters and Company Managers
/// pointing dynamically to Firebase Hosting (or local test origin).
class AppUrlBuilder {
  /// Default Firebase Hosting domain for Tashil Gift
  static const String productionDomain = 'https://tashil-gift.web.app';

  /// Resolves the current base URL.
  /// On web, uses the current domain origin (e.g. https://tashil-gift.web.app or http://localhost:8080).
  /// If forceProduction is true, always uses the live Firebase production domain.
  static String getBaseUrl({bool forceProduction = false}) {
    if (forceProduction) {
      return productionDomain;
    }
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && origin != 'null' && !origin.startsWith('file://')) {
        return origin;
      }
    }
    return productionDomain;
  }

  /// Builds a promoter / customer submission URL.
  /// e.g. https://tashil-gift.web.app/#/c/almarai?event=xyz
  static String buildPromoterUrl(String companySlug, {String? eventId, bool forceProduction = false}) {
    final baseUrl = getBaseUrl(forceProduction: forceProduction);
    final cleanSlug = companySlug.trim().toLowerCase();
    if (eventId != null && eventId.isNotEmpty) {
      return '$baseUrl/#/c/$cleanSlug?event=$eventId';
    }
    return '$baseUrl/#/c/$cleanSlug';
  }

  /// Builds a company manager / partner portal URL.
  /// e.g. https://tashil-gift.web.app/#/portal/almarai?event=xyz
  static String buildManagerPortalUrl(String companySlug, {String? eventId, bool forceProduction = false}) {
    final baseUrl = getBaseUrl(forceProduction: forceProduction);
    final cleanSlug = companySlug.trim().toLowerCase();
    if (eventId != null && eventId.isNotEmpty) {
      return '$baseUrl/#/portal/$cleanSlug?event=$eventId';
    }
    return '$baseUrl/#/portal/$cleanSlug';
  }
}
