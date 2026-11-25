/// TAG-43: browser "leave page?" warning while a campaign save is unfinished,
/// and the browser's user agent for the save failure log. No-ops off the web.
library;

export 'leave_page_guard_stub.dart'
    if (dart.library.js_interop) 'leave_page_guard_web.dart';
