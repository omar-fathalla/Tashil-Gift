import 'package:flutter/semantics.dart';

/// Maestro web (TAG-82 PR 3) reads the browser's accessibility tree, and
/// Flutter web builds that tree only after the user turns on accessibility.
/// An e2e build passes `--dart-define=E2E_SEMANTICS=true` to build it from the
/// start. A normal build (prod or dev) leaves this false and is unchanged.
const bool kE2eSemantics = bool.fromEnvironment('E2E_SEMANTICS');

SemanticsHandle? _e2eSemanticsHandle;

/// Call once in `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
void enableE2eSemanticsIfRequested() {
  if (!kE2eSemantics || _e2eSemanticsHandle != null) return;
  _e2eSemanticsHandle = SemanticsBinding.instance.ensureSemantics();
}

/// Stable `Semantics(identifier: ...)` values the e2e flows select by, so a
/// flow does not depend on the Arabic text or the browser locale. Keep them in
/// sync with `maestro/**`.
abstract final class E2eIds {
  static const loginEmail = 'e2e-login-email';
  static const loginPassword = 'e2e-login-password';
  static const loginSubmit = 'e2e-login-submit';
  static const campaignCard = 'e2e-campaign-card';
  static const campaignActions = 'e2e-campaign-actions';
  static const campaignEdit = 'e2e-campaign-edit';
  static const campaignEditorTitle = 'e2e-campaign-editor-title';
}
