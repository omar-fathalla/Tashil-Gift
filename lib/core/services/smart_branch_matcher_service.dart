import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'gemini_cloud_model.dart';
import '../utils/arabic_numbers_utils.dart';
import 'chain_products_intelligence_service.dart';
import '../../features/admin/domain/retail_chain_model.dart';

/// Status of the imported branch against system database
enum BranchMatchStatus {
  exactMatch,
  fuzzyMatch,
  newBranch,
  unknownChain,
}

/// Raw parsed item from text, Excel, or Image OCR
class RawBranchImportItem {
  final int rowNumber;
  final String rawChain;
  final String rawBranch;
  final String originalLine;

  const RawBranchImportItem({
    required this.rowNumber,
    required this.rawChain,
    required this.rawBranch,
    this.originalLine = '',
  });

  @override
  String toString() => '#$rowNumber: $rawChain -> $rawBranch';
}

/// Fully resolved and mapped item against existing Firestore chains and branches
class MatchedBranchImportItem {
  final RawBranchImportItem rawItem;
  final String canonicalChainName;
  final String? matchedChainId;
  final String? matchedBranchId;
  final String? matchedBranchName;
  final BranchMatchStatus status;
  final double confidence;
  final BranchModel? branchModel;
  final List<BranchModel> candidateBranches;
  final String suggestedCity;
  final String suggestedArabicName;

  const MatchedBranchImportItem({
    required this.rawItem,
    required this.canonicalChainName,
    this.matchedChainId,
    this.matchedBranchId,
    this.matchedBranchName,
    required this.status,
    this.confidence = 1.0,
    this.branchModel,
    this.candidateBranches = const [],
    this.suggestedCity = '',
    this.suggestedArabicName = '',
  });

  MatchedBranchImportItem copyWith({
    RawBranchImportItem? rawItem,
    String? canonicalChainName,
    String? matchedChainId,
    String? matchedBranchId,
    String? matchedBranchName,
    BranchMatchStatus? status,
    double? confidence,
    BranchModel? branchModel,
    List<BranchModel>? candidateBranches,
    String? suggestedCity,
    String? suggestedArabicName,
  }) {
    return MatchedBranchImportItem(
      rawItem: rawItem ?? this.rawItem,
      canonicalChainName: canonicalChainName ?? this.canonicalChainName,
      matchedChainId: matchedChainId ?? this.matchedChainId,
      matchedBranchId: matchedBranchId ?? this.matchedBranchId,
      matchedBranchName: matchedBranchName ?? this.matchedBranchName,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      branchModel: branchModel ?? this.branchModel,
      candidateBranches: candidateBranches ?? this.candidateBranches,
      suggestedCity: suggestedCity ?? this.suggestedCity,
      suggestedArabicName: suggestedArabicName ?? this.suggestedArabicName,
    );
  }
}

/// Complete summary of an import analysis
class BranchImportSummary {
  final List<MatchedBranchImportItem> items;

  const BranchImportSummary({required this.items});

  int get totalCount => items.length;
  int get matchedCount => items.where((i) => i.status == BranchMatchStatus.exactMatch || i.status == BranchMatchStatus.fuzzyMatch).length;
  int get newBranchesCount => items.where((i) => i.status == BranchMatchStatus.newBranch).length;
  int get unknownChainsCount => items.where((i) => i.status == BranchMatchStatus.unknownChain).length;

  Set<String> get matchedChainIds => items
      .where((i) => i.matchedChainId != null && i.matchedChainId!.isNotEmpty)
      .map((i) => i.matchedChainId!)
      .toSet();

  Set<String> get matchedChainNames => items
      .where((i) => i.matchedChainId != null && i.matchedChainId!.isNotEmpty)
      .map((i) => i.canonicalChainName)
      .toSet();
}

/// Service providing multi-modal extraction (Text, CSV, Excel, Gemini OCR)
/// and deterministic Arabic/English branch matching.
class SmartBranchMatcherService {
  static const Map<String, List<String>> _branchSynonyms = {
    // Carrefour & Malls
    'cfc': ['كايرو فيستيفال سيتي', 'كايرو فيستيفال', 'التجمع الخامس', 'التجمع'],
    'cairo festival': ['كايرو فيستيفال سيتي', 'كايرو فيستيفال', 'التجمع'],
    'moe': ['مول مصر', 'السادس من اكتوبر', 'اكتوبر'],
    'mall of egypt': ['مول مصر', 'السادس من اكتوبر', 'اكتوبر'],
    'moa': ['مول العرب', 'السادس من اكتوبر', 'اكتوبر'],
    'mall of arabia': ['مول العرب', 'السادس من اكتوبر', 'اكتوبر'],
    'almaza': ['سيتي سنتر ألماظة', 'ألماظة', 'الماظة', 'مصر الجديدة'],
    'alexandria': ['سيتي سنتر الإسكندرية', 'سيتي سنتر اسكندرية', 'الإسكندرية', 'اسكندرية'],
    'el maadi': ['المعادي', 'معادي', 'سيتي سنتر المعادي'],
    'maadi': ['المعادي', 'معادي'],

    // Hyper One
    'zayed': ['الشيخ زايد', 'زايد', 'مدينة الشيخ زايد'],
    'sheikh zayed': ['الشيخ زايد', 'زايد'],
    'asher': ['العاشر من رمضان', 'العاشر', '10 رمضان'],
    '10th of ramadan': ['العاشر من رمضان', 'العاشر'],
    'badr': ['مدينة بدر', 'بدر', 'طريق السويس'],

    // El Hawary
    'lebanon square': ['ميدان لبنان', 'المهندسين'],
    'lebanon sq': ['ميدان لبنان', 'المهندسين'],

    // Aswak Fathalla
    'rehab': ['الرحاب', 'مدينة الرحاب', 'سوق الرحاب'],
    'smoha': ['سموحة', 'سموحه'],

    // Gomla Market
    'el montzah': ['المنتزه', 'منتزه'],
    'montzah': ['المنتزه', 'منتزه'],
    'salah salem': ['صلاح سالم', 'عمارات العبور', 'العبور'],
    'salah salem (el-obour)': ['صلاح سالم', 'عمارات العبور', 'العبور'],
    'el-obour': ['عمارات العبور', 'العبور', 'صلاح سالم'],

    // Oscar & El Far & Lulu
    'new cairo': ['القاهرة الجديدة', 'التجمع', 'التجمع الخامس'],
    'south 90': ['التسعين الجنوبي', 'شارع التسعين', 'التجمع الخامس', 'التجمع'],
    '90 south': ['التسعين الجنوبي', 'شارع التسعين', 'التجمع الخامس'],
    'twin plaza': ['توين بلازا', 'التجمع', 'القاهرة الجديدة'],
    'madinaty': ['مدينتي', 'مدينة مدينتي'],

    // Seoudi
    'dream': ['دريم لاند', 'دريم', 'السادس من اكتوبر'],
    'dreamland': ['دريم لاند', 'دريم'],
    'city stars': ['سيتي ستارز', 'مدينة نصر'],

    // General Areas
    'dokki': ['الدقي'],
    'mohandessin': ['المهندسين'],
    'heliopolis': ['مصر الجديدة', 'هليوبوليس'],
    'nasr city': ['مدينة نصر'],
    'shoubra': ['شبرا'],
    'zamalek': ['الزمالك'],
    'sheraton': ['شيراتون', 'مساكن شيراتون'],
    'tagamoa': ['التجمع', 'التجمع الخامس'],
    'dandy': ['داندي ميجا مول', 'داندي مول'],
    'san stefano': ['سان ستيفانو'],
    'gleem': ['جليم'],
    'roushdy': ['رشدي'],
    'miami': ['ميامي'],
    'agami': ['العجمي'],
    'tanta': ['طنطا'],
    'mansoura': ['المنصورة'],
    'hurghada': ['الغردقة'],
    'sharm': ['شرم الشيخ'],
  };

  /// Inferred governorate/city for common branch names
  static String inferCityFromBranchName(String branchName) {
    final s = branchName.toLowerCase().trim();
    if (s.contains('alex') || s.contains('اسكندرية') || s.contains('إسكندرية') ||
        s.contains('smoha') || s.contains('سموحة') || s.contains('montzah') ||
        s.contains('منتزه') || s.contains('san stefano') || s.contains('miami') ||
        s.contains('gleem') || s.contains('roushdy') || s.contains('agami')) {
      return 'الإسكندرية';
    }
    if (s.contains('zayed') || s.contains('زايد') || s.contains('moe') ||
        s.contains('moa') || s.contains('dream') || s.contains('دريم') ||
        s.contains('october') || s.contains('أكتوبر') || s.contains('اكتوبر') ||
        s.contains('dokki') || s.contains('الدقي') || s.contains('mohandessin') ||
        s.contains('المهندسين') || s.contains('lebanon') || s.contains('لبنان') ||
        s.contains('haram') || s.contains('الهرم') || s.contains('faisal') || s.contains('فيصل')) {
      return 'الجيزة';
    }
    if (s.contains('asher') || s.contains('عاشر') || s.contains('zagazig') || s.contains('زقازيق')) {
      return 'الشرقية';
    }
    if (s.contains('tanta') || s.contains('طنطا') || s.contains('mahalla') || s.contains('المحلة')) {
      return 'الغربية';
    }
    if (s.contains('mansoura') || s.contains('منصورة')) {
      return 'الدقهلية';
    }
    if (s.contains('hurghada') || s.contains('غردقة')) {
      return 'البحر الأحمر';
    }
    if (s.contains('sharm') || s.contains('شرم')) {
      return 'جنوب سيناء';
    }
    return 'القاهرة';
  }

  /// Parses unstructured or semi-structured text input into raw branch items.
  /// Handles:
  /// - Tabular data with newlines (TSV, CSV, pipe-separated)
  /// - Numbered glued lines: `#1Carrefour El Maadi 2Carrefour CFC 3Carrefour Almaza ...`
  /// - Standard space-separated lines: `Carrefour   El Maadi`
  static List<RawBranchImportItem> parseText(String rawInput) {
    final text = rawInput.trim();
    if (text.isEmpty) return [];

    final List<RawBranchImportItem> results = [];

    final List<String> lines = [];
    if (text.contains('\n')) {
      lines.addAll(text.split(RegExp(r'\r?\n')));
    } else {
      // Inline numbered segmentation: Look for digit followed immediately or shortly by letters
      // e.g. "(Branch)1Carrefour ... 2Carrefour ... 21Spinneys ..."
      final matchPoints = <int>[];
      final regex = RegExp(r'(?:^|[\s\)\(\]\-\|])(\d{1,3})\s*([A-Za-z\u0600-\u06FF])');
      for (final m in regex.allMatches(text)) {
        final digitGroup = m.group(1);
        if (digitGroup != null) {
          final digitIdx = m.start + (m.group(0)!.indexOf(digitGroup));
          matchPoints.add(digitIdx);
        }
      }
      if (matchPoints.length >= 2) {
        for (int i = 0; i < matchPoints.length; i++) {
          final start = matchPoints[i];
          final end = (i + 1 < matchPoints.length) ? matchPoints[i + 1] : text.length;
          final chunk = text.substring(start, end).trim();
          if (chunk.isNotEmpty) lines.add(chunk);
        }
      } else {
        lines.add(text);
      }
    }

    int rowCounter = 1;
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Ignore pure headers
      final lowerLine = line.toLowerCase();
      if ((lowerLine.contains('account') || lowerLine.contains('مؤسسة') || lowerLine.contains('سلسلة')) &&
          (lowerLine.contains('branch') || lowerLine.contains('فرع'))) {
        final matchData = RegExp(r'1\s*([A-Za-z\u0600-\u06FF].+)$').firstMatch(line);
        if (matchData != null) {
          line = '1 ${matchData.group(1)}';
        } else {
          continue;
        }
      }

      var cleanLine = line.replaceFirst(RegExp(r'^[#\s]*\d+[\.\)\-\:\s]*'), '').trim();
      if (cleanLine.isEmpty) continue;

      String account = '';
      String branch = '';

      if (cleanLine.contains('\t')) {
        final parts = cleanLine.split('\t').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (parts.length >= 2) {
          account = parts[0];
          branch = parts.sublist(1).join(' ');
        }
      } else if (cleanLine.contains('|')) {
        final parts = cleanLine.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (parts.length >= 2) {
          if (int.tryParse(parts[0]) != null && parts.length >= 3) {
            account = parts[1];
            branch = parts.sublist(2).join(' ');
          } else {
            account = parts[0];
            branch = parts.sublist(1).join(' ');
          }
        }
      } else if (cleanLine.contains(';') || cleanLine.contains(',')) {
        final delim = cleanLine.contains(';') ? ';' : ',';
        final parts = cleanLine.split(delim).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (parts.length >= 2) {
          account = parts[0];
          branch = parts.sublist(1).join(' ');
        }
      } else if (RegExp(r'\s{2,}').hasMatch(cleanLine)) {
        final parts = cleanLine.split(RegExp(r'\s{2,}')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (parts.length >= 2) {
          account = parts[0];
          branch = parts.sublist(1).join(' ');
        }
      } else if (cleanLine.contains(' - ')) {
        final parts = cleanLine.split(' - ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (parts.length >= 2) {
          account = parts[0];
          branch = parts.sublist(1).join(' ');
        }
      } else {
        final candidateChains = [
          'Carrefour', 'Hyper One', 'Hyperone', 'El Hawary', 'El-Hawary',
          'Aswak', 'Fathalla', 'Gomla', 'Oscar', 'EL Far', 'El Far', 'Lulu',
          'Seoudi', 'Spinneys', 'Metro', 'Kheir Zaman', 'Zahran', 'Kazyon', 'Bim',
          'كارفور', 'هايبر وان', 'الهواري', 'فتح الله', 'جملة ماركت', 'أوسكار',
          'الفار', 'لولو', 'سعودي', 'سبينس', 'خير زمان', 'مترو'
        ];

        bool matchedKnownChain = false;
        for (final kc in candidateChains) {
          if (cleanLine.toLowerCase().startsWith(kc.toLowerCase())) {
            account = cleanLine.substring(0, kc.length).trim();
            branch = cleanLine.substring(kc.length).trim();
            matchedKnownChain = true;
            break;
          }
        }

        if (!matchedKnownChain) {
          final words = cleanLine.split(' ');
          if (words.length >= 2) {
            account = words[0];
            branch = words.sublist(1).join(' ');
          } else {
            account = cleanLine;
            branch = '';
          }
        }
      }

      if (account.isNotEmpty) {
        results.add(RawBranchImportItem(
          rowNumber: rowCounter++,
          rawChain: account.trim(),
          rawBranch: branch.trim(),
          originalLine: line,
        ));
      }
    }

    return results;
  }

  /// Parses CSV file contents
  static List<RawBranchImportItem> parseCsv(String csvContent) {
    final rows = const CsvToListConverter(shouldParseNumbers: false).convert(csvContent);
    return _parseTableRows(rows);
  }

  /// Parses modern Excel files (.xlsx)
  static List<RawBranchImportItem> parseExcel(Uint8List fileBytes, String fileName) {
    try {
      final excel = Excel.decodeBytes(fileBytes);
      final List<List<String>> allRows = [];

      for (var tableName in excel.tables.keys) {
        final sheet = excel.tables[tableName];
        if (sheet != null && sheet.maxRows > 0) {
          for (var row in sheet.rows) {
            final rowValues = row.map((cell) {
              if (cell == null || cell.value == null) return '';
              final val = cell.value;
              if (val is TextCellValue) return val.value.text ?? '';
              return val.toString();
            }).toList();

            if (rowValues.any((val) => val.trim().isNotEmpty)) {
              allRows.add(rowValues);
            }
          }
          if (allRows.isNotEmpty) break;
        }
      }

      return _parseTableRows(allRows);
    } catch (e) {
      throw FormatException('فشل في قراءة ملف الإكسيل ($fileName): $e');
    }
  }

  /// Generic helper to convert rows of tables into `RawBranchImportItem`
  static List<RawBranchImportItem> _parseTableRows(List<List<dynamic>> rows) {
    if (rows.isEmpty) return [];

    int accountCol = -1;
    int branchCol = -1;
    int startIndex = 0;

    for (int r = 0; r < rows.length && r < 5; r++) {
      final row = rows[r].map((e) => e.toString().toLowerCase().trim()).toList();
      for (int c = 0; c < row.length; c++) {
        final cell = row[c];
        if (cell.contains('account') || cell.contains('سلسلة') || cell.contains('مؤسسة') || cell.contains('chain')) {
          accountCol = c;
        }
        if (cell.contains('branch') || cell.contains('فرع') || cell.contains('outlet')) {
          branchCol = c;
        }
      }
      if (accountCol != -1 && branchCol != -1) {
        startIndex = r + 1;
        break;
      }
    }

    if (accountCol == -1 || branchCol == -1) {
      if (rows.first.length >= 3 && int.tryParse(rows.first[0].toString().trim()) != null) {
        accountCol = 1;
        branchCol = 2;
      } else if (rows.first.length >= 2) {
        accountCol = 0;
        branchCol = 1;
      } else {
        accountCol = 0;
        branchCol = -1;
      }
    }

    final List<RawBranchImportItem> results = [];
    int counter = 1;
    for (int r = startIndex; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      final account = accountCol >= 0 && accountCol < row.length ? row[accountCol].toString().trim() : '';
      final branch = branchCol >= 0 && branchCol < row.length ? row[branchCol].toString().trim() : '';

      if (account.isNotEmpty || branch.isNotEmpty) {
        if (account.toLowerCase() == 'account' || account.contains('المؤسسة')) continue;

        results.add(RawBranchImportItem(
          rowNumber: counter++,
          rawChain: account,
          rawBranch: branch,
          originalLine: row.join(' | '),
        ));
      }
    }

    return results;
  }

  /// Multimodal OCR extraction using Gemini 3.7 Flash
  static Future<List<RawBranchImportItem>> parseImageOrPdfWithGemini({
    required Uint8List fileBytes,
    required String mimeType,
  }) async {
    final model = CloudGenerativeModel(
      model: 'gemini-3.7-flash',
      generationConfig: GenerationConfig(
        temperature: 0.0,
        responseMimeType: 'application/json',
      ),
    );

    final prompt = '''
You are an expert OCR and retail document parser.
Inspect the attached image/document containing a table or list of retail accounts and branches.
Extract EVERY SINGLE row into a clean JSON array with exact objects:
[
  {"account": "Carrefour", "branch": "El Maadi"},
  {"account": "Carrefour", "branch": "CFC"},
  ...
]
Rules:
1. "account" is the retail chain / store enterprise (e.g. Carrefour, Hyper One, El Hawary, Aswak, Gomla, Oscar, El Far, Lulu, Seoudi, Spinneys).
2. "branch" is the specific branch name or mall (e.g. El Maadi, CFC, Almaza, Zayed, Asher, Badr, Lebanon Square, Rehab, Smoha, etc.).
3. If there are row numbers (1, 2, 3...), exclude them from account and branch text.
4. Return ONLY valid JSON array.
''';

    final content = [
      Content.multi([
        TextPart(prompt),
        DataPart(mimeType, fileBytes),
      ]),
    ];

    final response = await model.generateContent(content);
    final text = response.text?.trim() ?? '';
    if (text.isEmpty) return [];

    try {
      final decoded = jsonDecode(text) as List<dynamic>;
      final List<RawBranchImportItem> items = [];
      int counter = 1;
      for (final item in decoded) {
        if (item is Map) {
          final account = item['account']?.toString().trim() ?? '';
          final branch = item['branch']?.toString().trim() ?? '';
          if (account.isNotEmpty || branch.isNotEmpty) {
            items.add(RawBranchImportItem(
              rowNumber: counter++,
              rawChain: account,
              rawBranch: branch,
              originalLine: '$account - $branch',
            ));
          }
        }
      }
      return items;
    } catch (e) {
      throw FormatException('تعذر فك مخرجات الذكاء الاصطناعي: $e\nالمخرجات: $text');
    }
  }

  /// Core matching engine: matches raw import items against Firestore chains & branches
  static BranchImportSummary matchExtractedItems({
    required List<RawBranchImportItem> rawItems,
    required List<RetailChainModel> existingChains,
    required List<BranchModel> existingBranches,
  }) {
    final List<MatchedBranchImportItem> matchedResults = [];

    for (final raw in rawItems) {
      final canonicalChain = ChainProductsIntelligenceService.normalizeRetailChain(raw.rawChain);
      final matchedChain = _findMatchingChain(canonicalChain, raw.rawChain, existingChains);

      if (matchedChain == null) {
        matchedResults.add(MatchedBranchImportItem(
          rawItem: raw,
          canonicalChainName: canonicalChain,
          status: BranchMatchStatus.unknownChain,
          confidence: 0.0,
          suggestedCity: inferCityFromBranchName(raw.rawBranch),
          suggestedArabicName: _translateBranchNameToArabic(raw.rawBranch),
        ));
        continue;
      }

      final chainId = matchedChain.id;
      final chainName = matchedChain.name;

      final chainBranches = existingBranches.where((b) {
        return b.retailChainId.trim().toLowerCase() == chainId.toLowerCase() ||
               b.retailChainName.trim().toLowerCase() == chainName.toLowerCase() ||
               b.retailChainName.trim().toLowerCase() == canonicalChain.toLowerCase();
      }).toList();

      if (raw.rawBranch.trim().isEmpty) {
        matchedResults.add(MatchedBranchImportItem(
          rawItem: raw,
          canonicalChainName: chainName,
          matchedChainId: chainId,
          status: BranchMatchStatus.exactMatch,
          confidence: 1.0,
        ));
        continue;
      }

      final branchMatch = _matchBranch(raw.rawBranch, chainBranches);

      if (branchMatch != null) {
        matchedResults.add(MatchedBranchImportItem(
          rawItem: raw,
          canonicalChainName: chainName,
          matchedChainId: chainId,
          matchedBranchId: branchMatch.branch.id,
          matchedBranchName: branchMatch.branch.branchName,
          status: branchMatch.isExact ? BranchMatchStatus.exactMatch : BranchMatchStatus.fuzzyMatch,
          confidence: branchMatch.score,
          branchModel: branchMatch.branch,
          candidateBranches: chainBranches,
          suggestedCity: branchMatch.branch.city.isNotEmpty ? branchMatch.branch.city : inferCityFromBranchName(raw.rawBranch),
          suggestedArabicName: branchMatch.branch.branchName,
        ));
      } else {
        matchedResults.add(MatchedBranchImportItem(
          rawItem: raw,
          canonicalChainName: chainName,
          matchedChainId: chainId,
          status: BranchMatchStatus.newBranch,
          confidence: 0.0,
          candidateBranches: chainBranches,
          suggestedCity: inferCityFromBranchName(raw.rawBranch),
          suggestedArabicName: _translateBranchNameToArabic(raw.rawBranch),
        ));
      }
    }

    return BranchImportSummary(items: matchedResults);
  }

  static RetailChainModel? _findMatchingChain(
    String canonicalChainName,
    String rawChain,
    List<RetailChainModel> existingChains,
  ) {
    final canonNorm = _normalizeText(canonicalChainName);
    final rawNorm = _normalizeText(rawChain);

    for (final c in existingChains) {
      final nameNorm = _normalizeText(c.name);
      final slugNorm = _normalizeText(c.slug);

      if (nameNorm == canonNorm || nameNorm == rawNorm) return c;
      if (slugNorm == canonNorm || slugNorm == rawNorm) return c;
      if (nameNorm.contains(canonNorm) || canonNorm.contains(nameNorm)) return c;
    }

    return null;
  }

  static _BranchMatchResult? _matchBranch(String rawBranch, List<BranchModel> chainBranches) {
    if (chainBranches.isEmpty) return null;

    final qNorm = _normalizeText(rawBranch);
    final synonyms = _getSynonyms(qNorm);

    for (final b in chainBranches) {
      final bClean = _cleanBranchName(b.branchName);
      final bNorm = _normalizeText(bClean);
      if (bNorm == qNorm) {
        return _BranchMatchResult(branch: b, score: 1.0, isExact: true);
      }
    }

    for (final b in chainBranches) {
      final bNorm = _normalizeText(b.branchName);
      for (final syn in synonyms) {
        final synNorm = _normalizeText(syn);
        if (bNorm.contains(synNorm) || synNorm.contains(bNorm)) {
          return _BranchMatchResult(branch: b, score: 0.95, isExact: true);
        }
      }
    }

    BranchModel? bestSubstringMatch;
    for (final b in chainBranches) {
      final bNorm = _normalizeText(_cleanBranchName(b.branchName));
      if (bNorm.contains(qNorm) || qNorm.contains(bNorm)) {
        bestSubstringMatch = b;
        break;
      }
    }
    if (bestSubstringMatch != null) {
      return _BranchMatchResult(branch: bestSubstringMatch, score: 0.85, isExact: false);
    }

    final qTokens = qNorm.split(' ').where((t) => t.length >= 3).toSet();
    if (qTokens.isNotEmpty) {
      BranchModel? bestFuzzy;
      double highestScore = 0.0;

      for (final b in chainBranches) {
        final bTokens = _normalizeText(b.branchName).split(' ').where((t) => t.length >= 3).toSet();
        final intersection = qTokens.intersection(bTokens);
        if (intersection.isNotEmpty) {
          final score = intersection.length / qTokens.length;
          if (score > highestScore && score >= 0.5) {
            highestScore = score;
            bestFuzzy = b;
          }
        }
      }

      if (bestFuzzy != null) {
        return _BranchMatchResult(branch: bestFuzzy, score: highestScore, isExact: false);
      }
    }

    return null;
  }

  static List<String> _getSynonyms(String normText) {
    final List<String> list = [];
    _branchSynonyms.forEach((key, values) {
      if (normText == key || normText.contains(key) || key.contains(normText)) {
        list.addAll(values);
      }
      for (final v in values) {
        if (normText == v || normText.contains(v) || v.contains(normText)) {
          list.add(key);
          list.addAll(values);
          break;
        }
      }
    });
    return list.toSet().toList();
  }

  static String _translateBranchNameToArabic(String rawBranch) {
    final s = rawBranch.trim();
    final lower = s.toLowerCase();

    for (final entry in _branchSynonyms.entries) {
      if (lower == entry.key) {
        return entry.value.first;
      }
    }

    if (lower == 'cfc') return 'كايرو فيستيفال سيتي';
    if (lower == 'moe') return 'مول مصر';
    if (lower == 'moa') return 'مول العرب';
    if (lower.contains('el maadi') || lower == 'maadi') return 'المعادي';
    if (lower.contains('almaza')) return 'سيتي سنتر ألماظة';
    if (lower.contains('alexandria') || lower == 'alex') return 'سيتي سنتر الإسكندرية';
    if (lower.contains('zayed')) return 'الشيخ زايد';
    if (lower.contains('asher')) return 'العاشر من رمضان';
    if (lower.contains('badr')) return 'مدينة بدر';
    if (lower.contains('lebanon')) return 'ميدان لبنان';
    if (lower.contains('rehab')) return 'الرحاب';
    if (lower.contains('smoha')) return 'سموحة';
    if (lower.contains('montzah')) return 'المنتزه';
    if (lower.contains('salah salem')) return 'صلاح سالم (عمارات العبور)';
    if (lower.contains('new cairo')) return 'القاهرة الجديدة (التجمع)';
    if (lower.contains('south 90')) return 'التسعين الجنوبي';
    if (lower.contains('twin plaza')) return 'توين بلازا (التجمع)';
    if (lower.contains('madinaty')) return 'مدينتي';
    if (lower.contains('dream')) return 'دريم لاند (6 أكتوبر)';
    if (lower.contains('city stars')) return 'سيتي ستارز (مدينة نصر)';

    return s;
  }

  static String _cleanBranchName(String name) {
    return name
        .replaceAll(RegExp(r'\s*\([^\)]*\)'), '')
        .trim();
  }

  static String _normalizeText(String s) {
    var str = s.toLowerCase().trim().toEnglishDigits();
    str = str.replaceAll(RegExp(r'[أإآ]'), 'ا');
    str = str.replaceAll('ى', 'ي');
    str = str.replaceAll('ة', 'ه');
    str = str.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ');
    return str.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Generates a professional, structured WhatsApp / Email request message to send to the client or account manager,
  /// requesting sample POS cashier receipts (بونات كاشير) for missing chains and newly discovered branches.
  static String generatePosReceiptRequestMessage(
    BranchImportSummary summary, {
    String campaignTitle = '',
  }) {
    final buffer = StringBuffer();
    buffer.writeln('السلام عليكم ورحمة الله وبركاته،');
    buffer.writeln('تحية طيبة وبعد،،');
    buffer.writeln('');

    if (campaignTitle.trim().isNotEmpty) {
      buffer.writeln('بخصوص إعداد وتفعيل فروع الحملة الترويجية ($campaignTitle):');
    } else {
      buffer.writeln('بخصوص إعداد وتفعيل فروع الحملة الترويجية الجديدة:');
    }
    buffer.writeln('');
    buffer.writeln('حتى نضمن أعلى دقة في التوثيق والقراءة الآلية الذكية لبونات الشراء عبر الذكاء الاصطناعي بنسبة قبول 100% (POS Verification AI) ومنع رفض بونات العملاء، يرجى التكرم بتزويدنا بصورة واضحة لبونة شراء (كاشير تجريبية) من الفروع التالية لربط البصمة الهيكلية للكاشير (Store ID & Tax ID):');
    buffer.writeln('');

    final unknownChains = summary.items.where((i) => i.status == BranchMatchStatus.unknownChain).toList();
    final newBranches = summary.items.where((i) => i.status == BranchMatchStatus.newBranch).toList();

    if (unknownChains.isNotEmpty) {
      buffer.writeln('🏢 سلاسل ومنافذ جديدة مطلوب بونات كاشير لها:');
      for (final item in unknownChains) {
        final chainStr = item.canonicalChainName.isNotEmpty ? item.canonicalChainName : item.rawItem.rawChain;
        final branchStr = item.suggestedArabicName.isNotEmpty ? item.suggestedArabicName : item.rawItem.rawBranch;
        buffer.writeln('• [سلسلة: $chainStr] - الفرع: $branchStr (${item.rawItem.rawBranch}) - المحافظة: ${item.suggestedCity}');
      }
      buffer.writeln('');
    }

    if (newBranches.isNotEmpty) {
      buffer.writeln('📍 فروع جديدة تحتاج بونات للتوثيق والربط البصمي:');
      for (final item in newBranches) {
        final chainStr = item.canonicalChainName.isNotEmpty ? item.canonicalChainName : item.rawItem.rawChain;
        final branchStr = item.suggestedArabicName.isNotEmpty ? item.suggestedArabicName : item.rawItem.rawBranch;
        buffer.writeln('• [سلسلة: $chainStr] - الفرع: $branchStr (${item.rawItem.rawBranch}) - المحافظة: ${item.suggestedCity}');
      }
      buffer.writeln('');
    }

    if (unknownChains.isEmpty && newBranches.isEmpty) {
      buffer.writeln('✅ جميع الفروع الواردة (${summary.totalCount} فرعاً) مسجلة ومطابقة في قاعدة بيانات النظام.');
      buffer.writeln('الفروع المعتمدة:');
      for (final item in summary.items) {
        buffer.writeln('• ${item.canonicalChainName} - ${item.matchedBranchName ?? item.rawItem.rawBranch}');
      }
      buffer.writeln('');
    }

    buffer.writeln('📌 متطلبات صورة البونة المطلوبة:');
    buffer.writeln('1. صورة واضحة ومستوية تظهر ترويسة البونة (اسم السلسلة والفرع ورقم التسجيل الضريبي أو السجل التجاري).');
    buffer.writeln('2. إظهار رقم نقطة البيع أو رقم الكاشير (POS / Store ID / Terminal).');
    buffer.writeln('3. سطر يحتوي على أي منتج تجريبي مع التاريخ والوقت بوضوح.');
    buffer.writeln('');
    buffer.writeln('شاكرين لسيادتكم حسن تعاونكم الدائم،');
    buffer.writeln('فريق العمليات والذكاء الاصطناعي - تسهيل');

    return buffer.toString();
  }
}

class _BranchMatchResult {
  final BranchModel branch;
  final double score;
  final bool isExact;

  _BranchMatchResult({
    required this.branch,
    required this.score,
    required this.isExact,
  });
}
