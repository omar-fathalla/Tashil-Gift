import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/utils/arabic_numbers_utils.dart';
import '../../domain/whatsapp_gateway_config_model.dart';
import '../../domain/whatsapp_gateway_service.dart';
import 'whatsapp_screenshot_dialog.dart';

/// Modal dialog providing interactive WhatsApp QR Code scanning,
/// 8-character Pairing Code generation, and real-time session status monitoring
class WhatsAppQrPairingDialog extends StatefulWidget {
  final WhatsAppGatewayConfigModel config;
  final AppStrings strings;
  final bool isAr;
  final String? companySlug;
  final Function(WhatsAppGatewayConfigModel updatedConfig) onLinked;

  const WhatsAppQrPairingDialog({
    super.key,
    required this.config,
    required this.strings,
    required this.isAr,
    this.companySlug,
    required this.onLinked,
  });

  @override
  State<WhatsAppQrPairingDialog> createState() => _WhatsAppQrPairingDialogState();
}

class _WhatsAppQrPairingDialogState extends State<WhatsAppQrPairingDialog> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  final WhatsAppGatewayService _service = WhatsAppGatewayService();
  final TextEditingController _phoneController = TextEditingController();

  int _selectedTab = 0; // 0: QR Code, 1: Pairing Code
  Uint8List? _qrBytes;
  bool _isLoadingQr = true;
  String? _qrError;

  // Pairing code state
  String? _pairingCode;
  bool _isRequestingCode = false;
  String? _pairingError;

  // Session monitor state
  Timer? _pollingTimer;
  String _sessionStatus = 'UNKNOWN'; // SCAN_QR_CODE, WORKING, STARTING, FAILED, STOPPED
  String? _connectedPhone;
  String? _connectedPushName;
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    _fetchQrCode();
    _startSessionPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  void _startSessionPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      _pollSessionStatus();
    });
  }

  Future<void> _pollSessionStatus() async {
    if (!mounted) return;
    try {
      final details = await _service.fetchSessionDetails(widget.config);
      if (!mounted || details == null) return;

      final status = details['status']?.toString().toUpperCase() ?? 'UNKNOWN';
      final me = details['me'] as Map<String, dynamic>?;
      final rawPhone = me?['id']?.toString().replaceAll('@c.us', '') ?? '';
      final pushName = me?['pushName']?.toString() ?? '';

      setState(() {
        _sessionStatus = status;
        if (rawPhone.isNotEmpty) {
          _connectedPhone = '+$rawPhone';
          _connectedPushName = pushName;
        }
      });

      // If status changed to WORKING, user just scanned!
      if (status == 'WORKING' && rawPhone.isNotEmpty) {
        _pollingTimer?.cancel();
        _onPairingSuccess(rawPhone, pushName);
      } else if (status == 'SCAN_QR_CODE' && _qrBytes == null && !_isLoadingQr) {
        // Automatically fetch QR if we don't have it yet
        _fetchQrCode();
      }
    } catch (e) {
      debugPrint('Error polling WAHA session status: $e');
    }
  }

  Future<void> _onPairingSuccess(String rawPhone, String pushName) async {
    final displayPhone = '+$rawPhone${pushName.isNotEmpty ? " ($pushName)" : ""}';
    final updatedConfig = widget.config.copyWith(
      isConnected: true,
      isEnabled: true,
      connectedPhoneNumber: displayPhone,
      lastTestedAt: DateTime.now(),
    );

    // Persist configuration
    await _service.saveConfig(updatedConfig, companySlug: widget.companySlug);
    widget.onLinked(updatedConfig);
  }

  Future<void> _fetchQrCode() async {
    if (!mounted) return;
    setState(() {
      _isLoadingQr = true;
      _qrError = null;
    });

    try {
      final bytes = await _service.fetchQrCode(widget.config);
      if (!mounted) return;

      if (bytes != null && bytes.isNotEmpty) {
        setState(() {
          _qrBytes = bytes;
          _isLoadingQr = false;
        });
      } else {
        // Check session details to know why QR is not available
        final details = await _service.fetchSessionDetails(widget.config);
        final status = details?['status']?.toString().toUpperCase() ?? '';

        setState(() {
          _isLoadingQr = false;
          _sessionStatus = status.isNotEmpty ? status : _sessionStatus;
          if (status == 'WORKING') {
            _qrError = widget.isAr
                ? 'الجلسة متصلة بالفعل برقم هاتف!'
                : 'Session is already connected to a phone!';
          } else if (status == 'FAILED') {
            _qrError = widget.isAr
                ? 'الجلسة معطلة حالياً. اضغط "إعادة تشغيل الجلسة" لتنشيطها وتوليد كود الـ QR.'
                : 'Session failed. Click "Restart Session" to re-initialize and generate QR.';
          } else if (status == 'STARTING') {
            _qrError = widget.isAr
                ? 'جارٍ تشغيل محرك الواتساب بالسيرفر، انتظر ثوانٍ معدودة...'
                : 'WhatsApp engine is starting on server, please wait a moment...';
          } else {
            _qrError = widget.isAr
                ? 'تعذر تحميل رمز QR من السيرفر. تأكد من عمل السيرفر وصحة المفتاح.'
                : 'Failed to load QR code. Ensure the server is online and API key is valid.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingQr = false;
          _qrError = widget.isAr ? 'خطأ في الاتصال بالسيرفر: $e' : 'Connection error: $e';
        });
      }
    }
  }

  Future<void> _requestPairingCode() async {
    final rawPhone = _phoneController.text.toEnglishDigits().trim();
    if (rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isAr ? 'يرجى إدخال رقم الهاتف أولاً' : 'Please enter a phone number',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() {
      _isRequestingCode = true;
      _pairingError = null;
    });

    final code = await _service.requestPairingCode(
      config: widget.config,
      phoneNumber: rawPhone,
    );

    if (mounted) {
      setState(() {
        _isRequestingCode = false;
        if (code != null && code.isNotEmpty) {
          _pairingCode = code;
        } else {
          _pairingError = widget.isAr
              ? 'تعذر إصدار كود الاقتران. تأكد من أن الجلسة بحالة جاهزية المسح (SCAN_QR_CODE) وأن الرقم صحيح بالصيغة الدولية.'
              : 'Failed to request pairing code. Ensure the session is in SCAN_QR_CODE state and phone is valid.';
        }
      });
    }
  }

  Future<void> _restartSession() async {
    setState(() => _isActionInProgress = true);
    final success = await _service.restartInstance(widget.config);
    if (!mounted) return;

    setState(() => _isActionInProgress = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (widget.isAr ? 'تم إرسال أمر إعادة تشغيل الجلسة بنجاح' : 'Session restart triggered successfully')
              : (widget.isAr ? 'تعذر إعادة تشغيل الجلسة' : 'Failed to restart session'),
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        backgroundColor: success ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
      ),
    );

    if (success) {
      // Wait 3 seconds for server engine initialization then fetch QR
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        _fetchQrCode();
      }
    }
  }

  Future<void> _logoutSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 10),
            Text(
              widget.strings.unlinkConfirmTitle,
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          widget.strings.unlinkConfirmDesc,
          style: GoogleFonts.cairo(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(widget.isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(widget.isAr ? 'تأكيد فك الارتباط' : 'Confirm Unlink', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActionInProgress = true);
    final success = await _service.logoutInstance(widget.config);
    if (!mounted) return;

    setState(() => _isActionInProgress = false);
    if (success) {
      final updatedConfig = widget.config.copyWith(
        isConnected: false,
        connectedPhoneNumber: null,
      );
      await _service.saveConfig(updatedConfig, companySlug: widget.companySlug);
      widget.onLinked(updatedConfig);

      setState(() {
        _connectedPhone = null;
        _connectedPushName = null;
        _sessionStatus = 'SCAN_QR_CODE';
        _qrBytes = null;
      });

      // Re-trigger restart to spin up fresh QR session
      await _restartSession();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isAr ? 'تعذر تسجيل الخروج من السيرفر' : 'Failed to logout session on server',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Color _getStatusColor(ColorScheme cs) {
    switch (_sessionStatus) {
      case 'WORKING':
        return colorScheme.tertiary;
      case 'SCAN_QR_CODE':
        return cs.primary;
      case 'STARTING':
        return colorScheme.secondary;
      case 'FAILED':
      case 'STOPPED':
        return cs.error;
      default:
        return cs.outline;
    }
  }

  String _getStatusText() {
    switch (_sessionStatus) {
      case 'WORKING':
        return widget.strings.sessionStatusWorking;
      case 'SCAN_QR_CODE':
        return widget.strings.sessionStatusScanQr;
      case 'STARTING':
        return widget.strings.sessionStatusStarting;
      case 'FAILED':
        return widget.strings.sessionStatusFailed;
      case 'STOPPED':
        return widget.isAr ? 'الجلسة متوقفة' : 'Session stopped';
      default:
        return _sessionStatus;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 750;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: cs.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 36 : 16,
        vertical: isDesktop ? 24 : 16,
      ),
      child: Container(
        width: isDesktop ? 780 : double.infinity,
        constraints: BoxConstraints(maxHeight: size.height * 0.90),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header Bar
            _buildHeader(cs),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // 2. Status Banner
            _buildStatusBanner(cs),
            const SizedBox(height: 14),

            // 3. Tab Segment (QR vs Pairing Code)
            if (_sessionStatus != 'WORKING') ...[
              SegmentedButton<int>(
                segments: [
                  ButtonSegment<int>(
                    value: 0,
                    icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                    label: Text(widget.strings.scanQrTab, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: const Icon(Icons.pin_rounded, size: 18),
                    label: Text(widget.strings.pairingCodeTab, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (newSelection) {
                  setState(() => _selectedTab = newSelection.first);
                },
              ),
              const SizedBox(height: 16),
            ],

            // 4. Main Dynamic Body
            Flexible(
              child: SingleChildScrollView(
                child: _sessionStatus == 'WORKING'
                    ? _buildWorkingSuccessCard(cs)
                    : (_selectedTab == 0 ? _buildQrTabContent(cs) : _buildPairingCodeTabContent(cs)),
              ),
            ),

            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // 5. Action Footer
            _buildFooterActions(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.tertiary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.qr_code_scanner_rounded, color: colorScheme.tertiary, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.strings.qrPairingTitle,
                style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface),
              ),
              Text(
                widget.strings.qrPairingSubtitle,
                style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hub_rounded, size: 13, color: cs.primary),
              const SizedBox(width: 5),
              Text(
                widget.config.instanceId.isNotEmpty ? widget.config.instanceId : 'default',
                style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onSurface),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          tooltip: widget.isAr ? 'إغلاق' : 'Close',
        ),
      ],
    );
  }

  Widget _buildStatusBanner(ColorScheme cs) {
    final statusColor = _getStatusColor(cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _getStatusText(),
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
          if (_sessionStatus == 'STARTING')
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildWorkingSuccessCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.tertiary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.tertiary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            widget.strings.pairingSuccessTitle,
            style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onTertiaryFixedVariant),
          ),
          const SizedBox(height: 6),
          Text(
            widget.isAr
                ? 'تم ربط رقم الواتساب الخاص بك بنجاح وجاهز لبدء حملات الإرسال الآلي فوراً.'
                : 'Your WhatsApp number is connected and ready for automated campaign dispatching.',
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.phone_iphone_rounded, color: colorScheme.tertiary, size: 22),
                const SizedBox(width: 10),
                Text(
                  _connectedPhone ?? widget.config.connectedPhoneNumber ?? 'WhatsApp Connected',
                  style: GoogleFonts.robotoMono(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface),
                ),
                if (_connectedPushName != null && _connectedPushName!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '($_connectedPushName)',
                    style: GoogleFonts.cairo(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.onTertiaryFixedVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: Text(
                  widget.isAr ? 'تم وحفظ الاتصال' : 'Done & Save',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.error,
                  side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: _isActionInProgress ? null : _logoutSession,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text(
                  widget.strings.unlinkAndChangeNumber,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQrTabContent(ColorScheme cs) {
    return Column(
      children: [
        // QR Container
        Container(
          width: 280,
          height: 280,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _isLoadingQr
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text(
                      widget.isAr ? 'جارٍ جلب رمز الـ QR...' : 'Fetching QR code...',
                      style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                )
              : _qrError != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, color: cs.error, size: 40),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            _qrError!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.cairo(fontSize: 11, color: cs.error),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _fetchQrCode,
                          child: Text(widget.isAr ? 'إعادة المحاولة' : 'Retry', style: GoogleFonts.cairo(fontSize: 11)),
                        ),
                      ],
                    )
                  : _qrBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: InteractiveViewer(
                            child: Image.memory(
                              _qrBytes!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
        ),

        const SizedBox(height: 16),

        // Steps instructions card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isAr ? 'طريقة الربط عبر مسح الكود:' : 'How to link with QR code:',
                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface),
              ),
              const SizedBox(height: 8),
              _buildStepItem(
                number: '1',
                text: widget.isAr
                    ? 'افتح تطبيق واتساب على هاتفك (الرقم الذي ترغب في استخدامه).'
                    : 'Open WhatsApp on your phone (the number you want to use).',
                cs: cs,
              ),
              const SizedBox(height: 6),
              _buildStepItem(
                number: '2',
                text: widget.isAr
                    ? 'اضغط على خيارات (⋮) أو الإعدادات > الأجهزة المرتبطة (Linked Devices).'
                    : 'Tap Menu (⋮) or Settings > Linked Devices.',
                cs: cs,
              ),
              const SizedBox(height: 6),
              _buildStepItem(
                number: '3',
                text: widget.isAr
                    ? 'اضغط على "ربط جهاز" ووجّه كاميرا الهاتف نحو الرمز الموضح بالأعلى.'
                    : 'Tap "Link a Device" and point your camera at the QR code above.',
                cs: cs,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepItem({required String number, required String text, required ColorScheme cs}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildPairingCodeTabContent(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.strings.enterPhoneToGetCode,
                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.robotoMono(fontSize: 15, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: '01012345678 / +201211857725',
                  prefixIcon: const Icon(Icons.phone_rounded),
                  filled: true,
                  fillColor: cs.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: _isRequestingCode ? null : _requestPairingCode,
                icon: _isRequestingCode
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.vpn_key_rounded, size: 18),
                label: Text(
                  widget.strings.requestPairingCodeBtn,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        if (_pairingError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pairingError!,
                    style: GoogleFonts.cairo(fontSize: 11, color: cs.error),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_pairingCode != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.primary, width: 1.5),
            ),
            child: Column(
              children: [
                Text(
                  widget.strings.enterPairingCodeInWhatsApp,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _pairingCode!,
                        style: GoogleFonts.robotoMono(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded),
                        tooltip: widget.isAr ? 'نسخ الكود' : 'Copy code',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _pairingCode!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                widget.isAr ? 'تم نسخ كود الاقتران للحافظة' : 'Code copied to clipboard',
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.isAr
                      ? 'الخطوات: افتح واتساب > الأجهزة المرتبطة > ربط جهاز > الربط برقم الهاتف بدلاً من ذلك، ثم أدخل هذا الكود.'
                      : 'Steps: WhatsApp > Linked Devices > Link a Device > Link with phone number instead, then enter this code.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFooterActions(ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            // Restart Session
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: _isActionInProgress ? null : _restartSession,
              icon: _isActionInProgress
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.restart_alt_rounded, size: 16),
              label: Text(
                widget.strings.restartSessionBtn,
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            // Live Screenshot
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => WhatsAppScreenshotDialog(
                    config: widget.config,
                    strings: widget.strings,
                    isAr: widget.isAr,
                  ),
                );
              },
              icon: const Icon(Icons.screenshot_monitor_rounded, size: 16),
              label: Text(
                widget.strings.liveScreenshotBtn,
                style: GoogleFonts.cairo(fontSize: 12),
              ),
            ),
          ],
        ),

        // Refresh QR button
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: _isLoadingQr ? null : _fetchQrCode,
          icon: _isLoadingQr
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded, size: 16),
          label: Text(
            widget.isAr ? 'تحديث الكود' : 'Refresh QR',
            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
