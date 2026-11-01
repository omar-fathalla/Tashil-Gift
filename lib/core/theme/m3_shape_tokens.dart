import 'package:flutter/material.dart';

/// Material Design 3 shape scale (corner radius tokens).
/// Ref: https://m3.material.io/styles/shape/corner-radius-scale
abstract class M3Shape {
  static const double none = 0;
  static const double extraSmall = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double extraLarge = 28;

  static const BorderRadius radiusSmall = BorderRadius.all(Radius.circular(small));
  static const BorderRadius radiusMedium = BorderRadius.all(Radius.circular(medium));
  static const BorderRadius radiusLarge = BorderRadius.all(Radius.circular(large));
  static const BorderRadius radiusExtraLarge = BorderRadius.all(Radius.circular(extraLarge));
}

/// Material Design 3 elevation levels (dp).
/// Ref: https://m3.material.io/styles/elevation/tokens
abstract class M3Elevation {
  static const double level0 = 0;
  static const double level1 = 1;
  static const double level2 = 3;
  static const double level3 = 6;
  static const double level4 = 8;
  static const double level5 = 12;
}
