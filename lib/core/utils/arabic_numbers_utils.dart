import 'package:flutter/services.dart';

/// Extension on [String] to seamlessly handle and convert Eastern Arabic numerals
/// (٠ ١ ٢ ٣ ٤ ٥ ٦ ٧ ٨ ٩) and Persian numerals (۰ ۱ ۲ ۳ ۴ ۵ ۶ ۷ ۸ ۹)
/// to standard Western English digits (0 1 2 3 4 5 6 7 8 9).
extension ArabicNumbersExtension on String {
  /// Converts Eastern Arabic and Persian numerals to standard Western digits.
  /// Also converts Arabic decimal separator (٫) or Arabic comma (،) when needed.
  String toEnglishDigits({bool convertDecimal = true}) {
    const arabicEastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

    String result = this;
    for (int i = 0; i < 10; i++) {
      result = result.replaceAll(arabicEastern[i], english[i]);
      result = result.replaceAll(persian[i], english[i]);
    }

    if (convertDecimal) {
      result = result.replaceAll('٫', '.').replaceAll('،', '.');
    }

    return result;
  }

  /// Parses the string to an [int] safely after converting any Arabic/Persian digits.
  int? toIntOrNull() {
    final clean = toEnglishDigits().trim();
    return int.tryParse(clean);
  }

  /// Parses the string to a [double] safely after converting any Arabic/Persian digits.
  double? toDoubleOrNull() {
    final clean = toEnglishDigits().trim();
    return double.tryParse(clean);
  }
}

/// A [TextInputFormatter] that automatically converts Eastern Arabic and Persian digits
/// to standard English digits in real-time as the user types.
///
/// Can optionally enforce digits-only or allow decimal numbers.
class ArabicToEnglishDigitsFormatter extends TextInputFormatter {
  final bool digitsOnly;
  final bool allowDecimal;

  const ArabicToEnglishDigitsFormatter({
    this.digitsOnly = false,
    this.allowDecimal = false,
  });

  /// Factory for strictly integer fields (e.g. quantities, codes, barcodes)
  const ArabicToEnglishDigitsFormatter.digitsOnly()
      : digitsOnly = true,
        allowDecimal = false;

  /// Factory for monetary / decimal fields (e.g. prices, minimum spend)
  const ArabicToEnglishDigitsFormatter.decimal()
      : digitsOnly = false,
        allowDecimal = true;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1. Convert all Arabic/Persian digits to English digits
    String formatted = newValue.text.toEnglishDigits(convertDecimal: allowDecimal);

    // 2. Filter if restricted
    if (digitsOnly) {
      formatted = formatted.replaceAll(RegExp(r'[^0-9]'), '');
    } else if (allowDecimal) {
      formatted = formatted.replaceAll(RegExp(r'[^0-9.]'), '');
      // Ensure at most one decimal point
      final dotIndex = formatted.indexOf('.');
      if (dotIndex != -1) {
        final beforeDot = formatted.substring(0, dotIndex + 1);
        final afterDot = formatted.substring(dotIndex + 1).replaceAll('.', '');
        formatted = '$beforeDot$afterDot';
      }
    }

    // 3. Calculate cursor position safely
    int selectionOffset = newValue.selection.end;
    if (selectionOffset > formatted.length) {
      selectionOffset = formatted.length;
    } else if (selectionOffset < 0) {
      selectionOffset = 0;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: selectionOffset),
    );
  }
}
