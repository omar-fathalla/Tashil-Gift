import 'package:al_mraay/core/constants/ai_models.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'gemini_cloud_model.dart';
import '../utils/arabic_numbers_utils.dart';

final aiProductCatalogServiceProvider = Provider<AiProductCatalogService>((ref) {
  return AiProductCatalogService();
});

class ExtractedCatalogProduct {
  final String productName;
  final String barcode;
  final String category;
  final String unitSize;
  final double? referencePrice;
  final Map<String, dynamic>? rawMetadata;

  ExtractedCatalogProduct({
    required this.productName,
    required this.barcode,
    this.category = '',
    this.unitSize = '',
    this.referencePrice,
    this.rawMetadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'barcode': barcode,
      if (category.isNotEmpty) 'category': category,
      if (unitSize.isNotEmpty) 'unitSize': unitSize,
      if (referencePrice != null) 'referencePrice': referencePrice,
      if (rawMetadata != null && rawMetadata!.isNotEmpty) 'rawMetadata': rawMetadata,
    };
  }
}

class AiCatalogAnalysisResult {
  final bool isSuccess;
  final String message;
  final String detectedSchemaSummary;
  final Map<String, int> columnMapping;
  final List<ExtractedCatalogProduct> products;
  final int totalRowsRead;
  final int validProductsCount;
  final int skippedRowsCount;

  AiCatalogAnalysisResult({
    required this.isSuccess,
    required this.message,
    this.detectedSchemaSummary = '',
    this.columnMapping = const {},
    this.products = const [],
    this.totalRowsRead = 0,
    this.validProductsCount = 0,
    this.skippedRowsCount = 0,
  });
}

class AiProductCatalogService {
  // TAG-73: built on first AI call, so the parsing helpers work (and the
  // service can be created) before Firebase is initialised.
  late final CloudGenerativeModel _model = CloudGenerativeModel(
    model: AiModels.helperServices,
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json',
      temperature: 0.1,
    ),
  );

  AiProductCatalogService();

  /// Main entrypoint: Takes file bytes and file name (.xlsx, .xls, .csv, .txt),
  /// extracts data, analyzes schema using Gemini AI, and returns structured products.
  Future<AiCatalogAnalysisResult> analyzeAndParseFile({
    required Uint8List fileBytes,
    required String fileName,
    String? companyNameHint,
    void Function(String stepMessage, double progress)? onProgress,
  }) async {
    try {
      onProgress?.call('جاري قراءة واستخراج أسطر الملف...', 0.15);

      // Step 1: Decode rows from Excel or CSV
      final List<List<dynamic>> rawRows = _extractRawRows(fileBytes, fileName);

      if (rawRows.isEmpty) {
        return AiCatalogAnalysisResult(
          isSuccess: false,
          message: 'الملف فارغ أو لم يتم العثور على أي بيانات داخله.',
        );
      }

      onProgress?.call('جاري استكشاف أعمدة وهيكل الملف بالذكاء الاصطناعي...', 0.35);

      // Step 2: Extract headers and sample rows for AI Schema Recognition
      final int sampleCount = rawRows.length > 8 ? 8 : rawRows.length;
      final List<List<String>> sampleRows = rawRows
          .take(sampleCount)
          .map((row) => row.map((cell) => cell?.toString().trim() ?? '').toList())
          .toList();

      // Step 3: Run Gemini AI Column Mapping with heuristic fallback
      Map<String, dynamic> schemaMapping = await _detectSchemaWithAi(
        sampleRows: sampleRows,
        fileName: fileName,
        companyNameHint: companyNameHint,
      );

      final productNameCol = (schemaMapping['productNameCol'] as num?)?.toInt() ?? -1;
      final barcodeCol = (schemaMapping['barcodeCol'] as num?)?.toInt() ?? -1;
      final categoryCol = (schemaMapping['categoryCol'] as num?)?.toInt() ?? -1;
      final unitSizeCol = (schemaMapping['unitSizeCol'] as num?)?.toInt() ?? -1;
      final priceCol = (schemaMapping['priceCol'] as num?)?.toInt() ?? -1;
      final dataStartRowIndex = (schemaMapping['dataStartRowIndex'] as num?)?.toInt() ?? 1;
      final summaryAr = schemaMapping['summaryAr']?.toString() ?? 'تم التعرف على الأعمدة بنجاح';

      onProgress?.call('جاري معالجة وتدقيق الأصناف وتوحيد الباركودات...', 0.70);

      // Step 4: High-throughput local processing across all rows
      final List<ExtractedCatalogProduct> extractedList = [];
      final Set<String> seenBarcodes = {};
      int skippedCount = 0;

      final startIdx = dataStartRowIndex < rawRows.length ? dataStartRowIndex : 0;

      for (int i = startIdx; i < rawRows.length; i++) {
        final row = rawRows[i];
        if (row.isEmpty) {
          skippedCount++;
          continue;
        }

        // Extract Product Name
        String rawName = '';
        if (productNameCol >= 0 && productNameCol < row.length) {
          rawName = row[productNameCol]?.toString().trim() ?? '';
        }

        // Extract Barcode
        String rawBarcode = '';
        if (barcodeCol >= 0 && barcodeCol < row.length) {
          rawBarcode = row[barcodeCol]?.toString().trim() ?? '';
        }

        // Extract Category
        String category = '';
        if (categoryCol >= 0 && categoryCol < row.length) {
          category = row[categoryCol]?.toString().trim() ?? '';
        }

        // Extract Unit Size
        String unitSize = '';
        if (unitSizeCol >= 0 && unitSizeCol < row.length) {
          unitSize = row[unitSizeCol]?.toString().trim() ?? '';
        }

        // Extract Price
        double? refPrice;
        if (priceCol >= 0 && priceCol < row.length) {
          final pStr = row[priceCol]?.toString().trim() ?? '';
          refPrice = pStr.toDoubleOrNull();
        }

        // Clean & Normalize
        String cleanBarcode = _cleanBarcode(rawBarcode);
        String cleanName = _cleanProductName(rawName);

        // Security check: Ignore binary garbage lines
        if (_isBinaryOrGarbageContent(cleanName) || _isBinaryOrGarbageContent(cleanBarcode)) {
          skippedCount++;
          continue;
        }

        // Intelligent Barcode Extraction: If barcode is empty but product name has barcode merged in it
        if (cleanBarcode.isEmpty && cleanName.isNotEmpty) {
          // Check if name starts with 8-14 digits e.g. "6223004149511 فيبا سائل اطباق ليمون"
          final matchStart = RegExp(r'^(\d{8,14})\s*[-–_:/\\]*\s*(.+)$').firstMatch(cleanName);
          if (matchStart != null) {
            cleanBarcode = matchStart.group(1) ?? '';
            cleanName = (matchStart.group(2) ?? '').trim();
          } else {
            // Check if name ends with 8-14 digits e.g. "فيبا سائل اطباق 6223004149511"
            final matchEnd = RegExp(r'^(.+?)\s*[-–_:/\\]*\s*(\d{8,14})$').firstMatch(cleanName);
            if (matchEnd != null) {
              cleanName = (matchEnd.group(1) ?? '').trim();
              cleanBarcode = matchEnd.group(2) ?? '';
            }
          }
        }

        // Auto infer size from name if empty
        if (unitSize.isEmpty && cleanName.isNotEmpty) {
          unitSize = _inferSizeFromName(cleanName);
        }

        // Header check / empty check
        if (_isHeaderLikeRow(cleanName, cleanBarcode) || (cleanName.isEmpty && cleanBarcode.isEmpty)) {
          skippedCount++;
          continue;
        }

        // Ensure we have at least a name or barcode
        if (cleanName.isNotEmpty || cleanBarcode.isNotEmpty) {
          // Avoid exact barcode duplicate within the same batch if non-empty
          if (cleanBarcode.isNotEmpty && seenBarcodes.contains(cleanBarcode)) {
            // Already added
            continue;
          }
          if (cleanBarcode.isNotEmpty) {
            seenBarcodes.add(cleanBarcode);
          }

          extractedList.add(
            ExtractedCatalogProduct(
              productName: cleanName.isNotEmpty ? cleanName : 'منتج مستورد',
              barcode: cleanBarcode,
              category: category,
              unitSize: unitSize,
              referencePrice: refPrice,
            ),
          );
        } else {
          skippedCount++;
        }
      }

      onProgress?.call('اكتمل التحليل بنجاح!', 1.0);

      return AiCatalogAnalysisResult(
        isSuccess: extractedList.isNotEmpty,
        message: extractedList.isNotEmpty
            ? 'تم استخراج ${extractedList.length} منتج بنجاح عبر الذكاء الاصطناعي.'
            : 'لم يتم العثور على أي منتجات صالحة في الملف.',
        detectedSchemaSummary: summaryAr,
        columnMapping: {
          'productNameCol': productNameCol,
          'barcodeCol': barcodeCol,
          if (categoryCol >= 0) 'categoryCol': categoryCol,
          if (unitSizeCol >= 0) 'unitSizeCol': unitSizeCol,
          if (priceCol >= 0) 'priceCol': priceCol,
        },
        products: extractedList,
        totalRowsRead: rawRows.length,
        validProductsCount: extractedList.length,
        skippedRowsCount: skippedCount,
      );
    } catch (e) {
      return AiCatalogAnalysisResult(
        isSuccess: false,
        message: e is FormatException ? e.message : 'حدث خطأ أثناء تحليل الملف: $e',
      );
    }
  }

  /// Extracts raw rows from Excel (.xlsx, .xls) or CSV bytes safely.
  /// Never decodes binary Excel/Zip files as raw CSV strings.
  List<List<dynamic>> _extractRawRows(Uint8List fileBytes, String fileName) {
    final lowerName = fileName.toLowerCase();

    // 1. Check for old Excel 97-2003 (.xls) binary signature (OLE2 header: D0 CF 11 E0)
    if (_isOldExcelFormat(fileBytes, lowerName)) {
      throw const FormatException(
        'صيغة الملف قديمة (.xls). يرجى فتح الملف في برامج Excel وحفظه بصيغة (.xlsx الحديثة) أو تصديره بصيغة (.csv ترميز UTF-8).',
      );
    }

    // 2. CSV / Text handling
    if (lowerName.endsWith('.csv') || lowerName.endsWith('.txt')) {
      // Security check: If a binary zip file was renamed to .csv, reject it immediately
      if (_isZipHeader(fileBytes)) {
        throw const FormatException(
          'الملف المرفوع هو ملف Excel أو ZIP مضغوط تم تغيير امتداده إلى CSV. يرجى رفعه بامتداد .xlsx أو حفظه كـ CSV نصي حقيقي.',
        );
      }

      final content = utf8.decode(fileBytes, allowMalformed: true);
      final converter = const CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: false,
      );
      return converter.convert(content);
    }

    // 3. Modern Excel decoding (.xlsx)
    try {
      final excel = Excel.decodeBytes(fileBytes);
      final List<List<dynamic>> allRows = [];

      for (var tableName in excel.tables.keys) {
        final sheet = excel.tables[tableName];
        if (sheet != null && sheet.maxRows > 0) {
          for (var row in sheet.rows) {
            final rowValues = row.map((cell) {
              if (cell == null || cell.value == null) return '';
              return _extractCellValue(cell.value);
            }).toList();

            // Skip empty rows
            if (rowValues.any((val) => val.trim().isNotEmpty)) {
              allRows.add(rowValues);
            }
          }
          // Use the first non-empty sheet
          if (allRows.isNotEmpty) break;
        }
      }

      if (allRows.isEmpty) {
        throw const FormatException('لم يتم العثور على أي أوراق عمل (Sheets) تحتوي على بيانات في ملف الإكسيل.');
      }

      return allRows;
    } catch (excelError) {
      if (excelError is FormatException) rethrow;
      throw FormatException(
        'تعذر فك وقراءة ملف الإكسيل ($fileName). تأكد من أن الملف غير تالف أو محمي بكلمة مرور، أو احفظه بصيغة CSV (UTF-8).',
      );
    }
  }

  /// Converts various Excel CellValue types to clean string representations
  String _extractCellValue(CellValue? cellValue) {
    if (cellValue == null) return '';

    if (cellValue is TextCellValue) {
      final text = cellValue.value.text;
      return text ?? cellValue.value.toString();
    } else if (cellValue is IntCellValue) {
      return cellValue.value.toString();
    } else if (cellValue is DoubleCellValue) {
      final val = cellValue.value;
      if (val == val.roundToDouble()) {
        return val.toInt().toString();
      }
      return val.toString();
    } else if (cellValue is BoolCellValue) {
      return cellValue.value.toString();
    } else if (cellValue is DateCellValue) {
      return cellValue.asDateTimeLocal().toString();
    } else if (cellValue is DateTimeCellValue) {
      return cellValue.asDateTimeLocal().toString();
    } else if (cellValue is FormulaCellValue) {
      return cellValue.formula;
    }

    final str = cellValue.toString().trim();
    // Strip any TextCellValue(...) wrapper if present
    if (str.startsWith('TextCellValue(') && str.endsWith(')')) {
      return str.substring('TextCellValue('.length, str.length - 1);
    }
    return str;
  }

  /// Checks if file has ZIP header (PK\x03\x04 or PK\x05\x06 or PK\x07\x08)
  bool _isZipHeader(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 && bytes[1] == 0x4B; // 'P', 'K'
  }

  /// Checks if file is legacy Excel 97-2003 BIFF format
  bool _isOldExcelFormat(Uint8List bytes, String lowerName) {
    if (lowerName.endsWith('.xls')) return true;
    if (bytes.length >= 8) {
      // OLE2 Compound Document magic bytes: D0 CF 11 E0 A1 B1 1A E1
      return bytes[0] == 0xD0 &&
          bytes[1] == 0xCF &&
          bytes[2] == 0x11 &&
          bytes[3] == 0xE0 &&
          bytes[4] == 0xA1 &&
          bytes[5] == 0xB1 &&
          bytes[6] == 0x1A &&
          bytes[7] == 0xE1;
    }
    return false;
  }

  /// Detects if a string contains binary control characters or zip internals
  bool _isBinaryOrGarbageContent(String text) {
    if (text.isEmpty) return false;
    if (text.contains('[Content_Types]') ||
        text.contains('xl/worksheets') ||
        text.contains('PK\x03\x04') ||
        text.contains(r'$xml') ||
        text.contains('.rels')) {
      return true;
    }

    // Check for non-printable binary control characters
    int nonPrintableCount = 0;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code < 32 && code != 9 && code != 10 && code != 13) {
        nonPrintableCount++;
      }
    }
    return nonPrintableCount > 0;
  }

  /// Sends sample rows to Gemini AI to discover the column schema
  Future<Map<String, dynamic>> _detectSchemaWithAi({
    required List<List<String>> sampleRows,
    required String fileName,
    String? companyNameHint,
  }) async {
    try {
      final prompt = '''
You are an expert AI ERP Data Engineer specializing in Product Master Data and FMCG/Retail cataloging in Arabic and English.
Analyze the following sample rows from an uploaded catalog file ("$fileName"${companyNameHint != null ? ' for company "$companyNameHint"' : ''}).

Sample rows (up to 8 rows):
${jsonEncode(sampleRows)}

Your task is to identify the 0-based column indices for key fields:
1. "productNameCol": 0-based index of the column containing the product name, item description, title, or flavor/variant (e.g. "اسم الصنف", "Product Name", "Item Description", "الوصف", "المادة", "البيان").
2. "barcodeCol": 0-based index of the column containing the barcode, EAN, GTIN, UPC, or primary product code (e.g. "الباركود", "Barcode", "EAN", "GTIN", "كود الترقيم الدولي", "الرمز الشريطي").
3. "categoryCol": 0-based index of the main category or subcategory/group (e.g. "المجموعة", "Category", "Subcategory", "القسم", "الفئة", "النشاط"). Return -1 if not present.
4. "unitSizeCol": 0-based index of the unit, size, volume, or weight (e.g. "الحجم", "الوزن", "Size", "Unit", "Volume", "UOM"). Return -1 if not present.
5. "priceCol": 0-based index of the reference price, retail price, or unit cost. Return -1 if not present.
6. "headerRowIndex": 0-based index of the header row (usually 0).
7. "dataStartRowIndex": 0-based index where data rows start (usually 1).
8. "summaryAr": A clear, professional Arabic summary describing which columns were mapped (e.g. "تم التعرف على عمود اسم المنتج (عمود 1)، الباركود (عمود 3)، والمجموعة (عمود 2)").

Return strictly JSON matching this structure:
{
  "productNameCol": 0,
  "barcodeCol": 1,
  "categoryCol": -1,
  "unitSizeCol": -1,
  "priceCol": -1,
  "headerRowIndex": 0,
  "dataStartRowIndex": 1,
  "summaryAr": "ملخص الأعمدة المكتشفة باللغة العربية"
}
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      final rawText = response.text?.trim() ?? '';

      if (rawText.isNotEmpty) {
        final cleanJson = rawText
            .replaceAll(RegExp(r'^```json\s*|\s*```$', multiLine: true), '')
            .trim();
        final Map<String, dynamic> parsed = jsonDecode(cleanJson);
        return parsed;
      }
    } catch (_) {
      // Fallback heuristics
    }

    // Heuristic Fallback in case of network/AI failure
    return _heuristicSchemaDetection(sampleRows);
  }

  /// Rule-based schema detection when AI is unreachable
  Map<String, dynamic> _heuristicSchemaDetection(List<List<String>> sampleRows) {
    if (sampleRows.isEmpty) {
      return {
        'productNameCol': 0,
        'barcodeCol': 1,
        'categoryCol': -1,
        'unitSizeCol': -1,
        'priceCol': -1,
        'headerRowIndex': 0,
        'dataStartRowIndex': 1,
        'summaryAr': 'تم تحديد الأعمدة افتراضياً عبر التحليل الهيكلي',
      };
    }

    final headers = sampleRows.first;
    int nameCol = -1;
    int barcodeCol = -1;
    int catCol = -1;
    int sizeCol = -1;
    int priceCol = -1;

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase();
      if (h.contains('barcode') || h.contains('ean') || h.contains('gtin') || h.contains('باركود') || h.contains('شريطي')) {
        barcodeCol = i;
      } else if (h.contains('name') || h.contains('desc') || h.contains('item') || h.contains('اسم') || h.contains('صنف') || h.contains('منتج') || h.contains('وصف')) {
        nameCol = i;
      } else if (h.contains('cat') || h.contains('group') || h.contains('مجموع') || h.contains('قسم') || h.contains('فئة')) {
        catCol = i;
      } else if (h.contains('size') || h.contains('unit') || h.contains('حجم') || h.contains('وزن')) {
        sizeCol = i;
      } else if (h.contains('price') || h.contains('cost') || h.contains('سعر')) {
        priceCol = i;
      }
    }

    // Inspect sample data if headers not conclusive
    if (nameCol == -1 || barcodeCol == -1) {
      for (int r = 1; r < sampleRows.length; r++) {
        final row = sampleRows[r];
        for (int c = 0; c < row.length; c++) {
          final val = row[c].trim();
          if (barcodeCol == -1 && RegExp(r'^\d{8,14}$').hasMatch(val.replaceAll('.0', ''))) {
            barcodeCol = c;
          } else if (nameCol == -1 && val.length > 3 && !RegExp(r'^\d+$').hasMatch(val)) {
            nameCol = c;
          }
        }
      }
    }

    nameCol = nameCol != -1 ? nameCol : 0;
    barcodeCol = barcodeCol != -1 ? barcodeCol : (headers.length > 1 ? 1 : -1);

    return {
      'productNameCol': nameCol,
      'barcodeCol': barcodeCol,
      'categoryCol': catCol,
      'unitSizeCol': sizeCol,
      'priceCol': priceCol,
      'headerRowIndex': 0,
      'dataStartRowIndex': 1,
      'summaryAr': 'تم التعرف التلقائي على عمود اسم المنتج والباركود',
    };
  }

  /// Normalizes and cleans barcodes (removes Excel .0, non-digits, Arabic digits)
  String _cleanBarcode(String raw) {
    if (raw.isEmpty) return '';

    // Convert Arabic/Persian digits to Western
    String clean = raw.toEnglishDigits().trim();

    // Remove Excel float export like "6281007001001.0"
    if (clean.endsWith('.0')) {
      clean = clean.substring(0, clean.length - 2);
    }

    // Remove dashes, spaces or non-alphanumeric chars
    clean = clean.replaceAll(RegExp(r'[^\d]'), '');

    return clean;
  }

  /// Cleans and formats product name
  String _cleanProductName(String raw) {
    String clean = raw.trim();
    // Replace multiple spaces
    clean = clean.replaceAll(RegExp(r'\s+'), ' ');
    return clean;
  }

  /// Extracts unit size (e.g. 1L, 200ml, 1kg) from product name if not provided
  String _inferSizeFromName(String name) {
    final sizeRegex = RegExp(
      r'(\d+(?:\.\d+)?)\s*(لتر|مل|جم|جرام|كجم|كيلو|ك|l|ml|g|gm|kg)',
      caseSensitive: false,
    );
    final match = sizeRegex.firstMatch(name);
    if (match != null) {
      return match.group(0) ?? '';
    }
    return '';
  }

  bool _isHeaderLikeRow(String name, String barcode) {
    final lowerName = name.toLowerCase();
    final lowerBarcode = barcode.toLowerCase();
    return lowerName.contains('اسم') ||
        lowerName.contains('product name') ||
        lowerName.contains('item_desc') ||
        lowerBarcode.contains('barcode') ||
        lowerBarcode.contains('باركود') ||
        lowerBarcode.contains('ean');
  }
}
