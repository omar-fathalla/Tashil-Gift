import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../../core/widgets/m3_list_tile.dart';
import '../../domain/whatsapp_gateway_config_model.dart';
import '../../domain/whatsapp_gateway_service.dart';
import '../../domain/whatsapp_webhook_admin_models.dart';
import '../../domain/whatsapp_webhook_admin_repository.dart';

Color webhookStatusBackground(ColorScheme scheme, String key) {
  switch (key) {
    case 'verified':
    case 'registered':
      return scheme.primaryContainer;
    case 'pending_review':
      return scheme.tertiaryContainer;
    case 'verified_without_prize':
      return scheme.secondaryContainer;
    case 'rejected':
    case 'not_allowed':
    case 'error':
      return scheme.errorContainer;
    default:
      return scheme.surfaceContainerHighest;
  }
}

Color webhookStatusForeground(ColorScheme scheme, String key) {
  switch (key) {
    case 'verified':
    case 'registered':
      return scheme.onPrimaryContainer;
    case 'pending_review':
      return scheme.onTertiaryContainer;
    case 'verified_without_prize':
      return scheme.onSecondaryContainer;
    case 'rejected':
    case 'not_allowed':
    case 'error':
      return scheme.onErrorContainer;
    default:
      return scheme.onSurfaceVariant;
  }
}

/// Staff control page for the WAHA webhook, embedded in the company portal.
class WhatsAppWebhookInboxView extends ConsumerStatefulWidget {
  final bool? canManageOverride;
  final WhatsAppGatewayConfigModel? gatewayConfig;
  final List<WhatsappCampaignOption> campaigns;
  final String companySlug;
  final Future<Map<String, dynamic>?> Function()? loadSession;

  const WhatsAppWebhookInboxView({
    super.key,
    this.canManageOverride,
    this.gatewayConfig,
    this.campaigns = const [],
    this.companySlug = '',
    this.loadSession,
  });

  @override
  ConsumerState<WhatsAppWebhookInboxView> createState() => _WhatsAppWebhookInboxViewState();
}

class _WhatsAppWebhookInboxViewState extends ConsumerState<WhatsAppWebhookInboxView> {
  Map<String, dynamic>? _session;
  bool _sessionLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final Map<String, dynamic>? details;
      if (widget.loadSession != null) {
        details = await widget.loadSession!();
      } else if (widget.gatewayConfig != null) {
        details = await WhatsAppGatewayService().fetchSessionDetails(widget.gatewayConfig!);
      } else {
        details = null;
      }
      if (!mounted) return;
      setState(() {
        _session = details;
        _sessionLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sessionLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(ref);
    final bool allowed = widget.canManageOverride ?? ref.watch(isAdminProvider);
    if (!allowed) {
      return _StaffOnlyNotice(message: strings.webhookStaffOnly);
    }

    final config = ref.watch(whatsappWebhookConfigProvider);
    final inbox = ref.watch(whatsappInboundMessagesProvider);
    final links = ref.watch(whatsappSenderLinksProvider);
    final registrations = ref.watch(whatsappCampaignRegistrationsProvider);
    final acks = ref.watch(whatsappAckCountsProvider);
    final repo = ref.watch(whatsappWebhookRepositoryProvider);

    if (config.isLoading || inbox.isLoading || links.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final error = config.error ?? inbox.error ?? links.error;
    if (error != null) {
      return _StaffOnlyNotice(message: strings.operationFailed('$error'));
    }

    return WhatsAppWebhookInboxBody(
      strings: strings,
      config: config.value ?? const WhatsappWebhookConfig(),
      messages: inbox.value ?? const [],
      links: links.value ?? const [],
      registrations: registrations.value ?? const [],
      ackCounts: acks.value ?? const {},
      campaigns: widget.campaigns,
      companySlug: widget.companySlug,
      sessionPhone: wahaSessionPhone(_session),
      sessionStatus: _sessionLoaded ? wahaSessionStatus(_session) : '',
      onUpdateConfig: repo.updateConfig,
      onUpsertLink: repo.upsertLink,
      onDeleteLink: repo.deleteLink,
    );
  }
}

class WhatsAppWebhookInboxBody extends StatefulWidget {
  final AppStrings strings;
  final WhatsappWebhookConfig config;
  final List<WhatsappInboundMessage> messages;
  final List<WhatsappSenderLink> links;
  final List<WhatsappCampaignRegistration> registrations;
  final Map<String, int> ackCounts;
  final List<WhatsappCampaignOption> campaigns;
  final String companySlug;
  final String sessionPhone;
  final String sessionStatus;
  final Future<void> Function(Map<String, dynamic> data) onUpdateConfig;
  final Future<void> Function(Map<String, dynamic> data) onUpsertLink;
  final Future<void> Function(String phone) onDeleteLink;

  const WhatsAppWebhookInboxBody({
    super.key,
    required this.strings,
    required this.config,
    required this.messages,
    required this.links,
    required this.registrations,
    required this.ackCounts,
    required this.campaigns,
    required this.companySlug,
    required this.sessionPhone,
    required this.sessionStatus,
    required this.onUpdateConfig,
    required this.onUpsertLink,
    required this.onDeleteLink,
  });

  @override
  State<WhatsAppWebhookInboxBody> createState() => _WhatsAppWebhookInboxBodyState();
}

class _WhatsAppWebhookInboxBodyState extends State<WhatsAppWebhookInboxBody> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late bool _enabled;
  late bool _autoReplies;
  late bool _allowListOnly;
  late final TextEditingController _number;
  late final TextEditingController _displayName;
  late final TextEditingController _search;
  late final Map<String, TextEditingController> _templates;
  late final TextEditingController _linkPhone;
  late final TextEditingController _linkPrize;
  late final TextEditingController _linkName;
  late final TextEditingController _joinCode;
  String _filter = 'all';
  String? _linkCampaignId;
  bool _linkActive = true;
  String? _inviteCampaignId;
  bool _selfRegister = false;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      setState(() {});
    });
    _number = TextEditingController();
    _displayName = TextEditingController();
    _search = TextEditingController();
    _templates = {
      for (final key in kWhatsappReplyTemplateKeys) key: TextEditingController(),
    };
    _linkPhone = TextEditingController();
    _linkPrize = TextEditingController();
    _linkName = TextEditingController();
    _joinCode = TextEditingController();
    _adopt(widget.config, widget.registrations);
  }

  void _adopt(WhatsappWebhookConfig config, List<WhatsappCampaignRegistration> registrations) {
    _enabled = config.enabled;
    _autoReplies = config.autoRepliesEnabled;
    _allowListOnly = config.allowListOnly;
    _number.text = config.businessNumber;
    _displayName.text = config.businessDisplayName;
    for (final key in kWhatsappReplyTemplateKeys) {
      _templates[key]!.text = config.template(key);
    }
    if (_inviteCampaignId == null && widget.campaigns.isNotEmpty) {
      _inviteCampaignId = widget.campaigns.first.id;
      _pullInvite(registrations);
    }
    if (_linkCampaignId == null && widget.campaigns.isNotEmpty) {
      _linkCampaignId = widget.campaigns.first.id;
    }
  }

  void _pullInvite(List<WhatsappCampaignRegistration> registrations) {
    final id = _inviteCampaignId;
    if (id == null) return;
    WhatsappCampaignRegistration? match;
    for (final item in registrations) {
      if (item.campaignId == id) match = item;
    }
    _selfRegister = match?.selfRegistrationEnabled ?? false;
    if (_joinCode.text.isEmpty) _joinCode.text = match?.joinCode ?? '';
  }

  @override
  void didUpdateWidget(WhatsAppWebhookInboxBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_busy != null) return;
    if (_enabled == oldWidget.config.enabled) _enabled = widget.config.enabled;
    if (_autoReplies == oldWidget.config.autoRepliesEnabled) _autoReplies = widget.config.autoRepliesEnabled;
    if (_allowListOnly == oldWidget.config.allowListOnly) _allowListOnly = widget.config.allowListOnly;
    if (_number.text == oldWidget.config.businessNumber) _number.text = widget.config.businessNumber;
    if (_displayName.text == oldWidget.config.businessDisplayName) {
      _displayName.text = widget.config.businessDisplayName;
    }
    for (final key in kWhatsappReplyTemplateKeys) {
      if (_templates[key]!.text == oldWidget.config.template(key)) {
        _templates[key]!.text = widget.config.template(key);
      }
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _number.dispose();
    _displayName.dispose();
    _search.dispose();
    for (final controller in _templates.values) {
      controller.dispose();
    }
    _linkPhone.dispose();
    _linkPrize.dispose();
    _linkName.dispose();
    _joinCode.dispose();
    super.dispose();
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    setState(() => _busy = key);
    try {
      await action().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _snack(widget.strings.success, error: false);
    } catch (error) {
      if (!mounted) return;
      _snack(widget.strings.operationFailed('$error'), error: true);
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _snack(String message, {required bool error}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? scheme.error : scheme.inverseSurface,
      ),
    );
  }

  Future<void> _toggle({
    required String key,
    required bool value,
    required void Function(bool next) apply,
    required bool Function() read,
  }) async {
    final previous = read();
    setState(() => apply(value));
    try {
      await _run(key, () => widget.onUpdateConfig({key: value}));
    } catch (_) {
      if (mounted) setState(() => apply(previous));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final height = MediaQuery.sizeOf(context).height;
    return SizedBox(
      height: height < 640 ? 640 : height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: [
              Tab(text: strings.webhookTabControl),
              Tab(text: strings.webhookTabInbox),
              Tab(text: strings.webhookTabReplies),
              Tab(text: strings.webhookTabNumbers),
              Tab(text: strings.webhookTabInvites),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: IndexedStack(
                index: _tabs.index,
                children: [
                  _scroll(_control(scheme, textTheme, strings)),
                  _scroll(_inbox(scheme, textTheme, strings)),
                  _scroll(_replies(scheme, textTheme, strings)),
                  _scroll(_numbers(scheme, textTheme, strings)),
                  _scroll(_invites(scheme, textTheme, strings)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scroll(Widget child) {
    return SingleChildScrollView(child: child);
  }

  Widget _control(ColorScheme scheme, TextTheme textTheme, AppStrings strings) {
    final lastEvent = formatWebhookClock(widget.config.lastEventAt);
    final liveStatus = widget.sessionStatus.isNotEmpty ? widget.sessionStatus : widget.config.lastSessionStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.webhookEnabled, style: textTheme.titleMedium),
                  subtitle: Text(strings.webhookEnabledHint, style: textTheme.bodyMedium),
                  value: _enabled,
                  onChanged: _busy != null
                      ? null
                      : (value) => _toggle(
                            key: 'enabled',
                            value: value,
                            apply: (next) => _enabled = next,
                            read: () => _enabled,
                          ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.webhookAutoReplies, style: textTheme.titleMedium),
                  subtitle: Text(strings.webhookAutoRepliesHint, style: textTheme.bodyMedium),
                  value: _autoReplies,
                  onChanged: _busy != null
                      ? null
                      : (value) => _toggle(
                            key: 'autoRepliesEnabled',
                            value: value,
                            apply: (next) => _autoReplies = next,
                            read: () => _autoReplies,
                          ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.webhookAllowListOnly, style: textTheme.titleMedium),
                  subtitle: Text(strings.webhookAllowListOnlyHint, style: textTheme.bodyMedium),
                  value: _allowListOnly,
                  onChanged: _busy != null
                      ? null
                      : (value) => _toggle(
                            key: 'allowListOnly',
                            value: value,
                            apply: (next) => _allowListOnly = next,
                            read: () => _allowListOnly,
                          ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.webhookHealth, style: textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  lastEvent.isEmpty ? strings.webhookNoEventsYet : strings.webhookLastEvent(widget.config.lastEventName, lastEvent),
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(liveStatus.isEmpty ? strings.webhookSessionUnknown : liveStatus),
                      avatar: Icon(Icons.podcasts_outlined, color: scheme.onSecondaryContainer),
                      backgroundColor: scheme.secondaryContainer,
                      labelStyle: textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
                    ),
                    if (widget.sessionPhone.isNotEmpty)
                      Chip(
                        label: Text(widget.sessionPhone),
                        backgroundColor: scheme.surfaceContainerHigh,
                      ),
                  ],
                ),
                if (widget.ackCounts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(strings.webhookAckCounts, style: textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in widget.ackCounts.entries)
                        Badge(
                          backgroundColor: scheme.primaryContainer,
                          textColor: scheme.onPrimaryContainer,
                          label: Text('${entry.value}'),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8, right: 8),
                            child: Text(entry.key, style: textTheme.labelLarge),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(strings.webhookBusinessNumber, style: textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _number,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: strings.webhookBusinessNumber,
            helperText: strings.webhookBusinessNumberHint,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _displayName,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: strings.webhookDisplayName),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: _busy != null
                ? null
                : () => _run('number', () => widget.onUpdateConfig({
                      'businessNumber': _number.text,
                      'businessDisplayName': _displayName.text,
                    })),
            child: _busy == 'number'
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(strings.save),
          ),
        ),
      ],
    );
  }

  Widget _inbox(ColorScheme scheme, TextTheme textTheme, AppStrings strings) {
    final query = _search.text;
    final visible = widget.messages.where((message) {
      if (_filter != 'all' && message.verificationKey != _filter) return false;
      return inboxMatchesQuery(message, query);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchBar(
          hintText: strings.webhookSearchPhone,
          leading: const Icon(Icons.search),
          onChanged: (_) => setState(() {}),
          controller: _search,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in kWhatsappInboxFilters)
              FilterChip(
                label: Text(strings.webhookStatusLabel(key)),
                selected: _filter == key,
                onSelected: (_) => setState(() => _filter = key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(strings.webhookInboxEmpty, style: textTheme.bodyLarge, textAlign: TextAlign.center),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visible.length,
            separatorBuilder: (context, index) => const M3InsetDivider(),
            itemBuilder: (context, index) {
              final message = visible[index];
              final key = message.verificationKey;
              return ListTile(
                contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 8),
                leading: _thumbnail(message, scheme),
                title: Text(message.phone.isEmpty ? message.id : message.phone, style: textTheme.titleMedium),
                subtitle: Text(
                  [
                    formatWebhookClock(message.receivedAt),
                    message.displayReceipt,
                    message.campaignId,
                    message.displayPrize,
                  ].where((part) => part.isNotEmpty).join(' · '),
                  style: textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Chip(
                  label: Text(strings.webhookStatusLabel(key)),
                  backgroundColor: webhookStatusBackground(scheme, key),
                  labelStyle: textTheme.labelLarge?.copyWith(color: webhookStatusForeground(scheme, key)),
                  visualDensity: VisualDensity.compact,
                ),
                onTap: () => _openDetail(message),
              );
            },
          ),
      ],
    );
  }

  Widget _thumbnail(WhatsappInboundMessage message, ColorScheme scheme) {
    if (message.thumbnailUrl.isEmpty) {
      return CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(Icons.receipt_long_outlined, color: scheme.onSurfaceVariant),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        message.thumbnailUrl,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => CircleAvatar(
          backgroundColor: scheme.surfaceContainerHighest,
          child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  void _openDetail(WhatsappInboundMessage message) {
    final strings = widget.strings;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final analysis = message.analysis;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(strings.webhookDetailTitle, style: textTheme.titleLarge),
              const SizedBox(height: 8),
              ListTile(
                title: Text(strings.webhookPhone),
                subtitle: Text(message.phone),
              ),
              ListTile(
                title: Text(strings.webhookStatusLabel(message.verificationKey)),
                subtitle: Text(message.reason),
              ),
              ListTile(
                title: Text(strings.webhookReceipt),
                subtitle: Text(message.displayReceipt.isEmpty ? '—' : message.displayReceipt),
              ),
              ListTile(
                title: Text(strings.webhookPrize),
                subtitle: Text(message.displayPrize.isEmpty ? '—' : message.displayPrize),
              ),
              ListTile(
                title: Text(strings.webhookCampaign),
                subtitle: Text(message.campaignId.isEmpty ? '—' : message.campaignId),
              ),
              const M3InsetDivider(),
              Text(strings.webhookAnalysis, style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('${strings.webhookVerdict}: ${analysis['verdict'] ?? '—'}', style: textTheme.bodyLarge),
              Text('${strings.webhookConfidence}: ${analysis['confidence'] ?? '—'}', style: textTheme.bodyMedium),
              Text(analysis['message']?.toString() ?? '', style: textTheme.bodyMedium),
              Text(analysis['storeChainDetected']?.toString() ?? '', style: textTheme.bodyMedium),
              Text(analysis['branchDetected']?.toString() ?? '', style: textTheme.bodyMedium),
              const SizedBox(height: 16),
              Text(strings.webhookReply, style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message.replyText.isEmpty ? strings.webhookNoReply : message.replyText,
                style: textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
              ),
              if (message.replyMessageId.isNotEmpty)
                Text(message.replyMessageId, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        );
      },
    );
  }

  Widget _replies(ColorScheme scheme, TextTheme textTheme, AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.webhookTemplateHint, style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        for (final key in kWhatsappReplyTemplateKeys) ...[
          TextField(
            controller: _templates[key],
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: strings.webhookTemplateLabel(key)),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: _busy != null
                ? null
                : () => _run('templates', () => widget.onUpdateConfig({
                      'templates': {
                        for (final key in kWhatsappReplyTemplateKeys) key: _templates[key]!.text,
                      },
                    })),
            child: _busy == 'templates'
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(strings.save),
          ),
        ),
      ],
    );
  }

  Widget _numbers(ColorScheme scheme, TextTheme textTheme, AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _linkPhone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: strings.webhookPhone),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _linkName,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: strings.webhookCustomerName),
        ),
        const SizedBox(height: 8),
        _campaignMenu(
          value: _linkCampaignId,
          onChanged: (value) => setState(() => _linkCampaignId = value),
          strings: strings,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _linkPrize,
          decoration: InputDecoration(labelText: strings.webhookPrizeOptional),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(strings.webhookNumberActive, style: textTheme.titleSmall),
          value: _linkActive,
          onChanged: (value) => setState(() => _linkActive = value),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: _busy != null ? null : _saveLink,
            child: _busy == 'link'
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(strings.save),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.links.isEmpty)
          Text(strings.webhookNoNumbers, style: textTheme.bodyLarge)
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.links.length,
            separatorBuilder: (context, index) => const M3InsetDivider(),
            itemBuilder: (context, index) {
              final link = widget.links[index];
              return ListTile(
                contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                title: Text(link.phone, style: textTheme.titleMedium),
                subtitle: Text(
                  [
                    link.campaignName.isEmpty ? link.campaignId : link.campaignName,
                    link.prizeIdentifier,
                    link.active ? strings.webhookNumberActive : strings.webhookNumberInactive,
                  ].where((part) => part.isNotEmpty).join(' · '),
                  style: textTheme.bodyMedium,
                ),
                trailing: IconButton(
                  tooltip: strings.delete,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: _busy != null ? null : () => _confirmDelete(link.phone),
                ),
                onTap: () {
                  setState(() {
                    _linkPhone.text = link.phone;
                    _linkName.text = link.displayName;
                    _linkPrize.text = link.prizeIdentifier;
                    _linkCampaignId = link.campaignId;
                    _linkActive = link.active;
                  });
                },
              );
            },
          ),
      ],
    );
  }

  Future<void> _saveLink() async {
    if (_linkPhone.text.trim().isEmpty || (_linkCampaignId ?? '').isEmpty) {
      _snack(widget.strings.requiredField, error: true);
      return;
    }
    final campaign = _campaignName(_linkCampaignId);
    try {
      await _run('link', () => widget.onUpsertLink({
            'phone': _linkPhone.text,
            'campaignId': _linkCampaignId,
            'campaignName': campaign,
            'companySlug': widget.companySlug,
            'prizeIdentifier': _linkPrize.text,
            'displayName': _linkName.text,
            'active': _linkActive,
          }));
      if (!mounted) return;
      setState(() {
        _linkPhone.clear();
        _linkName.clear();
        _linkPrize.clear();
        _linkActive = true;
      });
    } catch (_) {}
  }

  Future<void> _confirmDelete(String phone) async {
    final strings = widget.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.delete),
        content: Text(phone),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(strings.delete)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _run('delete', () => widget.onDeleteLink(phone));
    } catch (_) {}
  }

  Widget _invites(ColorScheme scheme, TextTheme textTheme, AppStrings strings) {
    final link = buildWaMeInvite(
      _number.text.isNotEmpty ? _number.text : widget.config.businessNumber,
      _joinCode.text,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.webhookInviteHelp, style: textTheme.bodyMedium),
        const SizedBox(height: 8),
        _campaignMenu(
          value: _inviteCampaignId,
          onChanged: (value) {
            setState(() {
              _inviteCampaignId = value;
              _joinCode.clear();
              _pullInvite(widget.registrations);
            });
          },
          strings: strings,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(strings.webhookSelfRegistration, style: textTheme.titleSmall),
          subtitle: Text(strings.webhookSelfRegistrationHint, style: textTheme.bodyMedium),
          value: _selfRegister,
          onChanged: (value) => setState(() => _selfRegister = value),
        ),
        TextField(
          controller: _joinCode,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: strings.webhookJoinCode),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () {
                const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
                final random = Random();
                final code = List.generate(6, (_) => alphabet[random.nextInt(alphabet.length)]).join();
                setState(() => _joinCode.text = code);
              },
              child: Text(strings.webhookGenerateCode),
            ),
            FilledButton(
              onPressed: _busy != null ? null : _saveInvite,
              child: _busy == 'invite'
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(strings.save),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (link.isEmpty)
          Text(strings.webhookInviteNeedsNumber, style: textTheme.bodyMedium)
        else ...[
          SelectableText(link, style: textTheme.bodyLarge),
          const SizedBox(height: 8),
          Center(
            child: QrImageView(
              data: link,
              size: 160,
              eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: scheme.onSurface),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: scheme.onSurface,
              ),
              backgroundColor: scheme.surface,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (!mounted) return;
                  _snack(strings.linkCopied, error: false);
                },
                child: Text(strings.copyLink),
              ),
              FilledButton.tonal(
                onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                child: Text(strings.webhookShareLink),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _saveInvite() async {
    if ((_inviteCampaignId ?? '').isEmpty) {
      _snack(widget.strings.requiredField, error: true);
      return;
    }
    try {
      await _run('invite', () => widget.onUpdateConfig({
            'campaign': {
              'campaignId': _inviteCampaignId,
              'campaignName': _campaignName(_inviteCampaignId),
              'companySlug': widget.companySlug,
              'selfRegistrationEnabled': _selfRegister,
              'joinCode': _joinCode.text,
            },
          }));
    } catch (_) {}
  }

  String _campaignName(String? id) {
    for (final campaign in widget.campaigns) {
      if (campaign.id == id) return campaign.name;
    }
    return id ?? '';
  }

  Widget _campaignMenu({
    required String? value,
    required ValueChanged<String?> onChanged,
    required AppStrings strings,
  }) {
    if (widget.campaigns.isEmpty) {
      return Text(strings.webhookNoCampaigns, style: Theme.of(context).textTheme.bodyMedium);
    }
    final ids = widget.campaigns.map((campaign) => campaign.id).toSet();
    return DropdownButtonFormField<String>(
      initialValue: value != null && ids.contains(value) ? value : widget.campaigns.first.id,
      decoration: InputDecoration(labelText: strings.webhookCampaign),
      items: [
        for (final campaign in widget.campaigns)
          DropdownMenuItem(value: campaign.id, child: Text(campaign.name.isEmpty ? campaign.id : campaign.name)),
      ],
      onChanged: onChanged,
    );
  }
}

class _StaffOnlyNotice extends StatelessWidget {
  final String message;

  const _StaffOnlyNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(child: Text(message, style: textTheme.bodyLarge)),
            ],
          ),
        ),
      ),
    );
  }
}
