import 'dart:typed_data';

class WebResizedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  const WebResizedImage(this.bytes, this.width, this.height);
}

/// Non-web builds: no browser decoder, caller uses the Dart calibrator.
Future<WebResizedImage?> resizeReceiptInBrowser(
  Uint8List bytes, {
  required int maxWidth,
  required int maxHeight,
  required int quality,
  required double contrast,
  required double brightness,
}) async =>
    null;
