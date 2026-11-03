import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/widgets/tashil_gift_logo.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _rememberMe = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Clean up any legacy insecure keys
      await prefs.remove('saved_admin_password');
      await prefs.remove('active_admin_session');

      final savedEmail = prefs.getString('saved_admin_email');
      final rememberMePref = prefs.getBool('remember_admin_me') ?? true;

      if (mounted) {
        setState(() {
          _rememberMe = rememberMePref;
          if (savedEmail != null && savedEmail.isNotEmpty) {
            _emailController.text = savedEmail;
          } else {
            _emailController.text = kBootstrapSuperAdminEmail;
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login(AppStrings strings) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = ref.read(firebaseServiceProvider);
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      // 2.0.173: never spin forever (seen ~90s hangs when App Check stalls).
      await authService.signIn(email, password).timeout(const Duration(seconds: 30));

      // Save or clear Remember Me email preference (never passwords)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remember_admin_me', _rememberMe);
        await prefs.remove('active_admin_session');
        await prefs.remove('saved_admin_password');
        if (_rememberMe) {
          await prefs.setString('saved_admin_email', email);
        } else {
          await prefs.remove('saved_admin_email');
        }
      } catch (_) {}

      // On success, navigate to the Admin Dashboard
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        final isTimeout = e is TimeoutException;
        final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
        final errorMsg = isTimeout
            ? (isAr
                ? 'تسجيل الدخول أخد وقت أطول من المعتاد. تأكد من الاتصال وحاول مرة أخرى.'
                : 'Sign-in is taking too long. Check your connection and try again.')
            : AppErrorHandler.getFriendlyMessage(
                e,
                defaultMessage: strings.invalidAdminCredentialsMsg,
              );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorMsg,
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            duration: isTimeout ? const Duration(seconds: 10) : const Duration(seconds: 4),
            action: isTimeout
                ? SnackBarAction(
                    label: isAr ? 'إعادة المحاولة' : 'Retry',
                    textColor: Colors.white,
                    onPressed: () => _login(strings),
                  )
                : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(ref);
    final isAr = strings.languageCode == 'ar';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: SwitchPointHeader(
          subtitle: strings.authPortalSubtitle,
          showLanguageSelector: false,
          showCountryCurrencySelector: false,
          showDarkModeToggle: true,
        ),
        body: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWideScreen = constraints.maxWidth >= 768;

                  if (isWideScreen) {
                    // Full-Height 50/50 Split Screen Layout with Harmonious M3 Blue System Theme
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Left Half: System Showcase & Pillars (50% of screen)
                        Expanded(
                          flex: 1,
                          child: _buildShowcaseHalf(
                            context: context,
                            colorScheme: colorScheme,
                            strings: strings,
                            isAr: isAr,
                            isTablet: constraints.maxWidth < 1080,
                          ),
                        ),

                        // 2. Right Half: Clean Sign-In Pane (50% of screen)
                        Expanded(
                          flex: 1,
                          child: _buildCleanAuthHalf(
                            context: context,
                            colorScheme: colorScheme,
                            strings: strings,
                            isAr: isAr,
                          ),
                        ),
                      ],
                    );
                  }

                  // Mobile View: Login Form on Top, Highlights Below
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildCleanAuthHalf(
                          context: context,
                          colorScheme: colorScheme,
                          strings: strings,
                          isAr: isAr,
                          isMobile: true,
                        ),
                        _buildShowcaseHalf(
                          context: context,
                          colorScheme: colorScheme,
                          strings: strings,
                          isAr: isAr,
                          isMobile: true,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SwitchPointFooter(),
          ],
        ),
      ),
    );
  }

  /// 🌟 50% System Showcase & Platform Pillars Pane (Full-Width Symmetrical M3 Blue Layout)
  Widget _buildShowcaseHalf({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    bool isTablet = false,
    bool isMobile = false,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDarkMode
            ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.35)
            : colorScheme.surfaceContainerLow,
        border: BorderDirectional(
          end: !isMobile
              ? BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1)
              : BorderSide.none,
          top: isMobile
              ? BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4), width: 1)
              : BorderSide.none,
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 20 : (isTablet ? 24 : 36),
            vertical: isMobile ? 24 : 28,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Brand 'G' Logo & Main Title (Start of Showcase Content)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const TashilGiftLogo(size: 56),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.heroBrandHeadline,
                            style: GoogleFonts.cairo(
                              fontSize: isTablet ? 23 : 27,
                              fontWeight: FontWeight.w900,
                              color: colorScheme.onSurface,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tashil Gift • Retail & Brand Promotions',
                            style: GoogleFonts.cairo(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // 3. Platform Tagline
                Text(
                  strings.heroPlatformTagline,
                  style: GoogleFonts.cairo(
                    fontSize: isTablet ? 14 : 15,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 22),

                // 4. The 4 Core System Pillars (100% Full-Width Symmetrical 2x2 Grid)
                LayoutBuilder(
                  builder: (context, cardConstraints) {
                    final isSingleCol = cardConstraints.maxWidth < 500 || isMobile;

                    if (isSingleCol) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildPillarCard(
                            colorScheme: colorScheme,
                            icon: Icons.campaign_rounded,
                            title: strings.heroPillar1Title,
                            description: strings.heroPillar1Desc,
                          ),
                          const SizedBox(height: 12),
                          _buildPillarCard(
                            colorScheme: colorScheme,
                            icon: Icons.document_scanner_rounded,
                            title: strings.heroPillar2Title,
                            description: strings.heroPillar2Desc,
                          ),
                          const SizedBox(height: 12),
                          _buildPillarCard(
                            colorScheme: colorScheme,
                            icon: Icons.redeem_rounded,
                            title: strings.heroPillar3Title,
                            description: strings.heroPillar3Desc,
                          ),
                          const SizedBox(height: 12),
                          _buildPillarCard(
                            colorScheme: colorScheme,
                            icon: Icons.analytics_rounded,
                            title: strings.heroPillar4Title,
                            description: strings.heroPillar4Desc,
                          ),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _buildPillarCard(
                                  colorScheme: colorScheme,
                                  icon: Icons.campaign_rounded,
                                  title: strings.heroPillar1Title,
                                  description: strings.heroPillar1Desc,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildPillarCard(
                                  colorScheme: colorScheme,
                                  icon: Icons.document_scanner_rounded,
                                  title: strings.heroPillar2Title,
                                  description: strings.heroPillar2Desc,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _buildPillarCard(
                                  colorScheme: colorScheme,
                                  icon: Icons.redeem_rounded,
                                  title: strings.heroPillar3Title,
                                  description: strings.heroPillar3Desc,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildPillarCard(
                                  colorScheme: colorScheme,
                                  icon: Icons.analytics_rounded,
                                  title: strings.heroPillar4Title,
                                  description: strings.heroPillar4Desc,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 20),

                // 5. Full-Width Symmetrical Quick Stats Bar (100% matching width of Pillar Cards)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, statConstraints) {
                      if (statConstraints.maxWidth < 460) {
                        return Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          alignment: WrapAlignment.spaceAround,
                          children: [
                            _buildStatPill(
                              colorScheme: colorScheme,
                              value: strings.heroStatSpeed,
                              label: strings.heroStatSpeedLabel,
                              icon: Icons.speed_rounded,
                            ),
                            _buildStatPill(
                              colorScheme: colorScheme,
                              value: strings.heroStatAccuracy,
                              label: strings.heroStatAccuracyLabel,
                              icon: Icons.check_circle_outline_rounded,
                            ),
                            _buildStatPill(
                              colorScheme: colorScheme,
                              value: strings.heroStatGovernance,
                              label: strings.heroStatGovernanceLabel,
                              icon: Icons.verified_rounded,
                            ),
                          ],
                        );
                      }

                      return IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              child: Center(
                                child: _buildStatPill(
                                  colorScheme: colorScheme,
                                  value: strings.heroStatSpeed,
                                  label: strings.heroStatSpeedLabel,
                                  icon: Icons.speed_rounded,
                                ),
                              ),
                            ),
                            VerticalDivider(
                              width: 24,
                              thickness: 1,
                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                            Expanded(
                              child: Center(
                                child: _buildStatPill(
                                  colorScheme: colorScheme,
                                  value: strings.heroStatAccuracy,
                                  label: strings.heroStatAccuracyLabel,
                                  icon: Icons.check_circle_outline_rounded,
                                ),
                              ),
                            ),
                            VerticalDivider(
                              width: 24,
                              thickness: 1,
                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                            Expanded(
                              child: Center(
                                child: _buildStatPill(
                                  colorScheme: colorScheme,
                                  value: strings.heroStatGovernance,
                                  label: strings.heroStatGovernanceLabel,
                                  icon: Icons.verified_rounded,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 18),

                // 6. Badges Row: AI model & 100% Anti-Fraud Single-Resolution
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // AI model badge (AppStrings.heroGeminiModelBadge)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              strings.heroGeminiModelBadge,
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Anti-Fraud Governance Badge (Derived from M3 Dynamic Theme)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.28),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user_rounded, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              strings.heroAntiFraudBadge,
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSecondaryContainer,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillarCard({
    required ColorScheme colorScheme,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: GoogleFonts.cairo(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required ColorScheme colorScheme,
    required String value,
    required String label,
    required IconData icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 🏢 50% Clean Sign-In Pane (Spacious, Elevated, Full-Height)
  Widget _buildCleanAuthHalf({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    bool isMobile = false,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDarkMode
          ? colorScheme.surfaceContainer
          : colorScheme.surfaceContainerLowest,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 18 : 36,
            vertical: isMobile ? 20 : 36,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              elevation: 0,
              color: isDarkMode
                  ? colorScheme.surfaceContainerHigh
                  : colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 22.0 : 32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Lock/Admin Icon
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.admin_panel_settings_rounded,
                            size: 40,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Title
                      Text(
                        strings.authSignInTitle,
                        style: GoogleFonts.cairo(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      // Subtitle
                      Text(
                        strings.authSignInSubtitle,
                        style: GoogleFonts.cairo(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      // Security Badge (Derived from M3 Blue Theme)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_rounded, size: 15, color: colorScheme.primary),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  strings.secureAdminPortalBadge,
                                  style: GoogleFonts.cairo(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      // Email Field
                      TextFormField(
                        controller: _emailController,
                        style: GoogleFonts.cairo(fontSize: 14),
                        decoration: InputDecoration(
                          labelText: strings.authEmailLabel,
                          labelStyle: GoogleFonts.cairo(fontSize: 13),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          prefixIcon: Icon(Icons.email_outlined, color: colorScheme.primary, size: 20),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return strings.authEmailValidation;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: GoogleFonts.cairo(fontSize: 14),
                        decoration: InputDecoration(
                          labelText: strings.authPasswordLabel,
                          labelStyle: GoogleFonts.cairo(fontSize: 13),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          prefixIcon: Icon(Icons.lock_outline_rounded, color: colorScheme.primary, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return strings.authPasswordValidation;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      // Remember Me Checkbox
                      InkWell(
                        onTap: () => setState(() => _rememberMe = !_rememberMe),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                height: 24,
                                width: 24,
                                child: Checkbox(
                                  value: _rememberMe,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                  onChanged: (val) => setState(() => _rememberMe = val ?? true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  strings.rememberMe,
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Submit Button
                      FilledButton(
                        onPressed: _isLoading ? null : () => _login(strings),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                              )
                            : Text(
                                strings.authSignInBtn,
                                style: GoogleFonts.cairo(fontSize: 15.5, fontWeight: FontWeight.bold),
                              ),
                      ),
                      const SizedBox(height: 16),
                      // Security / Encryption Note
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            size: 13,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              strings.heroEnterpriseSecurityNote,
                              style: GoogleFonts.cairo(
                                fontSize: 10.5,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                              ),
                              textAlign: TextAlign.center,
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
      ),
    );
  }
}



