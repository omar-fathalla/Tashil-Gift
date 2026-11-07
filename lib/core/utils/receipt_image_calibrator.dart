import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'web_image_resizer.dart';

/// Holds the output metadata of client-side receipt image calibration.
class CalibratedImageResult {
  /// The calibrated, contrast-enhanced, and compressed JPEG bytes.
  final Uint8List bytes;

  /// Original byte size prior to calibration.
  final int originalSize;

  /// Calibrated byte size after downscaling, contrast adjustment, and compression.
  final int calibratedSize;

  /// Final pixel width.
  final int width;

  /// Final pixel height.
  final int height;

  /// Time spent in calibration.
  final Duration duration;

  /// Mime type of the calibrated image (always 'image/jpeg').
  final String mimeType;

  const CalibratedImageResult({
    required this.bytes,
    required this.originalSize,
    required this.calibratedSize,
    required this.width,
    required this.height,
    required this.duration,
    this.mimeType = 'image/jpeg',
  });

  /// Percentage of data saved through client-side calibration (e.g., 72.5%).
  double get compressionRatio {
    if (originalSize <= 0) return 0.0;
    final saved = originalSize - calibratedSize;
    if (saved <= 0) return 0.0;
    return (saved / originalSize) * 100.0;
  }

  /// Formatted percentage label (e.g. "-74.5%").
  String get compressionRatioLabel =>
      '-${compressionRatio.toStringAsFixed(1)}%';

  /// Total kilobytes saved.
  String get sizeSavedKbLabel {
    final savedBytes = originalSize - calibratedSize;
    if (savedBytes <= 0) return '0 KB';
    return '${(savedBytes / 1024).toStringAsFixed(0)} KB';
  }

  /// Formatted original size label (e.g. "3.4 MB" or "840 KB").
  String get originalSizeLabel => _formatBytes(originalSize);

  /// Formatted calibrated size label (e.g. "210 KB").
  String get calibratedSizeLabel => _formatBytes(calibratedSize);

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// Parameter envelope for receipt calibration (used across isolate boundaries or sync calls).
class CalibrationParams {
  final Uint8List rawBytes;
  final int maxWidth;
  final int maxHeight;
  final int quality;
  final double contrast;
  final double brightness;

  const CalibrationParams({
    required this.rawBytes,
    required this.maxWidth,
    required this.maxHeight,
    required this.quality,
    required this.contrast,
    required this.brightness,
  });
}

/// High-performance client-side receipt image calibration engine for Flutter.
///
/// Features:
/// 1. Automatic EXIF rotation baking (`bakeOrientation`).
/// 2. Thermal contrast enhancement (`contrast: 1.25`, `brightness: 1.05`) to
///    sharpen faint thermal ink while suppressing grey background paper noise.
/// 3. Aspect-ratio aware downscaling (max 1400px x 1600px).
/// 4. High-efficiency JPEG compression (quality: 78).
/// 5. Off-main-thread execution via [compute] on Mobile/Desktop, with
///    seamless synchronous fallback on Web.
/// 2.0.148+209: real MIME type from magic bytes, so raw (uncalibrated) bytes
/// such as iPhone HEIC are not mislabelled `image/jpeg` for Gemini.
String sniffImageMimeType(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return 'image/webp';
  }
  if (b.length >= 12 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
    final brand = String.fromCharCodes(b.sublist(8, 12)).toLowerCase();
    if (brand.startsWith('heic') || brand.startsWith('heix') ||
        brand.startsWith('hevc') || brand.startsWith('heim') ||
        brand.startsWith('heis')) {
      return 'image/heic';
    }
    if (brand.startsWith('mif1') || brand.startsWith('msf1') || brand.startsWith('heif')) {
      return 'image/heif';
    }
  }
  return 'image/jpeg';
}

class ReceiptImageCalibrator {
  /// Calibrate and compress receipt bytes asynchronously.
  ///
  /// Safe to call from UI threads: runs in a background isolate on mobile/desktop.
  static Future<CalibratedImageResult> calibrateReceiptBytes(
    Uint8List rawBytes, {
    int maxWidth = 1400,
    int maxHeight = 1600,
    int quality = 78,
    double contrast = 1.25,
    double brightness = 1.05,
  }) async {
    final params = CalibrationParams(
      rawBytes: rawBytes,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
      contrast: contrast,
      brightness: brightness,
    );

    // 2.0.148+209: on Web, decode/resize/contrast with the browser first
    // (HEIC on iOS Safari, EXIF orientation, no multi-second Dart decode on
    // the UI thread). Same size limits, brightness/contrast math and JPEG
    // quality as the Dart path; falls back to it if the browser path fails.
    if (kIsWeb) {
      final sw = Stopwatch()..start();
      final web = await resizeReceiptInBrowser(
        rawBytes,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        quality: quality,
        contrast: contrast,
        brightness: brightness,
      );
      if (web != null) {
        sw.stop();
        return CalibratedImageResult(
          bytes: web.bytes,
          originalSize: rawBytes.lengthInBytes,
          calibratedSize: web.bytes.lengthInBytes,
          width: web.width,
          height: web.height,
          duration: sw.elapsed,
        );
      }
      return calibrateReceiptBytesSync(params);
    }

    try {
      return await compute(calibrateReceiptBytesSync, params);
    } catch (e) {
      debugPrint('[ReceiptImageCalibrator] compute isolate failed, falling back to sync: $e');
      return calibrateReceiptBytesSync(params);
    }
  }

  /// Synchronous receipt calibration execution (used by isolates or Web).
  static CalibratedImageResult calibrateReceiptBytesSync(CalibrationParams params) {
    final stopwatch = Stopwatch()..start();
    final rawBytes = params.rawBytes;
    final originalSize = rawBytes.lengthInBytes;

    try {
      // 1. Decode raw image (JPEG, PNG, WebP, BMP, etc.)
      img.Image? decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        stopwatch.stop();
        return CalibratedImageResult(
          bytes: rawBytes,
          originalSize: originalSize,
          calibratedSize: originalSize,
          width: 0,
          height: 0,
          duration: stopwatch.elapsed,
          mimeType: sniffImageMimeType(rawBytes),
        );
      }

      // 2. Normalize EXIF orientation (handles phone camera tilts)
      decoded = img.bakeOrientation(decoded);

      // 3. Aspect-ratio preserved downscaling
      int targetW = decoded.width;
      int targetH = decoded.height;

      if (targetW > params.maxWidth || targetH > params.maxHeight) {
        final double widthRatio = params.maxWidth / targetW;
        final double heightRatio = params.maxHeight / targetH;
        final double scale = widthRatio < heightRatio ? widthRatio : heightRatio;

        targetW = (targetW * scale).round();
        targetH = (targetH * scale).round();

        decoded = img.copyResize(
          decoded,
          width: targetW,
          height: targetH,
          interpolation: img.Interpolation.linear,
        );
      }

      // 4. Contrast & brightness calibration for thermal receipt papers
      if (params.contrast != 1.0 || params.brightness != 1.0) {
        decoded = img.adjustColor(
          decoded,
          contrast: params.contrast,
          brightness: params.brightness,
        );
      }

      // 5. High-efficiency JPEG encoding
      final Uint8List calibratedBytes = Uint8List.fromList(
        img.encodeJpg(decoded, quality: params.quality),
      );

      stopwatch.stop();

      // In the rare event that calibrated output is larger than original, return the smaller one
      final bool isSmaller = calibratedBytes.lengthInBytes < originalSize;
      final effectiveBytes = isSmaller ? calibratedBytes : rawBytes;
      final effectiveSize = effectiveBytes.lengthInBytes;

      return CalibratedImageResult(
        bytes: effectiveBytes,
        originalSize: originalSize,
        calibratedSize: effectiveSize,
        width: decoded.width,
        height: decoded.height,
        duration: stopwatch.elapsed,
        mimeType: isSmaller ? 'image/jpeg' : sniffImageMimeType(rawBytes),
      );
    } catch (e) {
      stopwatch.stop();
      debugPrint('[ReceiptImageCalibrator] Exception during image calibration: $e');
      return CalibratedImageResult(
        bytes: rawBytes,
        originalSize: originalSize,
        calibratedSize: originalSize,
        width: 0,
        height: 0,
        duration: stopwatch.elapsed,
        mimeType: sniffImageMimeType(rawBytes),
      );
    }
  }

  /// Helper to calibrate an [XFile] picked from camera or gallery.
  static Future<CalibratedImageResult> calibrateXFile(
    XFile file, {
    int maxWidth = 1400,
    int maxHeight = 1600,
    int quality = 78,
    double contrast = 1.25,
    double brightness = 1.05,
  }) async {
    final rawBytes = await file.readAsBytes();
    return calibrateReceiptBytes(
      rawBytes,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
      contrast: contrast,
      brightness: brightness,
    );
  }

  /// Batch calibrate multiple receipt parts concurrently.
  static Future<List<CalibratedImageResult>> calibrateBatch(
    List<Uint8List> byteList, {
    int maxWidth = 1400,
    int maxHeight = 1600,
    int quality = 78,
    double contrast = 1.25,
    double brightness = 1.05,
  }) async {
    return Future.wait(
      byteList.map(
        (b) => calibrateReceiptBytes(
          b,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          quality: quality,
          contrast: contrast,
          brightness: brightness,
        ),
      ),
    );
  }
}
