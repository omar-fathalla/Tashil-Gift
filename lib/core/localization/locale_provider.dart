import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supported application languages
enum AppLanguage {
  arabic('ar', 'العربية', 'عربي', '🇦🇪'),
  english('en', 'English', 'EN', '🇬🇧'),
  hindi('hi', 'हिन्दी (Hindi UAE)', 'हिन्दी', '🇮🇳');

  final String code;
  final String label;
  final String shortLabel;
  final String flagEmoji;

  const AppLanguage(this.code, this.label, this.shortLabel, this.flagEmoji);
}

/// Global provider for the active locale.
/// Default is Arabic ('ar') as required.
final localeProvider = StateProvider<Locale>((ref) {
  // Optional ?lang=en|hi on the URL (e.g. links shared with English-speaking reps).
  final lang = Uri.base.queryParameters['lang'];
  if (lang == 'en' || lang == 'hi') return Locale(lang!, '');
  return const Locale('ar', '');
});

/// Helper extension on WidgetRef to easily query and toggle language
extension LocaleRefExtensions on WidgetRef {
  AppLanguage get currentAppLanguage {
    final code = watch(localeProvider).languageCode;
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.arabic,
    );
  }

  bool get isArabic => watch(localeProvider).languageCode == 'ar';
  bool get isEnglish => watch(localeProvider).languageCode == 'en';
  bool get isHindi => watch(localeProvider).languageCode == 'hi';
  Locale get currentLocale => watch(localeProvider);

  void toggleLanguage() {
    final current = read(localeProvider).languageCode;
    if (current == 'ar') {
      read(localeProvider.notifier).state = const Locale('en', '');
    } else if (current == 'en') {
      read(localeProvider.notifier).state = const Locale('hi', '');
    } else {
      read(localeProvider.notifier).state = const Locale('ar', '');
    }
  }

  void setLocale(String languageCode) {
    read(localeProvider.notifier).state = Locale(languageCode, '');
  }
}
