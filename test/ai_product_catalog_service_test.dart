@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:al_mraay/core/services/ai_product_catalog_service.dart';

void main() {
  group('AiProductCatalogService Tests', () {
    final service = AiProductCatalogService();

    test('Parses multi-column CSV and normalizes Eastern Arabic digits', () async {
      const csvData = '''اسم الصنف,المجموعة,الحجم,الباركود الدولي,السعر
حليب كامل الدسم,ألبان,1 لتر,٦٢٨١٠٠٧٠٠١٠٠١,١٥.٥
زبادي طبيعي,ألبان,١٧٠ جم,6281007002001.0,3.0
عصير مانجو فاخر,عصائر,250 مل,6281007003001,5.25''';

      final bytes = Uint8List.fromList(utf8.encode(csvData));
      final result = await service.analyzeAndParseFile(
        fileBytes: bytes,
        fileName: 'marai_products.csv',
        companyNameHint: 'المراعي',
      );

      expect(result.isSuccess, isTrue);
      expect(result.products.length, equals(3));

      // First product check
      final p1 = result.products[0];
      expect(p1.productName, contains('حليب كامل الدسم'));
      expect(p1.barcode, equals('6281007001001')); // normalized from Eastern Arabic ٦٢٨١٠٠٧٠٠١٠٠١

      // Second product check (check float .0 removal)
      final p2 = result.products[1];
      expect(p2.barcode, equals('6281007002001'));

      // Third product check
      final p3 = result.products[2];
      expect(p3.barcode, equals('6281007003001'));
    });

    test('Automatically separates barcode when merged into product name', () async {
      const csvData = '''اسم الصنف
6223004149511 فيبا سائل اطباق ليمون 3كجم
6223004149535 فيبا سائل اطباق تفاح 3 كجم
2053010001985 فيبا بلس + 600 جم منظف اطباق اوكسى
55500001217 كلوركس كلور للالوان 475 مل
55500001224 كلوركس كلور الوان ازرق 950 مل
6223004149962 ماكسيل 500مل افران رشاش+ مطابخ 500مل+200 رشاش''';

      final bytes = Uint8List.fromList(utf8.encode(csvData));
      final result = await service.analyzeAndParseFile(
        fileBytes: bytes,
        fileName: 'edco_products.csv',
        companyNameHint: 'ادكو',
      );

      expect(result.isSuccess, isTrue);
      expect(result.products.length, equals(6));

      expect(result.products[0].barcode, equals('6223004149511'));
      expect(result.products[0].productName, equals('فيبا سائل اطباق ليمون 3كجم'));

      expect(result.products[1].barcode, equals('6223004149535'));
      expect(result.products[1].productName, equals('فيبا سائل اطباق تفاح 3 كجم'));

      expect(result.products[2].barcode, equals('2053010001985'));
      expect(result.products[2].productName, equals('فيبا بلس + 600 جم منظف اطباق اوكسى'));

      expect(result.products[3].barcode, equals('55500001217'));
      expect(result.products[3].productName, equals('كلوركس كلور للالوان 475 مل'));

      expect(result.products[4].barcode, equals('55500001224'));
      expect(result.products[4].productName, equals('كلوركس كلور الوان ازرق 950 مل'));

      expect(result.products[5].barcode, equals('6223004149962'));
      expect(result.products[5].productName, equals('ماكسيل 500مل افران رشاش+ مطابخ 500مل+200 رشاش'));
    });

    test('Parses .xlsx Excel files using Excel.decodeBytes correctly', () async {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      // Header row
      sheet.appendRow([
        TextCellValue('اسم المنتج'),
        TextCellValue('الباركود'),
        TextCellValue('السعر'),
      ]);

      // Data rows
      sheet.appendRow([
        TextCellValue('جبنة شيدر المراعي 200 جم'),
        TextCellValue('6281007004001'),
        DoubleCellValue(45.5),
      ]);
      sheet.appendRow([
        TextCellValue('لبن رايب المراعي 500 مل'),
        IntCellValue(6281007005001),
        IntCellValue(15),
      ]);

      final fileBytes = Uint8List.fromList(excel.save()!);

      final result = await service.analyzeAndParseFile(
        fileBytes: fileBytes,
        fileName: 'catalog.xlsx',
        companyNameHint: 'المراعي',
      );

      expect(result.isSuccess, isTrue);
      expect(result.products.length, equals(2));
      expect(result.products[0].productName, 'جبنة شيدر المراعي 200 جم');
      expect(result.products[0].barcode, '6281007004001');
      expect(result.products[1].productName, 'لبن رايب المراعي 500 مل');
      expect(result.products[1].barcode, '6281007005001');
    });

    test('Rejects legacy .xls Excel files with a helpful Arabic message', () async {
      // Legacy OLE2 BIFF magic bytes
      final legacyBytes = Uint8List.fromList([
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0x00, 0x00, 0x00
      ]);

      final result = await service.analyzeAndParseFile(
        fileBytes: legacyBytes,
        fileName: 'old_catalog.xls',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('صيغة الملف قديمة (.xls)'));
    });

    test('Rejects binary ZIP files uploaded with fake .csv extension', () async {
      // ZIP magic bytes: PK\x03\x04
      final fakeCsvBytes = Uint8List.fromList([
        0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00
      ]);

      final result = await service.analyzeAndParseFile(
        fileBytes: fakeCsvBytes,
        fileName: 'fake.csv',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('ملف Excel أو ZIP مضغوط تم تغيير امتداده إلى CSV'));
    });
  });
}
