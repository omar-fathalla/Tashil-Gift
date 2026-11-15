import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/m3_progress_indicators.dart';
import '../../domain/whatsapp_campaign_media.dart';
import '../../domain/whatsapp_gateway_service.dart';

/// Poster / PDF controls on the WhatsApp campaign composer.
///
/// The primary action picks a file from the device. A pasted link stays
/// available as a fallback and is used only when no uploaded file is ready.
class WhatsAppCampaignMediaPanel extends StatelessWidget {
  final AppStrings strings;
  final bool isAr;
  final TextEditingController urlController;
  final WhatsAppCampaignMediaAttachment? attachment;
  final bool uploading;
  final double? progress;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final VoidCallback onUrlChanged;

  const WhatsAppCampaignMediaPanel({
    super.key,
    required this.strings,
    required this.isAr,
    required this.urlController,
    required this.attachment,
    required this.uploading,
    required this.progress,
    required this.onPick,
    required this.onClear,
    required this.onUrlChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uploaded = attachment;
    final pastedUrl = urlController.text.trim();
    final percent = (((progress ?? 0) * 100).round()).clamp(0, 100);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.upload_file_rounded, size: 18, color: cs.primary),
              const SizedBox(width: M3Spacing.xs),
              Expanded(
                child: Text(
                  strings.campaignMediaPickFile,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: M3Spacing.xs),
          Text(
            strings.campaignMediaPickHint,
            style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: M3Spacing.sm),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: uploading ? null : onPick,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: Text(
              uploaded == null
                  ? strings.campaignMediaPickFile
                  : strings.campaignMediaReplace,
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
          if (uploading) ...[
            const SizedBox(height: M3Spacing.sm),
            M3LinearProgress(value: progress ?? 0),
            const SizedBox(height: M3Spacing.xs),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$percent%',
                    style: GoogleFonts.robotoMono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: M3Spacing.xs),
                Expanded(
                  child: Text(
                    strings.campaignMediaUploading,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (uploaded != null) ...[
            const SizedBox(height: M3Spacing.sm),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    uploaded.isPdf
                        ? Icons.picture_as_pdf_rounded
                        : Icons.image_rounded,
                    color: cs.onSecondaryContainer,
                  ),
                  const SizedBox(width: M3Spacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          uploaded.displayName,
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            color: cs.onSecondaryContainer,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          strings.campaignMediaReady,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: strings.campaignMediaClear,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: uploading ? null : onClear,
                    icon: Icon(Icons.close_rounded, color: cs.error),
                  ),
                ],
              ),
            ),
            if (!uploaded.isPdf) ...[
              const SizedBox(height: M3Spacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  width: double.infinity,
                  color: cs.surfaceContainerHighest,
                  child: Image.network(
                    uploaded.downloadUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: M3Spacing.sm),
          Text(
            strings.campaignMediaUrlFallback,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: M3Spacing.xs),
          TextField(
            controller: urlController,
            onChanged: (_) => onUrlChanged(),
            decoration: InputDecoration(
              labelText: isAr ? 'رابط بوستر العرض' : 'Media Poster URL',
              hintText: 'https://example.com/promotions/supermarket_offer.jpg',
              hintStyle: GoogleFonts.cairo(fontSize: 12),
              prefixIcon: const Icon(Icons.link_rounded, size: 20),
              suffixIcon: urlController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        urlController.clear();
                        onUrlChanged();
                      },
                    )
                  : null,
              filled: true,
              fillColor: cs.surfaceContainerLow,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            style: GoogleFonts.robotoMono(fontSize: 12),
          ),
          if (uploaded != null && pastedUrl.isNotEmpty) ...[
            const SizedBox(height: M3Spacing.xs),
            Text(
              strings.campaignMediaUploadedWins,
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (uploaded == null && pastedUrl.isNotEmpty) ...[
            const SizedBox(height: M3Spacing.sm),
            if (isWhatsAppPdfAttachment(mediaUrl: pastedUrl))
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.picture_as_pdf_rounded,
                      color: cs.onPrimaryContainer,
                    ),
                    const SizedBox(width: M3Spacing.xs),
                    Expanded(
                      child: Text(
                        strings.pdfAttachmentReady,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  width: double.infinity,
                  color: cs.surfaceContainerHighest,
                  child: Image.network(
                    pastedUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image_rounded,
                              size: 16,
                              color: cs.error,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                isAr
                                    ? 'تعذر تحميل المعاينة، يرجى التأكد من صحة الرابط'
                                    : 'Unable to preview image from URL',
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: cs.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: M3Spacing.xs),
          Text(
            isAr
                ? 'يُرسل الملف مع نص الرسالة'
                : 'The file is sent together with the message text',
            style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: M3Spacing.xxs),
          Text(
            strings.pdfAttachmentHint,
            style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
