---
name: material-design-3
description: Mandatory Material Design 3 (M3) design system standards, dynamic single-seed theme guidelines, and Button Groups specification for Flutter.
---

# Material Design 3 (M3) Design System Guidelines

This skill provides authoritative guidelines for building and styling user interface components, screens, and design tokens across the application using Google's **Material Design 3 (M3)** specification.

Whenever creating or modifying screens, widgets, layouts, forms, dialogs, or themes, you MUST adhere strictly to these M3 standards.

---

## 1. Core Principles

1. **Strict M3 Enabling**: `useMaterial3: true` MUST be set on all `ThemeData` instances.
2. **Single Seed Color Generation**: All UI color roles (Primary, OnPrimary, PrimaryContainer, OnPrimaryContainer, Secondary, Surface, SurfaceContainer, Outline, Error) MUST be generated programmatically from a single seed color using `ColorScheme.fromSeed(seedColor: ..., brightness: ...)`.
3. **Accessibility & Contrast**: Never hardcode arbitrary static HEX colors (like `#000000` or `#FFFFFF`) directly on text or background widgets. Always reference theme roles like `colorScheme.onSurface`, `colorScheme.surfaceContainer`, `colorScheme.primaryContainer`.
4. **Adaptive RTL & Typography**: Use `GoogleFonts.cairoTextTheme()` for Arabic typography hierarchy, utilizing M3 display, headline, title, body, and label text styles.

---

## 2. Dynamic M3 Color Roles & Usage

| M3 Role | Use Case / Guidance |
| :--- | :--- |
| `primary` | Prominent actions, active navigation states, primary buttons, selected button group state. |
| `onPrimary` | Text and icons rendered on top of `primary`. |
| `primaryContainer` | Highlighted cards, key stat badges, active tab background. |
| `onPrimaryContainer` | Text/icons inside `primaryContainer`. |
| `secondaryContainer` | Active navigation rail/bar indicator, secondary connected buttons. |
| `surface` | Screen background and default base containers. |
| `surfaceContainerLow` / `surfaceContainer` / `surfaceContainerHigh` | Card backgrounds, dialog surfaces, elevated containers, button group unselected tracks. |
| `onSurface` | High-emphasis body text and primary headers. |
| `onSurfaceVariant` | Medium-emphasis captions, field labels, unselected button icons/text. |
| `outline` / `outlineVariant` | Component borders, list dividers, segmented button group borders. |

---

## 3. Material Design 3 Button Groups (M3 Button Groups)

Ref: [https://m3.material.io/components/button-groups/overview](https://m3.material.io/components/button-groups/overview)

Button groups organize buttons and add interactions between them.

### A. Connected Button Groups (Segmented Buttons)
- **Visual Design**: Seamlessly connected buttons sharing adjacent borders.
- **Outer Geometry**: Outer left/right ends have large rounded radii (e.g. `24px` or full pill shape `StadiumBorder()`), with inner dividing borders.
- **Selected State**: 
  - Filled background with `colorScheme.primary` or `colorScheme.secondaryContainer`.
  - Prefix Checkmark icon (`Icons.check`) or distinct selected icon.
  - High-contrast text (`colorScheme.onPrimary` or `colorScheme.onSecondaryContainer`).
- **Unselected State**:
  - `colorScheme.surfaceContainerHighest` or transparent fill with `outlineVariant` border.
  - Text in `colorScheme.onSurfaceVariant`.
- **Modes**: Supports Single-Select (Radio behavior) and Multi-Select (Filter behavior).

### B. Standard & Morphing Button Groups
- **Visual Design**: Distinct separated buttons / capsules / circles grouped horizontally or vertically.
- **Shapes**: Capsules (`StadiumBorder`), circles, or squircle shapes.
- **Interaction**: Used for toolbars, quick action bars, media controls, and status toggles.

---

## 4. Typography Hierarchy (Cairo M3 Tokens)

| Role | Font Size | Weight | Use Case |
| :--- | :--- | :--- | :--- |
| `displayLarge` / `displayMedium` | 32 - 45px | Bold (w700) | Dashboard hero numbers & splash headers |
| `headlineMedium` / `headlineSmall` | 20 - 28px | SemiBold (w600) | Screen titles & section headers |
| `titleMedium` / `titleSmall` | 14 - 16px | Medium (w500) | Card titles, list headers, tab text, button groups |
| `bodyLarge` / `bodyMedium` | 14 - 16px | Regular (w400) | Paragraphs, description text |
| `labelLarge` | 14px | SemiBold (w600) | Button labels, chip text, action items |

---

## 5. Component Standard Specifications

### A. Buttons (M3 Family)
- **Primary / Hero Actions**: Use `FilledButton` or `FilledButton.tonal`.
- **Secondary Actions**: Use `OutlinedButton` with `BorderSide(color: colorScheme.outline)`.
- **Tertiary Actions**: Use `TextButton`.
- **Button Groups**: Use `M3ConnectedButtonGroup` / `SegmentedButton` or `M3MorphingButtonGroup`.
- **Floating Action Buttons**: Use `FloatingActionButton` or `FloatingActionButton.extended` with `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))`.

### B. Cards & Containers
- Standard Card shape: `RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))`.
### C. Text Fields (Input Decoration)
- Filled variant with `fillColor: colorScheme.surfaceContainerHighest`.
- Border radius: `12px` to `16px`.
- Active focus border: `2px` width in `colorScheme.primary`.

### D. Unified Iconography & Color Tokens (M3 & Google Fonts Icons)
- **Mandatory Icon Family**: Strictly use **Material Design 3 Rounded Icons** (`Icons.*_rounded` from the Flutter Material library / Google Symbols). Never mix conflicting icon sets or styles.
- **Strict Color Harmonization (No Arbitrary Colors)**:
  - All icons MUST derive their colors dynamically from the active M3 `ColorScheme` generated from the brand purple seed.
  - Primary / Interactive / Brand Icons: `colorScheme.primary` or `colorScheme.onPrimaryContainer`.
  - Neutral / Secondary Icons: `colorScheme.onSurfaceVariant` or `colorScheme.outline`.
  - Never use random static colors (e.g. no arbitrary orange, no arbitrary bright green, no random yellow, no hardcoded HEX).
  - Semantic Status Colors:
    * Error: `colorScheme.error` or `colorScheme.onErrorContainer`.
    * Warning / Alert: `colorScheme.tertiary` or `colorScheme.onTertiaryContainer`.
    * Success: `colorScheme.primary` or structured M3 Success container.
- **No Raw Emojis in Form Labels or Dropdowns**:
  - NEVER embed raw Unicode emoji arrows or icons (such as `🔽`, `➡️`, `⚡`, `⚠️`, `✅`) inside `labelText`, `hintText`, or dropdown labels. Always use native `prefixIcon`, `suffixIcon`, or standard Flutter dropdown controls.
- **LTR / RTL Directional Icon Placement**:
  - In English / LTR pills, buttons, and badges (e.g. footer links, contact pills): The **Icon MUST be on the left** (leading), followed by the text on the right (`[Icon] [Text]`).
  - In Arabic / RTL components: The **Icon MUST be on the right** (leading for RTL), followed by the Arabic text on the left (`[Icon] [النص العربي]`).

---

## 6. Material Motion & Animation System (M3 Motion)

Every interactive UI element, button, request, and screen MUST have fluid animations adhering to Android & M3 specifications:

- **Button Micro-Interactions**: Use `AnimatedPressable` or `M3ActionButton` for tactile press scale bounce (`0.96` scale on tap).
- **Loading / Async Requests**: Use `M3ActionButton` (with `isLoading`) or `M3Feedback.showLoading()` during all asynchronous tasks and API/Firestore calls.
- **Approval & Verification**: Trigger the animated checkmark modal via `M3Feedback.showSuccess(...)` or `M3Feedback.showApprovalDialog(...)` whenever an invoice is approved, gift claimed, or action succeeds.
- **Item Creation / Additions**: Trigger the animated add pop via `M3Feedback.showAdded(...)` or wrap list elements in `M3AnimatedListItem`.
- **Page Transitions**: Always use `M3PageRoute` or the theme's built-in `M3PageTransitionsBuilder` for smooth screen navigation.

---

## 7. Workflow Requirement for AI Assistants

When requested to create or update ANY screen, action, or component:
1. **Read this SKILL file** and the `material-motion` skill to ensure complete alignment with Material Design 3 and Android Motion.
2. Utilize `Icons.*_rounded` with dynamic `colorScheme.primary` / `colorScheme.onSurfaceVariant` (no arbitrary colors or emojis).
3. Utilize `M3ActionButton` / `AnimatedPressable` for buttons and clickable containers.
4. Utilize `M3ConnectedButtonGroup` / `SegmentedButton` whenever presenting modes, filters, or paired actions.
5. Always provide feedback animations (`M3Feedback.showSuccess`, `M3Feedback.showAdded`, `M3Feedback.showLoading`) for user interactions.
6. Ensure `AppTheme.lightTheme` or `AppTheme.darkTheme` is used in `MaterialApp`.

