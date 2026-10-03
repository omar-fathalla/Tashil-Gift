import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/localization/locale_provider.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/theme/app_theme.dart';

void main() {
  group('Localization System Tests (Trilingual: Arabic, English, Hindi)', () {
    test('Default locale must be Arabic (ar)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initialLocale = container.read(localeProvider);
      expect(initialLocale.languageCode, equals('ar'));
    });

    test('Default theme mode must be Light Mode', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initialThemeMode = container.read(themeModeProvider);
      expect(initialThemeMode, equals(ThemeMode.light));
    });

    test('Toggling language switches correctly between ar, en, and hi', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(localeProvider).languageCode, equals('ar'));

      // Switch to English
      container.read(localeProvider.notifier).state = const Locale('en', '');
      expect(container.read(localeProvider).languageCode, equals('en'));

      // Switch to Hindi
      container.read(localeProvider.notifier).state = const Locale('hi', '');
      expect(container.read(localeProvider).languageCode, equals('hi'));

      // Switch back to Arabic
      container.read(localeProvider.notifier).state = const Locale('ar', '');
      expect(container.read(localeProvider).languageCode, equals('ar'));
    });

    test('AppStrings returns valid non-empty strings in Arabic, English, and Hindi', () {
      final stringsAr = AppStrings('ar');
      final stringsEn = AppStrings('en');
      final stringsHi = AppStrings('hi');

      // Navigation & Header
      expect(stringsAr.navEventsManagement, equals('الحملات'));
      expect(stringsEn.navEventsManagement, equals('Campaigns'));
      expect(stringsHi.navEventsManagement, equals('अभियान'));

      expect(stringsAr.navAnalytics, equals('التقارير'));
      expect(stringsEn.navAnalytics, equals('Reports'));
      expect(stringsHi.navAnalytics, equals('रिपोर्ट'));

      expect(stringsAr.navCompanyCatalog, equals('التكويد'));
      expect(stringsEn.navCompanyCatalog, equals('Catalog'));
      expect(stringsHi.navCompanyCatalog, equals('सूची'));

      expect(stringsAr.navRetailChains, equals('السلاسل'));
      expect(stringsEn.navRetailChains, equals('Chains'));
      expect(stringsHi.navRetailChains, equals('चेन'));

      expect(stringsAr.navInvoicesAudit, equals('الفواتير'));
      expect(stringsEn.navInvoicesAudit, equals('Invoices'));
      expect(stringsHi.navInvoicesAudit, equals('रसीदें'));

      expect(stringsAr.navCreateCampaign, equals('إنشاء حملة جديدة'));
      expect(stringsEn.navCreateCampaign, equals('Create New Campaign'));
      expect(stringsHi.navCreateCampaign, equals('नया अभियान बनाएं'));

      expect(stringsAr.navCompanyGifts, equals('الهدايا'));
      expect(stringsEn.navCompanyGifts, equals('Gifts'));
      expect(stringsHi.navCompanyGifts, equals('उपहार'));

      expect(stringsAr.navGameTypes, equals('الألعاب'));
      expect(stringsEn.navGameTypes, equals('Games'));
      expect(stringsHi.navGameTypes, equals('खेल'));

      // Common actions
      expect(stringsAr.save, equals('حفظ'));
      expect(stringsEn.save, equals('Save'));
      expect(stringsHi.save, equals('सहेजें'));

      expect(stringsAr.cancel, equals('إلغاء'));
      expect(stringsEn.cancel, equals('Cancel'));
      expect(stringsHi.cancel, equals('रद्द करें'));

      expect(stringsAr.delete, equals('حذف'));
      expect(stringsEn.delete, equals('Delete'));
      expect(stringsHi.delete, equals('हटाएं'));

      // Authentication & Login
      expect(stringsAr.authSignInTitle, equals('تسجيل الدخول للنظام'));
      expect(stringsEn.authSignInTitle, equals('System Sign In'));
      expect(stringsHi.authSignInTitle, equals('सिस्टम में लॉगिन करें'));

      expect(stringsAr.authEmailLabel, equals('البريد الإلكتروني'));
      expect(stringsEn.authEmailLabel, equals('Email Address'));
      expect(stringsHi.authEmailLabel, equals('ईमेल पता'));

      expect(stringsAr.authPasswordLabel, equals('كلمة المرور'));
      expect(stringsEn.authPasswordLabel, equals('Password'));
      expect(stringsHi.authPasswordLabel, equals('पासवर्ड'));

      expect(stringsAr.authSignInBtn, equals('دخول الحساب'));
      expect(stringsEn.authSignInBtn, equals('Sign In'));
      expect(stringsHi.authSignInBtn, equals('साइन इन करें'));

      expect(stringsAr.authQuickDemoBtn, equals('دخول تجريبي سريع (تخطي التحقق)'));
      expect(stringsEn.authQuickDemoBtn, equals('Quick Demo Sign In (Bypass Auth)'));
      expect(stringsHi.authQuickDemoBtn, equals('त्वरित डेमो लॉगिन (सत्यापन छोड़ें)'));

      expect(stringsAr.authSuperAdminBtn, equals('لوحة تحكم المشرف (Admin)'));
      expect(stringsEn.authSuperAdminBtn, equals('Super Admin Dashboard'));
      expect(stringsHi.authSuperAdminBtn, equals('सुपर व्यवस्थापक डैशबोर्ड (Admin)'));

      // AI Receipt Validation
      expect(stringsAr.validationScreenSubtitle, equals('شاشة فحص وتدقيق الفواتير بالذكاء الاصطناعي'));
      expect(stringsEn.validationScreenSubtitle, equals('AI Receipt Audit & Intelligent Verification Screen'));
      expect(stringsHi.validationScreenSubtitle, equals('एआई रसीद ऑडिट और स्मार्ट सत्यापन स्क्रीन'));

      expect(stringsAr.captureReceiptBtn, equals('التقاط صورة الفاتورة بالكاميرا'));
      expect(stringsEn.captureReceiptBtn, equals('Capture Receipt Photo with Camera'));
      expect(stringsHi.captureReceiptBtn, equals('कैमरे से रसीद की तस्वीर लें'));
    });
  });
}
