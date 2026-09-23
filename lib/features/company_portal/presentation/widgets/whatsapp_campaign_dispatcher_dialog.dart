import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../domain/whatsapp_gateway_config_model.dart';
import '../../domain/whatsapp_gateway_service.dart';
import 'whatsapp_gateway_settings_dialog.dart';

/// Contact model representing a customer targeted for WhatsApp/SMS campaigns
class CustomerCampaignContact {
  final String id;
  final String name;
  final String rawPhone;
  final String cleanPhone;
  final double totalSpend;
  final int totalInvoices;
  final List<String> prizesWon;
  final List<String> branches;
  final String lastBranch;
  final DateTime? lastVisitDate;
  final String? sourceTag;
  ContactDispatchStatus status;
  bool? isWhatsAppActive;

  CustomerCampaignContact({
    required this.id,
    required this.name,
    required this.rawPhone,
    required this.cleanPhone,
    required this.totalSpend,
    required this.totalInvoices,
    required this.prizesWon,
    required this.branches,
    required this.lastBranch,
    this.lastVisitDate,
    this.sourceTag,
    this.status = ContactDispatchStatus.pending,
    this.isWhatsAppActive,
  });

  bool get isWinner => prizesWon.isNotEmpty;
  bool get isRepeat => totalInvoices >= 2;
}

enum ContactDispatchStatus {
  pending,
  sent,
  failed,
  skipped,
}

enum DispatchMode {
  automatedGateway,
  manualBrowser,
}

/// Interactive Dual-Mode WhatsApp Campaign Dispatcher Modal
/// Supports:
/// 1. 100% Automated Background Dispatch via WhatsApp Gateway REST API with Anti-Spam pacing
/// 2. Sequential Step-by-Step Manual Browser Launch via wa.me deep links
class WhatsappCampaignDispatcherDialog extends StatefulWidget {
  final List<CustomerCampaignContact> contacts;
  final String messageTemplate;
  final String companyName;
  final String campaignName;
  final String? companySlug;
  final AppStrings strings;
  final bool isAr;
  final String? attachedMediaUrl;
  final String? pollTitle;
  final List<String>? pollOptions;
  final bool multiplePollAnswers;

  const WhatsappCampaignDispatcherDialog({
    super.key,
    required this.contacts,
    required this.messageTemplate,
    required this.companyName,
    required this.campaignName,
    this.companySlug,
    required this.strings,
    required this.isAr,
    this.attachedMediaUrl,
    this.pollTitle,
    this.pollOptions,
    this.multiplePollAnswers = false,
  });

  /// Formats phone number for WhatsApp international standard (e.g. 2010... or country code)
  static String formatPhoneForWhatsApp(String phone) {
    return WhatsAppGatewayService.formatInternationalPhone(phone);
  }

  @override
  State<WhatsappCampaignDispatcherDialog> createState() => _WhatsappCampaignDispatcherDialogState();
}

class _WhatsappCampaignDispatcherDialogState extends State<WhatsappCampaignDispatcherDialog> {
  final _gatewayService = WhatsAppGatewayService();
  WhatsAppGatewayConfigModel _gatewayConfig = const WhatsAppGatewayConfigModel();
  bool _isLoadingConfig = true;

  // Active Mode
  DispatchMode _selectedMode = DispatchMode.automatedGateway;

  // Manual Sequential Mode State
  int _manualIndex = 0;
  bool _autoAdvance = true;
  Timer? _autoAdvanceTimer;
  int _countdownSeconds = 0;

  // Automated Gateway Mode State
  bool _isAutoDispatching = false;
  bool _isAutoPaused = false;
  bool _isAutoCancelled = false;
  int _autoProcessedCount = 0;
  String _currentAutoStatus = '';
  final List<_DispatchLogItem> _dispatchLogs = [];
  final ScrollController _logsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadGatewayConfig();
  }

  Future<void> _loadGatewayConfig() async {
    final config = await _gatewayService.loadConfig(companySlug: widget.companySlug);
    if (mounted) {
      setState(() {
        _gatewayConfig = config;
        _isLoadingConfig = false;
        // Default to manual if gateway is not configured
        if (!config.isConfigured) {
          _selectedMode = DispatchMode.manualBrowser;
        }
      });
    }
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _isAutoCancelled = true;
    _logsScrollController.dispose();
    super.dispose();
  }

  int get _sentCount => widget.contacts.where((c) => c.status == ContactDispatchStatus.sent).length;
  int get _failedCount => widget.contacts.where((c) => c.status == ContactDispatchStatus.failed).length;
  int get _skippedCount => widget.contacts.where((c) => c.status == ContactDispatchStatus.skipped).length;
  int get _totalCount => widget.contacts.length;

  /// Personalizes the message template with customer-specific data
  String _buildPersonalizedMessage(CustomerCampaignContact contact) {
    return WhatsAppGatewayService.buildPersonalizedMessage(
      template: widget.messageTemplate,
      contact: contact,
      companyName: widget.companyName,
      campaignName: widget.campaignName,
    );
  }

  // ---------------------------------------------------------------------------
  // Automated Cloud Gateway Engine
  // ---------------------------------------------------------------------------
  Future<void> _startAutomatedDispatch() async {
    if (!_gatewayConfig.isConfigured) {
      _openGatewaySettings();
      return;
    }

    // Validate Poll if in poll mode
    if (widget.pollTitle != null && widget.pollTitle!.trim().isNotEmpty) {
      final validOpts = widget.pollOptions?.where((s) => s.trim().isNotEmpty).toList() ?? [];
      if (validOpts.length < 2) {
        setState(() {
          _currentAutoStatus = widget.strings.pollRequiresTwoOptions;
        });
        return;
      }
    }

    // If all contacts were already marked sent, auto-reset to pending so they can be broadcasted!
    var contactsToDispatch = widget.contacts.where((c) => c.status != ContactDispatchStatus.sent).toList();
    if (contactsToDispatch.isEmpty && widget.contacts.isNotEmpty) {
      for (final c in widget.contacts) {
        c.status = ContactDispatchStatus.pending;
      }
      contactsToDispatch = widget.contacts.toList();
    }

    if (contactsToDispatch.isEmpty) {
      setState(() {
        _isAutoDispatching = false;
        _currentAutoStatus = widget.strings.noData;
      });
      return;
    }

    setState(() {
      _isAutoDispatching = true;
      _isAutoPaused = false;
      _isAutoCancelled = false;
      _autoProcessedCount = 0;
      _dispatchLogs.clear();
      _currentAutoStatus = widget.isAr ? 'جاري بدء الإرسال التلقائي...' : 'Starting automated dispatch...';
    });

    try {
      await for (final event in _gatewayService.sendBatchStream(
        config: _gatewayConfig,
        contacts: contactsToDispatch,
        template: widget.messageTemplate,
        companyName: widget.companyName,
        campaignName: widget.campaignName,
        attachedMediaUrl: widget.attachedMediaUrl,
        pollTitle: widget.pollTitle,
        pollOptions: widget.pollOptions,
        multiplePollAnswers: widget.multiplePollAnswers,
        isCancelled: () => _isAutoCancelled,
      )) {
        if (!mounted) break;

        // Handle pause wait
        while (_isAutoPaused && !_isAutoCancelled) {
          await Future.delayed(const Duration(milliseconds: 300));
        }

        setState(() {
          _autoProcessedCount = event.currentIndex;
          _currentAutoStatus = event.statusMessage;

          if (event.lastResult != null) {
            _dispatchLogs.insert(
              0,
              _DispatchLogItem(
                contactName: event.currentContact.name.isNotEmpty ? event.currentContact.name : event.currentContact.rawPhone,
                phoneNumber: event.currentContact.rawPhone,
                isSuccess: event.lastResult!.isSuccess,
                message: event.lastResult!.isSuccess
                    ? (widget.isAr ? 'تم الإرسال بنجاح' : 'Sent successfully')
                    : (event.lastResult!.error ?? 'Error'),
                timestamp: DateTime.now(),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentAutoStatus = 'خطأ أثناء الإرسال: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAutoDispatching = false;
        });
      }
    }
  }

  void _pauseResumeAutoDispatch() {
    setState(() {
      _isAutoPaused = !_isAutoPaused;
      _currentAutoStatus = _isAutoPaused
          ? (widget.isAr ? 'تم الإيقاف المؤقت للإرسال' : 'Dispatch paused')
          : (widget.isAr ? 'تم استئناف الإرسال...' : 'Resuming dispatch...');
    });
  }

  void _cancelAutoDispatch() {
    setState(() {
      _isAutoCancelled = true;
      _isAutoDispatching = false;
      _isAutoPaused = false;
      _currentAutoStatus = widget.isAr ? 'تم إلغاء الإرسال' : 'Dispatch cancelled';
    });
  }

  void _openGatewaySettings() {
    showDialog<WhatsAppGatewayConfigModel>(
      context: context,
      builder: (ctx) => WhatsAppGatewaySettingsDialog(
        currentConfig: _gatewayConfig,
        companySlug: widget.companySlug,
        strings: widget.strings,
        isAr: widget.isAr,
        onSaved: (updated) {
          setState(() {
            _gatewayConfig = updated;
            if (updated.isConfigured) {
              _selectedMode = DispatchMode.automatedGateway;
            }
          });
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Manual Sequential Mode Engine
  // ---------------------------------------------------------------------------
  Future<void> _launchWhatsAppForCurrent() async {
    if (_manualIndex >= widget.contacts.length) return;
    final contact = widget.contacts[_manualIndex];
    final personalizedText = _buildPersonalizedMessage(contact);
    final targetPhone = WhatsappCampaignDispatcherDialog.formatPhoneForWhatsApp(contact.rawPhone);

    final url = 'https://wa.me/$targetPhone?text=${Uri.encodeComponent(personalizedText)}';
    final uri = Uri.parse(url);

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      setState(() {
        contact.status = ContactDispatchStatus.sent;
      });

      if (_autoAdvance && _manualIndex < widget.contacts.length - 1) {
        _startAutoAdvanceCountdown();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.strings.operationFailed(e.toString())),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _startAutoAdvanceCountdown() {
    _autoAdvanceTimer?.cancel();
    setState(() {
      _countdownSeconds = 3;
    });

    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _countdownSeconds = 0;
          if (_manualIndex < widget.contacts.length - 1) {
            _manualIndex++;
          }
        });
      } else {
        setState(() {
          _countdownSeconds--;
        });
      }
    });
  }

  void _skipCurrentManual() {
    _autoAdvanceTimer?.cancel();
    if (_manualIndex < widget.contacts.length) {
      setState(() {
        widget.contacts[_manualIndex].status = ContactDispatchStatus.skipped;
        _countdownSeconds = 0;
        if (_manualIndex < widget.contacts.length - 1) {
          _manualIndex++;
        }
      });
    }
  }

  void _nextManual() {
    _autoAdvanceTimer?.cancel();
    if (_manualIndex < widget.contacts.length - 1) {
      setState(() {
        _countdownSeconds = 0;
        _manualIndex++;
      });
    }
  }

  void _previousManual() {
    _autoAdvanceTimer?.cancel();
    if (_manualIndex > 0) {
      setState(() {
        _countdownSeconds = 0;
        _manualIndex--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDone = _selectedMode == DispatchMode.automatedGateway
        ? (!_isAutoDispatching && _autoProcessedCount > 0 && (_autoProcessedCount == _totalCount || _sentCount == _totalCount))
        : (_manualIndex >= widget.contacts.length || (_sentCount + _skippedCount == _totalCount));
    final progress = _totalCount > 0 ? (_sentCount + _skippedCount) / _totalCount : 0.0;
    final currentManualContact = widget.contacts.isNotEmpty ? widget.contacts[_manualIndex.clamp(0, widget.contacts.length - 1)] : null;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 680;

    return Dialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 16 : 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 760),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header with Gradient & Live Progress
              Container(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: isMobile ? 12 : 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF0F5132),
                      Color(0xFF198754),
                      Color(0xFF20C997),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.mark_chat_read_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.strings.whatsappGatewayTitle,
                                style: GoogleFonts.cairo(
                                  fontSize: isMobile ? 15 : 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${widget.companyName} • ${widget.campaignName} ($_totalCount ${widget.isAr ? "عميل محدد" : "Recipients"})',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Quick Gateway Settings Button
                        Tooltip(
                          message: widget.strings.whatsappGatewayTitle,
                          child: IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.25),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.tune_rounded, size: 18),
                            onPressed: _openGatewaySettings,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Mode Switcher Tabs
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _isAutoDispatching
                                  ? null
                                  : () => setState(() => _selectedMode = DispatchMode.automatedGateway),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _selectedMode == DispatchMode.automatedGateway
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.cloud_sync_rounded,
                                      size: 16,
                                      color: _selectedMode == DispatchMode.automatedGateway
                                          ? const Color(0xFF0F5132)
                                          : Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        widget.strings.autoGatewayDispatchMode,
                                        style: GoogleFonts.cairo(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: _selectedMode == DispatchMode.automatedGateway
                                              ? const Color(0xFF0F5132)
                                              : Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: InkWell(
                              onTap: _isAutoDispatching
                                  ? null
                                  : () => setState(() => _selectedMode = DispatchMode.manualBrowser),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _selectedMode == DispatchMode.manualBrowser
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.touch_app_rounded,
                                      size: 16,
                                      color: _selectedMode == DispatchMode.manualBrowser
                                          ? const Color(0xFF0F5132)
                                          : Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        widget.strings.manualDispatchMode,
                                        style: GoogleFonts.cairo(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: _selectedMode == DispatchMode.manualBrowser
                                              ? const Color(0xFF0F5132)
                                              : Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Progress Bar
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF20C997)),
              ),

              // 2. Main Body Content
              Expanded(
                child: _isLoadingConfig
                    ? const Center(child: CircularProgressIndicator())
                    : (isDone && _sentCount == _totalCount
                        ? _buildCompletionView(cs)
                        : (_selectedMode == DispatchMode.automatedGateway
                            ? _buildAutomatedGatewayView(cs, isMobile)
                            : (currentManualContact == null
                                ? Center(child: Text(widget.strings.noData))
                                : _buildManualQueueView(cs, currentManualContact, isMobile)))),
              ),

              // 3. Footer Action Bar
              Container(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: isMobile ? 10 : 14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
                ),
                child: Row(
                  children: [
                    if (_selectedMode == DispatchMode.manualBrowser)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch.adaptive(
                            value: _autoAdvance,
                            activeTrackColor: const Color(0xFF198754),
                            onChanged: (val) {
                              setState(() {
                                _autoAdvance = val;
                                if (!val) {
                                  _autoAdvanceTimer?.cancel();
                                  _countdownSeconds = 0;
                                }
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.strings.autoAdvanceToggle,
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 11 : 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _gatewayConfig.isConfigured ? Icons.check_circle_rounded : Icons.warning_rounded,
                            size: 16,
                            color: _gatewayConfig.isConfigured ? const Color(0xFF198754) : Colors.orange.shade800,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _gatewayConfig.isConfigured
                                ? '${_gatewayConfig.provider.displayName} • ${_gatewayConfig.delayBetweenMessagesSeconds}s delay'
                                : widget.strings.gatewayNotConfiguredBadge,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _gatewayConfig.isConfigured ? const Color(0xFF198754) : Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    const Spacer(),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20, vertical: isMobile ? 8 : 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        widget.strings.close,
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
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

  // ---------------------------------------------------------------------------
  // Automated Gateway View Builder
  // ---------------------------------------------------------------------------
  Widget _buildAutomatedGatewayView(ColorScheme cs, bool isMobile) {
    final hasConfig = _gatewayConfig.isConfigured;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gateway Status Banner
          if (!hasConfig)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.amber.shade800.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.amber.shade800.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.amber.shade900, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.isAr ? 'البوابة السحابية بحاجة للضبط أولاً' : 'Gateway configuration required',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.isAr
                        ? 'يرجى إدخال بيانات حساب البوابة (Instance ID & Token) لتتمكن من إرسال الرسائل تلقائياً في الخلفية.'
                        : 'Please enter your gateway credentials (Instance ID & Token) to enable automated background broadcasts.',
                    style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amber.shade800.withValues(alpha: 0.2),
                      foregroundColor: const Color(0xFF451A03),
                    ),
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: Text(widget.strings.gatewayNotConfiguredBadge, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    onPressed: _openGatewaySettings,
                  ),
                ],
              ),
            ),

          // Active Poll Preview Card
          if (widget.pollTitle != null && widget.pollTitle!.trim().isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF198754).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF198754).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF198754).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.poll_rounded, color: Color(0xFF198754), size: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.strings.pollPreviewTitle,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: const Color(0xFF0F5132),
                        ),
                      ),
                      const Spacer(),
                      if (widget.multiplePollAnswers)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF198754).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.isAr ? 'خيارات متعددة مسموحة' : 'Multiple choices allowed',
                            style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF0F5132)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.pollTitle!,
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onSurface),
                  ),
                  if (widget.pollOptions != null && widget.pollOptions!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: widget.pollOptions!
                          .where((opt) => opt.trim().isNotEmpty)
                          .map((opt) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF198754).withValues(alpha: 0.25)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.radio_button_unchecked_rounded, size: 13, color: Color(0xFF198754)),
                                    const SizedBox(width: 6),
                                    Text(opt, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Automated Dispatch Status Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.strings.autoDispatchTitle,
                      style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    if (_isAutoDispatching)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF198754).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF198754)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF198754)),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.isAr ? 'جاري البث...' : 'Broadcasting...',
                              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF198754)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.strings.autoDispatchNotice,
                  style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 16),

                // KPI Counter Stats
                Row(
                  children: [
                    Expanded(
                      child: _buildStatChip(
                        title: widget.isAr ? 'إجمالي الحملة' : 'Total',
                        value: '$_totalCount',
                        color: cs.primary,
                        cs: cs,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatChip(
                        title: widget.isAr ? 'تم بنجاح' : 'Success',
                        value: '$_sentCount',
                        color: const Color(0xFF198754),
                        cs: cs,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatChip(
                        title: widget.isAr ? 'تعذر' : 'Failed',
                        value: '$_failedCount',
                        color: Colors.red.shade700,
                        cs: cs,
                      ),
                    ),
                  ],
                ),

                // Reset Statuses Button if any contacts were already sent
                if (_sentCount > 0 && !_isAutoDispatching) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: cs.primary,
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: Text(
                        widget.strings.resetContactStatuses,
                        style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        setState(() {
                          for (final c in widget.contacts) {
                            c.status = ContactDispatchStatus.pending;
                          }
                          _currentAutoStatus = widget.isAr
                              ? 'تمت إعادة تعيين حالة جميع العملاء إلى قيد الانتظار'
                              : 'All customer statuses reset to pending';
                        });
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Live status message box
                if (_currentAutoStatus.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _currentAutoStatus,
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),

                const SizedBox(height: 16),

                // Auto Dispatch Action Buttons
                if (!_isAutoDispatching)
                  Builder(
                    builder: (context) {
                      final allSent = _totalCount > 0 && _sentCount == _totalCount;
                      return SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: allSent ? const Color(0xFF0F5132) : const Color(0xFF198754),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: Icon(allSent ? Icons.replay_rounded : Icons.bolt_rounded, size: 22),
                          label: Text(
                            allSent ? widget.strings.resendToAllNow : widget.strings.startAutoDispatch,
                            style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _startAutomatedDispatch,
                        ),
                      );
                    },
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: Icon(_isAutoPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                          label: Text(
                            _isAutoPaused ? widget.strings.resumeDispatch : widget.strings.pauseDispatch,
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                          ),
                          onPressed: _pauseResumeAutoDispatch,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.stop_rounded),
                          label: Text(
                            widget.strings.cancelDispatch,
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                          ),
                          onPressed: _cancelAutoDispatch,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Live Dispatch Logs Section
          if (_dispatchLogs.isNotEmpty) ...[
            Text(
              widget.isAr ? 'سجل الإرسال اللحظي (Live Dispatch Logs):' : 'Live Dispatch Logs:',
              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: ListView.separated(
                controller: _logsScrollController,
                shrinkWrap: true,
                padding: const EdgeInsets.all(10),
                itemCount: _dispatchLogs.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final log = _dispatchLogs[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(
                          log.isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                          size: 16,
                          color: log.isSuccess ? const Color(0xFF198754) : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${log.contactName} (${log.phoneNumber})',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          log.message,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: log.isSuccess ? const Color(0xFF0F5132) : Colors.red.shade900,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String title,
    required String value,
    required Color color,
    required ColorScheme cs,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            title,
            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Manual Queue View Builder
  // ---------------------------------------------------------------------------
  Widget _buildManualQueueView(ColorScheme cs, CustomerCampaignContact contact, bool isMobile) {
    final personalizedText = _buildPersonalizedMessage(contact);
    final isSent = contact.status == ContactDispatchStatus.sent;
    final isSkipped = contact.status == ContactDispatchStatus.skipped;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step Counter & Customer Progress Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${_manualIndex + 1}',
                      style: GoogleFonts.cairo(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.strings.customerQueueProgress} (${_manualIndex + 1} / $_totalCount)',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 12 : 14,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (_countdownSeconds > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF198754),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.isAr ? "التالي خلال" : "Next in"} $_countdownSeconds s',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Customer Profile Card
          Container(
            padding: EdgeInsets.all(isMobile ? 14 : 18),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                CircleAvatar(
                  radius: isMobile ? 22 : 26,
                  backgroundColor: cs.primary.withValues(alpha: 0.15),
                  child: Text(
                    contact.name.isNotEmpty ? contact.name.characters.first : 'ع',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 16 : 20,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              contact.name.isNotEmpty ? contact.name : (widget.isAr ? 'عميل بدون اسم' : 'Unnamed Customer'),
                              style: GoogleFonts.cairo(
                                fontSize: isMobile ? 14 : 16,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSent)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF198754).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF198754)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF198754), size: 13),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.isAr ? 'تم الإرسال' : 'Sent',
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF198754),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (isSkipped)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade800.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange.shade800),
                              ),
                              child: Text(
                                widget.isAr ? 'تم التخطي' : 'Skipped',
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone_iphone_rounded, size: 14, color: cs.primary),
                              const SizedBox(width: 4),
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  contact.rawPhone,
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '(+${WhatsappCampaignDispatcherDialog.formatPhoneForWhatsApp(contact.rawPhone)})',
                            style: GoogleFonts.robotoMono(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (contact.lastBranch.isNotEmpty)
                            _buildInfoChip(Icons.storefront_rounded, contact.lastBranch, cs),
                          _buildInfoChip(
                            Icons.receipt_long_rounded,
                            '${contact.totalInvoices} ${widget.isAr ? "فواتير" : "Invoices"}',
                            cs,
                          ),
                          if (contact.totalSpend > 0)
                            _buildInfoChip(
                              Icons.shopping_bag_outlined,
                              '${contact.totalSpend.toStringAsFixed(1)} ${widget.isAr ? "ج.م" : "EGP"}',
                              cs,
                            ),
                          if (contact.isWinner)
                            _buildInfoChip(
                              Icons.emoji_events_rounded,
                              contact.prizesWon.join(', '),
                              cs,
                              accentColor: Colors.amber.shade800,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Message Preview Container
          Text(
            widget.strings.liveMessagePreview,
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFDCF8C6).withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded, size: 15, color: Color(0xFF075E54)),
                    const SizedBox(width: 6),
                    Text(
                      widget.isAr ? 'نص الرسالة المجهزة لهذا العميل:' : 'Prepared WhatsApp message for this customer:',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF075E54),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  personalizedText,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    height: 1.6,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Big Main Action Button: Send & Open WhatsApp
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.send_rounded, size: 20),
              label: Text(
                widget.strings.sendAndOpenWhatsApp,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: _launchWhatsAppForCurrent,
            ),
          ),
          const SizedBox(height: 10),

          // Navigation Controls (Previous / Skip / Next)
          Row(
            children: [
              Expanded(
                flex: isMobile ? 3 : 0,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Icon(widget.isAr ? Icons.arrow_forward_ios_rounded : Icons.arrow_back_ios_rounded, size: 13),
                  label: Text(
                    widget.strings.previousCustomer,
                    style: GoogleFonts.cairo(fontSize: isMobile ? 11 : 12, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _manualIndex > 0 ? _previousManual : null,
                ),
              ),
              if (!isMobile) const Spacer(),
              if (isMobile) const SizedBox(width: 6),
              Expanded(
                flex: isMobile ? 3 : 0,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.redo_rounded, size: 15),
                  label: Text(
                    widget.strings.skipToNextCustomer,
                    style: GoogleFonts.cairo(fontSize: isMobile ? 11 : 12, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _skipCurrentManual,
                ),
              ),
              SizedBox(width: isMobile ? 6 : 8),
              Expanded(
                flex: isMobile ? 3 : 0,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Icon(widget.isAr ? Icons.arrow_back_ios_rounded : Icons.arrow_forward_ios_rounded, size: 13),
                  label: Text(
                    widget.strings.nextCustomer,
                    style: GoogleFonts.cairo(fontSize: isMobile ? 11 : 12, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _manualIndex < widget.contacts.length - 1 ? _nextManual : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionView(ColorScheme cs) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF198754).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF198754), size: 64),
            ),
            const SizedBox(height: 20),
            Text(
              widget.strings.dispatchCompleted,
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.isAr
                  ? 'تم إرسال الرسائل بنجاح لـ $_sentCount عميل من إجمالي $_totalCount عميل محدد.'
                  : 'Messages dispatched to $_sentCount of $_totalCount targeted customers.',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(
                    widget.strings.resendToAllNow,
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    setState(() {
                      for (final c in widget.contacts) {
                        c.status = ContactDispatchStatus.pending;
                      }
                      _autoProcessedCount = 0;
                    });
                    _startAutomatedDispatch();
                  },
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF198754),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.done_all_rounded),
                  label: Text(
                    widget.strings.confirm,
                    style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, ColorScheme cs, {Color? accentColor}) {
    final color = accentColor ?? cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DispatchLogItem {
  final String contactName;
  final String phoneNumber;
  final bool isSuccess;
  final String message;
  final DateTime timestamp;

  const _DispatchLogItem({
    required this.contactName,
    required this.phoneNumber,
    required this.isSuccess,
    required this.message,
    required this.timestamp,
  });
}
