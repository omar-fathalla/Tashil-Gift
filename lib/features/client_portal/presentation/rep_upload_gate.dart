import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/partner_portal_auth_service.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../auth/presentation/partner_portal_login_screen.dart';
import 'client_receipt_upload_screen.dart';

/// Login gate for the مندوب entry. After a `rep_uploader` session, the existing
/// campaign/branch picker and [ClientReceiptUploadScreen] run unchanged.
class RepUploadGate extends ConsumerStatefulWidget {
  final String companySlug;
  final String? initialEventId;

  const RepUploadGate({
    super.key,
    this.companySlug = '',
    this.initialEventId,
  });

  @override
  ConsumerState<RepUploadGate> createState() => _RepUploadGateState();
}

class _RepUploadGateState extends ConsumerState<RepUploadGate> {
  late String _slug;
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _slug = widget.companySlug.trim().toLowerCase();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _continueWithCode() {
    final slug = _codeController.text.trim().toEnglishDigits(convertDecimal: false).toLowerCase();
    if (slug.isEmpty) return;
    setState(() => _slug = slug);
  }

  @override
  Widget build(BuildContext context) {
    if (_slug.isEmpty) {
      return _RepCompanyCodeScreen(
        controller: _codeController,
        focusNode: _codeFocus,
        onContinue: _continueWithCode,
      );
    }
    return PortalAuthGuard(
      companySlug: _slug,
      eventId: widget.initialEventId,
      requiredRole: PartnerPortalRole.repUploader,
      authenticatedBuilder: (context, session) => ClientReceiptUploadScreen(
        companySlug: _slug,
        initialEventId: widget.initialEventId,
      ),
    );
  }
}

class _RepCompanyCodeScreen extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onContinue;

  const _RepCompanyCodeScreen({
    required this.controller,
    required this.focusNode,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAr = Directionality.of(context) == TextDirection.rtl;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.storefront_rounded, size: 40, color: colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    isAr ? 'حساب المندوب' : 'Field rep',
                    style: GoogleFonts.cairo(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAr
                        ? 'اكتب كود شركة الدعاية، ثم سجّل الدخول بحساب المندوبين.'
                        : 'Enter the agency code, then sign in with the rep account.',
                    style: GoogleFonts.cairo(fontSize: 14, color: colorScheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    inputFormatters: const [ArabicToEnglishDigitsFormatter()],
                    decoration: InputDecoration(
                      labelText: isAr ? 'كود الشركة' : 'Company code',
                      prefixIcon: const Icon(Icons.tag_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => onContinue(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: onContinue,
                      child: Text(
                        isAr ? 'متابعة' : 'Continue',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
