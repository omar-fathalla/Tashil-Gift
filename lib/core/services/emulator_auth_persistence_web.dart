import 'dart:html' as html;

/// Drops a persisted emulator session before Firebase starts.
///
/// The web SDK otherwise refreshes that session at `identitytoolkit.googleapis.com`
/// before `useAuthEmulator` can redirect it to localhost.
Future<void> clearEmulatorAuthPersistence() async {
  final factory = html.window.indexedDB;
  if (factory == null) return;
  try {
    // Another open tab can hold the database and block deletion. Startup must
    // not wait on that.
    await factory
        .deleteDatabase('firebaseLocalStorageDb')
        .timeout(const Duration(milliseconds: 400));
  } catch (_) {}
}
