import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/localization/app_strings.dart';
import '../../domain/whatsapp_gateway_config_model.dart';
import '../../domain/whatsapp_gateway_service.dart';

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

  bool _isTesting = false;
  bool _isRestarting = false;
  WhatsAppGatewayConnectionStatus? _testStatus;
  WhatsAppGatewayStats? _liveStats;

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.currentConfig.provider;
    _instanceIdController = TextEditingController(
      text: widget.currentConfig.instanceId.isNotEmpty ? widget.currentConfig.instanceId : 'instance190005',
    );
    _apiTokenController = TextEditingController(
      text: widget.currentConfig.apiToken.isNotEmpty ? widget.currentConfig.apiToken : 'v699gpqwmv242cgq',
    );
    _customEndpointController = TextEditingController(text: widget.currentConfig.customEndpointUrl);
    _delaySeconds = widget.currentConfig.delayBetweenMessagesSeconds.clamp(1, 15);
    _isEnabled = widget.currentConfig.isEnabled;
  }

  @override
  void dispose() {
    _instanceIdController.dispose();
    _apiTokenController.dispose();
    _customEndpointController.dispose();
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
    if (status.isConnected && tempConfig.provider == WhatsAppGatewayProvider.ultraMsg) {
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
              if (_selectedProvider != WhatsAppGatewayProvider.custom) ...[
                // Instance ID
                TextField(
                  controller: _instanceIdController,
                  decoration: InputDecoration(
                    labelText: strings.instanceIdLabel,
                    hintText: _selectedProvider == WhatsAppGatewayProvider.ultraMsg
                        ? 'مثال: instance12345'
                        : 'مثال: 1101823901',
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

              const SizedBox(height: 18),

              // Connection Test Status Box
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
                          if (_testStatus!.isConnected && _selectedProvider == WhatsAppGatewayProvider.ultraMsg)
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
                      ),

                      // Live Statistics breakdown (UltraMsg Real-time API Hub)
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
