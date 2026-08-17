import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/arabic_numbers_utils.dart';

void main() {
  group('ArabicNumbersExtension Tests', () {
    test('Converts Eastern Arabic digits to English digits', () {
      expect('٠١٢٣٤٥٦٧٨٩'.toEnglishDigits(), '0123456789');
      expect('١٩'.toEnglishDigits(), '19');
      expect('٢٤٥٠'.toEnglishDigits(), '2450');
      expect('٦٢٨١٠٠٧٠٠١٠٠١'.toEnglishDigits(), '6281007001001');
    });

    test('Converts Persian digits to English digits', () {
      expect('۰۱۲۳۴۵۶۷۸۹'.toEnglishDigits(), '0123456789');
      expect('۱۹'.toEnglishDigits(), '19');
    });

    test('Converts Arabic decimals (٫ and ،) to standard dot (.)', () {
      expect('٥٠٫٥'.toEnglishDigits(), '50.5');
      expect('١٠٠،٢٥'.toEnglishDigits(), '100.25');
    });

    test('toIntOrNull converts and parses integers', () {
      expect('١٩'.toIntOrNull(), 19);
      expect('٢٤٥٠'.toIntOrNull(), 2450);
      expect('  ١٠٠  '.toIntOrNull(), 100);
      expect('abc'.toIntOrNull(), isNull);
    });

    test('toDoubleOrNull converts and parses doubles', () {
      expect('٥٠٫٥'.toDoubleOrNull(), 50.5);
      expect('١٠٠'.toDoubleOrNull(), 100.0);
      expect('invalid'.toDoubleOrNull(), isNull);
    });
  });

  group('ArabicToEnglishDigitsFormatter Tests', () {
    test('DigitsOnly formatter transforms Arabic input to English digits in real-time', () {
      const formatter = ArabicToEnglishDigitsFormatter.digitsOnly();

      final result1 = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '١٩',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(result1.text, '19');

      final result2 = formatter.formatEditUpdate(
        const TextEditingValue(text: '19'),
        const TextEditingValue(
          text: '19٥',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(result2.text, '195');
    });

    test('Decimal formatter supports numbers with decimal points and converts Arabic comma/dot', () {
      const formatter = ArabicToEnglishDigitsFormatter.decimal();

      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '٥٠٫٥',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      expect(result.text, '50.5');
    });
  });
}
