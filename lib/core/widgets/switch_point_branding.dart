import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../constants/country_currency_config.dart';
import '../constants/app_version_config.dart';
import '../localization/locale_provider.dart';

/// Company constants & metadata for Switch Point & Tashil Gift System
class SwitchPointInfo {
  static const String companyName = 'Switch Point';
  static const String companyNameAr = 'سويتش بوينت';
  static const String platformName = 'Tashil Gift';
  static const String platformSubtitle = 'حلول الترويج والتحقق الذكي متعدد الشركات';
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

  const SwitchPointHeader({
    super.key,
    this.leading,
    this.subtitle,
    this.customActions,
    this.showMobileMenu = true,
    this.companyLogoUrl,
    this.onMobileMenuPressed,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && theme.brightness == Brightness.dark);

    final activeCountry = ref.watch(activeCountryProvider);
    final isAr = ref.isArabic;

    if (isMobile) {
      return SafeArea(
        bottom: false,
        child: Container(
          height: 56,
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
            horizontal: 8,
            vertical: 4,
          ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Natural START: Company / Brand Logo
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 4),
                ],
                _buildMobileLogo(context, colorScheme),
              ],
            ),

            // 2. Middle: The 3 In-Store Action Icons (Brief, Gift Stock, Invoices Log)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: customActions != null && customActions!.isNotEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: customActions!,
                          ),
                        ),
                      )
                    : Text(
                        subtitle ?? (isAr ? SwitchPointInfo.companyNameAr : SwitchPointInfo.companyName),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
              ),
            ),

            // 3. Natural END: Sleek 3-Lines Mobile Menu (Language, Country, Dark Mode)
            if (showMobileMenu)
              IconButton(
                icon: const Icon(Icons.menu_rounded, size: 24),
                tooltip: isAr ? 'القائمة والإعدادات (اللغة، الدولة، المظهر)' : 'Menu & Settings',
                color: colorScheme.primary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                onPressed: () {
                  if (onMobileMenuPressed != null) {
                    onMobileMenuPressed!();
                  } else {
                    SwitchPointMobileMenuSheet.show(
                      context,
                      subtitle: subtitle,
                      companyLogoUrl: companyLogoUrl,
                      customActions: null,
                    );
                  }
                },
              )
            else
              const SizedBox(width: 36),
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
        horizontal: 16,
        vertical: 4,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 8),
          ],

          // Switch Point Brand Logo & Title with click-to-website
          Expanded(
            child: InkWell(
              onTap: () => SwitchPointInfo.launchLink(SwitchPointInfo.websiteUrl),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary,
                            colorScheme.tertiary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.hub_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  SwitchPointInfo.platformName,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.cairo(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Tooltip(
                                message: AppVersionConfig.tooltipText,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    AppVersionConfig.versionDisplay,
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            subtitle ?? (isAr ? 'حلول الترويج والتحقق الذكي متعدد الشركات' : (ref.isHindi ? 'स्मार्ट मल्टी-कंपनी प्रचार और एआई सत्यापन' : 'Smart Multi-Company Promotion & AI Verification')),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Custom Actions (e.g. Preview button)
          if (customActions != null) ...customActions!,

          const SizedBox(width: 8),

          // Language Switcher (العربية / English / हिन्दी)
          _buildLanguageSelector(context, ref, colorScheme, false, isAr),

          const SizedBox(width: 8),

          // Country & Currency Selector
          _buildCountryCurrencySelector(context, ref, colorScheme, false, activeCountry),

          const SizedBox(width: 8),

          // Theme Mode Switcher (Dark / Light)
          _buildThemeModeButton(ref, colorScheme, isDark, false),
        ],
      ),
    );
  }

  Widget _buildMobileLogo(BuildContext context, ColorScheme colorScheme) {
    return Tooltip(
      message: AppVersionConfig.tooltipText,
      child: InkWell(
        onTap: () => SwitchPointInfo.launchLink(SwitchPointInfo.websiteUrl),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary,
                  colorScheme.tertiary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.hub_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeModeButton(
    WidgetRef ref,
    ColorScheme colorScheme,
    bool isDark,
    bool isMobile,
  ) {
    return IconButton(
      icon: Icon(
        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
        color: isDark ? Colors.amber : colorScheme.onSurfaceVariant,
        size: isMobile ? 18 : 24,
      ),
      padding: EdgeInsets.all(isMobile ? 4 : 8),
      constraints: isMobile ? const BoxConstraints() : null,
      tooltip: isDark
          ? 'التحويل للوضع الفاتح (Light Mode)'
          : 'التحويل للوضع الداكن (Dark Mode)',
      onPressed: () {
        ref.read(themeModeProvider.notifier).state =
            isDark ? ThemeMode.light : ThemeMode.dark;
      },
    );
  }

  Widget _buildLanguageSelector(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
    bool isMobile,
    bool isAr,
  ) {
    return PopupMenuButton<String>(
      tooltip: isAr
          ? 'تغيير لغة النظام'
          : (ref.isHindi ? 'भाषा बदलें' : 'Change System Language'),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      color: colorScheme.surfaceContainerHigh,
      elevation: 6,
      onSelected: (String code) {
        ref.setLocale(code);
      },
      itemBuilder: (BuildContext context) {
        return AppLanguage.values.map((lang) {
          final isSelected = ref.watch(localeProvider).languageCode == lang.code;
          return PopupMenuItem<String>(
            value: lang.code,
            child: Row(
              children: [
                Text(lang.flagEmoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Text(
                  lang.label,
                  style: GoogleFonts.cairo(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Icon(
                    Icons.check_rounded,
                    color: colorScheme.primary,
                    size: 18,
                  ),
                ],
              ],
            ),
          );
        }).toList();
      },
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

    return PopupMenuButton<CountryCurrency>(
      tooltip: countryTooltip,
      initialValue: activeCountry,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      color: colorScheme.surfaceContainerHigh,
      elevation: 6,
      onSelected: (CountryCurrency selected) {
        ref.read(activeCountryProvider.notifier).state = selected;
      },
      itemBuilder: (BuildContext context) {
        return CountryCurrencyConfig.supportedCountries.map((country) {
          final isCurrent = country.code == activeCountry.code;
          return PopupMenuItem<CountryCurrency>(
            value: country,
            child: Row(
              children: [
                Text(
                  country.flagEmoji,
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        country.fullName(lang),
                        style: GoogleFonts.cairo(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                          fontSize: 13,
                          color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '${country.currencyName(lang)} (${country.currencySymbolFor(lang)})',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: isCurrent ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_circle_rounded,
                    color: colorScheme.primary,
                    size: 18,
                  ),
                ],
              ],
            ),
          );
        }).toList();
      },
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
  }
}

/// Material Design 3 Persistent Footer for Switch Point Platform (English / LTR Format)
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

    final isMobile = screenWidth < 600;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 24,
          vertical: isMobile ? 6 : 14,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMobile) ...[
              // Compact Mobile View: Icons-only single row to minimize footer space
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  // Website Icon Button
                  _buildMobileIconPill(
                    context: context,
                    icon: Icons.public_rounded,
                    tooltip: 'Website: ${SwitchPointInfo.websiteDisplay}',
                    url: SwitchPointInfo.websiteUrl,
                  ),

                  // Email Support Icon Button
                  _buildMobileIconPill(
                    context: context,
                    icon: Icons.mail_outline_rounded,
                    tooltip: 'Email: ${SwitchPointInfo.supportEmail}',
                    url: 'mailto:${SwitchPointInfo.supportEmail}',
                  ),

                  // WhatsApp Egypt Icon Button
                  _buildMobileIconPill(
                    context: context,
                    icon: Icons.chat_rounded,
                    badgeText: 'EG',
                    tooltip: 'WhatsApp Egypt (${SwitchPointInfo.whatsappEgypt})',
                    url: SwitchPointInfo.whatsappEgyptUrl,
                    highlightColor: Colors.green.shade600,
                  ),

                  // WhatsApp UAE Icon Button
                  _buildMobileIconPill(
                    context: context,
                    icon: Icons.chat_rounded,
                    badgeText: 'UAE',
                    tooltip: 'WhatsApp UAE (${SwitchPointInfo.whatsappUae})',
                    url: SwitchPointInfo.whatsappUaeUrl,
                    highlightColor: Colors.green.shade600,
                  ),
                ],
              ),

              const SizedBox(height: 5),

              // Compact Mobile Copyright & Powered By
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 2,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.copyright_rounded,
                        size: 11,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '2026 Switch Point',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '•',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.outlineVariant,
                    ),
                  ),
                  InkWell(
                    onTap: () => SwitchPointInfo.launchLink(SwitchPointInfo.websiteUrl),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Powered by Switch Point',
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Desktop View: Clean & simple contact and links row in English (LTR)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Website Link
                  _buildFooterPill(
                    context: context,
                    icon: Icons.public_rounded,
                    label: SwitchPointInfo.websiteDisplay,
                    url: SwitchPointInfo.websiteUrl,
                  ),

                  // Email Support
                  _buildFooterPill(
                    context: context,
                    icon: Icons.mail_outline_rounded,
                    label: SwitchPointInfo.supportEmail,
                    url: 'mailto:${SwitchPointInfo.supportEmail}',
                  ),

                  // WhatsApp Egypt Icon Pill
                  _buildFooterPill(
                    context: context,
                    icon: Icons.chat_rounded,
                    label: 'WhatsApp Egypt',
                    tooltip: 'Contact via WhatsApp Egypt (${SwitchPointInfo.whatsappEgypt})',
                    url: SwitchPointInfo.whatsappEgyptUrl,
                    highlightColor: Colors.green.shade700,
                  ),

                  // WhatsApp UAE Icon Pill
                  _buildFooterPill(
                    context: context,
                    icon: Icons.chat_rounded,
                    label: 'WhatsApp UAE',
                    tooltip: 'Contact via WhatsApp UAE (${SwitchPointInfo.whatsappUae})',
                    url: SwitchPointInfo.whatsappUaeUrl,
                    highlightColor: Colors.green.shade700,
                  ),
                ],
              ),

              const SizedBox(height: 10),
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 8),

              // Copyright & Branding Row (LTR)
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Copyright Text
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copyright_rounded,
                          size: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          SwitchPointInfo.copyright,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),

                    // Powered by Switch Point Badge
                    InkWell(
                      onTap: () => SwitchPointInfo.launchLink(SwitchPointInfo.websiteUrl),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Powered by Switch Point Smart Systems',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Version Tag
                    Tooltip(
                      message: AppVersionConfig.tooltipText,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          AppVersionConfig.fullBuildDisplay,
                          style: GoogleFonts.cairo(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileIconPill({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required String url,
    String? badgeText,
    Color? highlightColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = highlightColor ?? colorScheme.primary;

    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => SwitchPointInfo.launchLink(url),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: badgeText != null ? 8 : 7,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: iconColor,
                ),
                if (badgeText != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    badgeText,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.tertiary],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
                  ),
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
                        Wrap(
                          spacing: 6,
                          children: AppLanguage.values.map((lang) {
                            final isSelected = currentLangCode == lang.code;
                            return ChoiceChip(
                              avatar: Text(lang.flagEmoji, style: const TextStyle(fontSize: 14)),
                              label: Text(
                                lang.label,
                                style: GoogleFonts.cairo(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (val) {
                                if (val) ref.setLocale(lang.code);
                              },
                            );
                          }).toList(),
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
                        Wrap(
                          spacing: 6,
                          children: CountryCurrencyConfig.supportedCountries.map((country) {
                            final isSelected = activeCountry.code == country.code;
                            return ChoiceChip(
                              avatar: Text(country.flagEmoji, style: const TextStyle(fontSize: 14)),
                              label: Text(
                                '${country.name(currentLangCode)} (${country.currencySymbolFor(currentLangCode)})',
                                style: GoogleFonts.cairo(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (val) {
                                if (val) ref.read(activeCountryProvider.notifier).state = country;
                              },
                            );
                          }).toList(),
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
