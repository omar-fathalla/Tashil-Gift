import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/campaign_save_confirmation.dart';

/// N-01: shown while a campaign save has not been confirmed by the server.
/// The links and QR stay hidden until [onVerify] confirms the save.
class CampaignSavePendingBanner extends StatelessWidget {
  const CampaignSavePendingBanner({super.key, required this.onVerify, this.verifying = false, this.message});

  final VoidCallback onVerify;
  final bool verifying;

  /// Result of the last check (null before the first check).
  final String? message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('n01-save-pending'),
      elevation: 0,
      color: cs.tertiaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_rounded, color: cs.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    CampaignSaveTexts.unconfirmedTitle,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onTertiaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(CampaignSaveTexts.unconfirmedBody, style: GoogleFonts.cairo(fontSize: 13, color: cs.onTertiaryContainer)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                key: const ValueKey('n01-verify-message'),
                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onTertiaryContainer),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                key: const ValueKey('n01-verify-button'),
                onPressed: verifying ? null : onVerify,
                icon: verifying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.verified_rounded, size: 18),
                label: Text(CampaignSaveTexts.verifyButton, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
