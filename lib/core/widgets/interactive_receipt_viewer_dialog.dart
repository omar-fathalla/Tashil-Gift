import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// A high-performance, interactive dialog for previewing, inspecting, zooming,
/// and rotating receipt images across all desktop and mobile screens.
class InteractiveReceiptViewerDialog extends StatefulWidget {
  final String imageUrl;
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

  @override
  void initState() {
    super.initState();
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
    if (widget.imageUrl.startsWith('http')) {
      final uri = Uri.parse(widget.imageUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            color: const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
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
                        color: const Color(0xFF12121A),
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
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.touch_app_rounded, size: 14, color: Color(0xFF64B5F6)),
                            const SizedBox(width: 6),
                            Text(
                              isAr
                                  ? 'انقر مرتين للتكبير السريع • اسحب للتحريك'
                                  : 'Double tap to zoom • Drag to pan',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: Colors.white70,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF262638),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          // Receipt Icon Badge
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.white,
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
                          color: Colors.white,
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
                            child: const Icon(
                              Icons.copy_rounded,
                              size: 14,
                              color: Color(0xFF818CF8),
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
                      color: Colors.white60,
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
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '${widget.totalValue} ${widget.currencySymbol ?? (isAr ? 'ج.م' : 'EGP')}',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF34D399),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Delete Action if authorized
          if (widget.canDelete && widget.onDelete != null) ...[
            IconButton.filledTonal(
              icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Color(0xFFEF4444)),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onDelete!();
              },
              tooltip: isAr ? 'حذف الفاتورة' : 'Delete Invoice',
            ),
            const SizedBox(width: 8),
          ],

          // Close Button
          IconButton.filledTonal(
            icon: const Icon(Icons.close_rounded, size: 20, color: Colors.white70),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.08),
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
    final zoomPercent = (_currentScale * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
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
            icon: Icons.zoom_in_rounded,
            tooltip: isAr ? 'تكبير (Zoom In)' : 'Zoom In',
            onPressed: _zoomIn,
          ),

          const SizedBox(width: 4),

          // ── Zoom Out Button ──
          _buildToolbarButton(
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
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                '$zoomPercent%',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),
          Container(
            height: 20,
            width: 1,
            color: Colors.white.withValues(alpha: 0.15),
          ),
          const SizedBox(width: 6),

          // ── Reset Zoom / Fit Screen Button ──
          _buildToolbarButton(
            icon: Icons.fit_screen_rounded,
            tooltip: isAr ? 'إعادة ضبط الحجم الطبيعي' : 'Reset / Fit to Screen',
            onPressed: _resetZoom,
          ),

          const SizedBox(width: 4),

          // ── Rotate 90° Button ──
          _buildToolbarButton(
            icon: Icons.rotate_right_rounded,
            tooltip: isAr ? 'تدوير 90 درجة' : 'Rotate 90°',
            onPressed: _rotateClockwise,
          ),

          // ── Open In Browser Button ──
          if (widget.imageUrl.startsWith('http')) ...[
            const SizedBox(width: 4),
            _buildToolbarButton(
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
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          hoverColor: Colors.white.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              icon,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  /// Builds image with Base64, URL, Loading Progress, and Error Fallback support
  Widget _buildReceiptImage(ThemeData theme, bool isAr) {
    if (widget.imageUrl.isEmpty) {
      return _buildErrorState(isAr, 'لا توجد صورة مسجلة لهذه الفاتورة');
    }

    if (widget.imageUrl.startsWith('data:image')) {
      try {
        final bytes = base64Decode(widget.imageUrl.split(',').last);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (ctx, err, stackTrace) => _buildErrorState(isAr, 'تعذر معالجة بيانات الصورة'),
        );
      } catch (_) {
        return _buildErrorState(isAr, 'صيغة بيانات الصورة غير صحيحة');
      }
    }

    return Image.network(
      widget.imageUrl,
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
                  color: const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isAr ? 'جاري تحميل صورة الفاتورة...' : 'Loading receipt image...',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => _buildErrorState(
        isAr,
        'تعذر تحميل صورة الفاتورة الأصلية',
      ),
    );
  }

  Widget _buildErrorState(bool isAr, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_rounded,
              size: 56,
              color: Color(0xFFEF4444),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: GoogleFonts.cairo(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFEF4444),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              isAr
                ? 'قد يكون السبب قيود اتصال الشبكة أو انتهاء صلاحية الرابط'
                : 'Network issue or expired image link',
              style: GoogleFonts.cairo(fontSize: 12, color: Colors.white60),
              textAlign: TextAlign.center,
            ),
            if (widget.imageUrl.startsWith('http')) ...[
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
