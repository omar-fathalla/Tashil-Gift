import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart' as xl;
import 'package:al_mraay/features/admin/domain/chain_product_model.dart';

void main() {
  group('Chain Products Price Intelligence Matrix Export Tests', () {
    final sampleItems = [
      const ChainProductItem(
        id: '6221155611529',
        barcode: '6221155611529',
        name: 'ريكسونا رول اون حريمي خوخ وعشب الليمون 50 مل',
        brand: 'Rexona',
        category: 'مزيلات عرق',
        latestPricesByChain: {
          'أسواق فتح الله': 69.0,
          'جملة ماركت': 69.0,
        },
        latestRegularPricesByChain: {
          'أسواق فتح الله': 69.0,
          'جملة ماركت': 69.0,
        },
        latestDatesByChain: {
          'أسواق فتح الله': '2026-08-28',
          'جملة ماركت': '2026-08-28',
        },
        chainSummaries: {
          'أسواق فتح الله': ChainPricingSummary(
            chainName: 'أسواق فتح الله',
            netUnitPrice: 69.0,
            regularUnitPrice: 69.0,
            unitDiscount: 0.0,
            discountPercent: 0.0,
            totalQuantity: 1,
            totalScans: 1,
            lastReceiptDate: '2026-08-28',
            branchesObserved: ['الهانوفيل'],
          ),
          'جملة ماركت': ChainPricingSummary(
            chainName: 'جملة ماركت',
            netUnitPrice: 69.0,
            regularUnitPrice: 69.0,
            unitDiscount: 0.0,
            discountPercent: 0.0,
            totalQuantity: 2,
            totalScans: 1,
            lastReceiptDate: '2026-08-28',
            branchesObserved: ['المنتزة'],
          ),
        },
        priceHistory: [],
        totalQuantitySold: 3,
        totalScansCount: 2,
        companySlug: 'unilever',
      ),
    ];

    test('Excel Workbook (.xlsx) generates valid binary bytes with RTL and custom headers', () {
      final excel = xl.Excel.createExcel();
      final sheetName = 'مصفوفة الأسعار والمنافسين';
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) {
        excel.rename(defaultSheet, sheetName);
      }
      final sheet = excel[sheetName];
      sheet.isRTL = true;

      final chains = ['أسواق فتح الله', 'جملة ماركت'];
      final headers = [
        'الباركود',
        'اسم المنتج',
        'العلامة التجارية',
        'التصنيف',
        ...chains.map((c) => 'سعر $c (ج.م)'),
        'السلسلة الأرخص',
        'أقل سعر (ج.م)',
        'السلسلة الأغلى',
        'أعلى سعر (ج.م)',
        'فارق السعر %',
        'موقف فتح الله التنافسي',
      ];

      for (var col = 0; col < headers.length; col++) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.value = xl.TextCellValue(headers[col]);
      }

      int rowIndex = 1;
      for (final item in sampleItems) {
        int colIndex = 0;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.barcode);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.name);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.brand);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.category);

        for (final c in chains) {
          final p = item.latestPricesByChain[c];
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(p ?? 0.0);
        }

        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.cheapestChain);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(item.minPrice);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.mostExpensiveChain);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(item.maxPrice);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(item.priceVariancePercent);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue('متطابق / عادي');
      }

      final fileBytes = excel.save();
      expect(fileBytes, isNotNull);
      expect(fileBytes!.length, greaterThan(100));
    });

    test('CSV export generates valid UTF-8 BOM buffer with Arabic headers and comma-separated rows', () {
      final buffer = StringBuffer();
      buffer.write('\uFEFF'); // UTF-8 BOM

      final chains = ['أسواق فتح الله', 'جملة ماركت'];
      buffer.write('Barcode,Product Name,Brand,Category,');
      for (final c in chains) {
        buffer.write('Price in $c (EGP),');
      }
      buffer.writeln('Cheapest Store,Min Price,Highest Store,Max Price,Price Gap %');

      for (final item in sampleItems) {
        buffer.write('"${item.barcode}","${item.name}","${item.brand}","${item.category}",');
        for (final c in chains) {
          final p = item.latestPricesByChain[c];
          buffer.write('${p != null ? p.toStringAsFixed(2) : ""},');
        }
        buffer.writeln('"${item.cheapestChain}",${item.minPrice.toStringAsFixed(2)},"${item.mostExpensiveChain}",${item.maxPrice.toStringAsFixed(2)},${item.priceVariancePercent.toStringAsFixed(1)}');
      }

      final csvString = buffer.toString();
      expect(csvString.startsWith('\uFEFF'), isTrue);
      expect(csvString, contains('6221155611529'));
      expect(csvString, contains('ريكسونا رول اون'));

      final encodedBytes = utf8.encode(csvString);
      expect(encodedBytes.length, greaterThan(50));
    });
  });
}
