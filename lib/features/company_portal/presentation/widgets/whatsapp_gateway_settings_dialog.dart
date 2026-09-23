import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/localization/app_strings.dart';
import '../../domain/whatsapp_ai_auto_reply_service.dart';
import '../../domain/whatsapp_gateway_config_model.dart';
import '../../domain/whatsapp_gateway_service.dart';
import 'whatsapp_screenshot_dialog.dart';

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
      text: widget.currentConfig.apiToken.isNotEmpty ? widget.currentConfig.apiToken : 'tashil_secret_token_2026',
    );
    _customEndpointController = TextEditingController(
      text: widget.currentConfig.customEndpointUrl.isNotEmpty ? widget.currentConfig.customEndpointUrl : 'http://76.13.14.23:3000',
    );
    _delaySeconds = widget.currentConfig.delayBetweenMessagesSeconds.clamp(1, 15);
    _isEnabled = widget.currentConfig.isEnabled;
    _enableTypingSimulation = widget.currentConfig.enableTypingSimulation;
    _typingDurationSeconds = widget.currentConfig.typingDurationSeconds.clamp(1, 10);
    _enableAiAutoReply = widget.currentConfig.enableAiAutoReply;
    _aiCustomSystemPromptController = TextEditingController(
      text: widget.currentConfig.aiCustomSystemPrompt,
    );
  }

  @override
  void dispose() {
    _instanceIdController.dispose();
    _apiTokenController.dispose();
    _customEndpointController.dispose();
    _aiCustomSystemPromptController.dispose();
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
          backgroundColor: success ? const Color(0xFF198754) : Colors.red,
        ),
      );
      if (success) {
        _testConnection();
      }
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
                const Icon(Icons.smart_toy_rounded, color: Color(0xFF6750A4)),
                const SizedBox(width: 8),
                Text(
                  widget.isAr ? 'محاكاة الرد الآلي الذكي (Gemini 3.7 Flash)' : 'AI Auto-Reply Simulator',
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
                        color: const Color(0xFF198754).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF198754)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.mark_chat_read_rounded, size: 16, color: Color(0xFF0F5132)),
                              const SizedBox(width: 6),
                              Text(
                                widget.isAr ? 'رد الذكاء الاصطناعي المُرسل للعميل:' : 'AI Generated WhatsApp Reply:',
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F5132)),
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
          backgroundColor: const Color(0xFF198754),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final strings = widget.strings;
    final isMobile = MediaQuery.of(context).size.width < 700;

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
                      color: const Color(0xFF25D366).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.cloud_sync_rounded, size: 28, color: Color(0xFF198754)),
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
              DropdownButtonFormField<WhatsAppGatewayProvider>(
                initialValue: _selectedProvider,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.hub_rounded, size: 20),
                  filled: true,
                  fillColor: cs.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
                items: WhatsAppGatewayProvider.values.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(p.displayName, style: GoogleFonts.cairo(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedProvider = val;
                      _testStatus = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Provider Fields
              if (_selectedProvider == WhatsAppGatewayProvider.waha) ...[
                // WAHA Endpoint URL
                TextField(
                  controller: _customEndpointController,
                  decoration: InputDecoration(
                    labelText: widget.isAr ? 'عنوان سيرفر WAHA (Endpoint URL)' : 'WAHA Server URL',
                    hintText: 'http://76.13.14.23:3000',
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
                    hintText: 'tashil_secret_token_2026',
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
                            const Icon(Icons.shield_outlined, size: 18, color: Color(0xFF198754)),
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
                      activeColor: const Color(0xFF198754),
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
                            color: const Color(0xFF198754).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.keyboard_outlined, color: Color(0xFF198754), size: 20),
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
                          activeThumbColor: const Color(0xFF198754),
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
                        activeColor: const Color(0xFF198754),
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
                            color: const Color(0xFF6750A4).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.smart_toy_outlined, color: Color(0xFF6750A4), size: 20),
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
                                      color: const Color(0xFF6750A4).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Gemini 3.7 Flash',
                                      style: GoogleFonts.robotoMono(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF6750A4)),
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
                          activeThumbColor: const Color(0xFF6750A4),
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
                        ? const Color(0xFF198754).withValues(alpha: 0.12)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _testStatus!.isConnected ? const Color(0xFF198754) : Colors.red,
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
                            color: _testStatus!.isConnected ? const Color(0xFF198754) : Colors.red,
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
                                    color: _testStatus!.isConnected ? const Color(0xFF0F5132) : Colors.red.shade900,
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
                                    style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F5132)),
                                  ),
                              ],
                            ),
                          ),
                          if (_testStatus!.isConnected && _selectedProvider == WhatsAppGatewayProvider.waha) ...[
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: cs.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              icon: const Icon(Icons.screenshot_monitor_rounded, size: 18),
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
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: cs.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              icon: _isRestarting
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.restart_alt_rounded, size: 18),
                              label: Text(
                                widget.isAr ? 'إعادة تشغيل الجلسة' : 'Restart Session',
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
                                      style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF198754)),
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
                                      style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
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
                                      style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
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

              // Buttons Bar
              if (isMobile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _isTesting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.wifi_tethering_rounded, size: 20),
                      label: Text(strings.testGatewayConnection, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                      onPressed: _isTesting ? null : _testConnection,
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF198754),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.save_rounded, size: 20),
                      label: Text(strings.saveGatewaySettings, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                      onPressed: _saveAndClose,
                    ),
                  ],
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
                        icon: _isTesting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_tethering_rounded, size: 20),
                        label: Text(strings.testGatewayConnection, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        onPressed: _isTesting ? null : _testConnection,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF198754),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.save_rounded, size: 20),
                        label: Text(strings.saveGatewaySettings, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        onPressed: _saveAndClose,
                      ),
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
