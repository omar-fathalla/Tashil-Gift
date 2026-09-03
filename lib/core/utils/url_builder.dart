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
  /// When [cleanUrl] is true (default for sharing), generates path without hash (e.g. https://tashil-gift.web.app/c/almarai?event=xyz)
  /// which enables WhatsApp and social crawlers to dynamically fetch the company brand logo.
  static String buildPromoterUrl(
    String companySlug, {
    String? eventId,
    bool forceProduction = false,
    bool cleanUrl = true,
  }) {
    final baseUrl = getBaseUrl(forceProduction: forceProduction);
    final cleanSlug = companySlug.trim().toLowerCase();
    final prefix = cleanUrl ? '' : '/#';
    if (cleanSlug.isEmpty && eventId != null && eventId.isNotEmpty) {
      return '$baseUrl$prefix/event/$eventId';
    }
    if (cleanSlug.isEmpty) {
      return baseUrl;
    }
    if (eventId != null && eventId.isNotEmpty) {
      return '$baseUrl$prefix/c/$cleanSlug?event=$eventId';
    }
    return '$baseUrl$prefix/c/$cleanSlug';
  }

  /// Builds a company manager / partner portal URL.
  /// When [cleanUrl] is true (default for sharing), generates path without hash (e.g. https://tashil-gift.web.app/portal/almarai?event=xyz)
  /// which enables WhatsApp and social crawlers to dynamically fetch the company brand logo.
  static String buildManagerPortalUrl(
    String companySlug, {
    String? eventId,
    bool forceProduction = false,
    bool cleanUrl = true,
  }) {
    final baseUrl = getBaseUrl(forceProduction: forceProduction);
    final cleanSlug = companySlug.trim().toLowerCase();
    final prefix = cleanUrl ? '' : '/#';
    if (cleanSlug.isEmpty && eventId != null && eventId.isNotEmpty) {
      return '$baseUrl$prefix/portal/$eventId';
    }
    if (cleanSlug.isEmpty) {
      return baseUrl;
    }
    if (eventId != null && eventId.isNotEmpty) {
      return '$baseUrl$prefix/portal/$cleanSlug?event=$eventId';
    }
    return '$baseUrl$prefix/portal/$cleanSlug';
  }
}
