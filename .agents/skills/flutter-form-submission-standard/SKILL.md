---
name: flutter-form-submission-standard
description: Mandatory standard for all Flutter form submissions, asynchronous button actions, Firestore write operations, auto-resetting input fields, auto-focus management, keyboard actions (Next/Done), and loading state safety.
version: 1.0.0
---

# Flutter Form Submission & Async Action Standard

This skill defines the **mandatory architectural and UI/UX standard** for all form submissions, data-entry workflows, asynchronous button actions, and Firestore/backend writes across the Flutter application.

Whenever creating, modifying, or reviewing any screen, widget, dialog, or form that creates, updates, or deletes data (e.g. adding gifts, registering companies, creating campaigns, adding catalog products, updating invoices, submitting forms), you **MUST** strictly adhere to this standard.

---

## 1. Core Problem & Rationale

1. **Stuck / Freezing Loading Buttons:**
   On Flutter (especially Flutter Web), asynchronous writes like `docRef.set(...)`, `collection.add(...)`, `batch.commit()`, or network calls return a Future/Promise that can wait indefinitely for remote server acknowledgment if network latency is high or offline synchronization is pending. Meanwhile, Firestore's local cache updates immediately. Without proper timeout and lifecycle guards, buttons remain permanently stuck in "جاري التسجيل..." or spinning progress indicators.

2. **Friction in Continuous Data Entry:**
   In management screens (e.g., adding gifts, registering companies, scanning barcodes), users frequently enter multiple records in succession. Leaving the form fields un-cleared or losing cursor focus forces the user to manually select and delete text with the mouse, causing severe UX friction.

---

## 2. Mandatory Rules

### Rule 1: Always Protect Async Writes with Smart Timeout
Every asynchronous write (`set`, `update`, `delete`, `add`, `batch.commit()`) in UI controllers/handlers **MUST** include a timeout (typically `4` seconds) to prevent infinite UI freezes.

```dart
await docRef.set({
  'id': docRef.id,
  'name': name,
  'createdAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true)).timeout(
  const Duration(seconds: 4),
  onTimeout: () {
    // Firestore local cache handles local mutation and syncs in the background
  },
);
```

---

### Rule 2: Guaranteed Loading State Teardown (`try/catch/finally`)
Loading flags (e.g. `_isLoading`, `_isSaving`) **MUST** be initialized inside `try` and unconditionally reset inside `finally`:

```dart
setState(() => _isLoading = true);

try {
  // 1. Async network / Firestore call with timeout
  await service.saveData(...).timeout(const Duration(seconds: 4), onTimeout: () {});

  // 2. Clear inputs & auto-focus
  _nameController.clear();
  _qtyController.clear();
  if (mounted) {
    _nameFocusNode.requestFocus();
    // 3. Floating Success SnackBar
    ScaffoldMessenger.of(context).showSnackBar(...);
  }
} catch (e) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء الحفظ')),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
} finally {
  if (mounted) {
    setState(() => _isLoading = false);
  }
}
```

---

### Rule 3: Automatic Form Fields Reset on Success
Upon successful submission, immediately clear all text controllers:
- `_firstController.clear();`
- `_secondController.clear();`
Never require the user to manually erase previous input to add the next item.

---

### Rule 4: Auto-Focus Management for Continuous Flow
1. Maintain `FocusNode` for the primary input field.
2. After clearing fields, call `_firstFocusNode.requestFocus();`.
3. Always dispose all `FocusNode` instances in the widget's `dispose()` method.

```dart
final FocusNode _nameFocusNode = FocusNode();
final FocusNode _codeFocusNode = FocusNode();

@override
void dispose() {
  _nameController.dispose();
  _codeController.dispose();
  _nameFocusNode.dispose();
  _codeFocusNode.dispose();
  super.dispose();
}
```

---

### Rule 5: Keyboard Flow (Next & Done Actions)
Never rely solely on mouse clicks. Support full keyboard navigation:
- Intermediate fields: `textInputAction: TextInputAction.next` with `onFieldSubmitted: (_) => _nextFocusNode.requestFocus()`
- Final field: `textInputAction: TextInputAction.done` with `onFieldSubmitted: (_) => _isLoading ? null : _submitForm()`

```dart
// First field
TextFormField(
  controller: _nameController,
  focusNode: _nameFocusNode,
  textInputAction: TextInputAction.next,
  onFieldSubmitted: (_) => _codeFocusNode.requestFocus(),
  ...
)

// Final field
TextFormField(
  controller: _codeController,
  focusNode: _codeFocusNode,
  textInputAction: TextInputAction.done,
  onFieldSubmitted: (_) => _isLoading ? null : _submitForm(),
  ...
)
```

---

### Rule 6: Modern Floating Feedback (SnackBar)
Feedback messages must be floating, rounded, and clearly differentiated by state:

```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Row(
      children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'تمت العملية بنجاح!',
            style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
    backgroundColor: Colors.green.shade800,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    duration: const Duration(seconds: 2),
  ),
);
```

---

## 3. Standard Implementation Template

```dart
class MyFormWidgetState extends ConsumerState<MyFormWidget> {
  final _nameController = TextEditingController();
  final _qtyController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _qtyFocusNode = FocusNode();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _qtyController.dispose();
    _nameFocusNode.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_isSubmitting) return;

    final name = _nameController.text.trim();
    final qty = _qtyController.text.toIntOrNull();

    if (name.isEmpty || qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى التحقق من صحة البيانات المدخلة'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final docRef = ref.read(firestoreProvider).collection('items').doc();
      await docRef.set({
        'id': docRef.id,
        'name': name,
        'quantity': qty,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 4), onTimeout: () {});

      _nameController.clear();
      _qtyController.clear();

      if (mounted) {
        _nameFocusNode.requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('تمت الإضافة بنجاح')),
              ],
            ),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء الحفظ')),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
```
