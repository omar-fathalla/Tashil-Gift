import 'package:flutter/material.dart';

/// Official Material Design 3 (M3) Spacing Tokens Engine.
///
/// Ref: https://m3.material.io/foundations/layout/understanding-layout/spacing
///
/// Implements the official 4dp/8dp spatial grid scale, functional semantic tokens,
/// and bidirectional directional insets for Tashil Gift Enterprise Design System.
abstract class M3SpacingTokens {
  // --- Core Numerical Scale (Multiples of 4dp and 8dp) ---

  /// Zero spacing (0dp)
  static const double space0 = 0.0;

  /// Micro spacing (4dp) - tight icon gaps, badge offsets, micro tags
  static const double space1 = 4.0;

  /// Baseline unit (8dp) - fundamental M3 grid multiplier for adjacent siblings
  static const double space2 = 8.0;

  /// Compact input spacing & pills (12dp)
  static const double space3 = 12.0;

  /// Standard card & list tile internal padding (16dp)
  static const double space4 = 16.0;

  /// Medium section spacer (20dp)
  static const double space5 = 20.0;

  /// Standard dialog padding & gutter between columns (24dp)
  static const double space6 = 24.0;

  /// Prominent section header padding (28dp)
  static const double space7 = 28.0;

  /// Large card group separator (32dp)
  static const double space8 = 32.0;

  /// Hero section separator (40dp)
  static const double space10 = 40.0;

  /// Page margin & standard minimum touch target height/width (48dp)
  static const double space12 = 48.0;

  /// Generous margin for ultra-wide displays (64dp)
  static const double space16 = 64.0;

  // --- Functional Semantic Tokens ---

  /// Gap between an inline icon and its adjacent label (4dp)
  static const double inlineIconGap = space1;

  /// Gap between adjacent sibling widgets in forms and rows (8dp)
  static const double siblingGap = space2;

  /// Internal padding for standard dashboard cards (16dp)
  static const double cardInternalPadding = space4;

  /// Vertical gap between major dashboard sections (24dp)
  static const double sectionVerticalGap = space6;

  /// Minimum accessible touch target dimension for interactive components (48dp)
  static const double minTouchTarget = space12;

  // --- Bidirectional Insets (Natural RTL & LTR) ---

  /// Standard page padding for Compact (< 600dp) screens
  static const EdgeInsetsDirectional pagePaddingCompact =
      EdgeInsetsDirectional.all(space4);

  /// Standard page padding for Expanded (>= 840dp) screens
  static const EdgeInsetsDirectional pagePaddingExpanded =
      EdgeInsetsDirectional.symmetric(horizontal: space6, vertical: space4);

  /// Standard card internal directional padding
  static const EdgeInsetsDirectional cardPadding =
      EdgeInsetsDirectional.all(cardInternalPadding);

  /// Standard list item directional content padding
  static const EdgeInsetsDirectional listTilePadding =
      EdgeInsetsDirectional.symmetric(horizontal: space4, vertical: space2);

  /// Standard dialog directional content padding
  static const EdgeInsetsDirectional dialogPadding =
      EdgeInsetsDirectional.all(space6);
}
