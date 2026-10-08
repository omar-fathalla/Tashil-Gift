import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/localization/app_strings.dart';
import '../../domain/whatsapp_gateway_config_model.dart';
import '../../domain/whatsapp_gateway_service.dart';

/// Modal dialog displaying a live rendered screenshot of the WAHA WhatsApp Web session
class WhatsAppScreenshotDialog extends StatefulWidget {
  final WhatsAppGatewayConfigModel config;
  final AppStrings strings;
  final bool isAr;

  const WhatsAppScreenshotDialog({
    super.key,
    required this.config,
    required this.strings,
    required this.isAr,
  });

  @override
  State<WhatsAppScreenshotDialog> createState() => _WhatsAppScreenshotDialogState();
}

class _WhatsAppScreenshotDialogState extends State<WhatsAppScreenshotDialog> {
  final WhatsAppGatewayService _service = WhatsAppGatewayService();
  Uint8List? _screenshotBytes;
  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _capturedAt;

  @override
  void initState() {
    super.initState();
    _fetchScreenshot();
  }

  Future<void> _fetchScreenshot() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final bytes = await _service.fetchLiveScreenshot(config: widget.config);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (bytes != null && bytes.isNotEmpty) {
          _screenshotBytes = bytes;
          _capturedAt = DateTime.now();
        } else {
          _errorMessage = widget.isAr
              ? 'تعذر التقاط شاشة الواتساب الحية من السيرفر. تأكد من عمل السيرفر وصحة مفتاح API.'
              : 'Failed to capture live screenshot. Ensure the server is running and API key is valid.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: cs.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 40 : 16,
        vertical: isDesktop ? 32 : 24,
      ),
      child: Container(
        width: isDesktop ? 960 : double.infinity,
        height: isDesktop ? 680 : size.height * 0.85,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.screenshot_monitor_rounded, color: cs.onPrimaryContainer, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isAr ? 'شاشة واتساب الحية (Live Session)' : 'Live WhatsApp Web Screenshot',
                        style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface),
                      ),
                      Text(
                        _capturedAt != null
                            ? '${widget.isAr ? "آخر لقطة: " : "Captured at: "}${_capturedAt!.hour.toString().padLeft(2, '0')}:${_capturedAt!.minute.toString().padLeft(2, '0')}:${_capturedAt!.second.toString().padLeft(2, '0')}'
                            : (widget.isAr ? 'عرض مباشر لشاشة المتصفح الداخلية في السيرفر' : 'Direct view of internal server browser session'),
                        style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                // Refresh Button
                FilledButton.tonalIcon(
                  onPressed: _isLoading ? null : _fetchScreenshot,
                  icon: _isLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    widget.isAr ? 'تحديث الآن' : 'Refresh',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: widget.isAr ? 'إغلاق' : 'Close',
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Screenshot Content Body
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: Center(
                  child: _isLoading
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              widget.isAr ? 'جارٍ التقاط شاشة السيرفر الحية...' : 'Capturing live server screenshot...',
                              style: GoogleFonts.cairo(fontSize: 13, color: cs.onSurfaceVariant),
                            ),
                          ],
                        )
                      : _errorMessage != null
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
                                  const SizedBox(height: 14),
                                  Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(fontSize: 13, color: cs.error),
                                  ),
                                  const SizedBox(height: 18),
                                  FilledButton.tonalIcon(
                                    onPressed: _fetchScreenshot,
                                    icon: const Icon(Icons.refresh_rounded, size: 18),
                                    label: Text(widget.isAr ? 'إعادة المحاولة' : 'Retry'),
                                  ),
                                ],
                              ),
                            )
                          : _screenshotBytes != null
                              ? InteractiveViewer(
                                  maxScale: 4.0,
                                  minScale: 0.8,
                                  child: Image.memory(
                                    _screenshotBytes!,
                                    fit: BoxFit.contain,
                                  ),
                                )
                              : const SizedBox.shrink(),
                ),
              ),
            ),

            const SizedBox(height: 12),
            // Footer Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.zoom_in_rounded, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      widget.isAr
                          ? 'يمكنك التكبير والتحريك بالماوس أو اللمس لمعاينة كافة التفاصيل داخل الشاشة.'
                          : 'You can pinch or drag to zoom and pan the screenshot preview.',
                      style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                Text(
                  '${widget.isAr ? "الجلسة: " : "Session: "}${widget.config.instanceId}',
                  style: GoogleFonts.robotoMono(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
