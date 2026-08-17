---
name: material-design-3-progress-indicators
description: Mandatory standard for Material Design 3 (M3) Linear and Circular Progress Indicators, animated progress bars, live percentage badges, batch processing streaming, file upload/download trackers, and indeterminate loading states across Flutter.
---

# Material Design 3 (M3) Progress Indicators & Download/Batch Standard

This skill establishes the mandatory architecture and design standards for **Progress Indicators, Download/Upload Bars, Batch Operations, and AI/Data Processing** across the entire application following Google's official **Material Design 3 (M3)** specification.

Whenever any asynchronous task, batch database write (Firestore), file download/upload, AI processing (Gemini), CSV/Excel import, or long-running operation is implemented or modified, you **MUST** strictly adhere to this standard.

---

## 1. Core Principles & Anti-Freezing Rules

### 🚫 The "Zero Static Freeze" Rule
- **Never display a frozen, static disabled button** with only a generic spinner or fixed text (e.g. `[ جاري الحفظ... 🔄 ]`) when processing large collections or long-running tasks.
- If an operation takes longer than 1 second or processes multiple items (e.g. saving 854 products), the UI **MUST** transition to an active **Material Design 3 Progress Indicator** with real-time feedback.

### 📊 Determinate vs. Indeterminate Standards
1. **Determinate Progress (`value: 0.0 -> 1.0`)**:
   - MUST be used whenever the total count of items, bytes, chunks, or steps is known in advance (e.g., Firestore batch writes, file uploads/downloads with byte counts, multi-step wizards).
   - MUST display:
     1. Animated Linear Progress Bar (`M3LinearProgress`) with rounded pill ends.
     2. Live percentage badge (e.g. `47%`, `100%`).
     3. Item counter (e.g. `تم حفظ 400 من 854 منتج`).
2. **Indeterminate Progress (`value: null`)**:
   - Used when total duration or item count is completely unknown (e.g. waiting for initial server connection, AI prompt generation).
   - MUST use M3 continuous sweep motion with `LinearProgressIndicator` or `M3LinearProgress(value: null)`.

---

## 2. Component Library Reference

Location: [`lib/core/widgets/m3_progress_indicators.dart`](file:///Users/fathalla/Development/al-mraay/lib/core/widgets/m3_progress_indicators.dart)

### A. M3 Linear Progress (`M3LinearProgress`)
A smooth, animated linear progress bar supporting both determinate and indeterminate modes:

```dart
import '../../core/widgets/m3_progress_indicators.dart';

// Determinate with smooth animation
M3LinearProgress(
  value: _progressValue, // 0.0 to 1.0
  height: 8.0,
  useGradient: true,
  color: Theme.of(context).colorScheme.primary,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
)

// Indeterminate wave
const M3LinearProgress(
  height: 6.0,
)
```

---

### B. M3 Progress Card (`M3ProgressCard`)
An elevated container widget ideal for batch operations, CSV imports, file downloads, and AI classification:

```dart
import '../../core/widgets/m3_progress_indicators.dart';

if (_isSaving)
  M3ProgressCard(
    title: 'جاري حفظ واعتماد المنتجات في الفايربيز',
    subtitle: 'يتم الآن تسجيل وترحيل المنتجات في قاعدة البيانات السحابية...',
    progress: _progressValue, // e.g. 0.47
    currentCount: _savedCount, // e.g. 400
    totalCount: _totalCount,   // e.g. 854
    icon: Icons.cloud_upload_rounded,
    onCancel: () => _cancelOperation(), // optional
  )
else
  FilledButton.icon(
    onPressed: _startBatchSave,
    icon: const Icon(Icons.cloud_upload_rounded),
    label: const Text('حفظ واعتماد 854 منتج'),
  )
```

---

## 3. Batch Streaming Implementation Pattern

When saving multiple items or executing chunked writes in Firestore, always split them into chunks (e.g. chunks of 200 or 400) and pass a progress callback:

### Service Layer (`CompanyProductsService`):
```dart
Future<int> batchSaveProducts({
  required String companySlug,
  required String companyName,
  required List<Map<String, dynamic>> products,
  void Function(int saved, int total)? onProgress,
}) async {
  int totalSaved = 0;
  const chunkSize = 400; // Under Firestore 500-op limit

  onProgress?.call(0, products.length);

  for (var i = 0; i < products.length; i += chunkSize) {
    final chunk = products.sublist(
      i,
      (i + chunkSize > products.length) ? products.length : i + chunkSize,
    );

    final batch = _firestore.batch();
    for (var item in chunk) {
      // populate batch...
      totalSaved++;
    }

    await batch.commit();
    onProgress?.call(totalSaved, products.length);
  }

  return totalSaved;
}
```

### UI Controller / Screen Layer:
```dart
setState(() {
  _isSaving = true;
  _progressValue = 0.0;
  _savedCount = 0;
  _totalCount = items.length;
});

await service.batchSaveProducts(
  companySlug: slug,
  companyName: name,
  products: items,
  onProgress: (saved, total) {
    if (mounted) {
      setState(() {
        _savedCount = saved;
        _totalCount = total;
        _progressValue = total > 0 ? (saved / total).clamp(0.0, 1.0) : 0.0;
      });
    }
  },
);

if (mounted) {
  setState(() {
    _progressValue = 1.0;
    _isSaving = false;
  });
  await M3Feedback.showSuccess(context, title: 'تم الحفظ بنجاح!');
}
```

---

## 4. Design & Motion Tokens

| Token / Attribute | Material Design 3 Standard Value | Description |
|---|---|---|
| **Track Height** | `6.0` to `10.0` dp | Standard height for linear progress |
| **Corner Radius** | `BorderRadius.circular(height / 2)` | Full pill-shaped track and indicator caps |
| **Track Color** | `colorScheme.surfaceContainerHighest` | Neutral, high-contrast background |
| **Indicator Color** | `colorScheme.primary` or Gradient | Primary brand indicator color |
| **Complete Color** | `Colors.green.shade600` / `Colors.green.shade800` | Smooth transition to success green on 100% |
| **Easing Curve** | `Curves.fastOutSlowIn` (Standard M3 Easing) | Smooth tween animation between value updates |
| **Animation Duration** | `300ms` | Smooth interpolation duration per progress tick |

---

## 5. Verification Checklist

Before approving any download, upload, or batch operation screen:
- [ ] No static disabled button with frozen text during active operations.
- [ ] Real-time progress percentage (0% to 100%) and item counter (`X of Y`) are visible.
- [ ] M3 Linear Progress bar has rounded corners (`BorderRadius.circular(4)` or pill) and dynamic theme colors.
- [ ] Smooth transition to success checkmark/dialog upon reaching 100%.
- [ ] `flutter analyze` passes with 0 errors and 0 warnings.
