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
  static const String platformSubtitle = 'System Admins & Promoters Login Portal';
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

  const SwitchPointHeader({
    super.key,
    this.leading,
    this.subtitle,
    this.customActions,
    this.showMobileMenu = true,
    this.companyLogoUrl,
    this.onMobileMenuPressed,
    this.showLanguageSelector = false,
    this.showCountryCurrencySelector = false,
    this.showDarkModeToggle = true,
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
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && theme.brightness == Brightness.dark);

    final activeCountry = ref.watch(activeCountryProvider);
    final isAr = ref.isArabic;

    if (isMobile) {
      return SafeArea(
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
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 6),
              ],

              // 1. Natural START: Brand 'G' Logo + Platform Name + Subtitle
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
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
                              subtitle ?? 'System Admins & Promoters Login Portal',
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: customActions!,
                ),
                const SizedBox(width: 6),
              ],

              // 3. Version & Build Badge + Dark Mode Toggle on Mobile
              _buildHeaderVersionPill(colorScheme, isMobile: true),
              const SizedBox(width: 6),
              if (showDarkModeToggle)
                _buildThemeModeButton(ref, colorScheme, isDark, true),
            ],
          ),
        ),
      );
    }

    return Container(
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
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 4,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 10),
          ],

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
                          subtitle ?? 'System Admins & Promoters Login Portal',
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

          if (showLanguageSelector) ...[
            _buildLanguageSelector(context, ref, colorScheme, false, isAr),
            const SizedBox(width: 8),
          ],

          if (showCountryCurrencySelector) ...[
            _buildCountryCurrencySelector(context, ref, colorScheme, false, activeCountry),
            const SizedBox(width: 8),
          ],

          // Version & Build Pill in Header (Moved from Footer)
          _buildHeaderVersionPill(colorScheme, isMobile: false),
          const SizedBox(width: 10),

          // Theme Mode Switcher (Dark / Light)
          if (showDarkModeToggle)
            _buildThemeModeButton(ref, colorScheme, isDark, false),
        ],
      ),
    );
  }

  Widget _buildHeaderVersionPill(ColorScheme colorScheme, {required bool isMobile}) {
    return Tooltip(
      message: AppVersionConfig.tooltipText,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 12,
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
              size: isMobile ? 13 : 15,
              color: colorScheme.primary,
            ),
            SizedBox(width: isMobile ? 4 : 6),
            Text(
              AppVersionConfig.fullBuildDisplay,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 10.5 : 12,
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

  Widget _buildThemeModeButton(
    WidgetRef ref,
    ColorScheme colorScheme,
    bool isDark,
    bool isMobile,
  ) {
    return Tooltip(
      message: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            ref.read(themeModeProvider.notifier).state =
                isDark ? ThemeMode.light : ThemeMode.dark;
          },
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 6 : 8),
            child: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: colorScheme.primary,
              size: isMobile ? 18 : 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
    bool isMobile,
    bool isAr,
  ) {
    return M3ActionMenu(
      tooltip: isAr
          ? 'تغيير لغة النظام'
          : (ref.isHindi ? 'भाषा बदलें' : 'Change System Language'),
      anchorBuilder: (context, controller, child) {
        return InkWell(
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 6 : 10,
              vertical: isMobile ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ref.currentAppLanguage.flagEmoji,
                  style: TextStyle(fontSize: isMobile ? 14 : 16),
                ),
                if (!isMobile) ...[
                  const SizedBox(width: 4),
                  Text(
                    ref.currentAppLanguage.shortLabel,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: isMobile ? 16 : 18,
                  color: colorScheme.primary,
                ),
              ],
            ),
          ),
        );
      },
      children: [
        M3ActionMenu.header(
          context: context,
          title: isAr ? 'اللغة / Language' : 'Select Language',
        ),
        ...AppLanguage.values.map((lang) {
          final isSelected = ref.watch(localeProvider).languageCode == lang.code;
          return M3ActionMenu.item(
            context: context,
            label: lang.label,
            leading: Text(lang.flagEmoji, style: const TextStyle(fontSize: 18)),
            isSelected: isSelected,
            onPressed: () {
              ref.setLocale(lang.code);
            },
          );
        }),
      ],
    );
  }

  Widget _buildCountryCurrencySelector(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
    bool isMobile,
    CountryCurrency activeCountry,
  ) {
    final lang = ref.watch(localeProvider).languageCode;
    final countryTooltip = lang == 'ar'
        ? 'الدولة والعملة النشطة: ${activeCountry.fullNameAr} (${activeCountry.currencySymbol})'
        : (lang == 'hi'
            ? 'सक्रिय देश और मुद्रा: ${activeCountry.fullName(lang)} (${activeCountry.currencySymbolFor(lang)})'
            : 'Active Country & Currency: ${activeCountry.fullName(lang)} (${activeCountry.currencySymbolFor(lang)})');

    return M3ActionMenu(
      tooltip: countryTooltip,
      anchorBuilder: (context, controller, child) {
        return InkWell(
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 5 : 12,
              vertical: isMobile ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  activeCountry.flagEmoji,
                  style: TextStyle(fontSize: isMobile ? 14 : 16),
                ),
                SizedBox(width: isMobile ? 3 : 6),
                if (!isMobile) ...[
                  Text(
                    activeCountry.name(lang),
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    activeCountry.currencySymbolFor(lang),
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 10 : 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: isMobile ? 16 : 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
      children: [
        M3ActionMenu.header(
          context: context,
          title: lang == 'ar' ? 'الدولة والعملة' : 'Country & Currency',
        ),
        ...CountryCurrencyConfig.supportedCountries.map((country) {
          final isCurrent = country.code == activeCountry.code;
          return M3ActionMenu.item(
            context: context,
            label: '${country.fullName(lang)} (${country.currencySymbolFor(lang)})',
            leading: Text(country.flagEmoji, style: const TextStyle(fontSize: 18)),
            isSelected: isCurrent,
            onPressed: () {
              ref.read(activeCountryProvider.notifier).state = country;
            },
          );
        }),
      ],
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
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 10,
        ),
        child: Wrap(
          spacing: 14,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 1. Copyright Text
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.copyright_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  SwitchPointInfo.copyright,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // 2. Powered by Switch Point Smart Systems Badge (links to website)
            InkWell(
              onTap: () => SwitchPointInfo.launchLink(SwitchPointInfo.websiteUrl),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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

            // 3. Email Support
            _buildFooterPill(
              context: context,
              icon: Icons.mail_outline_rounded,
              label: SwitchPointInfo.supportEmail,
              url: 'mailto:${SwitchPointInfo.supportEmail}',
            ),

            // 4. WhatsApp Egypt Pill (M3 Theme Blue & Google Icon)
            _buildFooterPill(
              context: context,
              icon: Icons.chat_bubble_outline_rounded,
              label: 'WhatsApp Egypt',
              tooltip: 'Contact via WhatsApp Egypt (${SwitchPointInfo.whatsappEgypt})',
              url: SwitchPointInfo.whatsappEgyptUrl,
            ),

            // 5. WhatsApp UAE Pill (M3 Theme Blue & Google Icon)
            _buildFooterPill(
              context: context,
              icon: Icons.chat_bubble_outline_rounded,
              label: 'WhatsApp UAE',
              tooltip: 'Contact via WhatsApp UAE (${SwitchPointInfo.whatsappUae})',
              url: SwitchPointInfo.whatsappUaeUrl,
            ),
          ],
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
          Icon(
            icon,
            size: 14,
            color: iconColor,
          ),
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
    final isDark = themeMode == ThemeMode.dark ||
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
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: ClipOval(
                      child: Image.network(
                        companyLogoUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, st) => Icon(Icons.business_rounded, color: colorScheme.primary, size: 20),
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
                        isAr ? 'القائمة الرئيسية والإعدادات' : (isHindi ? 'मुख्य मेनू और सेटिंग्स' : 'Main Menu & Settings'),
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
                      isAr ? 'إجراءات الحملة والبرموتر:' : (isHindi ? 'प्रचार और प्रमोटर क्रियाएं:' : 'Campaign & Promoter Actions:'),
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
                        color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
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
                    isAr ? 'إعدادات اللغة والمظهر:' : (isHindi ? 'भाषा और उपस्थिति सेटिंग्स:' : 'Language & Display Settings:'),
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
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Language Selector
                        Row(
                          children: [
                            Icon(Icons.translate_rounded, size: 18, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              isAr ? 'لغة التطبيق' : (isHindi ? 'ऐप की भाषा' : 'App Language'),
                              style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: currentLangCode,
                              isExpanded: true,
                              icon: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: colorScheme.onSurfaceVariant),
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
                            Icon(Icons.payments_rounded, size: 18, color: colorScheme.secondary),
                            const SizedBox(width: 8),
                            Text(
                              isAr ? 'الدولة والعملة المعتمدة' : (isHindi ? 'देश और मुद्रा' : 'Country & Currency'),
                              style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: activeCountry.code,
                              isExpanded: true,
                              icon: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                              dropdownColor: colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(12),
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                              items: CountryCurrencyConfig.supportedCountries.map((country) {
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
                                  final country = CountryCurrencyConfig.findByCode(val);
                                  ref.read(activeCountryProvider.notifier).state = country;
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
                            isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                            color: isDark ? Colors.amber : colorScheme.primary,
                            size: 20,
                          ),
                          title: Text(
                            isAr
                                ? (isDark ? 'الوضع الداكن (مفعل)' : 'الوضع الفاتح (مفعل)')
                                : (isHindi
                                    ? (isDark ? 'डार्क मोड (सक्रिय)' : 'लाइट मोड (सक्रिय)')
                                    : (isDark ? 'Dark Mode (Active)' : 'Light Mode (Active)')),
                            style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            isAr ? 'تبديل المظهر بين الوضع الليلي والنهاري' : (isHindi ? 'दिन और रात के मोड के बीच स्विच करें' : 'Toggle between Dark and Light mode'),
                            style: GoogleFonts.cairo(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                          ),
                          value: isDark,
                          onChanged: (val) {
                            ref.read(themeModeProvider.notifier).state = val ? ThemeMode.dark : ThemeMode.light;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Contact Us & Support Section (Moved from footer)
                  Text(
                    isAr ? 'تواصل معنا والدعم الفني:' : (isHindi ? 'हमसे संपर्क करें और तकनीकी सहायता:' : 'Contact Us & Technical Support:'),
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
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        // WhatsApp Egypt
                        ListTile(
                          dense: true,
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.chat_rounded, color: Colors.green.shade700, size: 18),
                          ),
                          title: Text(
                            'WhatsApp (مصر)',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            SwitchPointInfo.whatsappEgypt,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                          onTap: () => SwitchPointInfo.launchLink(SwitchPointInfo.whatsappEgyptUrl),
                        ),
                        const Divider(height: 1),

                        // WhatsApp UAE
                        ListTile(
                          dense: true,
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.chat_rounded, color: Colors.green.shade700, size: 18),
                          ),
                          title: Text(
                            'WhatsApp (الإمارات)',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            SwitchPointInfo.whatsappUae,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                          onTap: () => SwitchPointInfo.launchLink(SwitchPointInfo.whatsappUaeUrl),
                        ),
                        const Divider(height: 1),

                        // Support Email
                        ListTile(
                          dense: true,
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.mail_outline_rounded, color: Colors.blue.shade700, size: 18),
                          ),
                          title: Text(
                            isAr ? 'البريد الإلكتروني للدعم' : 'Support Email',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            SwitchPointInfo.supportEmail,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                          onTap: () => SwitchPointInfo.launchEmail(SwitchPointInfo.supportEmail),
                        ),
                        const Divider(height: 1),

                        // Official Website
                        ListTile(
                          dense: true,
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.public_rounded, color: Colors.purple.shade700, size: 18),
                          ),
                          title: Text(
                            isAr ? 'موقع سويتش بوينت الرسمي' : 'Switch Point Website',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            SwitchPointInfo.websiteDisplay,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                          onTap: () => SwitchPointInfo.launchLink(SwitchPointInfo.websiteUrl),
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
                          SwitchPointInfo.copyright,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
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
