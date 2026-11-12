import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

const String companySupervisorsCollection = 'company_supervisors';
const String companySupervisorsAudience = 'company_supervisors';

/// Western digits only. Same mapping as [ArabicNumbersExtension.toEnglishDigits],
/// kept local so the offline import script does not pull Flutter into the VM.
String supervisorWesternDigits(String raw, {bool convertDecimal = true}) {
  const arabicEastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  var result = raw;
  for (var i = 0; i < 10; i++) {
    result = result.replaceAll(arabicEastern[i], english[i]);
    result = result.replaceAll(persian[i], english[i]);
  }
  if (convertDecimal) {
    result = result.replaceAll('٫', '.').replaceAll('،', '.');
  }
  return result;
}

/// One supervisor row after duplicate phones have been collapsed.
class ImportedCompanySupervisor {
  final String id;
  final String name;
  final List<String> alternateNames;
  final String mobile;
  final String cleanPhone;
  final String source;

  const ImportedCompanySupervisor({
    required this.id,
    required this.name,
    required this.alternateNames,
    required this.mobile,
    required this.cleanPhone,
    this.source = 'excel_import',
  });
}

/// One phone that appeared more than once in the workbook.
class CompanySupervisorDuplicateGroup {
  final String mobile;
  final String keptName;
  final List<String> alternateNames;

  const CompanySupervisorDuplicateGroup({
    required this.mobile,
    required this.keptName,
    required this.alternateNames,
  });
}

/// Result of reading a supervisors workbook without writing anywhere.
class CompanySupervisorImportResult {
  final List<ImportedCompanySupervisor> supervisors;
  final int sourceRowCount;
  final int duplicateRowCount;
  final int invalidRowCount;
  final List<CompanySupervisorDuplicateGroup> duplicateGroups;
  final String? errorMessage;

  const CompanySupervisorImportResult({
    required this.supervisors,
    required this.sourceRowCount,
    required this.duplicateRowCount,
    required this.invalidRowCount,
    required this.duplicateGroups,
    this.errorMessage,
  });

  bool get isSuccess => errorMessage == null && supervisors.isNotEmpty;
  int get uniqueCount => supervisors.length;
}

/// Higher score wins. Length is the primary signal; word count breaks ties.
int companySupervisorNameScore(String name) {
  final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return -1;
  final words = trimmed.split(' ').where((part) => part.isNotEmpty).length;
  return trimmed.length * 1000 + words;
}

String normalizeCompanySupervisorName(String raw) {
  return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Egyptian mobiles only: 01[0125] followed by 8 digits, Western digits.
/// A 10-digit value that lost its leading zero in a numeric cell is restored.
String? normalizeEgyptianSupervisorMobile(String raw) {
  var digits = supervisorWesternDigits(raw).replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0020') && digits.length > 4) {
    digits = digits.substring(4);
  }
  if (digits.startsWith('20') && digits.length == 12) {
    digits = digits.substring(1);
  }
  if (digits.length == 10 && RegExp(r'^1[0125]\d{8}$').hasMatch(digits)) {
    digits = '0$digits';
  }
  if (!RegExp(r'^01[0125]\d{8}$').hasMatch(digits)) return null;
  return digits;
}

class _SupervisorAccumulator {
  String name;
  final List<String> alternateNames = [];
  int rowCount = 1;

  _SupervisorAccumulator(this.name);

  void absorb(String incoming) {
    rowCount++;
    final next = normalizeCompanySupervisorName(incoming);
    if (next.isEmpty || next == name) return;
    if (companySupervisorNameScore(next) > companySupervisorNameScore(name)) {
      if (name.isNotEmpty && !alternateNames.contains(name)) {
        alternateNames.add(name);
      }
      name = next;
    } else if (!alternateNames.contains(next)) {
      alternateNames.add(next);
    }
  }
}

/// Parses the supervisors workbook. Duplicate phones collapse to one record:
/// the longer / more complete name is kept, and every other distinct name is
/// stored as an alternate. The phone itself is never dropped.
CompanySupervisorImportResult parseCompanySupervisorWorkbook(
  Uint8List bytes, {
  String? fileName,
}) {
  try {
    final rows = _readRows(bytes, fileName: fileName);
    if (rows.isEmpty) {
      return const CompanySupervisorImportResult(
        supervisors: [],
        sourceRowCount: 0,
        duplicateRowCount: 0,
        invalidRowCount: 0,
        duplicateGroups: [],
        errorMessage: 'الملف فارغ أو لا يحتوي على صفوف قابلة للقراءة.',
      );
    }

    final header = _detectHeader(rows);
    final dataRows = rows.sublist(header.headerIndex + 1);
    final byMobile = <String, _SupervisorAccumulator>{};
    var invalid = 0;

    for (final row in dataRows) {
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      final rawPhone = header.phoneCol >= 0 && header.phoneCol < row.length ? row[header.phoneCol] : '';
      final rawName = header.nameCol >= 0 && header.nameCol < row.length ? row[header.nameCol] : '';
      final mobile = normalizeEgyptianSupervisorMobile(rawPhone);
      if (mobile == null) {
        invalid++;
        continue;
      }
      final name = normalizeCompanySupervisorName(supervisorWesternDigits(rawName, convertDecimal: false));
      final existing = byMobile[mobile];
      if (existing == null) {
        byMobile[mobile] = _SupervisorAccumulator(name);
      } else {
        existing.absorb(name);
      }
    }

    if (byMobile.isEmpty) {
      return CompanySupervisorImportResult(
        supervisors: const [],
        sourceRowCount: dataRows.length,
        duplicateRowCount: 0,
        invalidRowCount: invalid,
        duplicateGroups: const [],
        errorMessage: 'لم يتم العثور على أرقام موبايل مصرية صالحة في الملف.',
      );
    }

    final supervisors = <ImportedCompanySupervisor>[];
    final groups = <CompanySupervisorDuplicateGroup>[];
    var duplicateRows = 0;
    final mobiles = byMobile.keys.toList()..sort();
    for (final mobile in mobiles) {
      final acc = byMobile[mobile]!;
      final alternates = acc.alternateNames.where((name) => name.isNotEmpty && name != acc.name).toList();
      if (acc.rowCount > 1) {
        duplicateRows += acc.rowCount - 1;
        groups.add(CompanySupervisorDuplicateGroup(
          mobile: mobile,
          keptName: acc.name,
          alternateNames: List<String>.unmodifiable(alternates),
        ));
      }
      final cleanPhone = '2$mobile';
      supervisors.add(ImportedCompanySupervisor(
        id: mobile,
        name: acc.name,
        alternateNames: alternates,
        mobile: mobile,
        cleanPhone: cleanPhone,
        source: 'excel_import',
      ));
    }

    return CompanySupervisorImportResult(
      supervisors: supervisors,
      sourceRowCount: dataRows.where((row) => row.any((cell) => cell.trim().isNotEmpty)).length,
      duplicateRowCount: duplicateRows,
      invalidRowCount: invalid,
      duplicateGroups: groups,
    );
  } catch (error) {
    return CompanySupervisorImportResult(
      supervisors: const [],
      sourceRowCount: 0,
      duplicateRowCount: 0,
      invalidRowCount: 0,
      duplicateGroups: const [],
      errorMessage: 'تعذر قراءة الملف: $error',
    );
  }
}

class _HeaderLocation {
  final int headerIndex;
  final int phoneCol;
  final int nameCol;

  const _HeaderLocation({
    required this.headerIndex,
    required this.phoneCol,
    required this.nameCol,
  });
}

_HeaderLocation _detectHeader(List<List<String>> rows) {
  final scanUntil = rows.length < 5 ? rows.length : 5;
  for (var r = 0; r < scanUntil; r++) {
    var phoneCol = -1;
    var nameCol = -1;
    for (var c = 0; c < rows[r].length; c++) {
      final cell = rows[r][c].trim().toLowerCase();
      if (phoneCol == -1 && _isPhoneHeader(cell)) phoneCol = c;
      if (nameCol == -1 && _isNameHeader(cell)) nameCol = c;
    }
    if (phoneCol != -1 && nameCol != -1) {
      return _HeaderLocation(headerIndex: r, phoneCol: phoneCol, nameCol: nameCol);
    }
  }

  final first = rows.first;
  final phoneGuess = first.isNotEmpty ? normalizeEgyptianSupervisorMobile(first.first) : null;
  if (phoneGuess != null) {
    return const _HeaderLocation(headerIndex: -1, phoneCol: 0, nameCol: 1);
  }
  return const _HeaderLocation(headerIndex: 0, phoneCol: 0, nameCol: 1);
}

bool _isPhoneHeader(String header) {
  const keywords = ['موبايل', 'هاتف', 'تليفون', 'جوال', 'phone', 'mobile', 'whatsapp', 'cell'];
  return keywords.any(header.contains);
}

bool _isNameHeader(String header) {
  const keywords = ['اسم', 'name', 'person'];
  return keywords.any(header.contains);
}

List<List<String>> _readRows(Uint8List bytes, {String? fileName}) {
  final lowerName = (fileName ?? '').toLowerCase();
  if (lowerName.endsWith('.csv') || lowerName.endsWith('.txt')) {
    final content = String.fromCharCodes(bytes);
    return content
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.split(RegExp(r'[,;\t]')).map((cell) => cell.trim()).toList())
        .toList();
  }

  try {
    final excel = Excel.decodeBytes(bytes);
    Sheet? sheet = excel.tables['أرقام وأسماء'];
    if (sheet == null || sheet.maxRows == 0) {
      for (final candidate in excel.tables.values) {
        if (candidate.maxRows > 0) {
          sheet = candidate;
          break;
        }
      }
    }
    if (sheet != null && sheet.maxRows > 0) {
      final rows = <List<String>>[];
      for (final row in sheet.rows) {
        final values = row.map((cell) => _cellText(cell?.value)).toList();
        if (values.any((value) => value.trim().isNotEmpty)) {
          rows.add(values);
        }
      }
      if (rows.isNotEmpty) return rows;
    }
  } catch (_) {
    // Some workbooks store text as inline strings that this excel package cannot open.
  }
  return _readXlsxXml(bytes);
}

List<List<String>> _readXlsxXml(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? entry(String name) {
    for (final file in archive) {
      if (file.name == name) return file;
    }
    return null;
  }

  String textOf(ArchiveFile? file) {
    if (file == null) return '';
    final content = file.content;
    if (content is List<int>) return utf8.decode(content, allowMalformed: true);
    return '';
  }

  final workbookXml = textOf(entry('xl/workbook.xml'));
  final relsXml = textOf(entry('xl/_rels/workbook.xml.rels'));
  if (workbookXml.isEmpty) return const [];

  final rels = <String, String>{};
  if (relsXml.isNotEmpty) {
    final relDoc = XmlDocument.parse(relsXml);
    for (final node in relDoc.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'Relationship') continue;
      final id = _attr(node, 'Id');
      final target = _attr(node, 'Target');
      if (id.isNotEmpty && target.isNotEmpty) rels[id] = target;
    }
  }

  final workbook = XmlDocument.parse(workbookXml);
  String? preferredPath;
  String? firstPath;
  for (final node in workbook.descendants.whereType<XmlElement>()) {
    if (node.name.local != 'sheet') continue;
    final name = _attr(node, 'name');
    final relId = _attr(node, 'id');
    final target = rels[relId] ?? 'worksheets/sheet1.xml';
    final path = _sheetPath(target);
    firstPath ??= path;
    if (name == 'أرقام وأسماء') preferredPath = path;
  }
  final sheetPath = preferredPath ?? firstPath ?? 'xl/worksheets/sheet1.xml';
  final sheetXml = textOf(entry(sheetPath));
  if (sheetXml.isEmpty) return const [];

  final shared = <String>[];
  final sharedXml = textOf(entry('xl/sharedStrings.xml'));
  if (sharedXml.isNotEmpty) {
    final sharedDoc = XmlDocument.parse(sharedXml);
    for (final item in sharedDoc.descendants.whereType<XmlElement>()) {
      if (item.name.local != 'si') continue;
      final buffer = StringBuffer();
      for (final textNode in item.descendants.whereType<XmlElement>()) {
        if (textNode.name.local == 't') buffer.write(textNode.innerText);
      }
      shared.add(buffer.toString());
    }
  }

  final sheet = XmlDocument.parse(sheetXml);
  final rows = <List<String>>[];
  for (final row in sheet.descendants.whereType<XmlElement>()) {
    if (row.name.local != 'row') continue;
    final cells = <int, String>{};
    for (final cell in row.childElements) {
      if (cell.name.local != 'c') continue;
      final ref = _attr(cell, 'r');
      final column = _columnIndex(ref);
      if (column < 0) continue;
      cells[column] = _xmlCellText(cell, shared);
    }
    if (cells.isEmpty) continue;
    final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
    final values = List<String>.filled(width, '');
    cells.forEach((index, value) => values[index] = value);
    if (values.any((value) => value.trim().isNotEmpty)) rows.add(values);
  }
  return rows;
}

int _columnIndex(String cellRef) {
  final letters = cellRef.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.isEmpty) return -1;
  var index = 0;
  for (final code in letters.toUpperCase().codeUnits) {
    index = index * 26 + (code - 64);
  }
  return index - 1;
}

String _xmlCellText(XmlElement cell, List<String> shared) {
  final type = _attr(cell, 't');
  if (type == 'inlineStr') {
    final buffer = StringBuffer();
    for (final node in cell.descendants.whereType<XmlElement>()) {
      if (node.name.local == 't') buffer.write(node.innerText);
    }
    return buffer.toString();
  }
  final raw = cell.childElements.where((node) => node.name.local == 'v').map((node) => node.innerText).join();
  if (type == 's') {
    final index = int.tryParse(raw);
    if (index != null && index >= 0 && index < shared.length) return shared[index];
  }
  return raw;
}

String _sheetPath(String target) {
  var path = target.trim();
  if (path.startsWith('/')) path = path.substring(1);
  if (!path.startsWith('xl/')) path = 'xl/$path';
  return path;
}

String _attr(XmlElement node, String localName) {
  for (final attribute in node.attributes) {
    if (attribute.name.local == localName) return attribute.value;
  }
  return '';
}

String _cellText(CellValue? cellValue) {
  if (cellValue == null) return '';
  if (cellValue is TextCellValue) {
    return cellValue.value.text ?? cellValue.value.toString();
  }
  if (cellValue is IntCellValue) return cellValue.value.toString();
  if (cellValue is DoubleCellValue) {
    final value = cellValue.value;
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
  return cellValue.toString();
}
