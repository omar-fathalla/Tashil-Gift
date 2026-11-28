import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window.addEventListener')
external void _addListener(JSString type, JSFunction listener);

@JS('window.removeEventListener')
external void _removeListener(JSString type, JSFunction listener);

@JS('navigator.userAgent')
external JSString? get _userAgent;

JSFunction? _listener;

void _onBeforeUnload(JSObject event) {
  // Standard way to ask the browser to show its "Leave site?" dialog.
  event.callMethod('preventDefault'.toJS);
  event['returnValue'] = ''.toJS;
}

/// Shows the browser's "Leave site?" dialog on refresh/close while [active].
void setLeavePageGuard(bool active) {
  try {
    if (active && _listener == null) {
      final f = _onBeforeUnload.toJS;
      _listener = f;
      _addListener('beforeunload'.toJS, f);
    } else if (!active && _listener != null) {
      _removeListener('beforeunload'.toJS, _listener!);
      _listener = null;
    }
  } catch (_) {}
}

String browserUserAgent() {
  try {
    return _userAgent?.toDart ?? '';
  } catch (_) {
    return '';
  }
}
