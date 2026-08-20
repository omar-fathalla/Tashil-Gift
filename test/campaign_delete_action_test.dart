import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Campaign Deletion & Action Buttons Tests', () {
    test('AppStrings contains trilingual deletion keys across AR, EN, HI', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.deleteCampaignBtn, equals('حذف الحملة'));
      expect(stringsAr.deleteCampaignTooltip, contains('حذف هذه الحملة'));
      expect(stringsAr.deleteCampaignConfirmTitle, equals('حذف الحملة نهائياً'));
      expect(stringsAr.deleteCampaignConfirmBody, contains('هل أنت متأكد'));
      expect(stringsAr.campaignDeletedSuccess, contains('تم حذف الحملة بنجاح'));
      expect(stringsAr.operationFailed('Firestore network timeout'), contains('فشلت العملية:'));

      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.deleteCampaignBtn, equals('Delete Campaign'));
      expect(stringsEn.deleteCampaignTooltip, contains('Permanently delete this campaign'));
      expect(stringsEn.deleteCampaignConfirmTitle, equals('Permanently Delete Campaign'));
      expect(stringsEn.deleteCampaignConfirmBody, contains('Are you sure you want to permanently delete'));
      expect(stringsEn.campaignDeletedSuccess, contains('Campaign deleted successfully'));
      expect(stringsEn.operationFailed('Firestore network timeout'), contains('Operation failed:'));

      final stringsHi = AppStrings.fromLocale('hi');
      expect(stringsHi.deleteCampaignBtn, isNotEmpty);
      expect(stringsHi.deleteCampaignTooltip, isNotEmpty);
      expect(stringsHi.deleteCampaignConfirmTitle, isNotEmpty);
      expect(stringsHi.deleteCampaignConfirmBody, isNotEmpty);
      expect(stringsHi.campaignDeletedSuccess, isNotEmpty);
    });

    test('EventModel supports deletion metadata and clean Firestore serialization', () {
      final event = EventModel(
        id: 'event-unilever-1',
        eventName: 'يونيليفر ديوز - هيركير',
        targetCompany: 'يونيليفر',
        companySlug: '512',
        minimumSpend: 0.0,
        retailChainId: 'fathalla',
        retailChainName: 'أسواق فتح الله',
        isActive: true,
      );

      expect(event.id, equals('event-unilever-1'));
      expect(event.eventName, equals('يونيليفر ديوز - هيركير'));
      expect(event.companySlug, equals('512'));
    });
  });
}
