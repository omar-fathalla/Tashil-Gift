import 'dart:js_interop';

@JS('window.location.reload')
external void _reload();

/// Reloads the current page so the browser fetches the newest build.
void reloadPage() => _reload();
