import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/localization/locale_provider.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/partner_portal_auth_service.dart';
import '../../../core/widgets/tashil_gift_logo.dart';

/// Material Design 3 Auth Guard for Partner Portals:
/// - Brand Executive Portal (`/portal/:slug`, `/p/:slug`, `/brand/:slug`, `/company/:slug`)
/// - Agency Operations Portal (`/ops/:slug`, `/agency/:slug`, `/operations/:slug`, `/ep/:id`)
///
/// Features:
/// - Seamless bypass when logged in as a System Admin (`isAdminProvider == true`).
/// - Validates saved Remember-Me or in-memory session against live Firestore `credentialVersion`.
/// - Enforces strict role isolation (`brand_manager` vs `agency_ops`).
/// - Passes the active [PartnerPortalSession] (including optional `lockedEventId` for Tier-2 campaign overrides)
///   to [authenticatedBuilder] or renders [child].
class PortalAuthGuard extends ConsumerStatefulWidget {
  final String? companySlug;
  final String? eventId;
  final PartnerPortalRole requiredRole;
  final Widget? child;
  final Widget Function(BuildContext context, PartnerPortalSession? session)? authenticatedBuilder;

  const PortalAuthGuard({
    super.key,
    this.companySlug,
    this.eventId,
    required this.requiredRole,
    this.child,
    this.authenticatedBuilder,
  }) : assert(child != null || authenticatedBuilder != null, 'Provide either child or authenticatedBuilder');

  @override
  ConsumerState<PortalAuthGuard> createState() => _PortalAuthGuardState();
}

class _PortalAuthGuardState extends ConsumerState<PortalAuthGuard> {
  bool _isCheckingSession = true;
  PartnerPortalSession? _activeSession;
  String _resolvedCompanySlug = '';
  String _resolvedCompanyName = '';
  String? _resolvedEventName;
  int _lastCheckedEpoch = -1;

  @override
  void initState() {
    super.initState();
    _verifySession();
  }

  @override
  void didUpdateWidget(covariant PortalAuthGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companySlug != widget.companySlug ||
        oldWidget.eventId != widget.eventId ||
        oldWidget.requiredRole != widget.requiredRole) {
      _verifySession();
    }
  }

  Future<void> _verifySession() async {
    if (!mounted) return;
    setState(() => _isCheckingSession = true);

    try {
      final authService = ref.read(partnerPortalAuthServiceProvider);
      final resolved = await authService.resolveCredentials(
        companySlug: widget.companySlug ?? '',
        eventId: widget.eventId,
      );

      final session = await authService.getValidSession(
        companySlug: resolved.companySlug,
        requiredRole: widget.requiredRole,
        eventId: widget.eventId,
      );

      if (!mounted) return;
      setState(() {
        _resolvedCompanySlug = resolved.companySlug;
        _resolvedCompanyName = resolved.companyName;
        _resolvedEventName = resolved.eventName;
        _activeSession = session;
        _isCheckingSession = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activeSession = null;
        _isCheckingSession = false;
      });
    }
  }

  void _handleLoginSuccess(PartnerPortalSession session) {
    if (!mounted) return;
    ref.read(partnerPortalAdminBypassRevokedProvider.notifier).state = false;
    setState(() {
      _activeSession = session;
      _isCheckingSession = false;
    });
    ref.read(partnerPortalSessionEpochProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final isBypassRevoked = ref.watch(partnerPortalAdminBypassRevokedProvider);
    final sessionEpoch = ref.watch(partnerPortalSessionEpochProvider);

    if (_lastCheckedEpoch != -1 && _lastCheckedEpoch != sessionEpoch) {
      _lastCheckedEpoch = sessionEpoch;
      _activeSession = null;
      _isCheckingSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _verifySession());
    } else {
      _lastCheckedEpoch = sessionEpoch;
    }

    // System Admin seamless preview bypass (honored only if bypass was not explicitly revoked via sign out)
    if (isAdmin && !isBypassRevoked) {
      if (widget.authenticatedBuilder != null) {
        return widget.authenticatedBuilder!(context, _activeSession);
      }
      return widget.child!;
    }

    if (_isCheckingSession) {
      final colorScheme = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'جاري التحقق من صلاحية الدخول...',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_activeSession != null && _activeSession!.role == widget.requiredRole) {
      if (widget.authenticatedBuilder != null) {
        return widget.authenticatedBuilder!(context, _activeSession);
      }
      return widget.child!;
    }

    return PartnerPortalLoginScreen(
      companySlug: _resolvedCompanySlug.isNotEmpty ? _resolvedCompanySlug : (widget.companySlug ?? ''),
      companyName: _resolvedCompanyName,
      eventId: widget.eventId,
      eventName: _resolvedEventName,
      requiredRole: widget.requiredRole,
      onAuthenticated: _handleLoginSuccess,
    );
  }
}

/// Material Design 3 Partner Portal Login Screen
/// Supports Brand Executive Portal (`brand_manager`) and Agency Operations Portal (`agency_ops`).
class PartnerPortalLoginScreen extends ConsumerStatefulWidget {
  final String companySlug;
  final String companyName;
  final String? eventId;
  final String? eventName;
  final PartnerPortalRole requiredRole;
  final ValueChanged<PartnerPortalSession> onAuthenticated;

  const PartnerPortalLoginScreen({
    super.key,
    required this.companySlug,
    this.companyName = '',
    this.eventId,
    this.eventName,
    required this.requiredRole,
    required this.onAuthenticated,
  });

  @override
  ConsumerState<PartnerPortalLoginScreen> createState() => _PartnerPortalLoginScreenState();
}

class _PartnerPortalLoginScreenState extends ConsumerState<PartnerPortalLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _rememberMe = true;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(partnerPortalAuthServiceProvider);
      final result = await authService.authenticate(
        companySlug: widget.companySlug,
        requiredRole: widget.requiredRole,
        username: _usernameController.text,
        password: _passwordController.text,
        rememberMe: _rememberMe,
        eventId: widget.eventId,
      );

      if (!mounted) return;
      final isAr = ref.read(localeProvider).languageCode == 'ar';

      if (result.isSuccess && result.session != null) {
        widget.onAuthenticated(result.session!);
      } else {
        setState(() {
          _errorMessage = isAr
              ? (result.errorMessageAr ?? 'بيانات الدخول غير صحيحة')
              : (result.errorMessageEn ?? 'Invalid login credentials');
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final isAr = ref.read(localeProvider).languageCode == 'ar';
      setState(() {
        _errorMessage = isAr
            ? 'حدث خطأ أثناء التحقق من بيانات الدخول، يرجى المحاولة مرة أخرى.'
            : 'An error occurred while verifying credentials. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final isAr = locale.languageCode == 'ar';
    final isBrandRole = widget.requiredRole == PartnerPortalRole.brandManager;

    final displayCompany = widget.companyName.trim().isNotEmpty
        ? widget.companyName.trim()
        : (widget.companySlug.trim().isNotEmpty ? widget.companySlug.toUpperCase() : 'Tashil Gift');

    final portalTitle = isBrandRole
        ? (isAr ? 'البوابة التنفيذية للشركة والـ ROI' : 'Brand Executive & ROI Portal')
        : (isAr ? 'بوابة شركة الدعاية والعمليات الميدانية' : 'Agency Field Operations Portal');

    final portalSubtitle = isBrandRole
        ? (isAr
            ? 'متابعة حية لمؤشرات المبيعات، أداء الفروع، التحليلات الذكية، وأرصدة الهدايا (للاطلاع)'
            : 'Live sales analytics, branch performance, AI insights, and read-only stock balances')
        : (isAr
            ? 'إدارة وتوزيع أرصدة الهدايا بالفروع، التسويات الميدانية، ومتابعة الفواتير لحظياً'
            : 'Manage & distribute branch gift stock, field settlements, and live receipt operations');

    final roleBadgeText = isBrandRole
        ? (isAr ? 'بوابة المدير العام والعلامة التجارية' : 'Brand Manager Access')
        : (isAr ? 'بوابة مشرفي العمليات والوكالة' : 'Agency Operations Access');

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Brand Logo & Language Toggle Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const TashilGiftLogo(size: 36),
                          OutlinedButton.icon(
                            onPressed: () {
                              ref.read(localeProvider.notifier).state =
                                  isAr ? const Locale('en') : const Locale('ar');
                            },
                            icon: const Icon(Icons.language_rounded, size: 16),
                            label: Text(
                              isAr ? 'English' : 'العربية',
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Role Badge Pill
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isBrandRole
                                ? colorScheme.secondaryContainer
                                : colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isBrandRole
                                    ? Icons.business_center_rounded
                                    : Icons.store_mall_directory_rounded,
                                size: 16,
                                color: isBrandRole
                                    ? colorScheme.onSecondaryContainer
                                    : colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  roleBadgeText,
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isBrandRole
                                        ? colorScheme.onSecondaryContainer
                                        : colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Company / Campaign Header
                      Text(
                        displayCompany,
                        style: GoogleFonts.cairo(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (widget.eventName != null && widget.eventName!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.eventName!.trim(),
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        portalTitle,
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        portalSubtitle,
                        style: GoogleFonts.cairo(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Error Banner
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, color: colorScheme.onErrorContainer, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.cairo(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Username Input
                      TextFormField(
                        controller: _usernameController,
                        focusNode: _usernameFocus,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: isAr ? 'اسم المستخدم' : 'Username',
                          hintText: isBrandRole
                              ? 'brand_${widget.companySlug.isNotEmpty ? widget.companySlug : 'company'}'
                              : 'ops_${widget.companySlug.isNotEmpty ? widget.companySlug : 'company'}',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return isAr ? 'يرجى إدخال اسم المستخدم' : 'Please enter username';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password Input
                      TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submitLogin(),
                        decoration: InputDecoration(
                          labelText: isAr ? 'كلمة المرور' : 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: isAr
                                ? (_obscurePassword ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور')
                                : (_obscurePassword ? 'Show password' : 'Hide password'),
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return isAr ? 'يرجى إدخال كلمة المرور' : 'Please enter password';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Remember Me Checkbox
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _rememberMe = !_rememberMe),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (val) => setState(() => _rememberMe = val ?? true),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  isAr
                                      ? 'تذكرني على هذا الجهاز للدخول السريع بضغطة واحدة'
                                      : 'Remember me on this device for instant 1-click access',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Submit Button
                      SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _isSubmitting ? null : _submitLogin,
                          icon: _isSubmitting
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.login_rounded, size: 20),
                          label: Text(
                            _isSubmitting
                                ? (isAr ? 'جاري تسجيل الدخول...' : 'Signing in...')
                                : (isAr ? 'تسجيل الدخول للبوابة' : 'Sign In to Portal'),
                            style: GoogleFonts.cairo(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
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
