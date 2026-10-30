// 2.0.148+209: browser-native receipt resize (web only); null elsewhere.
export 'web_image_resizer_stub.dart'
    if (dart.library.js_interop) 'web_image_resizer_web.dart';
