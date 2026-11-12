import 'dart:io';

import 'package:al_mraay/features/company_portal/domain/company_supervisor.dart';
import 'package:al_mraay/features/company_portal/domain/company_supervisor_import.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_gateway_service.dart';
import 'package:al_mraay/features/company_portal/presentation/widgets/whatsapp_campaign_dispatcher_dialog.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owner workbook keeps 418 unique mobiles and both provided test rows', () {
    final bytes = File('tool/seeds/company-supervisors.xlsx').readAsBytesSync();
    final result = parseCompanySupervisorWorkbook(Uint8List.fromList(bytes), fileName: 'company-supervisors.xlsx');

    expect(result.errorMessage, isNull);
    expect(result.sourceRowCount, 424);
    expect(result.uniqueCount, 418);
    expect(result.duplicateRowCount, 6);
    expect(result.invalidRowCount, 0);
    expect(result.duplicateGroups, hasLength(6));

    final byMobile = {for (final supervisor in result.supervisors) supervisor.mobile: supervisor};
    expect(byMobile['01099999997']?.name, 'مشرف تجريبي Test Supervisor');
    expect(byMobile['01234567890']?.name, 'admin company');

    expect(byMobile['01060249094']?.name, 'mohamed ayman elgyar');
    expect(byMobile['01060249094']?.alternateNames, ['mohamedayman']);
    expect(byMobile['01229703053']?.name, 'الشركة المصرية السويسرية');
    expect(byMobile['01229703053']?.alternateNames, ['ahmed farouk']);
    expect(byMobile['01286699817']?.name, 'شمس يحيى');
    expect(byMobile['01286699817']?.alternateNames, ['شمس']);
    expect(byMobile['01013003411']?.name, 'محمود فوزى اسماعيل');
    expect(byMobile['01013003411']?.alternateNames, ['mahmoud fawzy']);
    expect(byMobile['01220712234']?.name, 'علاء يوسف');
    expect(byMobile['01220712234']?.alternateNames, ['فؤاد علاء']);
    expect(byMobile['01020402645']?.name, 'may mostafa');
    expect(byMobile['01020402645']?.alternateNames, ['محمد صلاح']);

    for (final supervisor in result.supervisors) {
      expect(supervisor.mobile, matches(RegExp(r'^01[0125]\d{8}$')));
      expect(supervisor.cleanPhone, WhatsAppGatewayService.formatInternationalPhone(supervisor.mobile));
      expect(supervisor.cleanPhone, isNot(contains(RegExp(r'[٠-٩۰-۹]'))));
      expect(supervisor.id, supervisor.mobile);
    }
  });

  test('eastern digits and a dropped leading zero still merge onto one mobile', () {
    final excel = Excel.createExcel();
    final sheet = excel['أرقام وأسماء'];
    sheet.appendRow([
      TextCellValue('رقم الموبايل'),
      TextCellValue('اسم الشخص'),
    ]);
    sheet.appendRow([
      TextCellValue('٠١٠٦٠٢٤٩٠٩٤'),
      TextCellValue('اسم قصير'),
    ]);
    sheet.appendRow([
      IntCellValue(1060249094),
      TextCellValue('اسم أطول ومكتمل'),
    ]);
    final bytes = Uint8List.fromList(excel.save()!);
    final result = parseCompanySupervisorWorkbook(bytes, fileName: 'supervisors.xlsx');

    expect(result.uniqueCount, 1);
    expect(result.supervisors.single.mobile, '01060249094');
    expect(result.supervisors.single.name, 'اسم أطول ومكتمل');
    expect(result.supervisors.single.alternateNames, ['اسم قصير']);
  });

  test('supervisor search includes the alternate name and western mobile', () {
    final bytes = File('tool/seeds/company-supervisors.xlsx').readAsBytesSync();
    final result = parseCompanySupervisorWorkbook(Uint8List.fromList(bytes), fileName: 'company-supervisors.xlsx');
    final contact = CompanySupervisor.fromImport(
      result.supervisors.firstWhere((supervisor) => supervisor.mobile == '01060249094'),
    ).toCampaignContact();
    expect(contact.id, 'supervisor_01060249094');
    expect(contact.searchIndex.contains('mohamedayman'), isTrue);
    expect(contact.searchIndex.contains('01060249094'), isTrue);
    expect(contact.totalInvoices, 0);
    expect(contact.prizesWon, isEmpty);
  });
}
