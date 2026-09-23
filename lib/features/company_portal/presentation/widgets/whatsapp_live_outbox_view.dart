import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../core/localization/app_strings.dart';
import '../../domain/whatsapp_gateway_config_model.dart';
import '../../domain/whatsapp_gateway_service.dart';
import 'whatsapp_campaign_dispatcher_dialog.dart';

/// Live WhatsApp Gateway Outbox & Message Delivery Log View
class WhatsAppLiveOutboxView extends StatefulWidget {
  final WhatsAppGatewayConfigModel gatewayConfig;
  final String? companySlug;
  final AppStrings strings;
  final bool isAr;
  final VoidCallback onOpenSettings;
  final List<CustomerCampaignContact>? customerContacts;

  const WhatsAppLiveOutboxView({
    super.key,
    required this.gatewayConfig,
    this.companySlug,
    required this.strings,
    required this.isAr,
    required this.onOpenSettings,
    this.customerContacts,
  });

  @override
  State<WhatsAppLiveOutboxView> createState() => _WhatsAppLiveOutboxViewState();
}

class _WhatsAppLiveOutboxViewState extends State<WhatsAppLiveOutboxView> {
  final _service = WhatsAppGatewayService();

  String _selectedStatus = 'all';
  int _currentPage = 1;
  final int _limit = 20;

  bool _isLoading = false;
  WhatsAppOutboxPageResult _pageResult = const WhatsAppOutboxPageResult();
  WhatsAppGatewayStats? _stats;

  /// Set of message IDs currently expanded to view multi-line content
  final Set<String> _expandedMessageIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void didUpdateWidget(covariant WhatsAppLiveOutboxView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gatewayConfig.instanceId != widget.gatewayConfig.instanceId ||
        oldWidget.gatewayConfig.apiToken != widget.gatewayConfig.apiToken) {
      _loadMessages();
    }
  }

  Future<void> _loadMessages() async {
    if (!widget.gatewayConfig.isConfigured) {
      return;
    }

    setState(() => _isLoading = true);

    final statsFuture = _service.fetchStatistics(widget.gatewayConfig);
    final messagesFuture = _service.fetchMessagesList(
      config: widget.gatewayConfig,
      status: _selectedStatus,
      page: _currentPage,
      limit: _limit,
    );

    final results = await Future.wait([statsFuture, messagesFuture]);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _stats = results[0] as WhatsAppGatewayStats?;
        _pageResult = results[1] as WhatsAppOutboxPageResult;
      });
    }
  }

  Future<void> _resendMessage(WhatsAppOutboxMessage msg) async {
    final phone = _resolveDisplayPhone(msg);
    if (phone.isEmpty) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          widget.isAr ? 'جارٍ إعادة إرسال الرسالة إلى $phone...' : 'Resending message to $phone...',
          style: GoogleFonts.cairo(),
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    final result = await _service.sendSingleMessage(
      config: widget.gatewayConfig,
      toPhone: phone,
      messageText: msg.body,
    );

    if (mounted) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            result.isSuccess
                ? (widget.isAr ? 'تمت إعادة الإرسال بنجاح' : 'Message resent successfully')
                : (widget.isAr ? 'فشل إعادة الإرسال: ${result.error}' : 'Resend failed: ${result.error}'),
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: result.isSuccess ? const Color(0xFF198754) : Colors.red,
        ),
      );
      if (result.isSuccess) {
        _loadMessages();
      }
    }
  }

  /// Resolves the contact name from WhatsApp or matched customer records
  String _resolveContactName(WhatsAppOutboxMessage msg) {
    if (msg.contactName.isNotEmpty && !msg.contactName.startsWith('+')) {
      return msg.contactName;
    }
    // Check against campaign customer contacts if available
    if (widget.customerContacts != null && widget.customerContacts!.isNotEmpty) {
      final clean = WhatsAppGatewayService.formatInternationalPhone(msg.toPhone);
      final match = widget.customerContacts!.where((c) => c.cleanPhone == clean || c.rawPhone == msg.toPhone).firstOrNull;
      if (match != null && match.name.isNotEmpty) {
        return match.name;
      }
    }
    return WhatsAppGatewayService.getDiscoveredContactName(msg.toPhone) ?? '';
  }

  /// Resolves the actual mobile phone number
  String _resolveDisplayPhone(WhatsAppOutboxMessage msg) {
    if (msg.toPhone.isNotEmpty && !msg.toPhone.contains('@') && !msg.isGroup) {
      return msg.toPhone;
    }
    if (widget.customerContacts != null) {
      final match = widget.customerContacts!.where((c) => c.name == msg.contactName).firstOrNull;
      if (match != null) return match.rawPhone;
    }
    return msg.toPhone;
  }

  /// Formats phone numbers nicely for visual presentation (e.g. +20 121 185 7725)
  static String _formatDisplayPhone(String phone) {
    if (phone.isEmpty) return '—';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('20')) {
      return '+${digits.substring(0, 2)} ${digits.substring(2, 5)} ${digits.substring(5, 8)} ${digits.substring(8)}';
    } else if (digits.length == 11 && digits.startsWith('01')) {
      return '${digits.substring(0, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}';
    } else if (digits.isNotEmpty) {
      return '+$digits';
    }
    return phone;
  }

  void _showMessageDetails(WhatsAppOutboxMessage msg, ColorScheme cs) {
    final contactName = _resolveContactName(msg);
    final displayPhone = _resolveDisplayPhone(msg);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF198754), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.isAr ? 'تفاصيل رسالة الواتساب' : 'WhatsApp Message Details',
                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow(
                  label: widget.isAr ? 'المعرف (ID):' : 'Message ID:',
                  value: '#${msg.id}',
                  cs: cs,
                ),
                if (contactName.isNotEmpty)
                  _buildDetailRow(
                    label: widget.isAr ? 'اسم المستلم:' : 'Recipient Name:',
                    value: contactName,
                    cs: cs,
                  ),
                _buildDetailRow(
                  label: widget.isAr ? 'رقم الهاتف:' : 'Phone Number:',
                  value: _formatDisplayPhone(displayPhone),
                  cs: cs,
                  isPhone: true,
                ),
                _buildDetailRow(
                  label: widget.isAr ? 'الحالة:' : 'Status:',
                  value: _getStatusLabel(msg.status),
                  cs: cs,
                  badgeColor: _getStatusColor(msg.status),
                ),
                if (msg.sentAt != null)
                  _buildDetailRow(
                    label: widget.isAr ? 'تاريخ الإرسال:' : 'Sent At:',
                    value: intl.DateFormat('yyyy/MM/dd - hh:mm a').format(msg.sentAt!),
                    cs: cs,
                  ),
                const SizedBox(height: 12),
                Text(
                  widget.isAr ? 'نص الرسالة:' : 'Message Text:',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: SelectableText(
                    msg.body,
                    style: GoogleFonts.cairo(fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(widget.isAr ? 'إغلاق' : 'Close', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF198754)),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(widget.isAr ? 'إعادة الإرسال' : 'Resend', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.of(ctx).pop();
              _resendMessage(msg);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required ColorScheme cs,
    bool isPhone = false,
    Color? badgeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: badgeColor != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      value,
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: badgeColor),
                    ),
                  )
                : Directionality(
                    textDirection: isPhone ? TextDirection.ltr : Directionality.of(context),
                    child: Text(
                      value,
                      style: isPhone
                          ? GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.bold)
                          : GoogleFonts.cairo(fontSize: 13),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'sent':
        return widget.isAr ? 'مرسلة بنجاح' : 'Sent';
      case 'received':
        return widget.isAr ? 'واردة (مستلمة)' : 'Received';
      case 'queue':
        return widget.isAr ? 'في الانتظار' : 'In Queue';
      case 'unsent':
        return widget.isAr ? 'لم تُرسل' : 'Unsent';
      case 'invalid':
        return widget.isAr ? 'رقم خاطئ / غير صالح' : 'Invalid Number';
      case 'expired':
        return widget.isAr ? 'منتهية الصلاحية' : 'Expired';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'sent':
        return const Color(0xFF198754);
      case 'received':
        return Colors.teal.shade700;
      case 'queue':
        return Colors.blue.shade700;
      case 'unsent':
        return Colors.orange.shade800;
      case 'invalid':
        return Colors.red.shade700;
      case 'expired':
        return Colors.grey.shade700;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'sent':
        return Icons.done_all_rounded;
      case 'received':
        return Icons.call_received_rounded;
      case 'queue':
        return Icons.hourglass_top_rounded;
      case 'unsent':
        return Icons.pause_circle_outline_rounded;
      case 'invalid':
        return Icons.highlight_off_rounded;
      case 'expired':
        return Icons.timer_off_outlined;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 768;

    if (!widget.gatewayConfig.isConfigured) {
      return Container(
        margin: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: 24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 54, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 14),
              Text(
                widget.isAr ? 'بوابة الواتساب غير مضبوطة' : 'WhatsApp Gateway Not Configured',
                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                widget.isAr ? 'يرجى إدخال معرف الجلسة ومفتاح الوصول لبدء سحب سجل الرسائل' : 'Please configure Instance ID and API Token to load message logs',
                style: GoogleFonts.cairo(fontSize: 13, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF198754)),
                icon: const Icon(Icons.settings_suggest_rounded, size: 18),
                label: Text(widget.isAr ? 'ضبط إعدادات البوابة الآن' : 'Configure Gateway Now', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: widget.onOpenSettings,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Live Gateway Overview Cards
          _buildLiveStatsRow(cs, isMobile),
          const SizedBox(height: 16),

          // 2. Status Filter Bar & Refresh Button
          _buildFilterToolbar(cs, isMobile),
          const SizedBox(height: 16),

          // 3. Messages Data Table / Cards
          if (_isLoading)
            Container(
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2.5),
                    SizedBox(height: 16),
                    Text('جارٍ جلب سجل الرسائل المباشر من السيرفر...'),
                  ],
                ),
              ),
            )
          else if (_pageResult.messages.isEmpty)
            Container(
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Text(
                      widget.isAr ? 'لا توجد رسائل مسجلة بهذه الحالة' : 'No messages found for this status',
                      style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else if (isMobile)
            _buildMobileMessagesList(cs)
          else
            _buildDesktopMessagesTable(cs),
        ],
      ),
    );
  }

  Widget _buildLiveStatsRow(ColorScheme cs, bool isMobile) {
    final sent = _stats?.sentCount ?? 0;
    final queue = _stats?.queueCount ?? 0;
    final unsent = _stats?.unsentCount ?? 0;
    final invalid = _stats?.invalidCount ?? 0;
    final expired = _stats?.expiredCount ?? 0;

    final statItems = [
      _StatCardData(
        title: widget.isAr ? 'المرسلة بنجاح' : 'Sent',
        count: '$sent',
        color: const Color(0xFF198754),
        icon: Icons.mark_chat_read_rounded,
      ),
      _StatCardData(
        title: widget.isAr ? 'في الانتظار' : 'In Queue',
        count: '$queue',
        color: Colors.blue.shade700,
        icon: Icons.hourglass_top_rounded,
      ),
      _StatCardData(
        title: widget.isAr ? 'لم تُرسل' : 'Unsent',
        count: '$unsent',
        color: Colors.orange.shade800,
        icon: Icons.pause_circle_outline_rounded,
      ),
      _StatCardData(
        title: widget.isAr ? 'أرقام خاطئة' : 'Invalid',
        count: '$invalid',
        color: Colors.red.shade700,
        icon: Icons.highlight_off_rounded,
      ),
      _StatCardData(
        title: widget.isAr ? 'منتهية الصلاحية' : 'Expired',
        count: '$expired',
        color: Colors.grey.shade700,
        icon: Icons.timer_off_outlined,
      ),
    ];

    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: statItems.map((item) {
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _buildStatCard(item, cs, fixedWidth: 150),
            );
          }).toList(),
        ),
      );
    }

    return Row(
      children: statItems.map((item) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildStatCard(item, cs),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatCard(_StatCardData item, ColorScheme cs, {double? fixedWidth}) {
    return Container(
      width: fixedWidth,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: item.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, color: item.color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.count,
                  style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.bold, color: item.color),
                ),
                Text(
                  item.title,
                  style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterToolbar(ColorScheme cs, bool isMobile) {
    final filters = [
      {'id': 'all', 'label': widget.isAr ? 'الكل' : 'All'},
      {'id': 'sent', 'label': widget.isAr ? 'المرسلة' : 'Sent'},
      {'id': 'received', 'label': widget.isAr ? 'الواردة' : 'Received'},
      {'id': 'queue', 'label': widget.isAr ? 'في الانتظار' : 'In Queue'},
      {'id': 'unsent', 'label': widget.isAr ? 'غير مرسلة' : 'Unsent'},
      {'id': 'invalid', 'label': widget.isAr ? 'خاطئة' : 'Invalid'},
      {'id': 'expired', 'label': widget.isAr ? 'Expired' : 'Expired'},
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters.map((f) {
                  final isSelected = _selectedStatus == f['id'];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Text(f['label']!),
                      selected: isSelected,
                      selectedColor: cs.primary,
                      labelStyle: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? cs.onPrimary : cs.onSurface,
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _selectedStatus = f['id']!;
                            _currentPage = 1;
                          });
                          _loadMessages();
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: widget.isAr ? 'تحديث السجل فورياً' : 'Refresh Log',
            icon: _isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _isLoading ? null : _loadMessages,
          ),
        ],
      ),
    );
  }

  /// Builds the Recipient cell showing Contact Name, Group Badge, and clean Phone Number
  Widget _buildRecipientCell(WhatsAppOutboxMessage msg, ColorScheme cs) {
    if (msg.isGroup) {
      final name = msg.groupName ?? msg.contactName;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.groups_rounded, size: 13, color: cs.onSecondaryContainer),
                const SizedBox(width: 4),
                Text(
                  widget.isAr ? 'مجموعة' : 'Group',
                  style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSecondaryContainer),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name.isNotEmpty ? name : (widget.isAr ? 'مجموعة واتساب' : 'WhatsApp Group'),
              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    final displayName = _resolveContactName(msg);
    final displayPhone = _resolveDisplayPhone(msg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (displayName.isNotEmpty && !displayName.startsWith('+')) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_circle_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  displayName,
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
        ],
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatDisplayPhone(displayPhone),
                style: GoogleFonts.robotoMono(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 13),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                tooltip: widget.isAr ? 'نسخ الرقم' : 'Copy phone',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: displayPhone));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(widget.isAr ? 'تم نسخ الرقم' : 'Phone copied'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds the Animated Expandable Message Text component (More / Less)
  Widget _buildAnimatedMessageBody(WhatsAppOutboxMessage msg, ColorScheme cs) {
    final text = msg.body.trim();
    if (text.isEmpty) {
      return Text(
        widget.isAr ? '(رسالة بدون نص)' : '(Empty message)',
        style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
      );
    }

    final isLong = text.length > 55 || text.contains('\n');
    final isExpanded = _expandedMessageIds.contains(msg.id);

    if (!isLong) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.cairo(fontSize: 12.5, height: 1.4, color: cs.onSurface),
        ),
      );
    }

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 260),
      firstCurve: Curves.easeInOutCubic,
      secondCurve: Curves.easeInOutCubic,
      sizeCurve: Curves.easeInOutCubic,
      crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      firstChild: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(fontSize: 12.5, height: 1.4, color: cs.onSurface),
            ),
          ),
          const SizedBox(height: 2),
          InkWell(
            onTap: () {
              setState(() {
                _expandedMessageIds.add(msg.id);
              });
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.isAr ? 'عرض المزيد' : 'More',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: cs.primary),
                ],
              ),
            ),
          ),
        ],
      ),
      secondChild: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: SelectableText(
              text,
              style: GoogleFonts.cairo(fontSize: 12.5, height: 1.5, color: cs.onSurface),
            ),
          ),
          InkWell(
            onTap: () {
              setState(() {
                _expandedMessageIds.remove(msg.id);
              });
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.isAr ? 'عرض أقل' : 'Less',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: cs.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopMessagesTable(ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minTableWidth = math.max(constraints.maxWidth, 1100.0);

        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    width: minTableWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Table Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 45,
                                child: Text(
                                  '#',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onSurface),
                                ),
                              ),
                              SizedBox(
                                width: 230,
                                child: Text(
                                  widget.isAr ? 'المستلم' : 'Recipient',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onSurface),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  widget.isAr ? 'نص الرسالة' : 'Message Body',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onSurface),
                                ),
                              ),
                              SizedBox(
                                width: 150,
                                child: Text(
                                  widget.isAr ? 'حالة الإرسال' : 'Delivery Status',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onSurface),
                                ),
                              ),
                              SizedBox(
                                width: 160,
                                child: Text(
                                  widget.isAr ? 'وقت الإرسال' : 'Sent Time',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onSurface),
                                ),
                              ),
                              SizedBox(
                                width: 100,
                                child: Text(
                                  widget.isAr ? 'الإجراءات' : 'Actions',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onSurface),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // Table Rows
                        ..._pageResult.messages.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final msg = entry.value;
                          final statusColor = _getStatusColor(msg.status);
                          final statusIcon = _getStatusIcon(msg.status);
                          final statusText = _getStatusLabel(msg.status);
                          final timeStr = msg.sentAt != null
                              ? intl.DateFormat('yyyy/MM/dd hh:mm a').format(msg.sentAt!)
                              : (msg.createdAt != null ? intl.DateFormat('yyyy/MM/dd hh:mm a').format(msg.createdAt!) : '—');
                          final isEven = idx % 2 == 0;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: isEven ? Colors.transparent : cs.surfaceContainerHighest.withValues(alpha: 0.15),
                              border: Border(
                                bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.25)),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 45,
                                  child: Tooltip(
                                    message: widget.isAr ? 'معرف الرسالة: ${msg.id}' : 'Message ID: ${msg.id}',
                                    child: Text(
                                      '${idx + 1}',
                                      style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 230,
                                  child: _buildRecipientCell(msg, cs),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: _buildAnimatedMessageBody(msg, cs),
                                  ),
                                ),
                                SizedBox(
                                  width: 150,
                                  child: Align(
                                    alignment: widget.isAr ? Alignment.centerRight : Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(statusIcon, color: statusColor, size: 15),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              statusText,
                                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 160,
                                  child: Text(
                                    timeStr,
                                    style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
                                  ),
                                ),
                                SizedBox(
                                  width: 100,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.visibility_outlined, size: 18),
                                        tooltip: widget.isAr ? 'معاينة الرسالة' : 'View Message',
                                        onPressed: () => _showMessageDetails(msg, cs),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.refresh_rounded, size: 18),
                                        tooltip: widget.isAr ? 'إعادة الإرسال' : 'Resend',
                                        color: const Color(0xFF198754),
                                        onPressed: () => _resendMessage(msg),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),

                // Pagination Controls Footer
                _buildOutboxPaginationFooter(cs),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileMessagesList(ColorScheme cs) {
    return Column(
      children: [
        ..._pageResult.messages.map((msg) {
          final statusColor = _getStatusColor(msg.status);
          final statusIcon = _getStatusIcon(msg.status);
          final statusText = _getStatusLabel(msg.status);
          final timeStr = msg.sentAt != null
              ? intl.DateFormat('yyyy/MM/dd hh:mm a').format(msg.sentAt!)
              : (msg.createdAt != null ? intl.DateFormat('yyyy/MM/dd hh:mm a').format(msg.createdAt!) : '—');

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: _buildRecipientCell(msg, cs),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, color: statusColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildAnimatedMessageBody(msg, cs),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        timeStr,
                        style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          onPressed: () => _showMessageDetails(msg, cs),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF198754)),
                          onPressed: () => _resendMessage(msg),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        _buildOutboxPaginationFooter(cs),
      ],
    );
  }

  Widget _buildOutboxPaginationFooter(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.isAr
                ? 'إجمالي الرسائل: ${_pageResult.total}'
                : 'Total Messages: ${_pageResult.total}',
            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _currentPage > 1
                    ? () {
                        setState(() => _currentPage--);
                        _loadMessages();
                      }
                    : null,
              ),
              Text(
                '${_pageResult.page} / ${_pageResult.totalPages > 0 ? _pageResult.totalPages : 1}',
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: _currentPage < _pageResult.totalPages
                    ? () {
                        setState(() => _currentPage++);
                        _loadMessages();
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCardData {
  final String title;
  final String count;
  final Color color;
  final IconData icon;

  _StatCardData({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
  });
}
