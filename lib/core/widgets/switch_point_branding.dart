import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../constants/country_currency_config.dart';
import '../localization/locale_provider.dart';

/// Company constants & metadata for Switch Point & Tashil Gift System
class SwitchPointInfo {
  static const String companyName = 'Switch Point';
  static const String companyNameAr = 'سويتش بوينت';
  static const String platformName = 'Tashil Gift';
  static const String platformSubtitle = 'حلول الترويج والتحقق الذكي متعدد الشركات';
  static const String websiteUrl = 'https://www.sw-point.com/';
  static const String websiteDisplay = 'www.switchpoint.com';
  static const String supportEmail = 'support@switchpoint.com';
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

  const SwitchPointHeader({
    super.key,
    this.leading,
    this.subtitle,
    this.customActions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(68);

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

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 16,
        vertical: isMobile ? 6 : 8,
      ),
      child: Row(
        children: [
          ?leading,

          // Switch Point Brand Logo & Title with click-to-website
          if (isMobile)
            InkWell(
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
            )
          else
            Flexible(
              child: InkWell(
                onTap: () => SwitchPointInfo.launchLink(SwitchPointInfo.websiteUrl),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
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
                              color: colorScheme.primary.withValues(alpha: 0.3),
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
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'v2.0',
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onPrimaryContainer,
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

          const Spacer(),

          // Custom Actions (e.g. Preview button)
          if (customActions != null) ...customActions!,

          SizedBox(width: isMobile ? 2 : 8),

          // Language Switcher (العربية / English / हिन्दी)
          PopupMenuButton<String>(
            tooltip: isAr ? 'تغيير لغة النظام' : (ref.isHindi ? 'भाषा बदलें' : 'Change System Language'),
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
                horizontal: isMobile ? 5 : 10,
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
          ),

          SizedBox(width: isMobile ? 2 : 8),

          // Country & Currency Selector
          _buildCountryCurrencySelector(context, ref, colorScheme, isMobile, activeCountry),

          SizedBox(width: isMobile ? 2 : 8),

          // Theme Mode Switcher (Dark / Light)
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: isDark ? Colors.amber : colorScheme.onSurfaceVariant,
              size: isMobile ? 18 : 24,
            ),
            padding: EdgeInsets.all(isMobile ? 4 : 8),
            constraints: isMobile ? const BoxConstraints() : null,
            tooltip: isDark ? 'التحويل للوضع الفاتح (Light Mode)' : 'التحويل للوضع الداكن (Dark Mode)',
            onPressed: () {
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
        ],
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
  const SwitchPointFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

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
          vertical: isMobile ? 10 : 14,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Clean & simple contact and links row in English (LTR)
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
                ),

                // WhatsApp UAE Icon Pill
                _buildFooterPill(
                  context: context,
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp UAE',
                  tooltip: 'Contact via WhatsApp UAE (${SwitchPointInfo.whatsappUae})',
                  url: SwitchPointInfo.whatsappUaeUrl,
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
                        isMobile ? '2026 Switch Point' : SwitchPointInfo.copyright,
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
                            isMobile ? 'Powered by Switch Point' : 'Powered by Switch Point Smart Systems',
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
                ],
              ),
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
