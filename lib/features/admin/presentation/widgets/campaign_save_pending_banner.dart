import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/campaign_save_confirmation.dart';

/// N-01: shown while a campaign save has not been confirmed by the server.
/// The links and QR stay hidden until [onVerify] confirms the save (or the
/// write lands by itself, TAG-43).
class CampaignSavePendingBanner extends StatelessWidget {
  const CampaignSavePendingBanner({
    super.key,
    required this.onVerify,
    this.verifying = false,
    this.message,
    this.errorDetail,
    this.onClearPending,
  });

  final VoidCallback onVerify;
  final bool verifying;

  /// Result of the last check (null before the first check).
  final String? message;

  /// TAG-43: technical error seen so far (e.g. "unavailable: ..."), if any.
  final String? errorDetail;

  /// TAG-43: drops the writes this browser could not send (web only).
  final VoidCallback? onClearPending;

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
            if (errorDetail != null && errorDetail!.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                errorDetail!,
                key: const ValueKey('tag43-pending-error'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('n01-verify-button'),
                  onPressed: verifying ? null : onVerify,
                  icon: verifying
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.verified_rounded, size: 18),
                  label: Text(CampaignSaveTexts.verifyButton, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ),
                if (onClearPending != null)
                  TextButton.icon(
                    key: const ValueKey('tag43-clear-pending'),
                    onPressed: onClearPending,
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: Text(CampaignSaveTexts.clearPendingButton, style: GoogleFonts.cairo()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// TAG-43: the save failed. Stays on screen (not a snackbar) with the real
/// error code and message until the next save.
class CampaignSaveFailedBanner extends StatelessWidget {
  const CampaignSaveFailedBanner({super.key, required this.failure, this.onClearPending});

  final CampaignSaveFailure failure;
  final VoidCallback? onClearPending;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('tag43-save-failed'),
      elevation: 0,
      color: cs.errorContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.error_rounded, color: cs.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    CampaignSaveTexts.failedTitle,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onErrorContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(CampaignSaveTexts.failedBody, style: GoogleFonts.cairo(fontSize: 13, color: cs.onErrorContainer)),
            const SizedBox(height: 8),
            SelectableText(
              failure.display,
              key: const ValueKey('tag43-failed-code'),
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: cs.onErrorContainer),
            ),
            if (onClearPending != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('tag43-clear-pending'),
                  onPressed: onClearPending,
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: Text(CampaignSaveTexts.clearPendingButton, style: GoogleFonts.cairo()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
