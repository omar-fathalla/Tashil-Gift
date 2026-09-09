import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';

// Copy of pure logic helpers from create_event_screen for unit test validation
const String _govAlexandria = 'الإسكندرية';
const String _govCairoGiza = 'القاهرة والجيزة';
const String _govNorthCoast = 'الساحل الشمالي ومطروح';
const String _govBeheira = 'البحيرة';
const String _govGharbiaDelta = 'الغربية والدلتا';
const String _govCanalDamietta = 'دمياط ومدن القناة';
const String _govUpperEgypt = 'محافظات الصعيد والبحر الأحمر';
const String _govOther = 'فروع ومناطق أخرى';

const List<String> _canonicalGovernorateOrder = [
  _govAlexandria,
  _govCairoGiza,
  _govNorthCoast,
  _govBeheira,
  _govGharbiaDelta,
  _govCanalDamietta,
  _govUpperEgypt,
  _govOther,
];

String _normalizeBranchSearchText(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '')
      .replaceAll(RegExp(r'[إأآا]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[\s_-]+'), ' ')
      .trim();
}

String _resolveBranchGovernorate(BranchModel branch) {
  final rawCity = branch.city.trim();
  final rawName = branch.branchName.trim();
  final rawAddress = branch.address.trim();

  String parenthetical = '';
  final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(rawName);
  if (parenMatch != null) {
    parenthetical = parenMatch.group(1)?.trim() ?? '';
  }

  final normCity = _normalizeBranchSearchText(rawCity);
  final normParen = _normalizeBranchSearchText(parenthetical);
  final normName = _normalizeBranchSearchText(rawName);
  final normAddress = _normalizeBranchSearchText(rawAddress);

  bool hasInLoc(List<String> keywords) {
    for (final kw in keywords) {
      final normKw = _normalizeBranchSearchText(kw);
      if (normCity.contains(normKw) || normParen.contains(normKw)) return true;
    }
    return false;
  }

  bool hasAnywhere(List<String> keywords) {
    for (final kw in keywords) {
      final normKw = _normalizeBranchSearchText(kw);
      if (normCity.contains(normKw) ||
          normParen.contains(normKw) ||
          normName.contains(normKw) ||
          normAddress.contains(normKw)) {
        return true;
      }
    }
    return false;
  }

  if (hasInLoc(['اسكندرية', 'الإسكندرية', 'alexandria', 'alex'])) {
    return _govAlexandria;
  }

  if (hasInLoc(['القاهرة', 'الجيزة', 'cairo', 'giza', 'اكتوبر', 'زايد', 'تجمع', 'معادي', 'شروق', 'بدر', 'عبور', 'مدينتي', 'رحاب'])) {
    return _govCairoGiza;
  }

  if (hasInLoc(['مطروح', 'الساحل الشمالي', 'ساحل', 'علمين', 'مارينا', 'امواج', 'روزانا', 'سيدي عبد الرحمن', 'الضبعة', 'الحمام'])) {
    return _govNorthCoast;
  }

  if (hasInLoc(['البحيرة', 'دمنهور', 'كفر الدوار', 'ايتاي', 'حوش عيسى', 'ابو حمص', 'رشيد', 'ادكو', 'كوم حمادة'])) {
    return _govBeheira;
  }

  if (hasInLoc(['الغربية', 'طنطا', 'المحلة', 'الدقهلية', 'المنصورة', 'المنوفية', 'شبين', 'القليوبية', 'بنها', 'الشرقية', 'الزقازيق', 'كفر الشيخ', 'دلتا'])) {
    return _govGharbiaDelta;
  }

  if (hasInLoc(['دمياط', 'بورسعيد', 'الإسماعيلية', 'السويس', 'القناة', 'راس البر'])) {
    return _govCanalDamietta;
  }

  if (hasInLoc(['صعيد', 'الفيوم', 'بني سويف', 'المنيا', 'اسيوط', 'سوهاج', 'قنا', 'الأقصر', 'اسوان', 'البحر الاحمر', 'الغردقة', 'شرم الشيخ'])) {
    return _govUpperEgypt;
  }

  if (hasAnywhere([
    'سموحة', 'ستانلي', 'سيدي بشر', 'سيدي جابر', 'الابراهيمية', 'الانفوشي',
    'الدخيلة', 'العجمي', 'الهانوفيل', 'البيطاش', 'ابو يوسف', 'جاردينيا',
    'سيتي سكوير', 'ميامي', 'فكتوريا', 'العصافرة', 'المنتزه', 'المندرة',
    'محرم بك', 'الشاطبي', 'كامب شيزار', 'كليوباترا', 'رشدي', 'جليم',
    'سابا باشا', 'ثروت', 'زيزينيا', 'جناكليس', 'بولكلي', 'شدس', 'العوايد',
    'السيوف', 'المعمورة', 'بحري', 'المنشية', 'محطة الرمل', 'الورديان', 'المكس', 'برج العرب'
  ])) {
    return _govAlexandria;
  }

  if (hasAnywhere([
    'المعادي', 'مدينة نصر', 'مصر الجديدة', 'التجمع', 'الرحاب', 'مدينتي',
    'الشروق', 'العبور', 'الشيخ زايد', '6 اكتوبر', 'حدائق الاهرام',
    'المهندسين', 'الدقي', 'الهرم', 'فيصل', 'العجوزة', 'الزمالك', 'شبرا',
    'حلوان', 'المقطم', 'عين شمس', 'المرج', 'المطرية', 'الزيتون', 'حدائق القبة'
  ])) {
    return _govCairoGiza;
  }

  if (hasAnywhere(['أمواج', 'امواج', 'روزانا', 'مارينا', 'مراسي', 'هاسيندا', 'العلمين'])) {
    return _govNorthCoast;
  }

  if (hasAnywhere(['دمنهور', 'كفر الدوار', 'ايتاي البارود'])) {
    return _govBeheira;
  }

  if (hasAnywhere(['المحلة', 'طنطا', 'المنصورة', 'بنها', 'الزقازيق', 'شبين الكوم'])) {
    return _govGharbiaDelta;
  }

  if (hasAnywhere(['دمياط', 'بورسعيد', 'الاسماعيلية', 'السويس', 'راس البر'])) {
    return _govCanalDamietta;
  }

  if (rawCity.isNotEmpty) {
    return rawCity;
  }

  return _govOther;
}

int _compareGovernorates(String a, String b) {
  final idxA = _canonicalGovernorateOrder.indexOf(a);
  final idxB = _canonicalGovernorateOrder.indexOf(b);
  if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
  if (idxA != -1) return -1;
  if (idxB != -1) return 1;
  return a.compareTo(b);
}

bool _doesBranchMatchQuery(BranchModel branch, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return true;
  final cleanQuery = _normalizeBranchSearchText(trimmed);
  if (cleanQuery.isEmpty) return true;

  final cleanName = _normalizeBranchSearchText(branch.branchName);
  final cleanCity = _normalizeBranchSearchText(branch.city);
  final cleanCode = _normalizeBranchSearchText(branch.branchCode);
  final cleanAddress = _normalizeBranchSearchText(branch.address);

  final fullText = '$cleanName $cleanCity $cleanCode $cleanAddress';

  if (fullText.contains(cleanQuery)) return true;

  final strippedQuery = cleanQuery.replaceAll(RegExp(r'\bفرع\b'), '').trim();
  final strippedName = cleanName.replaceAll(RegExp(r'\bفرع\b'), '').trim();
  if (strippedQuery.isNotEmpty) {
    if (strippedName.contains(strippedQuery) || fullText.contains(strippedQuery)) {
      return true;
    }
  }

  final tokens = cleanQuery.split(' ').where((t) => t.isNotEmpty && t != 'فرع').toList();
  if (tokens.isNotEmpty && tokens.every((token) => fullText.contains(token))) {
    return true;
  }

  return false;
}

void main() {
  group('Retail Chain Branch Governorate Grouping & Phonetic Live Search Tests', () {
    final fathallaBranches = [
      BranchModel(id: 'b1', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع أمواج', city: 'مطروح / الساحل الشمالي'),
      BranchModel(id: 'b2', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع ابو يوسف', city: 'الإسكندرية'),
      BranchModel(id: 'b3', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع اكتوبر', city: 'الإسكندرية'),
      BranchModel(id: 'b4', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع الابراهيمية', city: 'الإسكندرية'),
      BranchModel(id: 'b5', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع الابراهيمية ميني', city: 'الإسكندرية'),
      BranchModel(id: 'b6', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع الانفوشي', city: 'الإسكندرية'),
      BranchModel(id: 'b7', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع الدخيلة ميني', city: 'الإسكندرية'),
      BranchModel(id: 'b8', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع المحلة الكبرى', city: 'الغربية'),
      BranchModel(id: 'b9', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع بدر', city: 'القاهرة'),
      BranchModel(id: 'b10', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع دمنهور الاستاد', city: 'البحيرة'),
      BranchModel(id: 'b11', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع دمنهور الاندلس', city: 'البحيرة'),
      BranchModel(id: 'b12', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع دمياط الجديدة', city: 'دمياط'),
      BranchModel(id: 'b13', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع روزانا', city: 'مطروح / الساحل الشمالي'),
      BranchModel(id: 'b14', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع سموحة', city: 'الإسكندرية'),
      BranchModel(id: 'b15', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع سموحة ميني', city: 'الإسكندرية'),
      BranchModel(id: 'b16', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع ستانلي', city: 'الإسكندرية'),
      BranchModel(id: 'b17', retailChainId: 'fathalla', retailChainName: 'أسواق فتح الله', branchName: 'فرع سيدي بشر ميني', city: 'الإسكندرية'),
    ];

    test('All Fathalla branches resolve to their correct canonical governorates', () {
      expect(_resolveBranchGovernorate(fathallaBranches[0]), _govNorthCoast); // أمواج -> الساحل الشمالي ومطروح
      expect(_resolveBranchGovernorate(fathallaBranches[1]), _govAlexandria); // ابو يوسف -> الإسكندرية
      expect(_resolveBranchGovernorate(fathallaBranches[2]), _govAlexandria); // اكتوبر -> الإسكندرية (Agami)
      expect(_resolveBranchGovernorate(fathallaBranches[3]), _govAlexandria); // الابراهيمية -> الإسكندرية
      expect(_resolveBranchGovernorate(fathallaBranches[4]), _govAlexandria); // الابراهيمية ميني -> الإسكندرية
      expect(_resolveBranchGovernorate(fathallaBranches[7]), _govGharbiaDelta); // المحلة الكبرى -> الغربية والدلتا
      expect(_resolveBranchGovernorate(fathallaBranches[8]), _govCairoGiza); // بدر -> القاهرة والجيزة
      expect(_resolveBranchGovernorate(fathallaBranches[9]), _govBeheira); // دمنهور الاستاد -> البحيرة
      expect(_resolveBranchGovernorate(fathallaBranches[10]), _govBeheira); // دمنهور الاندلس -> البحيرة
      expect(_resolveBranchGovernorate(fathallaBranches[11]), _govCanalDamietta); // دمياط الجديدة -> دمياط ومدن القناة
      expect(_resolveBranchGovernorate(fathallaBranches[12]), _govNorthCoast); // روزانا -> الساحل الشمالي ومطروح
      expect(_resolveBranchGovernorate(fathallaBranches[13]), _govAlexandria); // سموحة -> الإسكندرية
    });

    test('Governorates are sorted in standard canonical Egyptian retail priority', () {
      final govs = [
        _govCanalDamietta,
        _govBeheira,
        _govAlexandria,
        _govGharbiaDelta,
        _govCairoGiza,
        _govNorthCoast,
      ];

      govs.sort(_compareGovernorates);

      expect(govs, [
        _govAlexandria,
        _govCairoGiza,
        _govNorthCoast,
        _govBeheira,
        _govGharbiaDelta,
        _govCanalDamietta,
      ]);
    });

    test('Live search: matches when typing "ابو يوسف" without prefix "فرع"', () {
      final results = fathallaBranches.where((b) => _doesBranchMatchQuery(b, 'ابو يوسف')).toList();
      expect(results.length, 1);
      expect(results.first.branchName, 'فرع ابو يوسف');
    });

    test('Live search: matches when typing "فرع ابو يوسف" with prefix', () {
      final results = fathallaBranches.where((b) => _doesBranchMatchQuery(b, 'فرع ابو يوسف')).toList();
      expect(results.length, 1);
      expect(results.first.branchName, 'فرع ابو يوسف');
    });

    test('Live search: matches "سموحة" returns main and mini branches', () {
      final results = fathallaBranches.where((b) => _doesBranchMatchQuery(b, 'سموحة')).toList();
      expect(results.length, 2);
      expect(results.map((b) => b.branchName), containsAll(['فرع سموحة', 'فرع سموحة ميني']));
    });

    test('Live search: matches "ميني" returns all mini branches', () {
      final results = fathallaBranches.where((b) => _doesBranchMatchQuery(b, 'ميني')).toList();
      expect(results.length, 4); // الابراهيمية ميني, الدخيلة ميني, سموحة ميني, سيدي بشر ميني
    });

    test('Live search: matches "دمنهور" returns Beheira branches', () {
      final results = fathallaBranches.where((b) => _doesBranchMatchQuery(b, 'دمنهور')).toList();
      expect(results.length, 2);
      expect(results.map((b) => b.branchName), containsAll(['فرع دمنهور الاستاد', 'فرع دمنهور الاندلس']));
    });

    test('Live search: matches "بدر" returns Cairo branch', () {
      final results = fathallaBranches.where((b) => _doesBranchMatchQuery(b, 'بدر')).toList();
      expect(results.length, 1);
      expect(results.first.branchName, 'فرع بدر');
    });

    test('Live search: matches phonetic "امواج" without hamza', () {
      final results = fathallaBranches.where((b) => _doesBranchMatchQuery(b, 'امواج')).toList();
      expect(results.length, 1);
      expect(results.first.branchName, 'فرع أمواج');
    });
  });
}
