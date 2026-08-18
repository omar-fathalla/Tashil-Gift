---
name: trilingual-localization-standard
description: Mandatory trilingual localization standard (Arabic, English, and UAE/GCC Retail Hindi) across all UI screens, forms, dialogs, validation messages, data tables, and content in Flutter.
version: 1.0.0
---

# Trilingual Localization Standard (Arabic, English, Hindi)

This skill defines the **mandatory architectural and UI localization standard** for all screens, forms, dialogs, validation messages, tables, cards, tooltips, and content across the application.

Whenever the AI creates, modifies, or reviews any UI screen, widget, form field, modal dialog, error message, or data table, it **MUST** strictly adhere to this standard.

---

## 1. The Trilingual Requirement & Context

The application operates across the Middle East and GCC retail markets (Egypt 🇪🇬, UAE 🇦🇪, Saudi Arabia 🇸🇦), serving a diverse workforce of administrators, brand managers, and retail promoters. Every single piece of user-facing content **MUST** support the 3 official application languages:

1. **العربية (Arabic - `ar`)**: Primary language, Right-to-Left (RTL), default locale, Cairo typography.
2. **English (`en`)**: Left-to-Right (LTR), International business and management standard.
3. **हिन्दी (Hindi - `hi`)**: Left-to-Right (LTR), Devanagari script, serving the widespread retail promoter, cashier, and field coordinator workforce across the UAE and GCC.

---

## 2. Mandatory Architectural Rules

### Rule 1: No Hardcoded User-Facing Strings in UI Widgets
Never hardcode raw string literals directly inside widgets (e.g., `Text('حفظ')` or `Text('Submit')` or `Text('سجل الفواتير')`).
- All user-facing strings **MUST** be defined in the centralized dictionary [`lib/core/localization/app_strings.dart`](file:///Users/fathalla/Development/al-mraay/lib/core/localization/app_strings.dart).
- Strings must provide all three translations using the helper `_t(ar: ..., en: ..., hi: ...)`.

```dart
// In lib/core/localization/app_strings.dart
String get saveChanges => _t(
  ar: 'حفظ التعديلات',
  en: 'Save Changes',
  hi: 'परिवर्तन सहेजें',
);
```

### Rule 2: Accessing Strings Reactively in Consumer Widgets
In any `ConsumerWidget` or `ConsumerStatefulWidget`, retrieve localized strings through Riverpod:

```dart
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';

@override
Widget build(BuildContext context, WidgetRef ref) {
  // Watches active locale and triggers immediate rebuild on language toggle
  final strings = AppStrings.of(ref);
  
  return Scaffold(
    appBar: AppBar(
      title: Text(strings.eventsTitle),
    ),
    body: Center(
      child: Text(strings.totalActiveEvents),
    ),
  );
}
```

### Rule 3: Instant Trilingual Form Transformation
All form fields (labels, placeholder hints, floating labels, prefix/suffix text, and validator error messages) **MUST** be dynamic and react instantaneously when the language is changed:

```dart
TextFormField(
  controller: _nameController,
  decoration: InputDecoration(
    labelText: strings.eventNameLabel,
    hintText: strings.eventNameHint,
    prefixIcon: const Icon(Icons.campaign_rounded),
  ),
  validator: (val) {
    if (val == null || val.trim().isEmpty) {
      return strings.requiredField; // e.g. "هذا الحقل مطلوب" / "This field is required" / "यह फ़ील्ड आवश्यक है"
    }
    return null;
  },
)
```

### Rule 4: Dynamic Directionality (RTL vs LTR)
The app must automatically adjust layout flow based on the active language:
- **Arabic (`ar`)**: `TextDirection.rtl`
- **English (`en`)** & **Hindi (`hi`)**: `TextDirection.ltr`

```dart
Directionality(
  textDirection: strings.isAr ? TextDirection.rtl : TextDirection.ltr,
  child: ...
)
```

When building custom rows with icons and badges, use directional alignment or flex layouts that adapt naturally with the root `Directionality`.

### Rule 5: Trilingual Dialogs, Modals & Notifications
All dialogs (Validation Report Dialogs, Winner Celebration Dialogs, Deletion Confirmations, Inactive Campaign Warnings) and SnackBars must be localized:

```dart
// Example: Confirmation Dialog
showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(strings.deleteEventConfirmTitle),
    content: Text(strings.deleteEventConfirmMsg),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(strings.cancel),
      ),
      FilledButton(
        onPressed: () => _confirmDelete(),
        child: Text(strings.delete),
      ),
    ],
  ),
);
```

### Rule 6: Trilingual Data Tables & Filter Chips
Table column headers, empty state placeholders, sort buttons, and filter chip labels must be supplied from `AppStrings`:

```dart
DataColumn(label: Text(strings.receiptNumberCol)),
DataColumn(label: Text(strings.receiptDateCol)),
DataColumn(label: Text(strings.receiptAmountCol)),
DataColumn(label: Text(strings.receiptStatusCol)),
```

### Rule 7: Coexistence with Arabic Numerals Normalization Standard
Even when the UI language is switched to English or Hindi, the app's input formatters and parsing logic MUST continue to accept both Western (`0-9`) and Eastern/Persian Arabic numerals (`٠-٩` / `۰-۹`) seamlessly as per the [`arabic-numerals-normalization`](file:///Users/fathalla/Development/al-mraay/.agents/skills/arabic-numerals-normalization/SKILL.md) skill.

### Rule 8: Clean Button Text (Strictly No Emojis in Button Text Strings)
Never embed Unicode emojis (like 📸, 🪄, ✨, 🚀, 🎯, 🔍) in button text strings in `AppStrings`. The icon must be provided exclusively once as a Flutter `Icon` widget in the button (e.g. `FilledButton.icon(icon: Icon(Icons.camera_alt_rounded), label: Text(strings.uploadReceiptSampleBtn))`) to prevent double-icon rendering.

---

## 3. Localization Architecture Reference

| Component | File Path | Purpose |
| :--- | :--- | :--- |
| **Dictionary (`AppStrings`)** | [`lib/core/localization/app_strings.dart`](file:///Users/fathalla/Development/al-mraay/lib/core/localization/app_strings.dart) | Central repository for all trilingual strings (`ar`, `en`, `hi`). |
| **Locale Provider (`localeProvider`)** | [`lib/core/localization/locale_provider.dart`](file:///Users/fathalla/Development/al-mraay/lib/core/localization/locale_provider.dart) | Global Riverpod state managing the active `Locale` and toggle methods. |
| **Language Switcher Widget** | [`lib/core/widgets/switch_point_branding.dart`](file:///Users/fathalla/Development/al-mraay/lib/core/widgets/switch_point_branding.dart) | Header action badge for one-tap switching between 🇦🇪 عربي / 🇬🇧 EN / 🇮🇳 हिन्दी. |
| **Unit & Localization Tests** | [`test/locale_provider_test.dart`](file:///Users/fathalla/Development/al-mraay/test/locale_provider_test.dart) | Test suite ensuring trilingual strings are complete and non-empty. |

---

## 4. AI Verification & Pre-Generation Checklist (Mandatory Protocol)

Whenever the AI is tasked with creating or updating any screen, form, or widget, it **MUST review and fulfill** the following 7-point checklist:

- [ ] **1. Central Dictionary:** Are all new text strings added to [`AppStrings`](file:///Users/fathalla/Development/al-mraay/lib/core/localization/app_strings.dart) with valid translations for Arabic (`ar`), English (`en`), and Hindi (`hi`)?
- [ ] **2. Reactive Watch:** Does the widget call `final strings = AppStrings.of(ref);` inside `build()` to trigger instant UI updates when language changes?
- [ ] **3. Form Inputs:** Are all `labelText`, `hintText`, `helperText`, and `validator` returns using `strings.*`?
- [ ] **4. Action Buttons:** Are all buttons (Save, Cancel, Delete, Edit, Export, Next, Close) using `strings.*`?
- [ ] **5. Modals & Dialogs:** Are all titles, subtitles, confirmation messages, and report cards localized in all 3 languages?
- [ ] **6. Table Headers & Chips:** Are table columns, status badges, and filter tabs localized?
- [ ] **7. Zero Hardcoded Text:** Are there zero raw Arabic or English text literals in the widget code?
