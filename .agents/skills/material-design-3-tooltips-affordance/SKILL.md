---
name: material-design-3-tooltips-affordance
description: Mandatory Material Design 3 (M3) standards for Hover Tooltips, Contextual Affordance, Explanatory Micro-copy, and Progressive Disclosure across all interactive Flutter web and mobile components.
version: 1.0.0
---

# Material Design 3 Tooltips & Contextual Affordance Standard

This skill establishes the **mandatory standard for Hover Tooltips, Contextual Help, and Micro-copy Affordance** across all interactive components (buttons, icon buttons, form fields, action pills, segmented controls, status badges, and table actions) in Flutter Web, Desktop, and Mobile.

Interactive elements without clear explanatory text create cognitive friction. By implementing contextual tooltips, users instantly understand what an element does simply by hovering over it with the mouse or long-pressing on touch screens.

---

## 1. Scientific & UX Foundations (الأسس العلمية وتجربة المستخدم)

### أ. مبدأ الإفصاح التدريجي (Progressive Disclosure)
- بدلاً من ملء الشاشة بنصوص شرح طويلة تزدحم بها الواجهة، تظل الواجهة أنيقة ومبسطة، مع كشف الشرح الكامل بمجرد توجيه مؤشر الماوس (Hover) نحو العنصر.

### ب. مبادئ نيلسن ونورمان (Recognition over Recall & Affordance)
- وفقاً لمعايير **Don Norman & Jakob Nielsen**، يجب ألا يُجبر المستخدم على تخمين وظيفة الزر أو حفظها غيباً. التحويم يمنح تأكيداً فورياً لما سيحدث قبل الضغط على العنصر.

### ج. إرشادات مايكرو-كوبي الشرح الذكي (Actionable Explanatory Micro-copy)
- **خطأ (تكرار اسم الزر فقط):** الزر اسمه "حذف" والـ Tooltip يقول "حذف".
- **صحيح (شرح القيمة والأثر):** الزر اسمه "حذف" والـ Tooltip يوضح: *"حذف هذا المنتج وباركوده من النظام بشكل نهائي"*.

---

## 2. Mandatory Architectural Rules (القواعد الإلزامية)

### القاعدة 1: إلزامية الـ Tooltip لجميع الأزرار الأيقونية (Icon-only Buttons)
- **يُمنع منعاً باتاً** استخدام `IconButton` أو أي زر يعتمد على الأيقونة فقط بدون توفير خاصية `tooltip: '...'` واضحة ومفسرة باللغة العربية الفصحى البسيطة.

### القاعدة 2: تزويد مجموعات الأزرار والـ Chips بشرح وظيفي
- عند استخدام `M3ConnectedButtonGroup` أو `M3ButtonSegment`، يجب تزويد الخيارات الغامضة بـ `tooltip:` يشرح ماذا سيحدث عند اختيار هذا التبويب.

### القاعدة 3: إثراء أزرار الحذف والتعديل والإجراءات الحساسة
- أزرار الإجراءات المؤثرة (مثل: حذف شركة، تعديل كود، ترحيل دفعات منتجات) يجب أن تشرح نطاق التأثير (مثل: *"حذف هذه الشركة وجميع منتجاتها المرتبطة من النظام"*).

### القاعدة 4: توقيت الظهور المريح (Smooth Hover Timing)
- ضبط `waitDuration: const Duration(milliseconds: 400)` لمنع وميض الـ Tooltips أثناء الحركة السريعة للماوس عبر الشاشة.
- ضبط `showDuration: const Duration(milliseconds: 2000)`.

---

## 3. Standard Implementation Patterns (نماذج الاستخدام البرمجي)

### أ. على مستوى الـ IconButton
```dart
IconButton(
  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
  tooltip: 'حذف هذا الصنف نهائياً من قاعدة بيانات النظام',
  onPressed: () => _handleDelete(item),
)
```

### ب. على مستوى الأزرار النصية أو المركبة (`FilledButton`, `OutlinedButton`)
```dart
Tooltip(
  message: 'تعديل الاسم التجاري أو الكود الرقمي المعرف لهذه الشركة',
  waitDuration: const Duration(milliseconds: 400),
  child: FilledButton.tonalIcon(
    onPressed: () => _showEditDialog(),
    icon: const Icon(Icons.edit_note_rounded),
    label: const Text('تعديل الشركة'),
  ),
)
```

### ج. على مستوى حقول الإدخال والـ Form Fields
```dart
TextField(
  controller: _barcodeController,
  decoration: InputDecoration(
    labelText: 'كود الباركود الدولي (EAN / Barcode)',
    hintText: '6281007001001',
    suffixIcon: Tooltip(
      message: 'الباركود المطبوع على عبوة المنتج المكون من أرقام إنجليزية',
      child: const Icon(Icons.help_outline_rounded, size: 20),
    ),
  ),
)
```

### د. على مستوى شرائح ومجموعات الأزرار (`M3ButtonSegment`)
```dart
M3ConnectedButtonGroup<CatalogInputMode>(
  selectedValue: _activeMode,
  onSelected: (mode) => setState(() => _activeMode = mode),
  segments: const [
    M3ButtonSegment(
      value: CatalogInputMode.manual,
      label: 'إدخال يدوي للمنتج',
      icon: Icons.edit_note_rounded,
      tooltip: 'تسجيل المنتجات واحداً تلو الآخر عبر كتابة الاسم والباركود يدوياً',
    ),
    M3ButtonSegment(
      value: CatalogInputMode.excelCsv,
      label: 'استيراد ملف Excel / CSV',
      icon: Icons.file_upload_outlined,
      tooltip: 'رفع ملف إكسيل أو لصق أسطر CSV ليقوم الذكاء الاصطناعي بمعالجتها دفعة واحدة',
    ),
  ],
)
```
