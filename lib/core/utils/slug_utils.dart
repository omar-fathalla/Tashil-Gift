/// Utility for generating clean, URL-friendly English slugs from Arabic or English campaign and company names.
class SlugUtils {
  static const Map<String, String> _knownBrandTranslations = {
    // Dairy & Juice
    'المراعي': 'almarai',
    'جهينة': 'juhayna',
    'دومتي': 'domty',
    'عبور لاند': 'obour-land',
    'لبنيتا': 'labanita',
    'بريزيدن': 'president',
    'بريزيدون': 'president',
    'لافاش كيري': 'la-vache-qui-rit',
    'فرجللو': 'faragalla',
    'لمار': 'lamar',
    'بيتي': 'beyti',
    'دانون': 'danone',
    'نستله': 'nestle',
    'نسله': 'nestle',
    'جرين لاند': 'greenland',
    'المراعي الخضراء': 'greenland',
    'المصريين': 'almasryeen',
    'باندا': 'panda',
    'طعمة': 'teama',
    'طعمة ميلك': 'teama-milk',
    'رودس': 'rhodes',

    // Beverages & Soda
    'بيبسي': 'pepsi',
    'كوكاكولا': 'coca-cola',
    'كوكا كولا': 'coca-cola',
    'سفن اب': '7up',
    'ميرندا': 'mirinda',
    'شويبس': 'schweppes',
    'فيروز': 'fayrouz',
    'بريل': 'birell',
    'ريد بول': 'redbull',
    'سي كولا': 'sico-cola',
    'سبيرو سباتس': 'spiro-spathis',
    'في 7': 'v7',
    'كينزا': 'kinza',
    'بارلي': 'barley',

    // Snacks & Confectionery
    'شيبسي': 'chipsy',
    'ليز': 'lays',
    'دوريتوس': 'doritos',
    'تايجر': 'tiger',
    'صن بايتس': 'sunbites',
    'بيج شيبس': 'big-chips',
    'لايون': 'lion',
    'فوكس': 'fox',
    'توداي': 'today',
    'أوريو': 'oreo',
    'كادبوري': 'cadbury',
    'جلاكسي': 'galaxy',
    'كيت كات': 'kitkat',
    'توينكيز': 'twinkies',
    'هوهوز': 'hohos',
    'كورونا': 'corona',
    'بيمبو': 'bimbo',
    'لوتس': 'lotus',
    'نوتيلا': 'nutella',
    'مولتو': 'molto',
    'تودو': 'todo',
    'بيك رولز': 'bake-rolls',
    'بيك ستيكس': 'bake-sticks',
    'فريسكا': 'freska',

    // Groceries & Cooking
    'عافية': 'afia',
    'صافولا': 'savola',
    'كريستال': 'crystal',
    'روابي': 'rawabi',

    'جنة': 'janna',
    'أمريكانا': 'americana',
    'فارم فريتس': 'farm-frites',
    'أطياب': 'atyab',
    'كوكي': 'koki',
    'حلواني': 'halwani',
    'حلواني اخوان': 'halwani-brothers',
    'الدوحة': 'eldoha',
    'الضحى': 'eldoha',
    'ريحانة': 'rehana',
    'الملكة': 'elmaleka',
    'ايطاليانو': 'italiano',
    'ريجينا': 'regina',
    'ستار': 'star',
    'زمزم': 'zamzam',
    'بونو': 'bono',
    'شاي العروسة': 'el-arosa',
    'العروسة': 'el-arosa',
    'ليبتون': 'lipton',
    'أحمد تي': 'ahmad-tea',
    'إيزيس': 'isis',
    'نسكافيه': 'nescafe',
    'على كافيه': 'alicafe',
    'بونجورنو': 'bonjorno',
    'دريم': 'dream',
    'تاج الملوك': 'tag-elmolouk',
    'فايف مينتس': 'five-minutes',
    'مجي': 'maggi',
    'فاين فودز': 'fine-foods',
    'كنور': 'knorr',
    'هاينز': 'heinz',
    'هارفست': 'harvest',
    'جيفركس': 'givrex',
    'بسمة': 'basma',
    'مونتانا': 'montana',
    'سما': 'sama',

    // Cleaning & Personal Care
    'أريال': 'ariel',
    'تايد': 'tide',
    'برسيل': 'persil',
    'أوكسي': 'oxi',
    'بونكس': 'bonux',
    'داوني': 'downy',
    'كمفورت': 'comfort',
    'فيري': 'fairy',
    'بريل سائل': 'pril',
    'فيبا': 'feba',
    'كلوركس': 'clorox',
    'ديتول': 'dettol',
    'جنرال': 'general',
    'فلاش': 'flash',
    'هاربيك': 'harpic',
    'لوكس': 'lux',
    'دوف': 'dove',
    'لايفبوي': 'lifebuoy',
    'بالموليف': 'palmolive',
    'كاماي': 'camay',
    'صانسيلك': 'sunsilk',
    'بانتين': 'pantene',
    'هيد اند شولدرز': 'head-and-shoulders',
    'كلير': 'clear',
    'لوريال': 'loreal',
    'فاتيكا': 'vatika',
    'سيجنال': 'signal',
    'كولجيت': 'colgate',
    'كلوس اب': 'close-up',
    'سنسوداين': 'sensodyne',
    'فاين': 'fine',
    'زينة': 'zeina',
    'وايت': 'white',
    'بابيا': 'papia',
    'فاميليا': 'familia',
    'بامبرز': 'pampers',
    'بيبي جوي': 'babyjoy',
    'فاين بيبي': 'fine-baby',
    'مولفيكس': 'molfix',
    'كانبيبي': 'canbebe',
    'إيفا': 'eva',
    'جونسون': 'johnsons',
    'نيفيا': 'nivea',
    'جليد': 'glade',
    'ايرويك': 'airwick',
    'فريدا': 'frida',
    'ريد': 'raid',
    'بايجون': 'baygon',

    // Retailers
    'فتح الله': 'fathalla',
    'أسواق فتح الله': 'fathalla',
    'كارفور': 'carrefour',
    'سبينس': 'spinneys',
    'سعودي': 'seoudi',
    'هايبر وان': 'hyper-one',
    'مترو': 'metro',
    'خير زمان': 'kheir-zaman',
    'كازيون': 'kazyon',
    'بيم': 'bim',
    'لولو': 'lulu',
    'لولو هايبر ماركت': 'lulu-hypermarket',
    'العثيم': 'othaim',
    'بنده': 'panda',
    'الدانوب': 'danube',
    'التميمي': 'tamimi',
    'ألفا ماركت': 'alfa-market',
    'المحمل': 'el-mahmal',
    'أولاد رجب': 'ragab-sons',
    'راية': 'raya',
    'بي تك': 'b-tech',
    'العربي': 'elaraby',
    'سويتش بوينت': 'switch-point',
  };

  static const Map<String, String> _arabicCharMap = {
    'أ': 'a', 'إ': 'e', 'آ': 'a', 'ا': 'a',
    'ب': 'b', 'ت': 't', 'ث': 'th', 'ج': 'g',
    'ح': 'h', 'خ': 'kh', 'د': 'd', 'ذ': 'th',
    'ر': 'r', 'ز': 'z', 'س': 's', 'ش': 'sh',
    'ص': 's', 'ض': 'd', 'ط': 't', 'ظ': 'z',
    'ع': 'a', 'غ': 'gh', 'ف': 'f', 'ق': 'q',
    'ك': 'k', 'ل': 'l', 'م': 'm', 'ن': 'n',
    'ه': 'h', 'و': 'w', 'ي': 'y', 'ى': 'a',
    'ة': 'a', 'ء': '', 'ئ': 'y', 'ؤ': 'o',
    'پ': 'p', 'چ': 'ch', 'ڤ': 'v', 'گ': 'g',
  };

  /// Alias for generateEnglishSlug
  static String generateSlug(String input) => generateEnglishSlug(input);

  /// Generates a clean English slug from an input string (Arabic or English).
  static String generateEnglishSlug(String input) {
    String trimmed = input.trim();
    if (trimmed.isEmpty) return 'campaign';

    // 1. Check direct known brand match
    final lowerTrimmed = trimmed.toLowerCase();
    for (final entry in _knownBrandTranslations.entries) {
      if (lowerTrimmed == entry.key || lowerTrimmed == entry.key.toLowerCase()) {
        return entry.value;
      }
    }

    // 2. Check if text already has Latin/English letters
    final hasLatin = RegExp(r'[a-zA-Z]').hasMatch(trimmed);
    final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(trimmed);

    if (hasLatin && !hasArabic) {
      return trimmed
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
    }

    // 3. Replace known keywords inside phrase
    String transformed = trimmed;
    _knownBrandTranslations.forEach((arKey, enVal) {
      transformed = transformed.replaceAll(arKey, ' $enVal ');
    });

    // 4. Transliterate remaining Arabic characters
    final buffer = StringBuffer();
    for (int i = 0; i < transformed.length; i++) {
      final char = transformed[i];
      if (_arabicCharMap.containsKey(char)) {
        buffer.write(_arabicCharMap[char]);
      } else if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
        buffer.write(char.toLowerCase());
      } else if (char == ' ' || char == '-' || char == '_') {
        buffer.write('-');
      }
    }

    final result = buffer.toString()
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    return result.isNotEmpty ? result : 'campaign';
  }

  /// Formats a slug (e.g. "almarai" -> "Almarai", "coca-cola" -> "Coca Cola") into a human-readable title.
  static String formatSlugToName(String slug) {
    if (slug.isEmpty) return '';
    return slug
        .split(RegExp(r'[-_]'))
        .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}' : '')
        .join(' ')
        .trim();
  }
}

