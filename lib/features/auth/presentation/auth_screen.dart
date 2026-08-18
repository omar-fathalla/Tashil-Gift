import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/localization/app_strings.dart';
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
      final rememberMePref = prefs.getBool('remember_admin_me') ?? true;
      if (mounted) {
        setState(() {
          _rememberMe = rememberMePref;
          if (savedEmail != null && savedEmail.isNotEmpty) {
            _emailController.text = savedEmail;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: strings.invalidAdminCredentialsMsg)),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
        subtitle: strings.authPortalSubtitle,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Card(
                    elevation: 0,
                    color: colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.admin_panel_settings_rounded,
                                  size: 44,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              strings.authSignInTitle,
                              style: GoogleFonts.cairo(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              strings.authSignInSubtitle,
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            // Security badge
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.shield_rounded, size: 14, color: Colors.teal),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        strings.secureAdminPortalBadge,
                                        style: GoogleFonts.cairo(
                                          fontSize: 11,
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
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _emailController,
                              style: GoogleFonts.cairo(),
                              decoration: InputDecoration(
                                labelText: strings.authEmailLabel,
                                labelStyle: GoogleFonts.cairo(),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: Icon(Icons.email_outlined, color: colorScheme.primary),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return strings.authEmailValidation;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: GoogleFonts.cairo(),
                              decoration: InputDecoration(
                                labelText: strings.authPasswordLabel,
                                labelStyle: GoogleFonts.cairo(),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: Icon(Icons.lock_outline_rounded, color: colorScheme.primary),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                    color: colorScheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return strings.authPasswordValidation;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
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
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                        onChanged: (val) => setState(() => _rememberMe = val ?? true),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      strings.rememberMe,
                                      style: GoogleFonts.cairo(
                                        fontSize: 13,
                                        color: colorScheme.onSurface,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _isLoading ? null : () => _login(strings),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.all(16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(
                                      strings.authSignInBtn,
                                      style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
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
          ),
          const SwitchPointFooter(),
        ],
      ),
    );
  }
}

