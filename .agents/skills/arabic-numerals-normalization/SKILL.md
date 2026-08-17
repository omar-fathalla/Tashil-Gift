---
name: arabic-numerals-normalization
description: Mandatory standard for automatic Eastern Arabic (٠-٩) and Persian (۰-۹) numeral conversion to Western digits (0-9) across all numeric input fields, parsing, validation, and database storage in Flutter.
version: 1.0.0
---

# Arabic & Persian Numerals Normalization Standard

This skill defines the **mandatory architectural and UI standard** for handling numeric input, formatting, parsing, validation, and storage across the application.

Whenever creating, modifying, or reviewing any screen, widget, form field, dialog, or service that handles numbers (quantities, prices, currency, minimum spend, barcodes, company codes, phone numbers, counters, or statistics), you **MUST** strictly adhere to this standard.

---

## 1. Core Problem & Rationale

On Arabic keyboards (mobile & desktop), users frequently type Eastern Arabic numerals (`٠ ١ ٢ ٣ ٤ ٥ ٦ ٧ ٨ ٩`) or Persian numerals (`۰ ۱ ۲ ۳ ۴ ۵ ۶ ۷ ۸ ۹`).

- Standard Flutter `FilteringTextInputFormatter.digitsOnly` **blocks** Eastern Arabic digits from being typed entirely.
- Standard Dart `int.tryParse('١٩')` or `double.tryParse('٥٠٫٥')` returns `null`, causing false validation errors (e.g., *"الكمية يجب أن تكون رقماً صحيحاً"*).
- Inconsistent storage leads to duplicate records, broken search filters, and failed mathematical computations.

---

## 2. Mandatory Rules

### Rule 1: All Number Input Fields MUST Use `ArabicToEnglishDigitsFormatter`
Never use plain `FilteringTextInputFormatter.digitsOnly` or raw `TextInputType.number` without the formatter.

```dart
import '../../../core/utils/arabic_numbers_utils.dart';

// For integer inputs (quantities, codes, barcodes, phone numbers):
TextFormField(
  keyboardType: TextInputType.number, // or TextInputType.phone
  inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
  ...
)

// For decimal/currency inputs (prices, spend limits, discounts):
TextFormField(
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  inputFormatters: [const ArabicToEnglishDigitsFormatter.decimal()],
  ...
)
```

### Rule 2: All Numeric Parsing MUST Use Safe Extensions
Never call `int.tryParse(text)` or `double.tryParse(text)` directly on raw user strings. Always use the extensions provided in [`lib/core/utils/arabic_numbers_utils.dart`](file:///Users/fathalla/Development/al-mraay/lib/core/utils/arabic_numbers_utils.dart).

```dart
import '../../../core/utils/arabic_numbers_utils.dart';

// Safe integer parsing:
final int qty = myController.text.toIntOrNull() ?? 0;

// Safe double/decimal parsing:
final double amount = myController.text.toDoubleOrNull() ?? 0.0;

// Text normalization (barcodes, phone numbers, search queries):
final String cleanCode = myController.text.toEnglishDigits().trim();
```

### Rule 3: Form Validation MUST Check Normalized Values
In `validator` callbacks of `TextFormField`, validate against normalized numbers:

```dart
validator: (value) {
  if (value == null || value.trim().isEmpty) return 'مطلوب';
  if (value.toDoubleOrNull() == null) return 'يرجى إدخال رقم صحيح';
  if ((value.toDoubleOrNull() ?? 0) <= 0) return 'القيمة يجب أن تكون أكبر من الصفر';
  return null;
}
```

### Rule 4: Standard ASCII Digits in Database & Backend
All numbers saved to Firestore, Realtime Database, Local Storage, or REST APIs must be saved in standard Western digits (`0-9`):
- Phone numbers: `"01012345678"` (never `"٠١٠١٢٣٤٥٦٧٨"`)
- Barcodes: `"6281007001001"`
- Company Codes / Slugs: `"2450"`
- Financial / Quantity fields: stored as numeric `int` or `double`

### Rule 5: Search & Filter Normalization
When searching by code, barcode, or numeric query, normalize the query string before comparing or querying Firestore:

```dart
onChanged: (val) {
  final cleanVal = val.toEnglishDigits().trim().toLowerCase();
  final matches = list.where((item) => item.code.contains(cleanVal)).toList();
}
```

---

## 3. Central Utility Reference

The canonical implementation is located at:
- **Utility File:** [`lib/core/utils/arabic_numbers_utils.dart`](file:///Users/fathalla/Development/al-mraay/lib/core/utils/arabic_numbers_utils.dart)
- **Unit Tests:** [`test/arabic_numbers_utils_test.dart`](file:///Users/fathalla/Development/al-mraay/test/arabic_numbers_utils_test.dart)

### Digit Translation Map Reference:
| Arabic Eastern | Persian | Western (Target) |
| :---: | :---: | :---: |
| ٠ | ۰ | 0 |
| ١ | ۱ | 1 |
| ٢ | ۲ | 2 |
| ٣ | ۳ | 3 |
| ٤ | ۴ | 4 |
| ٥ | ۵ | 5 |
| ٦ | ۶ | 6 |
| ٧ | ۷ | 7 |
| ٨ | ۸ | 8 |
| ٩ | ۹ | 9 |
| ٫ أو ، | , | . (Decimal) |
