import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../utils/file_download_helper.dart';

/// A high-performance, interactive dialog for previewing, inspecting, zooming,
/// and rotating receipt images across all desktop and mobile screens.
class InteractiveReceiptViewerDialog extends StatefulWidget {
  final String imageUrl;
  final List<String>? imageUrls;
  final int initialIndex;
  final String? receiptNumber;
  final String? storeName;
  final String? branchName;
  final dynamic totalValue;
  final String? date;
  final String? currencySymbol;
  final String? docId;
  final String? storagePath;
  final bool canDelete;
  final VoidCallback? onDelete;

  const InteractiveReceiptViewerDialog({
    super.key,
    required this.imageUrl,
    this.imageUrls,
    this.initialIndex = 0,
    this.receiptNumber,
    this.storeName,
    this.branchName,
    this.totalValue,
    this.date,
    this.currencySymbol,
    this.docId,
    this.storagePath,
    this.canDelete = false,
    this.onDelete,
  });

  /// Convenient helper to display the interactive viewer modal dialog
  static Future<void> show(
    BuildContext context, {
    required String imageUrl,
    List<String>? imageUrls,
    int initialIndex = 0,
    String? receiptNumber,
    String? storeName,
    String? branchName,
    dynamic totalValue,
    String? date,
    String? currencySymbol,
    String? docId,
    String? storagePath,
    bool canDelete = false,
    VoidCallback? onDelete,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => InteractiveReceiptViewerDialog(
        imageUrl: imageUrl,
        imageUrls: imageUrls,
        initialIndex: initialIndex,
        receiptNumber: receiptNumber,
        storeName: storeName,
        branchName: branchName,
        totalValue: totalValue,
        date: date,
        currencySymbol: currencySymbol,
        docId: docId,
        storagePath: storagePath,
        canDelete: canDelete,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<InteractiveReceiptViewerDialog> createState() =>
      _InteractiveReceiptViewerDialogState();
}

class _InteractiveReceiptViewerDialogState
    extends State<InteractiveReceiptViewerDialog> {
  late final TransformationController _transformationController;
  int _quarterTurns = 0;
  double _currentScale = 1.0;
  TapDownDetails? _doubleTapDetails;
  late int _currentPartIndex;
  bool _isDownloading = false;

  List<String> get _activeUrls {
    if (widget.imageUrls != null && widget.imageUrls!.isNotEmpty) {
      return widget.imageUrls!;
    }
    return [widget.imageUrl];
  }

  String get _currentImageUrl {
    final urls = _activeUrls;
    if (_currentPartIndex >= 0 && _currentPartIndex < urls.length) {
      return urls[_currentPartIndex];
    }
    return widget.imageUrl;
  }

  @override
  void initState() {
    super.initState();
    _currentPartIndex = widget.initialIndex.clamp(
      0,
      (widget.imageUrls?.length ?? 1) > 0 ? (widget.imageUrls?.length ?? 1) - 1 : 0,
    );
    _transformationController = TransformationController();
    _transformationController.addListener(_onTransformationChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if ((scale - _currentScale).abs() > 0.02) {
      setState(() {
        _currentScale = scale;
      });
    }
  }

  void _zoomIn() {
    final currentMatrix = _transformationController.value;
    final newScale = (_currentScale * 1.35).clamp(0.5, 8.0);
    final factor = newScale / _currentScale;
    
    final newMatrix = Matrix4.copy(currentMatrix)
      ..multiply(Matrix4.diagonal3Values(factor, factor, 1.0));
    _transformationController.value = newMatrix;
  }

  void _zoomOut() {
    final currentMatrix = _transformationController.value;
    final newScale = (_currentScale / 1.35).clamp(0.5, 8.0);
    final factor = newScale / _currentScale;
    
    final newMatrix = Matrix4.copy(currentMatrix)
      ..multiply(Matrix4.diagonal3Values(factor, factor, 1.0));
    _transformationController.value = newMatrix;
  }

  void _resetZoom() {
    setState(() {
      _transformationController.value = Matrix4.identity();
      _currentScale = 1.0;
    });
  }

  void _rotateClockwise() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
    });
  }

  void _handleDoubleTap() {
    if (_currentScale > 1.25) {
      _resetZoom();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      const newScale = 2.5;
      
      final x = -position.dx * (newScale - 1);
      final y = -position.dy * (newScale - 1);
      
      final zoomed = Matrix4.translationValues(x, y, 0.0)
        ..multiply(Matrix4.diagonal3Values(newScale, newScale, 1.0));
      
      _transformationController.value = zoomed;
    }
  }

  void _copyReceiptNumber(BuildContext context) {
    if (widget.receiptNumber != null && widget.receiptNumber!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: widget.receiptNumber!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم نسخ رقم الفاتورة: #${widget.receiptNumber}',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openImageInBrowser() async {
    if (_currentImageUrl.startsWith('http')) {
      final uri = Uri.parse(_currentImageUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  /// Downloads and saves the receipt image to the user's device or computer
  Future<void> _downloadImage(BuildContext context, bool isAr) async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
    });

    try {
      final rawNumber = widget.receiptNumber?.trim() ?? '';
      final safeReceiptNo = rawNumber.isNotEmpty
          ? rawNumber.replaceAll(RegExp(r'[^\w\-]'), '_')
          : 'receipt_${DateTime.now().millisecondsSinceEpoch}';
      final partSuffix = _activeUrls.length > 1 ? '_part${_currentPartIndex + 1}' : '';

      List<int>? imageBytes;
      String ext = 'jpg';
      String mimeType = 'image/jpeg';

      if (_currentImageUrl.startsWith('data:image')) {
        final parts = _currentImageUrl.split(',');
        final header = parts.first;
        final data = parts.last;
        imageBytes = base64Decode(data);
        if (header.contains('png')) {
          ext = 'png';
          mimeType = 'image/png';
        } else if (header.contains('webp')) {
          ext = 'webp';
          mimeType = 'image/webp';
        } else {
          ext = 'jpg';
          mimeType = 'image/jpeg';
        }
      } else if (_currentImageUrl.startsWith('http')) {
        try {
          final response = await http.get(Uri.parse(_currentImageUrl));
          if (response.statusCode == 200) {
            imageBytes = response.bodyBytes;
            final ct = (response.headers['content-type'] ?? '').toLowerCase();
            if (ct.contains('png')) {
              ext = 'png';
              mimeType = 'image/png';
            } else if (ct.contains('webp')) {
              ext = 'webp';
              mimeType = 'image/webp';
            } else {
              final uriPath = Uri.parse(_currentImageUrl).path.toLowerCase();
              if (uriPath.endsWith('.png')) {
                ext = 'png';
                mimeType = 'image/png';
              } else if (uriPath.endsWith('.webp')) {
                ext = 'webp';
                mimeType = 'image/webp';
              }
            }
          }
        } catch (_) {
          // Fall through to fallback
        }
      }

      final fileName = '$safeReceiptNo$partSuffix.$ext';

      if (imageBytes != null && imageBytes.isNotEmpty) {
        downloadFileBytes(
          bytes: imageBytes,
          fileName: fileName,
          mimeType: mimeType,
        );

        if (context.mounted) {
          final cs = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: cs.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: cs.onPrimary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isAr ? 'تم تحميل الفاتورة بنجاح: $fileName' : 'Invoice downloaded successfully: $fileName',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: cs.onPrimary),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        await _openImageInBrowser();
        if (context.mounted) {
          final cs = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: cs.secondary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Row(
                children: [
                  Icon(Icons.open_in_new_rounded, color: cs.onSecondary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isAr ? 'تم فتح صورة الفاتورة في نافذة جديدة لحفظها' : 'Receipt opened in a new tab to save',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: cs.onSecondary),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        final cs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: cs.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(
              isAr ? 'تعذر تحميل الفاتورة، يرجى المحاولة مرة أخرى' : 'Failed to download receipt, please try again',
              style: GoogleFonts.cairo(color: cs.onError),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 768;

    final hasStore = widget.storeName != null && widget.storeName!.isNotEmpty;
    final hasBranch = widget.branchName != null && widget.branchName!.isNotEmpty;
    final storeDisplay = hasStore
        ? (hasBranch ? '${widget.storeName} • ${widget.branchName}' : widget.storeName!)
        : (widget.branchName ?? '');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 24,
        vertical: isMobile ? 12 : 24,
      ),
      child: Center(
        child: Container(
          width: isMobile ? double.infinity : 860,
          height: isMobile ? screenSize.height * 0.92 : 820,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.outlineVariant,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.4),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // ── 1. Top Header Bar ──
              _buildHeader(theme, isAr, storeDisplay),

              // ── 2. Interactive Image Viewport ──
              Expanded(
                child: Stack(
                  children: [
                    // Viewport Container
                    Positioned.fill(
                      child: Container(
                        color: colorScheme.surfaceContainerLowest,
                        child: GestureDetector(
                          onDoubleTapDown: (details) => _doubleTapDetails = details,
                          onDoubleTap: _handleDoubleTap,
                          child: InteractiveViewer(
                            transformationController: _transformationController,
                            panEnabled: true,
                            scaleEnabled: true,
                            trackpadScrollCausesScale: true,
                            boundaryMargin: const EdgeInsets.all(250),
                            minScale: 0.3,
                            maxScale: 8.0,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: RotatedBox(
                                  quarterTurns: _quarterTurns,
                                  child: _buildReceiptImage(theme, isAr),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Top Right / Left Helper Hint
                    Positioned(
                      top: 14,
                      left: isAr ? 14 : null,
                      right: isAr ? null : 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.touch_app_rounded, size: 14, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              isAr
                                  ? 'انقر مرتين للتكبير السريع • اسحب للتحريك'
                                  : 'Double tap to zoom • Drag to pan',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Floating Zoom & Tool Controls Bar ──
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _buildControlsToolbar(theme, isAr),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Top Header Bar with Receipt Meta, Price & Actions
  Widget _buildHeader(ThemeData theme, bool isAr, String storeDisplay) {
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          // Receipt Icon Badge
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),

          // Receipt Title & Subtitle Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.receiptNumber != null && widget.receiptNumber!.isNotEmpty
                            ? (widget.receiptNumber!.startsWith('#')
                                ? widget.receiptNumber!
                                : '#${widget.receiptNumber}')
                            : (isAr ? 'معاينة وتدقيق الفاتورة' : 'Receipt Preview & Audit'),
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.receiptNumber != null && widget.receiptNumber!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _copyReceiptNumber(context),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Tooltip(
                            message: isAr ? 'نسخ رقم الفاتورة' : 'Copy Receipt Number',
                            child: Icon(
                              Icons.copy_rounded,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (storeDisplay.isNotEmpty || widget.date != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (storeDisplay.isNotEmpty) storeDisplay,
                      if (widget.date != null && widget.date!.isNotEmpty) widget.date!,
                    ].join(' • '),
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Total Price Pill if present
          if (widget.totalValue != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                '${widget.totalValue} ${widget.currencySymbol ?? (isAr ? 'ج.م' : 'EGP')}',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Delete Action if authorized
          if (widget.canDelete && widget.onDelete != null) ...[
            IconButton.filledTonal(
              icon: Icon(Icons.delete_outline_rounded, size: 19, color: colorScheme.onErrorContainer),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.errorContainer,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onDelete!();
              },
              tooltip: isAr ? 'حذف الفاتورة' : 'Delete Invoice',
            ),
            const SizedBox(width: 8),
          ],

          // Download / Save Action
          IconButton.filledTonal(
            icon: _isDownloading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  )
                : Icon(
                    Icons.download_rounded,
                    size: 20,
                    color: colorScheme.onPrimaryContainer,
                  ),
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.primaryContainer,
            ),
            onPressed: _isDownloading ? null : () => _downloadImage(context, isAr),
            tooltip: isAr ? 'تحميل وحفظ الفاتورة على الجهاز' : 'Download and Save Invoice',
          ),
          const SizedBox(width: 8),

          // Close Button
          IconButton.filledTonal(
            icon: Icon(Icons.close_rounded, size: 20, color: colorScheme.onSurfaceVariant),
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: isAr ? 'إغلاق المعاينة' : 'Close Preview',
          ),
        ],
      ),
    );
  }

  /// Floating Glassmorphic Toolbar with Zoom, Pan, Rotate, and Fullscreen Controls
  Widget _buildControlsToolbar(ThemeData theme, bool isAr) {
    final colorScheme = theme.colorScheme;
    final zoomPercent = (_currentScale * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: colorScheme.outlineVariant,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Zoom In Button ──
          _buildToolbarButton(
            colorScheme: colorScheme,
            icon: Icons.zoom_in_rounded,
            tooltip: isAr ? 'تكبير (Zoom In)' : 'Zoom In',
            onPressed: _zoomIn,
          ),

          const SizedBox(width: 4),

          // ── Zoom Out Button ──
          _buildToolbarButton(
            colorScheme: colorScheme,
            icon: Icons.zoom_out_rounded,
            tooltip: isAr ? 'تصغير (Zoom Out)' : 'Zoom Out',
            onPressed: _zoomOut,
          ),

          const SizedBox(width: 4),

          // ── Live Zoom Percentage Badge ──
          InkWell(
            onTap: _resetZoom,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                '$zoomPercent%',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),
          Container(
            height: 20,
            width: 1,
            color: colorScheme.outlineVariant,
          ),
          const SizedBox(width: 6),

          // ── Reset Zoom / Fit Screen Button ──
          _buildToolbarButton(
            colorScheme: colorScheme,
            icon: Icons.fit_screen_rounded,
            tooltip: isAr ? 'إعادة ضبط الحجم الطبيعي' : 'Reset / Fit to Screen',
            onPressed: _resetZoom,
          ),

          const SizedBox(width: 4),

          // ── Rotate 90° Button ──
          _buildToolbarButton(
            colorScheme: colorScheme,
            icon: Icons.rotate_right_rounded,
            tooltip: isAr ? 'تدوير 90 درجة' : 'Rotate 90°',
            onPressed: _rotateClockwise,
          ),

          // ── Multi-Part Navigation (if receipt has multiple parts) ──
          if (_activeUrls.length > 1) ...[
            const SizedBox(width: 6),
            Container(
              height: 20,
              width: 1,
              color: colorScheme.outlineVariant,
            ),
            const SizedBox(width: 4),
            _buildToolbarButton(
              colorScheme: colorScheme,
              icon: isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
              tooltip: isAr ? 'الجزء السابق' : 'Previous Part',
              onPressed: _currentPartIndex > 0
                  ? () => setState(() {
                        _currentPartIndex--;
                        _resetZoom();
                      })
                  : () {},
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                isAr
                    ? 'جزء ${_currentPartIndex + 1} من ${_activeUrls.length}'
                    : 'Part ${_currentPartIndex + 1}/${_activeUrls.length}',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            _buildToolbarButton(
              colorScheme: colorScheme,
              icon: isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              tooltip: isAr ? 'الجزء التالي' : 'Next Part',
              onPressed: _currentPartIndex < _activeUrls.length - 1
                  ? () => setState(() {
                        _currentPartIndex++;
                        _resetZoom();
                      })
                  : () {},
            ),
          ],

          const SizedBox(width: 6),
          Container(
            height: 20,
            width: 1,
            color: colorScheme.outlineVariant,
          ),
          const SizedBox(width: 6),

          // ── Download Button ──
          _buildToolbarButton(
            colorScheme: colorScheme,
            icon: Icons.download_rounded,
            tooltip: isAr ? 'تحميل وحفظ الفاتورة على جهازك' : 'Download and Save Invoice',
            isLoading: _isDownloading,
            iconColor: colorScheme.primary,
            onPressed: () => _downloadImage(context, isAr),
          ),

          // ── Open In Browser Button ──
          if (_currentImageUrl.startsWith('http')) ...[
            const SizedBox(width: 4),
            _buildToolbarButton(
              colorScheme: colorScheme,
              icon: Icons.open_in_new_rounded,
              tooltip: isAr ? 'فتح الصورة بالدقة الكاملة في المتصفح' : 'Open Full Resolution in Browser',
              onPressed: _openImageInBrowser,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required ColorScheme colorScheme,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? iconColor,
    bool isLoading = false,
  }) {
    final fg = iconColor ?? colorScheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(20),
          hoverColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                    ),
                  )
                : Icon(
                    icon,
                    size: 20,
                    color: fg,
                  ),
          ),
        ),
      ),
    );
  }

  /// Builds image with Base64, URL, Loading Progress, and Error Fallback support
  Widget _buildReceiptImage(ThemeData theme, bool isAr) {
    final colorScheme = theme.colorScheme;
    if (_currentImageUrl.isEmpty) {
      return _buildErrorState(colorScheme, isAr, 'لا توجد صورة مسجلة لهذه الفاتورة');
    }

    if (_currentImageUrl.startsWith('data:image')) {
      try {
        final bytes = base64Decode(_currentImageUrl.split(',').last);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (ctx, err, stackTrace) => _buildErrorState(colorScheme, isAr, 'تعذر معالجة بيانات الصورة'),
        );
      } catch (_) {
        return _buildErrorState(colorScheme, isAr, 'صيغة بيانات الصورة غير صحيحة');
      }
    }

    return Image.network(
      _currentImageUrl,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        final total = loadingProgress.expectedTotalBytes;
        final loaded = loadingProgress.cumulativeBytesLoaded;
        final value = total != null && total > 0 ? loaded / total : null;

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 3,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isAr ? 'جاري تحميل صورة الفاتورة...' : 'Loading receipt image...',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => _buildErrorState(
        colorScheme,
        isAr,
        'تعذر تحميل صورة الفاتورة الأصلية',
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme, bool isAr, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_rounded,
              size: 56,
              color: colorScheme.error,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: GoogleFonts.cairo(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              isAr
                ? 'قد يكون السبب قيود اتصال الشبكة أو انتهاء صلاحية الرابط'
                : 'Network issue or expired image link',
              style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (_currentImageUrl.startsWith('http')) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _openImageInBrowser,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(
                  isAr ? 'فتح الرابط مباشرة في المتصفح' : 'Open directly in browser',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
