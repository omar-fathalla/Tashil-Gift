/// Whether field-rep receipt upload requires the `rep_uploader` login.
///
/// Public web deep links (`/c`, `/event`, `/promoter`, `/submit`) stay open
/// until the store app is live. The rep entry (`/rep/...`) always requires
/// login. Flip [runtimeOverride] later (or build with
/// `--dart-define=REQUIRE_REP_LOGIN=true`) to close the public links without
/// another routing change. Device binding is intentionally not part of this.
class RepLoginPolicy {
  static const bool compileTimeRequire = bool.fromEnvironment('REQUIRE_REP_LOGIN');

  /// Runtime switch. `null` means "use [compileTimeRequire]".
  static bool? runtimeOverride;

  static bool get requireRepLogin => runtimeOverride ?? compileTimeRequire;

  /// [repEntry] is the store/rep route. It always asks for login.
  /// Public upload links ask for login only when [requireRepLogin] is on.
  static bool requiresLogin({required bool repEntry}) => repEntry || requireRepLogin;

  static void setRuntimeOverride(bool? value) {
    runtimeOverride = value;
  }
}
