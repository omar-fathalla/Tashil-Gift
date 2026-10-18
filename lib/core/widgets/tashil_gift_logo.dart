import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Official Material Design 3 Brand Logo for Tashil Gift ('G' Monogram).
/// Matches the Switch Point Enterprise Identity (M3 Default Blue squircle + bold white 'G').
class TashilGiftLogo extends StatelessWidget {
  final double size;
  final double? borderRadius;
  final bool showShadow;

  const TashilGiftLogo({
    super.key,
    this.size = 40,
    this.borderRadius,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? (size * 0.28);
    const olivePrimary = Color(0xFF5C631D);
    const oliveDeep = Color(0xFF444B04);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            olivePrimary,
            oliveDeep,
          ],
        ),
        borderRadius: BorderRadius.circular(effectiveRadius),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: olivePrimary.withValues(alpha: 0.28),
                  blurRadius: size * 0.22,
                  offset: Offset(0, size * 0.06),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        'G',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: size * 0.62,
          fontWeight: FontWeight.w900,
          height: 1.0,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
