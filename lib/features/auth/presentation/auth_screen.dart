import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/widgets/switch_point_branding.dart';
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
      final savedEmail = prefs.getString('saved_admin_email');
      final savedPassword = prefs.getString('saved_admin_password');
      final rememberMePref = prefs.getBool('remember_admin_me') ?? true;
      if (mounted) {
        setState(() {
          _rememberMe = rememberMePref;
          if (savedEmail != null && savedEmail.isNotEmpty) {
            _emailController.text = savedEmail;
          } else {
            _emailController.text = kPrimaryAdminEmail;
          }
          if (_rememberMe && savedPassword != null && savedPassword.isNotEmpty) {
            _passwordController.text = savedPassword;
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

      await authService.signIn(email, password);

      // Save or clear Remember Me preference
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remember_admin_me', _rememberMe);
        if (_rememberMe) {
          await prefs.setString('saved_admin_email', email);
          await prefs.setString('saved_admin_password', password);
          await prefs.setString('active_admin_session', email.toLowerCase());
        } else {
          await prefs.remove('saved_admin_email');
          await prefs.remove('saved_admin_password');
          await prefs.remove('active_admin_session');
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
        final errorMsg = AppErrorHandler.getFriendlyMessage(
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
    final isAr = ref.isArabic;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
        subtitle: strings.authPortalSubtitle,
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWideScreen = constraints.maxWidth >= 768;

                if (isWideScreen) {
                  // Full-Height 50/50 Split Screen Layout with Harmonious System Theme
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Natural Start Half: System Showcase & Pillars (50% of screen)
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

                      // 2. Natural End Half: Clean Sign-In Pane (50% of screen)
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
                      // 1. Mobile Sign-In on Top
                      _buildCleanAuthHalf(
                        context: context,
                        colorScheme: colorScheme,
                        strings: strings,
                        isAr: isAr,
                        isMobile: true,
                      ),
                      // 2. System Showcase Below
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
    );
  }

  /// 🌟 50% System Showcase & Platform Pillars Pane (Full-Height / Edge-to-Edge)
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
      decoration: BoxDecoration(
        color: isDarkMode
            ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.35)
            : colorScheme.surfaceContainerLow,
        border: Border(
          // Subtle inner divider between the two halves
          left: !isAr && !isMobile
              ? BorderSide.none
              : (isAr && !isMobile
                  ? BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1)
                  : BorderSide.none),
          right: isAr && !isMobile
              ? BorderSide.none
              : (!isAr && !isMobile
                  ? BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1)
                  : BorderSide.none),
          top: isMobile
              ? BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4), width: 1)
              : BorderSide.none,
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 20 : (isTablet ? 24 : 40),
            vertical: isMobile ? 24 : 32,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Top Badges Row
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // Gemini 3.7 Flash AI Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.4),
                          width: 1.2,
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

                    // Anti-Fraud Governance Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.teal.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_user_rounded, size: 16, color: Colors.teal),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              strings.heroAntiFraudBadge,
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // 2. Brand Logo & Main Title
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary,
                            colorScheme.tertiary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.hub_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'منظومة سويتش بوينت الذكية' : 'Switch Point Smart Platform',
                            style: GoogleFonts.cairo(
                              fontSize: isTablet ? 23 : 27,
                              fontWeight: FontWeight.w900,
                              color: colorScheme.onSurface,
                              height: 1.15,
                            ),
                          ),
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
                    height: 1.55,
                  ),
                ),

                const SizedBox(height: 24),

                // 4. The 4 Core System Pillars (Spacious Cards without truncation)
                LayoutBuilder(
                  builder: (context, cardConstraints) {
                    final isSingleCol = cardConstraints.maxWidth < 520 || isMobile;
                    final cardWidth = isSingleCol
                        ? double.infinity
                        : ((cardConstraints.maxWidth - 16) / 2);

                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildPillarCard(
                          colorScheme: colorScheme,
                          icon: Icons.campaign_rounded,
                          iconColor: colorScheme.primary,
                          iconBgColor: colorScheme.primaryContainer.withValues(alpha: 0.45),
                          title: strings.heroPillar1Title,
                          description: strings.heroPillar1Desc,
                          width: cardWidth,
                        ),
                        _buildPillarCard(
                          colorScheme: colorScheme,
                          icon: Icons.document_scanner_rounded,
                          iconColor: Colors.amber.shade800,
                          iconBgColor: Colors.amber.withValues(alpha: 0.15),
                          title: strings.heroPillar2Title,
                          description: strings.heroPillar2Desc,
                          width: cardWidth,
                        ),
                        _buildPillarCard(
                          colorScheme: colorScheme,
                          icon: Icons.card_giftcard_rounded,
                          iconColor: Colors.teal.shade700,
                          iconBgColor: Colors.teal.withValues(alpha: 0.15),
                          title: strings.heroPillar3Title,
                          description: strings.heroPillar3Desc,
                          width: cardWidth,
                        ),
                        _buildPillarCard(
                          colorScheme: colorScheme,
                          icon: Icons.analytics_rounded,
                          iconColor: Colors.indigo.shade700,
                          iconBgColor: Colors.indigo.withValues(alpha: 0.15),
                          title: strings.heroPillar4Title,
                          description: strings.heroPillar4Desc,
                          width: cardWidth,
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                // 5. Quick Stats High-Contrast Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.spaceAround,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildStatPill(
                        colorScheme: colorScheme,
                        value: strings.heroStatSpeed,
                        label: strings.heroStatSpeedLabel,
                        icon: Icons.speed_rounded,
                        accentColor: colorScheme.primary,
                      ),
                      _buildStatPill(
                        colorScheme: colorScheme,
                        value: strings.heroStatAccuracy,
                        label: strings.heroStatAccuracyLabel,
                        icon: Icons.check_circle_outline_rounded,
                        accentColor: Colors.teal.shade700,
                      ),
                      _buildStatPill(
                        colorScheme: colorScheme,
                        value: strings.heroStatGovernance,
                        label: strings.heroStatGovernanceLabel,
                        icon: Icons.verified_rounded,
                        accentColor: Colors.amber.shade800,
                      ),
                    ],
                  ),
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
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String description,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.cairo(
              fontSize: 12,
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
    required Color accentColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: accentColor),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
                height: 1.1,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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
                            color: colorScheme.primaryContainer.withValues(alpha: 0.45),
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
                      // Security Badge
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.teal.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.shield_rounded, size: 15, color: Colors.teal),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  strings.secureAdminPortalBadge,
                                  style: GoogleFonts.cairo(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal.shade800,
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



