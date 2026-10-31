import 'package:al_mraay/core/constants/ai_models.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/localization/app_strings.dart';
import '../../domain/whatsapp_ai_auto_reply_service.dart';
import '../../domain/whatsapp_gateway_config_model.dart';
import '../../domain/whatsapp_gateway_service.dart';
import 'whatsapp_screenshot_dialog.dart';
import 'whatsapp_qr_pairing_dialog.dart';
import '../../../../core/widgets/m3_action_menu.dart';
import '../../../../core/widgets/m3_button_groups.dart';

import '../../domain/whatsapp_winner_notification_service.dart';

/// Modal dialog for configuring WhatsApp Gateway API credentials and testing live connection
class WhatsAppGatewaySettingsDialog extends StatefulWidget {
  final WhatsAppGatewayConfigModel currentConfig;
  final String? companySlug;
  final AppStrings strings;
  final bool isAr;
  final Function(WhatsAppGatewayConfigModel updatedConfig) onSaved;

  const WhatsAppGatewaySettingsDialog({
    super.key,
    required this.currentConfig,
    this.companySlug,
    required this.strings,
    required this.isAr,
    required this.onSaved,
  });

  @override
  State<WhatsAppGatewaySettingsDialog> createState() => _WhatsAppGatewaySettingsDialogState();
}

class _WhatsAppGatewaySettingsDialogState extends State<WhatsAppGatewaySettingsDialog> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  final _service = WhatsAppGatewayService();
  late WhatsAppGatewayProvider _selectedProvider;
  late final TextEditingController _instanceIdController;
  late final TextEditingController _apiTokenController;
  late final TextEditingController _customEndpointController;
  late int _delaySeconds;
  late bool _isEnabled;
  late bool _enableTypingSimulation;
  late int _typingDurationSeconds;
  late bool _enableAiAutoReply;
  late final TextEditingController _aiCustomSystemPromptController;
  late bool _autoNotifyWinnersOnGiftHandover;
  late final TextEditingController _winnerTemplateController;

  bool _isTesting = false;
  bool _isRestarting = false;
  WhatsAppGatewayConnectionStatus? _testStatus;
  WhatsAppGatewayStats? _liveStats;

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.currentConfig.provider;
    _instanceIdController = TextEditingController(
      text: widget.currentConfig.instanceId.isNotEmpty ? widget.currentConfig.instanceId : 'default',
    );
    _apiTokenController = TextEditingController(
      text: widget.currentConfig.apiToken,
    );
    _customEndpointController = TextEditingController(
      text: widget.currentConfig.customEndpointUrl.isNotEmpty
          ? widget.currentConfig.customEndpointUrl
          : WhatsAppGatewayService.kDefaultWahaProxyBase,
    );
    _delaySeconds = widget.currentConfig.delayBetweenMessagesSeconds.clamp(1, 15);
    _isEnabled = widget.currentConfig.isEnabled;
    _enableTypingSimulation = widget.currentConfig.enableTypingSimulation;
    _typingDurationSeconds = widget.currentConfig.typingDurationSeconds.clamp(1, 10);
    _enableAiAutoReply = widget.currentConfig.enableAiAutoReply;
    _aiCustomSystemPromptController = TextEditingController(
      text: widget.currentConfig.aiCustomSystemPrompt,
    );
    _autoNotifyWinnersOnGiftHandover = widget.currentConfig.autoNotifyWinnersOnGiftHandover;
    _winnerTemplateController = TextEditingController(
      text: widget.currentConfig.winnerNotificationTemplate,
    );
  }

  @override
  void dispose() {
    _instanceIdController.dispose();
    _apiTokenController.dispose();
    _customEndpointController.dispose();
    _aiCustomSystemPromptController.dispose();
    _winnerTemplateController.dispose();
    super.dispose();
  }

  WhatsAppGatewayConfigModel _buildConfigFromForm() {
    return WhatsAppGatewayConfigModel(
      provider: _selectedProvider,
      instanceId: _instanceIdController.text.trim(),
      apiToken: _apiTokenController.text.trim(),
      customEndpointUrl: _customEndpointController.text.trim(),
      delayBetweenMessagesSeconds: _delaySeconds,
      isEnabled: _isEnabled,
      isConnected: _testStatus?.isConnected ?? widget.currentConfig.isConnected,
      lastTestedAt: _testStatus != null ? DateTime.now() : widget.currentConfig.lastTestedAt,
      connectedPhoneNumber: _testStatus?.phoneNumber ?? widget.currentConfig.connectedPhoneNumber,
      enableTypingSimulation: _enableTypingSimulation,
      typingDurationSeconds: _typingDurationSeconds,
      enableAiAutoReply: _enableAiAutoReply,
      aiCustomSystemPrompt: _aiCustomSystemPromptController.text.trim(),
      autoNotifyWinnersOnGiftHandover: _autoNotifyWinnersOnGiftHandover,
      winnerNotificationTemplate: _winnerTemplateController.text.trim(),
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testStatus = null;
      _liveStats = null;
    });

    final tempConfig = _buildConfigFromForm();
    final status = await _service.testConnection(tempConfig);
    WhatsAppGatewayStats? stats;
    if (status.isConnected && tempConfig.provider == WhatsAppGatewayProvider.waha) {
      stats = await _service.fetchStatistics(tempConfig);
    }

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testStatus = status;
        _liveStats = stats;
      });
    }
  }

  Future<void> _restartInstance() async {
    setState(() => _isRestarting = true);
    final tempConfig = _buildConfigFromForm();
    final success = await _service.restartInstance(tempConfig);
    if (mounted) {
      setState(() => _isRestarting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (widget.isAr ? 'تم إرسال أمر إعادة تشغيل الجلسة بنجاح' : 'Instance restart triggered successfully')
                : (widget.isAr ? 'تعذر إعادة تشغيل الجلسة' : 'Failed to restart instance'),
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: success ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
        ),
      );
      if (success) {
        _testConnection();
      }
    }
  }

  String? get _connectedPhoneNumber => _testStatus?.phoneNumber ?? widget.currentConfig.connectedPhoneNumber;

  void _openQrPairingDialog() {
    final currentFormConfig = _buildConfigFromForm();
    showDialog(
      context: context,
      builder: (ctx) => WhatsAppQrPairingDialog(
        config: currentFormConfig,
        strings: widget.strings,
        isAr: widget.isAr,
        companySlug: widget.companySlug,
        onLinked: (updatedConfig) {
          setState(() {
            _testStatus = WhatsAppGatewayConnectionStatus(
              isConnected: true,
              instanceStatus: 'WORKING',
              phoneNumber: updatedConfig.connectedPhoneNumber,
              statusDetails: widget.isAr
                  ? 'متصل بنجاح وجاهز للإرسال (سيرفر WAHA الخاص)'
                  : 'Connected successfully (WAHA Private Server)',
            );
          });
          widget.onSaved(updatedConfig);
        },
      ),
    ).then((_) {
      _testConnection();
    });
  }

  Future<void> _logoutCurrentNumber() async {
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

    setState(() => _isRestarting = true);
    final tempConfig = _buildConfigFromForm();
    final success = await _service.logoutInstance(tempConfig);
    if (!mounted) return;

    setState(() => _isRestarting = false);
    if (success) {
      final updatedConfig = tempConfig.copyWith(
        isConnected: false,
        connectedPhoneNumber: null,
      );
      await _service.saveConfig(updatedConfig, companySlug: widget.companySlug);
      widget.onSaved(updatedConfig);

      setState(() {
        _testStatus = WhatsAppGatewayConnectionStatus(
          isConnected: false,
          instanceStatus: 'SCAN_QR_CODE',
          statusDetails: widget.isAr
              ? 'تم فك الارتباط بنجاح. امسح رمز الـ QR لربط رقمك الجديد.'
              : 'Unlinked successfully. Scan QR to connect new phone.',
        );
      });

      // Restart instance to immediately have fresh QR ready
      await _service.restartInstance(tempConfig);

      // Open QR pairing dialog right away!
      _openQrPairingDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isAr ? 'تعذر فك الارتباط من السيرفر' : 'Failed to unlink phone on server',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _openAiReplySimulator(ColorScheme cs) {
    final queryController = TextEditingController(
      text: widget.isAr ? 'أين فرعكم في سموحة ومواعيد العمل؟' : 'Where is your branch and opening hours?',
    );
    String? aiReply;
    bool isGenerating = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: cs.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.smart_toy_rounded, color: cs.tertiary),
                const SizedBox(width: 8),
                Text(
                  widget.isAr ? 'محاكاة الرد الآلي الذكي (${AiModels.helperServicesLabel})' : 'AI Auto-Reply Simulator',
                  style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.isAr
                        ? 'اختبر كيف سيرد عقل الذكاء الاصطناعي تلقائياً عندما يسأل العميل عن الفروع أو شروط الحملة:'
                        : 'Test how the AI auto-replies to incoming customer messages:',
                    style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: queryController,
                    decoration: InputDecoration(
                      labelText: widget.isAr ? 'سؤال أو رد العميل الافتراضي' : 'Simulated Customer Question',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    style: GoogleFonts.cairo(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    icon: isGenerating
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(
                      widget.isAr ? 'توليد الرد الآلي فوراً' : 'Generate AI Auto-Reply',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
                    onPressed: isGenerating
                        ? null
                        : () async {
                            setDialogState(() {
                              isGenerating = true;
                              aiReply = null;
                            });
                            final reply = await WhatsAppAiAutoReplyService().generateReply(
                              customerMessage: queryController.text,
                              companyName: widget.companySlug ?? 'تساهيل جيفت',
                              campaignName: 'الحملة الترويجية الحالية',
                              customInstructions: _aiCustomSystemPromptController.text.trim(),
                            );
                            if (context.mounted) {
                              setDialogState(() {
                                isGenerating = false;
                                aiReply = reply;
                              });
                            }
                          },
                  ),
                  if (aiReply != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.primary.withValues(alpha: 0.6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.mark_chat_read_rounded, size: 16, color: cs.primary),
                              const SizedBox(width: 6),
                              Text(
                                widget.isAr ? 'رد الذكاء الاصطناعي المُرسل للعميل:' : 'AI Generated WhatsApp Reply:',
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(aiReply!, style: GoogleFonts.cairo(fontSize: 12, height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(widget.isAr ? 'إغلاق' : 'Close', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openTestWinnerDialog(ColorScheme cs) async {
    final messenger = ScaffoldMessenger.of(context);
    final phoneCtrl = TextEditingController(
      text: _testStatus?.phoneNumber ?? widget.currentConfig.connectedPhoneNumber ?? '01211857725',
    );
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.celebration_rounded, color: colorScheme.tertiary),
            const SizedBox(width: 8),
            Text(
              widget.isAr ? 'إرسال رسالة فوز تجريبية' : 'Test Winner Notification',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isAr
                  ? 'سيتم إرسال رسالة تهنئة تجريبية نموذجية للتحقق من صياغة وتنسيق الرسالة ووصولها للهاتف بنجاح:'
                  : 'A celebratory sample notification will be dispatched to test live delivery:',
              style: GoogleFonts.cairo(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: InputDecoration(
                labelText: widget.isAr ? 'رقم الهاتف للتجربة' : 'Recipient Phone',
                prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                hintText: '01211857725',
                filled: true,
                fillColor: cs.surfaceContainerLow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(widget.isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: colorScheme.tertiary),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(widget.isAr ? 'إرسال الآن' : 'Send Now', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || phoneCtrl.text.trim().isEmpty) return;

    final targetPhone = phoneCtrl.text.trim();
    final tempConfig = _buildConfigFromForm();

    final testMsg = WhatsAppWinnerNotificationService.buildWinnerMessage(
      config: tempConfig,
      prizeName: 'فواتشر بقيمة 50 جنيه',
      customerName: 'عمر فتح الله (تجربة)',
      retailChain: 'أسواق فتح الله',
      branchName: 'فرع الإقبال',
      companyName: 'شركة ادكو للتجارة والصناعة',
      campaignName: 'مهرجان التوفير والجوائز',
      voucherSerials: ['TEST-VCH-2026'],
      receiptNumber: 'REC-99401',
      customerPhone: '01000000000',
    );

    final res = await _service.sendSingleMessage(
      config: tempConfig,
      toPhone: targetPhone,
      messageText: testMsg,
    );

    if (res.isSuccess) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.isAr ? 'تم إرسال رسالة التهنئة بنجاح إلى $targetPhone 📲' : 'Test winner notification sent to $targetPhone',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: colorScheme.onTertiaryFixedVariant,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('فشل الإرسال: ${res.error}', style: GoogleFonts.cairo()),
          backgroundColor: cs.error,
        ),
      );
    }
  }

  Future<void> _saveAndClose() async {
    final updatedConfig = _buildConfigFromForm().copyWith(
      isEnabled: true,
      isConnected: _testStatus?.isConnected ?? widget.currentConfig.isConnected,
      lastTestedAt: DateTime.now(),
    );

    await _service.saveConfig(updatedConfig, companySlug: widget.companySlug);
    widget.onSaved(updatedConfig);

    if (mounted) {
      Navigator.of(context).pop(updatedConfig);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isAr ? 'تم حفظ وتفعيل إعدادات بوابة الواتساب بنجاح' : 'WhatsApp Gateway configured successfully',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final strings = widget.strings;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.cloud_sync_rounded, size: 28, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.whatsappGatewayTitle,
                          style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          strings.whatsappGatewaySubtitle,
                          style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),

              // Provider Selector
              Text(
                strings.gatewayProviderLabel,
                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              M3ActionMenu(
                anchorBuilder: (context, controller, child) => InkWell(
                  onTap: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.hub_rounded, size: 20, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selectedProvider.displayName,
                            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface),
                          ),
                        ),
                        Icon(Icons.unfold_more_rounded, size: 20, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
                children: WhatsAppGatewayProvider.values.map((p) {
                  return M3ActionMenu.item(
                    context: context,
                    label: p.displayName,
                    icon: Icons.hub_rounded,
                    isSelected: _selectedProvider == p,
                    onPressed: () {
                      setState(() {
                        _selectedProvider = p;
                        _testStatus = null;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Provider Fields
              if (_selectedProvider == WhatsAppGatewayProvider.waha) ...[
                // WAHA Endpoint URL
                TextField(
                  controller: _customEndpointController,
                  decoration: InputDecoration(
                    labelText: widget.isAr ? 'عنوان سيرفر WAHA (Endpoint URL)' : 'WAHA Server URL',
                    hintText: WhatsAppGatewayService.kDefaultWahaProxyBase,
                    prefixIcon: const Icon(Icons.dns_rounded, size: 20),
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 14),

                // API Key
                TextField(
                  controller: _apiTokenController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: widget.isAr ? 'مفتاح الـ API الخاص بالسيرفر (X-Api-Key)' : 'Server API Key',
                    hintText: widget.isAr ? 'اتركه فارغًا — السيرفر يحقن المفتاح' : 'Leave empty — server injects the key',
                    prefixIcon: const Icon(Icons.key_rounded, size: 20),
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 14),

                // Session Name
                TextField(
                  controller: _instanceIdController,
                  decoration: InputDecoration(
                    labelText: widget.isAr ? 'اسم الجلسة (Session Name)' : 'Session Name',
                    hintText: 'default',
                    prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ] else if (_selectedProvider != WhatsAppGatewayProvider.custom) ...[
                // Instance ID
                TextField(
                  controller: _instanceIdController,
                  decoration: InputDecoration(
                    labelText: strings.instanceIdLabel,
                    hintText: 'مثال: 1101823901',
                    prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 14),

                // API Token
                TextField(
                  controller: _apiTokenController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: strings.apiTokenLabel,
                    hintText: 'أدخل مفتاح الوصول Token',
                    prefixIcon: const Icon(Icons.key_rounded, size: 20),
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ] else ...[
                // Custom Endpoint URL
                TextField(
                  controller: _customEndpointController,
                  decoration: InputDecoration(
                    labelText: strings.customEndpointLabel,
                    hintText: 'https://your-whatsapp-server.com/api',
                    prefixIcon: const Icon(Icons.link_rounded, size: 20),
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _apiTokenController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '${strings.apiTokenLabel} (اختياري)',
                    hintText: 'Bearer Token إن وُجد',
                    prefixIcon: const Icon(Icons.key_rounded, size: 20),
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // Anti-Spam Pacing Slider
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_rounded, size: 18, color: cs.primary),
                            const SizedBox(width: 8),
                            Text(
                              strings.delayBetweenMessagesLabel,
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$_delaySeconds ${widget.isAr ? "ثوانٍ" : "sec"}',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _delaySeconds.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      activeColor: cs.primary,
                      onChanged: (val) => setState(() => _delaySeconds = val.round()),
                    ),
                    Text(
                      widget.isAr
                          ? '💡 نصيحة: وضع فاصل من 3 إلى 5 ثوانٍ بين الرسائل يحاكي السلوك البشري الطبيعي ويمنع تصنيف الرسائل كـ Spam.'
                          : '💡 Tip: 3 to 5 seconds delay mimics natural human messaging pacing and protects your number from anti-spam flags.',
                      style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant, height: 1.3),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Typing Simulation Card (Feature 3)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.keyboard_rounded, color: cs.onPrimaryContainer, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isAr ? 'محاكاة الكتابة الحقيقية (Typing Simulator)' : 'Typing Simulator',
                                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                widget.isAr
                                    ? 'تشغيل إشارة "يكتب الآن..." قبل إرسال كل رسالة لإضفاء طابع بشري بنسبة 100%'
                                    : 'Display "typing..." indicator before sending to simulate real human pacing',
                                style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _enableTypingSimulation,
                          activeThumbColor: cs.primary,
                          onChanged: (val) => setState(() => _enableTypingSimulation = val),
                        ),
                      ],
                    ),
                    if (_enableTypingSimulation) ...[
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.isAr ? 'مدة محاكاة الكتابة:' : 'Typing Duration:',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$_typingDurationSeconds ${widget.isAr ? "ثوانٍ" : "sec"}',
                              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _typingDurationSeconds.toDouble(),
                        min: 1,
                        max: 5,
                        divisions: 4,
                        activeColor: cs.primary,
                        onChanged: (val) => setState(() => _typingDurationSeconds = val.round()),
                      ),
                    ],
                  ],
                ),
              ),

              // AI Auto-Reply Bot Card (Feature 5)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cs.tertiaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.smart_toy_rounded, color: cs.onTertiaryContainer, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    widget.isAr ? 'الرد الآلي الذكي (AI Auto-Reply Bot)' : 'AI Auto-Reply Bot',
                                    style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: cs.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      AiModels.helperServicesConstLabel,
                                      style: GoogleFonts.robotoMono(fontSize: 9, fontWeight: FontWeight.bold, color: cs.onTertiaryContainer),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                widget.isAr
                                    ? 'الرد الفوري على أسئلة العملاء (الفروع، شروط الاستلام) بذكاء اصطناعي فائق السرعة'
                                    : 'Auto-reply to customer questions about branches and prize rules with Gemini AI',
                                style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _enableAiAutoReply,
                          activeThumbColor: cs.tertiary,
                          onChanged: (val) => setState(() => _enableAiAutoReply = val),
                        ),
                      ],
                    ),
                    if (_enableAiAutoReply) ...[
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _aiCustomSystemPromptController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: widget.isAr ? 'توجيهات إضافية لعقل الذكاء الاصطناعي (اختياري)' : 'Custom AI Instructions (Optional)',
                          hintText: widget.isAr ? 'مثال: التأكيد على أن مواعيد العمل من 10 ص حتى 11 م' : 'e.g. Confirm working hours from 10 AM to 11 PM',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: cs.surface,
                        ),
                        style: GoogleFonts.cairo(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.psychology_rounded, size: 16),
                          label: Text(
                            widget.isAr ? 'تجربة محاكاة رد الذكاء الاصطناعي' : 'Test AI Simulator',
                            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => _openAiReplySimulator(cs),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Auto-Notify Winners on Gift Handover Card (WhatsApp Winner Notification)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.card_giftcard_rounded, color: colorScheme.onTertiaryFixedVariant, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isAr ? 'إشعار الفائزين التلقائي بالواتساب عند تسليم الهدية' : 'Auto-Notify Winners on Gift Handover',
                                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                widget.isAr
                                    ? 'إرسال رسالة رسمية مبهجة فوراً برقم البون والفرع والشركة ونوع الجائزة'
                                    : 'Instantly dispatches branded celebratory WhatsApp message upon gift handover',
                                style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _autoNotifyWinnersOnGiftHandover,
                          activeTrackColor: colorScheme.tertiary,
                          onChanged: (val) => setState(() => _autoNotifyWinnersOnGiftHandover = val),
                        ),
                      ],
                    ),
                    if (_autoNotifyWinnersOnGiftHandover) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Text(
                        widget.isAr ? 'قالب رسالة التهنئة المعتمد:' : 'Winner Notification Message Template:',
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _winnerTemplateController,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: WhatsAppGatewayConfigModel.defaultWinnerTemplate,
                          filled: true,
                          fillColor: cs.surface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        style: GoogleFonts.cairo(fontSize: 11, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          '{customer_name}',
                          '{phone}',
                          '{retail_chain}',
                          '{branch_name}',
                          '{company_name}',
                          '{campaign_name}',
                          '{voucher_details}',
                          '{receipt_number}',
                          '{claim_date}',
                        ].map((token) {
                          return ActionChip(
                            label: Text(token, style: GoogleFonts.robotoMono(fontSize: 10)),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              final text = _winnerTemplateController.text;
                              _winnerTemplateController.text = '$text $token';
                              setState(() {});
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: Text(
                              widget.isAr ? 'استعادة القالب الافتراضي' : 'Reset to Default',
                              style: GoogleFonts.cairo(fontSize: 11),
                            ),
                            onPressed: () {
                              setState(() {
                                _winnerTemplateController.text = WhatsAppGatewayConfigModel.defaultWinnerTemplate;
                              });
                            },
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.tertiary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: Text(
                              widget.isAr ? 'إرسال رسالة فوز تجريبية' : 'Send Test Winner Message',
                              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _openTestWinnerDialog(cs),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // WhatsApp Device QR Pairing & Number Management Card
              if (_selectedProvider == WhatsAppGatewayProvider.waha)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.45), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.qr_code_scanner_rounded, color: colorScheme.tertiary, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.isAr ? 'ربط رقم الواتساب ومسح الرمز (QR Code)' : 'WhatsApp Phone Pairing (QR Code)',
                                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onSurface),
                                ),
                                Text(
                                  _connectedPhoneNumber != null && _connectedPhoneNumber!.isNotEmpty
                                      ? '${widget.isAr ? "الرقم المرتبط حالياً: " : "Linked Phone: "}$_connectedPhoneNumber'
                                      : (widget.isAr
                                          ? 'امسح رمز الاستجابة السريعة بكاميرا الواتساب لربط رقم الهاتف أو تغييره'
                                          : 'Scan QR code with WhatsApp camera to link or change phone number'),
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: _connectedPhoneNumber != null ? FontWeight.bold : FontWeight.normal,
                                    color: _connectedPhoneNumber != null ? cs.primary : cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          // Primary Button: Scan QR / Link New Number
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                            label: Text(
                              widget.strings.linkViaQrOrCode,
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            onPressed: _openQrPairingDialog,
                          ),

                          // Unlink / Change Number Button (if a number is connected)
                          if (_connectedPhoneNumber != null && _connectedPhoneNumber!.isNotEmpty)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cs.error,
                                side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.link_off_rounded, size: 18),
                              label: Text(
                                widget.strings.unlinkAndChangeNumber,
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              onPressed: _isRestarting ? null : _logoutCurrentNumber,
                            ),

                          // Restart Session Button
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _isRestarting
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.restart_alt_rounded, size: 18),
                            label: Text(
                              widget.strings.restartSessionBtn,
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            onPressed: _isRestarting ? null : _restartInstance,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Live Screenshot Quick Action Card (Feature 6)
              if (_selectedProvider == WhatsAppGatewayProvider.waha)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.screenshot_monitor_rounded, color: cs.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isAr ? 'لقطة الشاشة الحية (Live Screenshot)' : 'Live WhatsApp Screen',
                              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              widget.isAr
                                  ? 'معاينة شاشة واتساب ويب داخل السيرفر والتأكد من حالة هاتفك مباشرة'
                                  : 'Preview WhatsApp Web screen inside server and verify phone status',
                              style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.visibility_rounded, size: 16),
                        label: Text(
                          widget.isAr ? 'معاينة الشاشة' : 'Preview Screen',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => WhatsAppScreenshotDialog(
                              config: _buildConfigFromForm(),
                              strings: widget.strings,
                              isAr: widget.isAr,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

              // Connection Test Status Box & Live Statistics Hub
              if (_testStatus != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _testStatus!.isConnected
                        ? cs.primaryContainer.withValues(alpha: 0.25)
                        : cs.errorContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _testStatus!.isConnected ? cs.primary : cs.error,
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _testStatus!.isConnected ? Icons.check_circle_rounded : Icons.error_rounded,
                            color: _testStatus!.isConnected ? cs.primary : cs.error,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _testStatus!.isConnected ? strings.gatewayConnectedBadge : strings.gatewayDisconnectedBadge,
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _testStatus!.isConnected ? cs.primary : cs.error,
                                  ),
                                ),
                                if (_testStatus!.statusDetails != null)
                                  Text(
                                    _testStatus!.statusDetails!,
                                    style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                                  ),
                                if (_testStatus!.phoneNumber != null)
                                  Text(
                                    '${widget.isAr ? "الرقم المتصل: " : "Connected Phone: "}${_testStatus!.phoneNumber}',
                                    style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary),
                                  ),
                              ],
                            ),
                          ),
                          if (_selectedProvider == WhatsAppGatewayProvider.waha) ...[
                            if (!_testStatus!.isConnected)
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                                label: Text(
                                  widget.isAr ? 'مسح QR' : 'Scan QR',
                                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                onPressed: _openQrPairingDialog,
                              )
                            else ...[
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: cs.error,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                ),
                                icon: const Icon(Icons.link_off_rounded, size: 16),
                                label: Text(
                                  widget.isAr ? 'فك الارتباط' : 'Unlink',
                                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                onPressed: _isRestarting ? null : _logoutCurrentNumber,
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: cs.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                ),
                                icon: const Icon(Icons.screenshot_monitor_rounded, size: 16),
                                label: Text(
                                  widget.isAr ? 'شاشة حية' : 'Live Screen',
                                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => WhatsAppScreenshotDialog(
                                      config: _buildConfigFromForm(),
                                      strings: widget.strings,
                                      isAr: widget.isAr,
                                    ),
                                  );
                                },
                              ),
                            ],
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: cs.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              ),
                              icon: _isRestarting
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.restart_alt_rounded, size: 16),
                              label: Text(
                                widget.isAr ? 'إعادة تشغيل' : 'Restart',
                                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              onPressed: _isRestarting ? null : _restartInstance,
                            ),
                          ],
                        ],
                      ),

                      // Live Statistics breakdown (WAHA Real-time API Hub)
                      if (_liveStats != null) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${_liveStats!.sentCount}',
                                      style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: cs.primary),
                                    ),
                                    Text(
                                      widget.isAr ? 'المرسلة' : 'Sent',
                                      style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${_liveStats!.queueCount}',
                                      style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: cs.secondary),
                                    ),
                                    Text(
                                      widget.isAr ? 'في الانتظار' : 'In Queue',
                                      style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${_liveStats!.unsentCount + _liveStats!.invalidCount}',
                                      style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: cs.error),
                                    ),
                                    Text(
                                      widget.isAr ? 'لم تُسلّم' : 'Unsent',
                                      style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              // M3 Connected Action Buttons Bar (اختبار الاتصال & حفظ الإعدادات)
              M3ConnectedActionGroup(
                height: 48,
                borderRadius: 14,
                isExpanded: true,
                actions: [
                  M3ConnectedActionItem(
                    label: strings.testGatewayConnection,
                    icon: _isTesting ? null : Icons.wifi_tethering_rounded,
                    iconWidget: _isTesting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          )
                        : null,
                    onPressed: _isTesting ? null : _testConnection,
                  ),
                  M3ConnectedActionItem(
                    label: strings.saveGatewaySettings,
                    icon: Icons.check_circle_rounded,
                    isPrimary: true,
                    onPressed: _saveAndClose,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
