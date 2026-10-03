---
name: material-design-3-lists-and-tiles-standard
description: Mandatory standard for Material Design 3 (M3) ListTiles, standard line heights (56dp/72dp/88dp), directional 72dp Inset Dividers, 48x48dp touch target boundaries, 48dp subheaders, and accessibility across Flutter.
---

# Material Design 3 (M3) Lists, ListTiles & Inset Dividers Standard

This skill establishes the mandatory architectural and UI specification for **Material Design 3 (M3) Lists, ListTiles, Inset Dividers, Subheaders, and Touch Targets** across the entire application.

Whenever building or refactoring lists, transaction logs, prize claim displays, branch directories, settings menus, or tabular items, you **MUST** strictly adhere to this standard.

---

## 1. Specification & Standards Matrix

### 📏 A. Standard Fixed Heights
Every list tile MUST strictly adhere to the official Material Design 3 line height constraints:

| Line Count | Mobile / Touch (`<840dp`) | Desktop / Compact (`≥840dp`) | Typical Use Cases |
| :--- | :--- | :--- | :--- |
| **One-Line** (`M3ListTile.oneLine`) | **56dp** | **44dp – 48dp** | Simple navigation items, single labels, toggles, filter options. |
| **Two-Line** (`M3ListTile.twoLine`) | **72dp** | **60dp** | Products, gifts, contact items (Headline + Subtitle). |
| **Three-Line** (`M3ListTile.threeLine`) | **88dp** | **76dp** | Invoices, receipts, detailed logs (Headline + Subtitle + Timestamp/Tags). |

### 📐 B. Directional Inset Dividers (`M3InsetDivider`)
- **Start Indent**: Fixed at **72dp** (`indent: 72.0`, `endIndent: 0.0`).
- **Alignment Alignment**: 72dp equals `16dp start margin + 40dp leading avatar/icon + 16dp spacing`, aligning the divider perfectly with the start of the headline text.
- **RTL & LTR Automatic Mirroring**: In Flutter, `Divider(indent: 72)` evaluates against the ambient `Directionality`:
  - **In Arabic (`ar` / RTL)**: The divider indents 72dp from the **RIGHT**.
  - **In English (`en` / LTR) & Hindi (`hi` / LTR)**: The divider indents 72dp from the **LEFT**.

### 🔘 C. Accessibility & Minimum Touch Targets (a11y)
- **Minimum 48x48dp Touch Targets**: Every trailing action button, icon button, or interactive clickable target MUST be wrapped in or constrained by `M3TouchTargetBoundary` (`minSize: 48.0` / 48x48dp) to satisfy WCAG 2.1 AA and Google Play Accessibility guidelines.
- **Auditory & Screen-Reader Semantics**: Every list item MUST provide a descriptive `semanticsLabel` (e.g. `فاتورة رقم 1024، القيمة 450 ج.م، الحالة مقبولة`) for seamless assistive technology navigation.

### 🎨 D. Visual Selection State (`isSelected`)
- **Instantaneous (0ms) Visual Feedback**: When `isSelected: true`, the tile immediately takes:
  - Background: `colorScheme.secondaryContainer` (with subtle elevation or border).
  - Border: `Border.all(color: colorScheme.primary, width: 1.5)`.
  - Border Radius: `BorderRadius.circular(12.0)`.

### 🏷️ E. Subheaders (`M3Subheader`)
- **Height**: Fixed at **48dp** (`height: 48.0`).
- **Typography**: 12–13sp bold `GoogleFonts.cairo` with `colorScheme.primary` or `colorScheme.onSurfaceVariant`.
- **Layout**: Directional padding, optional leading icon, and trailing action/filter chip support.

---

## 2. Component Library Reference

Source: [`lib/core/widgets/m3_list_tile.dart`](file:///Users/fathalla/Development/Tashil%20Gift/lib/core/widgets/m3_list_tile.dart)

### A. One-Line ListTile
```dart
M3ListTile.oneLine(
  leading: const Icon(Icons.settings_outlined),
  headline: Text(strings.settingsLabel),
  trailing: const Icon(Icons.chevron_right_rounded),
  onTap: () => navigateToSettings(),
)
```

### B. Two-Line ListTile
```dart
M3ListTile.twoLine(
  leading: ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Image.network(gift.imageUrl, width: 40, height: 40, fit: BoxFit.cover),
  ),
  headline: Text(gift.giftName),
  subtitle: Text('هدية فورية معتمدة'),
  trailing: M3TouchTargetBoundary(
    minSize: 48,
    child: QuantityBadge(count: gift.quantity),
  ),
  semanticsLabel: '${gift.giftName}, الكمية ${gift.quantity}',
)
```

### C. Three-Line ListTile (e.g. Invoices & Receipts)
```dart
M3ListTile.threeLine(
  isSelected: isSelected,
  leading: StoreAvatar(chain: invoice.storeChain, size: 40),
  headline: Text('فاتورة #${invoice.receiptNumber}'),
  subtitle: Text('${invoice.storeChain} - ${invoice.branchName}'),
  supportingText: Text('${invoice.formattedDate} • ${invoice.itemsCount} منتجات'),
  trailing: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text('${invoice.totalValue} ج.م', style: TextStyle(fontWeight: FontWeight.w900)),
      StatusBadge(status: invoice.status),
    ],
  ),
  trailingActions: [
    M3TouchTargetBoundary(
      minSize: 48,
      child: IconButton(
        icon: const Icon(Icons.visibility_outlined),
        onPressed: () => viewInvoice(invoice),
      ),
    ),
  ],
  onTap: () => selectInvoice(invoice),
  semanticsLabel: 'فاتورة #${invoice.receiptNumber}, إجمالي ${invoice.totalValue} جنيه',
)
```

### D. Inset Divider Between Tiles
```dart
ListView.separated(
  itemCount: items.length,
  separatorBuilder: (context, index) => const M3InsetDivider(),
  itemBuilder: (context, index) => M3ListTile(...),
)
```

### E. Grouped Sections with 48dp Subheaders
```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    M3Subheader(
      height: 48,
      icon: Icons.storefront_rounded,
      title: Text('فروع كارفور (12 فرع)'),
      trailing: TextButton(onPressed: expandAll, child: Text('عرض الكل')),
    ),
    const M3InsetDivider(),
    // Branch tiles
  ],
)
```

---

## 3. Acceptance Criteria Checklist

- [ ] **Height Compliance**: 56dp (1 line), 72dp (2 lines), 88dp (3 lines) constrained on mobile.
- [ ] **72dp Directional Inset**: Divider starts at 72dp from natural layout start (Right in AR, Left in EN/HI).
- [ ] **Touch Target Safety**: All trailing action buttons have at least 48x48dp tappable dimensions.
- [ ] **0ms Instant Selection**: Selected items instantly acquire `secondaryContainer` and 12dp border radius.
- [ ] **Zero Overflows & 60 FPS**: Heavy list scrolling remains silky smooth with no layout shifts.
- [ ] **Semantics Provided**: VoiceOver / TalkBack reads invoice/gift data clearly.
