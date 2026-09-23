import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/company_portal/domain/customer_marketing_service.dart';
import 'package:al_mraay/features/company_portal/domain/marketing_contact_model.dart';
import 'package:excel/excel.dart';
import 'dart:convert';

void main() {
  group('CustomerMarketingService - Header & Field Detection Tests', () {
    test('Identifies phone headers correctly in Arabic and English', () {
      expect(CustomerMarketingService.isPhoneHeader('رقم الهاتف'), isTrue);
      expect(CustomerMarketingService.isPhoneHeader('الموبايل'), isTrue);
      expect(CustomerMarketingService.isPhoneHeader('رقم الواتساب'), isTrue);
      expect(CustomerMarketingService.isPhoneHeader('phone_number'), isTrue);
      expect(CustomerMarketingService.isPhoneHeader('mobile'), isTrue);
      expect(CustomerMarketingService.isPhoneHeader('whatsapp'), isTrue);

      expect(CustomerMarketingService.isPhoneHeader('اسم العميل'), isFalse);
      expect(CustomerMarketingService.isPhoneHeader('notes'), isFalse);
    });

    test('Identifies name headers correctly in Arabic and English', () {
      expect(CustomerMarketingService.isNameHeader('اسم العميل'), isTrue);
      expect(CustomerMarketingService.isNameHeader('الاسم'), isTrue);
      expect(CustomerMarketingService.isNameHeader('customer_name'), isTrue);
      expect(CustomerMarketingService.isNameHeader('full name'), isTrue);

      expect(CustomerMarketingService.isNameHeader('الفرع'), isFalse);
    });

    test('Identifies branch headers correctly in Arabic and English', () {
      expect(CustomerMarketingService.isBranchHeader('الفرع'), isTrue);
      expect(CustomerMarketingService.isBranchHeader('اسم الفرع'), isTrue);
      expect(CustomerMarketingService.isBranchHeader('المدينة'), isTrue);
      expect(CustomerMarketingService.isBranchHeader('branch'), isTrue);
      expect(CustomerMarketingService.isBranchHeader('outlet'), isTrue);
      expect(CustomerMarketingService.isBranchHeader('store'), isTrue);
    });

    test('Identifies notes headers correctly in Arabic and English', () {
      expect(CustomerMarketingService.isNotesHeader('ملاحظات'), isTrue);
      expect(CustomerMarketingService.isNotesHeader('ملاحظة'), isTrue);
      expect(CustomerMarketingService.isNotesHeader('تعليق'), isTrue);
      expect(CustomerMarketingService.isNotesHeader('notes'), isTrue);
      expect(CustomerMarketingService.isNotesHeader('remark'), isTrue);
    });
  });

  group('CustomerMarketingService - CSV Parsing & Phone Normalization', () {
    final service = CustomerMarketingService();

    test('Parses CSV with Arabic headers and normalizes Egyptian phone numbers', () async {
      const csvData = '''اسم العميل,رقم الموبايل,الفرع,ملاحظات
أحمد علي,01012345678,فرع التجمع,عميل VIP
سارة محمد,01123456789,فرع المهندسين,مشتريات دورية
محمود حسن,01234567890,فرع سموحة,
''';
      final bytes = utf8.encode(csvData);

      final result = await service.parseExcelOrCsv(
        bytes: bytes,
        fileName: 'test_customers.csv',
        companySlug: 'unilever',
      );

      expect(result.isSuccess, isTrue);
      expect(result.validContacts.length, equals(3));
      expect(result.invalidRowsCount, equals(0));
      expect(result.duplicatesFilteredCount, equals(0));

      final first = result.validContacts.first;
      expect(first.name, equals('أحمد علي'));
      expect(first.cleanPhone, equals('201012345678'));
      expect(first.branch, equals('فرع التجمع'));
      expect(first.notes, equals('عميل VIP'));
      expect(first.companySlug, equals('unilever'));
      expect(first.source, equals('excel_import'));
    });

    test('Filters duplicate phone numbers within the same file', () async {
      const csvData = '''اسم العميل,رقم الهاتف,الفرع
عميل 1,01012345678,فرع 1
عميل 2 مكرر,01012345678,فرع 2
عميل 3,01599998888,فرع 3
''';
      final bytes = utf8.encode(csvData);

      final result = await service.parseExcelOrCsv(
        bytes: bytes,
        fileName: 'duplicates.csv',
        companySlug: 'cadbury',
      );

      expect(result.validContacts.length, equals(2));
      expect(result.duplicatesFilteredCount, equals(1));
      expect(result.validContacts.map((c) => c.cleanPhone).toList(),
          containsAll(['201012345678', '201599998888']));
    });

    test('Converts Eastern Arabic numerals (٠-٩) in phone numbers', () async {
      const csvData = '''الاسم,الهاتف
كريم سعيد,٠١٠٢٣٤٥٦٧٨٩
''';
      final bytes = utf8.encode(csvData);

      final result = await service.parseExcelOrCsv(
        bytes: bytes,
        fileName: 'arabic_digits.csv',
        companySlug: 'unilever',
      );

      expect(result.validContacts.length, equals(1));
      expect(result.validContacts.first.cleanPhone, equals('201023456789'));
    });

    test('Flags rows with invalid or missing phone numbers', () async {
      const csvData = '''الاسم,رقم الهاتف
عميل صحيح,01012345678
عميل بدون رقم,
عميل برقم قصير جداً,12345
''';
      final bytes = utf8.encode(csvData);

      final result = await service.parseExcelOrCsv(
        bytes: bytes,
        fileName: 'invalid_data.csv',
        companySlug: 'test_company',
      );

      expect(result.validContacts.length, equals(1));
      expect(result.invalidRowsCount, equals(2));
    });
  });

  group('CustomerMarketingService - Excel Generation & Parsing', () {
    final service = CustomerMarketingService();

    test('Generates valid downloadable Excel template with sample data', () async {
      final templateBytes = CustomerMarketingService.generateSampleExcelTemplate();
      expect(templateBytes, isNotEmpty);

      // Verify that the generated template can be parsed back
      final excel = Excel.decodeBytes(templateBytes);
      expect(excel.tables.isNotEmpty, isTrue);

      final defaultSheet = excel.tables[excel.tables.keys.first]!;
      expect(defaultSheet.maxRows, greaterThanOrEqualTo(4)); // Header + 3 sample rows

      // Now parse it using our service
      final parseResult = await service.parseExcelOrCsv(
        bytes: templateBytes,
        fileName: 'Sample_Template.xlsx',
        companySlug: 'unilever',
      );

      expect(parseResult.isSuccess, isTrue);
      expect(parseResult.validContacts.length, equals(3));
      expect(parseResult.validContacts[0].cleanPhone, equals('201012345678'));
      expect(parseResult.validContacts[1].cleanPhone, equals('201211857725'));
      expect(parseResult.validContacts[2].cleanPhone, equals('201198765432'));
    });
  });

  group('MarketingContactModel - Integration Tests', () {
    test('Converts correctly to CustomerCampaignContact for WhatsApp campaign', () {
      final contact = MarketingContactModel(
        id: 'unilever_201012345678',
        name: 'محمد عبد الله',
        rawPhone: '01012345678',
        cleanPhone: '201012345678',
        branch: 'فرع سان ستيفانو',
        companySlug: 'unilever',
        source: 'excel_import',
        notes: 'عميل مستهدف لحملة الشتاء',
        createdAt: DateTime(2026, 9, 19),
      );

      final campaignContact = contact.toCustomerCampaignContact();
      expect(campaignContact.id, equals(contact.id));
      expect(campaignContact.name, equals('محمد عبد الله'));
      expect(campaignContact.rawPhone, equals('01012345678'));
      expect(campaignContact.cleanPhone, equals('201012345678'));
      expect(campaignContact.sourceTag, equals('excel_import'));
      expect(campaignContact.branches, contains('فرع سان ستيفانو'));
    });
  });
}
