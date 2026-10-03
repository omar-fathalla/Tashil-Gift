---
name: material-design-3-action-menus-standard
description: Mandatory Material Design 3 (M3) standard for Action Menus, Cascading Submenus, MenuAnchor, 8dp corner radius, Level 2 elevation, automatic RTL/LTR arrow mirroring, keyboard navigation, and touch target safety across Flutter.
---

# Material Design 3 (M3) Action Menus & Cascading Submenus Standard

This skill establishes the mandatory architectural and UI specification for **Material Design 3 (M3) Action Menus, Cascading Submenus, Overflow Actions, and Contextual Pickers** across the Tashil Gift platform.

Whenever building or refactoring action menus, row action bars, campaign card options, export menus, branch switchers, or contextual dropdowns, you **MUST** strictly adhere to this standard.

---

## 1. Specification & Standards Matrix

### 🏛️ A. Modern M3 Architecture (`MenuAnchor` vs `PopupMenuButton`)
- **Strict Legacy Deprecation**: The legacy `PopupMenuButton` widget is strictly deprecated across the entire codebase. All action menus MUST be implemented using Flutter M3's official `MenuAnchor`, `MenuItemButton`, and `SubmenuButton` primitives wrapped by `M3ActionMenu`.
- **Anchor Versatility**: Supports both standard icon buttons (`anchorIcon: Icon(...)`) and custom widgets (`anchorBuilder: (context, controller, child) => ...`), enabling filled buttons, chips, table cells, or cards to trigger menus effortlessly.

### 🎨 B. Container Styling & Material 3 Elevation
Every menu surface MUST strictly follow Google's Material Design 3 elevation and color tokens:
- **Surface Color**: Strictly `Theme.of(context).colorScheme.surfaceContainer`. Never use raw `Colors.white`, `Colors.grey`, or `surface`.
- **Corner Radius**: Strictly **8.0dp** (`RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0))`).
- **Elevation & Shadow**: Material 3 Level 2 elevation (`elevation: 2.0`) with subtle ambient shadow (`Colors.black.withValues(alpha: 0.18)`).
- **Subtle Outline Border**: 1.0dp border using `colorScheme.outlineVariant.withValues(alpha: 0.5)`.
- **Vertical Padding**: Standard 4dp padding (`M3SpacingTokens.space1`) at the top and bottom of the menu container.

### 📏 C. Responsive Density & Sizing
- **Mobile / Touch Devices (`<840dp`)**: Standard height of **48dp** per menu item to ensure effortless touch interaction.
- **Desktop / Mouse (`≥840dp`)**: Compact height of **40dp** per menu item for efficient data density in admin portals and analytical tables.
- **Minimum Width**: 160dp on desktop, 180dp on mobile.
- **Maximum Width**: Constrained at 320dp with text truncation (`TextOverflow.ellipsis`).
- **Touch Target Boundary**: The menu anchor button on touch devices MUST strictly adhere to the **48x48dp** minimum touch target boundary (`M3SpacingTokens.minTouchTarget`).

### 🌐 D. Bidirectional Cascading Submenus & Automatic Mirroring
- **Hierarchical Nesting**: Multi-level menus (e.g. Export Options -> CSV, Excel, Print) MUST use `M3ActionMenu.submenu`.
- **Automatic Directional Mirroring**:
  - In **Arabic (`ar` / RTL)**: Submenu navigation arrows MUST point **LEFT** (`Icons.chevron_left_rounded`).
  - In **English (`en` / LTR)** & **Hindi (`hi` / LTR)**: Submenu navigation arrows MUST point **RIGHT** (`Icons.chevron_right_rounded`).
  - `M3ActionMenu.submenu` evaluates `Directionality.of(context)` at runtime and renders the correct arrow direction automatically.

### 🎯 E. Visual Hierarchy & Destructive Actions
- **Logical Section Headers**: Use `M3ActionMenu.header` to provide 11sp bold Cairo category labels in `colorScheme.primary`.
- **Group Separation**: Use `M3ActionMenu.divider` (1dp thickness with 4dp vertical padding) between distinct functional groups.
- **Highlighted Destructive Actions**: Any permanent or irreversible action (e.g. Delete, Cancel, Revoke) MUST set `isDestructive: true`. This automatically styles the icon, text, and hover state in **`colorScheme.error`**, visually isolating dangerous operations.
- **Selection Feedback**: Filter items and option pickers support `isSelected: true`, displaying an automatic checkmark (`Icons.check_rounded`) and bold `colorScheme.primary` styling.
- **Keyboard Shortcuts**: Optional trailing shortcut badges (e.g. `Ctrl+E`, `⌘S`) via `shortcutText`.

### ⌨️ F. Full Keyboard & Assistive Accessibility (a11y)
- **Arrow Keys**: Seamless navigation with `ArrowUp` and `ArrowDown`.
- **Looping**: Automatically wraps from last item to first item and vice versa.
- **Activation**: Triggers instantly with `Enter` or `Space`.
- **Dismissal**: Closes cleanly with `Escape` or tapping outside.
- **Typeahead**: Supports keyboard character focus jumping.

---

## 2. Component Library Reference

Source: [`lib/core/widgets/m3_action_menu.dart`](file:///Users/fathalla/Development/Tashil%20Gift/lib/core/widgets/m3_action_menu.dart)

### A. Standard Icon Action Menu
```dart
M3ActionMenu(
  tooltip: isAr ? 'خيارات الفاتورة' : 'Invoice Actions',
  anchorIcon: const Icon(Icons.more_vert_rounded, size: 20),
  children: [
    M3ActionMenu.header(
      context: context,
      title: isAr ? 'الإجراءات' : 'Actions',
    ),
    M3ActionMenu.item(
      context: context,
      label: isAr ? 'عرض التفاصيل' : 'View Details',
      icon: Icons.visibility_outlined,
      onPressed: () => showInvoiceDetails(invoice),
    ),
    M3ActionMenu.item(
      context: context,
      label: isAr ? 'تحميل صورة الفاتورة' : 'Download Receipt Image',
      icon: Icons.file_download_outlined,
      onPressed: () => downloadReceiptImage(invoice),
    ),
    M3ActionMenu.divider(),
    M3ActionMenu.item(
      context: context,
      label: isAr ? 'إلغاء وحذف الفاتورة' : 'Cancel & Delete Invoice',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
      onPressed: () => confirmDeleteInvoice(invoice),
    ),
  ],
)
```

### B. Cascading Export Submenu
```dart
M3ActionMenu(
  tooltip: isAr ? 'تصدير التقارير' : 'Export Reports',
  anchorBuilder: (context, controller, child) {
    return FilledButton.tonalIcon(
      onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      icon: const Icon(Icons.download_rounded, size: 18),
      label: Text(isAr ? 'تصدير' : 'Export'),
    );
  },
  children: [
    M3ActionMenu.header(
      context: context,
      title: isAr ? 'صيغ التصدير المتاحة' : 'Export Formats',
    ),
    M3ActionMenu.item(
      context: context,
      label: isAr ? 'تقرير إكسيل كامل (.xlsx)' : 'Excel Workbook (.xlsx)',
      icon: Icons.table_chart_rounded,
      onPressed: () => exportToExcel(),
    ),
    M3ActionMenu.item(
      context: context,
      label: isAr ? 'ملف بيانات (.csv)' : 'CSV Data Sheet (.csv)',
      icon: Icons.description_outlined,
      onPressed: () => exportToCsv(),
    ),
    M3ActionMenu.divider(),
    M3ActionMenu.submenu(
      context: context,
      label: isAr ? 'خيارات إضافية' : 'Advanced Options',
      icon: Icons.tune_rounded,
      children: [
        M3ActionMenu.item(
          context: context,
          label: isAr ? 'طباعة / PDF' : 'Print / PDF',
          icon: Icons.print_rounded,
          onPressed: () => printReport(),
        ),
      ],
    ),
  ],
)
```

### C. Contextual Selection Picker (e.g. Branch Filter or Language Switcher)
```dart
M3ActionMenu(
  tooltip: isAr ? 'تصفية حسب الفرع' : 'Filter by Branch',
  children: [
    M3ActionMenu.header(
      context: context,
      title: isAr ? 'الفروع المعتمدة' : 'Canonical Branches',
    ),
    M3ActionMenu.item(
      context: context,
      label: isAr ? 'جميع الفروع' : 'All Branches',
      isSelected: selectedBranch == 'ALL',
      onPressed: () => onBranchSelected('ALL'),
    ),
    M3ActionMenu.divider(),
    ...canonicalBranches.map((branch) => M3ActionMenu.item(
      context: context,
      label: branch,
      isSelected: selectedBranch == branch,
      onPressed: () => onBranchSelected(branch),
    )),
  ],
)
```

---

## 3. Strict Rules & Anti-Patterns

| ❌ Forbidden Anti-Pattern | ✅ Mandatory M3 Standard |
| :--- | :--- |
| Using legacy `PopupMenuButton<T>` or `DropdownButton<T>` | Strictly use `M3ActionMenu` built on `MenuAnchor` |
| Hardcoding chevron icons (`Icons.chevron_right`) in submenus | Use `M3ActionMenu.submenu` which automatically mirrors in RTL/LTR |
| Hardcoding white/grey background colors in menu styling | Use `colorScheme.surfaceContainer` with Level 2 elevation |
| Plain text for dangerous delete actions | Use `isDestructive: true` with `colorScheme.error` |
| Tiny icon anchors without touch boundaries (< 48dp) | Constrain anchors to minimum 48x48dp touch target on touchscreens |
| Cluttering tables or cards with 5+ raw action buttons | Group primary actions into a clean `M3ActionMenu` |
