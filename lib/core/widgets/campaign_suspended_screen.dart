import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../localization/app_strings.dart';
import '../localization/locale_provider.dart';
import '../theme/app_theme.dart';
import '../../features/admin/domain/event_model.dart';

/// Portal Type enumeration to tailor the suspended message & visual theme
enum SuspendedPortalType {
  promoter,
  manager,
}

/// A world-class Material Design 3 compliant, trilingual, responsive
/// Suspended Campaign Screen for Promoters and Company Managers.
class CampaignSuspendedScreen extends ConsumerStatefulWidget {
  final SuspendedPortalType portalType;
  final EventModel? event;
  final String? companySlug;
  final String? companyName;
  final VoidCallback? onRefresh;

  const CampaignSuspendedScreen({
    super.key,
    required this.portalType,
    this.event,
    this.companySlug,
    this.companyName,
    this.onRefresh,
  });

  @override
  ConsumerState<CampaignSuspendedScreen> createState() => _CampaignSuspendedScreenState();
}

class _CampaignSuspendedScreenState extends ConsumerState<CampaignSuspendedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _pulseAnimation;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (widget.onRefresh != null) {
      widget.onRefresh!();
    }
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  void _showContactAdminDialog(BuildContext context, AppStrings strings, ColorScheme colorScheme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: colorScheme.surface,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.support_agent_rounded, color: colorScheme.onPrimaryContainer, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                strings.contactAdminBtn,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.supportTeamNotice,
              style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _buildContactInfoRow(
              context,
              icon: Icons.phone_in_talk_rounded,
              title: strings.isAr ? 'رقم الدعم الفني / واتساب:' : 'Support Phone / WhatsApp:',
              value: '+20 100 000 0000',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildContactInfoRow(
              context,
              icon: Icons.email_rounded,
              title: strings.isAr ? 'البريد الإلكتروني للإدارة:' : 'Admin Email:',
              value: 'support@tashilgift.com',
              colorScheme: colorScheme,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(strings.dialogCloseBtn, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfoRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
                SelectableText(
                  value,
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              final strings = AppStrings.of(ref);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(strings.contactAdminCopied),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isMobile = screenWidth < 600;

    final bool isPromoter = widget.portalType == SuspendedPortalType.promoter;
    final targetCompanyName = widget.companyName ?? widget.event?.targetCompany ?? 'الشركة الراعية';
    final targetLogoUrl = widget.event?.companyLogoUrl ?? '';
    final targetEventName = widget.event?.eventName ?? '';

    final heroTitle = isPromoter ? strings.promoterSuspendedTitle : strings.managerSuspendedTitle;
    final heroMessage = isPromoter ? strings.promoterSuspendedMessage : strings.managerSuspendedMessage;
    final heroIcon = isPromoter ? Icons.pause_circle_filled_rounded : Icons.lock_clock_rounded;

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline_rounded, size: 15, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 8),
              Text(
                isPromoter ? strings.promoterPortalLabel : strings.managerPortalLabel,
                style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
            ],
          ),
          actions: [
            // Language selector button
            PopupMenuButton<String>(
              icon: Icon(Icons.language_rounded, color: colorScheme.onSurfaceVariant, size: 20),
              tooltip: isAr ? 'تغيير لغة العرض' : 'Change Language',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: (langCode) {
                ref.read(localeProvider.notifier).state = Locale(langCode);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'ar',
                  child: Row(
                    children: [
                      const Text('🇪🇬 ', style: TextStyle(fontSize: 16)),
                      Text('العربية (Arabic)', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'en',
                  child: Row(
                    children: [
                      const Text('🇬🇧 ', style: TextStyle(fontSize: 16)),
                      Text('English', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'hi',
                  child: Row(
                    children: [
                      const Text('🇮🇳 ', style: TextStyle(fontSize: 16)),
                      Text('हिन्दी (Hindi)', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            // Theme toggle button
            IconButton(
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
              tooltip: isAr ? 'تبديل المظهر' : 'Toggle Theme',
              onPressed: () {
                ref.read(themeModeProvider.notifier).state =
                    Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: min(screenWidth * 0.94, 520),
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 20 : 28,
                  vertical: isMobile ? 24 : 32,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isPromoter
                        ? colorScheme.outlineVariant.withValues(alpha: 0.6)
                        : colorScheme.primary.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isPromoter
                          ? colorScheme.shadow.withValues(alpha: 0.05)
                          : colorScheme.primary.withValues(alpha: 0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brand Logo + Status Pill
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (targetLogoUrl.isNotEmpty || targetCompanyName.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            child: CircleAvatar(
                              radius: 20,
                              backgroundColor: colorScheme.primaryContainer,
                              backgroundImage: targetLogoUrl.isNotEmpty ? NetworkImage(targetLogoUrl) : null,
                              child: targetLogoUrl.isEmpty
                                  ? Text(
                                      targetCompanyName.isNotEmpty ? targetCompanyName[0].toUpperCase() : 'C',
                                      style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        if (targetCompanyName.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                targetCompanyName,
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Pulsing Hero Icon Container
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isPromoter
                              ? Colors.amber.shade100.withValues(alpha: 0.8)
                              : colorScheme.secondaryContainer.withValues(alpha: 0.8),
                          border: Border.all(
                            color: isPromoter ? Colors.amber.shade600 : colorScheme.primary,
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isPromoter ? Colors.amber.shade400 : colorScheme.primary)
                                  .withValues(alpha: 0.3),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          heroIcon,
                          size: 44,
                          color: isPromoter ? Colors.amber.shade900 : colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Status Badge (متوقفة مؤقتاً)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause_circle_rounded, size: 14, color: Colors.amber.shade900),
                          const SizedBox(width: 6),
                          Text(
                            strings.portalStatusPaused,
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Main Headline
                    Text(
                      heroTitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        height: 1.3,
                      ),
                    ),

                    if (targetEventName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        targetEventName,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Courteous Descriptive Message
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        heroMessage,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Action Buttons (Strict M3 Single Icon Rule)
                    Row(
                      children: [
                        // Refresh / Check Status Button
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isRefreshing ? null : _handleRefresh,
                            icon: _isRefreshing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(
                              strings.refreshStatusBtn,
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Contact Administration Button
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showContactAdminDialog(context, strings, colorScheme),
                            icon: const Icon(Icons.support_agent_rounded, size: 18),
                            label: Text(
                              strings.contactAdminBtn,
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: colorScheme.outline),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
