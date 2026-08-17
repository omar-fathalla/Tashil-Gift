import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';

/// Material Design 3 Top Banner displayed when running any game in Live Demo / Simulation mode.
class GameDemoBanner extends ConsumerWidget {
  final VoidCallback? onReset;
  final VoidCallback? onExit;

  const GameDemoBanner({
    super.key,
    this.onReset,
    this.onExit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.tertiary.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.tertiary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.sports_esports_rounded,
                color: colorScheme.onTertiary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          strings.demoModeBannerTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.tertiary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'DEMO',
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: colorScheme.onTertiary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    strings.demoModeBannerDesc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: colorScheme.onTertiaryContainer.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            if (onReset != null) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: strings.playAgainDemo,
                onPressed: onReset,
              ),
            ],
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: Text(
                strings.demoExitBtn,
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onPressed: onExit ?? () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
