import 'dart:js_interop';

import 'package:flutter/foundation.dart';

class WebResizedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  const WebResizedImage(this.bytes, this.width, this.height);
}

extension type _ResizeResult._(JSObject _) implements JSObject {
  external JSUint8Array get bytes;
  external int get width;
  external int get height;
}

@JS('tashilResizeReceiptImage')
external JSFunction? get _resizeFn;

@JS('tashilResizeReceiptImage')
external JSPromise<_ResizeResult?> _resize(
  JSUint8Array bytes,
  int maxW,
  int maxH,
  int quality,
  double contrast,
  double brightness,
);

/// Decode/resize/contrast/JPEG-encode with the browser (see web/index.html).
/// Handles HEIC on iOS Safari and EXIF orientation, avoids the slow pure-Dart
/// decode on the main thread. Returns null if unavailable or it failed.
Future<WebResizedImage?> resizeReceiptInBrowser(
  Uint8List bytes, {
  required int maxWidth,
  required int maxHeight,
  required int quality,
  required double contrast,
  required double brightness,
}) async {
  try {
    if (_resizeFn == null) return null;
    final r = await _resize(
      bytes.toJS,
      maxWidth,
      maxHeight,
      quality,
      contrast,
      brightness,
    ).toDart;
    if (r == null) return null;
    final out = r.bytes.toDart;
    if (out.isEmpty) return null;
    return WebResizedImage(out, r.width, r.height);
  } catch (e) {
    debugPrint('[web_image_resizer] browser resize failed: $e');
    return null;
  }
}
