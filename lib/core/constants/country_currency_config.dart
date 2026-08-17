import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Data model representing a country and its national currency
class CountryCurrency {
  final String code; // ISO-2 (e.g. 'EG', 'SA')
  final String nameAr; // e.g. 'مصر', 'السعودية'
  final String fullNameAr; // e.g. 'جمهورية مصر العربية'
  final String nameEn; // e.g. 'Egypt', 'Saudi Arabia'
  final String fullNameEn; // e.g. 'Arab Republic of Egypt'
  final String nameHi; // e.g. 'मिस्र', 'सऊदी अरब'
  final String fullNameHi; // e.g. 'मिस्र अरब गणराज्य'
  final String flagEmoji; // e.g. '🇪🇬', '🇸🇦'
  final String currencyCode; // ISO-3 (e.g. 'EGP', 'SAR')
  final String currencySymbol; // e.g. 'ج.م', 'ر.س'
  final String currencyNameAr; // e.g. 'الجنيه المصري', 'الريال السعودي'
  final String currencyNameEn; // e.g. 'Egyptian Pound', 'Saudi Riyal'
  final String currencyNameHi; // e.g. 'मिस्री पाउंड', 'सऊदी रियाल'

  const CountryCurrency({
    required this.code,
    required this.nameAr,
    required this.fullNameAr,
    this.nameEn = '',
    this.fullNameEn = '',
    this.nameHi = '',
    this.fullNameHi = '',
    required this.flagEmoji,
    required this.currencyCode,
    required this.currencySymbol,
    required this.currencyNameAr,
    this.currencyNameEn = '',
    this.currencyNameHi = '',
  });

  /// Returns localized short name
  String name(String languageCode) {
    if (languageCode == 'ar') return nameAr;
    if (languageCode == 'hi') return nameHi.isNotEmpty ? nameHi : nameEn;
    return nameEn.isNotEmpty ? nameEn : nameAr;
  }

  /// Returns localized full country name
  String fullName(String languageCode) {
    if (languageCode == 'ar') return fullNameAr;
    if (languageCode == 'hi') return fullNameHi.isNotEmpty ? fullNameHi : fullNameEn;
    return fullNameEn.isNotEmpty ? fullNameEn : fullNameAr;
  }

  /// Returns localized currency name
  String currencyName(String languageCode) {
    if (languageCode == 'ar') return currencyNameAr;
    if (languageCode == 'hi') return currencyNameHi.isNotEmpty ? currencyNameHi : currencyNameEn;
    return currencyNameEn.isNotEmpty ? currencyNameEn : currencyNameAr;
  }

  /// Returns formatted symbol or code based on language
  String currencySymbolFor(String languageCode) {
    if (languageCode == 'ar') return currencySymbol;
    return currencyCode;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CountryCurrency &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;
}

/// Global Country and Currency Configuration for Switch Point
class CountryCurrencyConfig {
  static const CountryCurrency defaultCountry = CountryCurrency(
    code: 'EG',
    nameAr: 'مصر',
    fullNameAr: 'جمهورية مصر العربية',
    nameEn: 'Egypt',
    fullNameEn: 'Arab Republic of Egypt',
    nameHi: 'मिस्र',
    fullNameHi: 'मिस्र अरब गणराज्य',
    flagEmoji: '🇪🇬',
    currencyCode: 'EGP',
    currencySymbol: 'ج.م',
    currencyNameAr: 'الجنيه المصري',
    currencyNameEn: 'Egyptian Pound',
    currencyNameHi: 'मिस्री पाउंड',
  );

  static const List<CountryCurrency> supportedCountries = [
    defaultCountry,
    CountryCurrency(
      code: 'SA',
      nameAr: 'السعودية',
      fullNameAr: 'المملكة العربية السعودية',
      nameEn: 'Saudi Arabia',
      fullNameEn: 'Kingdom of Saudi Arabia',
      nameHi: 'सऊदी अरब',
      fullNameHi: 'सऊदी अरब साम्राज्य',
      flagEmoji: '🇸🇦',
      currencyCode: 'SAR',
      currencySymbol: 'ر.س',
      currencyNameAr: 'الريال السعودي',
      currencyNameEn: 'Saudi Riyal',
      currencyNameHi: 'सऊदी रियाल',
    ),
    CountryCurrency(
      code: 'AE',
      nameAr: 'الإمارات',
      fullNameAr: 'الإمارات العربية المتحدة',
      nameEn: 'UAE',
      fullNameEn: 'United Arab Emirates',
      nameHi: 'यूएई',
      fullNameHi: 'संयुक्त अरब अमीरात',
      flagEmoji: '🇦🇪',
      currencyCode: 'AED',
      currencySymbol: 'د.إ',
      currencyNameAr: 'الدرهم الإماراتي',
      currencyNameEn: 'UAE Dirham',
      currencyNameHi: 'यूएई दिरहम',
    ),
    CountryCurrency(
      code: 'KW',
      nameAr: 'الكويت',
      fullNameAr: 'دولة الكويت',
      nameEn: 'Kuwait',
      fullNameEn: 'State of Kuwait',
      nameHi: 'कुवैत',
      fullNameHi: 'कुवैत राज्य',
      flagEmoji: '🇰🇼',
      currencyCode: 'KWD',
      currencySymbol: 'د.ك',
      currencyNameAr: 'الدينار الكويتي',
      currencyNameEn: 'Kuwaiti Dinar',
      currencyNameHi: 'कुवैती दिनार',
    ),
    CountryCurrency(
      code: 'QA',
      nameAr: 'قطر',
      fullNameAr: 'دولة قطر',
      nameEn: 'Qatar',
      fullNameEn: 'State of Qatar',
      nameHi: 'क़तर',
      fullNameHi: 'क़तर राज्य',
      flagEmoji: '🇶🇦',
      currencyCode: 'QAR',
      currencySymbol: 'ر.ق',
      currencyNameAr: 'الريال القطري',
      currencyNameEn: 'Qatari Riyal',
      currencyNameHi: 'क़तरी रियाल',
    ),
    CountryCurrency(
      code: 'BH',
      nameAr: 'البحرين',
      fullNameAr: 'مملكة البحرين',
      nameEn: 'Bahrain',
      fullNameEn: 'Kingdom of Bahrain',
      nameHi: 'बहरीन',
      fullNameHi: 'बहरीन साम्राज्य',
      flagEmoji: '🇧🇭',
      currencyCode: 'BHD',
      currencySymbol: 'د.ب',
      currencyNameAr: 'الدينار البحريني',
      currencyNameEn: 'Bahraini Dinar',
      currencyNameHi: 'बहरीनी दिनार',
    ),
    CountryCurrency(
      code: 'OM',
      nameAr: 'عُمان',
      fullNameAr: 'سلطنة عُمان',
      nameEn: 'Oman',
      fullNameEn: 'Sultanate of Oman',
      nameHi: 'ओमान',
      fullNameHi: 'ओमान सल्तनत',
      flagEmoji: '🇴🇲',
      currencyCode: 'OMR',
      currencySymbol: 'ر.ع',
      currencyNameAr: 'الريال العُماني',
      currencyNameEn: 'Omani Rial',
      currencyNameHi: 'ओमानी रियाल',
    ),
    CountryCurrency(
      code: 'JO',
      nameAr: 'الأردن',
      fullNameAr: 'المملكة الأردنية الهاشمية',
      nameEn: 'Jordan',
      fullNameEn: 'Hashemite Kingdom of Jordan',
      nameHi: 'जॉर्डन',
      fullNameHi: 'जॉर्डन का हाशमी साम्राज्य',
      flagEmoji: '🇯🇴',
      currencyCode: 'JOD',
      currencySymbol: 'د.أ',
      currencyNameAr: 'الدينار الأردني',
      currencyNameEn: 'Jordanian Dinar',
      currencyNameHi: 'जॉर्डनियाई दिनार',
    ),
  ];

  /// Find country by ISO country code
  static CountryCurrency findByCode(String code) {
    return supportedCountries.firstWhere(
      (c) => c.code.toUpperCase() == code.toUpperCase(),
      orElse: () => defaultCountry,
    );
  }

  /// Find country by ISO currency code (e.g. EGP, SAR)
  static CountryCurrency findByCurrencyCode(String currencyCode) {
    return supportedCountries.firstWhere(
      (c) => c.currencyCode.toUpperCase() == currencyCode.toUpperCase(),
      orElse: () => defaultCountry,
    );
  }
}

/// Riverpod StateProvider for active country & currency across the platform
final activeCountryProvider = StateProvider<CountryCurrency>((ref) {
  return CountryCurrencyConfig.defaultCountry;
});
