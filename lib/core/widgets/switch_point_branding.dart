import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../constants/country_currency_config.dart';
import '../constants/app_version_config.dart';
import '../localization/locale_provider.dart';
import 'm3_action_menu.dart';
import 'tashil_gift_logo.dart';

/// Company constants & metadata for Switch Point & Tashil Gift System
class SwitchPointInfo {
  static const String companyName = 'Switch Point';
  static const String companyNameAr = 'سويتش بوينت';
  static const String platformName = 'Tashil Gift';
  static const String platformSubtitle =
      'System Admins & Promoters Login Portal';
  static const String websiteUrl = 'https://www.sw-point.com/';
  static const String websiteDisplay = 'www.sw-point.com';
  static const String supportEmail = 'support@sw-point.com';
  static const String whatsappEgypt = '+20 121 185 7725';
  static const String whatsappEgyptUrl = 'https://wa.me/201211857725';
  static const String whatsappUae = '+971 55 871 5615';
  static const String whatsappUaeUrl = 'https://wa.me/971558715615';
  static const String copyright = '© 2026 Switch Point. All rights reserved.';

  /// Safe URL launcher helper
  static Future<void> launchLink(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Fallback
    }
  }

  /// Launch email client
  static Future<void> launchEmail(String email) async {
    final uri = Uri.parse('mailto:$email');
    try {
      await launchUrl(uri);
    } catch (_) {}
  }
}

/// Material Design 3 Persistent Header for Switch Point Platform
class SwitchPointHeader extends ConsumerWidget implements PreferredSizeWidget {
  final Widget? leading;
  final String? subtitle;
  final List<Widget>? customActions;
  final bool showMobileMenu;
  final String? companyLogoUrl;
  final VoidCallback? onMobileMenuPressed;
  final bool showLanguageSelector;
  final bool showCountryCurrencySelector;
  final bool showDarkModeToggle;

  /// When true, the version chip is removed from the app bar and the version
  /// is shown as an "About" entry inside the settings menu instead (M3 review #11).
  final bool showVersionInSettings;

  const SwitchPointHeader({
    super.key,
    this.leading,
    this.subtitle,
    this.customActions,
    this.showMobileMenu = true,
    this.companyLogoUrl,
    this.onMobileMenuPressed,
    this.showLanguageSelector = true,
    this.showCountryCurrencySelector = true,
    this.showDarkModeToggle = true,
    this.showVersionInSettings = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final themeMode = ref.watch(themeModeProvider);
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && theme.brightness == Brightness.dark);

    final activeCountry = ref.watch(activeCountryProvider);
    final isAr = ref.isArabic;

    if (isMobile) {
      return Directionality(
        textDirection: Directionality.of(context),
        child: SafeArea(
          bottom: false,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 6)],

                // 1. Natural START: Brand 'G' Logo + Platform Name + Subtitle
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildMobileLogo(context, colorScheme),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                SwitchPointInfo.platformName,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cairo(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                  letterSpacing: 0.3,
                                  height: 1.15,
                                ),
                              ),
                              Text(
                                subtitle ??
                                    'System Admins & Promoters Login Portal',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: GoogleFonts.cairo(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Middle: Custom Action Icons (if any)
                if (customActions != null && customActions!.isNotEmpty) ...[
                  Row(mainAxisSize: MainAxisSize.min, children: customActions!),
                  const SizedBox(width: 6),
                ],

                // 3. Version & Build Badge + Dark Mode Toggle on Mobile
                if (screenWidth >= 400 && !showVersionInSettings) ...[
                  _buildHeaderVersionPill(
                    colorScheme,
                    isMobile: true,
                    isCompact: true,
                  ),
                  const SizedBox(width: 6),
                ],
                _buildCompactControlsGroup(
                  context,
                  ref,
                  colorScheme,
                  isDark,
                  isAr,
                  activeCountry,
                  showLanguage:
                      showLanguageSelector && onMobileMenuPressed == null,
                  showCurrency:
                      showCountryCurrencySelector &&
                      onMobileMenuPressed == null,
                  showTheme: showDarkModeToggle,
                  dense: !showVersionInSettings,
                ),
                if (showMobileMenu && onMobileMenuPressed != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.menu_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                    ),
                    tooltip: isAr
                        ? 'القائمة الرئيسية والإعدادات'
                        : 'Menu & Settings',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(2),
                    onPressed: onMobileMenuPressed,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: Directionality.of(context),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],

            // Brand 'G' Logo & Title + Subtitle
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const TashilGiftLogo(size: 40),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            SwitchPointInfo.platformName,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.primary,
                              letterSpacing: 0.3,
                              height: 1.15,
                            ),
                          ),
                          Text(
                            subtitle ??
                                'System Admins & Promoters Login Portal',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: GoogleFonts.cairo(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Custom Actions (e.g. Preview button)
            if (customActions != null && customActions!.isNotEmpty) ...[
              ...customActions!,
              const SizedBox(width: 10),
            ],

            if (!showVersionInSettings) ...[
              _buildHeaderVersionPill(
                colorScheme,
                isMobile: false,
                isCompact: true,
              ),
              const SizedBox(width: 10),
            ],
            _buildCompactControlsGroup(
              context,
              ref,
              colorScheme,
              isDark,
              isAr,
              activeCountry,
              showLanguage: showLanguageSelector,
              showCurrency: showCountryCurrencySelector,
              showTheme: showDarkModeToggle,
            ),
          ],
        ),
      ),
    );
  }

  /// Compact, icon-only header controls (language / currency / theme) merged
  /// into a single tonal M3 container. Full labels live in tooltips/semantics.
  Widget _buildCompactControlsGroup(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
    bool isDark,
    bool isAr,
    CountryCurrency activeCountry, {
    required bool showLanguage,
    required bool showCurrency,
    required bool showTheme,
    bool dense = false,
  }) {
    if (!showLanguage && !showCurrency && !showTheme && !showVersionInSettings) {
      return const SizedBox.shrink();
    }
    final lang = ref.watch(localeProvider).languageCode;
    final isHi = lang == 'hi';
    final settingsLabel = isAr ? 'الإعدادات' : (isHi ? 'सेटिंग्स' : 'Settings');
    final themeLabel = isDark
        ? (isAr ? 'الوضع الفاتح' : (isHi ? 'लाइट मोड' : 'Light mode'))
        : (isAr ? 'الوضع الداكن' : (isHi ? 'डार्क मोड' : 'Dark mode'));
    final languageLabel = isAr ? 'اللغة' : (isHi ? 'भाषा' : 'Language');
    final countryLabel = isAr
        ? 'الدولة والعملة'
        : (isHi ? 'देश और मुद्रा' : 'Country & currency');

    return M3ActionMenu(
      tooltip: settingsLabel,
      anchorBuilder: (context, controller, child) {
        return Semantics(
          button: true,
          label: settingsLabel,
          child: IconButton.filledTonal(
            tooltip: settingsLabel,
            visualDensity: dense
                ? VisualDensity.compact
                : VisualDensity.standard,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
        );
      },
      children: [
        if (showVersionInSettings) ...[
          M3ActionMenu.item(
            context: context,
            label: isAr ? 'حول التطبيق' : 'About',
            subtitle: AppVersionConfig.fullBuildDisplay,
            icon: Icons.info_outline_rounded,
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  icon: const Icon(Icons.info_outline_rounded),
                  title: Text(isAr ? 'حول التطبيق' : 'About'),
                  content: Text(AppVersionConfig.tooltipText),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(isAr ? 'إغلاق' : 'Close'),
                    ),
                  ],
                ),
              );
            },
          ),
          if (showTheme || showLanguage || showCurrency) M3ActionMenu.divider(),
        ],
        if (showTheme)
          M3ActionMenu.item(
            context: context,
            label: themeLabel,
            icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            onPressed: () {
              ref.read(themeModeProvider.notifier).state = isDark
                  ? ThemeMode.light
                  : ThemeMode.dark;
            },
          ),
        if (showLanguage) ...[
          M3ActionMenu.divider(),
          M3ActionMenu.header(context: context, title: languageLabel),
          ...AppLanguage.values.map((l) {
            return M3ActionMenu.item(
              context: context,
              label: l.label,
              leading: Text(l.flagEmoji, style: const TextStyle(fontSize: 18)),
              isSelected: lang == l.code,
              onPressed: () => ref.setLocale(l.code),
            );
          }),
        ],
        if (showCurrency) ...[
          M3ActionMenu.divider(),
          M3ActionMenu.header(context: context, title: countryLabel),
          ...CountryCurrencyConfig.supportedCountries.map((country) {
            return M3ActionMenu.item(
              context: context,
              label:
                  '${country.fullName(lang)} (${country.currencySymbolFor(lang)})',
              leading: Text(
                country.flagEmoji,
                style: const TextStyle(fontSize: 18),
              ),
              isSelected: country.code == activeCountry.code,
              onPressed: () {
                ref.read(activeCountryProvider.notifier).state = country;
              },
            );
          }),
        ],
      ],
    );
  }

  Widget _buildHeaderVersionPill(
    ColorScheme colorScheme, {
    required bool isMobile,
    bool isCompact = false,
  }) {
    return Tooltip(
      message: AppVersionConfig.tooltipText,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 6 : (isMobile ? 8 : 12),
          vertical: isMobile ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_outlined,
              size: isCompact ? 12 : (isMobile ? 13 : 15),
              color: colorScheme.primary,
            ),
            SizedBox(width: isCompact ? 3 : (isMobile ? 4 : 6)),
            Text(
              isCompact
                  ? AppVersionConfig.versionDisplay
                  : AppVersionConfig.fullBuildDisplay,
              style: GoogleFonts.cairo(
                fontSize: isCompact ? 9.5 : (isMobile ? 10.5 : 12),
                fontWeight: FontWeight.w700,
                color: colorScheme.onPrimaryContainer,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLogo(BuildContext context, ColorScheme colorScheme) {
    return Tooltip(
      message: AppVersionConfig.tooltipText,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: TashilGiftLogo(size: 34),
      ),
    );
  }
}

/// Material Design 3 Persistent Single-Row Footer for Switch Point Platform (English / LTR Format)
class SwitchPointFooter extends StatelessWidget {
  final bool hideOnMobile;

  const SwitchPointFooter({super.key, this.hideOnMobile = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;

    // Completely remove/hide footer on mobile and tablet (< 900px) per user guidelines
    if (screenWidth < 900 || hideOnMobile) {
      return const SizedBox.shrink();
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final copyrightWidget = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.copyright_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    SwitchPointInfo.copyright,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );

            final linksWidgets = <Widget>[
              // 2. Powered by Switch Point Smart Systems Badge (links to website)
              InkWell(
                onTap: () =>
                    SwitchPointInfo.launchLink(SwitchPointInfo.websiteUrl),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Powered by Switch Point Smart Systems',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Official Website Pill
              _buildFooterPill(
                context: context,
                icon: Icons.public_rounded,
                label: SwitchPointInfo.websiteDisplay,
                url: SwitchPointInfo.websiteUrl,
              ),

              // 4. Email Support
              _buildFooterPill(
                context: context,
                icon: Icons.mail_outline_rounded,
                label: SwitchPointInfo.supportEmail,
                url: 'mailto:${SwitchPointInfo.supportEmail}',
              ),

              // 5. WhatsApp Egypt Pill (M3 Theme Blue & Google Icon)
              _buildFooterPill(
                context: context,
                icon: Icons.chat_bubble_outline_rounded,
                label: 'WhatsApp Egypt',
                tooltip:
                    'Contact via WhatsApp Egypt (${SwitchPointInfo.whatsappEgypt})',
                url: SwitchPointInfo.whatsappEgyptUrl,
              ),

              // 6. WhatsApp UAE Pill (M3 Theme Blue & Google Icon)
              _buildFooterPill(
                context: context,
                icon: Icons.chat_bubble_outline_rounded,
                label: 'WhatsApp UAE',
                tooltip:
                    'Contact via WhatsApp UAE (${SwitchPointInfo.whatsappUae})',
                url: SwitchPointInfo.whatsappUaeUrl,
              ),
            ];

            if (constraints.maxWidth >= 980) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(child: copyrightWidget),
                  const SizedBox(width: 12),
                  Flexible(
                    flex: 3,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: linksWidgets,
                    ),
                  ),
                ],
              );
            }

            return Wrap(
              spacing: 14,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [copyrightWidget, ...linksWidgets],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooterPill({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String url,
    String? tooltip,
    Color? highlightColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = highlightColor ?? colorScheme.primary;

    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );

    if (tooltip != null) {
      pill = Tooltip(message: tooltip, child: pill);
    }

    return InkWell(
      onTap: () => SwitchPointInfo.launchLink(url),
      borderRadius: BorderRadius.circular(20),
      child: pill,
    );
  }
}

/// Material Design 3 Mobile Navigation, Settings & Support Drawer Sheet
class SwitchPointMobileMenuSheet extends ConsumerWidget {
  final String? subtitle;
  final String? companyLogoUrl;
  final List<Widget>? customActions;

  const SwitchPointMobileMenuSheet({
    super.key,
    this.subtitle,
    this.companyLogoUrl,
    this.customActions,
  });

  /// Static helper to display the modal bottom sheet
  static Future<void> show(
    BuildContext context, {
    String? subtitle,
    String? companyLogoUrl,
    List<Widget>? customActions,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SwitchPointMobileMenuSheet(
        subtitle: subtitle,
        companyLogoUrl: companyLogoUrl,
        customActions: customActions,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAr = ref.isArabic;
    final isHindi = ref.isHindi;
    final currentLangCode = ref.watch(localeProvider).languageCode;
    final activeCountry = ref.watch(activeCountryProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && theme.brightness == Brightness.dark);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (companyLogoUrl != null && companyLogoUrl!.isNotEmpty) ...[
                  Container(
                    width: 38,
                    height: 38,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    child: ClipOval(
                      child: Image.network(
                        companyLogoUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, st) => Icon(
                          Icons.business_rounded,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  const TashilGiftLogo(size: 36),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        subtitle ?? SwitchPointInfo.platformName,
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        isAr
                            ? 'القائمة الرئيسية والإعدادات'
                            : (isHindi
                                  ? 'मुख्य मेनू और सेटिंग्स'
                                  : 'Main Menu & Settings'),
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable Body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Campaign Quick Actions (if any)
                  if (customActions != null && customActions!.isNotEmpty) ...[
                    Text(
                      isAr
                          ? 'إجراءات الحملة والبرموتر:'
                          : (isHindi
                                ? 'प्रचार और प्रमोटर क्रियाएं:'
                                : 'Campaign & Promoter Actions:'),
                      style: GoogleFonts.cairo(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.25,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: customActions!,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 2. Preferences & Settings Section
                  Text(
                    isAr
                        ? 'إعدادات اللغة والمظهر:'
                        : (isHindi
                              ? 'भाषा और उपस्थिति सेटिंग्स:'
                              : 'Language & Display Settings:'),
                    style: GoogleFonts.cairo(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Language Selector
                        Row(
                          children: [
                            Icon(
                              Icons.translate_rounded,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isAr
                                  ? 'لغة التطبيق'
                                  : (isHindi ? 'ऐप की भाषा' : 'App Language'),
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: currentLangCode,
                              isExpanded: true,
                              icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              dropdownColor: colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(12),
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                              items: AppLanguage.values.map((lang) {
                                return DropdownMenuItem<String>(
                                  value: lang.code,
                                  child: Text(
                                    lang.label,
                                    style: GoogleFonts.cairo(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) ref.setLocale(val);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Country & Currency Selector
                        Row(
                          children: [
                            Icon(
                              Icons.payments_rounded,
                              size: 18,
                              color: colorScheme.secondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isAr
                                  ? 'الدولة والعملة المعتمدة'
                                  : (isHindi
                                        ? 'देश और मुद्रा'
                                        : 'Country & Currency'),
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: activeCountry.code,
                              isExpanded: true,
                              icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              dropdownColor: colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(12),
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                              items: CountryCurrencyConfig.supportedCountries.map((
                                country,
                              ) {
                                return DropdownMenuItem<String>(
                                  value: country.code,
                                  child: Text(
                                    '${country.name(currentLangCode)} (${country.currencySymbolFor(currentLangCode)})',
                                    style: GoogleFonts.cairo(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  final country =
                                      CountryCurrencyConfig.findByCode(val);
                                  ref
                                          .read(activeCountryProvider.notifier)
                                          .state =
                                      country;
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Dark / Light Theme Mode
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          secondary: Icon(
                            isDark
                                ? Icons.dark_mode_rounded
                                : Icons.light_mode_rounded,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                          title: Text(
                            isAr
                                ? (isDark
                                      ? 'الوضع الداكن (مفعل)'
                                      : 'الوضع الفاتح (مفعل)')
                                : (isHindi
                                      ? (isDark
                                            ? 'डार्क मोड (सक्रिय)'
                                            : 'लाइट मोड (सक्रिय)')
                                      : (isDark
                                            ? 'Dark Mode (Active)'
                                            : 'Light Mode (Active)')),
                            style: GoogleFonts.cairo(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            isAr
                                ? 'تبديل المظهر بين الوضع الليلي والنهاري'
                                : (isHindi
                                      ? 'दिन और रात के मोड के बीच स्विच करें'
                                      : 'Toggle between Dark and Light mode'),
                            style: GoogleFonts.cairo(
                              fontSize: 10.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          value: isDark,
                          onChanged: (val) {
                            ref.read(themeModeProvider.notifier).state = val
                                ? ThemeMode.dark
                                : ThemeMode.light;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Contact Us & Support Section (Moved from footer)
                  Text(
                    isAr
                        ? 'تواصل معنا والدعم الفني:'
                        : (isHindi
                              ? 'हमसे संपर्क करें और तकनीकी सहायता:'
                              : 'Contact Us & Technical Support:'),
                    style: GoogleFonts.cairo(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        // WhatsApp Egypt
                        ListTile(
                          dense: true,
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.chat_rounded,
                              color: colorScheme.onPrimaryContainer,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            'WhatsApp (مصر)',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            SwitchPointInfo.whatsappEgypt,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(
                            Icons.open_in_new_rounded,
                            size: 16,
                          ),
                          onTap: () => SwitchPointInfo.launchLink(
                            SwitchPointInfo.whatsappEgyptUrl,
                          ),
                        ),
                        const Divider(height: 1),

                        // WhatsApp UAE
                        ListTile(
                          dense: true,
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.chat_rounded,
                              color: colorScheme.onPrimaryContainer,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            'WhatsApp (الإمارات)',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            SwitchPointInfo.whatsappUae,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(
                            Icons.open_in_new_rounded,
                            size: 16,
                          ),
                          onTap: () => SwitchPointInfo.launchLink(
                            SwitchPointInfo.whatsappUaeUrl,
                          ),
                        ),
                        const Divider(height: 1),

                        // Support Email
                        ListTile(
                          dense: true,
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.mail_outline_rounded,
                              color: colorScheme.onSecondaryContainer,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            isAr ? 'البريد الإلكتروني للدعم' : 'Support Email',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            SwitchPointInfo.supportEmail,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(
                            Icons.open_in_new_rounded,
                            size: 16,
                          ),
                          onTap: () => SwitchPointInfo.launchEmail(
                            SwitchPointInfo.supportEmail,
                          ),
                        ),
                        const Divider(height: 1),

                        // Official Website
                        ListTile(
                          dense: true,
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.public_rounded,
                              color: colorScheme.onTertiaryContainer,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            isAr
                                ? 'موقع سويتش بوينت الرسمي'
                                : 'Switch Point Website',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            SwitchPointInfo.websiteDisplay,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(
                            Icons.open_in_new_rounded,
                            size: 16,
                          ),
                          onTap: () => SwitchPointInfo.launchLink(
                            SwitchPointInfo.websiteUrl,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Copyright & Version Footer
                  Center(
                    child: Column(
                      children: [
                        Text(
                          '© ${SwitchPointInfo.copyright}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            AppVersionConfig.fullBuildDisplay,
                            style: GoogleFonts.cairo(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
