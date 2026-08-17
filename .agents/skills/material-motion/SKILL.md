---
name: material-motion
description: Mandatory Material Design 3 (M3) and Google Android Motion System guidelines, micro-interactions, animated buttons, loading feedback, approval/success checkmarks, and addition animations for Flutter.
---

# Material Design 3 (M3) & Android Motion System Guidelines

This skill provides authoritative guidelines for building, animating, and handling user interactions, button clicks, async requests, approvals, additions, and screen transitions across the application using Google's **Material Design 3 (M3) & Android Motion** specification.

Whenever creating or modifying buttons, forms, lists, cards, dialogs, network/Firestore requests, approvals, additions, or navigation routes, you **MUST** adhere strictly to these motion standards.

---

## 1. Mandatory Motion Principles for AI Agents

1. **Every Button & Clickable Element MUST Have Tactile Feedback**:
   - Never use static, lifeless containers with bare `onTap` or static buttons without motion.
   - Use `AnimatedPressable` or `M3ActionButton` to provide a subtle spring scale bounce (`0.96` scale factor) and haptic feedback.

2. **Every Async Request / Action MUST Show M3 Loading Motion**:
   - For primary action buttons that trigger async tasks (login, receipt AI processing, saving forms, claiming gifts), use `M3ActionButton` with `isLoading: true` or `M3Feedback.showLoading(context, message: '...')`.
   - Never leave the user without animated progress feedback during any request.

3. **Every Approval / Success / Verification MUST Show the Animated Checkmark**:
   - For approving invoices, validating receipts, claiming prizes, saving settings, or completing onboarding, trigger the Material 3 Success Checkmark via `M3Feedback.showSuccess(context, title: '...', message: '...')` or `M3SuccessCheckmark`.

4. **Every Creation / Addition Action MUST Show the Animated Add Pop**:
   - When a new event, gift, company, or record is added, show the animated pop with `M3Feedback.showAdded(context, itemName: '...')` or animate the new item into the list using `M3AnimatedListItem`.

5. **Smooth Page & Screen Transitions**:
   - All navigation routes MUST utilize standard Material 3 Shared Axis & Fade Through transitions (`M3PageRoute` or the theme's `M3PageTransitionsBuilder`).

---

## 2. Core Reusable Motion Components & Usage

Location: `lib/core/animations/m3_motion.dart`

### A. Tactile Press Feedback (`AnimatedPressable`)
Wrap any custom card, widget, or button with `AnimatedPressable` to give it Google Android tactile scale response:

```dart
import '../../core/animations/m3_motion.dart';

AnimatedPressable(
  onTap: () {
    // Action handler
  },
  child: Card(
    child: Text('عنصر قابل للضغط'),
  ),
)
```

---

### B. Async Action Button (`M3ActionButton`)
Use `M3ActionButton` for any submit, action, or async operations. It smoothly handles loading spinners, success checkmarks, and button states without layout jumps:

```dart
import '../../core/animations/m3_motion.dart';

M3ActionButton(
  label: 'حفظ التغييرات',
  icon: Icons.save_rounded,
  isLoading: _isSaving,
  isSuccess: _isSaved,
  variant: M3ButtonVariant.filled, // or .tonal, .outlined, .text
  onPressed: () async {
    await _saveData();
  },
)
```

---

### C. Approval & Success Animation (`M3Feedback.showSuccess`)
Whenever an approval, validation, or successful action completes:

```dart
import '../../core/animations/m3_motion.dart';

// Show animated checkmark modal
await M3Feedback.showSuccess(
  context,
  title: 'تم اعتماد الفاتورة بنجاح',
  message: 'تم تحديث نقاط العميل وإرسال إشعار فوري.',
  buttonText: 'حسناً',
);
```

---

### D. Item Added Animation (`M3Feedback.showAdded`)
Whenever a user adds a new company, event, gift, or receipt:

```dart
import '../../core/animations/m3_motion.dart';

// Show animated addition modal
await M3Feedback.showAdded(
  context,
  itemName: 'قسيمة مشتريات 100 ر.س',
  message: 'تمت إضافة الهدية إلى عجلة الحظ بنجاح.',
  icon: Icons.card_giftcard_rounded,
);
```

---

### E. Interactive Approval Dialog (`M3Feedback.showApprovalDialog`)
Whenever an action requires explicit user confirmation/approval before proceeding:

```dart
import '../../core/animations/m3_motion.dart';

final confirmed = await M3Feedback.showApprovalDialog(
  context,
  title: 'تأكيد اعتماد الفاتورة',
  message: 'هل أنت متأكد من رغبتك في اعتماد هذه الفاتورة ومنح الهدية؟',
  confirmText: 'نعم، اعتمد الآن',
  cancelText: 'تراجع',
);

if (confirmed == true) {
  // Execute approval
}
```

---

### F. Animated List Items (`M3AnimatedListItem`)
Wrap list items or grid cards to give them a staggered, smooth slide-and-fade entry when mounted:

```dart
import '../../core/animations/m3_motion.dart';

ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return M3AnimatedListItem(
      index: index,
      child: ItemCard(item: items[index]),
    );
  },
)
```

---

### G. Screen Navigation (`M3PageRoute`)
When navigating between screens imperatively:

```dart
import '../../core/animations/m3_motion.dart';

Navigator.of(context).push(
  M3PageRoute(
    page: const TargetScreen(),
  ),
);
```

---

## 3. Workflow Checklist for AI Assistants

Before finalizing ANY new UI screen, widget, or user action:
- [ ] Is interactive feedback (`AnimatedPressable` / `M3ActionButton`) attached to buttons?
- [ ] Is an M3 loading state handled during async operations?
- [ ] Is an approval/success animation (`M3Feedback.showSuccess`) displayed upon successful completion?
- [ ] Is an addition animation (`M3Feedback.showAdded`) displayed when adding entities?
- [ ] Are lists rendered with `M3AnimatedListItem`?
