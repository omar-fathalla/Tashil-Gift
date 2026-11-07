import 'dart:js_interop';

@JS('tashilHardReload')
external JSPromise<JSAny?>? _hardReload();

@JS('window.location.reload')
external void _reload();

/// Unregisters the service worker, clears Cache Storage and reloads so the
/// browser really fetches the newest build (see web/index.html).
void reloadPage() {
  try {
    _hardReload();
  } catch (_) {
    _reload();
  }
}
