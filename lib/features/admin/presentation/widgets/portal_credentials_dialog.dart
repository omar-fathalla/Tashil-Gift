import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/config/app_env.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/services/partner_portal_auth_service.dart';
import '../../domain/event_model.dart';

/// Material Design 3 Dialog for managing Two-Tier Partner Portal Credentials:
/// - Tier 1 (Company Level): Brand Executive (`/portal/:slug`) & Agency Operations (`/ops/:slug`)
///   inherited by all campaigns under the company.
/// - Tier 2 (Optional Campaign Override): Dedicated Agency Operations credentials for a specific campaign (`event`).
/// - Includes 1-Click "Copy WhatsApp Login Card", password regeneration, and automatic `credentialVersion` increment.
class PortalCredentialsDialog extends ConsumerStatefulWidget {
  final String companySlug;
  final String companyName;
  final EventModel? event;

  const PortalCredentialsDialog({
    super.key,
    required this.companySlug,
    required this.companyName,
    this.event,
  });

  static Future<void> show(
    BuildContext context, {
    required String companySlug,
    required String companyName,
    EventModel? event,
  }) {
    return showDialog(
      context: context,
      builder: (_) => PortalCredentialsDialog(
        companySlug: companySlug,
        companyName: companyName,
        event: event,
      ),
    );
  }

  @override
  ConsumerState<PortalCredentialsDialog> createState() => _PortalCredentialsDialogState();
}

class _PortalCredentialsDialogState extends ConsumerState<PortalCredentialsDialog> {
  final _brandUserCtrl = TextEditingController();
  final _brandPassCtrl = TextEditingController();
  final _agencyUserCtrl = TextEditingController();
  final _agencyPassCtrl = TextEditingController();
  final _customAgencyUserCtrl = TextEditingController();
  final _customAgencyPassCtrl = TextEditingController();

  bool _hasCustomCampaignAgency = false;
  bool _isLoading = true;
  bool _isSaving = false;
  int _brandVersion = 1;
  int _agencyVersion = 1;
  int _customAgencyVersion = 1;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  @override
  void dispose() {
    _brandUserCtrl.dispose();
    _brandPassCtrl.dispose();
    _agencyUserCtrl.dispose();
    _agencyPassCtrl.dispose();
    _customAgencyUserCtrl.dispose();
    _customAgencyPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCredentials() async {
    setState(() => _isLoading = true);
    final service = ref.read(partnerPortalAuthServiceProvider);
    final resolved = await service.resolveCredentials(
      companySlug: widget.companySlug,
      companyNameHint: widget.companyName,
      eventId: widget.event?.id,
    );

    if (!mounted) return;
    setState(() {
      _brandUserCtrl.text = resolved.brandManagerUsername;
      _brandPassCtrl.text = resolved.brandManagerPassword;
      _brandVersion = resolved.brandCredentialVersion;

      _agencyUserCtrl.text = resolved.agencyOpsUsername;
      _agencyPassCtrl.text = resolved.agencyOpsPassword;
      _agencyVersion = resolved.agencyCredentialVersion;

      _hasCustomCampaignAgency = resolved.hasCustomAgencyCredentials;
      _customAgencyUserCtrl.text = resolved.customAgencyUsername.isNotEmpty
          ? resolved.customAgencyUsername
          : PartnerPortalAuthService.defaultCampaignAgencyUsername(
              widget.companySlug,
              widget.event?.id ?? 'camp',
            );
      _customAgencyPassCtrl.text = resolved.customAgencyPassword.isNotEmpty
          ? resolved.customAgencyPassword
          : PartnerPortalAuthService.defaultCampaignAgencyPassword(
              widget.companySlug,
              widget.event?.id ?? 'camp',
            );
      _customAgencyVersion = resolved.customAgencyCredentialVersion;
      _isLoading = false;
    });
  }

  String _baseOrigin() {
    final base = Uri.base.origin;
    if (base.isEmpty || base == 'null' || base.startsWith('file:')) {
      return kDefaultHostingOrigin;
    }
    return base;
  }

  Future<void> _saveChanges({bool showSuccessSnack = true}) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final service = ref.read(partnerPortalAuthServiceProvider);
      final updated = await service.saveCompanyCredentials(
        companySlug: widget.companySlug,
        companyName: widget.companyName,
        brandManagerUsername: _brandUserCtrl.text.trim(),
        brandManagerPassword: _brandPassCtrl.text.trim(),
        agencyOpsUsername: _agencyUserCtrl.text.trim(),
        agencyOpsPassword: _agencyPassCtrl.text.trim(),
      );

      int nextCustomAgencyVer = _customAgencyVersion;
      if (widget.event != null && widget.event!.id.isNotEmpty) {
        nextCustomAgencyVer = await service.saveCampaignAgencyOverride(
          eventId: widget.event!.id,
          companySlug: widget.companySlug,
          hasCustomAgencyCredentials: _hasCustomCampaignAgency,
          customAgencyUsername: _customAgencyUserCtrl.text.trim(),
          customAgencyPassword: _customAgencyPassCtrl.text.trim(),
        );
      }

      if (!mounted) return;
      setState(() {
        _brandVersion = updated.brandCredentialVersion;
        _agencyVersion = updated.agencyCredentialVersion;
        _customAgencyVersion = nextCustomAgencyVer;
        _isSaving = false;
      });

      if (showSuccessSnack) {
        final isAr = ref.read(localeProvider).languageCode == 'ar';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr
                  ? '✅ تم حفظ بيانات الدخول وتحديث جلسات الأمان بنجاح'
                  : '✅ Portal credentials saved & security sessions updated',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
    }
  }

  Future<void> _copyWhatsAppCard({
    required PartnerPortalRole role,
    bool useCustomCampaignTier = false,
  }) async {
    await _saveChanges(showSuccessSnack: false);
    if (!mounted) return;

    final isAr = ref.read(localeProvider).languageCode == 'ar';
    final cleanSlug = widget.companySlug.trim().toLowerCase();
    final origin = _baseOrigin();

    final String portalUrl;
    final String username;
    final String password;

    if (role == PartnerPortalRole.brandManager) {
      portalUrl = '$origin/#/portal/$cleanSlug';
      username = _brandUserCtrl.text.trim();
      password = _brandPassCtrl.text.trim();
    } else if (useCustomCampaignTier && widget.event != null) {
      portalUrl = '$origin/#/ep/${widget.event!.id}';
      username = _customAgencyUserCtrl.text.trim();
      password = _customAgencyPassCtrl.text.trim();
    } else {
      portalUrl = '$origin/#/ops/$cleanSlug';
      username = _agencyUserCtrl.text.trim();
      password = _agencyPassCtrl.text.trim();
    }

    final cardText = PartnerPortalAuthService.buildWhatsAppLoginCard(
      role: role,
      companyName: widget.companyName.isNotEmpty ? widget.companyName : cleanSlug.toUpperCase(),
      portalUrl: portalUrl,
      username: username,
      password: password,
      campaignName: widget.event?.eventName,
      isCustomCampaignTier: useCustomCampaignTier,
      isAr: isAr,
    );

    await Clipboard.setData(ClipboardData(text: cardText));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAr
              ? '📋 تم نسخ بطاقة الدخول الذكية للواتساب (الرابط + اسم المستخدم + كلمة المرور)'
              : '📋 WhatsApp Login Card copied to clipboard (URL + Username + Password)',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final cleanSlug = widget.companySlug.trim().toLowerCase();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: _isLoading
            ? Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      isAr ? 'جاري تحميل بيانات الدخول...' : 'Loading portal credentials...',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.vpn_key_rounded,
                            color: colorScheme.onPrimaryContainer,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isAr
                                    ? 'إدارة بيانات الدخول وبطاقات الواتساب (${widget.companyName})'
                                    : 'Partner Portal Credentials & WhatsApp Cards (${widget.companyName})',
                                style: GoogleFonts.cairo(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                isAr
                                    ? 'المستوى الأول (للشركة بالكامل) + المستوى الثاني (تخصيص اختياري للحملة) مع إلغاء فوري للجلسات عند تغيير كلمة المرور'
                                    : 'Tier 1 (Company-wide inheritance) + Tier 2 (Optional campaign override) with instant session revocation',
                                style: GoogleFonts.cairo(
                                  fontSize: 11.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),

                  // Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Brand Executive Card (Tier 1)
                          _buildCredentialSectionCard(
                            colorScheme: colorScheme,
                            isAr: isAr,
                            icon: Icons.business_center_rounded,
                            badgeText: isAr
                                ? 'المستوى 1 — البوابة التنفيذية للشركة (قراءة فقط للأرصدة)'
                                : 'Tier 1 — Brand Executive Portal (Read-Only Stock)',
                            title: isAr
                                ? 'بيانات دخول مدير العلامة التجارية (/portal/$cleanSlug)'
                                : 'Brand Manager Credentials (/portal/$cleanSlug)',
                            subtitle: isAr
                                ? 'تفتح جميع حملات الشركة، مؤشرات الـ ROI، وسجل الفواتير، مع عرض أرصدة الهدايا بالفروع للعرض والتصدير فقط دون تعديل.'
                                : 'Unlocks company campaigns, ROI analytics, and read-only branch stock balances.',
                            version: _brandVersion,
                            userController: _brandUserCtrl,
                            passController: _brandPassCtrl,
                            isSecondaryContainer: true,
                            onRegeneratePassword: () {
                              setState(() {
                                _brandPassCtrl.text =
                                    PartnerPortalAuthService.generateRandomPassword(prefix: 'Bm');
                              });
                            },
                            onCopyWhatsAppCard: () => _copyWhatsAppCard(
                              role: PartnerPortalRole.brandManager,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 2. Agency Operations Card (Tier 1 Company Default)
                          _buildCredentialSectionCard(
                            colorScheme: colorScheme,
                            isAr: isAr,
                            icon: Icons.store_mall_directory_rounded,
                            badgeText: isAr
                                ? 'المستوى 1 — بوابة شركة الدعاية والعمليات الموحدة للشركة'
                                : 'Tier 1 — Default Company Agency Operations Portal',
                            title: isAr
                                ? 'بيانات دخول العمليات والأرصدة (/ops/$cleanSlug)'
                                : 'Agency Operations Credentials (/ops/$cleanSlug)',
                            subtitle: isAr
                                ? 'تورث تلقائياً لجميع حملات الشركة وتسمح بإدارة وتعديل أرصدة الهدايا والتسويات الميدانية (دون إظهار رابط المدير العام).'
                                : 'Inherited automatically by all company campaigns with full branch stock read/write access.',
                            version: _agencyVersion,
                            userController: _agencyUserCtrl,
                            passController: _agencyPassCtrl,
                            isSecondaryContainer: false,
                            onRegeneratePassword: () {
                              setState(() {
                                _agencyPassCtrl.text =
                                    PartnerPortalAuthService.generateRandomPassword(prefix: 'Op');
                              });
                            },
                            onCopyWhatsAppCard: () => _copyWhatsAppCard(
                              role: PartnerPortalRole.agencyOps,
                              useCustomCampaignTier: false,
                            ),
                          ),

                          // 3. Optional Tier 2 Campaign-Specific Agency Override (if opened from a campaign)
                          if (widget.event != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _hasCustomCampaignAgency
                                      ? colorScheme.primary
                                      : colorScheme.outlineVariant.withValues(alpha: 0.6),
                                  width: _hasCustomCampaignAgency ? 1.5 : 1.0,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.campaign_rounded,
                                        color: colorScheme.primary,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              isAr
                                                  ? 'المستوى 2 (اختياري): تخصيص بيانات دخول مستقلة لهذه الحملة فقط'
                                                  : 'Tier 2 (Optional): Custom Agency Credentials for this Campaign Only',
                                              style: GoogleFonts.cairo(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                            Text(
                                              isAr
                                                  ? 'فعّل هذا الخيار إذا كانت هذه الحملة (${widget.event!.eventName}) تُدار بواسطة وكالة دعاية مختلفة عن باقي حملات الشركة.'
                                                  : 'Enable if "${widget.event!.eventName}" is managed by a separate agency.',
                                              style: GoogleFonts.cairo(
                                                fontSize: 11.5,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Switch(
                                        value: _hasCustomCampaignAgency,
                                        onChanged: (val) => setState(() => _hasCustomCampaignAgency = val),
                                      ),
                                    ],
                                  ),
                                  if (_hasCustomCampaignAgency) ...[
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _customAgencyUserCtrl,
                                            decoration: InputDecoration(
                                              labelText: isAr
                                                  ? 'اسم مستخدم وكالة الحملة'
                                                  : 'Campaign Agency Username',
                                              prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                                              isDense: true,
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: TextField(
                                            controller: _customAgencyPassCtrl,
                                            decoration: InputDecoration(
                                              labelText: isAr
                                                  ? 'كلمة مرور وكالة الحملة'
                                                  : 'Campaign Agency Password',
                                              prefixIcon: const Icon(Icons.key_rounded, size: 18),
                                              suffixIcon: IconButton(
                                                tooltip: isAr ? 'توليد كلمة مرور جديدة' : 'Generate new password',
                                                icon: const Icon(Icons.autorenew_rounded, size: 18),
                                                onPressed: () {
                                                  setState(() {
                                                    _customAgencyPassCtrl.text =
                                                        PartnerPortalAuthService.generateRandomPassword(
                                                            prefix: 'Cp');
                                                  });
                                                },
                                              ),
                                              isDense: true,
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: FilledButton.tonalIcon(
                                        onPressed: () => _copyWhatsAppCard(
                                          role: PartnerPortalRole.agencyOps,
                                          useCustomCampaignTier: true,
                                        ),
                                        icon: const Icon(Icons.share_rounded, size: 18),
                                        label: Text(
                                          isAr
                                              ? 'نسخ بطاقة واتساب المخصصة لهذه الحملة (v$_customAgencyVersion)'
                                              : 'Copy Campaign WhatsApp Login Card (v$_customAgencyVersion)',
                                          style: GoogleFonts.cairo(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Footer Actions
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                      border: Border(
                        top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            isAr ? 'إغلاق' : 'Close',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _isSaving ? null : () => _saveChanges(showSuccessSnack: true),
                          icon: _isSaving
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(
                            isAr ? 'حفظ وتحديث الصلاحيات' : 'Save & Update Credentials',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCredentialSectionCard({
    required ColorScheme colorScheme,
    required bool isAr,
    required IconData icon,
    required String badgeText,
    required String title,
    required String subtitle,
    required int version,
    required TextEditingController userController,
    required TextEditingController passController,
    required bool isSecondaryContainer,
    required VoidCallback onRegeneratePassword,
    required VoidCallback onCopyWhatsAppCard,
  }) {
    final badgeBg = isSecondaryContainer ? colorScheme.secondaryContainer : colorScheme.primaryContainer;
    final badgeFg =
        isSecondaryContainer ? colorScheme.onSecondaryContainer : colorScheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: badgeFg),
                    const SizedBox(width: 6),
                    Text(
                      badgeText,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: badgeFg,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isAr ? 'إصدار الأمان v$version' : 'Security v$version',
                  style: GoogleFonts.cairo(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.cairo(
              fontSize: 11.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: userController,
                  decoration: InputDecoration(
                    labelText: isAr ? 'اسم المستخدم' : 'Username',
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: passController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: isAr ? 'كلمة المرور' : 'Password',
                    prefixIcon: const Icon(Icons.key_rounded, size: 18),
                    suffixIcon: IconButton(
                      tooltip: isAr
                          ? 'توليد كلمة مرور جديدة (يلغي الجلسات السابقة فوراً)'
                          : 'Regenerate password (revokes old sessions)',
                      icon: const Icon(Icons.autorenew_rounded, size: 18),
                      onPressed: onRegeneratePassword,
                    ),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: onCopyWhatsAppCard,
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: Text(
                  isAr ? 'نسخ بطاقة الدخول للواتساب (1-Click)' : 'Copy WhatsApp Login Card (1-Click)',
                  style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: badgeBg,
                  foregroundColor: badgeFg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
