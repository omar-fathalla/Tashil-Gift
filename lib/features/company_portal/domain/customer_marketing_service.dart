import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/utils/arabic_numbers_utils.dart';
import 'marketing_contact_model.dart';
import 'whatsapp_gateway_service.dart';

/// Result of parsing an Excel or CSV file for customer marketing contacts
class CustomerImportParseResult {
  final List<MarketingContactModel> validContacts;
  final int totalRows;
  final int invalidRowsCount;
  final int duplicateCount;
  final String? errorMessage;

  const CustomerImportParseResult({
    required this.validContacts,
    required this.totalRows,
    required this.invalidRowsCount,
    required this.duplicateCount,
    this.errorMessage,
  });

  bool get isSuccess => errorMessage == null && validContacts.isNotEmpty;
  int get duplicatesFilteredCount => duplicateCount;
}

/// Service managing custom customer contacts, persistence in Firestore,
/// and smart Excel/CSV parsing and template generation.
class CustomerMarketingService {
  final FirebaseFirestore? _firestore;

  CustomerMarketingService({FirebaseFirestore? firestore})
      : _firestore = firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  static const String collectionName = 'marketing_contacts';

  /// Generates a deterministic document ID for a contact based on company and phone
  String _buildDocId(String companySlug, String cleanPhone) {
    final cleanComp = companySlug.trim().toLowerCase();
    final slug = cleanComp.isNotEmpty ? cleanComp : 'global';
    return '${slug}_$cleanPhone';
  }

  /// Saves or updates a single marketing contact in Firestore
  Future<bool> saveContact(MarketingContactModel contact) async {
    try {
      final docId = _buildDocId(contact.companySlug, contact.cleanPhone);
      await _db.collection(collectionName).doc(docId).set(
        contact.copyWith().toMap(),
        SetOptions(merge: true),
      );
      return true;
    } catch (e) {
      debugPrint('Error saving marketing contact: $e');
      return false;
    }
  }

  /// Saves a batch of imported contacts using Firestore WriteBatch (up to 500 per batch)
  Future<int> saveBatchContacts(List<MarketingContactModel> contacts) async {
    if (contacts.isEmpty) return 0;
    int savedCount = 0;

    try {
      // Chunk into batches of 450 (Firestore limit is 500 operations per batch)
      const chunkSize = 450;
      for (int i = 0; i < contacts.length; i += chunkSize) {
        final chunk = contacts.sublist(i, (i + chunkSize).clamp(0, contacts.length));
        final batch = _db.batch();

        for (final contact in chunk) {
          final docId = _buildDocId(contact.companySlug, contact.cleanPhone);
          final ref = _db.collection(collectionName).doc(docId);
          batch.set(ref, contact.toMap(), SetOptions(merge: true));
        }

        await batch.commit();
        savedCount += chunk.length;
      }
    } catch (e) {
      debugPrint('Error saving batch marketing contacts: $e');
    }
    return savedCount;
  }

  /// Deletes a contact from Firestore
  Future<bool> deleteContact(String contactId) async {
    try {
      await _db.collection(collectionName).doc(contactId).delete();
      return true;
    } catch (e) {
      debugPrint('Error deleting marketing contact: $e');
      return false;
    }
  }

  /// Streams marketing contacts from Firestore for a given company
  Stream<List<MarketingContactModel>> streamContacts({String? companySlug}) {
    Query<Map<String, dynamic>> query = _db.collection(collectionName);

    if (companySlug != null && companySlug.trim().isNotEmpty && companySlug != 'all') {
      final slug = companySlug.trim().toLowerCase();
      query = query.where('companySlug', isEqualTo: slug);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => MarketingContactModel.fromFirestore(doc)).toList();
    });
  }

  /// Parses Excel (.xlsx / .xls) or CSV bytes into a structured list of valid contacts
  Future<CustomerImportParseResult> parseExcelOrCsv({
    required Uint8List bytes,
    required String fileName,
    String? companySlug,
  }) async {
    final lowerName = fileName.toLowerCase();
    List<List<dynamic>> rawRows = [];

    try {
      if (lowerName.endsWith('.csv') || lowerName.endsWith('.txt')) {
        // Parse CSV
        final content = utf8.decode(bytes, allowMalformed: true);
        rawRows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(content);
        if (rawRows.isEmpty || (rawRows.length == 1 && rawRows.first.isEmpty)) {
          // Try with \r\n
          rawRows = const CsvToListConverter(shouldParseNumbers: false).convert(content);
        }
      } else {
        // Parse Excel (.xlsx)
        final excel = Excel.decodeBytes(bytes);
        for (final tableName in excel.tables.keys) {
          final sheet = excel.tables[tableName];
          if (sheet != null && sheet.maxRows > 0) {
            for (final row in sheet.rows) {
              final rowValues = row.map((cell) => _extractCellValue(cell?.value)).toList();
              if (rowValues.any((val) => val.trim().isNotEmpty)) {
                rawRows.add(rowValues);
              }
            }
            if (rawRows.isNotEmpty) break;
          }
        }
      }

      if (rawRows.isEmpty) {
        return const CustomerImportParseResult(
          validContacts: [],
          totalRows: 0,
          invalidRowsCount: 0,
          duplicateCount: 0,
          errorMessage: 'الملف فارغ أو لا يحتوي على أي صفوف قابلة للقراءة.',
        );
      }

      // 1. Identify header row and column indexes
      int nameCol = -1;
      int phoneCol = -1;
      int branchCol = -1;
      int notesCol = -1;

      int headerRowIndex = 0;
      final firstRow = rawRows.first.map((c) => c.toString().trim().toLowerCase()).toList();

      for (int i = 0; i < firstRow.length; i++) {
        final val = firstRow[i];
        if (nameCol == -1 && isNameHeader(val)) {
          nameCol = i;
        } else if (phoneCol == -1 && isPhoneHeader(val)) {
          phoneCol = i;
        } else if (branchCol == -1 && isBranchHeader(val)) {
          branchCol = i;
        } else if (notesCol == -1 && isNotesHeader(val)) {
          notesCol = i;
        }
      }

      // If headers not found by names, fallback to positional detection
      bool hasHeader = nameCol != -1 || phoneCol != -1;
      if (!hasHeader) {
        // Heuristic: check if row 0 looks like column labels or actual data
        final row0Phone = rawRows.first.length > 1 ? rawRows.first[1].toString().toEnglishDigits() : '';
        if (row0Phone.replaceAll(RegExp(r'\D'), '').length >= 8) {
          // First row is actual data
          nameCol = 0;
          phoneCol = rawRows.first.length > 1 ? 1 : 0;
          branchCol = rawRows.first.length > 2 ? 2 : -1;
          headerRowIndex = -1; // Process from row 0
        } else {
          // First row is header
          nameCol = 0;
          phoneCol = rawRows.first.length > 1 ? 1 : 0;
          branchCol = rawRows.first.length > 2 ? 2 : -1;
          headerRowIndex = 0;
        }
      }

      final Map<String, MarketingContactModel> validMap = {};
      int invalidCount = 0;
      int duplicateCount = 0;
      final targetSlug = (companySlug != null && companySlug.isNotEmpty) ? companySlug : 'global';
      final now = DateTime.now();

      final startRow = headerRowIndex + 1;
      for (int r = startRow; r < rawRows.length; r++) {
        final row = rawRows[r];
        if (row.isEmpty) continue;

        final rawName = (nameCol >= 0 && nameCol < row.length) ? row[nameCol].toString().trim() : '';
        final rawPhoneStr = (phoneCol >= 0 && phoneCol < row.length) ? row[phoneCol].toString().trim() : '';
        final rawBranch = (branchCol >= 0 && branchCol < row.length) ? row[branchCol].toString().trim() : '';
        final rawNotes = (notesCol >= 0 && notesCol < row.length) ? row[notesCol].toString().trim() : '';

        // Clean digits
        final cleanDigits = rawPhoneStr.toEnglishDigits().replaceAll(RegExp(r'[^0-9+]'), '');
        final cleanPhone = WhatsAppGatewayService.formatInternationalPhone(cleanDigits);

        if (cleanPhone.length < 9) {
          invalidCount++;
          continue;
        }

        if (validMap.containsKey(cleanPhone)) {
          duplicateCount++;
          continue;
        }

        final displayName = rawName.isNotEmpty ? rawName : 'عميل مسجل';
        validMap[cleanPhone] = MarketingContactModel(
          id: '${targetSlug}_$cleanPhone',
          name: displayName,
          rawPhone: cleanDigits,
          cleanPhone: cleanPhone,
          branch: rawBranch,
          companySlug: targetSlug,
          source: 'excel_import',
          notes: rawNotes,
          createdAt: now,
        );
      }

      return CustomerImportParseResult(
        validContacts: validMap.values.toList(),
        totalRows: rawRows.length - (headerRowIndex >= 0 ? 1 : 0),
        invalidRowsCount: invalidCount,
        duplicateCount: duplicateCount,
      );
    } catch (e) {
      debugPrint('Error parsing Excel/CSV: $e');
      return CustomerImportParseResult(
        validContacts: const [],
        totalRows: 0,
        invalidRowsCount: 0,
        duplicateCount: 0,
        errorMessage: 'تعذر قراءة الملف: تأكد من صحة تنسيق الملف (Excel أو CSV). التفاصيل: $e',
      );
    }
  }

  /// Generates a ready-to-use sample Excel template with styling and guidance data
  static Uint8List generateSampleExcelTemplate() {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    // Header styling
    final headers = [
      'اسم العميل',
      'رقم الهاتف',
      'الفرع / المدينة',
      'ملاحظات',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // Sample guidance rows
    sheet.appendRow([
      TextCellValue('محمد أحمد'),
      TextCellValue('01012345678'),
      TextCellValue('فرع المعادي'),
      TextCellValue('عميل مميز'),
    ]);
    sheet.appendRow([
      TextCellValue('سارة محمود'),
      TextCellValue('01211857725'),
      TextCellValue('فرع مدينة نصر'),
      TextCellValue(''),
    ]);
    sheet.appendRow([
      TextCellValue('علي حسن'),
      TextCellValue('01198765432'),
      TextCellValue('فرع الإسكندرية (سموحة)'),
      TextCellValue('مهتم بالعروض الترويجية'),
    ]);

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  // --- Header Detection Helpers ---

  static bool isNameHeader(String header) {
    const keywords = ['اسم', 'الاسم', 'عميل', 'العميل', 'name', 'customer', 'client', 'customer_name', 'full_name'];
    return keywords.any((k) => header.contains(k));
  }

  static bool isPhoneHeader(String header) {
    const keywords = ['هاتف', 'الهاتف', 'موبايل', 'الموبايل', 'تليفون', 'جوال', 'واتساب', 'واتس', 'phone', 'mobile', 'whatsapp', 'cell', 'tel'];
    return keywords.any((k) => header.contains(k));
  }

  static bool isBranchHeader(String header) {
    const keywords = ['فرع', 'الفرع', 'مدينة', 'المدينة', 'منفذ', 'المنفذ', 'محافظة', 'المحافظة', 'branch', 'city', 'outlet', 'store', 'location'];
    return keywords.any((k) => header.contains(k));
  }

  static bool isNotesHeader(String header) {
    const keywords = ['ملاحظات', 'ملاحظة', 'وسم', 'تعليق', 'notes', 'note', 'tag', 'comment', 'remarks', 'remark'];
    return keywords.any((k) => header.contains(k));
  }

  static String _extractCellValue(CellValue? cellValue) {
    if (cellValue == null) return '';
    if (cellValue is TextCellValue) {
      return cellValue.value.text ?? cellValue.value.toString();
    } else if (cellValue is IntCellValue) {
      return cellValue.value.toString();
    } else if (cellValue is DoubleCellValue) {
      final val = cellValue.value;
      if (val == val.roundToDouble()) {
        return val.toInt().toString();
      }
      return val.toString();
    } else if (cellValue is DateCellValue) {
      return cellValue.asDateTimeLocal().toString();
    }
    return cellValue.toString();
  }
}
